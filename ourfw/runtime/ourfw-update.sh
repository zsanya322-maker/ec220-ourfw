#!/bin/sh
set -u
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
load_global || exit 1
PENDING="$STATE/update-pending"; GUARD="$STATE/update-guard.pid"

pending_get() { key="$1"; [ -f "$PENDING" ] || return 1; sed -n "s/^${key}=//p" "$PENDING" | head -n1; }
pending_validate() {
    MODULE="$(pending_get MODULE 2>/dev/null || true)"; VERSION="$(pending_get VERSION 2>/dev/null || true)"; STAMP="$(pending_get STAMP 2>/dev/null || true)"
    safe_id "$MODULE" && safe_id "$VERSION" && safe_id "$STAMP" || return 1
    case "$MODULE" in smart-routing|vpn|dns|nfqws|watchdog|diagnostics) ;; *) return 1;; esac
    DEST="$OURFW/modules/$MODULE"; BACK="$OURFW/history/${MODULE}-${STAMP}"; [ -d "$BACK" ] || return 1
}
restore_pending() {
    pending_validate || { log "component rollback: invalid pending state"; return 1; }
    rm -rf "$DEST"; cp -a "$BACK" "$DEST" || return 1
    [ ! -x "$DEST/apply.sh" ] || "$DEST/apply.sh" >/tmp/ourfw-update-restore.log 2>&1 || return 1
}
rollback_pending() {
    [ -f "$PENDING" ] || { echo "NO_UPDATE_PENDING=1"; return 0; }
    kill_pidfile "$GUARD"
    if restore_pending; then rm -f "$PENDING"; log "component update rolled back"; echo "UPDATE_ROLLED_BACK=1"; return 0; fi
    return 1
}
confirm_pending() {
    [ -f "$PENDING" ] || { echo "NO_UPDATE_PENDING=1"; return 0; }
    pending_validate || return 1; kill_pidfile "$GUARD"
    keep="${HISTORY_KEEP:-2}"
    ls -1dt "$OURFW/history/${MODULE}-"* 2>/dev/null | awk -v k="$keep" 'NR>k{print}' | while IFS= read -r old; do rm -rf "$old"; done
    if ! save_storage; then restore_pending >/dev/null 2>&1 || true; rm -f "$PENDING"; echo "UPDATE_CONFIRM_FAILED=1" >&2; return 1; fi
    rm -f "$PENDING"; log "component $MODULE updated to $VERSION and confirmed"
    echo "UPDATE_CONFIRMED=1"; echo "MODULE=$MODULE"; echo "VERSION=$VERSION"
}
install_pkg() {
    PKG="${1:-}"; EXPECTED="${2:-}"
    if [ -f "$STATE/pending" ] && ! pid_alive "$STATE/rollback-guard.pid"; then
        log "component update: stale configuration pending; restoring last-good"
        OURFW_LOCK_HELD=1 "$OURFW/runtime/ourfw-rollback.sh" now >/dev/null 2>&1 || return 2
    fi
    if [ -f "$PENDING" ] && ! pid_alive "$GUARD"; then
        log "component update: stale component pending; restoring previous module"
        rollback_pending >/dev/null 2>&1 || return 2
    fi
    [ ! -f "$STATE/pending" ] || { echo "configuration transaction is pending" >&2; return 2; }
    [ ! -f "$PENDING" ] || { echo "component transaction is pending" >&2; return 2; }
    [ -f "$PKG" ] || { echo "package not found" >&2; return 2; }; case "$PKG" in /tmp/*) ;; *) echo "package must be in /tmp" >&2; return 2;; esac
    [ ${#EXPECTED} -eq 64 ] || { echo "expected sha256 required" >&2; return 2; }; case "$EXPECTED" in ''|*[!0-9A-Fa-f]*) return 2;; esac
    need sha256sum || return 3; ACTUAL=$(sha256sum "$PKG" | awk '{print $1}')
    [ "$(echo "$ACTUAL" | tr A-F a-f)" = "$(echo "$EXPECTED" | tr A-F a-f)" ] || { echo "sha256 mismatch" >&2; return 4; }
    STAGE="$STATE/update.$$"; rm -rf "$STAGE"; mkdir -p "$STAGE"; LIST="$STATE/update-list.$$"
    tar -tjf "$PKG" > "$LIST" 2>/dev/null || { rm -rf "$STAGE" "$LIST"; return 5; }
    while IFS= read -r member; do
        case "$member" in manifest.conf|./manifest.conf|payload|payload/|payload/*|./payload|./payload/|./payload/*) ;; *) echo "invalid archive member: $member" >&2; rm -rf "$STAGE" "$LIST"; return 5;; esac
        case "/$member/" in */../*) echo "unsafe archive path" >&2; rm -rf "$STAGE" "$LIST"; return 5;; esac
    done < "$LIST"
    if tar -tvjf "$PKG" 2>/dev/null | grep -Eq ' -> | link to '; then rm -rf "$STAGE" "$LIST"; echo "links are not allowed" >&2; return 5; fi
    rm -f "$LIST"; tar -xjf "$PKG" -C "$STAGE" || { rm -rf "$STAGE"; return 5; }; [ -f "$STAGE/manifest.conf" ] || return 6
    MODULE=$(sed -n 's/^module=//p' "$STAGE/manifest.conf" | head -n1); VERSION=$(sed -n 's/^version=//p' "$STAGE/manifest.conf" | head -n1); TYPE=$(sed -n 's/^type=//p' "$STAGE/manifest.conf" | head -n1); [ -n "$TYPE" ] || TYPE=module
    safe_id "$MODULE" && safe_id "$VERSION" && safe_id "$TYPE" || { rm -rf "$STAGE"; return 7; }; [ "$TYPE" = module ] || return 7
    case "$MODULE" in smart-routing|vpn|dns|nfqws|watchdog|diagnostics) ;; *) echo "module is not update-whitelisted" >&2; return 7;; esac
    [ -d "$STAGE/payload" ] || return 8; find "$STAGE/payload" -type l | grep -q . && { echo "symlinks are not allowed" >&2; return 8; }
    DEST="$OURFW/modules/$MODULE"; [ -d "$DEST" ] || { echo "base module missing" >&2; return 8; }
    STAMP="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo current)-$$"; safe_id "$STAMP" || STAMP="current-$$"; BACK="$OURFW/history/${MODULE}-${STAMP}"; cp -a "$DEST" "$BACK" || return 9
    NEW="$OURFW/modules/.${MODULE}.new.$$"; rm -rf "$NEW"; mkdir -p "$NEW"
    # Overlay package payload on the complete existing module. Partial updates can
    # no longer delete required hooks by omission.
    cp -a "$DEST/." "$NEW/" || return 9; cp -a "$STAGE/payload/." "$NEW/" || return 9
    printf '%s\n' "$VERSION" > "$NEW/.version"; find "$NEW" -type f -name '*.sh' -exec chmod 755 {} \; 2>/dev/null
    [ -x "$NEW/apply.sh" ] && [ -x "$NEW/start.sh" ] || { echo "resulting module lacks apply.sh/start.sh" >&2; rm -rf "$NEW" "$STAGE"; return 10; }
    [ ! -x "$NEW/health.sh" ] || "$NEW/health.sh" preinstall || { rm -rf "$NEW" "$STAGE"; return 10; }
    { printf 'MODULE=%s\n' "$MODULE"; printf 'VERSION=%s\n' "$VERSION"; printf 'STAMP=%s\n' "$STAMP"; } > "$PENDING" || return 10
    # Arm rollback before replacing/applying files.
    (
        sleep "$ROLLBACK_TIMEOUT"; n=0
        while [ -f "$PENDING" ] && [ "$n" -lt 15 ]; do
            "$0" rollback >/dev/null 2>&1 && exit 0
            n=$((n+1)); sleep 2
        done
    ) >/dev/null 2>&1 &
    echo $! > "$GUARD"
    rm -rf "$DEST"; mv "$NEW" "$DEST" || { OURFW_LOCK_HELD=1 "$0" rollback >/dev/null 2>&1 || true; return 11; }
    if [ -x "$DEST/health.sh" ] && ! "$DEST/health.sh" postinstall; then OURFW_LOCK_HELD=1 "$0" rollback >/dev/null 2>&1 || true; return 12; fi
    if ! "$DEST/apply.sh"; then OURFW_LOCK_HELD=1 "$0" rollback >/dev/null 2>&1 || true; return 13; fi
    rm -rf "$STAGE"; log "component $MODULE candidate $VERSION applied; awaiting confirmation"
    echo "UPDATE_PENDING_CONFIRM=1"; echo "MODULE=$MODULE"; echo "VERSION=$VERSION"; echo "ROLLBACK_IN=$ROLLBACK_TIMEOUT"
}

ACTION="${1:-}"
# One atomic lock across config and component transactions. Internal rollback uses
# OURFW_LOCK_HELD=1 to avoid recursively acquiring it.
if [ "${OURFW_LOCK_HELD:-0}" != "1" ]; then
    txn_lock_acquire || { echo "another transaction is active" >&2; exit 3; }
    trap 'txn_lock_release >/dev/null 2>&1 || true' EXIT HUP INT TERM
fi
case "$ACTION" in
  confirm) confirm_pending ;;
  rollback) rollback_pending ;;
  install) shift; install_pkg "$@" ;;
  /tmp/*) install_pkg "$@" ;;
  *) echo "usage: ourfw-update.sh {install <pkg> <sha256>|confirm|rollback}" >&2; exit 2 ;;
esac
