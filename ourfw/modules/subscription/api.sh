#!/bin/sh
. /etc/storage/ourfw/modules/subscription/common.sh 2>/dev/null || exit 1
subscription_ensure_runtime >/dev/null 2>&1 || exit 1

nodes_json() {
    printf '['
    first=1
    if [ -f "$SUB_META" ]; then
        while IFS='|' read -r id protocol label host port transport engine support || [ -n "$id" ]; do
            safe_id "$id" || continue
            [ "$first" -eq 1 ] || printf ','
            first=0
            printf '{"id":"%s","protocol":"%s","label":"%s","host":"%s","port":%s,"transport":"%s","engine":"%s","support":"%s"}' \
              "$(json_escape "$id")" "$(json_escape "$protocol")" "$(json_escape "$label")" \
              "$(json_escape "$host")" "$([ "$port" -ge 0 ] 2>/dev/null && echo "$port" || echo 0)" \
              "$(json_escape "$transport")" "$(json_escape "$engine")" "$(json_escape "$support")"
        done < "$SUB_META"
    fi
    printf ']\n'
}

case "${1:-status}" in
  status)
    exec /bin/sh /etc/storage/ourfw/modules/subscription/health.sh
    ;;
  nodes)
    nodes_json
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
