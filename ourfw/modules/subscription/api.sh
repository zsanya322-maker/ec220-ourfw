#!/bin/sh
. /etc/storage/ourfw/modules/subscription/common.sh 2>/dev/null || exit 1
subscription_ensure_runtime >/dev/null 2>&1 || exit 1

node_exists() {
    wanted="$1"
    [ -f "$SUB_META" ] || return 1
    awk -F '|' -v id="$wanted" '$1==id{found=1; exit} END{exit(found?0:1)}' "$SUB_META" >/dev/null 2>&1
}

nodes_json() {
    subscription_load_conf >/dev/null 2>&1 || true
    primary="${SUBSCRIPTION_PRIMARY_ID:-}"
    backup="${SUBSCRIPTION_BACKUP_ID:-}"
    printf '['
    first=1
    if [ -f "$SUB_META" ]; then
        while IFS='|' read -r id protocol label host port transport engine support || [ -n "$id" ]; do
            safe_id "$id" || continue
            [ "$first" -eq 1 ] || printf ','
            first=0
            [ "$id" = "$primary" ] && is_primary=true || is_primary=false
            [ "$id" = "$backup" ] && is_backup=true || is_backup=false
            printf '{"id":"%s","protocol":"%s","label":"%s","host":"%s","port":%s,"transport":"%s","engine":"%s","support":"%s","primary":%s,"backup":%s}' \
              "$(json_escape "$id")" "$(json_escape "$protocol")" "$(json_escape "$label")" \
              "$(json_escape "$host")" "$([ "$port" -ge 0 ] 2>/dev/null && echo "$port" || echo 0)" \
              "$(json_escape "$transport")" "$(json_escape "$engine")" "$(json_escape "$support")" \
              "$is_primary" "$is_backup"
        done < "$SUB_META"
    fi
    printf ']\n'
}

selected_json() {
    subscription_load_conf || {
        printf '%s\n' '{"ok":false,"error":"invalid subscription config"}'
        return 1
    }
    p="${SUBSCRIPTION_PRIMARY_ID:-}"
    b="${SUBSCRIPTION_BACKUP_ID:-}"
    p_present=false; b_present=false
    [ -n "$p" ] && node_exists "$p" && p_present=true || true
    [ -n "$b" ] && node_exists "$b" && b_present=true || true
    printf '{"ok":true,"primary":"%s","primary_present":%s,"backup":"%s","backup_present":%s}\n' \
      "$(json_escape "$p")" "$p_present" "$(json_escape "$b")" "$b_present"
}

set_enabled() {
    value="$1"
    bool01 "$value" || return 2
    subscription_load_conf || return 3
    old="${SUBSCRIPTION_ENABLED:-0}"
    [ "$old" = "$value" ] && return 0
    conf_set "$SUB_CONF" SUBSCRIPTION_ENABLED "$value" || return 4
    if save_storage; then
        log "subscription: manager enabled=$value"
        return 0
    fi
    conf_set "$SUB_CONF" SUBSCRIPTION_ENABLED "$old" >/dev/null 2>&1 || true
    save_storage >/dev/null 2>&1 || true
    log 'subscription: manager setting persistence failed'
    return 5
}

set_selection() {
    slot="$1"; id="$2"
    case "$slot" in
      primary) key=SUBSCRIPTION_PRIMARY_ID ;;
      backup) key=SUBSCRIPTION_BACKUP_ID ;;
      *) return 2 ;;
    esac
    subscription_load_conf || return 3
    if [ -n "$id" ]; then
        subscription_node_id_valid "$id" || return 4
        node_exists "$id" || return 5
    fi

    case "$slot" in
      primary) old="${SUBSCRIPTION_PRIMARY_ID:-}" ;;
      backup) old="${SUBSCRIPTION_BACKUP_ID:-}" ;;
    esac
    [ "$old" = "$id" ] && return 0

    conf_set "$SUB_CONF" "$key" "$id" || return 6
    if save_storage; then
        log "subscription: ${slot} node selection updated"
        return 0
    fi

    # If flash persistence fails, restore the in-memory config too. Selection
    # IDs are small metadata; the secret URI is never copied to Storage.
    conf_set "$SUB_CONF" "$key" "$old" >/dev/null 2>&1 || true
    save_storage >/dev/null 2>&1 || true
    log "subscription: ${slot} selection persistence failed"
    return 7
}

selection_reply() {
    slot="$1"; id="$2"
    set_selection "$slot" "$id"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        printf '{"ok":true,"slot":"%s","id":"%s"}\n' "$slot" "$(json_escape "$id")"
        return 0
    fi
    printf '{"ok":false,"slot":"%s","error":"selection rejected","rc":%d}\n' "$slot" "$rc"
    return "$rc"
}

OP=${1:-status}
case "$OP" in
  status)
    exec /bin/sh /etc/storage/ourfw/modules/subscription/health.sh
    ;;
  enable|disable)
    [ "$OP" = enable ] && wanted=1 || wanted=0
    set_enabled "$wanted"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        printf '{"ok":true,"enabled":%s}\n' "$([ "$wanted" = 1 ] && echo true || echo false)"
        exit 0
    fi
    printf '{"ok":false,"error":"manager setting rejected","rc":%d}\n' "$rc"
    exit "$rc"
    ;;
  nodes)
    nodes_json
    ;;
  selected)
    selected_json
    ;;
  primary-n*)
    id=${OP#primary-}
    selection_reply primary "$id"
    ;;
  backup-n*)
    id=${OP#backup-}
    selection_reply backup "$id"
    ;;
  clear-primary)
    selection_reply primary ""
    ;;
  clear-backup)
    selection_reply backup ""
    ;;
  refresh)
    /bin/sh /etc/storage/ourfw/modules/subscription/fetch.sh || exit $?
    /bin/sh /etc/storage/ourfw/modules/subscription/parse.sh || exit $?
    exec /bin/sh /etc/storage/ourfw/modules/subscription/health.sh
    ;;
  parse)
    /bin/sh /etc/storage/ourfw/modules/subscription/parse.sh || exit $?
    exec /bin/sh /etc/storage/ourfw/modules/subscription/health.sh
    ;;
  *)
    printf '%s\n' '{"ok":false,"error":"unsupported subscription operation"}'
    exit 2
    ;;
esac
