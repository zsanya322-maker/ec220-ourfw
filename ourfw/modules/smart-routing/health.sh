#!/bin/sh
for x in iptables ipset ip; do command -v "$x" >/dev/null 2>&1 || exit 1; done
exit 0
