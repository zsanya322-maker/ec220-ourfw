#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LOADER="$ROOT/bootstrap/ourfw-loader.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT INT TERM
BASE="$T/storage/ourfw"
DEF="$T/defaults"
ARC="$T/defaults.tar.bz2"
mkdir -p "$BASE/config" "$BASE/profiles" "$BASE/rules" "$BASE/runtime"
printf 'v0.6.0\n' > "$BASE/VERSION"
printf 'old=1\n' > "$BASE/config/shared.conf"
printf 'secret-profile\n' > "$BASE/profiles/custom.conf"
printf '203.0.113.0/24\n' > "$BASE/rules/custom.list"
cat > "$BASE/runtime/ourfwctl.sh" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$BASE/runtime/ourfwctl.sh"

mkdir -p "$DEF/config" "$DEF/profiles" "$DEF/rules" "$DEF/runtime" "$DEF/modules/vpn"
printf 'v0.6.1\n' > "$DEF/VERSION"
printf 'default=1\n' > "$DEF/config/shared.conf"
printf 'new-setting=1\n' > "$DEF/config/new-v061.conf"
cat > "$DEF/runtime/ourfwctl.sh" <<'SH'
#!/bin/sh
printf 'new-controller\n' > "${OURFW_LOADER_TEST_MARKER:?}"
exit 0
SH
cat > "$DEF/modules/vpn/module-handoff.sh" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$DEF/runtime/ourfwctl.sh" "$DEF/modules/vpn/module-handoff.sh"
( cd "$DEF" && tar -cjf "$ARC" . )
cat > "$T/mtd_storage.sh" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "${OURFW_LOADER_TEST_SAVE:?}"
exit 0
SH
chmod +x "$T/mtd_storage.sh"

OURFW_LOADER_BASE="$BASE" \
OURFW_LOADER_DEFAULTS="$ARC" \
OURFW_LOADER_DISABLE="$T/disabled" \
OURFW_LOADER_RESET="$T/reset" \
OURFW_LOADER_LOG="$T/loader.log" \
OURFW_LOADER_WEB_DST="$T/no-web-mount" \
OURFW_LOADER_CSRF="$T/csrf" \
OURFW_LOADER_STORAGE_SAVE="$T/mtd_storage.sh" \
OURFW_LOADER_TEST_MARKER="$T/ctl-marker" \
OURFW_LOADER_TEST_SAVE="$T/save-marker" \
"$LOADER"

grep -qx 'v0.6.1' "$BASE/VERSION"
grep -qx 'old=1' "$BASE/config/shared.conf"
grep -qx 'new-setting=1' "$BASE/config/new-v061.conf"
grep -qx 'secret-profile' "$BASE/profiles/custom.conf"
grep -qx '203.0.113.0/24' "$BASE/rules/custom.list"
[[ -x "$BASE/modules/vpn/module-handoff.sh" ]]
grep -qx 'new-controller' "$T/ctl-marker"
grep -qx 'save' "$T/save-marker"

echo 'LOADER UPGRADE MOCK: OK'
