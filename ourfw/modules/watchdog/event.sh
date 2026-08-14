#!/bin/sh
[ "${1:-}" = "wan" ] || exit 0
# The daemon will observe state; do not restart it for every WAN transition.
exit 0
