#!/bin/sh
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
CFG="$OURFW/config/watchdog.conf"
WATCHDOG_ENABLED=0; WATCHDOG_INTERVAL=30; WATCHDOG_FAILS=3; WATCHDOG_SCOPE=all
PING_TARGET1=1.1.1.1; PING_TARGET2=8.8.8.8; WATCHDOG_REBOOT=0
WATCHDOG_VPN_TARGET=1.1.1.1; WATCHDOG_VPN_HANDSHAKE_MAX_AGE=180
WATCHDOG_USE_INETDETECT=1; WATCHDOG_INETDETECT_MAX_AGE=180
load_conf "$CFG" || exit 1
for b in WATCHDOG_ENABLED WATCHDOG_REBOOT WATCHDOG_USE_INETDETECT; do eval "v=\${$b}"; bool01 "$v" || exit 1; done
for n in WATCHDOG_INTERVAL WATCHDOG_FAILS WATCHDOG_VPN_HANDSHAKE_MAX_AGE WATCHDOG_INETDETECT_MAX_AGE; do eval "v=\${$n}"; is_uint "$v" || exit 1; done
[ "$WATCHDOG_INTERVAL" -ge 10 ] || WATCHDOG_INTERVAL=10
fail=0
check_gateway() { gw="$(ip -4 route show default 2>/dev/null | awk '/^default/{print $3; exit}')"; [ -z "$gw" ] || ping -c1 -W1 "$gw" >/dev/null 2>&1; }
check_native_inetdetect() {
    [ "$WATCHDOG_USE_INETDETECT" = 1 ] || return 2
    [ -f "$STATE/inet-state" ] || return 2
    set -- $(cat "$STATE/inet-state" 2>/dev/null); ts="${1:-0}"; st="${2:-}"
    is_uint "$ts" || return 2; now="$(date +%s 2>/dev/null || echo 0)"; is_uint "$now" || return 2
    age=$((now-ts)); [ "$age" -le "$WATCHDOG_INETDETECT_MAX_AGE" ] 2>/dev/null || return 2
    [ "$st" = 1 ]
}
check_internet() {
    check_native_inetdetect; rc=$?
    [ "$rc" -ne 2 ] && return "$rc"
    ping -c1 -W2 "$PING_TARGET1" >/dev/null 2>&1 || ping -c1 -W2 "$PING_TARGET2" >/dev/null 2>&1
}
check_vpn() {
    VPN_ENABLED=0; VPN_TYPE=wireguard
    load_conf "$OURFW/config/vpn.conf" >/dev/null 2>&1 || return 1
    [ "$VPN_ENABLED" = 0 ] && return 0
    iface="$(active_vpn_if)"; type="$(active_vpn_type)"
    iface_exists "$iface" || return 1
    [ -z "$WATCHDOG_VPN_TARGET" ] || ping -I "$iface" -c1 -W2 "$WATCHDOG_VPN_TARGET" >/dev/null 2>&1 && return 0
    case "$type" in
      wireguard) WG=/usr/sbin/wg ;;
      amneziawg) WG=/usr/sbin/awg ;;
      openvpn)
        p="$(cat "$STATE/openvpn.pid" 2>/dev/null || true)"; is_uint "$p" && kill -0 "$p" 2>/dev/null
        return ;;
      *) return 1;;
    esac
    [ -x "$WG" ] || return 1
    now="$(date +%s 2>/dev/null || echo 0)"; latest="$($WG show "$iface" latest-handshakes 2>/dev/null | awk 'BEGIN{m=0} $2+0>m{m=$2+0} END{print m+0}')"
    is_uint "$now" && is_uint "$latest" && [ "$latest" -gt 0 ] || return 1
    age=$((now-latest)); [ "$age" -ge 0 ] 2>/dev/null && [ "$age" -le "$WATCHDOG_VPN_HANDSHAKE_MAX_AGE" ] 2>/dev/null
}
run_checks() { case "$WATCHDOG_SCOPE" in gateway) check_gateway;; internet) check_internet;; vpn) check_vpn;; all) check_gateway && check_internet && check_vpn;; *) return 1;; esac; }
repair() {
    if [ -f "$STATE/pending" ]; then log "watchdog: failed during pending config; rollback"; "$OURFW/runtime/ourfw-rollback.sh" now >/dev/null 2>&1 && return 0; fi
    if [ -f "$STATE/update-pending" ]; then log "watchdog: failed during pending component; rollback"; "$OURFW/runtime/ourfw-update.sh" rollback >/dev/null 2>&1 && return 0; fi
    # VPN failover is cheaper than restarting every mutable service.
    if ! check_vpn; then
        "$OURFW/modules/vpn/failover.sh" >/tmp/ourfw-vpn-failover.log 2>&1 && { sleep 3; run_checks && return 0; }
    fi
    log "watchdog: repairing mutable services"
    "$OURFW/modules/vpn/apply.sh" >/dev/null 2>&1 || true; "$OURFW/modules/smart-routing/apply.sh" >/dev/null 2>&1 || true
    "$OURFW/modules/adblock/apply.sh" >/dev/null 2>&1 || true; "$OURFW/modules/dns/apply.sh" >/dev/null 2>&1 || true; "$OURFW/modules/nfqws/apply.sh" >/dev/null 2>&1 || true
    sleep 5; run_checks && return 0
    if [ "$WATCHDOG_REBOOT" = 1 ]; then log "watchdog: repair failed, reboot enabled"; reboot; fi
    return 1
}
[ "$WATCHDOG_ENABLED" = 1 ] || exit 0
while :; do
    if run_checks; then fail=0; else fail=$((fail+1)); log "watchdog: failed check $fail/$WATCHDOG_FAILS"; [ "$fail" -lt "$WATCHDOG_FAILS" ] || { repair || true; fail=0; }; fi
    sleep "$WATCHDOG_INTERVAL"
done
