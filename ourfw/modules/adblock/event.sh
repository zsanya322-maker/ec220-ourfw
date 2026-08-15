#!/bin/sh
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
[ "${1:-}" = wan ] || exit 0
ADBLOCK_ENABLED=0; ADBLOCK_REFRESH_HOURS=24
load_conf "$OURFW/config/adblock.conf" >/dev/null 2>&1 || exit 0
[ "$ADBLOCK_ENABLED" = 1 ] || exit 0
(
  sleep 5
  now="$(date +%s 2>/dev/null || echo 0)"; old="$(awk -F= '$1=="UPDATED"{print $2}' "$STATE/adblock.status" 2>/dev/null | tail -n1)"
  is_uint "$old" || old=0; age=$((now-old)); limit=$((ADBLOCK_REFRESH_HOURS*3600))
  [ "$age" -lt "$limit" ] 2>/dev/null || "$OURFW/modules/adblock/update.sh" >/dev/null 2>&1 || true
) >/dev/null 2>&1 &
exit 0
