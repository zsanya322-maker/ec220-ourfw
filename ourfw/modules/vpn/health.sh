#!/bin/sh
CFG=/etc/storage/ourfw/config/vpn.conf
[ -f "$CFG" ] || exit 1
[ -x /usr/sbin/wg ] || exit 1
[ -x /usr/sbin/awg ] || exit 1
exit 0
