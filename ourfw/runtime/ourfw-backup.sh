#!/bin/sh
set -u
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
load_global || exit 1

validate_archive() {
    arc="$1"; [ -f "$arc" ] || return 1
    list="$STATE/backup-list.$$"; verbose="$STATE/backup-verbose.$$"
    rm -f "$list" "$verbose"
    tar -tjf "$arc" > "$list" 2>/dev/null || { rm -f "$list" "$verbose"; return 1; }
    tar -tvjf "$arc" > "$verbose" 2>/dev/null || { rm -f "$list" "$verbose"; return 1; }
    # No symlinks/hardlinks/devices in restore packages.
    awk 'substr($1,1,1)!="-" && substr($1,1,1)!="d" {bad=1} END{exit bad}' "$verbose" || { rm -f "$list" "$verbose"; return 1; }
    have_c=0; have_p=0; have_r=0
    while IFS= read -r member; do
        m=${member#./}; m=${m%/}
        case "/$m/" in */../*) rm -f "$list" "$verbose"; return 1;; esac
        case "$m" in
          config) have_c=1;; config/*) ;;
          profiles) have_p=1;; profiles/*) ;;
          rules) have_r=1;; rules/*) ;;
          '') ;;
          *) rm -f "$list" "$verbose"; return 1;;
        esac
    done < "$list"
    rm -f "$list" "$verbose"
    [ "$have_c" = 1 ] && [ "$have_p" = 1 ] && [ "$have_r" = 1 ]
}

case "${1:-}" in
  export)
    out="$STATE/ourfw-backup.$$.tar.bz2"
    rm -f "$out"
    ( cd "$OURFW" && tar -cf - config profiles rules 2>/dev/null ) | bzip2 -9 > "$out" || { rm -f "$out"; exit 1; }
    validate_archive "$out" || { rm -f "$out"; exit 1; }
    printf '%s\n' "$out"
    ;;
  restore)
    arc="${2:-}"; validate_archive "$arc" || { echo 'invalid OURFW backup' >&2; exit 2; }
    OURFW_CANDIDATE_BACKUP="$arc" "$OURFW/runtime/ourfw-apply.sh" web-backup-restore
    ;;
  verify)
    validate_archive "${2:-}"
    ;;
  *) echo 'usage: ourfw-backup.sh {export|restore <archive>|verify <archive>}' >&2; exit 2;;
esac
