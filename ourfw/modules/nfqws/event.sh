#!/bin/sh
[ -x /usr/bin/zapret.sh ] || exit 0
case "${1:-}" in
 firewall) /usr/bin/zapret.sh firewall-start >/dev/null 2>&1 || true ;;
 wan) [ "${2:-}" = "up" ] && /etc/storage/ourfw/modules/nfqws/apply.sh || true ;;
esac
exit 0
