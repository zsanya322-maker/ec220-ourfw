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

rm -f "$OUT"
LC_ALL=C TZ=UTC tar -C "$STAGE" \
  --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
  --exclude='./generated' --exclude='./generated/*' \
  -cf - . | bzip2 -9 > "$OUT"
echo "$OUT"
