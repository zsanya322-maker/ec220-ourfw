#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TESTROOT=${TMPDIR:-/tmp}/ourfw-v05-runtime-mock-$$
ETC=/etc/storage/ourfw
if [[ -e "$ETC" || -L "$ETC" ]]; then
  echo "RUNTIME MOCK: SKIP ($ETC already exists)"
  exit 0
fi
mkdir -p /etc/storage "$TESTROOT"
cp -a "$ROOT/ourfw" "$TESTROOT/ourfw"
ln -s "$TESTROOT/ourfw" "$ETC"
# Windows/ZIP checkouts may not preserve executable bits; the real immutable loader
# normalizes every mutable .sh on first seed, so the runtime mock does the same.
find "$TESTROOT/ourfw" -type f -name '*.sh' -exec chmod 755 {} \;
cleanup(){
  if [[ -f /tmp/ourfw/update-guard.pid ]]; then kill "$(cat /tmp/ourfw/update-guard.pid)" 2>/dev/null || true; fi
  if [[ -f /tmp/ourfw/rollback-guard.pid ]]; then kill "$(cat /tmp/ourfw/rollback-guard.pid)" 2>/dev/null || true; fi
  rm -f "$ETC" /tmp/ourfw-v05-module.tar.bz2 /tmp/ourfw-v05-routing.conf
  rm -rf /tmp/ourfw "$TESTROOT"
}
trap cleanup EXIT INT TERM

# base64url transfer -> validated section staging
json=$($ETC/runtime/ourfw-transfer.sh get routing-config)
printf '%s' "$json" | python3 -c 'import json,sys; j=json.load(sys.stdin); assert j["ok"] and j["bytes"]>0'
cp "$ETC/config/routing.conf" /tmp/ourfw-v05-routing.conf
sed -i 's/^IPV6_POLICY=.*/IPV6_POLICY=native/' /tmp/ourfw-v05-routing.conf
sha=$(sha256sum /tmp/ourfw-v05-routing.conf | awk '{print $1}')
enc=$(base64 -w0 /tmp/ourfw-v05-routing.conf | tr '/+' '_-' | tr -d '=')
$ETC/runtime/ourfw-transfer.sh begin routing-config "$sha" >/dev/null
while [[ -n "$enc" ]]; do c=${enc:0:900}; enc=${enc:900}; $ETC/runtime/ourfw-transfer.sh chunk routing-config "$c" >/dev/null; done
$ETC/runtime/ourfw-transfer.sh stage routing-config >/dev/null
cmp /tmp/ourfw-v05-routing.conf /tmp/ourfw/webedit/routing-config
$ETC/runtime/ourfw-transfer.sh section-abort routing >/dev/null

# backup archive validation
b=$($ETC/runtime/ourfw-backup.sh export | tail -n1)
$ETC/runtime/ourfw-backup.sh verify "$b"
rm -f "$b"

# Safe module overlay -> pending -> rollback, using diagnostics to avoid network changes.
mkdir -p "$TESTROOT/pkg/payload"
cat > "$TESTROOT/pkg/manifest.conf" <<'EOF'
module=diagnostics
version=0.5-test
type=module
EOF
printf 'candidate\n' > "$TESTROOT/pkg/payload/test-marker.txt"
( cd "$TESTROOT/pkg" && tar -cjf /tmp/ourfw-v05-module.tar.bz2 manifest.conf payload )
sha=$(sha256sum /tmp/ourfw-v05-module.tar.bz2 | awk '{print $1}')
$ETC/runtime/ourfw-update.sh install /tmp/ourfw-v05-module.tar.bz2 "$sha" >/dev/null
[[ -f "$ETC/modules/diagnostics/test-marker.txt" && -f /tmp/ourfw/update-pending ]]
$ETC/runtime/ourfw-update.sh rollback >/dev/null
[[ ! -f "$ETC/modules/diagnostics/test-marker.txt" && ! -f /tmp/ourfw/update-pending ]]
! find /tmp/ourfw/update-history -mindepth 1 -print -quit 2>/dev/null | grep -q .

# Rescue flag blocks mutable API actions.
touch /etc/storage/ourfw.disabled
set +e
$ETC/runtime/ourfw-api.sh file-get routing-config >/dev/null 2>&1
rc=$?
set -e
rm -f /etc/storage/ourfw.disabled
[[ $rc -eq 4 ]]

echo 'RUNTIME MOCK: OK'
