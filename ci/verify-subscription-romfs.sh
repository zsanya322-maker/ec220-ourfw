#!/bin/bash
set -euo pipefail
TREE=${1:-padavan-ng}
REPORT=${2:-SUBSCRIPTION-ROMFS-VERIFY.txt}
ROMFS="$TREE/trunk/romfs"
ARCHIVE="$ROMFS/usr/share/ourfw/defaults.tar.bz2"
: > "$REPORT"
log() { printf '%s\n' "$*" | tee -a "$REPORT"; }
fail() { log 'SUBSCRIPTION_ROMFS_VERIFY=FAILED'; log "ERROR=$*"; exit 61; }

[[ -s "$ARCHIVE" ]] || fail 'missing OURFW defaults archive'
list=$(mktemp)
trap 'rm -f "$list"' EXIT
tar -tjf "$ARCHIVE" > "$list" || fail 'cannot list defaults archive'

required=(
  './config/subscription.conf'
  './profiles/subscription.secret'
  './rules/subscription.allow-hosts'
  './modules/subscription/common.sh'
  './modules/subscription/apply.sh'
  './modules/subscription/start.sh'
  './modules/subscription/fetch.sh'
  './modules/subscription/parse.sh'
  './modules/subscription/health.sh'
  './modules/subscription/api.sh'
  './modules/subscription/secret-transfer.sh'
  './www/subscription.asp'
  './www/assets/subscription.js'
)
for item in "${required[@]}"; do
  grep -qx "$item" "$list" || fail "defaults archive missing $item"
done

# Production-safe defaults are part of the packed payload, not merely source.
tmp=$(mktemp -d)
trap 'rm -f "$list"; rm -rf "$tmp"' EXIT
tar -xjf "$ARCHIVE" -C "$tmp" \
  ./config/subscription.conf ./profiles/subscription.secret \
  ./modules/subscription/start.sh ./modules/subscription/secret-transfer.sh \
  ./www/index.asp ./www/subscription.asp ./www/assets/subscription.js \
  || fail 'cannot extract subscription defaults/WebUI'
grep -qx 'SUBSCRIPTION_ENABLED=0' "$tmp/config/subscription.conf" || fail 'subscription not disabled by default'
grep -qx 'SUBSCRIPTION_REFRESH=manual' "$tmp/config/subscription.conf" || fail 'subscription refresh not manual by default'
if grep -Ev '^[[:space:]]*(#|$)' "$tmp/profiles/subscription.secret" | grep -q .; then
  fail 'immutable payload unexpectedly contains a provider URL/secret'
fi

# Inspect executable shell lines only. Comments deliberately document forbidden
# operations (fetch/refresh), so scanning raw text would create a false positive.
start_code=$(grep -Ev '^[[:space:]]*(#|$)' "$tmp/modules/subscription/start.sh" || true)
if printf '%s\n' "$start_code" | grep -Eq 'fetch\.sh|(^|[[:space:]/])(curl|wget)([[:space:]]|$)|(^|[^A-Za-z0-9_])refresh([^A-Za-z0-9_]|$)'; then
  fail 'subscription boot hook performs refresh/network work'
fi

grep -Fq 'href="/ourfw/subscription.asp"' "$tmp/www/index.asp" || fail 'main WebUI has no Subscription/Hysteria link'
grep -Fq 'type="password" id="sub-url"' "$tmp/www/subscription.asp" || fail 'subscription URL field is not password-style'
if grep -q 'setInterval' "$tmp/www/assets/subscription.js"; then fail 'subscription WebUI contains periodic polling'; fi
if grep -Eq "file-get[^\n]*subscription-secret|subscription-secret[^\n]*file-get" "$tmp/www/assets/subscription.js"; then fail 'subscription WebUI attempts to read write-only source'; fi
grep -q 'subscription_validate_url' "$tmp/modules/subscription/secret-transfer.sh" || fail 'secret transport lacks URL validation'
grep -q 'chmod 0600.*SUB_SECRET' "$tmp/modules/subscription/secret-transfer.sh" || fail 'secret transport lacks mode 0600 enforcement'

log 'SUBSCRIPTION_ROMFS_VERIFY=OK'
log "DEFAULTS_BYTES=$(stat -c %s "$ARCHIVE")"
log "SUBSCRIPTION_FILES=${#required[@]}"
