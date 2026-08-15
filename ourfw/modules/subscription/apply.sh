#!/bin/sh
. /etc/storage/ourfw/modules/subscription/common.sh 2>/dev/null || exit 1

case "${1:-ensure}" in
  ensure|validate)
    subscription_load_conf || { log "subscription: invalid manager config"; exit 2; }
    subscription_ensure_runtime || exit 3
    subscription_ensure_salt || exit 4
    ;;
  *)
    echo "usage: apply.sh {ensure|validate}" >&2
    exit 2
    ;;
esac
