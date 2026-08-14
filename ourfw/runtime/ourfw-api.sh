#!/bin/sh
# Mutable API dispatcher. The immutable httpd bridge executes only this file
# and passes sanitized argv; all actual operations remain replaceable in OURFW.
. /etc/storage/ourfw/runtime/ourfw-common.sh 2>/dev/null || exit 1
OUT=/tmp/ourfw-api.json
ACTION=${1:-status}
P1=${2:-}
P2=${3:-}

write_json() { printf '%s\n' "$1" > "$OUT"; }
run_ctl() {
    op="$1"
    /etc/storage/ourfw/runtime/ourfwctl.sh "$op" >/tmp/ourfw-api-action.log 2>&1
    rc=$?
    write_json "{\"ok\":$([ $rc -eq 0 ] && echo true || echo false),\"action\":\"$op\",\"rc\":$rc}"
    return $rc
}

case "$ACTION" in
  status)
    /etc/storage/ourfw/runtime/ourfwctl.sh status-json > "$OUT" 2>/dev/null || write_json '{"ok":false,"error":"status unavailable"}'
    ;;
  apply|confirm|rollback|baseline)
    run_ctl "$ACTION"
    ;;
  diagnostics)
    f="$(/etc/storage/ourfw/modules/diagnostics/snapshot.sh 2>/dev/null | tail -n1)"
    [ -n "$f" ] && write_json "{\"ok\":true,\"file\":\"$(json_escape "$f")\"}" || write_json '{"ok":false,"error":"diagnostics failed"}'
    ;;
  module)
    # p1=module id, p2=operation. Mutable extension point without arbitrary shell.
    safe_id "$P1" && safe_id "$P2" || { write_json '{"ok":false,"error":"invalid module request"}'; exit 2; }
    hook="$OURFW/modules/$P1/api.sh"
    [ -x "$hook" ] || { write_json '{"ok":false,"error":"module api unavailable"}'; exit 3; }
    "$hook" "$P2" > "$OUT" 2>/tmp/ourfw-api-action.log || {
        rc=$?; write_json "{\"ok\":false,\"module\":\"$P1\",\"op\":\"$P2\",\"rc\":$rc}"; exit $rc;
    }
    ;;
  *)
    write_json '{"ok":false,"error":"unsupported action"}'; exit 2 ;;
esac
