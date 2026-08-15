#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=${TMPDIR:-/tmp}/ourfw-romfs-mock-$$
trap 'rm -rf "$TMP"' EXIT INT TERM
R="$TMP/tree/trunk/romfs"
mkdir -p "$R/bin" "$R/usr/bin" "$R/usr/sbin" "$R/usr/share/ourfw" "$R/www/ourfw/assets" "$R/lib/modules/3.4/mock" "$TMP/defaults/runtime" "$TMP/defaults/modules/smart-routing" "$TMP/defaults/modules/vpn" "$TMP/defaults/modules/nfqws" "$TMP/defaults/www/assets"
# Regular/symlink layout mirrors the important Padavan pattern that caused v0.4.3 false-positive.
printf '#!/bin/sh\n' > "$R/usr/bin/ourfw-loader.sh"; chmod 755 "$R/usr/bin/ourfw-loader.sh"
printf 'ourfw_api.cgi file-chunk /tmp/ourfw-csrf.token /etc/storage/ourfw/runtime/ourfw-api.sh\n' > "$R/usr/sbin/httpd"
printf 'dropbearmulti\n' > "$R/usr/bin/dropbearmulti"
ln -s /usr/bin/dropbearmulti "$R/usr/sbin/dropbear"
for f in wg awg; do printf x > "$R/usr/sbin/$f"; chmod 755 "$R/usr/sbin/$f"; done
for f in nfqws zapret.sh; do printf x > "$R/usr/bin/$f"; chmod 755 "$R/usr/bin/$f"; done
printf x > "$R/bin/busybox"; chmod 755 "$R/bin/busybox"
ln -s ../../bin/busybox "$R/usr/bin/sha256sum"
ln -s /bin/busybox "$R/bin/base64"
printf 'ourfw-loader.sh\n' > "$R/usr/bin/autostart.sh"
printf '<html>Backup Center vpn-profile</html>\n' > "$R/www/ourfw/index.asp"
printf 'component-package diagnostics-export section-commit\n' > "$R/www/ourfw/assets/ourfw.js"
printf 'body{}\n' > "$R/www/ourfw/assets/ourfw.css"
for f in runtime/ourfwctl.sh runtime/ourfw-api.sh runtime/ourfw-transfer.sh runtime/ourfw-backup.sh runtime/ourfw-ui.sh modules/smart-routing/apply.sh modules/vpn/apply.sh modules/nfqws/apply.sh www/index.asp www/assets/ourfw.js www/assets/ourfw.css; do mkdir -p "$TMP/defaults/$(dirname "$f")"; printf x > "$TMP/defaults/$f"; done
( cd "$TMP/defaults" && tar -cf - . ) | bzip2 -9 > "$R/usr/share/ourfw/defaults.tar.bz2"
for m in wireguard.ko amneziawg.ko nfnetlink_queue.ko xt_NFQUEUE.ko ip6table_mangle.ko; do printf x > "$R/lib/modules/3.4/mock/$m"; done
: > "$TMP/build.log"
bash "$ROOT/ci/verify-built-romfs.sh" "$TMP/tree" "$TMP/build.log" "$TMP/report.txt" >/dev/null
grep -q '^ROMFS_VERIFY=OK$' "$TMP/report.txt"
echo 'ROMFS VERIFIER MOCK: OK'
