#!/bin/sh
set -u
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
load_global || exit 1
TAG="${1:-default}"
safe_id "$TAG" || exit 2
[ "${OURFW_ENABLED:-1}" = "1" ] || { echo "OURFW_DISABLED=1"; exit 0; }

[ ! -f "$STATE/pending" ] || { echo "another transaction is pending" >&2; exit 3; }
[ ! -f "$STATE/update-pending" ] || { echo "component transaction is pending" >&2; exit 3; }

# last-good is created at boot/confirm BEFORE the administrator changes candidate files.
[ -f "$STATE/last-good.tar" ] || (
    cd "$OURFW" && tar -cf "$STATE/last-good.tar" config profiles rules 2>/dev/null
) || exit 4
printf '%s\n' "$TAG" > "$STATE/pending"

apply_modules() {
    for m in vpn smart-routing dns nfqws watchdog diagnostics; do
        hook="$OURFW/modules/$m/apply.sh"
        [ -x "$hook" ] || continue
        log "apply module: $m"
        "$hook" || return 1
    done
}

if ! apply_modules; then
    "$OURFW/runtime/ourfw-rollback.sh" now
    exit 5
fi

# Connectivity guard. Confirmation from UI/SSH commits the new state.
(
    sleep "$ROLLBACK_TIMEOUT"
    [ -f "$STATE/pending" ] && "$OURFW/runtime/ourfw-rollback.sh" now
) >/dev/null 2>&1 &
echo $! > "$STATE/rollback-guard.pid"

echo "PENDING_CONFIRM=1"
echo "ROLLBACK_IN=$ROLLBACK_TIMEOUT"
