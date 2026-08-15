#!/bin/sh
[ -x /bin/iptables ] || exit 1
[ -x /sbin/ipset ] || exit 1
[ -x /bin/ip ] || exit 1
exit 0
