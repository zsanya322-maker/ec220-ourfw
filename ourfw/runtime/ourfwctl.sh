#!/bin/sh
. /etc/storage/ourfw/runtime/ourfw-common.sh 2>/dev/null || exit 1
load_global || exit 1

csrf_ensure() {
    _f=/tmp/ourfw-csrf.token
    _t="$(cat "$_f" 2>/dev/null || true)"
    case "$_t" in *[!0-9A-Fa-f]*) _t="";; esac
    [ "${#_t}" -eq 64 ] 2>/dev/null && return 0

    _sum=/usr/bin/sha256sum
    [ -x "$_sum" ] || _sum=/bin/sha256sum
    [ -x "$_sum" ] || { log "csrf: sha256sum unavailable"; return 1; }

    _t="$(dd if=/dev/urandom bs=32 count=1 2>/dev/null | "$_sum" 2>/dev/null | awk '{print $1}')"
    case "$_t" in *[!0-9A-Fa-f]*) _t="";; esac
    [ "${#_t}" -eq 64 ] 2>/dev/null || { log "csrf: token generation failed"; return 1; }

    ( umask 077; printf '%s\n' "$_t" > "$_f" ) || return 1
    chmod 0600 "$_f" 2>/dev/null || true
}

display_version() {
    if [ -s "$OURFW/VERSION.overlay" ]; then
        sed -n '1p' "$OURFW/VERSION.overlay"
    else
        sed -n '1p' "$OURFW/VERSION" 2>/dev/null || printf '%s\n' dev
    fi
}

baseline_if_missing() {
    [ -f "$STATE/last-good.tar" ] || "$OURFW/runtime/ourfw-rollback.sh" baseline >/dev/null 2>&1
}

boot_modules() {
    csrf_ensure || log "csrf: unavailable after mutable boot self-heal"
    [ "${OURFW_ENABLED:-1}" = "1" ] || exit 0
    hook_install || log "unable to install Padavan event hooks"
    baseline_if_missing
    for _m in zram subscription vpn smart-routing adblock dns nfqws watchdog diagnostics; do
        _f="$OURFW/modules/$_m/start.sh"
        [ -x "$_f" ] && "$_f" boot || true
    done
}

event_modules() {
    _ev="$1"; shift
    case "$_ev" in
      firewall)
        for _m in smart-routing nfqws; do
            _f="$OURFW/modules/$_m/event.sh"
            [ -x "$_f" ] && "$_f" firewall "$@" || true
        done
        ;;
      wan)
        for _m in vpn smart-routing adblock dns nfqws zram watchdog; do
            _f="$OURFW/modules/$_m/event.sh"
            [ -x "$_f" ] && "$_f" wan "$@" || true
        done
        ;;
      internet)
        _f="$OURFW/modules/watchdog/event.sh"
        [ -x "$_f" ] && "$_f" internet "$@" || true
        ;;
      *) return 2 ;;
    esac
}

status() {
    _ver="$(display_version)"
    _wan="$(wan_if)"
    _vpn=down
    _iface="$(active_vpn_if)"
    _vtype="$(active_vpn_type)"
    iface_exists "$_iface" && _vpn=up
    _nfq=down
    pidof nfqws >/dev/null 2>&1 && _nfq=up
    printf 'OURFW_VERSION=%s\n' "$_ver"
    printf 'PENDING_ROLLBACK=%s\n' "$({ [ -f "$STATE/pending" ] || [ -f "$STATE/update-pending" ]; } && echo 1 || echo 0)"
    printf 'WAN_IF=%s\nVPN_TYPE=%s\nVPN_IF=%s\nVPN_STATE=%s\nNFQWS_STATE=%s\n' "$_wan" "$_vtype" "$_iface" "$_vpn" "$_nfq"
    printf 'STORAGE_DIR=%s\n' "$OURFW"
}

read_state_id() {
    _v="$(cat "$1" 2>/dev/null || true)"
    case "$_v" in ''|*[!A-Za-z0-9._-]*) _v="";; esac
    printf '%s\n' "$_v"
}

count_list() {
    [ -f "$1" ] || { echo 0; return; }
    strip_list "$1" 2>/dev/null | awk 'END{print NR+0}'
}

ipset_count() {
    _set="$1"
    _n="$(ipset list "$_set" 2>/dev/null | awk -F: '$1=="Number of entries"{gsub(/[[:space:]]/,"",$2);print $2;exit}')"
    is_uint "${_n:-}" || _n=0
    printf '%s\n' "$_n"
}

status_json() {
    csrf_ensure || true

    _ver="$(json_escape "$(display_version)")"
    _wan="$(json_escape "$(wan_if)")"

    VPN_INTERFACE=wg0
    VPN_ENABLED=0
    VPN_TYPE=wireguard
    VPN_FAILOVER_ENABLED=0
    VPN_FAILOVER_TYPE=openvpn
    load_conf "$OURFW/config/vpn.conf" >/dev/null 2>&1 || true
    _vpn_if="$(active_vpn_if)"
    _vpn_type="$(active_vpn_type)"
    _vpn_enabled="${VPN_ENABLED:-0}"
    _vpn_state=false
    iface_exists "$_vpn_if" && _vpn_state=true

    _hs_age=-1
    if [ "$_vpn_state" = true ]; then
        _tool=
        case "$_vpn_type" in
          amneziawg) [ -x /usr/sbin/awg ] && _tool=/usr/sbin/awg ;;
          wireguard) [ -x /usr/sbin/wg ] && _tool=/usr/sbin/wg ;;
        esac
        if [ -n "$_tool" ]; then
            _last="$("$_tool" show "$_vpn_if" latest-handshakes 2>/dev/null | awk 'NR==1{print $2}')"
            _now="$(date +%s 2>/dev/null || echo 0)"
            if is_uint "${_last:-}" && is_uint "${_now:-}" && [ "$_last" -gt 0 ] 2>/dev/null && [ "$_now" -ge "$_last" ] 2>/dev/null; then
                _hs_age=$((_now-_last))
            fi
        fi
    fi

    NFQWS_ENABLED=0
    load_conf "$OURFW/config/nfqws.conf" >/dev/null 2>&1 || true
    _nfq_enabled="${NFQWS_ENABLED:-0}"
    _nfq=false
    pidof nfqws >/dev/null 2>&1 && _nfq=true

    ROUTING_MODE=smart
    RULE_PREF=10000
    VPN_IPSET=ourfw_vpn4
    DIRECT_IPSET=ourfw_direct4
    load_conf "$OURFW/config/routing.conf" >/dev/null 2>&1 || true
    _routing_mode="$(json_escape "${ROUTING_MODE:-smart}")"
    _routing_active=false
    ip rule show 2>/dev/null | grep -q "^${RULE_PREF}:" && _routing_active=true
    _vpn_ipset_entries="$(ipset_count "${VPN_IPSET:-ourfw_vpn4}")"
    _direct_ipset_entries="$(ipset_count "${DIRECT_IPSET:-ourfw_direct4}")"
    _vpn_domain_rules="$(count_list "$OURFW/rules/vpn-domains.list")"
    _direct_domain_rules="$(count_list "$OURFW/rules/direct-domains.list")"
    _vpn_ip_rules="$(count_list "$OURFW/rules/vpn-ips.list")"
    _direct_ip_rules="$(count_list "$OURFW/rules/direct-ips.list")"

    WATCHDOG_ENABLED=0
    load_conf "$OURFW/config/watchdog.conf" >/dev/null 2>&1 || true
    _watchdog_enabled="${WATCHDOG_ENABLED:-0}"

    DNS_ENABLED=1
    load_conf "$OURFW/config/dns.conf" >/dev/null 2>&1 || true
    _dns_enabled="${DNS_ENABLED:-1}"
    _dns_generated=0
    [ -f "$OURFW/dnsmasq-ourfw.conf" ] && _dns_generated="$(grep -c '^ipset=/' "$OURFW/dnsmasq-ourfw.conf" 2>/dev/null || echo 0)"
    is_uint "${_dns_generated:-}" || _dns_generated=0

    ADBLOCK_ENABLED=0
    load_conf "$OURFW/config/adblock.conf" >/dev/null 2>&1 || true
    _adblock_enabled="${ADBLOCK_ENABLED:-0}"
    _adblock_domains=0
    if [ -f "$STATE/adblock.status" ]; then
        _n="$(sed -n 's/^DOMAINS=//p' "$STATE/adblock.status" 2>/dev/null | head -n1)"
        is_uint "${_n:-}" && _adblock_domains="$_n" || true
    fi

    ZRAM_MODE=off
    load_conf "$OURFW/config/zram.conf" >/dev/null 2>&1 || true
    _zram_mode="$(json_escape "${ZRAM_MODE:-off}")"
    _zram_active=false
    grep -q '^/dev/zram0[[:space:]]' /proc/swaps 2>/dev/null && _zram_active=true

    _https_cap=false
    _sftp_cap=false
    _openvpn_cap=false
    [ -x /usr/bin/openssl ] && [ -x /usr/bin/https-cert.sh ] && [ -x /usr/sbin/httpd ] && _https_cap=true
    [ -x /usr/libexec/sftp-server ] && _sftp_cap=true
    [ -x /usr/sbin/openvpn ] && _openvpn_cap=true

    _pending=false
    _pending_tag=
    _pending_scope=
    _pending_seconds=0
    _pending_kind=
    if [ -f "$STATE/pending" ]; then
        _pending=true
        _pending_kind=config
        _pending_tag="$(read_state_id "$STATE/pending-tag")"
        [ -n "$_pending_tag" ] || _pending_tag="$(read_state_id "$STATE/pending")"
        _pending_scope="$(read_state_id "$STATE/pending-scope")"
        _deadline="$(cat "$STATE/pending-deadline" 2>/dev/null || echo 0)"
        _now="$(date +%s 2>/dev/null || echo 0)"
        if is_uint "${_deadline:-}" && is_uint "${_now:-}" && [ "$_deadline" -gt "$_now" ] 2>/dev/null; then
            _pending_seconds=$((_deadline-_now))
        fi
    elif [ -f "$STATE/update-pending" ]; then
        _pending=true
        _pending_kind=component
        _pending_scope=component
    fi

    _last_result="$(read_state_id "$STATE/last-result")"
    _last_tag="$(read_state_id "$STATE/last-tag")"
    _last_scope="$(read_state_id "$STATE/last-scope")"
    _last_time="$(cat "$STATE/last-time" 2>/dev/null || echo 0)"
    is_uint "${_last_time:-}" || _last_time=0

    _csrf="$(cat /tmp/ourfw-csrf.token 2>/dev/null || true)"
    case "$_csrf" in *[!0-9A-Fa-f]*) _csrf="";; esac
    [ "${#_csrf}" -eq 64 ] 2>/dev/null || _csrf=""

    printf '{'
    printf '"version":"%s","wan_if":"%s",' "$_ver" "$_wan"
    printf '"vpn_type":"%s","vpn_if":"%s","vpn_enabled":%s,"vpn_up":%s,"vpn_handshake_age":%s,' \
      "$(json_escape "$_vpn_type")" "$(json_escape "$_vpn_if")" \
      "$([ "$_vpn_enabled" = 1 ] && echo true || echo false)" "$_vpn_state" "$_hs_age"
    printf '"vpn_failover_enabled":%s,"vpn_failover_type":"%s",' \
      "$([ "${VPN_FAILOVER_ENABLED:-0}" = 1 ] && echo true || echo false)" "$(json_escape "${VPN_FAILOVER_TYPE:-openvpn}")"
    printf '"nfqws_enabled":%s,"nfqws_up":%s,' "$([ "$_nfq_enabled" = 1 ] && echo true || echo false)" "$_nfq"
    printf '"routing_mode":"%s","routing_active":%s,' "$_routing_mode" "$_routing_active"
    printf '"vpn_domain_rules":%s,"direct_domain_rules":%s,"vpn_ip_rules":%s,"direct_ip_rules":%s,' \
      "$_vpn_domain_rules" "$_direct_domain_rules" "$_vpn_ip_rules" "$_direct_ip_rules"
    printf '"vpn_ipset_entries":%s,"direct_ipset_entries":%s,' "$_vpn_ipset_entries" "$_direct_ipset_entries"
    printf '"dns_enabled":%s,"dns_generated":%s,' "$([ "$_dns_enabled" = 1 ] && echo true || echo false)" "$_dns_generated"
    printf '"watchdog_enabled":%s,' "$([ "$_watchdog_enabled" = 1 ] && echo true || echo false)"
    printf '"adblock_enabled":%s,"adblock_domains":%s,' "$([ "$_adblock_enabled" = 1 ] && echo true || echo false)" "$_adblock_domains"
    printf '"zram_mode":"%s","zram_active":%s,' "$_zram_mode" "$_zram_active"
    printf '"https_cap":%s,"sftp_cap":%s,"openvpn_cap":%s,' "$_https_cap" "$_sftp_cap" "$_openvpn_cap"
    printf '"pending":%s,"pending_kind":"%s","pending_tag":"%s","pending_scope":"%s","pending_seconds":%s,' \
      "$_pending" "$(json_escape "$_pending_kind")" "$(json_escape "$_pending_tag")" "$(json_escape "$_pending_scope")" "$_pending_seconds"
    printf '"last_result":"%s","last_tag":"%s","last_scope":"%s","last_time":%s,' \
      "$(json_escape "$_last_result")" "$(json_escape "$_last_tag")" "$(json_escape "$_last_scope")" "$_last_time"
    printf '"csrf":"%s"}\n' "$_csrf"
}

case "${1:-}" in
  boot) boot_modules ;;
  event) shift; event_modules "$@" ;;
  status) status ;;
  status-json) status_json ;;
  apply) exec "$OURFW/runtime/ourfw-apply.sh" "${2:-default}" ;;
  confirm)
    if [ -f "$STATE/update-pending" ]; then exec "$OURFW/runtime/ourfw-update.sh" confirm; fi
    exec "$OURFW/runtime/ourfw-rollback.sh" confirm
    ;;
  rollback)
    if [ -f "$STATE/update-pending" ]; then exec "$OURFW/runtime/ourfw-update.sh" rollback; fi
    exec "$OURFW/runtime/ourfw-rollback.sh" now
    ;;
  baseline) exec "$OURFW/runtime/ourfw-rollback.sh" baseline ;;
  update) shift; exec "$OURFW/runtime/ourfw-update.sh" install "$@" ;;
  *) echo "usage: ourfwctl {boot|event|status|status-json|apply|confirm|rollback|baseline|update}" >&2; exit 2 ;;
esac
