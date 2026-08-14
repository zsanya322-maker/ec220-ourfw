#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SRC="$ROOT/ourfw"
INT="$ROOT/integration/padavan-user-ourfw/files"
OUT=${1:-"$INT/defaults.tar.bz2"}

mkdir -p "$(dirname "$OUT")" "$INT/www"
# Keep immutable rescue loader and WebUI fallback synchronized with the same
# sources that are shipped in the mutable defaults archive.
cp "$ROOT/bootstrap/ourfw-loader.sh" "$INT/ourfw-loader.sh"
chmod 755 "$INT/ourfw-loader.sh"
rm -rf "$INT/www"
cp -a "$SRC/www" "$INT/www"

rm -f "$OUT"
# Store OURFW contents, not the outer directory, so loader can extract to
# /etc/storage/ourfw. Padavan storage uses bzip2 too, so this is also a useful
# approximation of mutable-storage cost.
( cd "$SRC" && tar -cf - . ) | bzip2 -9 > "$OUT"
echo "$OUT"
