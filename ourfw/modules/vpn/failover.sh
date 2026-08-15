#!/bin/sh
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
VPN_ENABLED=0; VPN_TYPE=wireguard; VPN_FAILOVER_ENABLED=0; VPN_FAILOVER_TYPE=openvpn
load_conf "$OURFW/config/vpn.conf" || exit 1
[ "$VPN_ENABLED" = 1 ] && [ "$VPN_FAILOVER_ENABLED" = 1 ] || exit 1
cur="$(active_vpn_type)"
if [ "$cur" = "$VPN_TYPE" ]; then next="$VPN_FAILOVER_TYPE"; else next="$VPN_TYPE"; fi
[ "$next" != "$cur" ] || exit 1
printf '%s\n' "$next" > "$STATE/vpn-override-type"
log "vpn: failover $cur -> $next"
if "$OURFW/modules/vpn/apply.sh" && "$OURFW/modules/smart-routing/apply.sh" && "$OURFW/modules/dns/apply.sh"; then exit 0; fi
log "vpn: failover to $next failed; returning to primary $VPN_TYPE"
rm -f "$STATE/vpn-override-type"
"$OURFW/modules/vpn/apply.sh" >/dev/null 2>&1 || true
"$OURFW/modules/smart-routing/apply.sh" >/dev/null 2>&1 || true
"$OURFW/modules/dns/apply.sh" >/dev/null 2>&1 || true
exit 1
