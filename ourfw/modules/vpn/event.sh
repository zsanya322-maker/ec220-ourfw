#!/bin/sh
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
[ "$1" = "wan" ] || exit 0
act="${2:-}"
case "$act" in
  up) sleep 2; /etc/storage/ourfw/modules/vpn/apply.sh ;;
  down)
    CFG="$OURFW/config/vpn.conf"; VPN_INTERFACE=wg0
    [ -f "$CFG" ] && load_conf "$CFG" >/dev/null 2>&1 || true
    iface_exists "$VPN_INTERFACE" && ip link del dev "$VPN_INTERFACE" >/dev/null 2>&1 || true
    rm -f "$STATE/vpn-endpoint4" "$STATE/vpn-dns" "$STATE/vpn-type"
    ;;
esac
exit 0
