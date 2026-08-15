#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASE=/etc/storage/ourfw
T=$(mktemp -d)
if [[ -e "$BASE" || -L "$BASE" ]]; then
  echo "V0.6.2 DNS FAIL-CLOSED: SKIP ($BASE exists)"
  exit 0
fi
mkdir -p /etc/storage "$T/bin"
cp -a "$ROOT/ourfw" "$T/ourfw"
find "$T/ourfw" -type f -name '*.sh' -exec chmod 755 {} \;
ln -s "$T/ourfw" "$BASE"
cleanup(){ rm -f "$BASE"; rm -rf /tmp/ourfw "$T"; }
trap cleanup EXIT INT TERM

cat > "$T/bin/restart_dhcpd" <<'SH'
#!/bin/sh
exit 0
SH
cat > "$T/bin/logger" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$T/bin/"*
rm -rf /tmp/ourfw; mkdir -p /tmp/ourfw
: > "$T/ourfw/rules/vpn-domains.list"
: > "$T/ourfw/rules/direct-domains.list"
: > "$T/ourfw/rules/dns-servers.list"
sed -i 's/^VPN_USE_PEER_DNS=.*/VPN_USE_PEER_DNS=1/' "$T/ourfw/config/vpn.conf"
printf '10.0.0.1\n' > /tmp/ourfw/vpn-dns

run_dns(){ OURFW_DNSMASQ_MAIN="$T/dnsmasq-main.conf" PATH="$T/bin:$PATH" sh "$BASE/modules/dns/apply.sh"; }
expect_fail(){ set +e; run_dns >/dev/null 2>&1; rc=$?; set -e; [[ $rc -ne 0 ]]; }

# Explicit VPN peer DNS must suppress resolv.conf fallback.
run_dns
grep -qx 'no-resolv' "$T/ourfw/dnsmasq-ourfw.conf"
grep -qx 'server=10.0.0.1' "$T/ourfw/dnsmasq-ourfw.conf"
base_sha=$(sha256sum "$T/ourfw/dnsmasq-ourfw.conf" | awk '{print $1}')

# Invalid VPN-domain input is a policy error, not a silently direct domain.
printf 'bad domain\n' > "$T/ourfw/rules/vpn-domains.list"
expect_fail
[[ "$(sha256sum "$T/ourfw/dnsmasq-ourfw.conf" | awk '{print $1}')" = "$base_sha" ]]
: > "$T/ourfw/rules/vpn-domains.list"

# IPv6 peer DNS is rejected until selective IPv6 routing can carry it safely.
printf '2001:db8::53\n' > /tmp/ourfw/vpn-dns
expect_fail
[[ "$(sha256sum "$T/ourfw/dnsmasq-ourfw.conf" | awk '{print $1}')" = "$base_sha" ]]

# Explicit user upstreams also use no-resolv and invalid upstreams fail closed.
sed -i 's/^VPN_USE_PEER_DNS=.*/VPN_USE_PEER_DNS=0/' "$T/ourfw/config/vpn.conf"
rm -f /tmp/ourfw/vpn-dns
printf '9.9.9.9\n' > "$T/ourfw/rules/dns-servers.list"
run_dns
grep -qx 'no-resolv' "$T/ourfw/dnsmasq-ourfw.conf"
grep -qx 'server=9.9.9.9' "$T/ourfw/dnsmasq-ourfw.conf"
printf 'not-an-ip\n' > "$T/ourfw/rules/dns-servers.list"
expect_fail
printf '::::\n' > "$T/ourfw/rules/dns-servers.list"
expect_fail

echo 'V0.6.2 DNS FAIL-CLOSED: OK'
