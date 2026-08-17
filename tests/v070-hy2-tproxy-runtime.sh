#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SRC="$ROOT/ourfw/modules/vpn/hy2-tproxy.sh"
START="$ROOT/ourfw/modules/vpn/start.sh"

fail() { echo "HY2 TPROXY runtime regression: $*" >&2; exit 1; }

[ -f "$SRC" ] || fail 'runtime script missing'
sh -n "$SRC" || fail 'runtime script syntax error'

# Hysteria remains explicitly opt-in. Firmware boot must not fetch/start/arm it.
if grep -Eq 'hy2-tproxy|Hysteria|HY2_' "$START"; then
  fail 'VPN boot hook references Hysteria runtime'
fi

grep -Fq 'hy2-engine-v0.7b-r1/ec220-hy2-tproxy-salamander' "$SRC" || fail 'pinned engine URL missing'
grep -Fq '02d907537a313f0fd69b0390af2eb89b4f8661208320ee6955f7bf9f1c0de99f' "$SRC" || fail 'pinned engine SHA256 missing'
grep -Fq 'HY2_ENGINE_BYTES=${HY2_ENGINE_BYTES:-9830593}' "$SRC" || fail 'pinned engine size missing'

# Secrets are passed only through a protected URI file, never argv auth/obfs flags.
grep -Fq '"$HY2_ENGINE" -uri-file "$uri" -check-config' "$SRC" || fail 'protected URI validation missing'
grep -Fq '"$HY2_ENGINE" -uri-file "$uri" -listen' "$SRC" || fail 'protected URI engine start missing'
if grep -Eq '"\$HY2_ENGINE"[^\n]*( -auth | -obfs-password )' "$SRC"; then
  fail 'engine secret appears on argv'
fi

# Kernel support must be loaded explicitly for both TCP and UDP TPROXY.
for token in 'nf_tproxy_core.ko' 'xt_socket.ko' 'xt_TPROXY.ko'; do
  grep -Fq "$token" "$SRC" || fail "module loader missing $token"
done

grep -Fq 'iptables -t mangle -I PREROUTING 1 -j "$HY2_CHAIN"' "$SRC" || fail 'generic PREROUTING insert missing'
grep -Fq 'ipt_del_jump -t mangle -D PREROUTING -j "$HY2_CHAIN"' "$SRC" || fail 'matching PREROUTING delete missing'
grep -Fq 'iptables -t mangle -A "$HY2_CHAIN" ! -i "$lan" -j RETURN' "$SRC" || fail 'LAN scope guard missing'

# Both transports must hit the local transparent proxy, while private LAN ranges bypass it.
grep -F 'iptables -t mangle -A "$HY2_CHAIN" -p tcp' "$SRC" | grep -Fq -- '-j TPROXY' || fail 'TCP TPROXY rule missing'
grep -F 'iptables -t mangle -A "$HY2_CHAIN" -p udp' "$SRC" | grep -Fq -- '-j TPROXY' || fail 'UDP TPROXY rule missing'
grep -Fq '192.168.0.0/16' "$SRC" || fail 'private LAN exclusion missing'
grep -Fq '127.0.0.0/8' "$SRC" || fail 'loopback exclusion missing'

# Initial hardware test is LAN-only; router-origin OUTPUT interception is forbidden.
if grep -E 'iptables .*OUTPUT.*TPROXY|iptables .* -A OUTPUT .*HY2_CHAIN|iptables .* -I OUTPUT .*HY2_CHAIN' "$SRC"; then
  fail 'router-origin OUTPUT interception enabled prematurely'
fi

# Every route arm must be automatically reversible unless a token is confirmed.
grep -Fq 'HY2_ROLLBACK_TIMEOUT=${HY2_ROLLBACK_TIMEOUT:-90}' "$SRC" || fail '90s rollback timeout missing'
grep -Fq 'sleep "$HY2_ROLLBACK_TIMEOUT"' "$SRC" || fail 'rollback guard sleep missing'
grep -Fq 'route_cleanup_no_guard >/dev/null 2>&1 || true' "$SRC" || fail 'automatic route cleanup missing'
grep -Fq 'CONFIRM_TOKEN=' "$SRC" || fail 'confirmation token output missing'
grep -Fq 'legacy OURFW VPN interface is active' "$SRC" || fail 'legacy VPN conflict guard missing'

echo 'HY2 TPROXY RUNTIME REGRESSION: OK'
