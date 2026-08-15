#!/bin/sh
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
OP=${1:-}
case "$OP" in
  enable) value=1 ;;
  disable) value=0 ;;
  *) printf '{"ok":false,"error":"unsupported operation"}\n'; exit 2 ;;
esac
candidate_conf_set "/etc/storage/ourfw/config/nfqws.conf" "NFQWS_ENABLED" "$value" "web-nfqws" >/tmp/ourfw-api-module.log 2>&1
rc=$?
printf '{"ok":%s,"module":"nfqws","operation":"%s","pending":%s,"rc":%d}\n' "$([ $rc -eq 0 ] && echo true || echo false)" "$OP" "$([ $rc -eq 0 ] && echo true || echo false)" "$rc"
exit $rc
