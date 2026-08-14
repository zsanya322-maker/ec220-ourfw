#!/bin/sh
set -eu
SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OURFW_ROOT=$(CDPATH= cd -- "$SELF_DIR/.." && pwd)
TREE=${1:-}
MODE=${2:-prepare}
EXPECTED_UPSTREAM_COMMIT=0e6caa2749a8814345c8a0d496a2fde2e6746a7d

usage() {
    echo "Usage: $0 /path/to/padavan-ng [prepare|build]" >&2
    exit 2
}
[ -n "$TREE" ] || usage
TREE=$(CDPATH= cd -- "$TREE" && pwd)
TRUNK="$TREE/trunk"

# A flash-oriented build must be reproducible. If this is a git checkout,
# reject any source except the exact commit behind the user's known-good image.
if [ -d "$TREE/.git" ] && command -v git >/dev/null 2>&1; then
    ACTUAL_COMMIT=$(git -C "$TREE" rev-parse HEAD 2>/dev/null || true)
    [ "$ACTUAL_COMMIT" = "$EXPECTED_UPSTREAM_COMMIT" ] || {
        echo "Refusing unpinned Padavan tree: $ACTUAL_COMMIT" >&2
        echo "Expected: $EXPECTED_UPSTREAM_COMMIT" >&2
        exit 5
    }
else
    [ "${OURFW_SOURCE_COMMIT:-}" = "$EXPECTED_UPSTREAM_COMMIT" ] || {
        echo "Source export has no .git metadata." >&2
        echo "After verifying it, set OURFW_SOURCE_COMMIT=$EXPECTED_UPSTREAM_COMMIT" >&2
        exit 5
    }
fi

[ -d "$TRUNK" ] || { echo "Missing Padavan trunk: $TRUNK" >&2; exit 3; }

# OURFW owns the exact EC220 build configuration. Do this BEFORE integration,
# because apply-to-padavan.py deliberately refuses any non-EC220 .config.
if [ -f "$TRUNK/.config" ]; then
    cp -f "$TRUNK/.config" "$TRUNK/.config.pre-ourfw"
fi
cp -f "$OURFW_ROOT/build.config" "$TRUNK/.config"

python3 "$OURFW_ROOT/tools/apply-to-padavan.py" "$TREE"
python3 "$OURFW_ROOT/tools/verify-padavan-tree.py" "$TREE"
echo "Prepared exact EC220-G5 v2 OURFW build tree."

case "$MODE" in
  prepare) ;;
  build)
    cd "$TRUNK"
    ./clear_tree.sh
    ./build_firmware.sh
    ;;
  *) usage ;;
esac
