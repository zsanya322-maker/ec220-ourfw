#!/bin/sh
. /etc/storage/ourfw/runtime/ourfw-common.sh 2>/dev/null || exit 1
load_global || exit 1

# Hardware compatibility: EC220 BusyBox ash has no `command` builtin.
# Keep a per-boot CSRF token available from mutable runtime as defense-in-depth
# even if the immutable loader cannot create it.
csrf_ensure() {
    f=/tmp/ourfw-csrf.token
    t="$(cat "$f" 2>/dev/null || true)"
    case "$t" in *[!0-9A-Fa-f]*) t="";; esac
    [ "${#t}" -eq 64 ] 2>/dev/null && return 0

    sum=/usr/bin/sha256sum
    [ -x "$sum" ] || sum=/bin/sha256sum
    [ -x "$sum" ] || { log "csrf: sha256sum unavailable"; return 1; }

    t="$(dd if=/dev/urandom bs=32 count=1 2>/dev/null | "$sum" 2>/dev/null | awk '{print $1}')"
    case "$t" in *[!0-9A-Fa-f]*) t="";; esac
    [ "${#t}" -eq 64 ] 2>/dev/null || { log "csrf: token generation failed"; return 1; }

    ( umask 077; printf '%s\n' "$t" > "$f" ) || return 1
    chmod 0600 "$f" 2>/dev/null || true
    return 0
}

baseline_if_missing() {
    [ -f "$STATE/last-good.tar" ] || "$OURFW/runtime/ourfw-rollback.sh" baseline >/dev/null 2>&1
}

boot_modules() {
    csrf_ensure || log "csrf: unavailable after mutable boot self-heal"
    [ "${OURFW_ENABLED:-1}" = "1" ] || exit 0
    hook_install || log "unable to install Padavan event hooks"
    baseline_if_missing
    # Subscription boot hook is deliberately passive: it only creates protected
    # runtime state/salt and fixes secret permissions. It never fetches a feed.
    for m in zram subscription vpn smart-routing adblock dns nfqws watchdog diagnostics; do
        f="$OURFW/modules/$m/start.sh"
        [ -x "$f" ] && "$f" boot || true
    done
}

event_modules() {
    ev="$1"; shift
    case "$ev" in
      firewall)
        for m in smart-routing nfqws; do
            f="$OURFW/modules/$m/event.sh"; [ -x "$f" ] && "$f" firewall "$@" || true
        done
        ;;
      wan)
        for m in vpn smart-routing adblock dns nfqws zram watchdog; do
            f="$OURFW/modules/$m/event.sh"; [ -x "$f" ] && "$f" wan "$@" || true
        done
        ;;
      internet)
        f="$OURFW/modules/watchdog/event.sh"
        [ -x "$f" ] && "$f" internet "$@" || true
        ;;
      *) return 2 ;;
    esac
}

status() {
    ver="$(cat "$OURFW/VERSION" 2>/dev/null || echo dev)"
    wan="$(wan_if)"
    vpn=down; iface="$(active_vpn_if)"; vtype="$(active_vpn_type)"
    iface_exists "$iface" && vpn=up
    nfq=down; pidof nfqws >/dev/null 2>&1 && nfq=up
    printf 'OURFW_VERSION=%s\n' "$ver"
    printf 'PENDING_ROLLBACK=%s\n' "$({ [ -f "$STATE/pending" ] || [ -f "$STATE/update-pending" ]; } && echo 1 || echo 0)"
    printf 'WAN_IF=%s\nVPN_TYPE=%s\nVPN_IF=%s\nVPN_STATE=%s\nNFQWS_STATE=%s\n' "$wan" "$vtype" "$iface" "$vpn" "$nfq"
    printf 'STORAGE_DIR=%s\n' "$OURFW"
}

status_json() {
    csrf_ensure || true
    ver="$(json_escape "$(cat "$OURFW/VERSION" 2>/dev/null || echo dev)")"
    wan="$(json_escape "$(wan_if)")"

    VPN_INTERFACE=wg0; VPN_ENABLED=0; VPN_TYPE=wireguard; VPN_FAILOVER_ENABLED=0; VPN_FAILOVER_TYPE=openvpn
    load_conf "$OURFW/config/vpn.conf" >/dev/null 2>&1 || true
    vpn_if="$(active_vpn_if)"; vpn_type="$(active_vpn_type)"; vpn_enabled="${VPN_ENABLED:-0}"
    vpn_state=false; iface_exists "$vpn_if" && vpn_state=true

    NFQWS_ENABLED=0
    load_conf "$OURFW/config/nfqws.conf" >/dev/null 2>&1 || true
    nfq_enabled="${NFQWS_ENABLED:-0}"; nfq=false; pidof nfqws >/dev/null 2>&1 && nfq=true

    ROUTING_MODE=smart
    load_conf "$OURFW/config/routing.conf" >/dev/null 2>&1 || true
    routing_mode="$(json_escape "${ROUTING_MODE:-smart}")"

    WATCHDOG_ENABLED=0
    load_conf "$OURFW/config/watchdog.conf" >/dev/null 2>&1 || true
    watchdog_enabled="${WATCHDOG_ENABLED:-0}"

    ADBLOCK_ENABLED=0
    load_conf "$OURFW/config/adblock.conf" >/dev/null 2>&1 || true
    adblock_enabled="${ADBLOCK_ENABLED:-0}"
    adblock_domains=0
    if [ -f "$STATE/adblock.status" ]; then
        n="$(sed -n 's/^DOMAINS=//p' "$STATE/adblock.status" 2>/dev/null | head -n1)"
        is_uint "$n" && adblock_domains="$n" || true
    fi

    ZRAM_MODE=off
    load_conf "$OURFW/config/zram.conf" >/dev/null 2>&1 || true
    zram_mode="$(json_escape "${ZRAM_MODE:-off}")"
    zram_active=false
    grep -q '^/dev/zram0[[:space:]]' /proc/swaps 2>/dev/null && zram_active=true

    https_cap=false; sftp_cap=false; openvpn_cap=false
    [ -x /usr/bin/openssl ] && [ -x /usr/bin/https-cert.sh ] && [ -x /usr/sbin/httpd ] && https_cap=true
    [ -x /usr/libexec/sftp-server ] && sftp_cap=true
    [ -x /usr/sbin/openvpn ] && openvpn_cap=true

    pending=false; { [ -f "$STATE/pending" ] || [ -f "$STATE/update-pending" ]; } && pending=true
    csrf="$(cat /tmp/ourfw-csrf.token 2>/dev/null || true)"
    case "$csrf" in *[!0-9A-Fa-f]*) csrf="";; esac
    [ "${#csrf}" -eq 64 ] 2>/dev/null || csrf=""
    printf '{"version":"%s","wan_if":"%s","vpn_type":"%s","vpn_if":"%s","vpn_enabled":%s,"vpn_up":%s,"vpn_failover_enabled":%s,"vpn_failover_type":"%s","nfqws_enabled":%s,"nfqws_up":%s,"routing_mode":"%s","watchdog_enabled":%s,"adblock_enabled":%s,"adblock_domains":%s,"zram_mode":"%s","zram_active":%s,"https_cap":%s,"sftp_cap":%s,"openvpn_cap":%s,"pending":%s,"csrf":"%s"}\n' \
      "$ver" "$wan" "$(json_escape "$vpn_type")" "$(json_escape "$vpn_if")" \
      "$([ "$vpn_enabled" = 1 ] && echo true || echo false)" "$vpn_state" \
      "$([ "${VPN_FAILOVER_ENABLED:-0}" = 1 ] && echo true || echo false)" "$(json_escape "${VPN_FAILOVER_TYPE:-openvpn}")" \
      "$([ "$nfq_enabled" = 1 ] && echo true || echo false)" "$nfq" "$routing_mode" \
      "$([ "$watchdog_enabled" = 1 ] && echo true || echo false)" \
      "$([ "$adblock_enabled" = 1 ] && echo true || echo false)" "$adblock_domains" "$zram_mode" "$zram_active" \
      "$https_cap" "$sftp_cap" "$openvpn_cap" "$pending" "$csrf"
}

case "${1:-}" in
  boot) boot_modules ;;
  event) shift; event_modules "$@" ;;
  status) status ;;
  status-json) status_json ;;
  apply) exec "$OURFW/runtime/ourfw-apply.sh" "${2:-default}" ;;
  confirm)
    if [ -f "$STATE/update-pending" ]; then exec "$OURFW/runtime/ourfw-update.sh" confirm; fi
    exec "$OURFW/runtime/ourfw-rollback.sh" confirm ;;
  rollback)
    if [ -f "$STATE/update-pending" ]; then exec "$OURFW/runtime/ourfw-update.sh" rollback; fi
    exec "$OURFW/runtime/ourfw-rollback.sh" now ;;
  baseline) exec "$OURFW/runtime/ourfw-rollback.sh" baseline ;;
  update) shift; exec "$OURFW/runtime/ourfw-update.sh" install "$@" ;;
  *) echo "usage: ourfwctl {boot|event|status|status-json|apply|confirm|rollback|baseline|update}" >&2; exit 2 ;;
esac
