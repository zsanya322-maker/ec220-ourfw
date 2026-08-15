#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LIMIT=${OURFW_STORAGE_LIMIT:-131072}
TMP=${TMPDIR:-/tmp}/ourfw-budget-$$.tbz
trap 'rm -f "$TMP"' EXIT INT TERM
# Use the exact build generator so Windows/Linux mode differences cannot make
# the budget disagree with the firmware payload.
sh "$ROOT/build/make-defaults.sh" "$TMP" >/dev/null
SIZE=$(wc -c < "$TMP" | tr -d ' ')
LEFT=$((LIMIT-SIZE))
PCT=$((SIZE*100/LIMIT))
printf 'OURFW source: %s\nCompressed tar.bz2: %s bytes\nStorage budget: %s bytes\nUsed: %s%%\nRemaining: %s bytes\n' "$ROOT/ourfw" "$SIZE" "$LIMIT" "$PCT" "$LEFT"
[ "$SIZE" -le "$LIMIT" ] || exit 2
