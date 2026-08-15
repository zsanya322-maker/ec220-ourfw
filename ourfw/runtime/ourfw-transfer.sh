#!/bin/sh
# Authenticated WebUI file transfer helper.  The immutable C bridge passes short safe tokens plus bounded <=1024-char
# base64url chunks; larger/binary payloads are chunked and are
# decoded/validated here in mutable OURFW.
set -u
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
load_global || exit 1
XFER="$STATE/transfer"
EDIT="$STATE/webedit"
mkdir -p "$XFER" "$EDIT" 2>/dev/null

TARGET= REL= KIND= MAX= KEYS=
target_info() {
    TARGET="$1"; REL=; KIND=; MAX=; KEYS=
    case "$TARGET" in
      vpn-config)
        REL=config/vpn.conf; KIND=kv; MAX=4096; KEYS='VPN_ENABLED VPN_TYPE VPN_INTERFACE VPN_PROFILE VPN_USE_PEER_DNS' ;;
      vpn-profile)
        REL=profiles/vpn.conf; KIND=vpn; MAX=16384 ;;
      routing-config)
        REL=config/routing.conf; KIND=kv; MAX=4096; KEYS='ROUTING_MODE VPN_INTERFACE ROUTE_TABLE FWMARK FWMASK RULE_PREF KILLSWITCH IPV6_POLICY VPN_IPSET DIRECT_IPSET' ;;
      vpn-domains)
        REL=rules/vpn-domains.list; KIND=domains; MAX=16384 ;;
      direct-domains)
        REL=rules/direct-domains.list; KIND=domains; MAX=16384 ;;
      vpn-ips)
        REL=rules/vpn-ips.list; KIND=ipv4nets; MAX=16384 ;;
      direct-ips)
        REL=rules/direct-ips.list; KIND=ipv4nets; MAX=16384 ;;
      nfqws-config)
        REL=config/nfqws.conf; KIND=kv; MAX=4096; KEYS='NFQWS_ENABLED NFQWS_WAN_IF NFQWS_LOG NFQWS_STRATEGY' ;;
      nfqws-strategy)
        REL=profiles/nfqws.strategy; KIND=text; MAX=24576 ;;
      nfqws-user)
        REL=rules/nfqws-user.list; KIND=textlist; MAX=24576 ;;
      nfqws-exclude)
        REL=rules/nfqws-exclude.list; KIND=textlist; MAX=24576 ;;
      nfqws-auto)
        REL=rules/nfqws-auto.list; KIND=textlist; MAX=24576 ;;
      dns-config)
        REL=config/dns.conf; KIND=kv; MAX=4096; KEYS='DNS_ENABLED DNS_SERVERS_FILE VPN_DOMAINS_FILE DIRECT_DOMAINS_FILE' ;;
      dns-servers)
        REL=rules/dns-servers.list; KIND=dns; MAX=8192 ;;
      watchdog-config)
        REL=config/watchdog.conf; KIND=kv; MAX=4096; KEYS='WATCHDOG_ENABLED WATCHDOG_INTERVAL WATCHDOG_FAILS WATCHDOG_SCOPE PING_TARGET1 PING_TARGET2 WATCHDOG_REBOOT WATCHDOG_VPN_TARGET WATCHDOG_VPN_HANDSHAKE_MAX_AGE' ;;
      component-package)
        KIND=component; MAX=131072 ;;
      backup-import)
        KIND=backup; MAX=196608 ;;
      *) return 1 ;;
    esac
}

stage_dir() { printf '%s/%s\n' "$XFER" "$TARGET"; }
section_targets() {
    case "$1" in
      routing) printf '%s\n' 'routing-config vpn-domains direct-domains vpn-ips direct-ips' ;;
      vpn) printf '%s\n' 'vpn-config vpn-profile' ;;
      nfqws) printf '%s\n' 'nfqws-config nfqws-strategy nfqws-user nfqws-exclude nfqws-auto' ;;
      dns) printf '%s\n' 'dns-config dns-servers' ;;
      watchdog) printf '%s\n' 'watchdog-config' ;;
      *) return 1 ;;
    esac
}
json_fail() { printf '{"ok":false,"error":"%s"}\n' "$(json_escape "$1")"; return 1; }
json_ok() { printf '{"ok":true%s}\n' "${1:-}"; }

b64url_encode() {
    # base64url without padding: alphabet is accepted by immutable bridge.
    base64 "$1" | tr -d '\r\n=' | tr '/+' '_-'
}

b64url_decode() {
    src="$1"; dst="$2"
    n=$(wc -c < "$src" 2>/dev/null | tr -d ' '); is_uint "$n" || return 1
    rem=$((n % 4)); pad=
    case "$rem" in 0) ;; 2) pad='==';; 3) pad='=';; *) return 1;; esac
    { tr '_-' '/+' < "$src"; printf '%s' "$pad"; } | base64 -d > "$dst" 2>/dev/null
}

validate_no_nul() {
    # BusyBox tools are text-oriented.  Reject decoded NUL by comparing byte
    # count before/after stripping it.
    f="$1"; a=$(wc -c < "$f" | tr -d ' '); b=$(tr -d '\000' < "$f" | wc -c | tr -d ' ')
    [ "$a" = "$b" ]
}

validate_kv() {
    f="$1"; allowed=" $KEYS "
    ( load_conf "$f" ) >/dev/null 2>&1 || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        line=$(printf '%s' "$line" | tr -d '\r')
        line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        case "$line" in ''|'#'*) continue;; esac
        key=${line%%=*}
        case "$allowed" in *" $key "*) ;; *) return 1;; esac
    done < "$f"
}

validate_domains() {
    f="$1"
    strip_list "$f" | while IFS= read -r d; do
        case "$d" in *[!A-Za-z0-9._-]*|.*|*.) exit 1;; esac
    done
}

validate_ipv4nets() {
    f="$1"
    strip_list "$f" | awk '
      function bad(){exit 1}
      {
        x=$0; p=32
        if(index(x,"/")>0){split(x,z,"/"); if(length(z)!=2) bad(); x=z[1]; p=z[2]; if(p !~ /^[0-9]+$/ || p<0 || p>32) bad()}
        n=split(x,a,"."); if(n!=4) bad()
        for(i=1;i<=4;i++) if(a[i] !~ /^[0-9]+$/ || a[i]<0 || a[i]>255) bad()
      }
    '
}

validate_dns() {
    f="$1"
    strip_list "$f" | while IFS= read -r s; do
        case "$s" in *[!0-9A-Fa-f:.]*) exit 1;; esac
    done
}

validate_vpn() {
    f="$1"; validate_no_nul "$f" || return 1
    grep -Eq '^[[:space:]]*\[Interface\][[:space:]]*$' "$f" || return 1
    grep -Eq '^[[:space:]]*\[Peer\][[:space:]]*$' "$f" || return 1
    for k in Address PrivateKey PublicKey Endpoint AllowedIPs; do
        grep -Eq "^[[:space:]]*${k}[[:space:]]*=" "$f" || return 1
    done
    # CR/LF/text is fine; shell metacharacters are never evaluated.  Keep a sane size.
    return 0
}

validate_textlist() {
    validate_no_nul "$1" || return 1
    # Lists are data files consumed by zapret.  Forbid control characters other
    # than CR/LF/TAB; printable UTF-8 bytes are otherwise left to zapret.
    LC_ALL=C grep -q '[[:cntrl:]]' "$1" 2>/dev/null && {
        # Remove accepted whitespace and check whether controls remain.
        tr -d '\r\n\t' < "$1" | LC_ALL=C grep -q '[[:cntrl:]]' && return 1 || true
    }
    return 0
}

validate_candidate() {
    f="$1"; bytes=$(wc -c < "$f" | tr -d ' '); is_uint "$bytes" || return 1
    [ "$bytes" -le "$MAX" ] || return 1
    case "$KIND" in
      kv) validate_kv "$f" ;;
      domains) validate_no_nul "$f" && validate_domains "$f" ;;
      ipv4nets) validate_no_nul "$f" && validate_ipv4nets "$f" ;;
      dns) validate_no_nul "$f" && validate_dns "$f" ;;
      vpn) validate_vpn "$f" ;;
      text|textlist) validate_textlist "$f" ;;
      component|backup) return 0 ;;
      *) return 1 ;;
    esac
}

op_get() {
    target_info "$1" || { json_fail 'unknown target'; return; }
    [ -n "$REL" ] || { json_fail 'target is not readable text'; return; }
    f="$OURFW/$REL"
    if [ ! -f "$f" ] && [ "$TARGET" = vpn-profile ] && [ -f "$OURFW/profiles/vpn.conf.example" ]; then f="$OURFW/profiles/vpn.conf.example"; fi
    [ -f "$f" ] || f=/dev/null
    bytes=$(wc -c < "$f" | tr -d ' '); sha=$(sha256sum "$f" | awk '{print $1}')
    printf '{"ok":true,"target":"%s","bytes":%s,"sha256":"%s","data":"' "$TARGET" "$bytes" "$sha"
    b64url_encode "$f"
    printf '"}\n'
}

op_begin() {
    target_info "$1" || { json_fail 'unknown target'; return; }
    expected="$2"; [ ${#expected} -eq 64 ] 2>/dev/null || { json_fail 'sha256 required'; return; }
    case "$expected" in *[!0-9A-Fa-f]*) json_fail 'invalid sha256'; return;; esac
    d=$(stage_dir); rm -rf "$d"; mkdir -p "$d" || { json_fail 'cannot create staging'; return; }
    printf '%s\n' "$expected" > "$d/expected.sha256"; : > "$d/data.b64"
    json_ok ',"staged":true'
}

op_chunk() {
    target_info "$1" || { json_fail 'unknown target'; return; }
    chunk="$2"; case "$chunk" in ''|*[!A-Za-z0-9_-]*) json_fail 'invalid base64url chunk'; return;; esac
    [ ${#chunk} -le 1024 ] 2>/dev/null || { json_fail 'chunk too large'; return; }
    d=$(stage_dir); [ -f "$d/expected.sha256" ] || { json_fail 'upload not started'; return; }
    cur=$(wc -c < "$d/data.b64" | tr -d ' '); maxb64=$(( (MAX * 4 / 3) + 16 ))
    [ $((cur + ${#chunk})) -le "$maxb64" ] || { rm -rf "$d"; json_fail 'payload too large'; return; }
    printf '%s' "$chunk" >> "$d/data.b64" || { json_fail 'staging write failed'; return; }
    json_ok ',"chunk":true'
}

op_abort() {
    target_info "$1" || { json_fail 'unknown target'; return; }
    rm -rf "$(stage_dir)"; json_ok ',"aborted":true'
}

commit_persistent() {
    decoded="$1"; tag="web-$TARGET"
    OURFW_CANDIDATE_SRC="$decoded" OURFW_CANDIDATE_REL="$REL" "$OURFW/runtime/ourfw-apply.sh" "$tag" >/tmp/ourfw-web-apply.log 2>&1
    rc=$?
    [ $rc -eq 0 ] || { json_fail "apply failed rc=$rc"; return; }
    json_ok ',"pending":true,"rollback_seconds":90'
}

decode_staged_upload() {
    # target_info must already have been called.
    d=$(stage_dir); [ -f "$d/expected.sha256" ] && [ -f "$d/data.b64" ] || return 1
    expected=$(cat "$d/expected.sha256" 2>/dev/null); decoded="$d/decoded.bin"
    b64url_decode "$d/data.b64" "$decoded" || return 1
    actual=$(sha256sum "$decoded" | awk '{print $1}')
    [ "$(printf '%s' "$actual" | tr A-F a-f)" = "$(printf '%s' "$expected" | tr A-F a-f)" ] || return 1
    validate_candidate "$decoded" || return 1
    return 0
}

op_stage() {
    target_info "$1" || { json_fail 'unknown target'; return; }
    [ -n "$REL" ] || { json_fail 'special target cannot be section-staged'; return; }
    d=$(stage_dir); decode_staged_upload || { rm -rf "$d"; json_fail 'staged candidate validation failed'; return; }
    dst="$EDIT/$TARGET"; cp "$decoded" "$dst.tmp" || { rm -rf "$d"; json_fail 'cannot stage candidate'; return; }
    mv "$dst.tmp" "$dst" || { rm -rf "$d"; json_fail 'cannot stage candidate'; return; }
    rm -rf "$d"
    json_ok ',"staged":true'
}

op_section_abort() {
    targets=$(section_targets "$1") || { json_fail 'unknown section'; return; }
    for t in $targets; do rm -f "$EDIT/$t"; done
    json_ok ',"aborted":true'
}

op_section_commit() {
    section="$1"; targets=$(section_targets "$section") || { json_fail 'unknown section'; return; }
    tree="$STATE/section-tree.$$"; arc="$STATE/section-patch.$$.tar.bz2"
    rm -rf "$tree" "$arc"; mkdir -p "$tree" || { json_fail 'cannot create section staging'; return; }
    count=0
    for t in $targets; do
        [ -f "$EDIT/$t" ] || continue
        target_info "$t" || { rm -rf "$tree"; json_fail 'invalid staged target'; return; }
        validate_candidate "$EDIT/$t" || { rm -rf "$tree"; json_fail "staged target failed validation: $t"; return; }
        [ -n "$REL" ] || { rm -rf "$tree"; json_fail 'special target in section'; return; }
        mkdir -p "$tree/$(dirname "$REL")" || { rm -rf "$tree"; json_fail 'cannot create patch tree'; return; }
        cp "$EDIT/$t" "$tree/$REL" || { rm -rf "$tree"; json_fail 'cannot build patch tree'; return; }
        count=$((count+1))
    done
    [ "$count" -gt 0 ] || { rm -rf "$tree"; json_fail 'nothing staged'; return; }
    ( cd "$tree" && tar -cf - . 2>/dev/null ) | bzip2 -9 > "$arc" || { rm -rf "$tree" "$arc"; json_fail 'cannot build patch archive'; return; }
    rm -rf "$tree"
    OURFW_CANDIDATE_PATCH="$arc" "$OURFW/runtime/ourfw-apply.sh" "web-section-$section" >/tmp/ourfw-web-apply.log 2>&1
    rc=$?; rm -f "$arc"
    [ $rc -eq 0 ] || { json_fail "section apply failed rc=$rc"; return; }
    for t in $targets; do rm -f "$EDIT/$t"; done
    json_ok ',"pending":true,"section":"'"$section"'","rollback_seconds":90'
}

op_commit() {
    target_info "$1" || { json_fail 'unknown target'; return; }
    d=$(stage_dir); [ -f "$d/expected.sha256" ] && [ -f "$d/data.b64" ] || { json_fail 'upload not started'; return; }
    expected=$(cat "$d/expected.sha256" 2>/dev/null); decoded="$d/decoded.bin"
    b64url_decode "$d/data.b64" "$decoded" || { rm -rf "$d"; json_fail 'base64 decode failed'; return; }
    actual=$(sha256sum "$decoded" | awk '{print $1}')
    [ "$(printf '%s' "$actual" | tr A-F a-f)" = "$(printf '%s' "$expected" | tr A-F a-f)" ] || { rm -rf "$d"; json_fail 'sha256 mismatch'; return; }
    validate_candidate "$decoded" || { rm -rf "$d"; json_fail 'candidate validation failed'; return; }

    case "$KIND" in
      component)
        "$OURFW/runtime/ourfw-update.sh" install "$decoded" "$actual" >/tmp/ourfw-web-component.log 2>&1
        rc=$?; rm -rf "$d"
        [ $rc -eq 0 ] || { json_fail "component install failed rc=$rc"; return; }
        json_ok ',"pending":true,"kind":"component"'
        ;;
      backup)
        "$OURFW/runtime/ourfw-backup.sh" restore "$decoded" >/tmp/ourfw-web-restore.log 2>&1
        rc=$?; rm -rf "$d"
        [ $rc -eq 0 ] || { json_fail "backup restore failed rc=$rc"; return; }
        json_ok ',"pending":true,"kind":"backup"'
        ;;
      *)
        # Keep decoded file until synchronous candidate copy has completed.
        commit_persistent "$decoded"; rc=$?; rm -rf "$d"; return $rc
        ;;
    esac
}

export_json_file() {
    kind="$1"; f="$2"; name="$3"
    [ -f "$f" ] || { json_fail "$kind unavailable"; return; }
    bytes=$(wc -c < "$f" | tr -d ' '); sha=$(sha256sum "$f" | awk '{print $1}')
    printf '{"ok":true,"kind":"%s","name":"%s","bytes":%s,"sha256":"%s","data":"' \
      "$kind" "$(json_escape "$name")" "$bytes" "$sha"
    b64url_encode "$f"
    printf '"}\n'
}

case "${1:-}" in
  get) op_get "${2:-}" ;;
  begin) op_begin "${2:-}" "${3:-}" ;;
  chunk) op_chunk "${2:-}" "${3:-}" ;;
  commit) op_commit "${2:-}" ;;
  stage) op_stage "${2:-}" ;;
  abort) op_abort "${2:-}" ;;
  section-commit) op_section_commit "${2:-}" ;;
  section-abort) op_section_abort "${2:-}" ;;
  backup-export)
    f="$($OURFW/runtime/ourfw-backup.sh export 2>/dev/null | tail -n1)"
    export_json_file backup "$f" "ourfw-backup-$(date +%Y%m%d-%H%M%S 2>/dev/null || echo current).tar.bz2"
    rm -f "$f" 2>/dev/null || true
    ;;
  diagnostics-export)
    f="$($OURFW/modules/diagnostics/snapshot.sh 2>/dev/null | tail -n1)"
    export_json_file diagnostics "$f" "ourfw-diagnostics-$(date +%Y%m%d-%H%M%S 2>/dev/null || echo current).txt"
    ;;
  *) json_fail 'unsupported transfer operation' ;;
esac
