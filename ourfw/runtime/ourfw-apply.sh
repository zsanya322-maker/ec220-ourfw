#!/bin/sh
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
load_global || exit 1
. /etc/storage/ourfw/runtime/ourfw-scope.sh || exit 1

TAG="${1:-default}"
safe_id "$TAG" || exit 2
SCOPE="$(scope_for_tag "$TAG")" || exit 2
scope_modules "$SCOPE" >/dev/null || exit 2

LOCKED=0
if [ "${OURFW_LOCK_HELD:-0}" != "1" ]; then
    txn_lock_acquire || { echo "another transaction is active" >&2; exit 3; }
    LOCKED=1
    trap 'txn_lock_release >/dev/null 2>&1 || true' EXIT HUP INT TERM
fi

pending_cleanup_meta() {
    rm -f "$STATE/pending-scope" "$STATE/pending-tag" "$STATE/pending-start" "$STATE/pending-deadline"
}

# A stale marker means the old caller died. Restore the exact last-good files
# using the scope that old candidate actually touched.
if [ -f "$STATE/pending" ]; then
    if pid_alive "$STATE/rollback-guard.pid"; then
        echo "another transaction is pending" >&2
        exit 3
    fi
    log "configuration: stale pending detected; restoring last-good"
    OURFW_LOCK_HELD=1 "$OURFW/runtime/ourfw-rollback.sh" now >/dev/null 2>&1 || {
        echo "stale rollback failed" >&2
        exit 4
    }
fi
if [ -f "$STATE/update-pending" ]; then
    if pid_alive "$STATE/update-guard.pid"; then
        echo "component transaction is pending" >&2
        exit 3
    fi
    log "configuration: stale component pending detected; restoring module"
    OURFW_LOCK_HELD=1 "$OURFW/runtime/ourfw-update.sh" rollback >/dev/null 2>&1 || {
        echo "stale component rollback failed" >&2
        exit 4
    }
fi

[ -f "$STATE/last-good.tar" ] ||
    ( cd "$OURFW" && tar -cf "$STATE/last-good.tar" config profiles rules 2>/dev/null ) ||
    exit 4

printf '%s\n' "$TAG" > "$STATE/pending" || exit 4
printf '%s\n' "$TAG" > "$STATE/pending-tag" || { rm -f "$STATE/pending"; exit 4; }
printf '%s\n' "$SCOPE" > "$STATE/pending-scope" || { rm -f "$STATE/pending"; pending_cleanup_meta; exit 4; }

NOW="$(date +%s 2>/dev/null || echo 0)"
is_uint "$NOW" || NOW=0
DEADLINE=0
[ "$NOW" -gt 0 ] 2>/dev/null && DEADLINE=$((NOW + ROLLBACK_TIMEOUT))
printf '%s\n' "$NOW" > "$STATE/pending-start"
printf '%s\n' "$DEADLINE" > "$STATE/pending-deadline"

# Arm rollback before candidate files are moved into place.
(
    sleep "$ROLLBACK_TIMEOUT"
    _n=0
    while [ -f "$STATE/pending" ] && [ "$_n" -lt 15 ]; do
        "$OURFW/runtime/ourfw-rollback.sh" now >/dev/null 2>&1 && exit 0
        _n=$((_n+1))
        sleep 2
    done
) >/dev/null 2>&1 &
echo $! > "$STATE/rollback-guard.pid"

install_candidate() {
    if [ -n "${OURFW_CANDIDATE_SRC:-}" ] || [ -n "${OURFW_CANDIDATE_REL:-}" ]; then
        _src="${OURFW_CANDIDATE_SRC:-}"
        _rel="${OURFW_CANDIDATE_REL:-}"
        [ -f "$_src" ] || { log "candidate: source missing"; return 1; }
        case "$_src" in /tmp/ourfw-*|/tmp/ourfw/*) ;; *) log "candidate: unsafe source"; return 1;; esac
        case "$_rel" in
          config/*.conf|profiles/vpn.conf|profiles/openvpn.ovpn|profiles/openvpn.auth|profiles/nfqws.strategy|rules/*.list|dnsmasq-ourfw.conf) ;;
          *) log "candidate: unsafe destination $_rel"; return 1 ;;
        esac
        _dst="$OURFW/$_rel"
        mkdir -p "$(dirname "$_dst")" || return 1
        _tmp="$_dst.candidate.$$"
        cp "$_src" "$_tmp" || return 1
        case "$_rel" in
          profiles/vpn.conf|profiles/openvpn.ovpn|profiles/openvpn.auth|config/vpn.conf) chmod 600 "$_tmp" 2>/dev/null || true ;;
          *) chmod 644 "$_tmp" 2>/dev/null || true ;;
        esac
        mv "$_tmp" "$_dst" || return 1
        log "candidate installed: $_rel"
    fi

    if [ -n "${OURFW_CANDIDATE_PATCH:-}" ]; then
        _arc="$OURFW_CANDIDATE_PATCH"
        case "$_arc" in /tmp/ourfw-*|/tmp/ourfw/*) ;; *) log "candidate patch: unsafe source"; return 1;; esac
        [ -f "$_arc" ] || return 1
        _stage="$STATE/patch-tree.$$"
        rm -rf "$_stage"
        mkdir -p "$_stage" || return 1
        bzip2 -dc "$_arc" | tar -xf - -C "$_stage" || { rm -rf "$_stage"; return 1; }
        for _top in config profiles rules; do
            [ -d "$_stage/$_top" ] || continue
            find "$_stage/$_top" -type f | while IFS= read -r _src; do
                _rel=${_src#"$_stage"/}
                _dst="$OURFW/$_rel"
                mkdir -p "$(dirname "$_dst")" || exit 1
                _tmp="$_dst.candidate.$$"
                cp "$_src" "$_tmp" || exit 1
                case "$_rel" in
                  profiles/vpn.conf|profiles/openvpn.ovpn|profiles/openvpn.auth|config/vpn.conf) chmod 600 "$_tmp" 2>/dev/null || true ;;
                  *) chmod 644 "$_tmp" 2>/dev/null || true ;;
                esac
                mv "$_tmp" "$_dst" || exit 1
            done || { rm -rf "$_stage"; return 1; }
        done
        rm -rf "$_stage"
        log "candidate patch installed"
    fi

    if [ -n "${OURFW_CANDIDATE_BACKUP:-}" ]; then
        _arc="$OURFW_CANDIDATE_BACKUP"
        case "$_arc" in /tmp/ourfw-*|/tmp/ourfw/*) ;; *) log "candidate backup: unsafe source"; return 1;; esac
        [ -f "$_arc" ] || return 1
        _stage="$STATE/restore-tree.$$"
        rm -rf "$_stage"
        mkdir -p "$_stage" || return 1
        bzip2 -dc "$_arc" | tar -xf - -C "$_stage" || { rm -rf "$_stage"; return 1; }
        for _d in config profiles rules; do
            [ -d "$_stage/$_d" ] || { rm -rf "$_stage"; log "backup restore: missing $_d"; return 1; }
        done
        rm -rf "$OURFW/config" "$OURFW/profiles" "$OURFW/rules"
        cp -a "$_stage/config" "$_stage/profiles" "$_stage/rules" "$OURFW/" || { rm -rf "$_stage"; return 1; }
        find "$OURFW" -type f -name '*.sh' -exec chmod 755 {} \; 2>/dev/null || true
        for _sf in "$OURFW/config/vpn.conf" "$OURFW/profiles/vpn.conf" "$OURFW/profiles/openvpn.ovpn" "$OURFW/profiles/openvpn.auth"; do
            [ -f "$_sf" ] && chmod 600 "$_sf" 2>/dev/null || true
        done
        rm -rf "$_stage"
        log "backup candidate installed"
    fi
}

log "candidate begin: tag=$TAG scope=$SCOPE"
if ! install_candidate; then
    OURFW_LOCK_HELD=1 "$OURFW/runtime/ourfw-rollback.sh" now >/dev/null 2>&1 || true
    exit 5
fi

if ! scope_apply "$SCOPE"; then
    OURFW_LOCK_HELD=1 "$OURFW/runtime/ourfw-rollback.sh" now >/dev/null 2>&1 || true
    exit 5
fi

echo "PENDING_CONFIRM=1"
echo "ROLLBACK_IN=$ROLLBACK_TIMEOUT"
echo "SCOPE=$SCOPE"
echo "TAG=$TAG"
