#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SRC="$ROOT/ourfw"
INT="$ROOT/integration/padavan-user-ourfw/files"
OUT=${1:-"$INT/defaults.tar.bz2"}
STAGE=${TMPDIR:-/tmp}/ourfw-defaults-stage-$$
trap 'rm -rf "$STAGE"' EXIT INT TERM

mkdir -p "$(dirname "$OUT")" "$INT/www" "$STAGE"
cp "$ROOT/bootstrap/ourfw-loader.sh" "$INT/ourfw-loader.sh"
chmod 755 "$INT/ourfw-loader.sh"
rm -rf "$INT/www"
cp -a "$SRC/www" "$INT/www"
# Canonical fallback WebUI modes even when source came through Windows ZIP/Git.
find "$INT/www" -type d -exec chmod 755 {} \;
find "$INT/www" -type f -exec chmod 644 {} \;

# Canonical staging copy makes defaults bit-reproducible across Windows/Linux
# checkouts where executable bits may differ. The immutable loader repeats the
# *.sh chmod when seeding /etc/storage as a final safety net.
cp -a "$SRC/." "$STAGE/"
rm -rf "$STAGE/generated"
find "$STAGE" -type d -exec chmod 755 {} \;
find "$STAGE" -type f -exec chmod 644 {} \;
find "$STAGE" -type f -name '*.sh' -exec chmod 755 {} \;

# Hardware A/B on EC220-G5 v2 confirmed that the old 15-second status poll
# causes visible CPU spikes and local 192.168.1.1 latency while OURFW is open.
# Production payload is event-driven instead: initial status, explicit Refresh,
# post-action refreshes, and one refresh when the browser tab becomes visible.
# There is deliberately no background/periodic poll on this single-core MT7620A.
for js in "$INT/www/assets/ourfw.js" "$STAGE/www/assets/ourfw.js"; do
    [ -f "$js" ] || { echo "OURFW WebUI JS missing: $js" >&2; exit 1; }
    grep -Fq 'status();setInterval(status,15000);' "$js" || {
        echo "OURFW WebUI poll signature changed unexpectedly: $js" >&2; exit 1;
    }
    sed -i "s/status();setInterval(status,15000);/status();document.addEventListener('visibilitychange',()=>{if(!document.hidden)status();});/" "$js"
    if grep -Fq 'setInterval(status' "$js"; then
        echo "periodic OURFW status polling survived payload generation: $js" >&2; exit 1;
    fi
    grep -Fq "document.addEventListener('visibilitychange'" "$js" || {
        echo "visibility refresh hook missing from OURFW payload: $js" >&2; exit 1;
    }
done

rm -f "$OUT"
LC_ALL=C TZ=UTC tar -C "$STAGE" \
  --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
  --exclude='./generated' --exclude='./generated/*' \
  -cf - . | bzip2 -9 > "$OUT"
echo "$OUT"
