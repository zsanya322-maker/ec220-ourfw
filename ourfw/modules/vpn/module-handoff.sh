#!/bin/sh
# WireGuard and AmneziaWG in the pinned 3.4 kernel export at least one common
# symbol. They are therefore treated as mutually exclusive runtime modules.
target="${1:-}"
PROC_MODULES="${OURFW_PROC_MODULES:-/proc/modules}"
MODPROBE="${OURFW_MODPROBE:-/sbin/modprobe}"

log_handoff() {
    logger -t OURFW -- "$*" 2>/dev/null || true
    [ -d /tmp/ourfw ] && printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$*" >> /tmp/ourfw.log 2>/dev/null || true
}

module_loaded() {
    [ -r "$PROC_MODULES" ] && grep -q "^$1[[:space:]]" "$PROC_MODULES" 2>/dev/null
}

case "$target" in
  wireguard) other=amneziawg ;;
  amneziawg) other=wireguard ;;
  *) log_handoff "vpn: invalid WG-family module target: $target"; exit 2 ;;
esac

[ -r "$PROC_MODULES" ] || { log_handoff "vpn: cannot read module state: $PROC_MODULES"; exit 3; }
[ -x "$MODPROBE" ] || { log_handoff "vpn: modprobe helper unavailable: $MODPROBE"; exit 3; }

if module_loaded "$other"; then
    log_handoff "vpn: unloading conflicting kernel module $other before $target"
    "$MODPROBE" -r "$other" >/dev/null 2>&1 || { log_handoff "vpn: cannot unload conflicting module $other"; exit 4; }
    module_loaded "$other" && { log_handoff "vpn: conflicting module $other is still loaded"; exit 5; }
fi

if ! module_loaded "$target"; then
    "$MODPROBE" -q "$target" >/dev/null 2>&1 || { log_handoff "vpn: cannot load kernel module $target"; exit 6; }
fi
module_loaded "$target" || { log_handoff "vpn: module $target did not become active"; exit 7; }
exit 0
