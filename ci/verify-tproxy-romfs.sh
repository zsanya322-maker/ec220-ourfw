#!/bin/bash
set -euo pipefail
TREE=${1:-padavan-ng}
REPORT=${2:-TPROXY-ROMFS-VERIFY.txt}
ROMFS="$TREE/trunk/romfs"
: > "$REPORT"
log() { printf '%s\n' "$*" | tee -a "$REPORT"; }

snapshot() {
  log '--- TPROXY_DIAGNOSTICS_BEGIN ---'
  if [[ -d "$ROMFS" ]]; then
    log 'ROMFS_MATCHES:'
    find "$ROMFS" -type f \( -iname '*tproxy*' -o -iname '*socket*' -o -iname '*xtable*' -o -iname '*iptables*' \) \
      -printf '%P %s\n' 2>/dev/null | sort | tee -a "$REPORT" || true
  else
    log 'ROMFS_MISSING=1'
  fi

  log 'BUILD_TREE_MATCHES:'
  find "$TREE/trunk" -type f \( -name 'xt_TPROXY.ko' -o -name 'xt_socket.ko' -o -name 'libxt_TPROXY.so' -o -name 'libxt_socket.so' \) \
    -printf '%P %s\n' 2>/dev/null | sort | head -100 | tee -a "$REPORT" || true

  cfg="$TREE/trunk/configs/boards/TPLINK/TL_EC220_G5-V2/kernel-3.4.x.config"
  if [[ -f "$cfg" ]]; then
    log 'KCONFIG_TPROXY:'
    grep -E 'CONFIG_(NETFILTER_TPROXY|NETFILTER_XT_TARGET_TPROXY|NETFILTER_XT_MATCH_SOCKET|IP_MULTIPLE_TABLES)=' "$cfg" \
      | tee -a "$REPORT" || true
  fi
  log '--- TPROXY_DIAGNOSTICS_END ---'
}

fail() {
  log 'TPROXY_ROMFS_VERIFY=FAILED'
  log "ERROR=$*"
  snapshot
  exit 51
}

[[ -d "$ROMFS/lib/modules" ]] || fail 'missing lib/modules'

tproxy_mod=$(find "$ROMFS/lib/modules" -type f -name 'xt_TPROXY.ko' -print -quit)
socket_mod=$(find "$ROMFS/lib/modules" -type f -name 'xt_socket.ko' -print -quit)
[[ -n "$tproxy_mod" && -s "$tproxy_mod" ]] || fail 'xt_TPROXY.ko was not built/packed'
[[ -n "$socket_mod" && -s "$socket_mod" ]] || fail 'xt_socket.ko was not built/packed'

userspace=NO
multi=$(find "$ROMFS" -type f \( -name 'xtables-legacy-multi' -o -name 'iptables-multi' -o -name 'iptables' \) -print -quit)
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
