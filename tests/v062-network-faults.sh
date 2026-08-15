#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASE=/etc/storage/ourfw
T=$(mktemp -d)
ORIG_STORAGE=0
if [[ -e "$BASE" || -L "$BASE" ]]; then
  echo "V0.6.2 NETWORK FAULTS: SKIP ($BASE exists)"
  exit 0
fi
mkdir -p /etc/storage "$T/bin"
cp -a "$ROOT/ourfw" "$T/ourfw"
find "$T/ourfw" -type f -name '*.sh' -exec chmod 755 {} \;
ln -s "$T/ourfw" "$BASE"
cleanup(){ rm -f "$BASE"; rm -rf /tmp/ourfw "$T"; }
trap cleanup EXIT INT TERM

cat > "$T/ourfw/config/routing.conf" <<'CFG'
ROUTING_MODE=vpn-all
ROUTE_TABLE=100
FWMARK=0x100
FWMASK=0x100
RULE_PREF=10000
KILLSWITCH=1
IPV6_POLICY=block
CFG
cat > "$T/ourfw/config/vpn.conf" <<'CFG'
VPN_ENABLED=1
VPN_TYPE=wireguard
VPN_INTERFACE=wg0
VPN_PROFILE=/etc/storage/ourfw/profiles/vpn.conf
VPN_OPENVPN_PROFILE=/etc/storage/ourfw/profiles/openvpn.ovpn
VPN_OPENVPN_AUTH=/etc/storage/ourfw/profiles/openvpn.auth
VPN_USE_PEER_DNS=0
VPN_FAILOVER_ENABLED=1
VPN_FAILOVER_TYPE=openvpn
CFG
printf '203.0.113.0/24\n' > "$T/ourfw/rules/vpn-ips.list"
: > "$T/ourfw/rules/direct-ips.list"

cat > "$T/bin/iptables" <<'SH'
#!/bin/sh
printf 'iptables %s\n' "$*" >> "${NETLOG:?}"
case " $* " in *" -D "*) exit 1;; esac
case " $* " in *"${FAIL_MATCH:-__NO_MATCH__}"*) [ -z "${FAIL_MATCH:-}" ] || exit 42;; esac
exit 0
SH
cat > "$T/bin/ip6tables" <<'SH'
#!/bin/sh
printf 'ip6tables %s\n' "$*" >> "${NETLOG:?}"
case " $* " in *" -D "*) exit 1;; esac
case " $* " in *"${FAIL_MATCH:-__NO_MATCH__}"*) [ -z "${FAIL_MATCH:-}" ] || exit 43;; esac
exit 0
SH
cat > "$T/bin/ipset" <<'SH'
#!/bin/sh
printf 'ipset %s\n' "$*" >> "${NETLOG:?}"
case " $* " in *"${FAIL_MATCH:-__NO_MATCH__}"*) [ -z "${FAIL_MATCH:-}" ] || exit 44;; esac
exit 0
SH
cat > "$T/bin/ip" <<'SH'
#!/bin/sh
printf 'ip %s\n' "$*" >> "${NETLOG:?}"
if [ "${1:-}" = link ] && [ "${2:-}" = show ]; then exit 0; fi
if [ "${1:-}" = rule ] && [ "${2:-}" = del ]; then exit 1; fi
case " $* " in *"${FAIL_MATCH:-__NO_MATCH__}"*) [ -z "${FAIL_MATCH:-}" ] || exit 45;; esac
exit 0
SH
cat > "$T/bin/nvram" <<'SH'
#!/bin/sh
[ "${1:-}" = get ] && [ "${2:-}" = lan_ifname ] && { echo br0; exit 0; }
exit 0
SH
chmod +x "$T/bin/"*

run_ok(){
  rm -rf /tmp/ourfw; mkdir -p /tmp/ourfw
  printf 'wg0\n' > /tmp/ourfw/vpn-interface
  printf 'wireguard\n' > /tmp/ourfw/vpn-type
  : > "$T/net.log"
  NETLOG="$T/net.log" PATH="$T/bin:$PATH" FAIL_MATCH= sh "$BASE/modules/smart-routing/apply.sh"
  grep -q 'ip rule add fwmark 0x100/0x100 table 100 pref 10000' "$T/net.log"
  grep -q 'iptables -t filter -A OURFW_KILL .* -j REJECT' "$T/net.log"
  grep -q 'ip6tables -t filter -A OURFW6_OUT -j REJECT' "$T/net.log"
}

run_must_fail(){
  local match=$1
  rm -rf /tmp/ourfw; mkdir -p /tmp/ourfw
  printf 'wg0\n' > /tmp/ourfw/vpn-interface
  printf 'wireguard\n' > /tmp/ourfw/vpn-type
  : > "$T/net.log"
  set +e
  NETLOG="$T/net.log" PATH="$T/bin:$PATH" FAIL_MATCH="$match" sh "$BASE/modules/smart-routing/apply.sh"
  rc=$?
  set -e
  [[ $rc -ne 0 ]] || { echo "expected failure for: $match" >&2; exit 1; }
  # A critical failure must trigger cleanup attempts rather than leave a
  # half-installed policy that callers could mistake for success.
  [[ $(grep -c 'iptables -t mangle -D PREROUTING -j OURFW_ROUTE' "$T/net.log") -ge 2 ]]
}

run_ok
run_must_fail ' -A OURFW_KILL -m mark '
run_must_fail ' -A OURFW6_OUT -j REJECT '
run_must_fail ' rule add fwmark '
run_must_fail ' -A PREROUTING -j OURFW_ROUTE '
run_must_fail ' -! add ourfw_vpn4 '

echo 'V0.6.2 NETWORK FAULTS: OK'
