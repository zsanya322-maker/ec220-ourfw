#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SRC=${1:-"$ROOT/ourfw"}
LIMIT=${OURFW_STORAGE_LIMIT:-131072}
TMP=${TMPDIR:-/tmp}/ourfw-budget-$$.tbz
trap 'rm -f "$TMP"' EXIT INT TERM
( cd "$SRC" && tar -cf - . ) | bzip2 -9 > "$TMP"
SIZE=$(wc -c < "$TMP" | tr -d ' ')
LEFT=$((LIMIT-SIZE))
PCT=$((SIZE*100/LIMIT))
printf 'OURFW source: %s\nCompressed tar.bz2: %s bytes\nStorage budget: %s bytes\nUsed: %s%%\nRemaining: %s bytes\n' "$SRC" "$SIZE" "$LIMIT" "$PCT" "$LEFT"
[ "$SIZE" -le "$LIMIT" ] || exit 2
