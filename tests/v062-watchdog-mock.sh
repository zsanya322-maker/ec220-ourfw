#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASE=/etc/storage/ourfw
T=$(mktemp -d)
if [[ -e "$BASE" || -L "$BASE" ]]; then
  echo "V0.6.2 WATCHDOG MOCK: SKIP ($BASE exists)"
  exit 0
fi
mkdir -p /etc/storage "$T/bin"
cp -a "$ROOT/ourfw" "$T/ourfw"
find "$T/ourfw" -type f -name '*.sh' -exec chmod 755 {} \;
ln -s "$T/ourfw" "$BASE"
cleanup(){ rm -f "$BASE"; rm -rf /tmp/ourfw "$T"; }
trap cleanup EXIT INT TERM

cat > "$T/bin/ip" <<'SH'
#!/bin/sh
if [ "${1:-}" = -4 ] && [ "${2:-}" = route ] && [ "${3:-}" = show ] && [ "${4:-}" = default ]; then
  [ -n "${DEFAULT_ROUTE:-}" ] && printf '%s\n' "$DEFAULT_ROUTE"
  exit 0
fi
if [ "${1:-}" = link ] && [ "${2:-}" = show ]; then
  [ "${IFACE_OK:-1}" = 1 ]
  exit $?
fi
exit 0
SH
cat > "$T/bin/ping" <<'SH'
#!/bin/sh
[ "${PING_OK:-0}" = 1 ]
SH
cat > "$T/bin/logger" <<'SH'
#!/bin/sh
exit 0
SH
cat > "$T/bin/nvram" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$T/bin/"*

cat > "$T/ourfw/config/vpn.conf" <<'CFG'
VPN_ENABLED=1
VPN_TYPE=openvpn
VPN_INTERFACE=wg0
VPN_PROFILE=/etc/storage/ourfw/profiles/vpn.conf
VPN_OPENVPN_PROFILE=/etc/storage/ourfw/profiles/openvpn.ovpn
VPN_OPENVPN_AUTH=/etc/storage/ourfw/profiles/openvpn.auth
VPN_USE_PEER_DNS=0
VPN_FAILOVER_ENABLED=1
VPN_FAILOVER_TYPE=wireguard
CFG

write_watchdog(){
  cat > "$T/ourfw/config/watchdog.conf" <<CFG
WATCHDOG_ENABLED=1
WATCHDOG_INTERVAL=30
WATCHDOG_FAILS=3
WATCHDOG_SCOPE=$1
PING_TARGET1=1.1.1.1
PING_TARGET2=8.8.8.8
WATCHDOG_REBOOT=0
WATCHDOG_VPN_TARGET=${2-1.1.1.1}
WATCHDOG_VPN_HANDSHAKE_MAX_AGE=180
WATCHDOG_USE_INETDETECT=1
WATCHDOG_INETDETECT_MAX_AGE=180
CFG
}
run_watchdog(){
  OURFW_WATCHDOG_ONESHOT=1 PATH="$T/bin:$PATH" DEFAULT_ROUTE="${DEFAULT_ROUTE:-}" IFACE_OK="${IFACE_OK:-1}" PING_OK="${PING_OK:-0}" sh "$BASE/modules/watchdog/watchdog.sh"
}
expect_fail(){ set +e; run_watchdog; rc=$?; set -e; [[ $rc -ne 0 ]]; }
expect_ok(){ run_watchdog; }

rm -rf /tmp/ourfw; mkdir -p /tmp/ourfw
# No default route is failure, even if ping mock itself would succeed.
write_watchdog gateway
DEFAULT_ROUTE= PING_OK=1 IFACE_OK=1 expect_fail
# Normal routed gateway succeeds when reachable.
DEFAULT_ROUTE='default via 192.0.2.1 dev eth2' PING_OK=1 IFACE_OK=1 expect_ok
# PPP/point-to-point default has no `via`; live default interface is valid for
# gateway scope and Internet scope remains responsible for reachability.
DEFAULT_ROUTE='default dev ppp0 scope link' PING_OK=0 IFACE_OK=1 expect_ok

# OpenVPN: a live daemon cannot mask a failed explicit tunnel reachability test.
write_watchdog vpn 1.1.1.1
printf 'tun0\n' > /tmp/ourfw/vpn-interface
printf 'openvpn\n' > /tmp/ourfw/vpn-type
printf '%s\n' "$$" > /tmp/ourfw/openvpn.pid
DEFAULT_ROUTE='default via 192.0.2.1 dev eth2' PING_OK=0 IFACE_OK=1 expect_fail
DEFAULT_ROUTE='default via 192.0.2.1 dev eth2' PING_OK=1 IFACE_OK=1 expect_ok
# With no explicit target, process+interface fallback remains allowed.
write_watchdog vpn ''
DEFAULT_ROUTE='default via 192.0.2.1 dev eth2' PING_OK=0 IFACE_OK=1 expect_ok

# A future InetDetect timestamp must not be trusted as a fresh healthy state.
write_watchdog internet
future=$(( $(date +%s) + 600 ))
printf '%s 1\n' "$future" > /tmp/ourfw/inet-state
PING_OK=0 IFACE_OK=1 expect_fail

echo 'V0.6.2 WATCHDOG MOCK: OK'
