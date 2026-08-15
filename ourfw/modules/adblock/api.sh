#!/bin/sh
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
op="${1:-status}"; rc=0
case "$op" in
  enable) candidate_conf_set "$OURFW/config/adblock.conf" ADBLOCK_ENABLED 1 web-adblock >/tmp/ourfw-api-module.log 2>&1; rc=$? ;;
  disable) candidate_conf_set "$OURFW/config/adblock.conf" ADBLOCK_ENABLED 0 web-adblock >/tmp/ourfw-api-module.log 2>&1; rc=$? ;;
  update) "$OURFW/modules/adblock/update.sh" >/tmp/ourfw-adblock-update.log 2>&1; rc=$? ;;
  status) ;;
  *) printf '{"ok":false,"error":"unsupported operation"}\n'; exit 2;;
esac
count="$(awk -F= '$1=="DOMAINS"{print $2}' "$STATE/adblock.status" 2>/dev/null | tail -n1)"; is_uint "${count:-}" || count=0
bytes="$(awk -F= '$1=="BYTES"{print $2}' "$STATE/adblock.status" 2>/dev/null | tail -n1)"; is_uint "${bytes:-}" || bytes=0
updated="$(awk -F= '$1=="UPDATED"{print $2}' "$STATE/adblock.status" 2>/dev/null | tail -n1)"; is_uint "${updated:-}" || updated=0
sources="$(awk -F= '$1=="SOURCES"{print $2}' "$STATE/adblock.status" 2>/dev/null | tail -n1)"; is_uint "${sources:-}" || sources=0
printf '{"ok":%s,"module":"adblock","operation":"%s","domains":%s,"bytes":%s,"updated":%s,"sources":%s,"pending":%s,"rc":%d}\n' \
  "$([ $rc -eq 0 ] && echo true || echo false)" "$op" "$count" "$bytes" "$updated" "$sources" \
  "$([ "$op" = enable ] || [ "$op" = disable ] && [ $rc -eq 0 ] && echo true || echo false)" "$rc"
exit $rc
