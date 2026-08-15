#!/bin/sh
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
ZRAM_MODE=auto; ZRAM_ALGO=auto
load_conf "$OURFW/config/zram.conf" || exit 1
case "$ZRAM_MODE" in off|auto|25|50) ;; *) log "zram: invalid mode"; exit 1;; esac
case "$ZRAM_ALGO" in auto|lzo|lz4) ;; *) log "zram: invalid algorithm"; exit 1;; esac
# Prevent Padavan's native zram policy from racing OURFW; keep this runtime-only.
have_exec nvram && nvram set zram_enable=0 >/dev/null 2>&1 || true
swapoff /dev/zram0 >/dev/null 2>&1 || true
if [ "$ZRAM_MODE" = off ]; then
    [ -w /sys/block/zram0/reset ] && echo 1 > /sys/block/zram0/reset 2>/dev/null || true
    modprobe -r zram >/dev/null 2>&1 || true
    log "zram: disabled"; exit 0
fi
need modprobe || exit 1; need mkswap || exit 1; need swapon || exit 1
modprobe -q zram >/dev/null 2>&1 || { log "zram: cannot load zram.ko"; exit 1; }
[ -e /dev/zram0 ] || { log "zram: /dev/zram0 missing"; exit 1; }
[ -w /sys/block/zram0/reset ] && echo 1 > /sys/block/zram0/reset 2>/dev/null || true
algo="$ZRAM_ALGO"
if [ "$algo" = auto ]; then
    if grep -qw lz4 /sys/block/zram0/comp_algorithm 2>/dev/null; then algo=lz4; else algo=lzo; fi
fi
if [ -w /sys/block/zram0/comp_algorithm ]; then
    echo "$algo" > /sys/block/zram0/comp_algorithm 2>/dev/null || { algo=lzo; echo lzo > /sys/block/zram0/comp_algorithm 2>/dev/null || true; }
fi
pct="$ZRAM_MODE"; [ "$pct" = auto ] && pct=25
memkb="$(awk '/^MemTotal:/{print $2; exit}' /proc/meminfo 2>/dev/null)"; is_uint "$memkb" || exit 1
bytes=$((memkb * 1024 * pct / 100)); [ "$bytes" -gt 0 ] || exit 1
echo "$bytes" > /sys/block/zram0/disksize 2>/dev/null || { log "zram: cannot set disksize"; exit 1; }
mkswap /dev/zram0 >/dev/null 2>&1 || { log "zram: mkswap failed"; exit 1; }
swapon -p 32767 /dev/zram0 >/dev/null 2>&1 || { log "zram: swapon failed"; exit 1; }
printf 'MODE=%s\nPERCENT=%s\nALGO=%s\nBYTES=%s\n' "$ZRAM_MODE" "$pct" "$algo" "$bytes" > "$STATE/zram.status"
log "zram: active ${pct}% algo=$algo bytes=$bytes"
exit 0
