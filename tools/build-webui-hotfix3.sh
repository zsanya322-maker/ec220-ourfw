#!/bin/sh
set -eu

OUT=${1:-dist-hotfix}
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
STAGE="$OUT/.stage-webui-hwfix3"
PKG="$OUT/OURFW-v0.6.x-HOTFIX3-WebUI-polling.tar.bz2"

rm -rf "$STAGE"
mkdir -p "$STAGE/payload/assets" "$OUT"

cat > "$STAGE/manifest.conf" <<'EOF'
module=webui
version=v0.6.4-hwfix3
type=webui
EOF

# Partial overlay for the existing transactional updater. It is applied over
# the installed complete WebUI, remounted, and rolled back unless confirmed.
cp "$ROOT/ourfw/www/assets/ourfw.js" "$STAGE/payload/assets/ourfw.js"

# Physical EC220 regression gate: do not reintroduce background status polling.
if grep -Eq 'setInterval[[:space:]]*\([^\n]*(status|action[^\n]*status)' "$STAGE/payload/assets/ourfw.js"; then
    echo 'refusing to package: periodic OURFW status polling detected' >&2
    exit 20
fi

tar -cjf "$PKG" -C "$STAGE" manifest.conf payload
sha256sum "$PKG" > "$PKG.sha256"
rm -rf "$STAGE"
printf 'HOTFIX_PACKAGE=%s\n' "$PKG"
printf 'HOTFIX_BYTES=%s\n' "$(stat -c %s "$PKG")"
printf 'HOTFIX_SHA256=%s\n' "$(sha256sum "$PKG" | awk '{print $1}')"
