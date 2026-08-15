#!/bin/sh
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
CFG="$OURFW/config/adblock.conf"
ADBLOCK_ENABLED=0; ADBLOCK_SOURCES_FILE="$OURFW/rules/adblock-sources.list"; ADBLOCK_ALLOW_FILE="$OURFW/rules/adblock-allow.list"; ADBLOCK_DENY_FILE="$OURFW/rules/adblock-deny.list"
ADBLOCK_MAX_DOMAINS=15000; ADBLOCK_REFRESH_HOURS=24; ADBLOCK_QUERY_LOG=0
load_conf "$CFG" || exit 1
[ "$ADBLOCK_ENABLED" = 1 ] || exit 0
LOCK="$STATE/adblock.lock"; mkdir "$LOCK" 2>/dev/null || { log "adblock: update already running"; exit 0; }; trap 'rm -rf "$LOCK"' EXIT HUP INT TERM
need curl || { log "adblock: curl missing"; exit 1; }
TMP="$STATE/adblock-work.$$"; RAW="$TMP.raw"; ALL="$TMP.all"; SORTED="$TMP.sorted"; ALLOW="$TMP.allow"; FINAL="$TMP.final"; RUNTIME="$STATE/adblock-dnsmasq.conf"
rm -f "$RAW" "$ALL" "$SORTED" "$ALLOW" "$FINAL"; : > "$ALL"; errors=0; sources=0
normalize() {
    awk 'BEGIN{IGNORECASE=1}
      {gsub(/\r/,""); sub(/[[:space:]]*[#;].*$/,""); if($0 ~ /^[[:space:]]*$/) next;
       if($1=="0.0.0.0" || $1=="127.0.0.1" || $1=="::" || $1=="::1") d=$2; else d=$1;
       d=tolower(d); sub(/^\*\./,"",d); sub(/^\|\|/,"",d); sub(/\^.*$/, "", d);
       if(d ~ /^[a-z0-9][a-z0-9._-]*\.[a-z0-9][a-z0-9.-]*$/ && d !~ /\.\./) print d; }' "$1"
}
strip_list "$ADBLOCK_SOURCES_FILE" | while IFS= read -r url; do
    case "$url" in https://*) ;; *) log "adblock: only HTTPS source URLs are allowed"; continue;; esac
    # Keep the router safe from accidentally huge subscriptions.
    if curl -fsSL --connect-timeout 10 --max-time 45 --max-filesize 2097152 "$url" -o "$RAW" >/dev/null 2>&1; then
        normalize "$RAW" >> "$ALL"; sources=$((sources+1))
    else
        errors=$((errors+1)); log "adblock: source failed: $url"
    fi
done
# Pipeline loops in BusyBox ash may run in a subshell; recompute source count from
# the configured list and derive errors only as advisory.
sources="$(strip_list "$ADBLOCK_SOURCES_FILE" | grep -Ec '^https://' 2>/dev/null || echo 0)"
[ -f "$ADBLOCK_DENY_FILE" ] && normalize "$ADBLOCK_DENY_FILE" >> "$ALL"
sort -u "$ALL" > "$SORTED" 2>/dev/null || cp "$ALL" "$SORTED"
[ -f "$ADBLOCK_ALLOW_FILE" ] && normalize "$ADBLOCK_ALLOW_FILE" | sort -u > "$ALLOW" || : > "$ALLOW"
awk 'NR==FNR{a[$0]=1;next} !a[$0]' "$ALLOW" "$SORTED" | head -n "$ADBLOCK_MAX_DOMAINS" > "$FINAL"
count="$(wc -l < "$FINAL" | tr -d ' ')"; is_uint "$count" || count=0
OUT="$RUNTIME.tmp.$$"
{
    echo '# OURFW AdBlock Lite - generated in RAM'
    awk '{print "address=/"$0"/0.0.0.0"; print "address=/"$0"/::"}' "$FINAL"
    [ "$ADBLOCK_QUERY_LOG" = 1 ] && echo 'log-queries'
} > "$OUT" || exit 1
mv "$OUT" "$RUNTIME"
now="$(date +%s 2>/dev/null || echo 0)"; bytes="$(wc -c < "$RUNTIME" | tr -d ' ')"
printf 'DOMAINS=%s\nBYTES=%s\nUPDATED=%s\nSOURCES=%s\n' "$count" "$bytes" "$now" "$sources" > "$STATE/adblock.status"
rm -f "$RAW" "$ALL" "$SORTED" "$ALLOW" "$FINAL"
# Refresh the safe persistent bind target without ever writing the large file to flash.
TARGET="$OURFW/adblock-runtime.conf"; [ -f "$TARGET" ] || : > "$TARGET"; umount "$TARGET" >/dev/null 2>&1 || true
mount -o bind "$RUNTIME" "$TARGET" >/dev/null 2>&1 || { log "adblock: bind mount failed after update"; exit 1; }
log "adblock: loaded $count domains ($bytes bytes runtime config)"
if [ "${1:-}" != --no-dns-restart ]; then "$OURFW/modules/dns/apply.sh" >/dev/null 2>&1 || exit 1; fi
exit 0
