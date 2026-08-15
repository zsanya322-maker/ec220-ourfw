#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LOADER="$ROOT/bootstrap/ourfw-loader.sh"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT INT TERM

make_old(){
  local base=$1
  rm -rf "$base"; mkdir -p "$base/runtime" "$base/config" "$base/profiles" "$base/rules"
  printf 'v0.6.1\n' > "$base/VERSION"
  printf 'user-value=keep\n' > "$base/config/custom.conf"
  printf 'profile-secret\n' > "$base/profiles/custom.conf"
  printf '198.51.100.0/24\n' > "$base/rules/custom.list"
  cat > "$base/runtime/ourfwctl.sh" <<'SH'
#!/bin/sh
exit 0
SH
  chmod +x "$base/runtime/ourfwctl.sh"
}

make_defaults(){
  local dir=$1 arc=$2 broken=$3
  rm -rf "$dir"; mkdir -p "$dir/runtime" "$dir/modules/test" "$dir/config" "$dir/profiles" "$dir/rules"
  printf 'v0.6.2\n' > "$dir/VERSION"
  cat > "$dir/runtime/ourfwctl.sh" <<'SH'
#!/bin/sh
exit 0
SH
  if [[ "$broken" == 1 ]]; then
    cat > "$dir/modules/test/apply.sh" <<'SH'
#!/bin/sh
if then this is deliberately broken
SH
  else
    cat > "$dir/modules/test/apply.sh" <<'SH'
#!/bin/sh
exit 0
SH
  fi
  chmod +x "$dir/runtime/ourfwctl.sh" "$dir/modules/test/apply.sh"
  ( cd "$dir" && tar -cjf "$arc" . )
}

run_loader(){
  local base=$1 arc=$2 save=$3 log=$4
  OURFW_LOADER_BASE="$base" \
  OURFW_LOADER_DEFAULTS="$arc" \
  OURFW_LOADER_DISABLE="$T/disabled" \
  OURFW_LOADER_RESET="$T/reset" \
  OURFW_LOADER_LOG="$log" \
  OURFW_LOADER_WEB_DST="$T/no-web" \
  OURFW_LOADER_CSRF="$T/csrf" \
  OURFW_LOADER_STORAGE_SAVE="$save" \
  "$LOADER"
}

# 1) Broken firmware mutable payload: preflight must restore old tree before any
# storage write can make the broken candidate persistent.
BASE1="$T/base1"; ARC1="$T/broken.tar.bz2"; make_old "$BASE1"; make_defaults "$T/def-bad" "$ARC1" 1
cat > "$T/save-ok" <<'SH'
#!/bin/sh
printf 'save\n' >> "${SAVE_LOG:?}"
exit 0
SH
chmod +x "$T/save-ok"
: > "$T/save1.log"
SAVE_LOG="$T/save1.log" run_loader "$BASE1" "$ARC1" "$T/save-ok" "$T/loader1.log"
grep -qx 'v0.6.1' "$BASE1/VERSION"
grep -qx 'user-value=keep' "$BASE1/config/custom.conf"
[[ ! -s "$T/save1.log" ]]
grep -q 'refresh failed preflight; restored v0.6.1' "$T/loader1.log"

# 2) Valid candidate but mtd_storage refusal: keep old in-RAM tree and do not
# report the upgrade as successful.
BASE2="$T/base2"; ARC2="$T/good.tar.bz2"; make_old "$BASE2"; make_defaults "$T/def-good" "$ARC2" 0
cat > "$T/save-fail" <<'SH'
#!/bin/sh
printf 'attempt\n' >> "${SAVE_LOG:?}"
exit 9
SH
chmod +x "$T/save-fail"
: > "$T/save2.log"
SAVE_LOG="$T/save2.log" run_loader "$BASE2" "$ARC2" "$T/save-fail" "$T/loader2.log"
grep -qx 'v0.6.1' "$BASE2/VERSION"
grep -qx 'profile-secret' "$BASE2/profiles/custom.conf"
grep -qx '198.51.100.0/24' "$BASE2/rules/custom.list"
grep -q 'refresh storage save failed; restored v0.6.1' "$T/loader2.log"
[[ $(wc -l < "$T/save2.log") -ge 1 ]]

echo 'V0.6.2 LOADER FAILURE MOCK: OK'
