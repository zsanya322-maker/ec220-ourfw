#!/bin/sh
mkdir -p /tmp/ourfw-diag
/etc/storage/ourfw/modules/diagnostics/snapshot.sh /tmp/ourfw-diag/boot.txt >/dev/null 2>&1 || true
exit 0
