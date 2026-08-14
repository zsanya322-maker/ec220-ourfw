#!/bin/sh
# OURFW immutable rescue loader. Keep this tiny: it must never be the reason
# base Padavan fails to boot.
BASE=/etc/storage/ourfw
CTL="$BASE/runtime/ourfwctl.sh"
DEFAULTS=/usr/share/ourfw/defaults.tar.bz2
DISABLE=/etc/storage/ourfw.disabled
RESET=/etc/storage/ourfw.reset
LOG=/tmp/ourfw-loader.log
WEB_DST=/www/ourfw

log() { echo "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null) $*" >> "$LOG"; }

seed_defaults() {
    [ -r "$DEFAULTS" ] || { log "defaults archive missing: $DEFAULTS"; return 1; }
    mkdir -p "$BASE" || return 1
    if command -v bzcat >/dev/null 2>&1; then
        bzcat "$DEFAULTS" | tar -xf - -C "$BASE" || return 1
    else
        bzip2 -dc "$DEFAULTS" | tar -xf - -C "$BASE" || return 1
    fi
    find "$BASE" -type f -name '*.sh' -exec chmod 0755 {} \; 2>/dev/null
    log "mutable OURFW seeded from firmware defaults"
}

preflight_mutable() {
    bad=0
    for f in "$BASE"/runtime/*.sh "$BASE"/modules/*/*.sh; do
        [ -f "$f" ] || continue
        sh -n "$f" >/dev/null 2>&1 || { log "preflight failed: $f"; bad=1; }
    done
    [ "$bad" -eq 0 ]
}

mount_mutable_ui() {
    [ -d "$BASE/www" ] || return 0
    [ -d "$WEB_DST" ] || { log "immutable WebUI mountpoint missing"; return 1; }
    grep -q " $WEB_DST " /proc/mounts 2>/dev/null && return 0
    mount -o bind "$BASE/www" "$WEB_DST" >/dev/null 2>&1 || {
        log "bind mount WebUI failed; immutable fallback remains active"
        return 1
    }
    log "mutable WebUI mounted on $WEB_DST"
}

# One-file rescue switch: base Padavan boots, all OURFW mutable code stays off.
[ -e "$DISABLE" ] && { log "disabled by $DISABLE"; exit 0; }

# Explicit reset to firmware defaults. Preserve broken tree in /tmp for this boot.
if [ -e "$RESET" ]; then
    stamp="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo boot)"
    if [ -d "$BASE" ]; then
        rm -rf "/tmp/ourfw-rescue-$stamp" 2>/dev/null
        mv "$BASE" "/tmp/ourfw-rescue-$stamp" 2>/dev/null || rm -rf "$BASE"
    fi
    rm -f "$RESET"
    seed_defaults || exit 0
    /sbin/mtd_storage.sh save >/dev/null 2>&1 || true
fi

# First boot after flashing.
if [ ! -x "$CTL" ]; then
    seed_defaults || exit 0
    /sbin/mtd_storage.sh save >/dev/null 2>&1 || true
fi

[ -x "$CTL" ] || { log "controller unavailable"; exit 0; }
preflight_mutable || { log "mutable OURFW rejected; base Padavan continues"; exit 0; }
mount_mutable_ui || true
"$CTL" boot >>"$LOG" 2>&1 || log "controller boot failed rc=$?; base Padavan remains available"
exit 0
