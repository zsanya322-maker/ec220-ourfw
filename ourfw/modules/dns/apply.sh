#!/bin/sh
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
CFG="$OURFW/config/dns.conf"
DNS_ENABLED=1
DNS_SERVERS_FILE="$OURFW/rules/dns-servers.list"
VPN_DOMAINS_FILE="$OURFW/rules/vpn-domains.list"
DIRECT_DOMAINS_FILE="$OURFW/rules/direct-domains.list"
load_conf "$CFG" || exit 1
bool01 "$DNS_ENABLED" || exit 1
R="$OURFW/config/routing.conf"
VPN_IPSET=ourfw_vpn4; DIRECT_IPSET=ourfw_direct4
[ -f "$R" ] && load_conf "$R" || exit 1

OUT="$GEN/dnsmasq-ourfw.conf"
: > "$OUT"
if [ "$DNS_ENABLED" = "1" ]; then
    strip_list "$DNS_SERVERS_FILE" | while read s; do
        case "$s" in *[!0-9a-fA-F:.]*) log "dns: invalid upstream $s";; *) echo "server=$s" >> "$OUT";; esac
    done
    # Optional DNS from the active VPN profile. It is runtime state, not a
    # permanent rewrite of resolv.conf, so disabling OURFW cleanly removes it.
    if [ -s "$STATE/vpn-dns" ]; then
        tr ',' '\n' < "$STATE/vpn-dns" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | while read s; do
            [ -n "$s" ] || continue
            case "$s" in *[!0-9a-fA-F:.]*) log "dns: invalid vpn dns $s";; *) echo "server=$s" >> "$OUT";; esac
        done
    fi
    strip_list "$VPN_DOMAINS_FILE" | while read d; do
        case "$d" in *[!A-Za-z0-9._-]*|.*|*.) log "dns: invalid vpn domain $d";; *) echo "ipset=/$d/$VPN_IPSET" >> "$OUT";; esac
    done
    strip_list "$DIRECT_DOMAINS_FILE" | while read d; do
        case "$d" in *[!A-Za-z0-9._-]*|.*|*.) log "dns: invalid direct domain $d";; *) echo "ipset=/$d/$DIRECT_IPSET" >> "$OUT";; esac
    done
fi

MAIN=/etc/storage/dnsmasq/dnsmasq.conf
INC="$STATE/dns-include.$$"
printf '%s\n' "conf-file=$OUT" > "$INC"
managed_block "$MAIN" DNS_INCLUDE "$INC" || exit 1
rm -f "$INC"

# Padavan only rebuilds /etc/dnsmasq.conf (and thus re-reads the persistent
# /etc/storage/dnsmasq/dnsmasq.conf include) on the full DHCP/DNS restart.
# A DNS-only SIGHUP is insufficient after changing this persistent include.
if command -v restart_dhcpd >/dev/null 2>&1; then
    restart_dhcpd >/tmp/ourfw-dns-restart.log 2>&1 || { log "dns: restart_dhcpd failed"; exit 1; }
elif [ -x /sbin/restart_dhcpd ]; then
    /sbin/restart_dhcpd >/tmp/ourfw-dns-restart.log 2>&1 || { log "dns: restart_dhcpd failed"; exit 1; }
else
    log "dns: restart_dhcpd applet missing"
    exit 1
fi
log "dns: generated $(wc -l < "$OUT" 2>/dev/null) rules"
exit 0
