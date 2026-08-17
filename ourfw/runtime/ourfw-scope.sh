#!/bin/sh
# Scoped runtime apply helper. Keeps unrelated services alive when one WebUI
# section changes.
. /etc/storage/ourfw/runtime/ourfw-common.sh 2>/dev/null || exit 1

scope_for_tag() {
    _ourfw_scope_tag="${1:-default}"
    case "$_ourfw_scope_tag" in
      web-section-routing) printf '%s\n' routing ;;
      web-smart-routing) printf '%s\n' routing-mode ;;
      web-section-vpn|web-vpn) printf '%s\n' vpn ;;
      web-section-dns|web-dns) printf '%s\n' dns ;;
      web-section-nfqws|web-nfqws) printf '%s\n' nfqws ;;
      web-section-adblock|web-adblock) printf '%s\n' adblock ;;
      web-section-watchdog|web-watchdog) printf '%s\n' watchdog ;;
      web-section-zram|web-zram) printf '%s\n' zram ;;
      *) printf '%s\n' all ;;
    esac
}

scope_modules() {
    case "${1:-all}" in
      all)          printf '%s\n' 'zram vpn smart-routing adblock dns nfqws watchdog diagnostics' ;;
      vpn)          printf '%s\n' 'vpn smart-routing dns' ;;
      routing)      printf '%s\n' 'smart-routing dns' ;;
      routing-mode) printf '%s\n' 'smart-routing' ;;
      dns)          printf '%s\n' 'dns' ;;
      nfqws)        printf '%s\n' 'nfqws' ;;
      adblock)      printf '%s\n' 'adblock dns' ;;
      watchdog)     printf '%s\n' 'watchdog' ;;
      zram)         printf '%s\n' 'zram' ;;
      *) return 1 ;;
    esac
}

scope_apply() {
    _ourfw_scope_name="${1:-all}"
    _ourfw_scope_mods="$(scope_modules "$_ourfw_scope_name")" || return 1

    case "$_ourfw_scope_name" in
      all|vpn) rm -f "$STATE/vpn-override-type" 2>/dev/null || true ;;
    esac

    for _ourfw_scope_mod in $_ourfw_scope_mods; do
        _ourfw_scope_hook="$OURFW/modules/$_ourfw_scope_mod/apply.sh"
        [ -x "$_ourfw_scope_hook" ] || continue
        log "apply[$_ourfw_scope_name] module: $_ourfw_scope_mod"
        if ! "$_ourfw_scope_hook"; then
            log "apply[$_ourfw_scope_name] failed: $_ourfw_scope_mod"
            return 1
        fi
    done
    return 0
}
