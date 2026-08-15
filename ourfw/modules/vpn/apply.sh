#!/bin/sh
# OURFW owns VPN interface creation and policy routing. Padavan native vpnc is
# kept disabled in RAM to avoid competing table/rule management.
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
CFG="$OURFW/config/vpn.conf"
VPN_ENABLED=0; VPN_TYPE=wireguard; VPN_INTERFACE=wg0; VPN_PROFILE="$OURFW/profiles/vpn.conf"
VPN_OPENVPN_PROFILE="$OURFW/profiles/openvpn.ovpn"; VPN_OPENVPN_AUTH="$OURFW/profiles/openvpn.auth"
VPN_USE_PEER_DNS=0; VPN_FAILOVER_ENABLED=0; VPN_FAILOVER_TYPE=openvpn
load_conf "$CFG" || exit 1
bool01 "$VPN_ENABLED" || exit 1; bool01 "$VPN_USE_PEER_DNS" || exit 1; bool01 "$VPN_FAILOVER_ENABLED" || exit 1
case "$VPN_TYPE" in wireguard|amneziawg|openvpn) ;; *) log "vpn: invalid VPN_TYPE=$VPN_TYPE"; exit 1;; esac
case "$VPN_FAILOVER_TYPE" in wireguard|amneziawg|openvpn) ;; *) log "vpn: invalid failover type"; exit 1;; esac
case "$VPN_INTERFACE" in ''|*[!A-Za-z0-9_.-]*) exit 1;; esac
[ ${#VPN_INTERFACE} -le 15 ] || exit 1

profile_get() {
    sec="$1"; key="$2"; file="$3"
    awk -v want_sec="$sec" -v want_key="$key" '
      /^[[:space:]]*\[/ {s=$0; gsub(/[[:space:]\[\]]/, "", s); cur=s; next}
      cur==want_sec {line=$0; sub(/[[:space:]]*[#;].*$/, "", line); p=index(line,"="); if(!p) next;
        k=substr(line,1,p-1); v=substr(line,p+1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", k); gsub(/^[[:space:]]+|[[:space:]]+$/, "", v);
        if(k==want_key){print v; exit}}' "$file"
}

stop_openvpn() {
    pf="$STATE/openvpn.pid"
    if [ -f "$pf" ]; then
        p="$(cat "$pf" 2>/dev/null || true)"
        if is_uint "$p" && kill -0 "$p" 2>/dev/null; then
            kill "$p" 2>/dev/null || true; n=0
            while kill -0 "$p" 2>/dev/null && [ "$n" -lt 8 ]; do sleep 1; n=$((n+1)); done
            kill -9 "$p" 2>/dev/null || true
        fi
    fi
    rm -f "$pf"
    iface_exists tun0 && ip link del dev tun0 >/dev/null 2>&1 || true
}

remove_wg_iface() {
    i="$1"
    case "$i" in ''|tun0) return 0;; esac
    iface_exists "$i" && ip link del dev "$i" >/dev/null 2>&1 || true
}

stop_ourfw_vpn() {
    old_if="$(cat "$STATE/vpn-interface" 2>/dev/null || true)"
    stop_openvpn
    remove_wg_iface "$old_if"
    [ "$VPN_INTERFACE" = "$old_if" ] || remove_wg_iface "$VPN_INTERFACE"
    # v0.6.0 used wg0 unconditionally, so clean a stale legacy interface too.
    [ "$old_if" = wg0 ] || [ "$VPN_INTERFACE" = wg0 ] || remove_wg_iface wg0
    rm -f "$STATE/vpn-endpoint4" "$STATE/vpn-endpoint6" "$STATE/vpn-dns" "$STATE/vpn-type" "$STATE/vpn-interface"
}

resolve4() {
    h="$1"
    case "$h" in *[!0-9.]*) ;; *) printf '%s\n' "$h"; return 0;; esac
    ping -c1 -W1 "$h" 2>/dev/null | sed -n '1{s/.*(\([0-9][0-9.]*\)).*/\1/p;s/^PING[[:space:]][^[:space:]]*[[:space:]]\([0-9][0-9.]*\).*/\1/p;}' | head -n1
}

resolve6() {
    h="$1"
    case "$h" in *:*) printf '%s\n' "$h"; return 0;; esac
    command -v ping6 >/dev/null 2>&1 || return 0
    ping6 -c1 -W1 "$h" 2>/dev/null | sed -n '1{s/.*(\([0-9A-Fa-f:][0-9A-Fa-f:]*\)).*/\1/p;s/^PING[[:space:]][^[:space:]]*[[:space:]]\([0-9A-Fa-f:][0-9A-Fa-f:]*\).*/\1/p;}' | head -n1
}

cache_openvpn_endpoint() {
    hosts="$STATE/openvpn-remote-hosts.$$"; t4="$STATE/vpn-endpoint4.tmp.$$"; t6="$STATE/vpn-endpoint6.tmp.$$"
    awk 'BEGIN{IGNORECASE=1} /^[[:space:]]*#/||/^[[:space:]]*;/ {next} tolower($1)=="remote" {print $2}' "$VPN_OPENVPN_PROFILE" 2>/dev/null | sort -u > "$hosts"
    : > "$t4"; : > "$t6"
    while IFS= read -r host; do
        [ -n "$host" ] || continue
        ip4="$(resolve4 "$host")"
        case "$ip4" in ''|*[!0-9.]*) ;; *) printf '%s\n' "$ip4" >> "$t4";; esac
        ip6="$(resolve6 "$host")"
        case "$ip6" in *:*) case "$ip6" in *[!0-9A-Fa-f:]*) ;; *) printf '%s\n' "$ip6" >> "$t6";; esac;; esac
    done < "$hosts"
    rm -f "$hosts"
    sort -u "$t4" -o "$t4" 2>/dev/null || true; sort -u "$t6" -o "$t6" 2>/dev/null || true
    if [ -s "$t4" ]; then mv "$t4" "$STATE/vpn-endpoint4"; else rm -f "$t4" "$STATE/vpn-endpoint4"; fi
    if [ -s "$t6" ]; then mv "$t6" "$STATE/vpn-endpoint6"; else rm -f "$t6" "$STATE/vpn-endpoint6"; fi
}

validate_auth_file() {
    [ -f "$VPN_OPENVPN_AUTH" ] || return 1
    lines="$(grep -vc '^[[:space:]]*$' "$VPN_OPENVPN_AUTH" 2>/dev/null || echo 0)"
    [ "$lines" -eq 2 ] 2>/dev/null
}

make_openvpn_config() {
    src="$VPN_OPENVPN_PROFILE"; out="$STATE/openvpn.conf"
    [ -s "$src" ] || { log "vpn: OpenVPN profile missing"; return 1; }
    : > "$out" || return 1
    inblock=0; blocktag=
    while IFS= read -r line || [ -n "$line" ]; do
        trim="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        lower="$(printf '%s' "$trim" | tr 'A-Z' 'a-z')"
        if [ "$inblock" = 1 ]; then
            if [ "$lower" = "</$blocktag>" ]; then inblock=0; blocktag=; fi
            printf '%s\n' "$line" >> "$out"
            continue
        fi
        case "$lower" in
          '<ca>'|'<cert>'|'<key>'|'<pkcs12>'|'<tls-auth>'|'<tls-crypt>'|'<tls-crypt-v2>'|'<crl-verify>')
            blocktag="$(printf '%s' "$lower" | tr -d '<>')"; inblock=1
            printf '%s\n' "$line" >> "$out"; continue;;
          '</'*) log "vpn: unexpected OpenVPN inline block close: $lower"; rm -f "$out"; return 1;;
          '<'*'>') log "vpn: unsupported OpenVPN inline block rejected: $lower"; rm -f "$out"; return 1;;
        esac
        case "$trim" in ''|'#'*|';'*) printf '%s\n' "$line" >> "$out"; continue;; esac
        key="$(printf '%s\n' "$trim" | awk '{print tolower($1)}')"
        case "$key" in
          up|down|route-up|route-pre-down|ipchange|client-connect|client-disconnect|learn-address|auth-user-pass-verify|plugin|script-security|management|management-client-user|management-client-group|config|cd|chroot|daemon|writepid|log|log-append|status|user|group)
            log "vpn: unsafe OpenVPN directive rejected: $key"; rm -f "$out"; return 1;;
          dev|dev-type|route|route-ipv6|redirect-gateway|redirect-private|route-gateway|route-metric|route-delay|route-noexec|route-nopull)
            continue;;
          ca|cert|key|pkcs12|tls-auth|tls-crypt|tls-crypt-v2|crl-verify)
            log "vpn: external OpenVPN file directive rejected: $key (use inline block)"; rm -f "$out"; return 1;;
          auth-user-pass)
            if validate_auth_file; then printf 'auth-user-pass %s\n' "$VPN_OPENVPN_AUTH" >> "$out"; else log "vpn: auth-user-pass requires a two-line OURFW auth file"; rm -f "$out"; return 1; fi
            ;;
          *) printf '%s\n' "$line" >> "$out";;
        esac
    done < "$src"
    [ "$inblock" = 0 ] || { log "vpn: unterminated OpenVPN inline block <$blocktag>"; rm -f "$out"; return 1; }
    cat >> "$out" <<EOT
dev tun0
dev-type tun
route-noexec
script-security 0
auth-nocache
pull-filter ignore "redirect-gateway"
pull-filter ignore "route"
EOT
    chmod 600 "$out" 2>/dev/null || true
}

start_openvpn() {
    OVPN=/usr/sbin/openvpn
    [ -x "$OVPN" ] || { log "vpn: OpenVPN binary missing"; return 1; }
    make_openvpn_config || return 1
    cache_openvpn_endpoint
    rm -f "$STATE/openvpn.pid" "$STATE/openvpn.log"
    "$OVPN" --config "$STATE/openvpn.conf" --daemon ourfw-openvpn --writepid "$STATE/openvpn.pid" --log-append "$STATE/openvpn.log" >/dev/null 2>&1 || { log "vpn: OpenVPN launch failed"; return 1; }
    n=0
    while [ "$n" -lt 20 ]; do
        iface_exists tun0 && break
        [ -f "$STATE/openvpn.pid" ] || break
        sleep 1; n=$((n+1))
    done
    iface_exists tun0 || { log "vpn: OpenVPN tun0 did not appear"; stop_openvpn; return 1; }
    if [ "$VPN_USE_PEER_DNS" = 1 ]; then
        awk 'BEGIN{IGNORECASE=1} tolower($1)=="dhcp-option" && toupper($2)=="DNS" {print $3}' "$VPN_OPENVPN_PROFILE" | paste -sd, - > "$STATE/vpn-dns" 2>/dev/null || true
        [ -s "$STATE/vpn-dns" ] || rm -f "$STATE/vpn-dns"
    fi
    printf '%s\n' openvpn > "$STATE/vpn-type"; printf '%s\n' tun0 > "$STATE/vpn-interface"
    log "vpn: OpenVPN ready on tun0"
}

start_wg_family() {
    type="$1"; profile="$VPN_PROFILE"; [ -f "$profile" ] || { log "vpn: profile not found: $profile"; return 1; }
    chmod 600 "$profile" 2>/dev/null || true; need ip || return 1
    addr="$(profile_get Interface Address "$profile")"; priv="$(profile_get Interface PrivateKey "$profile")"; dns="$(profile_get Interface DNS "$profile")"
    mtu="$(profile_get Interface MTU "$profile")"; pub="$(profile_get Peer PublicKey "$profile")"; psk="$(profile_get Peer PresharedKey "$profile")"
    endpoint="$(profile_get Peer Endpoint "$profile")"; keep="$(profile_get Peer PersistentKeepalive "$profile")"; allowed="$(profile_get Peer AllowedIPs "$profile")"
    [ -n "$addr" ] && [ -n "$priv" ] && [ -n "$pub" ] && [ -n "$endpoint" ] && [ -n "$allowed" ] || { log "vpn: WG/AWG profile incomplete"; return 1; }
    [ -n "$mtu" ] || mtu=1420; [ -n "$keep" ] || keep=25
    is_uint "$mtu" || { log "vpn: invalid MTU"; return 1; }
    is_uint "$keep" || { log "vpn: invalid keepalive"; return 1; }
    [ "$mtu" -ge 576 ] 2>/dev/null && [ "$mtu" -le 9000 ] 2>/dev/null || { log "vpn: MTU out of range"; return 1; }
    [ "$keep" -le 65535 ] 2>/dev/null || { log "vpn: keepalive out of range"; return 1; }
    for v in "$priv" "$pub" "$psk" "$endpoint" "$allowed"; do
        case "$v" in *'`'*|*'$('*|*';'*|*'|'*|*'&'*) log "vpn: unsafe WG/AWG profile value"; return 1;; esac
    done
    TMP="$STATE/vpn-setconf.$$"; rm -f "$TMP"
    { echo '[Interface]'; printf 'PrivateKey = %s\n' "$priv"
      if [ "$type" = amneziawg ]; then
        for k in Jc Jmin Jmax S1 S2 H1 H2 H3 H4; do v="$(profile_get Interface "$k" "$profile")"; [ -n "$v" ] || continue; is_uint "$v" || return 1; printf '%s = %s\n' "$k" "$v"; done
        i1="$(profile_get Interface I1 "$profile")"
        if [ -n "$i1" ]; then
            [ ${#i1} -le 512 ] || { log "vpn: AWG I1 too long"; rm -f "$TMP"; return 1; }
            case "$i1" in *[!0-9A-Fa-fxXbB\<\>\ ,]*) log "vpn: invalid AWG I1"; rm -f "$TMP"; return 1;; esac
            printf 'I1 = %s\n' "$i1"
        fi
      fi
      echo '[Peer]'; printf 'PublicKey = %s\n' "$pub"; [ -z "$psk" ] || printf 'PresharedKey = %s\n' "$psk"
      printf 'Endpoint = %s\nPersistentKeepalive = %s\nAllowedIPs = %s\n' "$endpoint" "$keep" "$allowed"
    } > "$TMP" || return 1
    chmod 600 "$TMP" 2>/dev/null || true
    if [ "$type" = wireguard ]; then WG=/usr/sbin/wg; mod=wireguard; linktype=wireguard; else WG=/usr/sbin/awg; mod=amneziawg; linktype=amneziawg; fi
    [ -x "$WG" ] || { rm -f "$TMP"; return 1; }
    HANDOFF="$OURFW/modules/vpn/module-handoff.sh"
    [ -x "$HANDOFF" ] || { log "vpn: WG/AWG module handoff helper missing"; rm -f "$TMP"; return 1; }
    "$HANDOFF" "$mod" || { log "vpn: WG/AWG kernel module handoff failed for $mod"; rm -f "$TMP"; return 1; }
    ip link add dev "$VPN_INTERFACE" type "$linktype" >/tmp/ourfw-vpn-start.log 2>&1 || { rm -f "$TMP"; return 1; }
    ok=1; OLDIFS=$IFS; IFS=','
    for a in $addr; do IFS=$OLDIFS; a="$(printf '%s' "$a" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"; [ -n "$a" ] || continue; case "$a" in *:*) fam=-6;; *) fam=-4;; esac; ip $fam addr add "$a" dev "$VPN_INTERFACE" >/dev/null 2>&1 || ok=0; IFS=','; done
    IFS=$OLDIFS; [ "$ok" = 1 ] || { rm -f "$TMP"; return 1; }
    ip link set dev "$VPN_INTERFACE" mtu "$mtu" >/dev/null 2>&1 || return 1
    "$WG" setconf "$VPN_INTERFACE" "$TMP" >/tmp/ourfw-vpn-setconf.log 2>&1 || { rm -f "$TMP"; return 1; }; rm -f "$TMP"
    ip link set dev "$VPN_INTERFACE" up >/dev/null 2>&1 || return 1
    ep="$($WG show "$VPN_INTERFACE" endpoints 2>/dev/null | awk 'NR==1{print $2}')"
    ep4="$(printf '%s' "$ep" | sed -n 's/^\([0-9][0-9.]*\):[0-9][0-9]*$/\1/p')"; ep6="$(printf '%s' "$ep" | sed -n 's/^\[\([^]]*\)\]:[0-9][0-9]*$/\1/p')"
    [ -n "$ep4" ] && printf '%s\n' "$ep4" > "$STATE/vpn-endpoint4" || true; [ -n "$ep6" ] && printf '%s\n' "$ep6" > "$STATE/vpn-endpoint6" || true
    if [ "$VPN_USE_PEER_DNS" = 1 ] && [ -n "$dns" ]; then printf '%s\n' "$dns" > "$STATE/vpn-dns"; fi
    printf '%s\n' "$type" > "$STATE/vpn-type"; printf '%s\n' "$VPN_INTERFACE" > "$STATE/vpn-interface"
    log "vpn: $type ready on $VPN_INTERFACE"
}

# OURFW remains removable: do not commit Padavan native VPN-client state.
command -v nvram >/dev/null 2>&1 && nvram set vpnc_enable=0 >/dev/null 2>&1 || true
if [ "$VPN_ENABLED" = 0 ]; then stop_ourfw_vpn; rm -f "$STATE/vpn-override-type"; log "vpn: disabled"; exit 0; fi

type="$VPN_TYPE"
if [ "$VPN_FAILOVER_ENABLED" = 1 ] && [ -s "$STATE/vpn-override-type" ]; then
    ov="$(cat "$STATE/vpn-override-type" 2>/dev/null || true)"; case "$ov" in wireguard|amneziawg|openvpn) type="$ov";; esac
fi
stop_ourfw_vpn
case "$type" in
  wireguard|amneziawg) start_wg_family "$type" || { stop_ourfw_vpn; exit 1; } ;;
  openvpn) start_openvpn || { stop_ourfw_vpn; exit 1; } ;;
esac
exit 0
