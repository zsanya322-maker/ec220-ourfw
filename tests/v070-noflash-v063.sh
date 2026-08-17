#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
INSTALL="$ROOT/noflash/v063/APPLY-OURFW-v0.7.0-NOFLASH-v063.sh"
ROLLBACK="$ROOT/noflash/v063/ROLLBACK-CURRENT-BOOT.sh"

[ -f "$INSTALL" ] && [ -f "$ROLLBACK" ] || { echo 'no-flash installer files missing' >&2; exit 1; }
sh -n "$INSTALL"
sh -n "$ROLLBACK"

grep -Fq 'EXPECTED_BASE=v0.6.3' "$INSTALL" || { echo 'no-flash baseline gate missing' >&2; exit 1; }
grep -Fq 'EXPECTED_OVERLAY=v0.7.0-noflash-v063' "$INSTALL" || { echo 'overlay version gate missing' >&2; exit 1; }
grep -Fq 'KERNEL_EXPECTED=3.4.113' "$INSTALL" || { echo 'kernel compatibility gate missing' >&2; exit 1; }
grep -Fq '.command-compat-hotfix1' "$INSTALL" || { echo 'HOTFIX1 gate missing' >&2; exit 1; }
grep -Fq '.csrf-compat-hotfix2' "$INSTALL" || { echo 'HOTFIX2 gate missing' >&2; exit 1; }
grep -Fq 'setInterval(status,15000)' "$INSTALL" || { echo 'HOTFIX3 negative gate missing' >&2; exit 1; }
grep -Fq 'visibilitychange' "$INSTALL" || { echo 'HOTFIX3 positive gate missing' >&2; exit 1; }

grep -Fq '[ ! -e "$STAGE/VERSION" ]' "$INSTALL" || { echo 'base VERSION overwrite guard missing' >&2; exit 1; }
grep -Fq 'VERSION.overlay' "$INSTALL" || { echo 'overlay version file missing' >&2; exit 1; }
grep -Fq 'Existing config, profiles and rules are preserved' "$INSTALL" || { echo 'preservation contract missing' >&2; exit 1; }
grep -Fq 'subscription/start.sh" boot' "$INSTALL" || { echo 'passive subscription init missing' >&2; exit 1; }
grep -Fq 'ROUTING_CHANGED=NO' "$INSTALL" || { echo 'passive install contract missing' >&2; exit 1; }

# Exact hardware-tested module hashes from the live v0.6.3 RAM test.
for h in \
  904722a51c27a85e6d54376c9c66b134562a83203506725b4ff0e22722848c1a \
  cbd1178368ce77109bc089e214e93135fbec2edbb36a66e86032fa3b9d9787e9 \
  513cdec45fdd853fbef8ffe7810e49ec3b3bcd8391359c903b373a6f18d9a79f; do
    grep -Fq "$h" "$INSTALL" || { echo "module hash gate missing: $h" >&2; exit 1; }
done

# Permanent v0.6.4 hardware regressions must also remain enforced by source.
sh "$ROOT/tests/v064-hardware-regressions.sh" >/dev/null
sh "$ROOT/tests/v070-subscription-manager.sh" >/dev/null
sh "$ROOT/tests/v070-subscription-webui.sh" >/dev/null

echo 'V0.7 NOFLASH v0.6.3 COMPATIBILITY: OK'
