#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PARTITION_LIMIT=${OURFW_STORAGE_PARTITION_LIMIT:-131072}
# OURFW must never plan to consume the whole Padavan Storage partition: stock
# scripts, HTTPS material and user settings share the same compressed MTD blob.
OURFW_LIMIT=${OURFW_STORAGE_LIMIT:-65536}
TMP=${TMPDIR:-/tmp}/ourfw-budget-$$.tbz
trap 'rm -f "$TMP"' EXIT INT TERM
[ "$OURFW_LIMIT" -le "$PARTITION_LIMIT" ] || { echo 'OURFW storage limit exceeds partition' >&2; exit 3; }
sh "$ROOT/build/make-defaults.sh" "$TMP" >/dev/null
SIZE=$(wc -c < "$TMP" | tr -d ' ')
LEFT=$((OURFW_LIMIT-SIZE))
RESERVED=$((PARTITION_LIMIT-OURFW_LIMIT))
PCT=$((SIZE*100/OURFW_LIMIT))
printf 'OURFW source: %s\nCompressed tar.bz2: %s bytes\nOURFW own cap: %s bytes\nReserved for Padavan/user storage: %s bytes\nUsed of OURFW cap: %s%%\nRemaining OURFW headroom: %s bytes\n' "$ROOT/ourfw" "$SIZE" "$OURFW_LIMIT" "$RESERVED" "$PCT" "$LEFT"
[ "$SIZE" -le "$OURFW_LIMIT" ] || exit 2
