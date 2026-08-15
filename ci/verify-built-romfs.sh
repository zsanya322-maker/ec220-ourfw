#!/bin/bash
set -euo pipefail
TREE=${1:-padavan-ng}
LOG=${2:-build.log}
ROMFS="$TREE/trunk/romfs"
REPORT=${3:-ROMFS-VERIFY.txt}

report_line() { printf '%s\n' "$*" | tee -a "$REPORT"; }
fail() { report_line "ROMFS_VERIFY=FAILED"; report_line "ERROR=$*"; echo "ROMFS VERIFY FAILED: $*" >&2; exit 40; }
: > "$REPORT"
[[ -d "$ROMFS" ]] || fail "missing ROMFS: $ROMFS"

# Resolve paths the way they will resolve inside the target rootfs.  `test -e`
# on the CI host is wrong for absolute symlinks such as
# /usr/sbin/dropbear -> /usr/bin/dropbearmulti.
romfs_exists() {
  local rel="$1" p="$ROMFS/$rel" target dir
  [[ -e "$p" ]] && return 0
  [[ -L "$p" ]] || return 1
  target=$(readlink "$p") || return 1
  if [[ "$target" = /* ]]; then
    [[ -e "$ROMFS$target" || -L "$ROMFS$target" ]]
  else
    dir=$(dirname "$p")
    [[ -e "$dir/$target" || -L "$dir/$target" ]]
  fi
}

# Padavan's user build loop can continue after a child make failure. Never accept
# an image if any recursive make actually emitted a fatal target error.
if [[ -f "$LOG" ]] && grep -Eq 'make\[[0-9]+\]: \*\*\* .* Error [0-9]+' "$LOG"; then
  report_line 'ROMFS_VERIFY=FAILED'
  report_line 'ERROR=fatal make errors found in build log'
  grep -En 'make\[[0-9]+\]: \*\*\* .* Error [0-9]+' "$LOG" | tee -a "$REPORT" >&2 || true
  exit 41
fi

required=(
  usr/bin/ourfw-loader.sh
  usr/share/ourfw/defaults.tar.bz2
  www/ourfw/index.asp
  www/ourfw/assets/ourfw.js
  www/ourfw/assets/ourfw.css
  usr/sbin/httpd
  usr/sbin/dropbear
  usr/sbin/wg
  usr/sbin/awg
  usr/bin/nfqws
  usr/bin/zapret.sh
  usr/bin/sha256sum
  bin/base64
  usr/bin/autostart.sh
)
for rel in "${required[@]}"; do
  romfs_exists "$rel" || fail "missing $rel"
done
[[ -x "$ROMFS/usr/bin/ourfw-loader.sh" ]] || fail 'OURFW loader is not executable'
[[ -s "$ROMFS/usr/share/ourfw/defaults.tar.bz2" ]] || fail 'defaults archive is empty'
[[ -s "$ROMFS/usr/sbin/wg" && -s "$ROMFS/usr/sbin/awg" && -s "$ROMFS/usr/bin/nfqws" ]] || fail 'VPN/nfqws binary empty'

grep -aq 'ourfw_api.cgi' "$ROMFS/usr/sbin/httpd" || fail 'OURFW API bridge missing from compiled httpd'
grep -aq 'file-chunk' "$ROMFS/usr/sbin/httpd" || fail 'v0.5 chunk bridge missing from compiled httpd'
grep -aq '/tmp/ourfw-csrf.token' "$ROMFS/usr/sbin/httpd" || fail 'CSRF token bridge missing from compiled httpd'
grep -q 'ourfw-loader.sh' "$ROMFS/usr/bin/autostart.sh" || fail 'OURFW loader missing from autostart'

# The immutable defaults archive must actually contain the mutable controller/UI.
defaults_list=$(mktemp)
trap 'rm -f "$defaults_list"' EXIT
tar -tjf "$ROMFS/usr/share/ourfw/defaults.tar.bz2" > "$defaults_list" || fail 'cannot list defaults archive'
for item in \
  './runtime/ourfwctl.sh' \
  './runtime/ourfw-api.sh' \
  './runtime/ourfw-transfer.sh' \
  './runtime/ourfw-backup.sh' \
  './runtime/ourfw-ui.sh' \
  './modules/smart-routing/apply.sh' \
  './modules/vpn/apply.sh' \
  './modules/nfqws/apply.sh' \
  './www/index.asp' \
  './www/assets/ourfw.js' \
  './www/assets/ourfw.css'; do
  grep -qx "$item" "$defaults_list" || fail "defaults archive missing $item"
done

# Kernel capabilities required by OURFW.
for mod in wireguard.ko amneziawg.ko nfnetlink_queue.ko xt_NFQUEUE.ko ip6table_mangle.ko; do
  find "$ROMFS/lib/modules" -type f -name "$mod" -print -quit | grep -q . || fail "kernel module missing: $mod"
done

report_line 'ROMFS_VERIFY=OK'
report_line "ROMFS_BYTES=$(du -sb "$ROMFS" | awk '{print $1}')"
report_line "OURFW_DEFAULTS_BYTES=$(stat -c %s "$ROMFS/usr/share/ourfw/defaults.tar.bz2")"
report_line "WG_BYTES=$(stat -c %s "$ROMFS/usr/sbin/wg")"
report_line "AWG_BYTES=$(stat -c %s "$ROMFS/usr/sbin/awg")"
report_line "NFQWS_BYTES=$(stat -c %s "$ROMFS/usr/bin/nfqws")"
report_line 'MODULES:'
for mod in wireguard.ko amneziawg.ko nfnetlink_queue.ko xt_NFQUEUE.ko ip6table_mangle.ko; do
  find "$ROMFS/lib/modules" -type f -name "$mod" -printf '%P %s bytes\n' | tee -a "$REPORT"
done
