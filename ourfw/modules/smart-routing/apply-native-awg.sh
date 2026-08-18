#!/bin/sh
# OURFW Smart Routing policy layer over Padavan-native AmneziaWG transport.
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1

CFG="$OURFW/config/routing.conf"
ROUTING_MODE=smart
VPN_INTERFACE=wg0
FWMARK=0x100
FWMASK=0x100
RULE_PREF=10000
KILLSWITCH=1
IPV6_POLICY=block
VPN_IPSET=ourfw_vpn4
DIRECT_IPSET=ourfw_direct4
load_conf "$CFG" || exit 1

VPN_ENABLED=0
VPN_TYPE=amneziawg
[ -f "$OURFW/config/vpn.conf" ] && load_conf "$OURFW/config/vpn.conf" || exit 1

VPN_INTERFACE="$(active_vpn_if)"
[ -n "$VPN_INTERFACE" ] || VPN_INTERFACE=wg0
TRANSPORT_TABLE="$(cat "$STATE/awg-transport-table" 2>/dev/null || echo 51820)"
TRANSPORT_MARK="$(cat "$STATE/awg-transport-mark" 2>/dev/null || echo 51820)"
NATIVE="$OURFW/modules/vpn/padavan-awg-client.sh"

case "$ROUTING_MODE" in off|smart|vpn-all) ;; *) log "routing-native: invalid mode"; exit 1;; esac
is_uint "$RULE_PREF" || exit 1
bool01 "$KILLSWITCH" || exit 1
bool01 "$VPN_ENABLED" || exit 1
case "$IPV6_POLICY" in block|native) ;; *) exit 1;; esac
need iptables || exit 1
need ipset || exit 1
need ip || exit 1

ipt_del_jump() { while iptables "$@" >/dev/null 2>&1; do :; done; }
ip6_del_jump() { while ip6tables "$@" >/dev/null 2>&1; do :; done; }

clean_policy() {
    ipt_del_jump -t mangle -D PREROUTING -j OURFW_ROUTE
    ipt_del_jump -t mangle -D OUTPUT -j OURFW_ROUTE
    ipt_del_jump -t filter -D FORWARD -j OURFW_KILL
    ipt_del_jump -t filter -D OUTPUT -j OURFW_KILL
    iptables -t mangle -F OURFW_ROUTE >/dev/null 2>&1 || true
    iptables -t mangle -X OURFW_ROUTE >/dev/null 2>&1 || true
    iptables -t filter -F OURFW_KILL >/dev/null 2>&1 || true
    iptables -t filter -X OURFW_KILL >/dev/null 2>&1 || true

    ipt_del_jump -t nat -D POSTROUTING -j OURFW_VPN_NAT
    iptables -t nat -F OURFW_VPN_NAT >/dev/null 2>&1 || true
    iptables -t nat -X OURFW_VPN_NAT >/dev/null 2>&1 || true

    if have_exec ip6tables; then
        ip6_del_jump -t filter -D FORWARD -j OURFW6_FWD
        ip6_del_jump -t filter -D OUTPUT -j OURFW6_OUT
        ip6tables -t filter -F OURFW6_FWD >/dev/null 2>&1 || true
        ip6tables -t filter -X OURFW6_FWD >/dev/null 2>&1 || true
        ip6tables -t filter -F OURFW6_OUT >/dev/null 2>&1 || true
        ip6tables -t filter -X OURFW6_OUT >/dev/null 2>&1 || true
    fi

    while ip rule del pref "$RULE_PREF" >/dev/null 2>&1; do :; done
    ip route flush table 100 >/dev/null 2>&1 || true
}

route_fail() {
    log "routing-native: critical rule failed: $*"
    clean_policy
    return 1
}

clean_policy

if [ "$VPN_ENABLED" = 1 ] && [ "$VPN_TYPE" = amneziawg ] && iface_exists "$VPN_INTERFACE"; then
    [ -x "$NATIVE" ] || { log "routing-native: native AWG helper missing"; exit 1; }
    "$NATIVE" refresh >/tmp/ourfw-awg-native-refresh.log 2>&1 ||
        { log "routing-native: native AWG refresh failed"; exit 1; }
fi

ipset -! create "$VPN_IPSET" hash:net family inet >/dev/null 2>&1 || exit 1
ipset -! create "$DIRECT_IPSET" hash:net family inet >/dev/null 2>&1 || exit 1
ipset flush "$VPN_IPSET" >/dev/null 2>&1 || exit 1
ipset flush "$DIRECT_IPSET" >/dev/null 2>&1 || exit 1

vpn_list="$STATE/routing-vpn-ips.$$"
direct_list="$STATE/routing-direct-ips.$$"
strip_list "$OURFW/rules/vpn-ips.list" > "$vpn_list" || exit 1
strip_list "$OURFW/rules/direct-ips.list" > "$direct_list" || exit 1

while IFS= read -r n; do
    [ -n "$n" ] || continue
    ipset -! add "$VPN_IPSET" "$n" >/dev/null 2>&1 || { rm -f "$vpn_list" "$direct_list"; exit 1; }
done < "$vpn_list"
while IFS= read -r n; do
    [ -n "$n" ] || continue
    ipset -! add "$DIRECT_IPSET" "$n" >/dev/null 2>&1 || { rm -f "$vpn_list" "$direct_list"; exit 1; }
done < "$direct_list"
rm -f "$vpn_list" "$direct_list"

[ "$ROUTING_MODE" = off ] && { log "routing-native: off"; exit 0; }

iptables -t mangle -N OURFW_ROUTE >/dev/null 2>&1 || exit 1
iptables -t mangle -A PREROUTING -j OURFW_ROUTE >/dev/null 2>&1 || exit 1
iptables -t mangle -A OUTPUT -j OURFW_ROUTE >/dev/null 2>&1 || exit 1

iptables -t mangle -A OURFW_ROUTE -m mark --mark "$TRANSPORT_MARK" -j RETURN >/dev/null 2>&1 || exit 1

if [ -s "$STATE/vpn-endpoint4" ]; then
    while IFS= read -r ep4; do
        case "$ep4" in ''|*[!0-9.]*) ;; *)
            iptables -t mangle -A OURFW_ROUTE -d "$ep4" -j RETURN >/dev/null 2>&1 || exit 1
            ;;
        esac
    done < "$STATE/vpn-endpoint4"
fi

for n in 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4; do
    iptables -t mangle -A OURFW_ROUTE -d "$n" -j RETURN >/dev/null 2>&1 || exit 1
done

iptables -t mangle -A OURFW_ROUTE -m set --match-set "$DIRECT_IPSET" dst -j RETURN >/dev/null 2>&1 || exit 1

case "$ROUTING_MODE" in
  smart)
    iptables -t mangle -A OURFW_ROUTE -m set --match-set "$VPN_IPSET" dst \
        -j MARK --or-mark "$FWMARK" >/dev/null 2>&1 || exit 1
    ;;
  vpn-all)
    iptables -t mangle -A OURFW_ROUTE -j MARK --or-mark "$FWMARK" >/dev/null 2>&1 || exit 1
    ;;
esac

if [ "$VPN_ENABLED" = 1 ] && iface_exists "$VPN_INTERFACE"; then
    ip route show table "$TRANSPORT_TABLE" 2>/dev/null | grep -q '^default .*dev '"$VPN_INTERFACE" ||
        { log "routing-native: transport default route missing"; clean_policy; exit 1; }
    ip rule add fwmark "$FWMARK/$FWMASK" table "$TRANSPORT_TABLE" pref "$RULE_PREF" >/dev/null 2>&1 ||
        { route_fail "policy rule"; exit 1; }
fi

iptables -t filter -N OURFW_KILL >/dev/null 2>&1 || exit 1
iptables -t filter -I FORWARD 1 -j OURFW_KILL >/dev/null 2>&1 || exit 1
iptables -t filter -I OUTPUT 1 -j OURFW_KILL >/dev/null 2>&1 || exit 1
if [ "$KILLSWITCH" = 1 ] && [ "$VPN_ENABLED" = 1 ]; then
    iptables -t filter -A OURFW_KILL -m mark --mark "$FWMARK/$FWMASK" ! -o "$VPN_INTERFACE" \
        -j REJECT >/dev/null 2>&1 || exit 1
fi

if [ "$IPV6_POLICY" = block ] && [ "$VPN_ENABLED" = 1 ]; then
    need ip6tables || { clean_policy; exit 1; }
    LAN_IF="$(lan_if)"
    ip6tables -t filter -N OURFW6_FWD >/dev/null 2>&1 || exit 1
    ip6tables -t filter -N OURFW6_OUT >/dev/null 2>&1 || exit 1
    ip6tables -t filter -I FORWARD 1 -j OURFW6_FWD >/dev/null 2>&1 || exit 1
    ip6tables -t filter -I OUTPUT 1 -j OURFW6_OUT >/dev/null 2>&1 || exit 1
    for n in ::1/128 fe80::/10 fc00::/7 ff00::/8; do
        ip6tables -t filter -A OURFW6_FWD -d "$n" -j RETURN >/dev/null 2>&1 || exit 1
        ip6tables -t filter -A OURFW6_OUT -d "$n" -j RETURN >/dev/null 2>&1 || exit 1
    done
    ip6tables -t filter -A OURFW6_FWD -i "$LAN_IF" -j REJECT >/dev/null 2>&1 || exit 1
    ip6tables -t filter -A OURFW6_OUT -j REJECT >/dev/null 2>&1 || exit 1
fi

log "routing-native: mode=$ROUTING_MODE vpn_enabled=$VPN_ENABLED vpn_if=$VPN_INTERFACE table=$TRANSPORT_TABLE"
exit 0
