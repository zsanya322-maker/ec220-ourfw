#!/bin/sh
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
load_global || exit 1
. /etc/storage/ourfw/runtime/ourfw-scope.sh || exit 1

LOCKED=0
if [ "${OURFW_LOCK_HELD:-0}" != "1" ]; then
    txn_lock_acquire || { echo "another transaction is active" >&2; exit 3; }
    LOCKED=1
    trap 'txn_lock_release >/dev/null 2>&1 || true' EXIT HUP INT TERM
fi

pending_tag() {
    _v="$(cat "$STATE/pending-tag" 2>/dev/null || cat "$STATE/pending" 2>/dev/null || true)"
    safe_id "$_v" || _v=unknown
    printf '%s\n' "$_v"
}

pending_scope() {
    _v="$(cat "$STATE/pending-scope" 2>/dev/null || true)"
    scope_modules "$_v" >/dev/null 2>&1 || _v=all
    printf '%s\n' "$_v"
}

pending_cleanup() {
    rm -f "$STATE/pending" "$STATE/pending-scope" "$STATE/pending-tag" \
          "$STATE/pending-start" "$STATE/pending-deadline"
}

record_last() {
    _result="$1"; _tag="$2"; _scope="$3"
    _now="$(date +%s 2>/dev/null || echo 0)"
    is_uint "$_now" || _now=0
    printf '%s\n' "$_result" > "$STATE/last-result"
    printf '%s\n' "$_tag" > "$STATE/last-tag"
    printf '%s\n' "$_scope" > "$STATE/last-scope"
    printf '%s\n' "$_now" > "$STATE/last-time"
}

snapshot_good() {
    _tmp="$STATE/last-good.$$.tar"
    rm -f "$_tmp"
    ( cd "$OURFW" && tar -cf "$_tmp" config profiles rules 2>/dev/null ) || return 1
    mv "$_tmp" "$STATE/last-good.tar"
}

case "${1:-}" in
  baseline)
    [ ! -f "$STATE/pending" ] && [ ! -f "$STATE/update-pending" ] ||
        { echo "transaction pending; baseline refused" >&2; exit 3; }
    snapshot_good
    ;;

  confirm)
    [ -f "$STATE/pending" ] || { echo "NO_PENDING=1"; exit 0; }
    _tag="$(pending_tag)"
    _scope="$(pending_scope)"
    kill_pidfile "$STATE/rollback-guard.pid"
    if ! save_storage; then
        log "storage save failed during confirm; rolling back candidate"
        OURFW_LOCK_HELD=1 "$0" now >/dev/null 2>&1 || true
        echo "CONFIRM_FAILED=1" >&2
        exit 1
    fi
    pending_cleanup
    snapshot_good || exit 1
    record_last confirmed "$_tag" "$_scope"
    log "configuration confirmed and saved: tag=$_tag scope=$_scope"
    echo "CONFIRMED=1"
    echo "SCOPE=$_scope"
    ;;

  now)
    [ -f "$STATE/pending" ] || exit 0
    _tag="$(pending_tag)"
    _scope="$(pending_scope)"
    kill_pidfile "$STATE/rollback-guard.pid"
    [ -f "$STATE/last-good.tar" ] ||
        { log "rollback requested but no last-good snapshot"; exit 1; }

    rm -rf "$OURFW/config" "$OURFW/profiles" "$OURFW/rules"
    mkdir -p "$OURFW/config" "$OURFW/profiles" "$OURFW/rules"
    tar -xf "$STATE/last-good.tar" -C "$OURFW" || exit 1
    for _sf in "$OURFW/config/vpn.conf" "$OURFW/profiles/vpn.conf" "$OURFW/profiles/openvpn.ovpn" "$OURFW/profiles/openvpn.auth"; do
        [ -f "$_sf" ] && chmod 600 "$_sf" 2>/dev/null || true
    done

    if scope_apply "$_scope"; then
        pending_cleanup
        record_last rolled-back "$_tag" "$_scope"
        log "automatic rollback completed: tag=$_tag scope=$_scope"
        echo "ROLLED_BACK=1"
        echo "SCOPE=$_scope"
    else
        log "automatic rollback restored files but scoped runtime reapply failed: scope=$_scope"
        echo "ROLLBACK_REAPPLY_FAILED=1" >&2
        exit 1
    fi
    ;;

  *)
    echo "usage: ourfw-rollback.sh {baseline|confirm|now}" >&2
    exit 2
    ;;
esac
