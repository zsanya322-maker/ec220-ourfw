#!/bin/sh
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
CFG="$OURFW/config/watchdog.conf"
WATCHDOG_ENABLED=1; WATCHDOG_INTERVAL=30; WATCHDOG_FAILS=3; WATCHDOG_SCOPE=all
PING_TARGET1=1.1.1.1; PING_TARGET2=8.8.8.8; WATCHDOG_REBOOT=0
WATCHDOG_VPN_TARGET=1.1.1.1; WATCHDOG_VPN_HANDSHAKE_MAX_AGE=180
load_conf "$CFG" || exit 1
bool01 "$WATCHDOG_ENABLED" || exit 1; bool01 "$WATCHDOG_REBOOT" || exit 1
is_uint "$WATCHDOG_INTERVAL" || exit 1; is_uint "$WATCHDOG_FAILS" || exit 1; is_uint "$WATCHDOG_VPN_HANDSHAKE_MAX_AGE" || exit 1
[ "$WATCHDOG_INTERVAL" -ge 10 ] || WATCHDOG_INTERVAL=10
fail=0
check_gateway() { gw="$(ip -4 route show default 2>/dev/null | awk '/^default/{print $3; exit}')"; [ -z "$gw" ] || ping -c1 -W1 "$gw" >/dev/null 2>&1; }
check_internet() { ping -c1 -W2 "$PING_TARGET1" >/dev/null 2>&1 || ping -c1 -W2 "$PING_TARGET2" >/dev/null 2>&1; }
check_vpn() {
    VPN_INTERFACE=wg0; VPN_ENABLED=0; VPN_TYPE=wireguard
    load_conf "$OURFW/config/vpn.conf" >/dev/null 2>&1 || return 1
    [ "$VPN_ENABLED" = "0" ] && return 0
    iface_exists "$VPN_INTERFACE" || return 1
    # Active probe through the tunnel is the strongest check and works even when
    # an interface exists but the peer/path is dead.
    if [ -n "$WATCHDOG_VPN_TARGET" ] && ping -I "$VPN_INTERFACE" -c1 -W2 "$WATCHDOG_VPN_TARGET" >/dev/null 2>&1; then return 0; fi
    case "$VPN_TYPE" in wireguard) WG=/usr/sbin/wg;; amneziawg) WG=/usr/sbin/awg;; *) return 1;; esac
    [ -x "$WG" ] || return 1
    now="$(date +%s 2>/dev/null || echo 0)"; is_uint "$now" || return 1
    latest="$($WG show "$VPN_INTERFACE" latest-handshakes 2>/dev/null | awk 'BEGIN{m=0} $2+0>m{m=$2+0} END{print m+0}')"
    is_uint "$latest" || return 1; [ "$latest" -gt 0 ] || return 1
    age=$((now-latest)); [ "$age" -ge 0 ] 2>/dev/null && [ "$age" -le "$WATCHDOG_VPN_HANDSHAKE_MAX_AGE" ] 2>/dev/null
}
run_checks() { case "$WATCHDOG_SCOPE" in gateway) check_gateway;; internet) check_internet;; vpn) check_vpn;; all) check_gateway && check_internet && check_vpn;; *) return 1;; esac; }
repair() {
    log "watchdog: threshold reached, repairing mutable services"
    "$OURFW/modules/vpn/apply.sh" >/dev/null 2>&1 || true; "$OURFW/modules/smart-routing/apply.sh" >/dev/null 2>&1 || true
    "$OURFW/modules/dns/apply.sh" >/dev/null 2>&1 || true; "$OURFW/modules/nfqws/apply.sh" >/dev/null 2>&1 || true
    sleep 5; run_checks && return 0
    if [ "$WATCHDOG_REBOOT" = "1" ]; then log "watchdog: repair failed, reboot requested by policy"; reboot; fi
    return 1
}
[ "$WATCHDOG_ENABLED" = "1" ] || exit 0
while :; do
    if run_checks; then fail=0; else fail=$((fail+1)); log "watchdog: failed check $fail/$WATCHDOG_FAILS"; [ "$fail" -lt "$WATCHDOG_FAILS" ] || { repair || true; fail=0; }; fi
    sleep "$WATCHDOG_INTERVAL"
done
