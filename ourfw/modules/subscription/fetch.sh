#!/bin/sh
. /etc/storage/ourfw/modules/subscription/common.sh 2>/dev/null || exit 1
subscription_load_conf || { subscription_ensure_runtime >/dev/null 2>&1 || true; subscription_status_write fetch config_error invalid_config >/dev/null 2>&1 || true; exit 2; }
subscription_ensure_runtime || exit 3

[ "${SUBSCRIPTION_ENABLED:-0}" = 1 ] || {
    subscription_status_write fetch disabled manager_off
    exit 4
}
need curl || { subscription_status_write fetch source_error curl_missing; exit 5; }

url="$(subscription_source_url 2>/dev/null || true)"
subscription_validate_url "$url" || {
    subscription_status_write fetch source_error invalid_url
    log "subscription: provider source rejected"
    exit 6
}
host="$(subscription_source_host "$url")"
subscription_host_allowed "$host" || {
    subscription_status_write fetch source_error host_denied
    log "subscription: provider host rejected by allow list"
    exit 7
}

cfg="$SUB_STATE/curl.conf.$$"
out="$SUB_STATE/raw.feed.tmp.$$"
rm -f "$cfg" "$out"
umask 077
# Keep the secret URL out of argv. Curl reads it from a protected config file.
{
    printf 'url = "%s"\n' "$url"
    printf 'output = "%s"\n' "$out"
    printf 'connect-timeout = 8\n'
    printf 'max-time = 30\n'
    printf 'fail\n'
    printf 'silent\n'
    printf 'show-error\n'
    printf 'location\n'
    printf 'proto = "=https"\n'
    printf 'proto-redir = "=https"\n'
    printf 'max-filesize = %s\n' "$SUBSCRIPTION_MAX_BYTES"
} > "$cfg" || exit 8
chmod 0600 "$cfg"

if ! curl --config "$cfg" >/dev/null 2>&1; then
    rm -f "$cfg" "$out"
    subscription_status_write fetch network_error curl_failed
    log "subscription: HTTPS refresh failed"
    exit 9
fi
rm -f "$cfg"

[ -f "$out" ] || { subscription_status_write fetch network_error no_output; exit 10; }
bytes="$(wc -c < "$out" 2>/dev/null | tr -d '[:space:]')"
is_uint "$bytes" || bytes=0
if [ "$bytes" -le 0 ] || [ "$bytes" -gt "$SUBSCRIPTION_MAX_BYTES" ]; then
    rm -f "$out"
    subscription_status_write fetch size_error rejected
    log "subscription: response size rejected"
    exit 11
fi
chmod 0600 "$out" 2>/dev/null || true
mv "$out" "$SUB_RAW" || exit 12
subscription_status_write fetch ok "bytes=$bytes"
log "subscription: feed refreshed (${bytes} bytes)"
