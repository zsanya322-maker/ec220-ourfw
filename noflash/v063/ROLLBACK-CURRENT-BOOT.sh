#!/bin/sh
# Restore the exact mutable OURFW tree captured by the v0.7 no-flash installer.
# This helper works until the next reboot because the backup intentionally lives
# in /tmp to avoid consuming scarce persistent Storage.
set -u
BASE=/etc/storage/ourfw
BACKUP=/tmp/OURFW-v0.6.3-HF123-before-v0.7.0-noflash.tar.bz2

[ "$(id -u 2>/dev/null || echo 1)" = 0 ] || { echo 'run as router admin/root' >&2; exit 1; }
[ -s "$BACKUP" ] || { echo "backup missing: $BACKUP" >&2; exit 2; }

rm -rf "$BASE" || exit 3
tar -xjf "$BACKUP" -C /etc/storage || exit 4
[ "$(cat "$BASE/VERSION" 2>/dev/null || true)" = v0.6.3 ] || { echo 'restored VERSION is not v0.6.3' >&2; exit 5; }
if [ -x /sbin/mtd_storage.sh ]; then /sbin/mtd_storage.sh save; else mtd_storage.sh save; fi
rc=$?
[ "$rc" -eq 0 ] || exit "$rc"
echo 'NOFLASH_ROLLBACK_OK=1'
echo 'BASE_VERSION=v0.6.3'
