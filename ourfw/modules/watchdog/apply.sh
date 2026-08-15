#!/bin/sh
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
CFG="$OURFW/config/watchdog.conf"; WATCHDOG_ENABLED=0
load_conf "$CFG" || exit 1
bool01 "$WATCHDOG_ENABLED" || exit 1
PF="$STATE/watchdog.pid"
kill_pidfile "$PF"
[ "$WATCHDOG_ENABLED" = "1" ] || { log "watchdog: disabled"; exit 0; }
"$OURFW/modules/watchdog/watchdog.sh" >/dev/null 2>&1 &
echo $! > "$PF"
sleep 1
pid_alive "$PF" || { log "watchdog: failed to start"; exit 1; }
log "watchdog: started pid=$(cat "$PF")"
exit 0
