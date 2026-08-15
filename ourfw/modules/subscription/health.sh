#!/bin/sh
. /etc/storage/ourfw/modules/subscription/common.sh 2>/dev/null || exit 1
subscription_load_conf >/dev/null 2>&1 || SUBSCRIPTION_ENABLED=0
subscription_ensure_runtime >/dev/null 2>&1 || true

nodes=0
[ -f "$SUB_META" ] && nodes="$(wc -l < "$SUB_META" 2>/dev/null | tr -d '[:space:]')"
is_uint "$nodes" || nodes=0
fetch_result="$(sed -n 's/^RESULT=//p' "$SUB_STATE/fetch.status" 2>/dev/null | head -n1)"
parse_result="$(sed -n 's/^RESULT=//p' "$SUB_STATE/parse.status" 2>/dev/null | head -n1)"
[ -n "$fetch_result" ] || fetch_result=idle
[ -n "$parse_result" ] || parse_result=idle
case "$fetch_result" in *[!A-Za-z0-9_.-]*) fetch_result=redacted;; esac
case "$parse_result" in *[!A-Za-z0-9_.-]*) parse_result=redacted;; esac

printf '{"ok":true,"enabled":%s,"refresh":"%s","nodes":%s,"fetch":"%s","parse":"%s"}\n' \
  "$([ "${SUBSCRIPTION_ENABLED:-0}" = 1 ] && echo true || echo false)" \
  "$(json_escape "${SUBSCRIPTION_REFRESH:-manual}")" "$nodes" \
  "$(json_escape "$fetch_result")" "$(json_escape "$parse_result")"
