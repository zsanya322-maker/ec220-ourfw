#!/bin/sh
# Experimental OURFW v0.7 Hysteria2 data plane for EC220-G5 v2.
# No action is taken at boot. The caller must explicitly prepare/start/arm it.
set -u

COMMON=${OURFW_COMMON_OVERRIDE:-/etc/storage/ourfw/runtime/ourfw-common.sh}
. "$COMMON" 2>/dev/null || exit 1

HY2_ENGINE_URL=${HY2_ENGINE_URL:-https://github.com/zsanya322-maker/ec220-ourfw/releases/download/hy2-engine-v0.7b-r1/ec220-hy2-tproxy-salamander}
HY2_ENGINE_SHA256=${HY2_ENGINE_SHA256:-02d907537a313f0fd69b0390af2eb89b4f8661208320ee6955f7bf9f1c0de99f}
HY2_ENGINE_BYTES=${HY2_ENGINE_BYTES:-9830593}
HY2_PORT=${HY2_PORT:-2500}
HY2_MARK=${HY2_MARK:-0x200}
HY2_MASK=${HY2_MASK:-0x200}
HY2_TABLE=${HY2_TABLE:-101}
HY2_RULE_PREF=${HY2_RULE_PREF:-10010}
HY2_ROLLBACK_TIMEOUT=${HY2_ROLLBACK_TIMEOUT:-90}
HY2_VPN_IPSET=${HY2_VPN_IPSET:-ourfw_vpn4}
HY2_DIRECT_IPSET=${HY2_DIRECT_IPSET:-ourfw_direct4}
HY2_MODULE_DIR=${HY2_MODULE_DIR:-$OURFW/modules/vpn/tproxy-modules}
HY2_RUNTIME=${HY2_RUNTIME:-$STATE/hy2}
HY2_ALLOW_LEGACY_VPN=${HY2_ALLOW_LEGACY_VPN:-0}
HY2_ENGINE="$HY2_RUNTIME/ec220-hy2-tproxy"
HY2_ENGINE_PID="$HY2_RUNTIME/engine.pid"
HY2_ENGINE_LOG="$HY2_RUNTIME/engine.log"
HY2_ROUTE_STATE="$HY2_RUNTIME/route.state"
HY2_GUARD_PID="$HY2_RUNTIME/route-guard.pid"
HY2_CONFIRM_TOKEN="$HY2_RUNTIME/confirm.token"
HY2_CHAIN=OURFW_HY2

mkdir_runtime() {
    mkdir -p "$HY2_RUNTIME" || return 1
    chmod 0700 "$HY2_RUNTIME" 2>/dev/null || true
}

is_loaded() {
    grep -q "^$1 " /proc/modules 2>/dev/null
}

module_file() {
    name="$1"
    if [ -s "$HY2_MODULE_DIR/$name" ]; then
        printf '%s\n' "$HY2_MODULE_DIR/$name"
        return 0
    fi
    find /lib/modules -type f -name "$name" -print -quit 2>/dev/null
}

load_one() {
    mod="$1"; file="$2"
    is_loaded "$mod" && return 0
    path="$(module_file "$file")"
    [ -n "$path" ] && [ -s "$path" ] || { log "hy2: module $file missing"; return 1; }
    insmod "$path" >/dev/null 2>&1 || { is_loaded "$mod" && return 0; log "hy2: insmod $file failed"; return 1; }
    is_loaded "$mod"
}

load_modules() {
    need insmod || return 1
    load_one nf_tproxy_core nf_tproxy_core.ko || return 1
    load_one xt_socket xt_socket.ko || return 1
    load_one xt_TPROXY xt_TPROXY.ko || return 1
    return 0
}

sha_ok() {
    f="$1"
    [ -s "$f" ] || return 1
    bytes="$(wc -c < "$f" 2>/dev/null | tr -d '[:space:]')"
    [ "$bytes" = "$HY2_ENGINE_BYTES" ] || return 1
    actual="$(sha256sum "$f" 2>/dev/null | awk '{print $1}')"
    [ "$(printf '%s' "$actual" | tr A-F a-f)" = "$(printf '%s' "$HY2_ENGINE_SHA256" | tr A-F a-f)" ]
}

fetch_engine() {
    mkdir_runtime || return 1
    need sha256sum || return 1
    if sha_ok "$HY2_ENGINE"; then
        chmod 0700 "$HY2_ENGINE" 2>/dev/null || true
        return 0
    fi
    need curl || { log "hy2: curl missing"; return 1; }
    tmp="$HY2_RUNTIME/engine.tmp.$$"
    rm -f "$tmp"
    umask 077
    curl -fL --connect-timeout 10 --max-time 180 --retry 2 --proto '=https' --proto-redir '=https' \
      -o "$tmp" "$HY2_ENGINE_URL" >/dev/null 2>&1 || { rm -f "$tmp"; log "hy2: engine download failed"; return 1; }
    sha_ok "$tmp" || { rm -f "$tmp"; log "hy2: downloaded engine failed size/SHA256 verification"; return 1; }
    chmod 0700 "$tmp" || { rm -f "$tmp"; return 1; }
    mv "$tmp" "$HY2_ENGINE" || return 1
    log "hy2: verified transient engine ready"
}

pid_value() {
    [ -f "$1" ] || return 1
    p="$(cat "$1" 2>/dev/null || true)"
    is_uint "$p" || return 1
    printf '%s\n' "$p"
}

engine_alive() {
    p="$(pid_value "$HY2_ENGINE_PID" 2>/dev/null || true)"
    [ -n "$p" ] && kill -0 "$p" 2>/dev/null
}

engine_stop() {
    p="$(pid_value "$HY2_ENGINE_PID" 2>/dev/null || true)"
    if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then
        kill "$p" 2>/dev/null || true
        n=0
        while kill -0 "$p" 2>/dev/null && [ "$n" -lt 5 ]; do sleep 1; n=$((n+1)); done
        kill -9 "$p" 2>/dev/null || true
    fi
    rm -f "$HY2_ENGINE_PID"
}

validate_uri_file() {
    uri="$1"
    [ -f "$uri" ] && [ -s "$uri" ] || { log "hy2: URI file missing"; return 1; }
    # The engine independently enforces regular-file, size and 0600-style access.
    "$HY2_ENGINE" -uri-file "$uri" -check-config > "$HY2_RUNTIME/config-check.txt" 2>&1 || {
        log "hy2: protected URI validation failed"; return 1;
    }
    grep -q '^CONFIG_CHECK=OK ' "$HY2_RUNTIME/config-check.txt" || return 1
}

engine_start() {
    uri="$1"
    load_modules || return 1
    fetch_engine || return 1
    validate_uri_file "$uri" || return 1
    engine_stop
    : > "$HY2_ENGINE_LOG"
    chmod 0600 "$HY2_ENGINE_LOG" 2>/dev/null || true
    "$HY2_ENGINE" -uri-file "$uri" -listen ":$HY2_PORT" >> "$HY2_ENGINE_LOG" 2>&1 &
    p=$!
    printf '%s\n' "$p" > "$HY2_ENGINE_PID"
    chmod 0600 "$HY2_ENGINE_PID" 2>/dev/null || true
    n=0
    while [ "$n" -lt 8 ]; do
        kill -0 "$p" 2>/dev/null || { rm -f "$HY2_ENGINE_PID"; log "hy2: engine exited during startup"; return 1; }
        grep -q 'EC220 HY2 connected' "$HY2_ENGINE_LOG" 2>/dev/null && { log "hy2: engine connected"; return 0; }
        sleep 1; n=$((n+1))
    done
    engine_stop
    log "hy2: engine connection timeout"
    return 1
}

ipt_del_jump() {
    while iptables "$@" >/dev/null 2>&1; do :; done
}

route_cleanup_no_guard() {
    # The jump is intentionally generic and the first chain rule limits it to
    # the LAN interface. This makes creation and deletion byte-for-byte
    # symmetric, so rollback cannot leave a stale PREROUTING reference.
    ipt_del_jump -t mangle -D PREROUTING -j "$HY2_CHAIN"
    iptables -t mangle -F "$HY2_CHAIN" >/dev/null 2>&1 || true
    iptables -t mangle -X "$HY2_CHAIN" >/dev/null 2>&1 || true
    while ip rule del pref "$HY2_RULE_PREF" >/dev/null 2>&1; do :; done
    ip route flush table "$HY2_TABLE" >/dev/null 2>&1 || true
    rm -f "$HY2_ROUTE_STATE" "$HY2_CONFIRM_TOKEN"
}

kill_guard() {
    p="$(pid_value "$HY2_GUARD_PID" 2>/dev/null || true)"
    [ -z "$p" ] || kill "$p" >/dev/null 2>&1 || true
    rm -f "$HY2_GUARD_PID"
}

route_off() {
    kill_guard
    route_cleanup_no_guard
    log "hy2: TPROXY routing disabled"
}

route_fail() {
    log "hy2: route setup failed: $*"
    route_cleanup_no_guard
    return 1
}

make_token() {
    need sha256sum || return 1
    dd if=/dev/urandom bs=24 count=1 2>/dev/null | sha256sum | awk '{print substr($1,1,24)}'
}

legacy_vpn_active() {
    [ "$HY2_ALLOW_LEGACY_VPN" = 1 ] && return 1
    [ -s "$STATE/vpn-interface" ] || return 1
    iface="$(cat "$STATE/vpn-interface" 2>/dev/null || true)"
    case "$iface" in ''|*[!A-Za-z0-9_.:-]*) return 1;; esac
    ip link show dev "$iface" >/dev/null 2>&1
}

route_arm() {
    mode="$1"
    case "$mode" in smart|vpn-all) ;; *) echo "mode must be smart or vpn-all" >&2; return 2;; esac
    engine_alive || { echo "Hysteria engine is not running" >&2; return 3; }
    load_modules || return 4
    need iptables || return 4
    need ip || return 4
    [ "$mode" != smart ] || need ipset || return 4
    if legacy_vpn_active; then
        echo "legacy OURFW VPN interface is active; disable it before arming Hysteria TPROXY" >&2
        return 4
    fi

    lan="$(lan_if 2>/dev/null || true)"
    case "$lan" in ''|*[!A-Za-z0-9_.:-]*) echo "cannot determine LAN interface" >&2; return 4;; esac

    route_off >/dev/null 2>&1 || true
    ip rule add fwmark "$HY2_MARK/$HY2_MASK" table "$HY2_TABLE" pref "$HY2_RULE_PREF" >/dev/null 2>&1 || { route_fail "ip rule"; return 5; }
    ip route add local 0.0.0.0/0 dev lo table "$HY2_TABLE" >/dev/null 2>&1 || { route_fail "local policy route"; return 5; }
    iptables -t mangle -N "$HY2_CHAIN" >/dev/null 2>&1 || { route_fail "mangle chain"; return 5; }
    iptables -t mangle -I PREROUTING 1 -j "$HY2_CHAIN" >/dev/null 2>&1 || { route_fail "PREROUTING jump"; return 5; }
    iptables -t mangle -A "$HY2_CHAIN" ! -i "$lan" -j RETURN >/dev/null 2>&1 || { route_fail "LAN scope"; return 5; }

    for n in 0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4; do
        iptables -t mangle -A "$HY2_CHAIN" -d "$n" -j RETURN >/dev/null 2>&1 || { route_fail "private exclusion"; return 5; }
    done

    if [ "$mode" = smart ]; then
        ipset -! create "$HY2_VPN_IPSET" hash:net family inet >/dev/null 2>&1 || { route_fail "VPN ipset"; return 5; }
        ipset -! create "$HY2_DIRECT_IPSET" hash:net family inet >/dev/null 2>&1 || { route_fail "direct ipset"; return 5; }
        iptables -t mangle -A "$HY2_CHAIN" -m set --match-set "$HY2_DIRECT_IPSET" dst -j RETURN >/dev/null 2>&1 || { route_fail "direct ipset bypass"; return 5; }
        iptables -t mangle -A "$HY2_CHAIN" -p tcp -m set --match-set "$HY2_VPN_IPSET" dst -j TPROXY --on-port "$HY2_PORT" --tproxy-mark "$HY2_MARK/$HY2_MASK" >/dev/null 2>&1 || { route_fail "TCP TPROXY"; return 5; }
        iptables -t mangle -A "$HY2_CHAIN" -p udp -m set --match-set "$HY2_VPN_IPSET" dst -j TPROXY --on-port "$HY2_PORT" --tproxy-mark "$HY2_MARK/$HY2_MASK" >/dev/null 2>&1 || { route_fail "UDP TPROXY"; return 5; }
    else
        iptables -t mangle -A "$HY2_CHAIN" -p tcp -j TPROXY --on-port "$HY2_PORT" --tproxy-mark "$HY2_MARK/$HY2_MASK" >/dev/null 2>&1 || { route_fail "TCP TPROXY"; return 5; }
        iptables -t mangle -A "$HY2_CHAIN" -p udp -j TPROXY --on-port "$HY2_PORT" --tproxy-mark "$HY2_MARK/$HY2_MASK" >/dev/null 2>&1 || { route_fail "UDP TPROXY"; return 5; }
    fi

    mkdir_runtime || { route_fail "runtime"; return 5; }
    printf 'MODE=%s\nLAN_IF=%s\nPORT=%s\nMARK=%s\nTABLE=%s\n' "$mode" "$lan" "$HY2_PORT" "$HY2_MARK" "$HY2_TABLE" > "$HY2_ROUTE_STATE"
    chmod 0600 "$HY2_ROUTE_STATE" 2>/dev/null || true
    token="$(make_token)" || { route_fail "rollback token"; return 5; }
    printf '%s\n' "$token" > "$HY2_CONFIRM_TOKEN"
    chmod 0600 "$HY2_CONFIRM_TOKEN" 2>/dev/null || true
    (
        sleep "$HY2_ROLLBACK_TIMEOUT"
        [ -f "$HY2_CONFIRM_TOKEN" ] || exit 0
        route_cleanup_no_guard >/dev/null 2>&1 || true
        log "hy2: unconfirmed TPROXY rules auto-rolled back"
    ) >/dev/null 2>&1 &
    printf '%s\n' $! > "$HY2_GUARD_PID"
    printf 'HY2_ROUTE_PENDING_CONFIRM=1\nMODE=%s\nROLLBACK_IN=%s\nCONFIRM_TOKEN=%s\n' "$mode" "$HY2_ROLLBACK_TIMEOUT" "$token"
}

route_confirm() {
    supplied="${1:-}"
    [ -f "$HY2_CONFIRM_TOKEN" ] || { echo "NO_HY2_ROUTE_PENDING=1"; return 1; }
    expected="$(cat "$HY2_CONFIRM_TOKEN" 2>/dev/null || true)"
    [ -n "$supplied" ] && [ "$supplied" = "$expected" ] || { echo "invalid confirmation token" >&2; return 2; }
    kill_guard
    rm -f "$HY2_CONFIRM_TOKEN"
    printf 'HY2_ROUTE_CONFIRMED=1\n'
}

status() {
    if engine_alive; then eng=running; else eng=stopped; fi
    if [ -f "$HY2_ROUTE_STATE" ]; then route=armed; else route=off; fi
    m_core=missing; m_sock=missing; m_tproxy=missing
    is_loaded nf_tproxy_core && m_core=loaded
    is_loaded xt_socket && m_sock=loaded
    is_loaded xt_TPROXY && m_tproxy=loaded
    cached=0; sha_ok "$HY2_ENGINE" && cached=1 || true
    printf 'HY2_ENGINE=%s\nHY2_ROUTE=%s\nENGINE_VERIFIED=%s\nNF_TPROXY_CORE=%s\nXT_SOCKET=%s\nXT_TPROXY=%s\n' \
      "$eng" "$route" "$cached" "$m_core" "$m_sock" "$m_tproxy"
    [ -f "$HY2_ROUTE_STATE" ] && cat "$HY2_ROUTE_STATE"
    [ -f "$HY2_CONFIRM_TOKEN" ] && printf 'HY2_ROUTE_PENDING_CONFIRM=1\n' || true
}

case "${1:-status}" in
  status) status ;;
  prepare) load_modules && fetch_engine && status ;;
  check-uri) shift; fetch_engine && validate_uri_file "${1:-}" ;;
  start) shift; engine_start "${1:-}" ;;
  stop) route_off >/dev/null 2>&1 || true; engine_stop; status ;;
  route-on|arm) shift; route_arm "${1:-smart}" ;;
  confirm) shift; route_confirm "${1:-}" ;;
  route-off) route_off; status ;;
  purge-runtime) route_off >/dev/null 2>&1 || true; engine_stop; rm -rf "$HY2_RUNTIME"; printf 'HY2_RUNTIME_PURGED=1\n' ;;
  *)
    echo "usage: hy2-tproxy.sh {status|prepare|check-uri <0600-uri>|start <0600-uri>|arm <smart|vpn-all>|confirm <token>|route-off|stop|purge-runtime}" >&2
    exit 2
    ;;
esac
