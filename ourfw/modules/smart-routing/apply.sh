#!/bin/sh
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
CFG="$OURFW/config/routing.conf"
ROUTING_MODE=smart; VPN_INTERFACE=wg0; ROUTE_TABLE=100; FWMARK=0x100; FWMASK=0x100; RULE_PREF=10000; KILLSWITCH=1; IPV6_POLICY=block
VPN_IPSET=ourfw_vpn4; DIRECT_IPSET=ourfw_direct4
load_conf "$CFG" || exit 1
VPN_ENABLED=0; VPN_USE_PEER_DNS=0
[ -f "$OURFW/config/vpn.conf" ] && load_conf "$OURFW/config/vpn.conf" || exit 1
case "$ROUTING_MODE" in off|smart|vpn-all) ;; *) log "routing: invalid mode"; exit 1;; esac
is_uint "$ROUTE_TABLE" || exit 1; is_uint "$RULE_PREF" || exit 1; bool01 "$KILLSWITCH" || exit 1; bool01 "$VPN_ENABLED" || exit 1; bool01 "$VPN_USE_PEER_DNS" || exit 1
case "$IPV6_POLICY" in block|native) ;; *) log "routing: invalid IPV6_POLICY"; exit 1;; esac
need iptables || exit 1; need ipset || exit 1; need ip || exit 1

ipt_del_jump() { while iptables "$@" >/dev/null 2>&1; do :; done; }
ip6_del_jump() { while ip6tables "$@" >/dev/null 2>&1; do :; done; }
clean_rules() {
    ipt_del_jump -t mangle -D PREROUTING -j OURFW_ROUTE
    ipt_del_jump -t mangle -D OUTPUT -j OURFW_ROUTE
    ipt_del_jump -t filter -D FORWARD -j OURFW_KILL
    ipt_del_jump -t filter -D OUTPUT -j OURFW_KILL
    iptables -t mangle -F OURFW_ROUTE >/dev/null 2>&1 || true; iptables -t mangle -X OURFW_ROUTE >/dev/null 2>&1 || true
    iptables -t filter -F OURFW_KILL >/dev/null 2>&1 || true; iptables -t filter -X OURFW_KILL >/dev/null 2>&1 || true
    if command -v ip6tables >/dev/null 2>&1; then
        ip6_del_jump -t filter -D FORWARD -j OURFW6_FWD
        ip6_del_jump -t filter -D OUTPUT -j OURFW6_OUT
        ip6tables -t filter -F OURFW6_FWD >/dev/null 2>&1 || true; ip6tables -t filter -X OURFW6_FWD >/dev/null 2>&1 || true
        ip6tables -t filter -F OURFW6_OUT >/dev/null 2>&1 || true; ip6tables -t filter -X OURFW6_OUT >/dev/null 2>&1 || true
        # cleanup v0.3 legacy chain if present
        ip6_del_jump -t filter -D FORWARD -j OURFW6_KILL
        ip6tables -t filter -F OURFW6_KILL >/dev/null 2>&1 || true; ip6tables -t filter -X OURFW6_KILL >/dev/null 2>&1 || true
    fi
    while ip rule del pref "$RULE_PREF" >/dev/null 2>&1; do :; done
    ip route flush table "$ROUTE_TABLE" >/dev/null 2>&1 || true
}

clean_rules
ipset -! create "$VPN_IPSET" hash:net family inet >/dev/null 2>&1 || exit 1
ipset -! create "$DIRECT_IPSET" hash:net family inet >/dev/null 2>&1 || exit 1
ipset flush "$VPN_IPSET" >/dev/null 2>&1 || true; ipset flush "$DIRECT_IPSET" >/dev/null 2>&1 || true
strip_list "$OURFW/rules/vpn-ips.list" | while read n; do ipset -! add "$VPN_IPSET" "$n" >/dev/null 2>&1 || log "routing: invalid vpn ip $n"; done
strip_list "$OURFW/rules/direct-ips.list" | while read n; do ipset -! add "$DIRECT_IPSET" "$n" >/dev/null 2>&1 || log "routing: invalid direct ip $n"; done

[ "$ROUTING_MODE" = "off" ] && { log "routing: off"; exit 0; }
iptables -t mangle -N OURFW_ROUTE >/dev/null 2>&1 || exit 1
iptables -t mangle -A PREROUTING -j OURFW_ROUTE
iptables -t mangle -A OUTPUT -j OURFW_ROUTE
if [ -s "$STATE/vpn-endpoint4" ]; then
    ep4="$(head -n1 "$STATE/vpn-endpoint4" 2>/dev/null)"
    case "$ep4" in *[!0-9.]*) log "routing: ignored invalid endpoint cache";; *) iptables -t mangle -A OURFW_ROUTE -d "$ep4" -j RETURN;; esac
fi
# Peer DNS is part of the VPN contract. Mark its IPv4 DNS traffic before the
# generic private/direct exclusions so a provider DNS such as 10.0.0.1 cannot
# silently escape through WAN. The normal kill-switch then protects it if wg0
# disappears. IPv6 peer DNS is intentionally ignored by dns/apply.sh until the
# selective IPv6 router is implemented.
if [ "$VPN_ENABLED" = "1" ] && [ "$VPN_USE_PEER_DNS" = "1" ] && [ -s "$STATE/vpn-dns" ]; then
    tr ',' '\n' < "$STATE/vpn-dns" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | while IFS= read -r d; do
        [ -n "$d" ] || continue
        case "$d" in
          *:*) ;;
          *[!0-9.]*) log "routing: ignored invalid peer DNS $d" ;;
          *)
            iptables -t mangle -A OURFW_ROUTE -p udp -d "$d" --dport 53 -j MARK --or-mark "$FWMARK" >/dev/null 2>&1 || log "routing: invalid peer DNS $d"
            iptables -t mangle -A OURFW_ROUTE -p tcp -d "$d" --dport 53 -j MARK --or-mark "$FWMARK" >/dev/null 2>&1 || log "routing: invalid peer DNS $d"
            ;;
        esac
    done
fi
for n in 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4; do iptables -t mangle -A OURFW_ROUTE -d "$n" -j RETURN; done
iptables -t mangle -A OURFW_ROUTE -m set --match-set "$DIRECT_IPSET" dst -j RETURN
case "$ROUTING_MODE" in
  smart) iptables -t mangle -A OURFW_ROUTE -m set --match-set "$VPN_IPSET" dst -j MARK --or-mark "$FWMARK";;
  vpn-all) iptables -t mangle -A OURFW_ROUTE -j MARK --or-mark "$FWMARK";;
esac
if iface_exists "$VPN_INTERFACE"; then
    ip route add default dev "$VPN_INTERFACE" table "$ROUTE_TABLE" >/dev/null 2>&1 || ip route replace default dev "$VPN_INTERFACE" table "$ROUTE_TABLE" >/dev/null 2>&1 || exit 1
    ip rule add fwmark "$FWMARK/$FWMASK" table "$ROUTE_TABLE" pref "$RULE_PREF" >/dev/null 2>&1 || true
fi

iptables -t filter -N OURFW_KILL >/dev/null 2>&1 || true
iptables -t filter -I FORWARD 1 -j OURFW_KILL
iptables -t filter -I OUTPUT 1 -j OURFW_KILL
if [ "$KILLSWITCH" = "1" ] && [ "$VPN_ENABLED" = "1" ]; then
    iptables -t filter -A OURFW_KILL -m mark --mark "$FWMARK/$FWMASK" ! -o "$VPN_INTERFACE" -j REJECT
fi

# IPv6 policy is fail-closed only when policy VPN itself is enabled. If wg0 is
# temporarily down we still block global IPv6, preventing a silent direct leak.
if [ "$IPV6_POLICY" = "block" ] && [ "$VPN_ENABLED" = "1" ]; then
    need ip6tables || { log "routing: ip6tables missing for IPv6 leak guard"; clean_rules; exit 1; }
    LAN_IF="$(lan_if)"
    ip6tables -t filter -N OURFW6_FWD >/dev/null 2>&1 || true
    ip6tables -t filter -N OURFW6_OUT >/dev/null 2>&1 || true
    # Insert before Padavan ESTABLISHED/RELATED accepts so existing direct v6
    # sessions cannot survive enabling the guard.
    ip6tables -t filter -I FORWARD 1 -j OURFW6_FWD
    ip6tables -t filter -I OUTPUT 1 -j OURFW6_OUT
    for n in ::1/128 fe80::/10 fc00::/7 ff00::/8; do
        ip6tables -t filter -A OURFW6_FWD -d "$n" -j RETURN
        ip6tables -t filter -A OURFW6_OUT -d "$n" -j RETURN
    done
    # Allow the encrypted IPv6 transport endpoint to remain direct.
    if [ -s "$STATE/vpn-endpoint6" ]; then
        ep6="$(head -n1 "$STATE/vpn-endpoint6" 2>/dev/null)"
        case "$ep6" in *[!0-9A-Fa-f:.]*) log "routing: ignored invalid IPv6 endpoint cache";; *) ip6tables -t filter -A OURFW6_OUT -d "$ep6" -j RETURN;; esac
    fi
    ip6tables -t filter -A OURFW6_FWD -o "$VPN_INTERFACE" -j RETURN
    ip6tables -t filter -A OURFW6_FWD -i "$LAN_IF" -j REJECT
    ip6tables -t filter -A OURFW6_OUT -o "$VPN_INTERFACE" -j RETURN
    ip6tables -t filter -A OURFW6_OUT -j REJECT
fi
log "routing: mode=$ROUTING_MODE vpn_enabled=$VPN_ENABLED vpn_if=$VPN_INTERFACE ipv6=$IPV6_POLICY"
exit 0
