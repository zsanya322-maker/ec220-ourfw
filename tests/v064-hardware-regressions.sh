#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

# Real EC220-G5 v2 BusyBox ash has no POSIX `command` builtin. Target-side
# runtime and immutable loader must never reintroduce `command -v`.
if grep -R -nF 'command -v' "$ROOT/ourfw/runtime" "$ROOT/ourfw/modules" "$ROOT/bootstrap/ourfw-loader.sh"; then
    echo 'v0.6.4+ regression: target command -v dependency found' >&2
    exit 1
fi

grep -q '^have_exec() {' "$ROOT/ourfw/runtime/ourfw-common.sh" || {
    echo 'v0.6.4+ regression: mutable executable resolver missing' >&2; exit 1;
}
grep -q '^have_exec() {' "$ROOT/bootstrap/ourfw-loader.sh" || {
    echo 'v0.6.4+ regression: immutable executable resolver missing' >&2; exit 1;
}
grep -q '^csrf_ensure() {' "$ROOT/ourfw/runtime/ourfwctl.sh" || {
    echo 'v0.6.4+ regression: mutable CSRF self-heal missing' >&2; exit 1;
}
grep -q '^csrf_new() {' "$ROOT/bootstrap/ourfw-loader.sh" || {
    echo 'v0.6.4+ regression: immutable CSRF generator missing' >&2; exit 1;
}
grep -q '/usr/bin/sha256sum' "$ROOT/ourfw/runtime/ourfwctl.sh" || {
    echo 'v0.6.4+ regression: CSRF direct sha256sum path missing' >&2; exit 1;
}

# The generated immutable copy must stay byte-for-byte aligned with canonical
# bootstrap source; make-defaults.sh will refresh it during CI integration.
cmp -s "$ROOT/bootstrap/ourfw-loader.sh" "$ROOT/integration/padavan-user-ourfw/files/ourfw-loader.sh" || {
    echo 'v0.6.4+ regression: immutable loader copies differ' >&2; exit 1;
}

# Hardware A/B proved the 15-second WebUI status poll causes CPU and local ping
# spikes on the single-core MT7620A. Payload generation must remove periodic
# polling and install only an event-driven visibility refresh.
grep -Fq 'periodic OURFW status polling survived payload generation' "$ROOT/build/make-defaults.sh" || {
    echo 'v0.6.4+ regression: WebUI polling payload gate missing' >&2; exit 1;
}
if grep -Fq 'setInterval(status' "$ROOT/integration/padavan-user-ourfw/files/www/assets/ourfw.js"; then
    echo 'v0.6.4+ regression: generated WebUI still polls periodically' >&2; exit 1
fi
grep -Fq "document.addEventListener('visibilitychange'" "$ROOT/integration/padavan-user-ourfw/files/www/assets/ourfw.js" || {
    echo 'v0.6.4+ regression: generated WebUI visibility refresh missing' >&2; exit 1;
}

# These are permanent hardware regressions, not tests for one release string.
# Any future firmware must remain >= v0.6.4 and keep all of the checks above.
ver="$(cat "$ROOT/ourfw/VERSION" 2>/dev/null || true)"
case "$ver" in
  v[0-9]*.[0-9]*.[0-9]*) ;;
  *) echo "v0.6.4+ regression: invalid VERSION '$ver'" >&2; exit 1;;
esac
nums=${ver#v}
oldIFS=$IFS; IFS=.; set -- $nums; IFS=$oldIFS
[ "$#" -eq 3 ] || { echo "v0.6.4+ regression: invalid VERSION '$ver'" >&2; exit 1; }
maj=$1; min=$2; pat=$3
case "$maj$min$pat" in *[!0-9]*) echo "v0.6.4+ regression: invalid VERSION '$ver'" >&2; exit 1;; esac
if [ "$maj" -eq 0 ] && { [ "$min" -lt 6 ] || { [ "$min" -eq 6 ] && [ "$pat" -lt 4 ]; }; }; then
    echo "v0.6.4+ regression: VERSION regressed to '$ver'" >&2
    exit 1
fi

echo "V0.6.4+ HARDWARE REGRESSIONS: OK ($ver)"
