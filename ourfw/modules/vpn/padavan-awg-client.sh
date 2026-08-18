#!/bin/sh
# OURFW Padavan-native AmneziaWG transport dataplane.
# Based on the traffic model used by padavan-ng amneziawg/client.sh:
# transport fwmark, dedicated table, src_valid_mark, UDP CONNMARK,
# VPN SNAT and TCP MSS clamping. OURFW Smart Routing remains the policy layer.
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1

CFG="$OURFW/config/vpn.conf"
VPN_ENABLED=0
VPN_TYPE=amneziawg
VPN_INTERFACE=wg0
VPN_PROFILE="$OURFW/profiles/vpn.conf"
VPN_USE_PEER_DNS=0
load_conf "$CFG" || exit 1

AWG=/usr/sbin/awg
HANDOFF="$OURFW/modules/vpn/module-handoff.sh"
TRANSPORT_MARK=51820
TRANSPORT_TABLE=51820
PRE_CHAIN=OURFW_AWG_PRE
POST_CHAIN=OURFW_AWG_POST
NAT_CHAIN=OURFW_AWG_NAT
MSS_CHAIN=OURFW_AWG_MSS

ipt_del_jump() {
    while iptables "$@" >/dev/null 2>&1; do :; done
}

profile_get() {
    sec="$1"; key="$2"; file="$3"
    awk -v want_sec="$sec" -v want_key="$key" '
      /^[[:space:]]*\[/ {
        s=$0
        sub(/^[[:space:]]*\[/, "", s)
        sub(/\][[:space:]]*$/, "", s)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
        cur=s
        next
      }
      cur==want_sec {
        line=$0
        sub(/[[:space:]]*[#;].*$/, "", line)
        p=index(line,"=")
        if(!p) next
        k=substr(line,1,p-1)
        v=substr(line,p+1)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        if(k==want_key){print v; exit}
      }' "$file"
}

cleanup_transport_rules() {
    ipt_del_jump -t mangle -D PREROUTING -j "$PRE_CHAIN"
    ipt_del_jump -t mangle -D POSTROUTING -j "$POST_CHAIN"
    ipt_del_jump -t nat -D POSTROUTING -j "$NAT_CHAIN"
    ipt_del_jump -t mangle -D FORWARD -j "$MSS_CHAIN"
    while iptables -D INPUT -i "$VPN_INTERFACE" -j ACCEPT >/dev/null 2>&1; do :; done

    iptables -t mangle -F "$PRE_CHAIN" >/dev/null 2>&1 || true
    iptables -t mangle -X "$PRE_CHAIN" >/dev/null 2>&1 || true
    iptables -t mangle -F "$POST_CHAIN" >/dev/null 2>&1 || true
    iptables -t mangle -X "$POST_CHAIN" >/dev/null 2>&1 || true
    iptables -t nat -F "$NAT_CHAIN" >/dev/null 2>&1 || true
    iptables -t nat -X "$NAT_CHAIN" >/dev/null 2>&1 || true
    iptables -t mangle -F "$MSS_CHAIN" >/dev/null 2>&1 || true
    iptables -t mangle -X "$MSS_CHAIN" >/dev/null 2>&1 || true

    ip route flush table "$TRANSPORT_TABLE" >/dev/null 2>&1 || true
}

client_ipv4() {
    ip -4 addr show dev "$VPN_INTERFACE" 2>/dev/null |
        awk '/[[:space:]]inet[[:space:]]/{split($2,a,"/"); print a[1]; exit}'
}

apply_transport_rules() {
    iface_exists "$VPN_INTERFACE" || { log "awg-native: interface $VPN_INTERFACE missing"; return 1; }
    [ -x "$AWG" ] || { log "awg-native: awg tool missing"; return 1; }

    addr4="$(client_ipv4)"
    case "$addr4" in ''|*[!0-9.]*) log "awg-native: IPv4 client address missing"; return 1;; esac

    cleanup_transport_rules

    "$AWG" set "$VPN_INTERFACE" fwmark "$TRANSPORT_MARK" >/tmp/ourfw-awg-fwmark.log 2>&1 ||
        { log "awg-native: cannot set transport fwmark"; return 1; }

    ip route add default dev "$VPN_INTERFACE" table "$TRANSPORT_TABLE" >/dev/null 2>&1 ||
    ip route replace default dev "$VPN_INTERFACE" table "$TRANSPORT_TABLE" >/dev/null 2>&1 ||
        { log "awg-native: cannot create transport table"; return 1; }

    if have_exec sysctl; then
        sysctl -q net.ipv4.conf.all.src_valid_mark=1 >/dev/null 2>&1 || true
    elif [ -w /proc/sys/net/ipv4/conf/all/src_valid_mark ]; then
        echo 1 > /proc/sys/net/ipv4/conf/all/src_valid_mark 2>/dev/null || true
    fi

    iptables -t mangle -N "$PRE_CHAIN" >/dev/null 2>&1 || return 1
    iptables -t mangle -N "$POST_CHAIN" >/dev/null 2>&1 || return 1
    iptables -t nat -N "$NAT_CHAIN" >/dev/null 2>&1 || return 1
    iptables -t mangle -N "$MSS_CHAIN" >/dev/null 2>&1 || return 1

    iptables -t mangle -I PREROUTING 1 -j "$PRE_CHAIN" >/dev/null 2>&1 || return 1
    iptables -t mangle -I POSTROUTING 1 -j "$POST_CHAIN" >/dev/null 2>&1 || return 1
    iptables -t nat -I POSTROUTING 1 -j "$NAT_CHAIN" >/dev/null 2>&1 || return 1
    iptables -t mangle -I FORWARD 1 -j "$MSS_CHAIN" >/dev/null 2>&1 || return 1
    iptables -I INPUT 1 -i "$VPN_INTERFACE" -j ACCEPT >/dev/null 2>&1 || return 1

    iptables -t mangle -A "$POST_CHAIN" -m mark --mark "$TRANSPORT_MARK" -p udp -j CONNMARK --save-mark >/dev/null 2>&1 || true
    iptables -t mangle -A "$PRE_CHAIN" -p udp -j CONNMARK --restore-mark >/dev/null 2>&1 || true

    iptables -t nat -A "$NAT_CHAIN" -o "$VPN_INTERFACE" -j SNAT --to-source "$addr4" >/dev/null 2>&1 ||
        { log "awg-native: VPN SNAT failed"; cleanup_transport_rules; return 1; }

    iptables -t mangle -A "$MSS_CHAIN" -o "$VPN_INTERFACE" -p tcp -m tcp --tcp-flags SYN,RST SYN \
        -j TCPMSS --clamp-mss-to-pmtu >/dev/null 2>&1 || true

    printf '%s\n' "$TRANSPORT_MARK" > "$STATE/awg-transport-mark"
    printf '%s\n' "$TRANSPORT_TABLE" > "$STATE/awg-transport-table"
    log "awg-native: transport ready if=$VPN_INTERFACE mark=$TRANSPORT_MARK table=$TRANSPORT_TABLE snat=$addr4"
    return 0
}

stop_openvpn_if_any() {
    pf="$STATE/openvpn.pid"
    if [ -f "$pf" ]; then
        p="$(cat "$pf" 2>/dev/null || true)"
        if is_uint "${p:-}" && kill -0 "$p" 2>/dev/null; then
            kill "$p" 2>/dev/null || true
            sleep 1
            kill -9 "$p" 2>/dev/null || true
        fi
    fi
    rm -f "$pf"
    iface_exists tun0 && ip link del dev tun0 >/dev/null 2>&1 || true
}

stop_native() {
    cleanup_transport_rules
    if iface_exists "$VPN_INTERFACE"; then
        ip link del dev "$VPN_INTERFACE" >/dev/null 2>&1 || true
    fi
    rm -f "$STATE/vpn-endpoint4" "$STATE/vpn-endpoint6" "$STATE/vpn-dns" \
          "$STATE/vpn-type" "$STATE/vpn-interface" \
          "$STATE/awg-transport-mark" "$STATE/awg-transport-table"
    return 0
}

start_native() {
    [ -f "$VPN_PROFILE" ] || { log "awg-native: profile missing"; return 1; }
    [ -x "$AWG" ] || { log "awg-native: /usr/sbin/awg missing"; return 1; }
    [ -x "$HANDOFF" ] || { log "awg-native: module handoff missing"; return 1; }
    need ip || return 1
    need iptables || return 1

    addr="$(profile_get Interface Address "$VPN_PROFILE")"
    priv="$(profile_get Interface PrivateKey "$VPN_PROFILE")"
    dns="$(profile_get Interface DNS "$VPN_PROFILE")"
    mtu="$(profile_get Interface MTU "$VPN_PROFILE")"
    pub="$(profile_get Peer PublicKey "$VPN_PROFILE")"
    psk="$(profile_get Peer PresharedKey "$VPN_PROFILE")"
    endpoint="$(profile_get Peer Endpoint "$VPN_PROFILE")"
    keep="$(profile_get Peer PersistentKeepalive "$VPN_PROFILE")"
    allowed="$(profile_get Peer AllowedIPs "$VPN_PROFILE")"

    [ -n "$addr" ] && [ -n "$priv" ] && [ -n "$pub" ] && [ -n "$endpoint" ] && [ -n "$allowed" ] ||
        { log "awg-native: profile incomplete"; return 1; }
    [ -n "$mtu" ] || mtu=1420
    [ -n "$keep" ] || keep=25
    is_uint "$mtu" || return 1
    is_uint "$keep" || return 1

    for v in "$priv" "$pub" "$psk" "$endpoint" "$allowed"; do
        case "$v" in *'`'*|*'$('*|*';'*|*'|'*|*'&'*) log "awg-native: unsafe profile value"; return 1;; esac
    done

    TMP="$STATE/awg-native-setconf.$$"
    rm -f "$TMP"
    {
        echo '[Interface]'
        printf 'PrivateKey = %s\n' "$priv"
        for k in Jc Jmin Jmax S1 S2 H1 H2 H3 H4; do
            v="$(profile_get Interface "$k" "$VPN_PROFILE")"
            [ -n "$v" ] || continue
            is_uint "$v" || { rm -f "$TMP"; return 1; }
            printf '%s = %s\n' "$k" "$v"
        done
        i1="$(profile_get Interface I1 "$VPN_PROFILE")"
        if [ -n "$i1" ]; then
            [ ${#i1} -le 512 ] || { rm -f "$TMP"; return 1; }
            case "$i1" in *[!0-9A-Fa-fxXbB\<\>\ ,]*) rm -f "$TMP"; return 1;; esac
            printf 'I1 = %s\n' "$i1"
        fi
        echo '[Peer]'
        printf 'PublicKey = %s\n' "$pub"
        [ -z "$psk" ] || printf 'PresharedKey = %s\n' "$psk"
        printf 'Endpoint = %s\n' "$endpoint"
        printf 'PersistentKeepalive = %s\n' "$keep"
        printf 'AllowedIPs = %s\n' "$allowed"
    } > "$TMP" || return 1
    chmod 0600 "$TMP" 2>/dev/null || true

    stop_openvpn_if_any
    stop_native
    "$HANDOFF" amneziawg || { rm -f "$TMP"; return 1; }

    ip link add dev "$VPN_INTERFACE" type amneziawg >/tmp/ourfw-awg-native-start.log 2>&1 ||
        { rm -f "$TMP"; return 1; }

    ok=1
    OLDIFS=$IFS
    IFS=','
    for a in $addr; do
        IFS=$OLDIFS
        a="$(printf '%s' "$a" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [ -n "$a" ] || continue
        case "$a" in *:*) fam=-6;; *) fam=-4;; esac
        ip $fam addr add "$a" dev "$VPN_INTERFACE" >/dev/null 2>&1 || ok=0
        IFS=','
    done
    IFS=$OLDIFS
    [ "$ok" = 1 ] || { rm -f "$TMP"; stop_native; return 1; }

    ip link set dev "$VPN_INTERFACE" mtu "$mtu" >/dev/null 2>&1 || { rm -f "$TMP"; stop_native; return 1; }
    "$AWG" setconf "$VPN_INTERFACE" "$TMP" >/tmp/ourfw-awg-native-setconf.log 2>&1 ||
        { rm -f "$TMP"; stop_native; return 1; }
    rm -f "$TMP"
    ip link set dev "$VPN_INTERFACE" up >/dev/null 2>&1 || { stop_native; return 1; }

    ep="$("$AWG" show "$VPN_INTERFACE" endpoints 2>/dev/null | awk 'NR==1{print $2}')"
    ep4="$(printf '%s' "$ep" | sed -n 's/^\([0-9][0-9.]*\):[0-9][0-9]*$/\1/p')"
    ep6="$(printf '%s' "$ep" | sed -n 's/^\[\([^]]*\)\]:[0-9][0-9]*$/\1/p')"
    [ -n "$ep4" ] && printf '%s\n' "$ep4" > "$STATE/vpn-endpoint4" || rm -f "$STATE/vpn-endpoint4"
    [ -n "$ep6" ] && printf '%s\n' "$ep6" > "$STATE/vpn-endpoint6" || rm -f "$STATE/vpn-endpoint6"

    if [ "$VPN_USE_PEER_DNS" = 1 ] && [ -n "$dns" ]; then
        printf '%s\n' "$dns" > "$STATE/vpn-dns"
    else
        rm -f "$STATE/vpn-dns"
    fi

    printf '%s\n' amneziawg > "$STATE/vpn-type"
    printf '%s\n' "$VPN_INTERFACE" > "$STATE/vpn-interface"

    apply_transport_rules || { stop_native; return 1; }
    log "vpn: amneziawg Padavan-native ready on $VPN_INTERFACE"
    return 0
}

case "${1:-}" in
  start|restart) start_native ;;
  stop) stop_native ;;
  refresh) apply_transport_rules ;;
  status)
    iface_exists "$VPN_INTERFACE" || exit 1
    "$AWG" show "$VPN_INTERFACE" 2>/dev/null
    ;;
  *) echo "usage: $0 {start|restart|stop|refresh|status}" >&2; exit 2 ;;
esac
