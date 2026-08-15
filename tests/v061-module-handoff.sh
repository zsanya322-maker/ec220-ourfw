#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
HELPER="$ROOT/ourfw/modules/vpn/module-handoff.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT INT TERM
MODS="$T/modules"
FAKE="$T/modprobe"
cat > "$FAKE" <<'SH'
#!/bin/sh
set -eu
mods=${OURFW_PROC_MODULES:?}
block=${OURFW_MODPROBE_BLOCK_REMOVE:-}
case "${1:-}" in
  -r)
    m=${2:-}
    [ "$m" != "$block" ] || exit 19
    awk -v m="$m" '$1!=m {print}' "$mods" > "$mods.tmp"
    mv "$mods.tmp" "$mods"
    ;;
  -q)
    m=${2:-}
    case "$m" in wireguard) other=amneziawg;; amneziawg) other=wireguard;; *) exit 20;; esac
    grep -q "^$other " "$mods" 2>/dev/null && exit 17
    grep -q "^$m " "$mods" 2>/dev/null || printf '%s 1 0 - Live 0x0\n' "$m" >> "$mods"
    ;;
  *) exit 21;;
esac
SH
chmod +x "$FAKE"

printf 'wireguard 1 0 - Live 0x0\n' > "$MODS"
OURFW_PROC_MODULES="$MODS" OURFW_MODPROBE="$FAKE" sh "$HELPER" amneziawg
grep -q '^amneziawg ' "$MODS"
! grep -q '^wireguard ' "$MODS"

OURFW_PROC_MODULES="$MODS" OURFW_MODPROBE="$FAKE" sh "$HELPER" wireguard
grep -q '^wireguard ' "$MODS"
! grep -q '^amneziawg ' "$MODS"

printf 'wireguard 1 0 - Live 0x0\n' > "$MODS"
set +e
OURFW_PROC_MODULES="$MODS" OURFW_MODPROBE="$FAKE" OURFW_MODPROBE_BLOCK_REMOVE=wireguard sh "$HELPER" amneziawg
rc=$?
set -e
[[ $rc -ne 0 ]]
grep -q '^wireguard ' "$MODS"
! grep -q '^amneziawg ' "$MODS"

echo 'V0.6.1 MODULE HANDOFF: OK'
