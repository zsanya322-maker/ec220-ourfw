#!/bin/sh
# Dispatcher: Padavan-native dataplane for AmneziaWG, legacy OURFW for other VPNs.
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
CFG="$OURFW/config/vpn.conf"
VPN_ENABLED=0
VPN_TYPE=wireguard
load_conf "$CFG" || exit 1
NATIVE="$OURFW/modules/vpn/padavan-awg-client.sh"
LEGACY="$OURFW/modules/vpn/apply-other-vpn.sh"

if [ "$VPN_ENABLED" = 0 ]; then
    [ -x "$NATIVE" ] && "$NATIVE" stop >/dev/null 2>&1 || true
    if [ -x "$LEGACY" ]; then exec "$LEGACY"; fi
    rm -f "$STATE/vpn-type" "$STATE/vpn-interface"
    log "vpn: disabled"
    exit 0
fi

case "$VPN_TYPE" in
  amneziawg)
    [ -x "$NATIVE" ] || { log "vpn: Padavan-native AWG helper missing"; exit 1; }
    exec "$NATIVE" restart
    ;;
  wireguard|openvpn)
    [ -x "$NATIVE" ] && "$NATIVE" stop >/dev/null 2>&1 || true
    [ -x "$LEGACY" ] || { log "vpn: legacy non-AWG engine missing"; exit 1; }
    exec "$LEGACY"
    ;;
  *)
    log "vpn: unsupported VPN_TYPE=$VPN_TYPE"
    exit 1
    ;;
esac
