#!/bin/bash
set -euo pipefail
TREE=${1:-padavan-ng}
LOG=${2:-build.log}
ROMFS="$TREE/trunk/romfs"
REPORT=${3:-ROMFS-VERIFY.txt}

fail() { echo "ROMFS VERIFY FAILED: $*" >&2; exit 40; }
[[ -d "$ROMFS" ]] || fail "missing ROMFS: $ROMFS"

# Padavan's user build loop can continue after a child make failure. Never accept
# an image if any recursive make actually emitted a fatal target error.
if [[ -f "$LOG" ]] && grep -Eq 'make\[[0-9]+\]: \*\*\* .* Error [0-9]+' "$LOG"; then
  echo 'Fatal make errors found in build log:' >&2
  grep -En 'make\[[0-9]+\]: \*\*\* .* Error [0-9]+' "$LOG" >&2 || true
  exit 41
fi

required=(
  usr/bin/ourfw-loader.sh
  usr/share/ourfw/defaults.tar.bz2
  www/ourfw/index.asp
  usr/sbin/httpd
  usr/sbin/dropbear
  usr/sbin/wg
  usr/sbin/awg
  usr/bin/nfqws
  usr/bin/zapret.sh
  usr/bin/sha256sum
  usr/bin/autostart.sh
)
for rel in "${required[@]}"; do
  [[ -e "$ROMFS/$rel" ]] || fail "missing $rel"
done
[[ -x "$ROMFS/usr/bin/ourfw-loader.sh" ]] || fail 'OURFW loader is not executable'
[[ -s "$ROMFS/usr/share/ourfw/defaults.tar.bz2" ]] || fail 'defaults archive is empty'
[[ -s "$ROMFS/usr/sbin/wg" && -s "$ROMFS/usr/sbin/awg" && -s "$ROMFS/usr/bin/nfqws" ]] || fail 'VPN/nfqws binary empty'

grep -aq 'ourfw_api.cgi' "$ROMFS/usr/sbin/httpd" || fail 'OURFW API bridge missing from compiled httpd'
grep -q 'ourfw-loader.sh' "$ROMFS/usr/bin/autostart.sh" || fail 'OURFW loader missing from autostart'

# The immutable defaults archive must actually contain the mutable controller/UI.
# Materialise the list once: with pipefail, `tar | grep -q` can look like failure
# because grep exits early and tar receives SIGPIPE.
defaults_list=$(mktemp)
trap 'rm -f "$defaults_list"' EXIT
tar -tjf "$ROMFS/usr/share/ourfw/defaults.tar.bz2" > "$defaults_list" || fail 'cannot list defaults archive'
for item in './runtime/ourfwctl.sh' './runtime/ourfw-api.sh' './modules/smart-routing/apply.sh' './modules/vpn/apply.sh' './modules/nfqws/apply.sh' './www/index.asp'; do
  grep -qx "$item" "$defaults_list" || fail "defaults archive missing $item"
done

# Kernel capabilities required by OURFW.
for mod in wireguard.ko amneziawg.ko nfnetlink_queue.ko xt_NFQUEUE.ko ip6table_mangle.ko; do
  find "$ROMFS/lib/modules" -type f -name "$mod" -print -quit | grep -q . || fail "kernel module missing: $mod"
done

{
  echo 'ROMFS_VERIFY=OK'
  echo "ROMFS_BYTES=$(du -sb "$ROMFS" | awk '{print $1}')"
  echo "OURFW_DEFAULTS_BYTES=$(stat -c %s "$ROMFS/usr/share/ourfw/defaults.tar.bz2")"
  echo "WG_BYTES=$(stat -c %s "$ROMFS/usr/sbin/wg")"
  echo "AWG_BYTES=$(stat -c %s "$ROMFS/usr/sbin/awg")"
  echo "NFQWS_BYTES=$(stat -c %s "$ROMFS/usr/bin/nfqws")"
  echo 'MODULES:'
  for mod in wireguard.ko amneziawg.ko nfnetlink_queue.ko xt_NFQUEUE.ko ip6table_mangle.ko; do
    find "$ROMFS/lib/modules" -type f -name "$mod" -printf '%P %s bytes\n'
  done
} | tee "$REPORT"
