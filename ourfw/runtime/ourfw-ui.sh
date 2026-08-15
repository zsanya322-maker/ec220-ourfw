#!/bin/sh
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
WEB_DST=/www/ourfw
case "${1:-}" in
  remount)
    [ -d "$OURFW/www" ] || exit 1
    [ -d "$WEB_DST" ] || exit 1
    umount "$WEB_DST" >/dev/null 2>&1 || true
    mount -o bind "$OURFW/www" "$WEB_DST" >/dev/null 2>&1 || exit 1
    ;;
  *) echo 'usage: ourfw-ui.sh remount' >&2; exit 2;;
esac
