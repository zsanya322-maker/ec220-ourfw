#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASE=/etc/storage/ourfw
T=$(mktemp -d)
if [[ -e "$BASE" || -L "$BASE" ]]; then
  echo "V0.6.2 ROLLBACK REAPPLY: SKIP ($BASE exists)"
  exit 0
fi
mkdir -p /etc/storage "$T/ourfw/runtime" "$T/ourfw/config" "$T/ourfw/profiles" "$T/ourfw/rules" "$T/old/config" "$T/old/profiles" "$T/old/rules"
ln -s "$T/ourfw" "$BASE"
cleanup(){ rm -f "$BASE"; rm -rf /tmp/ourfw "$T"; }
trap cleanup EXIT INT TERM
cp "$ROOT/ourfw/runtime/ourfw-common.sh" "$T/ourfw/runtime/"
cp "$ROOT/ourfw/runtime/ourfw-rollback.sh" "$T/ourfw/runtime/"
chmod 755 "$T/ourfw/runtime/"*.sh
cat > "$T/ourfw/config/global.conf" <<'CFG'
OURFW_ENABLED=1
ROLLBACK_TIMEOUT=90
HISTORY_KEEP=2
LOG_LEVEL=1
CFG
printf 'candidate\n' > "$T/ourfw/config/value.conf"
printf 'profile-candidate\n' > "$T/ourfw/profiles/value.conf"
printf 'rule-candidate\n' > "$T/ourfw/rules/value.list"
printf 'old-good\n' > "$T/old/config/value.conf"
cp "$T/ourfw/config/global.conf" "$T/old/config/global.conf"
printf 'profile-good\n' > "$T/old/profiles/value.conf"
printf 'rule-good\n' > "$T/old/rules/value.list"

for m in zram vpn smart-routing adblock dns nfqws watchdog diagnostics; do
  mkdir -p "$T/ourfw/modules/$m"
  cat > "$T/ourfw/modules/$m/apply.sh" <<SH
#!/bin/sh
printf '%s\\n' '$m' >> "\${REAPPLY_LOG:?}"
if [ '$m' = smart-routing ] && [ "\${FAIL_REAPPLY:-0}" = 1 ]; then exit 7; fi
exit 0
SH
  chmod 755 "$T/ourfw/modules/$m/apply.sh"
done

rm -rf /tmp/ourfw; mkdir -p /tmp/ourfw
( cd "$T/old" && tar -cf /tmp/ourfw/last-good.tar config profiles rules )
printf 'web-test\n' > /tmp/ourfw/pending
: > "$T/reapply.log"

set +e
OURFW_LOCK_HELD=1 FAIL_REAPPLY=1 REAPPLY_LOG="$T/reapply.log" sh "$BASE/runtime/ourfw-rollback.sh" now >/dev/null 2>&1
rc=$?
set -e
[[ $rc -ne 0 ]]
grep -qx 'old-good' "$T/ourfw/config/value.conf"
[[ -f /tmp/ourfw/pending ]]
grep -q '^smart-routing$' "$T/reapply.log"

: > "$T/reapply.log"
OURFW_LOCK_HELD=1 FAIL_REAPPLY=0 REAPPLY_LOG="$T/reapply.log" sh "$BASE/runtime/ourfw-rollback.sh" now >/dev/null
[[ ! -f /tmp/ourfw/pending ]]
grep -qx 'old-good' "$T/ourfw/config/value.conf"
[[ $(wc -l < "$T/reapply.log") -eq 8 ]]

echo 'V0.6.2 ROLLBACK REAPPLY: OK'
