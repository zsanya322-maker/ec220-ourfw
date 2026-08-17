#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MOD="$ROOT/ourfw/modules/subscription"
VPN_API="$ROOT/ourfw/modules/vpn/api.sh"

for f in common.sh apply.sh start.sh fetch.sh parse.sh health.sh api.sh; do
    [ -f "$MOD/$f" ] || { echo "v0.7: missing subscription/$f" >&2; exit 1; }
done

grep -q '^SUBSCRIPTION_ENABLED=0$' "$ROOT/ourfw/config/subscription.conf" || {
    echo 'v0.7: subscription must be disabled by default' >&2; exit 1;
}
grep -q '^SUBSCRIPTION_REFRESH=manual$' "$ROOT/ourfw/config/subscription.conf" || {
    echo 'v0.7: refresh must be manual by default' >&2; exit 1;
}
grep -q '^SUBSCRIPTION_PRIMARY_ID=$' "$ROOT/ourfw/config/subscription.conf" || {
    echo 'v0.7: primary selection must default empty' >&2; exit 1;
}
grep -q '^SUBSCRIPTION_BACKUP_ID=$' "$ROOT/ourfw/config/subscription.conf" || {
    echo 'v0.7: backup selection must default empty' >&2; exit 1;
}

# Subscription code is a data parser/manager, never a routing owner.
if grep -R -nE '(^|[^A-Za-z0-9_])(iptables|ip6tables|nft|route)[[:space:]]|ip[[:space:]]+rule|restart_(dhcpd|dns)|kill-switch' "$MOD"; then
    echo 'v0.7: subscription module must not own routing/firewall/DNS' >&2
    exit 1
fi
if grep -R -nE '^[[:space:]]*(eval|source)[[:space:]]|;[[:space:]]*(eval|source)[[:space:]]' "$MOD"; then
    echo 'v0.7: subscription content must never be eval/source executed' >&2
    exit 1
fi
if grep -R -nF 'command -v' "$MOD"; then
    echo 'v0.7: EC220 target cannot depend on command -v' >&2
    exit 1
fi
grep -q 'curl --config' "$MOD/fetch.sh" || { echo 'v0.7: secret URL must stay out of curl argv' >&2; exit 1; }
grep -q 'proto = "=https"' "$MOD/fetch.sh" || { echo 'v0.7: HTTPS-only curl policy missing' >&2; exit 1; }
grep -q 'proto-redir = "=https"' "$MOD/fetch.sh" || { echo 'v0.7: HTTPS-only redirect policy missing' >&2; exit 1; }
grep -q 'max-filesize' "$MOD/fetch.sh" || { echo 'v0.7: fetch size cap missing' >&2; exit 1; }
grep -q 'nodes.secret.old' "$MOD/parse.sh" || { echo 'v0.7: last-known-good parse rollback missing' >&2; exit 1; }
grep -q 'SUBSCRIPTION_PRIMARY_ID' "$MOD/api.sh" && grep -q 'SUBSCRIPTION_BACKUP_ID' "$MOD/api.sh" || { echo 'v0.7: node selection API missing' >&2; exit 1; }

# Engine orchestration remains in VPN, while Subscription only exposes IDs and
# volatile URI files. The VPN API must validate selected metadata before use.
grep -q 'hy2-start-primary' "$VPN_API" || { echo 'v0.7: Hysteria primary start API missing' >&2; exit 1; }
grep -q 'hy2-start-backup' "$VPN_API" || { echo 'v0.7: Hysteria backup start API missing' >&2; exit 1; }
grep -q '\$STATE/subscription/nodes.secret' "$VPN_API" || { echo 'v0.7: VPN API is not using volatile node secrets' >&2; exit 1; }
grep -q '\$2=="hysteria2"' "$VPN_API" || { echo 'v0.7: selected protocol validation missing' >&2; exit 1; }
if grep -Eq '/etc/storage/[^" ]*nodes\.secret|SUBSCRIPTION_.*URI=' "$ROOT/ourfw/config/subscription.conf" "$VPN_API"; then
    echo 'v0.7: node URI secret was made persistent' >&2
    exit 1
fi

# Runtime smoke test in an isolated CI filesystem. The production scripts use
# fixed /etc/storage paths, so expose this checkout there only for this test.
TMP="/tmp/ourfw-v070-test.$$"
ETC=/etc/storage/ourfw
OLD=""
cleanup() {
    rm -rf "$TMP" /tmp/ourfw /tmp/OURFW_V070_PWNED 2>/dev/null || true
    rm -f "$ROOT/ourfw/profiles/subscription.salt" 2>/dev/null || true
    if [ -L "$ETC" ]; then rm -f "$ETC"; fi
    if [ -n "$OLD" ] && [ -e "$OLD" ]; then mv "$OLD" "$ETC"; fi
}
trap cleanup EXIT HUP INT TERM
mkdir -p "$TMP" /etc/storage
if [ -e "$ETC" ] || [ -L "$ETC" ]; then
    OLD="/tmp/ourfw-v070-old.$$"
    mv "$ETC" "$OLD"
fi
ln -s "$ROOT/ourfw" "$ETC"
mkdir -p /tmp/ourfw/subscription
rm -f /tmp/OURFW_V070_PWNED

# Pre-seed a valid installation-local salt so the test never calls Storage save.
printf '%064d\n' 0 > "$ROOT/ourfw/profiles/subscription.salt"
chmod 0600 "$ROOT/ourfw/profiles/subscription.salt"

(
  . "$ETC/modules/subscription/common.sh"
  subscription_validate_url 'https://vpn.example/sub?id=abc'
  ! subscription_validate_url 'http://vpn.example/sub'
  ! subscription_validate_url 'https://vpn.example/a b'
  ! subscription_validate_url 'https://vpn.example/a"b'
  ! subscription_validate_url 'https://vpn.example/a\b'
) || { echo 'v0.7: URL validation smoke failed' >&2; exit 1; }

FEED="$TMP/feed.txt"
cat > "$FEED" <<'EOF'
hysteria2://user:$(touch${IFS}/tmp/OURFW_V070_PWNED)@hy.example:443/?sni=example.com#evil
vless://deadbeef@vl.example:8443?security=reality&x=`touch${IFS}/tmp/OURFW_V070_PWNED`
unknown://abc@other.example:9999/?q=;touch${IFS}/tmp/OURFW_V070_PWNED
EOF

/bin/sh "$MOD/parse.sh" "$FEED"
[ ! -e /tmp/OURFW_V070_PWNED ] || { echo 'v0.7: hostile feed executed shell content' >&2; exit 1; }
[ "$(wc -l < /tmp/ourfw/subscription/nodes.meta | tr -d '[:space:]')" = 3 ] || {
    echo 'v0.7: unexpected node count' >&2; exit 1;
}
grep -q '|hysteria2|' /tmp/ourfw/subscription/nodes.meta || { echo 'v0.7: Hysteria classification missing' >&2; exit 1; }
grep -q '|vless|' /tmp/ourfw/subscription/nodes.meta || { echo 'v0.7: VLESS classification missing' >&2; exit 1; }
grep -q '|unsupported|' /tmp/ourfw/subscription/nodes.meta || { echo 'v0.7: unknown scheme classification missing' >&2; exit 1; }
if grep -Eq 'deadbeef|touch|user:|security=reality' /tmp/ourfw/subscription/nodes.meta; then
    echo 'v0.7: secret material leaked into public metadata' >&2
    exit 1
fi

cp /tmp/ourfw/subscription/nodes.meta "$TMP/meta.before"
printf '%s\n' '%%% definitely not a feed %%%' > "$TMP/bad.feed"
if /bin/sh "$MOD/parse.sh" "$TMP/bad.feed" >/dev/null 2>&1; then
    echo 'v0.7: malformed feed unexpectedly accepted' >&2
    exit 1
fi
cmp -s "$TMP/meta.before" /tmp/ourfw/subscription/nodes.meta || {
    echo 'v0.7: failed parse destroyed last-good metadata' >&2; exit 1;
}

printf '%s\n' 'hy2://token@b64.example:443/?sni=b64.example' | base64 | tr -d '\n' > "$TMP/base64.feed"
/bin/sh "$MOD/parse.sh" "$TMP/base64.feed"
grep -q '|hysteria2|' /tmp/ourfw/subscription/nodes.meta || { echo 'v0.7: outer-base64 parse failed' >&2; exit 1; }

HEALTH="$(/bin/sh "$MOD/health.sh")"
NODES="$(/bin/sh "$MOD/api.sh" nodes)"
SELECTED="$(/bin/sh "$MOD/api.sh" selected)"
printf '%s\n' "$HEALTH" | grep -q '"nodes":1' || { echo 'v0.7: health node count wrong' >&2; exit 1; }
printf '%s\n' "$NODES" | grep -q '"primary":false' || { echo 'v0.7: node selection metadata missing' >&2; exit 1; }
printf '%s\n' "$SELECTED" | grep -q '"primary":""' || { echo 'v0.7: empty primary selection status wrong' >&2; exit 1; }
if printf '%s\n%s\n%s\n' "$HEALTH" "$NODES" "$SELECTED" | grep -Eq 'hy2://|token@|subscription.secret'; then
    echo 'v0.7: status/API leaked secret subscription data' >&2
    exit 1
fi

echo 'V0.7 SUBSCRIPTION MANAGER REGRESSIONS: OK'
