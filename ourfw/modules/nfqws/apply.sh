#!/bin/sh
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
CFG="$OURFW/config/nfqws.conf"
NFQWS_ENABLED=0; NFQWS_WAN_IF=; NFQWS_LOG=0; NFQWS_STRATEGY="$OURFW/profiles/nfqws.strategy"
load_conf "$CFG" || exit 1
bool01 "$NFQWS_ENABLED" || exit 1
bool01 "$NFQWS_LOG" || exit 1
[ -x /usr/bin/zapret.sh ] || { [ "$NFQWS_ENABLED" = "0" ] && exit 0; log "nfqws: /usr/bin/zapret.sh missing"; exit 1; }

Z=/etc/storage/zapret
mkdir -p "$Z"

# OURFW is the sole nfqws orchestrator. The pinned Padavan firmware can expose
# stock zapret_* service toggles via NVRAM; disable enable/autostart-style keys
# in RAM so rc/firewall rebuilds cannot start a competing instance. Do not commit
# NVRAM, preserving stock settings for rescue mode.
if command -v nvram >/dev/null 2>&1; then
    nvram show 2>/dev/null | sed -n 's/^\(zapret_[A-Za-z0-9_]*\)=.*/\1/p' | while read k; do
        case "$k" in *enable*|*enabled*|*autostart*) nvram set "$k=0" >/dev/null 2>&1 || true;; esac
    done
fi
# OURFW owns these lists; zapret auto-host learning remains persistent because
# auto.list points back into OURFW storage.
for pair in "user.list:nfqws-user.list" "exclude.list:nfqws-exclude.list" "auto.list:nfqws-auto.list"; do
    a="${pair%%:*}"; b="${pair##*:}"
    rm -f "$Z/$a"
    ln -s "$OURFW/rules/$b" "$Z/$a" || exit 1
done

WAN="$NFQWS_WAN_IF"; [ -n "$WAN" ] || WAN="$(wan_if)"
C="$Z/config"
cat > "$C" <<EOT
ISP_INTERFACE=$WAN
NFQUEUE_NUM=200
LOG_LEVEL=$NFQWS_LOG
EOT

if [ "$NFQWS_ENABLED" = "0" ]; then
    /usr/bin/zapret.sh stop >/dev/null 2>&1 || true
    log "nfqws: disabled"
    exit 0
fi
[ -s "$NFQWS_STRATEGY" ] || { log "nfqws: strategy missing"; exit 1; }
# zapret.sh officially accepts an alternate strategy path as restart arg.
/usr/bin/zapret.sh restart "$NFQWS_STRATEGY" >/tmp/ourfw-nfqws.log 2>&1 || { log "nfqws: restart failed"; exit 1; }
# The current zapret.sh command set has no 'status'; verify the actual worker.
if command -v pidof >/dev/null 2>&1; then
    pidof nfqws >/dev/null 2>&1 || { log "nfqws: worker did not start"; exit 1; }
else
    ps 2>/dev/null | grep '[n]fqws' >/dev/null 2>&1 || { log "nfqws: worker did not start"; exit 1; }
fi
log "nfqws: active${WAN:+ on $WAN}"
exit 0
