#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

# Real EC220-G5 v2 BusyBox ash has no POSIX `command` builtin. Target-side
# runtime and immutable loader must never reintroduce `command -v`.
if grep -R -nF 'command -v' "$ROOT/ourfw/runtime" "$ROOT/ourfw/modules" "$ROOT/bootstrap/ourfw-loader.sh"; then
    echo 'v0.6.4 regression: target command -v dependency found' >&2
    exit 1
fi

grep -q '^have_exec() {' "$ROOT/ourfw/runtime/ourfw-common.sh" || {
    echo 'v0.6.4 regression: mutable executable resolver missing' >&2; exit 1;
}
grep -q '^have_exec() {' "$ROOT/bootstrap/ourfw-loader.sh" || {
    echo 'v0.6.4 regression: immutable executable resolver missing' >&2; exit 1;
}
grep -q '^csrf_ensure() {' "$ROOT/ourfw/runtime/ourfwctl.sh" || {
    echo 'v0.6.4 regression: mutable CSRF self-heal missing' >&2; exit 1;
}
grep -q '^csrf_new() {' "$ROOT/bootstrap/ourfw-loader.sh" || {
    echo 'v0.6.4 regression: immutable CSRF generator missing' >&2; exit 1;
}
grep -q '/usr/bin/sha256sum' "$ROOT/ourfw/runtime/ourfwctl.sh" || {
    echo 'v0.6.4 regression: CSRF direct sha256sum path missing' >&2; exit 1;
}

# The generated immutable copy must stay byte-for-byte aligned with canonical
# bootstrap source; make-defaults.sh will refresh it during CI integration.
cmp -s "$ROOT/bootstrap/ourfw-loader.sh" "$ROOT/integration/padavan-user-ourfw/files/ourfw-loader.sh" || {
    echo 'v0.6.4 regression: immutable loader copies differ' >&2; exit 1;
}

[ "$(cat "$ROOT/ourfw/VERSION")" = 'v0.6.4' ] || {
    echo 'v0.6.4 regression: VERSION mismatch' >&2; exit 1;
}

echo 'V0.6.4 HARDWARE REGRESSIONS: OK'
