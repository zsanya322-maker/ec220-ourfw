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
VPN_USE_PEER_DNS=0
[ -f "$OURFW/config/vpn.conf" ] && load_conf "$OURFW/config/vpn.conf" || exit 1
bool01 "$VPN_USE_PEER_DNS" || exit 1

# Never point dnsmasq at /tmp: disable/preflight failure must leave base DNS bootable.
OUT="$OURFW/dnsmasq-ourfw.conf"
TMP="$STATE/dnsmasq-ourfw.$$"
UP="$STATE/dns-upstream.$$"
LIST="$STATE/dns-list.$$"
cleanup_tmp(){ rm -f "$TMP" "$UP" "$LIST"; }
trap cleanup_tmp EXIT HUP INT TERM
: > "$TMP"; : > "$UP"
# The target is a tiny persistent placeholder. AdBlock bind-mounts its large
# generated /tmp config over this file only while enabled, so reboot is safe.
echo "conf-file=$OURFW/adblock-runtime.conf" >> "$TMP"

dns_fail() {
    log "dns: fail-closed: $*"
    return 1
}

valid_dns_ip() {
    s="$1"
    # Until selective IPv6 policy routing is implemented, all OURFW explicit
    # upstreams are deliberately IPv4-only. This avoids accepting malformed
    # IPv6 literals and prevents a user-supplied v6 resolver from bypassing an
    # IPv4 VPN policy.
    case "$s" in ''|*:*|*[!0-9.]*) return 1;; esac
    printf '%s\n' "$s" | awk -F. '
      NF!=4 {exit 1}
      {for(i=1;i<=4;i++) if($i !~ /^[0-9]+$/ || $i<0 || $i>255) exit 1}
    ' >/dev/null 2>&1
}

valid_domain() {
    d="$1"
    [ -n "$d" ] || return 1
    [ ${#d} -le 253 ] 2>/dev/null || return 1
    case "$d" in *[!A-Za-z0-9._-]*|.*|*.|*..*) return 1;; esac
    return 0
}

if [ "$DNS_ENABLED" = "1" ]; then
    strip_list "$DNS_SERVERS_FILE" > "$LIST" || { dns_fail "cannot parse upstream list"; exit 1; }
    while IFS= read -r s; do
        [ -n "$s" ] || continue
        valid_dns_ip "$s" || { dns_fail "invalid upstream $s"; exit 1; }
        printf 'server=%s\n' "$s" >> "$UP" || exit 1
    done < "$LIST"

    if [ "$VPN_USE_PEER_DNS" = "1" ] && [ -s "$STATE/vpn-dns" ]; then
        tr ',' '\n' < "$STATE/vpn-dns" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' > "$LIST" || { dns_fail "cannot parse VPN peer DNS"; exit 1; }
        while IFS= read -r s; do
            [ -n "$s" ] || continue
            # IPv6 peer DNS fallback skipped: unsupported v6 resolver is rejected fail-closed.
            case "$s" in *:*) dns_fail "IPv6 peer DNS $s unsupported until selective IPv6 routing is enabled"; exit 1;; esac
            valid_dns_ip "$s" || { dns_fail "invalid VPN peer DNS $s"; exit 1; }
            printf 'server=%s\n' "$s" >> "$UP" || exit 1
        done < "$LIST"
    fi

    # dnsmasq's `server=` option does not disable /etc/resolv.conf. Whenever
    # OURFW supplies an explicit upstream (especially VPN peer DNS), force all
    # upstream resolution to that explicit set to prevent ISP DNS fallback.
    if [ -s "$UP" ]; then
        echo 'no-resolv' >> "$TMP" || exit 1
        cat "$UP" >> "$TMP" || exit 1
    fi

    strip_list "$VPN_DOMAINS_FILE" > "$LIST" || { dns_fail "cannot parse VPN domain list"; exit 1; }
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        valid_domain "$d" || { dns_fail "invalid VPN domain $d"; exit 1; }
        printf 'ipset=/%s/%s\n' "$d" "$VPN_IPSET" >> "$TMP" || exit 1
    done < "$LIST"

    strip_list "$DIRECT_DOMAINS_FILE" > "$LIST" || { dns_fail "cannot parse direct domain list"; exit 1; }
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        valid_domain "$d" || { dns_fail "invalid direct domain $d"; exit 1; }
        printf 'ipset=/%s/%s\n' "$d" "$DIRECT_IPSET" >> "$TMP" || exit 1
    done < "$LIST"
fi
mv "$TMP" "$OUT" || exit 1

MAIN="${OURFW_DNSMASQ_MAIN:-/etc/storage/dnsmasq/dnsmasq.conf}"
INC="$STATE/dns-include.$$"
printf '%s\n' "conf-file=$OUT" > "$INC"
managed_block "$MAIN" DNS_INCLUDE "$INC" || exit 1
rm -f "$INC"

if command -v restart_dhcpd >/dev/null 2>&1; then
    restart_dhcpd >/tmp/ourfw-dns-restart.log 2>&1 || { log "dns: restart_dhcpd failed"; exit 1; }
elif [ -x /sbin/restart_dhcpd ]; then
    /sbin/restart_dhcpd >/tmp/ourfw-dns-restart.log 2>&1 || { log "dns: restart_dhcpd failed"; exit 1; }
else
    log "dns: restart_dhcpd applet missing"; exit 1
fi
log "dns: generated $(wc -l < "$OUT" 2>/dev/null) rules"
exit 0
