#!/bin/sh
# OURFW owns interface creation and policy routing. We deliberately use only
# Padavan's compiled wg/awg tools + kernel modules and do NOT call Padavan native VPN-client orchestration, because it installs
# its own routing rules/table that would conflict with OURFW.
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
CFG="$OURFW/config/vpn.conf"
VPN_ENABLED=0; VPN_TYPE=wireguard; VPN_INTERFACE=wg0; VPN_PROFILE="$OURFW/profiles/vpn.conf"; VPN_USE_PEER_DNS=0
load_conf "$CFG" || exit 1
bool01 "$VPN_ENABLED" || exit 1
bool01 "$VPN_USE_PEER_DNS" || exit 1
case "$VPN_INTERFACE" in ''|*[!A-Za-z0-9_.-]*) log "vpn: invalid interface"; exit 1;; esac
[ ${#VPN_INTERFACE} -le 15 ] || { log "vpn: interface name too long"; exit 1; }
[ "$VPN_INTERFACE" = "wg0" ] || { log "vpn: v0.5 requires VPN_INTERFACE=wg0"; exit 1; }

profile_get() {
    sec="$1"; key="$2"; file="$3"
    awk -v want_sec="$sec" -v want_key="$key" '
      /^[[:space:]]*\[/ {
        s=$0; gsub(/[[:space:]\[\]]/, "", s); cur=s; next
      }
      cur==want_sec {
        line=$0; sub(/[[:space:]]*[#;].*$/, "", line)
        p=index(line,"="); if(!p) next
        k=substr(line,1,p-1); v=substr(line,p+1)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
        if(k==want_key){print v; exit}
      }' "$file"
}

stop_ourfw_vpn() {
    iface_exists "$VPN_INTERFACE" && ip link del dev "$VPN_INTERFACE" >/dev/null 2>&1 || true
    rm -f "$STATE/vpn-endpoint4" "$STATE/vpn-endpoint6" "$STATE/vpn-dns" "$STATE/vpn-type"
}

# Keep Padavan's own VPN-client orchestrator disabled at runtime. Do not commit
# NVRAM: OURFW remains removable and base Padavan settings survive a rescue boot.
command -v nvram >/dev/null 2>&1 && nvram set vpnc_enable=0 >/dev/null 2>&1 || true

if [ "$VPN_ENABLED" = "0" ]; then
    stop_ourfw_vpn
    log "vpn: disabled"
    exit 0
fi

[ -f "$VPN_PROFILE" ] || { log "vpn: profile not found: $VPN_PROFILE"; exit 1; }
chmod 600 "$VPN_PROFILE" 2>/dev/null || true
need ip || exit 1
need modprobe || exit 1

addr="$(profile_get Interface Address "$VPN_PROFILE")"
priv="$(profile_get Interface PrivateKey "$VPN_PROFILE")"
dns="$(profile_get Interface DNS "$VPN_PROFILE")"
mtu="$(profile_get Interface MTU "$VPN_PROFILE")"
pub="$(profile_get Peer PublicKey "$VPN_PROFILE")"
psk="$(profile_get Peer PresharedKey "$VPN_PROFILE")"
endpoint="$(profile_get Peer Endpoint "$VPN_PROFILE")"
keep="$(profile_get Peer PersistentKeepalive "$VPN_PROFILE")"
allowed="$(profile_get Peer AllowedIPs "$VPN_PROFILE")"

[ -n "$addr" ] && [ -n "$priv" ] && [ -n "$pub" ] && [ -n "$endpoint" ] && [ -n "$allowed" ] || {
    log "vpn: profile misses Address/PrivateKey/PublicKey/Endpoint/AllowedIPs"; exit 1;
}
[ -n "$mtu" ] || mtu=1420
[ -n "$keep" ] || keep=25
is_uint "$mtu" || { log "vpn: invalid MTU"; exit 1; }
is_uint "$keep" || { log "vpn: invalid keepalive"; exit 1; }
[ "$mtu" -ge 576 ] 2>/dev/null && [ "$mtu" -le 9000 ] 2>/dev/null || { log "vpn: MTU out of range"; exit 1; }
[ "$keep" -le 65535 ] 2>/dev/null || { log "vpn: keepalive out of range"; exit 1; }

# Reject command-ish/newline profile values before putting them into setconf.
for v in "$priv" "$pub" "$psk" "$endpoint" "$allowed"; do
    case "$v" in *'`'*|*'$('*|*';'*|*'|'*|*'&'*) log "vpn: unsafe profile value"; exit 1;; esac
done

TMP="$STATE/vpn-setconf.$$"
rm -f "$TMP"
{
    echo '[Interface]'
    printf 'PrivateKey = %s\n' "$priv"
    if [ "$VPN_TYPE" = "amneziawg" ]; then
        for k in Jc Jmin Jmax S1 S2 H1 H2 H3 H4; do
            v="$(profile_get Interface "$k" "$VPN_PROFILE")"
            [ -n "$v" ] || continue
            is_uint "$v" || { log "vpn: invalid AWG $k"; rm -f "$TMP"; exit 1; }
            printf '%s = %s\n' "$k" "$v"
        done
        # The pinned Padavan commit adds AmneziaWG I1 byte-pattern support.
        # Keep it as data, never shell-evaluate it. Example syntax: <b 0x..>.
        i1="$(profile_get Interface I1 "$VPN_PROFILE")"
        if [ -n "$i1" ]; then
            [ ${#i1} -le 512 ] || { log "vpn: AWG I1 too long"; rm -f "$TMP"; exit 1; }
            case "$i1" in *[!0-9A-Fa-fxXbB\<\>\ ,]*)
                log "vpn: invalid AWG I1"; rm -f "$TMP"; exit 1;;
            esac
            printf 'I1 = %s\n' "$i1"
        fi
    fi
    echo '[Peer]'
    printf 'PublicKey = %s\n' "$pub"
    [ -n "$psk" ] && printf 'PresharedKey = %s\n' "$psk"
    printf 'Endpoint = %s\n' "$endpoint"
    printf 'PersistentKeepalive = %s\n' "$keep"
    printf 'AllowedIPs = %s\n' "$allowed"
} > "$TMP" || { rm -f "$TMP"; exit 1; }
chmod 600 "$TMP" 2>/dev/null || true

stop_ourfw_vpn
case "$VPN_TYPE" in
  wireguard)
    WG=/usr/sbin/wg
    [ -x "$WG" ] || { log "vpn: $WG missing"; rm -f "$TMP"; exit 1; }
    modprobe -q wireguard >/dev/null 2>&1 || { log "vpn: cannot load wireguard module"; rm -f "$TMP"; exit 1; }
    ip link add dev "$VPN_INTERFACE" type wireguard >/tmp/ourfw-vpn-start.log 2>&1 || { log "vpn: cannot create WireGuard interface"; rm -f "$TMP"; exit 1; }
    ;;
  amneziawg)
    WG=/usr/sbin/awg
    [ -x "$WG" ] || { log "vpn: $WG missing"; rm -f "$TMP"; exit 1; }
    modprobe -q amneziawg >/dev/null 2>&1 || { log "vpn: cannot load amneziawg module"; rm -f "$TMP"; exit 1; }
    ip link add dev "$VPN_INTERFACE" type amneziawg >/tmp/ourfw-vpn-start.log 2>&1 || { log "vpn: cannot create AmneziaWG interface"; rm -f "$TMP"; exit 1; }
    ;;
  *) log "vpn: invalid VPN_TYPE=$VPN_TYPE"; rm -f "$TMP"; exit 1 ;;
esac

ok=1
# Address can contain comma-separated IPv4/IPv6 CIDRs. OURFW adds no routes here.
OLDIFS=$IFS; IFS=','
for a in $addr; do
    IFS=$OLDIFS
    a="$(printf '%s' "$a" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -n "$a" ] || continue
    case "$a" in *:*) fam=-6;; *) fam=-4;; esac
    ip $fam addr add "$a" dev "$VPN_INTERFACE" >/dev/null 2>&1 || ok=0
    IFS=','
done
IFS=$OLDIFS
[ "$ok" = "1" ] || { log "vpn: cannot assign interface address"; stop_ourfw_vpn; rm -f "$TMP"; exit 1; }
ip link set dev "$VPN_INTERFACE" mtu "$mtu" >/dev/null 2>&1 || { stop_ourfw_vpn; rm -f "$TMP"; exit 1; }
"$WG" setconf "$VPN_INTERFACE" "$TMP" >/tmp/ourfw-vpn-setconf.log 2>&1 || { log "vpn: setconf failed"; stop_ourfw_vpn; rm -f "$TMP"; exit 1; }
rm -f "$TMP"
ip link set dev "$VPN_INTERFACE" up >/dev/null 2>&1 || { log "vpn: interface up failed"; stop_ourfw_vpn; exit 1; }

# Cache resolved IPv4 transport endpoint. vpn-all MUST leave this direct or the
# encrypted UDP packets would recursively enter the tunnel.
ep="$($WG show "$VPN_INTERFACE" endpoints 2>/dev/null | awk 'NR==1{print $2}')"
ep4="$(printf '%s' "$ep" | sed -n 's/^\([0-9][0-9.]*\):[0-9][0-9]*$/\1/p')"
ep6="$(printf '%s' "$ep" | sed -n 's/^\[\([^]]*\)\]:[0-9][0-9]*$/\1/p')"
[ -n "$ep4" ] && printf '%s\n' "$ep4" > "$STATE/vpn-endpoint4" || rm -f "$STATE/vpn-endpoint4"
[ -n "$ep6" ] && printf '%s\n' "$ep6" > "$STATE/vpn-endpoint6" || rm -f "$STATE/vpn-endpoint6"
if [ "$VPN_USE_PEER_DNS" = "1" ] && [ -n "$dns" ]; then
    printf '%s\n' "$dns" > "$STATE/vpn-dns"
else
    rm -f "$STATE/vpn-dns"
fi
printf '%s\n' "$VPN_TYPE" > "$STATE/vpn-type"

iface_exists "$VPN_INTERFACE" || { log "vpn: interface did not appear"; exit 1; }
log "vpn: $VPN_TYPE interface ready on $VPN_INTERFACE (routing owned by OURFW)"
exit 0
