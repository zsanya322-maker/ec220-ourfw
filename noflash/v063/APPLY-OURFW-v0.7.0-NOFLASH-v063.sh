#!/bin/sh
# OURFW v0.7.0 no-flash overlay installer for the hardware-confirmed
# EC220-G5 v2 baseline: firmware v0.6.3 + command/CSRF/WebUI hotfixes.
#
# This never writes the firmware partition. It updates only /etc/storage/ourfw,
# keeps /etc/storage/ourfw/VERSION at v0.6.3 so the immutable v0.6.3 loader
# will not refresh the mutable tree on boot, and stores the feature version in
# VERSION.overlay instead.
set -u

BASE=/etc/storage/ourfw
EXPECTED_BASE=v0.6.3
EXPECTED_OVERLAY=v0.7.0-noflash-v063
KERNEL_EXPECTED=3.4.113
BACKUP=/tmp/OURFW-v0.6.3-HF123-before-v0.7.0-noflash.tar.bz2
STAGE=/tmp/ourfw-v070-noflash-stage.$$
SELF_DIR=${0%/*}
[ "$SELF_DIR" != "$0" ] || SELF_DIR=.
PAYLOAD="$SELF_DIR/OURFW-v0.7.0-NOFLASH-v063-payload.tar.bz2"
MANIFEST="$SELF_DIR/MANIFEST.txt"
LIST=/tmp/ourfw-v070-noflash-list.$$

cleanup() { rm -rf "$STAGE" "$LIST" 2>/dev/null || true; }
trap cleanup EXIT HUP INT TERM

fail() { echo "NOFLASH_INSTALL_FAIL: $*" >&2; exit 1; }

have_exec() {
    _name="$1"
    case "$_name" in */*) [ -x "$_name" ]; return $?;; esac
    _oldifs="$IFS"; IFS=:
    for _dir in ${PATH:-/bin:/sbin:/usr/bin:/usr/sbin}; do
        [ -n "$_dir" ] || _dir=.
        if [ -x "$_dir/$_name" ]; then IFS="$_oldifs"; return 0; fi
    done
    IFS="$_oldifs"
    return 1
}

sha_file() {
    f="$1"
    if [ -x /usr/bin/sha256sum ]; then /usr/bin/sha256sum "$f" | awk '{print $1}'
    elif [ -x /bin/sha256sum ]; then /bin/sha256sum "$f" | awk '{print $1}'
    else return 1
    fi
}

restore_backup() {
    [ -s "$BACKUP" ] || return 1
    echo "Restoring pre-install OURFW tree..."
    rm -rf "$BASE" || return 1
    tar -xjf "$BACKUP" -C /etc/storage || return 1
    [ "$(cat "$BASE/VERSION" 2>/dev/null || true)" = "$EXPECTED_BASE" ] || return 1
    /sbin/mtd_storage.sh save >/dev/null 2>&1 || mtd_storage.sh save >/dev/null 2>&1 || return 1
    echo "RESTORE_OK=1"
}

printf '%s\n' '===== OURFW v0.7.0 NO-FLASH INSTALL ====='
printf 'BASE_EXPECTED=%s\nOVERLAY=%s\n' "$EXPECTED_BASE" "$EXPECTED_OVERLAY"

[ "$(id -u 2>/dev/null || echo 1)" = 0 ] || fail 'run through the router admin/root SSH session'
[ -d "$BASE/runtime" ] && [ -d "$BASE/modules" ] && [ -d "$BASE/www" ] || fail 'OURFW mutable tree missing'
[ "$(cat "$BASE/VERSION" 2>/dev/null || true)" = "$EXPECTED_BASE" ] || fail 'live OURFW base is not v0.6.3'
[ "$(uname -r 2>/dev/null || true)" = "$KERNEL_EXPECTED" ] || fail 'kernel is not the hardware-tested 3.4.113 baseline'

# Require the exact live state that was confirmed on the router before making a
# persistent overlay. These gates prevent accidentally applying the package to
# an unpatched/unknown v0.6.3 installation.
[ -f "$BASE/runtime/.command-compat-hotfix1" ] || fail 'HOTFIX1 marker missing'
[ -f "$BASE/runtime/.csrf-compat-hotfix2" ] || fail 'HOTFIX2 marker missing'
if grep -Fq 'command -v' "$BASE/runtime/ourfw-common.sh" 2>/dev/null; then fail 'mutable command compatibility regression detected'; fi
grep -Fq 'csrf_ensure()' "$BASE/runtime/ourfwctl.sh" 2>/dev/null || fail 'CSRF self-heal missing'
if grep -Fq 'setInterval(status,15000)' "$BASE/www/assets/ourfw.js" 2>/dev/null; then fail 'HOTFIX3 is not installed'; fi
grep -Fq 'visibilitychange' "$BASE/www/assets/ourfw.js" 2>/dev/null || fail 'HOTFIX3 visibility refresh missing'

[ -s "$PAYLOAD" ] || fail "payload missing: $PAYLOAD"
[ -s "$MANIFEST" ] || fail "manifest missing: $MANIFEST"
have_exec tar || fail 'tar missing'
have_exec bzip2 || fail 'bzip2 missing'
sha_file "$PAYLOAD" >/dev/null 2>&1 || fail 'sha256sum missing'

expected_sha="$(sed -n 's/^PAYLOAD_SHA256=//p' "$MANIFEST" 2>/dev/null | head -n1)"
case "$expected_sha" in ''|*[!0-9A-Fa-f]*) fail 'manifest payload SHA256 invalid';; esac
[ "${#expected_sha}" -eq 64 ] 2>/dev/null || fail 'manifest payload SHA256 length invalid'
actual_sha="$(sha_file "$PAYLOAD")" || fail 'cannot hash payload'
[ "$(printf '%s' "$actual_sha" | tr A-F a-f)" = "$(printf '%s' "$expected_sha" | tr A-F a-f)" ] || fail 'payload SHA256 mismatch'

rm -rf "$STAGE" "$LIST" 2>/dev/null
mkdir -p "$STAGE" || fail 'cannot create RAM staging directory'
tar -tjf "$PAYLOAD" > "$LIST" 2>/dev/null || fail 'cannot list payload archive'
while IFS= read -r member; do
    case "/$member/" in */../*) fail 'unsafe ../ path in payload';; esac
    case "$member" in
      .|./|runtime|runtime/|runtime/*|./runtime|./runtime/|./runtime/*|modules|modules/|modules/*|./modules|./modules/|./modules/*|www|www/|www/*|./www|./www/|./www/*|defaults|defaults/|defaults/*|./defaults|./defaults/|./defaults/*|VERSION.overlay|./VERSION.overlay) ;;
      *) fail "unexpected payload member: $member";;
    esac
done < "$LIST"
tar -xjf "$PAYLOAD" -C "$STAGE" || fail 'payload extraction failed'

[ ! -e "$STAGE/VERSION" ] || fail 'payload must never replace base VERSION'
[ "$(cat "$STAGE/VERSION.overlay" 2>/dev/null || true)" = "$EXPECTED_OVERLAY" ] || fail 'overlay version mismatch'
[ -d "$STAGE/runtime" ] && [ -d "$STAGE/modules/subscription" ] && [ -d "$STAGE/www" ] || fail 'required v0.7 payload trees missing'
[ -x "$STAGE/runtime/ourfw-api.sh" ] || chmod 0755 "$STAGE/runtime/ourfw-api.sh" 2>/dev/null || true

# Production WebUI must keep the hardware-confirmed no-poll behavior.
if grep -Fq 'setInterval(status' "$STAGE/www/assets/ourfw.js" 2>/dev/null; then fail 'candidate WebUI reintroduces periodic polling'; fi
grep -Fq 'visibilitychange' "$STAGE/www/assets/ourfw.js" 2>/dev/null || fail 'candidate WebUI visibility refresh missing'
grep -Fq 'href="/ourfw/subscription.asp"' "$STAGE/www/index.asp" 2>/dev/null || fail 'subscription navigation missing'
[ -f "$STAGE/www/subscription.asp" ] && [ -f "$STAGE/www/assets/subscription.js" ] || fail 'subscription WebUI files missing'

# The three modules below are exactly the binaries already loaded successfully
# on this physical v0.6.3 kernel. Keeping them in Storage costs only about 6 KiB
# when bzip2-compressed and removes a network dependency from future boots.
MODDIR="$STAGE/modules/vpn/tproxy-modules"
[ -s "$MODDIR/nf_tproxy_core.ko" ] || fail 'nf_tproxy_core.ko missing'
[ -s "$MODDIR/xt_socket.ko" ] || fail 'xt_socket.ko missing'
[ -s "$MODDIR/xt_TPROXY.ko" ] || fail 'xt_TPROXY.ko missing'
[ "$(sha_file "$MODDIR/nf_tproxy_core.ko")" = '904722a51c27a85e6d54376c9c66b134562a83203506725b4ff0e22722848c1a' ] || fail 'nf_tproxy_core SHA mismatch'
[ "$(sha_file "$MODDIR/xt_socket.ko")" = 'cbd1178368ce77109bc089e214e93135fbec2edbb36a66e86032fa3b9d9787e9' ] || fail 'xt_socket SHA mismatch'
[ "$(sha_file "$MODDIR/xt_TPROXY.ko")" = '513cdec45fdd853fbef8ffe7810e49ec3b3bcd8391359c903b373a6f18d9a79f' ] || fail 'xt_TPROXY SHA mismatch'

bad=0
for f in "$STAGE"/runtime/*.sh "$STAGE"/modules/*/*.sh; do
    [ -f "$f" ] || continue
    sh -n "$f" >/dev/null 2>&1 || { echo "shell preflight failed: $f" >&2; bad=1; }
done
[ "$bad" -eq 0 ] || fail 'candidate shell preflight failed'

# Full live mutable backup remains in RAM until reboot. Download it with WinSCP
# before reboot if a byte-for-byte rollback copy is desired on the PC.
rm -f "$BACKUP" "$BACKUP.sha256" 2>/dev/null
tar -cjf "$BACKUP" -C /etc/storage ourfw || fail 'cannot create pre-install backup'
sha_file "$BACKUP" > "$BACKUP.sha256" 2>/dev/null || true
printf 'BACKUP=%s\n' "$BACKUP"

# Overlay code/UI only. Existing config, profiles and rules are preserved.
# Subscription defaults are created only when absent.
cp -a "$STAGE/runtime/." "$BASE/runtime/" || { restore_backup >/dev/null 2>&1 || true; fail 'runtime overlay failed'; }
cp -a "$STAGE/modules/." "$BASE/modules/" || { restore_backup >/dev/null 2>&1 || true; fail 'module overlay failed'; }
cp -a "$STAGE/www/." "$BASE/www/" || { restore_backup >/dev/null 2>&1 || true; fail 'WebUI overlay failed'; }

mkdir -p "$BASE/config" "$BASE/profiles" || { restore_backup >/dev/null 2>&1 || true; fail 'cannot create mutable config/profile directories'; }
if [ ! -e "$BASE/config/subscription.conf" ]; then
    cp "$STAGE/defaults/config/subscription.conf" "$BASE/config/subscription.conf" || { restore_backup >/dev/null 2>&1 || true; fail 'subscription config seed failed'; }
fi
if [ ! -e "$BASE/profiles/subscription.secret" ]; then
    cp "$STAGE/defaults/profiles/subscription.secret" "$BASE/profiles/subscription.secret" || { restore_backup >/dev/null 2>&1 || true; fail 'subscription secret seed failed'; }
fi
chmod 0600 "$BASE/config/subscription.conf" "$BASE/profiles/subscription.secret" 2>/dev/null || true
printf '%s\n' "$EXPECTED_OVERLAY" > "$BASE/VERSION.overlay" || { restore_backup >/dev/null 2>&1 || true; fail 'cannot write overlay version'; }
[ "$(cat "$BASE/VERSION" 2>/dev/null || true)" = "$EXPECTED_BASE" ] || { restore_backup >/dev/null 2>&1 || true; fail 'base VERSION was unexpectedly changed'; }

find "$BASE/runtime" "$BASE/modules" -type f -name '*.sh' -exec chmod 0755 {} \; 2>/dev/null || true
bad=0
for f in "$BASE"/runtime/*.sh "$BASE"/modules/*/*.sh; do
    [ -f "$f" ] || continue
    sh -n "$f" >/dev/null 2>&1 || { echo "live shell preflight failed: $f" >&2; bad=1; }
done
if [ "$bad" -ne 0 ]; then restore_backup >/dev/null 2>&1 || true; fail 'live shell preflight failed; restored previous tree'; fi

# Pre-create/repair the local subscription salt without saving Storage yet.
# subscription_ensure_salt() normally persists a newly created salt itself; doing
# that here would bypass the installer's single final MTD transaction gate. A
# valid salt makes the passive initialization below strictly RAM/filesystem-only,
# and the one final mtd_storage save then persists code + salt atomically.
SUB_SALT="$BASE/profiles/subscription.salt"
salt="$(sed -n '1p' "$SUB_SALT" 2>/dev/null | tr -d '\r\n' || true)"
case "$salt" in *[!0-9A-Fa-f]*) salt="";; esac
if [ "${#salt}" -ne 64 ] 2>/dev/null; then
    sum=/usr/bin/sha256sum
    [ -x "$sum" ] || sum=/bin/sha256sum
    [ -x "$sum" ] || { restore_backup >/dev/null 2>&1 || true; fail 'sha256sum unavailable for subscription salt'; }
    salt_tmp="$SUB_SALT.tmp.$$"
    ( umask 077; dd if=/dev/urandom bs=32 count=1 2>/dev/null | "$sum" 2>/dev/null | awk '{print $1}' > "$salt_tmp" ) || {
        rm -f "$salt_tmp"; restore_backup >/dev/null 2>&1 || true; fail 'subscription salt generation failed';
    }
    salt="$(sed -n '1p' "$salt_tmp" 2>/dev/null | tr -d '\r\n')"
    case "$salt" in *[!0-9A-Fa-f]*) salt="";; esac
    [ "${#salt}" -eq 64 ] 2>/dev/null || { rm -f "$salt_tmp"; restore_backup >/dev/null 2>&1 || true; fail 'generated subscription salt invalid'; }
    chmod 0600 "$salt_tmp" 2>/dev/null || true
    mv "$salt_tmp" "$SUB_SALT" || { restore_backup >/dev/null 2>&1 || true; fail 'cannot install subscription salt'; }
fi
chmod 0600 "$SUB_SALT" 2>/dev/null || true

# Passive initialization only. Because a valid salt now exists, this step does
# not call mtd_storage.sh. It does not fetch a subscription, start Hysteria, or
# touch routing/firewall/DNS.
"$BASE/modules/subscription/start.sh" boot >/tmp/ourfw-v070-noflash-subscription-init.log 2>&1 || {
    restore_backup >/dev/null 2>&1 || true
    fail 'passive subscription initialization failed; restored previous tree'
}

# Storage write is the single final gate. If it refuses the larger mutable tree, put the
# exact pre-install tree back and persist that instead.
if [ -x /sbin/mtd_storage.sh ]; then SAVE=/sbin/mtd_storage.sh; else SAVE=mtd_storage.sh; fi
if ! "$SAVE" save; then
    echo 'Storage save rejected candidate; restoring previous OURFW...'
    restore_backup || fail 'storage save failed and automatic restore also failed'
    fail 'candidate did not fit/persist; previous tree restored'
fi

printf '%s\n' '===== NO-FLASH INSTALL OK ====='
printf 'BASE_VERSION=%s\n' "$(cat "$BASE/VERSION" 2>/dev/null || true)"
printf 'OVERLAY_VERSION=%s\n' "$(cat "$BASE/VERSION.overlay" 2>/dev/null || true)"
printf 'TPROXY_MODULES=PERSISTENT_STORAGE_VERIFIED\n'
printf 'HYSTERIA_ENGINE=RAM_ONLY_VERIFIED_FETCH\n'
printf 'ROUTING_CHANGED=NO\nVPN_STARTED=NO\nSUBSCRIPTION_FETCHED=NO\n'
printf 'BACKUP=%s\n' "$BACKUP"
printf '%s\n' 'Before reboot: verify WebUI/SSH, then optionally download BACKUP with WinSCP.'
