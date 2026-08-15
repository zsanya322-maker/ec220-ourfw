#!/bin/sh
set -u
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
load_global || exit 1
TAG="${1:-default}"
safe_id "$TAG" || exit 2
[ "${OURFW_ENABLED:-1}" = "1" ] || { echo "OURFW_DISABLED=1"; exit 0; }

txn_lock_acquire || { echo "another transaction is active" >&2; exit 3; }
trap 'txn_lock_release >/dev/null 2>&1 || true' EXIT HUP INT TERM

# A pending marker with a dead/missing guard means the previous caller crashed.
if [ -f "$STATE/pending" ]; then
    if pid_alive "$STATE/rollback-guard.pid"; then echo "another transaction is pending" >&2; exit 3; fi
    log "configuration: stale pending detected; restoring last-good"
    OURFW_LOCK_HELD=1 "$OURFW/runtime/ourfw-rollback.sh" now >/dev/null 2>&1 || { echo "stale rollback failed" >&2; exit 4; }
fi
if [ -f "$STATE/update-pending" ]; then
    if pid_alive "$STATE/update-guard.pid"; then echo "component transaction is pending" >&2; exit 3; fi
    log "configuration: stale component pending detected; restoring module"
    OURFW_LOCK_HELD=1 "$OURFW/runtime/ourfw-update.sh" rollback >/dev/null 2>&1 || { echo "stale component rollback failed" >&2; exit 4; }
fi

[ -f "$STATE/last-good.tar" ] || ( cd "$OURFW" && tar -cf "$STATE/last-good.tar" config profiles rules 2>/dev/null ) || exit 4
printf '%s\n' "$TAG" > "$STATE/pending" || exit 4

# Arm rollback BEFORE touching networking. If this shell dies mid-apply the
# independent guard still restores last-good.
(
    sleep "$ROLLBACK_TIMEOUT"
    n=0
    while [ -f "$STATE/pending" ] && [ "$n" -lt 15 ]; do
        "$OURFW/runtime/ourfw-rollback.sh" now >/dev/null 2>&1 && exit 0
        n=$((n+1)); sleep 2
    done
) >/dev/null 2>&1 &
echo $! > "$STATE/rollback-guard.pid"

apply_modules() {
    for m in vpn smart-routing dns nfqws watchdog diagnostics; do
        hook="$OURFW/modules/$m/apply.sh"; [ -x "$hook" ] || continue
        log "apply module: $m"; "$hook" || return 1
    done
}
if ! apply_modules; then
    OURFW_LOCK_HELD=1 "$OURFW/runtime/ourfw-rollback.sh" now >/dev/null 2>&1 || true
    exit 5
fi

echo "PENDING_CONFIRM=1"
echo "ROLLBACK_IN=$ROLLBACK_TIMEOUT"
