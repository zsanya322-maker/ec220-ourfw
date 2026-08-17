#!/bin/sh
. /etc/storage/ourfw/modules/subscription/common.sh 2>/dev/null || exit 1
subscription_load_conf || { subscription_ensure_runtime >/dev/null 2>&1 || true; subscription_status_write parse config_error invalid_config >/dev/null 2>&1 || true; exit 2; }
subscription_ensure_runtime || exit 3
subscription_ensure_salt || { subscription_status_write parse source_error salt_missing; exit 4; }

src=${1:-$SUB_RAW}
[ -f "$src" ] || { subscription_status_write parse source_error feed_missing; exit 5; }
bytes="$(wc -c < "$src" 2>/dev/null | tr -d '[:space:]')"
is_uint "$bytes" || bytes=0
[ "$bytes" -gt 0 ] && [ "$bytes" -le "$SUBSCRIPTION_MAX_BYTES" ] || {
    subscription_status_write parse size_error feed_rejected
    exit 6
}

sum=/usr/bin/sha256sum
[ -x "$sum" ] || sum=/bin/sha256sum
[ -x "$sum" ] || { subscription_status_write parse source_error sha256_missing; exit 7; }
need base64 || { subscription_status_write parse source_error base64_missing; exit 8; }

stage="$SUB_STATE/parse.$$"
rm -rf "$stage"
umask 077
mkdir -p "$stage/nodes.secret" || exit 9
meta="$stage/nodes.meta"
: > "$meta"

# Phase 1 accepts either newline share URIs or one outer base64 wrapper.
parse_src="$src"
if ! grep -Eq '^[[:space:]]*[A-Za-z][A-Za-z0-9+.-]*://' "$src" 2>/dev/null; then
    compact="$stage/outer.b64"
    decoded="$stage/decoded.feed"
    tr -d '\r\n\t ' < "$src" > "$compact"
    if [ ! -s "$compact" ] || ! base64 -d "$compact" > "$decoded" 2>/dev/null; then
        rm -rf "$stage"
        subscription_status_write parse format_error invalid_outer_base64
        exit 10
    fi
    dbytes="$(wc -c < "$decoded" 2>/dev/null | tr -d '[:space:]')"
    is_uint "$dbytes" || dbytes=0
    if [ "$dbytes" -le 0 ] || [ "$dbytes" -gt "$SUBSCRIPTION_MAX_BYTES" ]; then
        rm -rf "$stage"
        subscription_status_write parse size_error decoded_rejected
        exit 11
    fi
    parse_src="$decoded"
fi

salt="$(sed -n '1p' "$SUB_SALT" 2>/dev/null | tr -d '\r\n')"
count=0
skipped=0
limit_hit=0

while IFS= read -r uri || [ -n "$uri" ]; do
    uri="$(printf '%s' "$uri" | sed 's/\r$//; s/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$uri" ] || continue

    ubytes="$(printf '%s' "$uri" | wc -c 2>/dev/null | tr -d '[:space:]')"
    is_uint "$ubytes" || ubytes=0
    if [ "$ubytes" -le 0 ] || [ "$ubytes" -gt "$SUBSCRIPTION_URI_MAX_BYTES" ]; then
        skipped=$((skipped+1))
        continue
    fi

    scheme="$(printf '%s' "$uri" | sed -n 's|^\([A-Za-z][A-Za-z0-9+.-]*\)://.*$|\1|p' | tr 'A-Z' 'a-z')"
    [ -n "$scheme" ] || { skipped=$((skipped+1)); continue; }

    count=$((count+1))
    if [ "$count" -gt "$SUBSCRIPTION_MAX_NODES" ]; then
        limit_hit=1
        break
    fi

    authority="$(printf '%s' "$uri" | sed 's|^[A-Za-z][A-Za-z0-9+.-]*://||; s|[/#?].*$||')"
    endpoint=${authority##*@}
    host=""
    port=0
    case "$endpoint" in
      \[*\]*)
        host=${endpoint#\[}
        host=${host%%\]*}
        tail=${endpoint#*\]}
        case "$tail" in :*) port=${tail#:};; esac
        ;;
      *)
        colons="$(printf '%s' "$endpoint" | tr -cd ':' | wc -c | tr -d '[:space:]')"
        if [ "$colons" = 1 ]; then
            host=${endpoint%:*}
            port=${endpoint##*:}
        else
            host=$endpoint
        fi
        ;;
    esac
    host="$(printf '%s' "$host" | tr 'A-Z' 'a-z' | sed 's/[^a-z0-9._:-]/_/g' | cut -c1-160)"
    [ -n "$host" ] || host=unknown
    is_uint "$port" || port=0
    [ "$port" -le 65535 ] 2>/dev/null || port=0

    protocol=unsupported
    transport=unknown
    engine=none
    support=unsupported
    case "$scheme" in
      hysteria2|hy2)
        protocol=hysteria2; transport=udp; engine=hysteria; support=experimental
        ;;
      vless)
        protocol=vless; transport=unknown; engine=none; support=unsupported
        ;;
      wireguard)
        protocol=wireguard; transport=udp; engine=native; support=unsupported
        ;;
    esac

    if [ "$port" -gt 0 ]; then label="$protocol-$host:$port"; else label="$protocol-$host"; fi
    label="$(printf '%s' "$label" | cut -c1-"$SUBSCRIPTION_LABEL_MAX_BYTES")"

    identity="$protocol|$host|$port"
    digest="$(printf '%s\n' "$salt|$identity" | "$sum" 2>/dev/null | awk '{print substr($1,1,16)}')"
    case "$digest" in ''|*[!0-9A-Fa-f]*) digest="$(printf '%08x' "$count" 2>/dev/null || printf '%s' "$count")";; esac
    base_id="n$digest"
    id="$base_id"
    duplicate=2
    while [ -e "$stage/nodes.secret/$id.uri" ]; do
        id="$base_id-$duplicate"
        duplicate=$((duplicate+1))
    done

    ( umask 077; printf '%s\n' "$uri" > "$stage/nodes.secret/$id.uri" ) || { rm -rf "$stage"; exit 12; }
    chmod 0600 "$stage/nodes.secret/$id.uri" 2>/dev/null || true
    printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$id" "$protocol" "$label" "$host" "$port" "$transport" "$engine" "$support" >> "$meta" || {
        rm -rf "$stage"; exit 13;
    }
done < "$parse_src"

if [ "$limit_hit" -eq 1 ]; then
    rm -rf "$stage"
    subscription_status_write parse limit_error too_many_nodes
    log "subscription: feed rejected by node limit"
    exit 14
fi
if [ "$count" -eq 0 ]; then
    rm -rf "$stage"
    subscription_status_write parse format_error no_share_uris
    exit 15
fi

# Swap only after the entire feed parsed successfully. Failed refresh/parse keeps
# the previous last-known-good node table and session secrets intact.
old_meta="$SUB_STATE/nodes.meta.old.$$"
old_secrets="$SUB_STATE/nodes.secret.old.$$"
rm -f "$old_meta"; rm -rf "$old_secrets"
[ -f "$SUB_META" ] && mv "$SUB_META" "$old_meta"
[ -d "$SUB_SECRETS" ] && mv "$SUB_SECRETS" "$old_secrets"
if ! mv "$stage/nodes.secret" "$SUB_SECRETS" || ! mv "$meta" "$SUB_META"; then
    rm -rf "$SUB_SECRETS"; rm -f "$SUB_META"
    [ -d "$old_secrets" ] && mv "$old_secrets" "$SUB_SECRETS"
    [ -f "$old_meta" ] && mv "$old_meta" "$SUB_META"
    rm -rf "$stage"
    subscription_status_write parse source_error atomic_swap_failed
    exit 16
fi
chmod 0700 "$SUB_SECRETS" 2>/dev/null || true
chmod 0600 "$SUB_META" 2>/dev/null || true
rm -rf "$old_secrets"; rm -f "$old_meta"; rm -rf "$stage"
subscription_status_write parse ok "nodes=$count,skipped=$skipped"
log "subscription: parsed ${count} node records (${skipped} skipped)"
