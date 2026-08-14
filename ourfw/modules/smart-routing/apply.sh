#!/bin/sh
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
CFG="$OURFW/config/routing.conf"
ROUTING_MODE=smart; VPN_INTERFACE=wg0; ROUTE_TABLE=100; FWMARK=0x100; FWMASK=0x100; RULE_PREF=10000; KILLSWITCH=1; IPV6_POLICY=block
VPN_IPSET=ourfw_vpn4; DIRECT_IPSET=ourfw_direct4
load_conf "$CFG" || exit 1
case "$ROUTING_MODE" in off|smart|vpn-all) ;; *) log "routing: invalid mode"; exit 1;; esac
is_uint "$ROUTE_TABLE" || exit 1
is_uint "$RULE_PREF" || exit 1
bool01 "$KILLSWITCH" || exit 1
case "$IPV6_POLICY" in block|native) ;; *) log "routing: invalid IPV6_POLICY"; exit 1;; esac
need iptables || exit 1
need ipset || exit 1
need ip || exit 1

ipt_del_jump() { while iptables "$@" >/dev/null 2>&1; do :; done; }
clean_rules() {
    ipt_del_jump -t mangle -D PREROUTING -j OURFW_ROUTE
    ipt_del_jump -t mangle -D OUTPUT -j OURFW_ROUTE
    ipt_del_jump -t filter -D FORWARD -j OURFW_KILL
    ipt_del_jump -t filter -D OUTPUT -j OURFW_KILL
    iptables -t mangle -F OURFW_ROUTE >/dev/null 2>&1 || true
    iptables -t mangle -X OURFW_ROUTE >/dev/null 2>&1 || true
    iptables -t filter -F OURFW_KILL >/dev/null 2>&1 || true
    iptables -t filter -X OURFW_KILL >/dev/null 2>&1 || true
    if command -v ip6tables >/dev/null 2>&1; then
        while ip6tables -t filter -D FORWARD -j OURFW6_KILL >/dev/null 2>&1; do :; done
        ip6tables -t filter -F OURFW6_KILL >/dev/null 2>&1 || true
        ip6tables -t filter -X OURFW6_KILL >/dev/null 2>&1 || true
    fi
    while ip rule del pref "$RULE_PREF" >/dev/null 2>&1; do :; done
    ip route flush table "$ROUTE_TABLE" >/dev/null 2>&1 || true
}

clean_rules
ipset -! create "$VPN_IPSET" hash:net family inet >/dev/null 2>&1 || exit 1
ipset -! create "$DIRECT_IPSET" hash:net family inet >/dev/null 2>&1 || exit 1
ipset flush "$VPN_IPSET" >/dev/null 2>&1 || true
ipset flush "$DIRECT_IPSET" >/dev/null 2>&1 || true
strip_list "$OURFW/rules/vpn-ips.list" | while read n; do ipset -! add "$VPN_IPSET" "$n" >/dev/null 2>&1 || log "routing: invalid vpn ip $n"; done
strip_list "$OURFW/rules/direct-ips.list" | while read n; do ipset -! add "$DIRECT_IPSET" "$n" >/dev/null 2>&1 || log "routing: invalid direct ip $n"; done

[ "$ROUTING_MODE" = "off" ] && { log "routing: off"; exit 0; }
iptables -t mangle -N OURFW_ROUTE >/dev/null 2>&1 || exit 1
iptables -t mangle -A PREROUTING -j OURFW_ROUTE
iptables -t mangle -A OUTPUT -j OURFW_ROUTE

# Never policy-route the VPN transport endpoint itself. OURFW VPN resolves the
# endpoint before this module runs and caches its IPv4 address in /tmp.
if [ -s "$STATE/vpn-endpoint4" ]; then
    ep4="$(head -n1 "$STATE/vpn-endpoint4" 2>/dev/null)"
    case "$ep4" in *[!0-9.]*) log "routing: ignored invalid endpoint cache";; *)
        iptables -t mangle -A OURFW_ROUTE -d "$ep4" -j RETURN ;;
    esac
fi

# Never policy-route local/private destinations; direct rules override VPN rules.
for n in 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4; do
    iptables -t mangle -A OURFW_ROUTE -d "$n" -j RETURN
 done
iptables -t mangle -A OURFW_ROUTE -m set --match-set "$DIRECT_IPSET" dst -j RETURN

case "$ROUTING_MODE" in
  smart)
    iptables -t mangle -A OURFW_ROUTE -m set --match-set "$VPN_IPSET" dst -j MARK --or-mark "$FWMARK"
    ;;
  vpn-all)
    iptables -t mangle -A OURFW_ROUTE -j MARK --or-mark "$FWMARK"
    ;;
esac

# Keep a dedicated table. If VPN is down, kill-switch prevents marked traffic leaking direct.
if iface_exists "$VPN_INTERFACE"; then
    ip route add default dev "$VPN_INTERFACE" table "$ROUTE_TABLE" >/dev/null 2>&1 || \
      ip route replace default dev "$VPN_INTERFACE" table "$ROUTE_TABLE" >/dev/null 2>&1 || exit 1
    ip rule add fwmark "$FWMARK/$FWMASK" table "$ROUTE_TABLE" pref "$RULE_PREF" >/dev/null 2>&1 || true
fi

iptables -t filter -N OURFW_KILL >/dev/null 2>&1 || true
iptables -t filter -A FORWARD -j OURFW_KILL
iptables -t filter -A OUTPUT -j OURFW_KILL
if [ "$KILLSWITCH" = "1" ]; then
    # Reject any marked IPv4 packet that would leave outside the VPN. This remains
    # effective even if wg0 disappears after rules were applied.
    iptables -t filter -A OURFW_KILL -m mark --mark "$FWMARK/$FWMASK" ! -o "$VPN_INTERFACE" -j REJECT
fi

# v0.3 policy routing is deliberately IPv4-first. Without a guard, a client can
# resolve AAAA and silently bypass an IPv4 VPN policy. Default to no-leak:
# while Smart/VPN-all policy is active, forwarded IPv6 from LAN may only leave
# through wg0. Set IPV6_POLICY=native explicitly to keep native IPv6 instead.
if [ "$IPV6_POLICY" = "block" ]; then
    need ip6tables || { log "routing: ip6tables missing for IPv6 leak guard"; clean_rules; exit 1; }
    LAN_IF="$(lan_if)"
    ip6tables -t filter -N OURFW6_KILL >/dev/null 2>&1 || true
    ip6tables -t filter -A FORWARD -j OURFW6_KILL
    ip6tables -t filter -A OURFW6_KILL -i "$LAN_IF" ! -o "$VPN_INTERFACE" -j REJECT
fi
log "routing: mode=$ROUTING_MODE vpn_if=$VPN_INTERFACE ipv6=$IPV6_POLICY"
exit 0
