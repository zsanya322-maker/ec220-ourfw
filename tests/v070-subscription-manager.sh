#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MOD="$ROOT/ourfw/modules/subscription"

for f in common.sh apply.sh start.sh fetch.sh parse.sh health.sh api.sh; do
    [ -f "$MOD/$f" ] || { echo "v0.7a: missing subscription/$f" >&2; exit 1; }
done

grep -q '^SUBSCRIPTION_ENABLED=0$' "$ROOT/ourfw/config/subscription.conf" || {
    echo 'v0.7a: subscription must be disabled by default' >&2; exit 1;
}
grep -q '^SUBSCRIPTION_REFRESH=manual$' "$ROOT/ourfw/config/subscription.conf" || {
    echo 'v0.7a: refresh must be manual by default' >&2; exit 1;
}

# Subscription code is a data parser/manager, never a routing owner.
if grep -R -nE '(^|[^A-Za-z0-9_])(iptables|ip6tables|nft|route)[[:space:]]|ip[[:space:]]+rule|restart_(dhcpd|dns)|kill-switch' "$MOD"; then
    echo 'v0.7a: subscription module must not own routing/firewall/DNS' >&2
    exit 1
fi
# Match eval/source only where they can actually start a shell command. Do not
# flag harmless English text such as "provider source rejected" inside quotes.
if grep -R -nE '^[[:space:]]*(eval|source)[[:space:]]|;[[:space:]]*(eval|source)[[:space:]]' "$MOD"; then
    echo 'v0.7a: subscription content must never be eval/source executed' >&2
    exit 1
fi
if grep -R -nF 'command -v' "$MOD"; then
    echo 'v0.7a: EC220 target cannot depend on command -v' >&2
    exit 1
fi
grep -q 'curl --config' "$MOD/fetch.sh" || { echo 'v0.7a: secret URL must stay out of curl argv' >&2; exit 1; }
grep -q 'proto = "=https"' "$MOD/fetch.sh" || { echo 'v0.7a: HTTPS-only curl policy missing' >&2; exit 1; }
grep -q 'proto-redir = "=https"' "$MOD/fetch.sh" || { echo 'v0.7a: HTTPS-only redirect policy missing' >&2; exit 1; }
grep -q 'max-filesize' "$MOD/fetch.sh" || { echo 'v0.7a: fetch size cap missing' >&2; exit 1; }
grep -q 'nodes.secret.old' "$MOD/parse.sh" || { echo 'v0.7a: last-known-good parse rollback missing' >&2; exit 1; }

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

# URL validation: valid HTTPS accepted; whitespace/quote/backslash/non-HTTPS rejected.
(
  . "$ETC/modules/subscription/common.sh"
  subscription_validate_url 'https://vpn.example/sub?id=abc'
  ! subscription_validate_url 'http://vpn.example/sub'
  ! subscription_validate_url 'https://vpn.example/a b'
  ! subscription_validate_url 'https://vpn.example/a"b'
  ! subscription_validate_url 'https://vpn.example/a\b'
) || { echo 'v0.7a: URL validation smoke failed' >&2; exit 1; }

FEED="$TMP/feed.txt"
cat > "$FEED" <<'EOF'
hysteria2://user:$(touch${IFS}/tmp/OURFW_V070_PWNED)@hy.example:443/?sni=example.com#evil
vless://deadbeef@vl.example:8443?security=reality&x=`touch${IFS}/tmp/OURFW_V070_PWNED`
unknown://abc@other.example:9999/?q=;touch${IFS}/tmp/OURFW_V070_PWNED
EOF

/bin/sh "$MOD/parse.sh" "$FEED"
[ ! -e /tmp/OURFW_V070_PWNED ] || { echo 'v0.7a: hostile feed executed shell content' >&2; exit 1; }
[ "$(wc -l < /tmp/ourfw/subscription/nodes.meta | tr -d '[:space:]')" = 3 ] || {
    echo 'v0.7a: unexpected node count' >&2; exit 1;
}
grep -q '|hysteria2|' /tmp/ourfw/subscription/nodes.meta || { echo 'v0.7a: Hysteria classification missing' >&2; exit 1; }
grep -q '|vless|' /tmp/ourfw/subscription/nodes.meta || { echo 'v0.7a: VLESS classification missing' >&2; exit 1; }
grep -q '|unsupported|' /tmp/ourfw/subscription/nodes.meta || { echo 'v0.7a: unknown scheme classification missing' >&2; exit 1; }
# Public metadata must never echo auth/query/UUID-like hostile secret material.
if grep -Eq 'deadbeef|touch|user:|security=reality' /tmp/ourfw/subscription/nodes.meta; then
    echo 'v0.7a: secret material leaked into public metadata' >&2
    exit 1
fi

# A malformed later refresh must keep the last-good node table intact.
cp /tmp/ourfw/subscription/nodes.meta "$TMP/meta.before"
printf '%s\n' '%%% definitely not a feed %%%' > "$TMP/bad.feed"
if /bin/sh "$MOD/parse.sh" "$TMP/bad.feed" >/dev/null 2>&1; then
    echo 'v0.7a: malformed feed unexpectedly accepted' >&2
    exit 1
fi
cmp -s "$TMP/meta.before" /tmp/ourfw/subscription/nodes.meta || {
    echo 'v0.7a: failed parse destroyed last-good metadata' >&2; exit 1;
}

# Outer-base64 form must decode and parse too.
printf '%s\n' 'hy2://token@b64.example:443/?sni=b64.example' | base64 | tr -d '\n' > "$TMP/base64.feed"
/bin/sh "$MOD/parse.sh" "$TMP/base64.feed"
grep -q '|hysteria2|' /tmp/ourfw/subscription/nodes.meta || { echo 'v0.7a: outer-base64 parse failed' >&2; exit 1; }

# Health/API output is metadata only; no raw URI or provider source is returned.
HEALTH="$(/bin/sh "$MOD/health.sh")"
NODES="$(/bin/sh "$MOD/api.sh" nodes)"
printf '%s\n' "$HEALTH" | grep -q '"nodes":1' || { echo 'v0.7a: health node count wrong' >&2; exit 1; }
if printf '%s\n%s\n' "$HEALTH" "$NODES" | grep -Eq 'hy2://|token@|subscription.secret'; then
    echo 'v0.7a: status/API leaked secret subscription data' >&2
    exit 1
fi

echo 'V0.7a SUBSCRIPTION MANAGER REGRESSIONS: OK'
