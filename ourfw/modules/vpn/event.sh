#!/bin/sh
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
[ "${1:-}" = wan ] || exit 0
act="${2:-}"
case "$act" in
  up)
    sleep 2
    "$OURFW/modules/vpn/apply.sh"
    ;;
  down)
    # WAN teardown must stop whichever runtime tunnel is active, including
    # OpenVPN. Do not rewrite persistent VPN config.
    pf="$STATE/openvpn.pid"
    if [ -f "$pf" ]; then p="$(cat "$pf" 2>/dev/null || true)"; is_uint "$p" && kill "$p" 2>/dev/null || true; fi
    iface="$(active_vpn_if)"
    iface_exists "$iface" && ip link del dev "$iface" >/dev/null 2>&1 || true
    iface_exists wg0 && ip link del dev wg0 >/dev/null 2>&1 || true
    iface_exists tun0 && ip link del dev tun0 >/dev/null 2>&1 || true
    rm -f "$pf" "$STATE/vpn-endpoint4" "$STATE/vpn-endpoint6" "$STATE/vpn-dns" "$STATE/vpn-type" "$STATE/vpn-interface"
    ;;
esac
exit 0
