#!/bin/sh
# Mutable API dispatcher. The immutable httpd bridge executes only this file
# and passes sanitized argv; all actual operations remain replaceable in OURFW.
. /etc/storage/ourfw/runtime/ourfw-common.sh 2>/dev/null || exit 1
OUT=/tmp/ourfw-api.json
ACTION=${1:-status}
P1=${2:-}
P2=${3:-}

# Rescue switch is authoritative for mutable operations. Status remains readable
# so the fallback page can explain why OURFW is inactive.
if [ -e /etc/storage/ourfw.disabled ] && [ "$ACTION" != status ]; then
    printf '%s\n' '{"ok":false,"error":"OURFW disabled by rescue flag"}' > /tmp/ourfw-api.json
    exit 4
fi

write_json() { printf '%s\n' "$1" > "$OUT"; }
run_ctl() {
    op="$1"
    /etc/storage/ourfw/runtime/ourfwctl.sh "$op" >/tmp/ourfw-api-action.log 2>&1
    rc=$?
    write_json "{\"ok\":$([ $rc -eq 0 ] && echo true || echo false),\"action\":\"$op\",\"rc\":$rc}"
    return $rc
}
subscription_secret_transfer() {
    op="$1"; arg="${2:-}"
    hook="$OURFW/modules/subscription/secret-transfer.sh"
    [ -x "$hook" ] || { write_json '{"ok":false,"error":"subscription secret transport unavailable"}'; return 3; }
    if [ -n "$arg" ]; then "$hook" "$op" "$arg" > "$OUT" 2>/tmp/ourfw-api-action.log; else "$hook" "$op" > "$OUT" 2>/tmp/ourfw-api-action.log; fi
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
  file-get)
    safe_id "$P1" || { write_json '{"ok":false,"error":"invalid target"}'; exit 2; }
    [ "$P1" != subscription-secret ] || { write_json '{"ok":false,"error":"subscription source is write-only"}'; exit 3; }
    "$OURFW/runtime/ourfw-transfer.sh" get "$P1" > "$OUT" 2>/tmp/ourfw-api-action.log
    ;;
  file-begin)
    safe_id "$P1" || { write_json '{"ok":false,"error":"invalid target"}'; exit 2; }
    if [ "$P1" = subscription-secret ]; then subscription_secret_transfer begin "$P2"; exit $?; fi
    "$OURFW/runtime/ourfw-transfer.sh" begin "$P1" "$P2" > "$OUT" 2>/tmp/ourfw-api-action.log
    ;;
  file-chunk)
    safe_id "$P1" || { write_json '{"ok":false,"error":"invalid target"}'; exit 2; }
    if [ "$P1" = subscription-secret ]; then subscription_secret_transfer chunk "$P2"; exit $?; fi
    "$OURFW/runtime/ourfw-transfer.sh" chunk "$P1" "$P2" > "$OUT" 2>/tmp/ourfw-api-action.log
    ;;
  file-commit)
    safe_id "$P1" || { write_json '{"ok":false,"error":"invalid target"}'; exit 2; }
    if [ "$P1" = subscription-secret ]; then subscription_secret_transfer commit; exit $?; fi
    "$OURFW/runtime/ourfw-transfer.sh" commit "$P1" > "$OUT" 2>/tmp/ourfw-api-action.log
    ;;
  file-stage)
    safe_id "$P1" || { write_json '{"ok":false,"error":"invalid target"}'; exit 2; }
    "$OURFW/runtime/ourfw-transfer.sh" stage "$P1" > "$OUT" 2>/tmp/ourfw-api-action.log
    ;;
  section-commit)
    safe_id "$P1" || { write_json '{"ok":false,"error":"invalid section"}'; exit 2; }
    "$OURFW/runtime/ourfw-transfer.sh" section-commit "$P1" > "$OUT" 2>/tmp/ourfw-api-action.log
    ;;
  section-abort)
    safe_id "$P1" || { write_json '{"ok":false,"error":"invalid section"}'; exit 2; }
    "$OURFW/runtime/ourfw-transfer.sh" section-abort "$P1" > "$OUT" 2>/tmp/ourfw-api-action.log
    ;;
  file-abort)
    safe_id "$P1" || { write_json '{"ok":false,"error":"invalid target"}'; exit 2; }
    if [ "$P1" = subscription-secret ]; then subscription_secret_transfer abort; exit $?; fi
    "$OURFW/runtime/ourfw-transfer.sh" abort "$P1" > "$OUT" 2>/tmp/ourfw-api-action.log
    ;;
  backup-export)
    "$OURFW/runtime/ourfw-transfer.sh" backup-export > "$OUT" 2>/tmp/ourfw-api-action.log
    ;;
  diagnostics-export)
    "$OURFW/runtime/ourfw-transfer.sh" diagnostics-export > "$OUT" 2>/tmp/ourfw-api-action.log
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
