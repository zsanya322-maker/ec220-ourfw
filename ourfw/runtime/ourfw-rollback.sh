#!/bin/sh
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
load_global || exit 1
LOCKED=0
if [ "${OURFW_LOCK_HELD:-0}" != "1" ]; then
    txn_lock_acquire || { echo "another transaction is active" >&2; exit 3; }
    LOCKED=1
    trap 'txn_lock_release >/dev/null 2>&1 || true' EXIT HUP INT TERM
fi
snapshot_good() {
    tmp="$STATE/last-good.$$.tar"; rm -f "$tmp"
    ( cd "$OURFW" && tar -cf "$tmp" config profiles rules 2>/dev/null ) || return 1
    mv "$tmp" "$STATE/last-good.tar"
}
reapply() {
    for m in vpn smart-routing dns nfqws watchdog diagnostics; do
        hook="$OURFW/modules/$m/apply.sh"; [ -x "$hook" ] && "$hook" || true
    done
}
case "${1:-}" in
  baseline)
    [ ! -f "$STATE/pending" ] && [ ! -f "$STATE/update-pending" ] || { echo "transaction pending; baseline refused" >&2; exit 3; }
    snapshot_good ;;
  confirm)
    [ -f "$STATE/pending" ] || { echo "NO_PENDING=1"; exit 0; }
    kill_pidfile "$STATE/rollback-guard.pid"
    if ! save_storage; then
        log "storage save failed during confirm; rolling back candidate"
        OURFW_LOCK_HELD=1 "$0" now >/dev/null 2>&1 || true
        echo "CONFIRM_FAILED=1" >&2; exit 1
    fi
    rm -f "$STATE/pending"; snapshot_good || exit 1
    log "configuration confirmed and saved"; echo "CONFIRMED=1" ;;
  now)
    [ -f "$STATE/pending" ] || exit 0
    kill_pidfile "$STATE/rollback-guard.pid"
    [ -f "$STATE/last-good.tar" ] || { log "rollback requested but no last-good snapshot"; exit 1; }
    rm -rf "$OURFW/config" "$OURFW/profiles" "$OURFW/rules"; mkdir -p "$OURFW/config" "$OURFW/profiles" "$OURFW/rules"
    tar -xf "$STATE/last-good.tar" -C "$OURFW" || exit 1
    rm -f "$STATE/pending"; reapply
    log "automatic rollback completed"; echo "ROLLED_BACK=1" ;;
  *) echo "usage: ourfw-rollback.sh {baseline|confirm|now}" >&2; exit 2 ;;
esac
