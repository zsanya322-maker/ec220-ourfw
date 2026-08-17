#!/bin/sh
set -eu

ROOT=${1:-.}
fail(){ echo "FAIL: $*" >&2; exit 1; }

for f in \
  "$ROOT/ourfw/runtime/ourfw-scope.sh" \
  "$ROOT/ourfw/runtime/ourfw-apply.sh" \
  "$ROOT/ourfw/runtime/ourfw-rollback.sh" \
  "$ROOT/ourfw/runtime/ourfwctl.sh"
do
  [ -f "$f" ] || fail "missing $f"
  sh -n "$f" || fail "shell syntax: $f"
done

grep -Fq 'web-section-routing) printf' "$ROOT/ourfw/runtime/ourfw-scope.sh" || fail "routing section scope missing"
grep -Fq "routing)      printf '%s\\n' 'smart-routing dns'" "$ROOT/ourfw/runtime/ourfw-scope.sh" || fail "routing scope dependencies wrong"
grep -Fq "vpn)          printf '%s\\n' 'vpn smart-routing dns'" "$ROOT/ourfw/runtime/ourfw-scope.sh" || fail "vpn scope dependencies wrong"
grep -Fq 'scope_apply "$SCOPE"' "$ROOT/ourfw/runtime/ourfw-apply.sh" || fail "apply is not scoped"
grep -Fq 'scope_apply "$_scope"' "$ROOT/ourfw/runtime/ourfw-rollback.sh" || fail "rollback is not scoped"
! grep -Fq 'for m in zram vpn smart-routing adblock dns nfqws watchdog diagnostics' "$ROOT/ourfw/runtime/ourfw-apply.sh" || fail "old full apply loop remains"
! grep -Fq 'for m in zram vpn smart-routing adblock dns nfqws watchdog diagnostics' "$ROOT/ourfw/runtime/ourfw-rollback.sh" || fail "old full rollback loop remains"

grep -Fq '"pending_scope"' "$ROOT/ourfw/runtime/ourfwctl.sh" || fail "pending scope status missing"
grep -Fq '"pending_seconds"' "$ROOT/ourfw/runtime/ourfwctl.sh" || fail "pending countdown status missing"
grep -Fq 'VERSION.overlay' "$ROOT/ourfw/runtime/ourfwctl.sh" || fail "overlay display version missing"

HTML="$ROOT/ourfw/www/index.asp"
JS="$ROOT/ourfw/www/assets/ourfw.js"

grep -Fq 'id="pending-bar"' "$HTML" || fail "prominent pending bar missing"
grep -Fq 'id="routing-mode-select"' "$HTML" || fail "routing mode select missing"
grep -Fq 'id="vpn-enabled"' "$HTML" || fail "VPN enabled editor missing"
grep -Fq 'id="nfqws-enabled"' "$HTML" || fail "nfqws enabled editor missing"
grep -Fq 'Оставить и сохранить' "$HTML" || fail "human confirm label missing"
! grep -Fq 'data-module="smart-routing"' "$HTML" || fail "routing still has immediate module buttons"
! grep -Fq 'data-module="vpn" data-op="enable"' "$HTML" || fail "VPN still has duplicate enable button"
! grep -Fq 'data-module="vpn" data-op="disable"' "$HTML" || fail "VPN still has duplicate disable button"

grep -Fq 'visibilitychange' "$JS" || fail "visibility refresh missing"
grep -Fq 'schedulePending' "$JS" || fail "pending-only refresh missing"
! grep -Fq 'setInterval(status' "$JS" || fail "periodic production status polling regressed"
grep -Fq "c=kvSet(c,'ROUTING_MODE'" "$JS" || fail "routing mode is not saved with section"
grep -Fq "c=kvSet(c,'VPN_ENABLED'" "$JS" || fail "VPN enabled is not saved with VPN section"
grep -Fq "c=kvSet(c,'NFQWS_ENABLED'" "$JS" || fail "nfqws enabled is not saved with section"

cmp -s "$ROOT/ourfw/www/index.asp" "$ROOT/integration/padavan-user-ourfw/files/www/index.asp" || fail "integration index copy differs"
cmp -s "$ROOT/ourfw/www/assets/ourfw.js" "$ROOT/integration/padavan-user-ourfw/files/www/assets/ourfw.js" || fail "integration JS copy differs"
cmp -s "$ROOT/ourfw/www/assets/ourfw.css" "$ROOT/integration/padavan-user-ourfw/files/www/assets/ourfw.css" || fail "integration CSS copy differs"

echo "V071_SCOPED_UI=OK"
