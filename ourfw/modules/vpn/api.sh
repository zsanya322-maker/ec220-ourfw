#!/bin/sh
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
OP=${1:-}
case "$OP" in
  enable) value=1 ;;
  disable) value=0 ;;
  *) printf '{"ok":false,"error":"unsupported operation"}\n'; exit 2 ;;
esac
conf_set "/etc/storage/ourfw/config/vpn.conf" "VPN_ENABLED" "$value" || { printf '{"ok":false,"error":"config update failed"}\n'; exit 3; }
/etc/storage/ourfw/runtime/ourfwctl.sh apply web-vpn >/tmp/ourfw-api-module.log 2>&1
rc=$?
printf '{"ok":%s,"module":"vpn","operation":"%s","pending":%s,"rc":%d}\n' "$([ $rc -eq 0 ] && echo true || echo false)" "$OP" "$([ $rc -eq 0 ] && echo true || echo false)" "$rc"
exit $rc
