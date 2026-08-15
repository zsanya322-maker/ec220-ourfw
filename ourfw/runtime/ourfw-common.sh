#!/bin/sh

OURFW=/etc/storage/ourfw
STATE=/tmp/ourfw
LOG=/tmp/ourfw.log
# Generated runtime files are intentionally volatile: do not waste 128 KiB Storage.
GEN="$STATE/generated"
GLOBAL="$OURFW/config/global.conf"
mkdir -p "$STATE" "$GEN" 2>/dev/null

log() {
    logger -t OURFW -- "$*" 2>/dev/null
    [ -d "$STATE" ] && printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$*" >> "$LOG"
}

need() {
    command -v "$1" >/dev/null 2>&1 || { log "missing tool: $1"; return 1; }
}

safe_id() {
    case "$1" in ''|*[!A-Za-z0-9._-]*) return 1;; *) return 0;; esac
}

is_uint() {
    case "$1" in ''|*[!0-9]*) return 1;; *) return 0;; esac
}

bool01() {
    [ "$1" = "0" ] || [ "$1" = "1" ]
}

load_conf() {
    # Strict key=value parser. Never source mutable configuration: even a tiny
    # WebUI validation bug must not turn a config value into shell execution.
    f="$1"
    [ -f "$f" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        line=$(printf '%s' "$line" | tr -d '\r')
        # trim outer whitespace; comments are full-line only by design
        line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        case "$line" in ''|'#'*) continue;; esac
        case "$line" in
          *=*) key=${line%%=*}; val=${line#*=} ;;
          *) log "invalid config line in $f: $line"; return 1 ;;
        esac
        case "$key" in ''|*[!A-Za-z0-9_]*) log "invalid config key in $f: $key"; return 1;; esac
        case "$key" in [0-9]*) log "invalid config key in $f: $key"; return 1;; esac
        # Current OURFW .conf files deliberately use no spaces/quotes. This
        # whitelist permits paths, IPv4/IPv6-ish values, CSV and hex marks.
        case "$val" in *[!A-Za-z0-9_./,:@%+=?+-]*)
            log "unsafe config value rejected in $f: $key"; return 1;;
        esac
        export "$key=$val"
    done < "$f"
}

conf_set() {
    # conf_set FILE KEY VALUE -- atomically update a strict mutable key=value file.
    f="$1"; key="$2"; val="$3"
    case "$key" in ''|*[!A-Za-z0-9_]*) return 1;; esac
    case "$key" in [0-9]*) return 1;; esac
    case "$val" in *[!A-Za-z0-9_./,:@%+=?+-]*) return 1;; esac
    [ -f "$f" ] || return 1
    tmp="$STATE/conf-set.$$"
    awk -v k="$key" -v v="$val" '
      BEGIN{done=0}
      $0 ~ "^[[:space:]]*" k "=" { if(!done){print k "=" v; done=1}; next }
      {print}
      END{if(!done) print k "=" v}
    ' "$f" > "$tmp" || { rm -f "$tmp"; return 1; }
    mv "$tmp" "$f"
}

load_global() {
    OURFW_ENABLED=1
    ROLLBACK_TIMEOUT=90
    HISTORY_KEEP=2
    LOG_LEVEL=1
    [ -f "$GLOBAL" ] && load_conf "$GLOBAL" || return 1
    bool01 "${OURFW_ENABLED:-1}" || return 1
    is_uint "${ROLLBACK_TIMEOUT:-90}" || return 1
    is_uint "${HISTORY_KEEP:-2}" || return 1
}

save_storage() {
    /sbin/mtd_storage.sh save >/tmp/ourfw-storage-save.log 2>&1
}

wan_if() {
    v=""
    command -v nvram >/dev/null 2>&1 && v="$(nvram get wan0_ifname 2>/dev/null)"
    [ -n "$v" ] || v="$(ip -4 route show default 2>/dev/null | awk '/^default/{for(i=1;i<=NF;i++)if($i=="dev"){print $(i+1); exit}}')"
    [ -n "$v" ] || v="$(route -n 2>/dev/null | awk '$1=="0.0.0.0"{print $8; exit}')"
    printf '%s\n' "$v"
}

lan_if() {
    v=""
    command -v nvram >/dev/null 2>&1 && v="$(nvram get lan_ifname 2>/dev/null)"
    [ -n "$v" ] || v=br0
    printf '%s\n' "$v"
}

iface_exists() {
    [ -n "$1" ] && ip link show dev "$1" >/dev/null 2>&1
}

pid_alive() {
    [ -f "$1" ] || return 1
    p="$(cat "$1" 2>/dev/null)"
    is_uint "$p" || return 1
    kill -0 "$p" 2>/dev/null
}

kill_pidfile() {
    pf="$1"
    if pid_alive "$pf"; then
        p="$(cat "$pf")"
        kill "$p" 2>/dev/null || true
        n=0
        while kill -0 "$p" 2>/dev/null && [ "$n" -lt 5 ]; do sleep 1; n=$((n+1)); done
        kill -9 "$p" 2>/dev/null || true
    fi
    rm -f "$pf"
}


TXN_LOCK="$STATE/txn.lock"
txn_lock_acquire() {
    tries=0
    while [ "$tries" -lt 2 ]; do
        if mkdir "$TXN_LOCK" 2>/dev/null; then
            printf '%s\n' "$$" > "$TXN_LOCK/pid"
            return 0
        fi
        owner="$(cat "$TXN_LOCK/pid" 2>/dev/null || true)"
        if is_uint "$owner" && kill -0 "$owner" 2>/dev/null; then
            return 1
        fi
        log "transaction: removing stale lock owner=${owner:-unknown}"
        rm -rf "$TXN_LOCK" 2>/dev/null || return 1
        tries=$((tries+1))
    done
    return 1
}

txn_lock_release() {
    [ -d "$TXN_LOCK" ] || return 0
    owner="$(cat "$TXN_LOCK/pid" 2>/dev/null || true)"
    [ "$owner" = "$$" ] || [ "${OURFW_LOCK_HELD:-0}" = "1" ] || return 1
    rm -rf "$TXN_LOCK"
}

strip_list() {
    # Output non-empty, non-comment lines with leading/trailing whitespace removed.
    [ -f "$1" ] || return 0
    sed 's/[[:space:]]*#.*$//; s/^[[:space:]]*//; s/[[:space:]]*$//' "$1" | sed '/^$/d'
}

active_vpn_type() {
    t="$(cat "$STATE/vpn-type" 2>/dev/null || true)"
    if [ -z "$t" ] && [ -f "$OURFW/config/vpn.conf" ]; then
        VPN_TYPE=wireguard
        load_conf "$OURFW/config/vpn.conf" >/dev/null 2>&1 || true
        t="${VPN_TYPE:-wireguard}"
    fi
    printf '%s\n' "${t:-wireguard}"
}

active_vpn_if() {
    i="$(cat "$STATE/vpn-interface" 2>/dev/null || true)"
    if [ -z "$i" ] && [ -f "$OURFW/config/vpn.conf" ]; then
        VPN_INTERFACE=wg0
        load_conf "$OURFW/config/vpn.conf" >/dev/null 2>&1 || true
        i="${VPN_INTERFACE:-wg0}"
    fi
    printf '%s\n' "${i:-wg0}"
}

managed_block() {
    # managed_block file tag content-file
    file="$1"; tag="$2"; src="$3"
    begin="# OURFW:$tag BEGIN"
    end="# OURFW:$tag END"
    tmp="/tmp/ourfw-managed.$$"
    [ -f "$file" ] || { mkdir -p "$(dirname "$file")"; : > "$file"; }
    awk -v b="$begin" -v e="$end" '
        $0==b {skip=1; next}
        $0==e {skip=0; next}
        !skip {print}
    ' "$file" > "$tmp" || return 1
    {
        cat "$tmp"
        printf '\n%s\n' "$begin"
        cat "$src"
        printf '%s\n' "$end"
    } > "${tmp}.2" || return 1
    mv "${tmp}.2" "$file"
    rm -f "$tmp"
}

remove_managed_block() {
    file="$1"; tag="$2"
    [ -f "$file" ] || return 0
    begin="# OURFW:$tag BEGIN"
    end="# OURFW:$tag END"
    tmp="/tmp/ourfw-managed.$$"
    awk -v b="$begin" -v e="$end" '
        $0==b {skip=1; next}
        $0==e {skip=0; next}
        !skip {print}
    ' "$file" > "$tmp" && mv "$tmp" "$file"
}

hook_install() {
    # Keep OURFW behind Padavan's native lifecycle rather than replacing rc.
    # The Internet Detector hook supplies multi-target TCP state transitions.
    p1=/etc/storage/post_iptables_script.sh
    p2=/etc/storage/post_wan_script.sh
    p3=/etc/storage/inet_state_script.sh
    s1="$STATE/hook-firewall.$$"
    s2="$STATE/hook-wan.$$"
    s3="$STATE/hook-internet.$$"
    cat > "$s1" <<'EOT'
[ -x /etc/storage/ourfw/runtime/ourfwctl.sh ] && /etc/storage/ourfw/runtime/ourfwctl.sh event firewall >/dev/null 2>&1 &
EOT
    cat > "$s2" <<'EOT'
[ -x /etc/storage/ourfw/runtime/ourfwctl.sh ] && /etc/storage/ourfw/runtime/ourfwctl.sh event wan "$@" >/dev/null 2>&1 &
EOT
    cat > "$s3" <<'EOT'
_ourfw_inet="$(nvram get link_internet 2>/dev/null || true)"
[ -x /etc/storage/ourfw/runtime/ourfwctl.sh ] && /etc/storage/ourfw/runtime/ourfwctl.sh event internet "$_ourfw_inet" "$@" >/dev/null 2>&1 &
EOT
    managed_block "$p1" HOOK_FIREWALL "$s1"
    managed_block "$p2" HOOK_WAN "$s2"
    managed_block "$p3" HOOK_INTERNET "$s3"
    chmod 755 "$p1" "$p2" "$p3" 2>/dev/null
    rm -f "$s1" "$s2" "$s3"
}

json_escape() {
    # Minimal JSON string escape for status output.
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g'
}

candidate_conf_set() {
    # candidate_conf_set FILE KEY VALUE TAG
    f="$1"; key="$2"; val="$3"; tag="$4"
    [ -f "$f" ] || return 1
    safe_id "$tag" || return 1
    tmp="$STATE/candidate-conf.$$"
    cp "$f" "$tmp" || return 1
    conf_set "$tmp" "$key" "$val" || { rm -f "$tmp"; return 1; }
    case "$f" in "$OURFW"/*) rel=${f#"$OURFW"/};; *) rm -f "$tmp"; return 1;; esac
    OURFW_CANDIDATE_SRC="$tmp" OURFW_CANDIDATE_REL="$rel" "$OURFW/runtime/ourfw-apply.sh" "$tag"
    rc=$?
    rm -f "$tmp"
    return $rc
}
