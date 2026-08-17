#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PAGE="$ROOT/ourfw/www/subscription.asp"
JS="$ROOT/ourfw/www/assets/subscription.js"
XFER="$ROOT/ourfw/modules/subscription/secret-transfer.sh"
API="$ROOT/ourfw/runtime/ourfw-api.sh"

for f in "$PAGE" "$JS" "$XFER"; do [ -s "$f" ] || { echo "v0.7 WebUI: missing $f" >&2; exit 1; }; done

grep -q 'type="password" id="sub-url"' "$PAGE" || { echo 'v0.7 WebUI: secret URL field is not password/write-only UI' >&2; exit 1; }
grep -q 'subscription-secret' "$JS" || { echo 'v0.7 WebUI: protected URL transport missing' >&2; exit 1; }
if grep -Eq "file-get[^\n]*subscription-secret|subscription-secret[^\n]*file-get" "$JS"; then
  echo 'v0.7 WebUI: browser attempts to read secret URL' >&2; exit 1
fi
if grep -q 'setInterval' "$JS"; then
  echo 'v0.7 WebUI: periodic subscription polling is forbidden on EC220 hardware' >&2; exit 1
fi
grep -q "document.addEventListener('visibilitychange'" "$JS" || { echo 'v0.7 WebUI: event-driven visibility refresh missing' >&2; exit 1; }
grep -q "input.value=''" "$JS" || { echo 'v0.7 WebUI: secret URL input is not cleared after save' >&2; exit 1; }
grep -q 'j.ok===false' "$JS" || { echo 'v0.7 WebUI: module failure responses are not rejected' >&2; exit 1; }
for op in refresh primary backup hy2-start-primary hy2-start-backup hy2-arm-smart hy2-confirm; do grep -q "$op" "$JS" || { echo "v0.7 WebUI: missing control $op" >&2; exit 1; }; done

grep -q 'subscription source is write-only' "$API" || { echo 'v0.7 API: file-get secret denial missing' >&2; exit 1; }
grep -q 'secret-transfer.sh' "$API" || { echo 'v0.7 API: dedicated secret transport missing' >&2; exit 1; }
grep -q 'subscription_validate_url' "$XFER" || { echo 'v0.7 transfer: HTTPS URL validation missing' >&2; exit 1; }
grep -q 'subscription_host_allowed' "$XFER" || { echo 'v0.7 transfer: provider host allowlist missing' >&2; exit 1; }
grep -q 'chmod 0600.*SUB_SECRET' "$XFER" || { echo 'v0.7 transfer: secret mode 0600 missing' >&2; exit 1; }
grep -q 'previous source restored' "$XFER" || { echo 'v0.7 transfer: Storage failure rollback missing' >&2; exit 1; }
grep -q '"source_set"' "$ROOT/ourfw/modules/subscription/health.sh" || { echo 'v0.7 health: safe source_set boolean missing' >&2; exit 1; }
if grep -q 'subscription_source_url.*printf' "$ROOT/ourfw/modules/subscription/health.sh"; then
  echo 'v0.7 health: source URL may be emitted' >&2; exit 1
fi
grep -q 'enable|disable' "$ROOT/ourfw/modules/subscription/api.sh" || { echo 'v0.7 API: manager enable/disable missing' >&2; exit 1; }
grep -q 'set_selection "$slot" "$id"' "$ROOT/ourfw/modules/subscription/api.sh" || { echo 'v0.7 API: selection result handling missing' >&2; exit 1; }
grep -q 'zram subscription vpn' "$ROOT/ourfw/runtime/ourfwctl.sh" || { echo 'v0.7 boot: passive subscription bootstrap is not wired' >&2; exit 1; }
grep -q '/ourfw/subscription.asp' "$ROOT/build/make-defaults.sh" || { echo 'v0.7 WebUI: main-panel subscription link injection missing' >&2; exit 1; }

if command -v node >/dev/null 2>&1; then node --check "$JS"; fi
sh -n "$XFER"
echo 'V0.7 SUBSCRIPTION WEBUI REGRESSIONS: OK'
