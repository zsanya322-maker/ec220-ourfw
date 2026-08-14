#!/bin/sh
[ "${1:-}" = "wan" ] || exit 0
[ "${2:-}" = "up" ] || exit 0
exec /etc/storage/ourfw/modules/dns/apply.sh
