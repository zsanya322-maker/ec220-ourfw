#!/bin/sh
# OURFW immutable rescue loader. It must never be the reason base Padavan fails.
BASE=/etc/storage/ourfw
CTL="$BASE/runtime/ourfwctl.sh"
DEFAULTS=/usr/share/ourfw/defaults.tar.bz2
DISABLE=/etc/storage/ourfw.disabled
RESET=/etc/storage/ourfw.reset
LOG=/tmp/ourfw-loader.log
WEB_DST=/www/ourfw
DNS_SAFE="$BASE/dnsmasq-ourfw.conf"
CSRF=/tmp/ourfw-csrf.token

log() { echo "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null) $*" >> "$LOG"; }

ensure_dns_safe() {
    mkdir -p "$BASE" 2>/dev/null || return 1
    [ -f "$DNS_SAFE" ] || : > "$DNS_SAFE"
    return 0
}

clear_dns_policy() {
    ensure_dns_safe || return 0
    : > "$DNS_SAFE" 2>/dev/null || true
    # If dnsmasq already started earlier in boot, force it to re-read the now
    # empty OURFW include. Failure here must never block base Padavan boot.
    if command -v restart_dhcpd >/dev/null 2>&1; then
        restart_dhcpd >/dev/null 2>&1 || true
    elif [ -x /sbin/restart_dhcpd ]; then
        /sbin/restart_dhcpd >/dev/null 2>&1 || true
    fi
}

csrf_new() {
    umask 077
    token=""
    if command -v sha256sum >/dev/null 2>&1; then
        token="$(dd if=/dev/urandom bs=32 count=1 2>/dev/null | sha256sum 2>/dev/null | awk '{print $1}')"
    fi
    case "$token" in *[!0-9A-Fa-f]*) token="";; esac
    if [ "${#token}" -eq 64 ] 2>/dev/null; then
        printf '%s\n' "$token" > "$CSRF"; chmod 600 "$CSRF" 2>/dev/null
    else
        rm -f "$CSRF"; log 'CSRF token generation failed; mutating WebUI API stays unavailable'
    fi
}

seed_defaults() {
    [ -r "$DEFAULTS" ] || { log "defaults archive missing: $DEFAULTS"; return 1; }
    mkdir -p "$BASE" || return 1
    if command -v bzcat >/dev/null 2>&1; then
        bzcat "$DEFAULTS" | tar -xf - -C "$BASE" || return 1
    else
        bzip2 -dc "$DEFAULTS" | tar -xf - -C "$BASE" || return 1
    fi
    find "$BASE" -type f -name '*.sh' -exec chmod 0755 {} \; 2>/dev/null
    for sf in "$BASE/config/vpn.conf" "$BASE/profiles/vpn.conf" "$BASE/profiles/openvpn.ovpn" "$BASE/profiles/openvpn.auth"; do [ -f "$sf" ] && chmod 0600 "$sf" 2>/dev/null || true; done
    ensure_dns_safe || true
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
        log "bind mount WebUI failed; immutable fallback remains active"; return 1;
    }
    log "mutable WebUI mounted on $WEB_DST"
}

# Create safety primitives before any mutable-code decision. dnsmasq may reference
# this file even when OURFW is disabled or rejected; an empty file is valid.
ensure_dns_safe || true
csrf_new

[ -e "$DISABLE" ] && { clear_dns_policy; log "disabled by $DISABLE"; exit 0; }

if [ -e "$RESET" ]; then
    stamp="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo boot)"
    if [ -d "$BASE" ]; then
        rm -rf "/tmp/ourfw-rescue-$stamp" 2>/dev/null
        mv "$BASE" "/tmp/ourfw-rescue-$stamp" 2>/dev/null || rm -rf "$BASE"
    fi
    rm -f "$RESET"
    seed_defaults || { ensure_dns_safe || true; exit 0; }
    /sbin/mtd_storage.sh save >/dev/null 2>&1 || true
fi

if [ ! -x "$CTL" ]; then
    seed_defaults || { ensure_dns_safe || true; exit 0; }
    /sbin/mtd_storage.sh save >/dev/null 2>&1 || true
fi

[ -x "$CTL" ] || { ensure_dns_safe || true; log "controller unavailable"; exit 0; }
preflight_mutable || { clear_dns_policy; log "mutable OURFW rejected; base Padavan continues"; exit 0; }
mount_mutable_ui || true
"$CTL" boot >>"$LOG" 2>&1 || log "controller boot failed rc=$?; base Padavan remains available"
exit 0
