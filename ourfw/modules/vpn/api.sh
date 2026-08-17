#!/bin/sh
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1

HY2="$OURFW/modules/vpn/hy2-tproxy.sh"
SUB_CONF="$OURFW/config/subscription.conf"
SUB_META="$STATE/subscription/nodes.meta"
SUB_SECRETS="$STATE/subscription/nodes.secret"
OP=${1:-}

reply() {
    ok="$1"; op="$2"; rc="$3"; detail="$4"
    detail="$(printf '%s' "$detail" | tr '\r\n' ';;')"
    printf '{"ok":%s,"module":"vpn","operation":"%s","rc":%d,"detail":"%s"}\n' \
      "$ok" "$(json_escape "$op")" "$rc" "$(json_escape "$detail")"
}

run_hy2() {
    op="$1"; shift
    [ -f "$HY2" ] || { reply false "$op" 3 'Hysteria runtime missing'; return 3; }
    out="$(/bin/sh "$HY2" "$@" 2>&1)"
    rc=$?
    [ "$rc" -eq 0 ] && ok=true || ok=false
    reply "$ok" "$op" "$rc" "$out"
    return "$rc"
}

selected_hy2_uri() {
    slot="$1"
    [ -f "$SUB_CONF" ] || return 1
    SUBSCRIPTION_PRIMARY_ID=
    SUBSCRIPTION_BACKUP_ID=
    load_conf "$SUB_CONF" >/dev/null 2>&1 || return 1
    case "$slot" in
      primary) id="${SUBSCRIPTION_PRIMARY_ID:-}" ;;
      backup) id="${SUBSCRIPTION_BACKUP_ID:-}" ;;
      *) return 1 ;;
    esac
    safe_id "$id" || return 1
    [ -f "$SUB_META" ] || return 1
    awk -F '|' -v id="$id" '$1==id && $2=="hysteria2" && $7=="hysteria" && $8=="experimental"{ok=1; exit} END{exit(ok?0:1)}' "$SUB_META" >/dev/null 2>&1 || return 1
    uri="$SUB_SECRETS/$id.uri"
    [ -f "$uri" ] && [ -s "$uri" ] || return 1
    printf '%s\n' "$uri"
}

case "$OP" in
  enable|disable)
    [ "$OP" = enable ] && value=1 || value=0
    candidate_conf_set "$OURFW/config/vpn.conf" "VPN_ENABLED" "$value" "web-vpn" >/tmp/ourfw-api-module.log 2>&1
    rc=$?
    printf '{"ok":%s,"module":"vpn","operation":"%s","pending":%s,"rc":%d}\n' \
      "$([ $rc -eq 0 ] && echo true || echo false)" "$OP" "$([ $rc -eq 0 ] && echo true || echo false)" "$rc"
    exit "$rc"
    ;;
  hy2-status)
    run_hy2 "$OP" status
    ;;
  hy2-prepare)
    run_hy2 "$OP" prepare
    ;;
  hy2-start-primary|hy2-start-backup)
    slot=${OP#hy2-start-}
    uri="$(selected_hy2_uri "$slot" 2>/dev/null || true)"
    if [ -z "$uri" ]; then
        reply false "$OP" 4 "selected ${slot} Hysteria2 node is unavailable; refresh and select a Hysteria2 node first"
        exit 4
    fi
    run_hy2 "$OP" start "$uri"
    ;;
  hy2-arm-smart)
    run_hy2 "$OP" arm smart
    ;;
  hy2-arm-all)
    run_hy2 "$OP" arm vpn-all
    ;;
  hy2-route-off)
    run_hy2 "$OP" route-off
    ;;
  hy2-stop)
    run_hy2 "$OP" stop
    ;;
  hy2-purge-runtime)
    run_hy2 "$OP" purge-runtime
    ;;
  hy2-confirm-*)
    token=${OP#hy2-confirm-}
    safe_id "$token" || { reply false "$OP" 2 'invalid confirmation token'; exit 2; }
    run_hy2 "$OP" confirm "$token"
    ;;
  *)
    printf '{"ok":false,"error":"unsupported operation"}\n'
    exit 2
    ;;
esac
