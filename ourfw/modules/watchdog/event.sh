#!/bin/sh
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
[ "${1:-}" = internet ] || exit 0
state="${2:-}"; now="$(date +%s 2>/dev/null || echo 0)"
printf '%s %s\n' "$now" "$state" > "$STATE/inet-state"
# A network-changing candidate should never strand the administrator. Padavan's
# detector is event-driven, so use it as an early rollback hint; the independent
# 90-second guard remains authoritative.
if [ "$state" != 1 ] && { [ -f "$STATE/pending" ] || [ -f "$STATE/update-pending" ]; }; then
    (
      sleep 3
      cur="$(nvram get link_internet 2>/dev/null || true)"
      [ "$cur" = 1 ] && exit 0
      if [ -f "$STATE/pending" ]; then "$OURFW/runtime/ourfw-rollback.sh" now >/dev/null 2>&1 || true; fi
      if [ -f "$STATE/update-pending" ]; then "$OURFW/runtime/ourfw-update.sh" rollback >/dev/null 2>&1 || true; fi
    ) >/dev/null 2>&1 &
fi
exit 0
