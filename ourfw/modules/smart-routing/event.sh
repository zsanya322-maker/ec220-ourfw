#!/bin/sh
case "${1:-}" in
 firewall|wan) exec /etc/storage/ourfw/modules/smart-routing/apply.sh ;;
 *) exit 0;;
esac
