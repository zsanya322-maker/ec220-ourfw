#!/bin/sh
# Write-only transport for the provider subscription URL.
# The URL is never returned by an API/status call and is persisted mode 0600.
set -u
. /etc/storage/ourfw/modules/subscription/common.sh 2>/dev/null || exit 1

UP="$SUB_STATE/source-upload"
EXPECTED="$UP/expected.bytes"
DATA="$UP/data.b64"
MAX_BYTES=4096

json_escape_local() { json_escape "$1"; }
json_fail() { printf '{"ok":false,"error":"%s"}\n' "$(json_escape_local "$1")"; return 1; }
json_ok() { printf '%s\n' '{"ok":true,"source_set":true}'; }

ensure_upload_dir() {
    subscription_ensure_runtime || return 1
    rm -rf "$UP"
    mkdir -p "$UP" || return 1
    chmod 0700 "$UP" 2>/dev/null || true
}

b64url_decode() {
    src="$1"; dst="$2"
    n="$(wc -c < "$src" 2>/dev/null | tr -d '[:space:]')"
    is_uint "$n" || return 1
    rem=$((n % 4)); pad=
    case "$rem" in 0) ;; 2) pad='==';; 3) pad='=';; *) return 1;; esac
    { tr '_-' '/+' < "$src"; printf '%s' "$pad"; } | base64 -d > "$dst" 2>/dev/null
}

source_line() {
    sed 's/\r$//; /^[[:space:]]*#/d; /^[[:space:]]*$/d' "$1" 2>/dev/null
}

validate_decoded() {
    f="$1"
    bytes="$(wc -c < "$f" 2>/dev/null | tr -d '[:space:]')"
    is_uint "$bytes" || return 1
    [ "$bytes" -gt 0 ] && [ "$bytes" -le "$MAX_BYTES" ] || return 1
    [ "$(tr -d '\000' < "$f" | wc -c | tr -d '[:space:]')" = "$bytes" ] || return 1
    lines="$(source_line "$f" | wc -l | tr -d '[:space:]')"
    [ "$lines" = 1 ] || return 1
    url="$(source_line "$f" | sed -n '1p')"
    subscription_validate_url "$url" || return 1
    host="$(subscription_source_host "$url")"
    subscription_host_allowed "$host" || return 1
    return 0
}

op_begin() {
    n="${1:-}"
    is_uint "$n" || { json_fail 'byte length required'; return; }
    [ "$n" -gt 0 ] && [ "$n" -le "$MAX_BYTES" ] || { json_fail 'subscription URL too large'; return; }
    ensure_upload_dir || { json_fail 'cannot create protected staging'; return; }
    printf '%s\n' "$n" > "$EXPECTED" || { json_fail 'cannot stage length'; return; }
    : > "$DATA"
    chmod 0600 "$EXPECTED" "$DATA" 2>/dev/null || true
    printf '%s\n' '{"ok":true,"staged":true}'
}

op_chunk() {
    chunk="${1:-}"
    case "$chunk" in ''|*[!A-Za-z0-9_-]*) json_fail 'invalid base64url chunk'; return;; esac
    [ "${#chunk}" -le 1024 ] 2>/dev/null || { json_fail 'chunk too large'; return; }
    [ -f "$EXPECTED" ] && [ -f "$DATA" ] || { json_fail 'upload not started'; return; }
    cur="$(wc -c < "$DATA" | tr -d '[:space:]')"
    is_uint "$cur" || { json_fail 'invalid staging state'; return; }
    maxb64=$(( (MAX_BYTES * 4 / 3) + 16 ))
    [ $((cur + ${#chunk})) -le "$maxb64" ] || { rm -rf "$UP"; json_fail 'payload too large'; return; }
    printf '%s' "$chunk" >> "$DATA" || { json_fail 'staging write failed'; return; }
    printf '%s\n' '{"ok":true,"chunk":true}'
}

op_abort() {
    rm -rf "$UP"
    printf '%s\n' '{"ok":true,"aborted":true}'
}

op_commit() {
    [ -f "$EXPECTED" ] && [ -f "$DATA" ] || { json_fail 'upload not started'; return; }
    expected="$(cat "$EXPECTED" 2>/dev/null || true)"
    is_uint "$expected" || { rm -rf "$UP"; json_fail 'invalid staging state'; return; }
    decoded="$UP/decoded.url"
    b64url_decode "$DATA" "$decoded" || { rm -rf "$UP"; json_fail 'base64 decode failed'; return; }
    actual="$(wc -c < "$decoded" 2>/dev/null | tr -d '[:space:]')"
    [ "$actual" = "$expected" ] || { rm -rf "$UP"; json_fail 'byte length mismatch'; return; }
    validate_decoded "$decoded" || { rm -rf "$UP"; json_fail 'subscription URL rejected'; return; }
    url="$(source_line "$decoded" | sed -n '1p')"

    old="$UP/old.secret"
    had_old=0
    if [ -f "$SUB_SECRET" ]; then
        cp "$SUB_SECRET" "$old" || { rm -rf "$UP"; json_fail 'cannot stage previous source'; return; }
        chmod 0600 "$old" 2>/dev/null || true
        had_old=1
    fi

    tmp="$SUB_SECRET.tmp.$$"
    mkdir -p "$(dirname "$SUB_SECRET")" || { rm -rf "$UP"; json_fail 'cannot create profile directory'; return; }
    ( umask 077; printf '%s\n' "$url" > "$tmp" ) || { rm -f "$tmp"; rm -rf "$UP"; json_fail 'cannot write protected source'; return; }
    chmod 0600 "$tmp" 2>/dev/null || true
    mv "$tmp" "$SUB_SECRET" || { rm -f "$tmp"; rm -rf "$UP"; json_fail 'cannot install protected source'; return; }

    if ! save_storage; then
        if [ "$had_old" -eq 1 ]; then cp "$old" "$SUB_SECRET" 2>/dev/null || true; chmod 0600 "$SUB_SECRET" 2>/dev/null || true; else rm -f "$SUB_SECRET"; fi
        save_storage >/dev/null 2>&1 || true
        rm -rf "$UP"
        json_fail 'Storage save failed; previous source restored'
        return
    fi

    chmod 0600 "$SUB_SECRET" 2>/dev/null || true
    rm -rf "$UP"
    log 'subscription: protected source URL updated'
    json_ok
}

case "${1:-}" in
  begin) op_begin "${2:-}" ;;
  chunk) op_chunk "${2:-}" ;;
  commit) op_commit ;;
  abort) op_abort ;;
  *) json_fail 'unsupported secret transfer operation' ;;
esac
