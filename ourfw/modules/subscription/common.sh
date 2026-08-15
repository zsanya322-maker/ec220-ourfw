#!/bin/sh
. /etc/storage/ourfw/runtime/ourfw-common.sh 2>/dev/null || exit 1

SUB_CONF="$OURFW/config/subscription.conf"
SUB_SECRET="$OURFW/profiles/subscription.secret"
SUB_SALT="$OURFW/profiles/subscription.salt"
SUB_ALLOW="$OURFW/rules/subscription.allow-hosts"
SUB_STATE="$STATE/subscription"
SUB_RAW="$SUB_STATE/raw.feed"
SUB_META="$SUB_STATE/nodes.meta"
SUB_SECRETS="$SUB_STATE/nodes.secret"
SUB_CANDIDATE="$SUB_STATE/candidate"

subscription_load_conf() {
    SUBSCRIPTION_ENABLED=0
    SUBSCRIPTION_REFRESH=manual
    SUBSCRIPTION_MAX_BYTES=524288
    SUBSCRIPTION_MAX_NODES=512
    SUBSCRIPTION_URI_MAX_BYTES=8192
    SUBSCRIPTION_LABEL_MAX_BYTES=160
    [ -f "$SUB_CONF" ] && load_conf "$SUB_CONF" || return 1

    bool01 "${SUBSCRIPTION_ENABLED:-0}" || return 1
    case "${SUBSCRIPTION_REFRESH:-manual}" in manual|daily) ;; *) return 1;; esac
    is_uint "${SUBSCRIPTION_MAX_BYTES:-}" || return 1
    is_uint "${SUBSCRIPTION_MAX_NODES:-}" || return 1
    is_uint "${SUBSCRIPTION_URI_MAX_BYTES:-}" || return 1
    is_uint "${SUBSCRIPTION_LABEL_MAX_BYTES:-}" || return 1
    [ "$SUBSCRIPTION_MAX_BYTES" -ge 1024 ] && [ "$SUBSCRIPTION_MAX_BYTES" -le 1048576 ] || return 1
    [ "$SUBSCRIPTION_MAX_NODES" -ge 1 ] && [ "$SUBSCRIPTION_MAX_NODES" -le 1024 ] || return 1
    [ "$SUBSCRIPTION_URI_MAX_BYTES" -ge 128 ] && [ "$SUBSCRIPTION_URI_MAX_BYTES" -le 16384 ] || return 1
    [ "$SUBSCRIPTION_LABEL_MAX_BYTES" -ge 16 ] && [ "$SUBSCRIPTION_LABEL_MAX_BYTES" -le 256 ] || return 1
}

subscription_ensure_runtime() {
    mkdir -p "$SUB_STATE" "$SUB_SECRETS" "$SUB_CANDIDATE" || return 1
    chmod 0700 "$SUB_STATE" "$SUB_SECRETS" "$SUB_CANDIDATE" 2>/dev/null || true
    [ -f "$SUB_SECRET" ] && chmod 0600 "$SUB_SECRET" 2>/dev/null || true
    [ -f "$SUB_SALT" ] && chmod 0600 "$SUB_SALT" 2>/dev/null || true
}

subscription_ensure_salt() {
    if [ -f "$SUB_SALT" ]; then
        s="$(sed -n '1p' "$SUB_SALT" 2>/dev/null | tr -d '\r\n')"
        case "$s" in *[!0-9A-Fa-f]*) s="";; esac
        [ "${#s}" -eq 64 ] 2>/dev/null && return 0
    fi

    sum=/usr/bin/sha256sum
    [ -x "$sum" ] || sum=/bin/sha256sum
    [ -x "$sum" ] || { log "subscription: sha256sum unavailable for local salt"; return 1; }

    tmp="$SUB_SALT.tmp.$$"
    mkdir -p "$(dirname "$SUB_SALT")" || return 1
    ( umask 077; dd if=/dev/urandom bs=32 count=1 2>/dev/null | "$sum" 2>/dev/null | awk '{print $1}' > "$tmp" ) || {
        rm -f "$tmp"; return 1;
    }
    s="$(sed -n '1p' "$tmp" 2>/dev/null | tr -d '\r\n')"
    case "$s" in *[!0-9A-Fa-f]*) s="";; esac
    [ "${#s}" -eq 64 ] 2>/dev/null || { rm -f "$tmp"; return 1; }
    chmod 0600 "$tmp" 2>/dev/null || true
    mv "$tmp" "$SUB_SALT" || return 1
    save_storage || log "subscription: salt created but Storage save failed"
}

subscription_source_url() {
    [ -f "$SUB_SECRET" ] || return 1
    sed 's/\r$//; /^[[:space:]]*#/d; /^[[:space:]]*$/d' "$SUB_SECRET" 2>/dev/null | sed -n '1p'
}

subscription_validate_url() {
    u="$1"
    case "$u" in
      https://*) ;;
      *) return 1;;
    esac
    # Reject shell/control whitespace, quotes and backslashes before the value is
    # ever written to curl's protected config file.
    case "$u" in
      *[[:space:]]*|*\"*|*\\*) return 1;;
    esac
    [ "${#u}" -le 4096 ] 2>/dev/null || return 1
    h="$(subscription_source_host "$u")"
    [ -n "$h" ] || return 1
    case "$h" in *[!A-Za-z0-9._:-]*) return 1;; esac
    return 0
}

subscription_source_host() {
    u="$1"
    rest=${u#https://}
    auth=${rest%%/*}
    auth=${auth%%\?*}
    auth=${auth%%\#*}
    case "$auth" in *@*) auth=${auth##*@};; esac
    case "$auth" in
      \[*\]*)
        h=${auth#\[}; h=${h%%\]*}
        ;;
      *)
        h=${auth%%:*}
        ;;
    esac
    printf '%s\n' "$h" | tr 'A-Z' 'a-z'
}

subscription_host_allowed() {
    h="$1"
    [ -f "$SUB_ALLOW" ] || return 0
    any=0
    while IFS= read -r line || [ -n "$line" ]; do
        line="$(printf '%s' "$line" | sed 's/\r$//; s/^[[:space:]]*//; s/[[:space:]]*$//')"
        case "$line" in ''|'#'*) continue;; esac
        any=1
        line="$(printf '%s' "$line" | tr 'A-Z' 'a-z')"
        [ "$line" = "$h" ] && return 0
    done < "$SUB_ALLOW"
    [ "$any" -eq 0 ] && return 0
    return 1
}

subscription_status_write() {
    kind="$1"; result="$2"; detail="$3"
    case "$kind" in fetch|parse|probe) ;; *) return 1;; esac
    case "$result" in ok|disabled|config_error|source_error|network_error|size_error|format_error|limit_error|unsupported|idle) ;; *) result=source_error;; esac
    case "$detail" in *[!A-Za-z0-9_.:=,+-]*) detail=redacted;; esac
    tmp="$SUB_STATE/$kind.status.tmp.$$"
    {
        printf 'RESULT=%s\n' "$result"
        printf 'DETAIL=%s\n' "$detail"
        date '+EPOCH=%s' 2>/dev/null || printf 'EPOCH=0\n'
    } > "$tmp" || return 1
    mv "$tmp" "$SUB_STATE/$kind.status"
}
