#!/bin/bash
set -euo pipefail
TREE=${1:-padavan-ng}
REPORT=${2:-TPROXY-ROMFS-VERIFY.txt}
ROMFS="$TREE/trunk/romfs"
: > "$REPORT"
log() { printf '%s\n' "$*" | tee -a "$REPORT"; }
fail() { log 'TPROXY_ROMFS_VERIFY=FAILED'; log "ERROR=$*"; exit 51; }

[[ -d "$ROMFS/lib/modules" ]] || fail 'missing lib/modules'

tproxy_mod=$(find "$ROMFS/lib/modules" -type f -name 'xt_TPROXY.ko' -print -quit)
socket_mod=$(find "$ROMFS/lib/modules" -type f -name 'xt_socket.ko' -print -quit)
[[ -n "$tproxy_mod" && -s "$tproxy_mod" ]] || fail 'xt_TPROXY.ko was not built/packed'
[[ -n "$socket_mod" && -s "$socket_mod" ]] || fail 'xt_socket.ko was not built/packed'

userspace=NO
multi=$(find "$ROMFS" -type f \( -name 'xtables-legacy-multi' -o -name 'iptables-multi' \) -print -quit)
if [[ -n "$multi" ]] && grep -aq 'TPROXY target options' "$multi" && grep -aq 'socket match options' "$multi"; then
  userspace=BUILTIN
else
  tproxy_so=$(find "$ROMFS" -type f -name 'libxt_TPROXY.so' -print -quit)
  socket_so=$(find "$ROMFS" -type f -name 'libxt_socket.so' -print -quit)
  if [[ -n "$tproxy_so" && -s "$tproxy_so" && -n "$socket_so" && -s "$socket_so" ]]; then
    userspace=SHARED
  fi
fi
[[ "$userspace" != NO ]] || fail 'iptables userspace lacks TPROXY/socket extensions'

log 'TPROXY_ROMFS_VERIFY=OK'
log "XT_TPROXY_BYTES=$(stat -c %s "$tproxy_mod")"
log "XT_SOCKET_BYTES=$(stat -c %s "$socket_mod")"
log "IPTABLES_TPROXY_MODE=$userspace"
log "XT_TPROXY_PATH=${tproxy_mod#$ROMFS/}"
log "XT_SOCKET_PATH=${socket_mod#$ROMFS/}"
[[ -n "$multi" ]] && log "XTABLES_MULTI_PATH=${multi#$ROMFS/}"
