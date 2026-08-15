#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SRC="$ROOT/ourfw"
INT="$ROOT/integration/padavan-user-ourfw/files"
OUT=${1:-"$INT/defaults.tar.bz2"}

mkdir -p "$(dirname "$OUT")" "$INT/www"
cp "$ROOT/bootstrap/ourfw-loader.sh" "$INT/ourfw-loader.sh"
chmod 755 "$INT/ourfw-loader.sh"
rm -rf "$INT/www"
cp -a "$SRC/www" "$INT/www"

rm -f "$OUT"
# Reproducible mutable defaults: canonical order/ownership/mtime. Runtime-generated
# state is never shipped in the persistent 128 KiB Storage payload.
LC_ALL=C TZ=UTC tar -C "$SRC" \
  --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
  --exclude='./generated' --exclude='./generated/*' \
  -cf - . | bzip2 -9 > "$OUT"
echo "$OUT"
