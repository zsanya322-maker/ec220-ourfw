#!/bin/sh
# Boot is intentionally passive: create protected state only. No fetch, parser
# refresh, route, DNS or firewall operation is allowed from this hook.
exec /bin/sh /etc/storage/ourfw/modules/subscription/apply.sh ensure
