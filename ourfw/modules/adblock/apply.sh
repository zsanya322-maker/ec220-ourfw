#!/bin/sh
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
CFG="$OURFW/config/adblock.conf"
ADBLOCK_ENABLED=0; ADBLOCK_SOURCES_FILE="$OURFW/rules/adblock-sources.list"; ADBLOCK_ALLOW_FILE="$OURFW/rules/adblock-allow.list"; ADBLOCK_DENY_FILE="$OURFW/rules/adblock-deny.list"
ADBLOCK_MAX_DOMAINS=15000; ADBLOCK_REFRESH_HOURS=24; ADBLOCK_QUERY_LOG=0
load_conf "$CFG" || exit 1
bool01 "$ADBLOCK_ENABLED" || exit 1; bool01 "$ADBLOCK_QUERY_LOG" || exit 1; is_uint "$ADBLOCK_MAX_DOMAINS" || exit 1; is_uint "$ADBLOCK_REFRESH_HOURS" || exit 1
[ "$ADBLOCK_MAX_DOMAINS" -ge 100 ] && [ "$ADBLOCK_MAX_DOMAINS" -le 50000 ] || exit 1
TARGET="$OURFW/adblock-runtime.conf"; RUNTIME="$STATE/adblock-dnsmasq.conf"
mkdir -p "$STATE"; [ -f "$TARGET" ] || : > "$TARGET"
if [ "$ADBLOCK_ENABLED" = 0 ]; then
    umount "$TARGET" >/dev/null 2>&1 || true
    : > "$TARGET"; rm -f "$RUNTIME" "$STATE/adblock.status"
    log "adblock: disabled"; exit 0
fi
# Reuse current runtime list if available. Otherwise build it now; download
# failures are non-fatal and fall back to the local denylist.
if [ ! -s "$RUNTIME" ]; then "$OURFW/modules/adblock/update.sh" --no-dns-restart || true; fi
[ -f "$RUNTIME" ] || : > "$RUNTIME"
umount "$TARGET" >/dev/null 2>&1 || true
mount -o bind "$RUNTIME" "$TARGET" >/dev/null 2>&1 || { log "adblock: bind mount failed"; exit 1; }
log "adblock: runtime list active"
exit 0
