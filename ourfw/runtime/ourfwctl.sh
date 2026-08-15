#!/bin/sh
. /etc/storage/ourfw/runtime/ourfw-common.sh 2>/dev/null || exit 1
load_global || exit 1

baseline_if_missing() {
    [ -f "$STATE/last-good.tar" ] || "$OURFW/runtime/ourfw-rollback.sh" baseline >/dev/null 2>&1
}

boot_modules() {
    [ "${OURFW_ENABLED:-1}" = "1" ] || exit 0
    hook_install || log "unable to install Padavan event hooks"
    baseline_if_missing
    for m in vpn smart-routing dns nfqws watchdog diagnostics; do
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
        for m in vpn smart-routing dns nfqws watchdog; do
            f="$OURFW/modules/$m/event.sh"; [ -x "$f" ] && "$f" wan "$@" || true
        done
        ;;
      *) return 2 ;;
    esac
}

status() {
    ver="$(cat "$OURFW/VERSION" 2>/dev/null || echo dev)"
    wan="$(wan_if)"
    vpn=down; iface=wg0
    [ -f "$OURFW/config/vpn.conf" ] && load_conf "$OURFW/config/vpn.conf" >/dev/null 2>&1 || true
    iface="${VPN_INTERFACE:-wg0}"
    iface_exists "$iface" && vpn=up
    nfq=down; pidof nfqws >/dev/null 2>&1 && nfq=up
    printf 'OURFW_VERSION=%s\n' "$ver"
    printf 'PENDING_ROLLBACK=%s\n' "$({ [ -f "$STATE/pending" ] || [ -f "$STATE/update-pending" ]; } && echo 1 || echo 0)"
    printf 'WAN_IF=%s\nVPN_IF=%s\nVPN_STATE=%s\nNFQWS_STATE=%s\n' "$wan" "$iface" "$vpn" "$nfq"
    printf 'STORAGE_DIR=%s\n' "$OURFW"
}

status_json() {
    ver="$(json_escape "$(cat "$OURFW/VERSION" 2>/dev/null || echo dev)")"
    wan="$(json_escape "$(wan_if)")"

    VPN_INTERFACE=wg0; VPN_ENABLED=0
    load_conf "$OURFW/config/vpn.conf" >/dev/null 2>&1 || true
    vpn_if="${VPN_INTERFACE:-wg0}"; vpn_enabled="${VPN_ENABLED:-0}"
    vpn_state=false; iface_exists "$vpn_if" && vpn_state=true

    NFQWS_ENABLED=0
    load_conf "$OURFW/config/nfqws.conf" >/dev/null 2>&1 || true
    nfq_enabled="${NFQWS_ENABLED:-0}"; nfq=false; pidof nfqws >/dev/null 2>&1 && nfq=true

    ROUTING_MODE=smart
    load_conf "$OURFW/config/routing.conf" >/dev/null 2>&1 || true
    routing_mode="$(json_escape "${ROUTING_MODE:-smart}")"

    WATCHDOG_ENABLED=1
    load_conf "$OURFW/config/watchdog.conf" >/dev/null 2>&1 || true
    watchdog_enabled="${WATCHDOG_ENABLED:-1}"

    pending=false; { [ -f "$STATE/pending" ] || [ -f "$STATE/update-pending" ]; } && pending=true
    csrf="$(cat /tmp/ourfw-csrf.token 2>/dev/null || true)"
    case "$csrf" in *[!0-9A-Fa-f]*) csrf="";; esac
    [ "${#csrf}" -eq 64 ] 2>/dev/null || csrf=""
    printf '{"version":"%s","wan_if":"%s","vpn_if":"%s","vpn_enabled":%s,"vpn_up":%s,"nfqws_enabled":%s,"nfqws_up":%s,"routing_mode":"%s","watchdog_enabled":%s,"pending":%s,"csrf":"%s"}\n' \
      "$ver" "$wan" "$(json_escape "$vpn_if")" \
      "$([ "$vpn_enabled" = 1 ] && echo true || echo false)" "$vpn_state" \
      "$([ "$nfq_enabled" = 1 ] && echo true || echo false)" "$nfq" "$routing_mode" \
      "$([ "$watchdog_enabled" = 1 ] && echo true || echo false)" "$pending" "$csrf"
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
