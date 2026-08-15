#!/bin/sh
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
op="${1:-status}"; rc=0
case "$op" in
  off|auto|25|50) candidate_conf_set "$OURFW/config/zram.conf" ZRAM_MODE "$op" web-zram >/tmp/ourfw-api-module.log 2>&1; rc=$? ;;
  status) ;;
  *) printf '{"ok":false,"error":"unsupported operation"}\n'; exit 2;;
esac
active=false; grep -q '^/dev/zram0[[:space:]]' /proc/swaps 2>/dev/null && active=true
bytes="$(awk -F= '$1=="BYTES"{print $2}' "$STATE/zram.status" 2>/dev/null | tail -n1)"; is_uint "${bytes:-}" || bytes=0
algo="$(awk -F= '$1=="ALGO"{print $2}' "$STATE/zram.status" 2>/dev/null | tail -n1)"; safe_id "${algo:-none}" || algo=none
printf '{"ok":%s,"module":"zram","operation":"%s","active":%s,"bytes":%s,"algo":"%s","pending":%s,"rc":%d}\n' \
  "$([ $rc -eq 0 ] && echo true || echo false)" "$op" "$active" "$bytes" "$algo" \
  "$([ "$op" != status ] && [ $rc -eq 0 ] && echo true || echo false)" "$rc"
exit $rc
