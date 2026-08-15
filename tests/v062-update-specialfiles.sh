#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASE=/etc/storage/ourfw
T=$(mktemp -d)
if [[ -e "$BASE" || -L "$BASE" ]]; then
  echo "V0.6.2 UPDATE SPECIAL FILES: SKIP ($BASE exists)"
  exit 0
fi
mkdir -p /etc/storage "$T/pkg/payload"
cp -a "$ROOT/ourfw" "$T/ourfw"
find "$T/ourfw" -type f -name '*.sh' -exec chmod 755 {} \;
ln -s "$T/ourfw" "$BASE"
cleanup(){ rm -f "$BASE" /tmp/ourfw-v062-special.tar.bz2; rm -rf /tmp/ourfw "$T"; }
trap cleanup EXIT INT TERM
cat > "$T/pkg/manifest.conf" <<'CFG'
module=diagnostics
version=0.6.2-test
type=module
CFG
mkfifo "$T/pkg/payload/evil-fifo"
( cd "$T/pkg" && tar -cjf /tmp/ourfw-v062-special.tar.bz2 manifest.conf payload )
sha=$(sha256sum /tmp/ourfw-v062-special.tar.bz2 | awk '{print $1}')
rm -rf /tmp/ourfw; mkdir -p /tmp/ourfw
set +e
"$BASE/runtime/ourfw-update.sh" install /tmp/ourfw-v062-special.tar.bz2 "$sha" >/dev/null 2>&1
rc=$?
set -e
[[ $rc -ne 0 ]]
[[ ! -p "$BASE/modules/diagnostics/evil-fifo" ]]
[[ ! -f /tmp/ourfw/update-pending ]]
echo 'V0.6.2 UPDATE SPECIAL FILES: OK'
