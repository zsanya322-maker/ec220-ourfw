#!/bin/sh
# OURFW immutable rescue loader. It must never be the reason base Padavan fails.
BASE="${OURFW_LOADER_BASE:-/etc/storage/ourfw}"
CTL="$BASE/runtime/ourfwctl.sh"
DEFAULTS="${OURFW_LOADER_DEFAULTS:-/usr/share/ourfw/defaults.tar.bz2}"
DISABLE="${OURFW_LOADER_DISABLE:-/etc/storage/ourfw.disabled}"
RESET="${OURFW_LOADER_RESET:-/etc/storage/ourfw.reset}"
LOG="${OURFW_LOADER_LOG:-/tmp/ourfw-loader.log}"
WEB_DST="${OURFW_LOADER_WEB_DST:-/www/ourfw}"
DNS_SAFE="$BASE/dnsmasq-ourfw.conf"
CSRF="${OURFW_LOADER_CSRF:-/tmp/ourfw-csrf.token}"
STORAGE_SAVE="${OURFW_LOADER_STORAGE_SAVE:-/sbin/mtd_storage.sh}"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null) $*" >> "$LOG"; }

persist_storage() {
    [ -x "$STORAGE_SAVE" ] && "$STORAGE_SAVE" save >/dev/null 2>&1 || true
}

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

normalize_mutable_perms() {
    find "$BASE" -type f -name '*.sh' -exec chmod 0755 {} \; 2>/dev/null
    for sf in "$BASE/config/vpn.conf" "$BASE/profiles/vpn.conf" "$BASE/profiles/openvpn.ovpn" "$BASE/profiles/openvpn.auth"; do [ -f "$sf" ] && chmod 0600 "$sf" 2>/dev/null || true; done
}

seed_defaults() {
    [ -r "$DEFAULTS" ] || { log "defaults archive missing: $DEFAULTS"; return 1; }
    mkdir -p "$BASE" || return 1
    if command -v bzcat >/dev/null 2>&1; then
        bzcat "$DEFAULTS" | tar -xf - -C "$BASE" || return 1
    else
        bzip2 -dc "$DEFAULTS" | tar -xf - -C "$BASE" || return 1
    fi
    normalize_mutable_perms
    ensure_dns_safe || true
    log "mutable OURFW seeded from firmware defaults"
}

defaults_version() {
    probe="/tmp/ourfw-default-probe.$$"
    rm -rf "$probe" 2>/dev/null
    mkdir -p "$probe" || return 1
    if command -v bzcat >/dev/null 2>&1; then
        bzcat "$DEFAULTS" | tar -xf - -C "$probe" >/dev/null 2>&1 || { rm -rf "$probe"; return 1; }
    else
        bzip2 -dc "$DEFAULTS" | tar -xf - -C "$probe" >/dev/null 2>&1 || { rm -rf "$probe"; return 1; }
    fi
    v="$(cat "$probe/VERSION" 2>/dev/null || true)"
    rm -rf "$probe"
    case "$v" in v[0-9]*.[0-9]*.[0-9]*) printf '%s\n' "$v";; *) return 1;; esac
}

refresh_defaults_if_needed() {
    [ -x "$CTL" ] || return 0
    new="$(defaults_version)" || { log 'cannot read firmware OURFW version; keeping current mutable tree'; return 1; }
    cur="$(cat "$BASE/VERSION" 2>/dev/null || true)"
    [ "$cur" = "$new" ] && return 0

    old="/tmp/ourfw-preupgrade.$$"
    rm -rf "$old" 2>/dev/null
    mv "$BASE" "$old" || { log 'cannot stage mutable OURFW for firmware refresh'; return 1; }
    if ! seed_defaults; then
        rm -rf "$BASE" 2>/dev/null
        mv "$old" "$BASE" 2>/dev/null || true
        ensure_dns_safe || true
        log "firmware OURFW refresh failed during seed; restored ${cur:-unknown}"
        return 1
    fi

    # User backup contract defines these three trees as persistent user data.
    # Overlay them onto the new firmware defaults so newly introduced files stay
    # available while existing settings/profiles/rules are preserved.
    for d in config profiles rules; do
        [ -d "$old/$d" ] || continue
        mkdir -p "$BASE/$d" || {
            rm -rf "$BASE"; mv "$old" "$BASE" 2>/dev/null || true; ensure_dns_safe || true; return 1;
        }
        cp -a "$old/$d/." "$BASE/$d/" || {
            rm -rf "$BASE"; mv "$old" "$BASE" 2>/dev/null || true; ensure_dns_safe || true; log "firmware OURFW refresh failed restoring $d"; return 1;
        }
    done
    normalize_mutable_perms
    ensure_dns_safe || true
    rm -rf "$old"
    persist_storage
    log "mutable OURFW refreshed from firmware ${cur:-unknown} -> $new; config/profiles/rules preserved"
    return 0
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
    persist_storage
fi

if [ ! -x "$CTL" ]; then
    seed_defaults || { ensure_dns_safe || true; exit 0; }
    persist_storage
fi

[ -x "$CTL" ] || { ensure_dns_safe || true; log "controller unavailable"; exit 0; }
refresh_defaults_if_needed || { clear_dns_policy; log 'mutable OURFW firmware refresh rejected; base Padavan continues'; exit 0; }
[ -x "$CTL" ] || { ensure_dns_safe || true; log "controller unavailable after refresh"; exit 0; }
preflight_mutable || { clear_dns_policy; log "mutable OURFW rejected; base Padavan continues"; exit 0; }
mount_mutable_ui || true
"$CTL" boot >>"$LOG" 2>&1 || log "controller boot failed rc=$?; base Padavan remains available"
exit 0
