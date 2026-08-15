#!/bin/bash
set -euo pipefail
TREE=${1:-padavan-ng}; OUT=${2:-dist}; PINNED=0e6caa2749a8814345c8a0d496a2fde2e6746a7d; BOARD=TL_EC220_G5-V2
mkdir -p "$OUT"
actual=$(git -C "$TREE" rev-parse HEAD); [[ "$actual" == "$PINNED" ]] || { echo "wrong upstream commit: $actual" >&2; exit 20; }
short=${actual:0:10}
fw="$TREE/trunk/images/TL_EC220_G5-V2_3.4.3.9L-102-${short}.bin"
[[ -f "$fw" ]] || { echo "exact firmware image not found: $fw" >&2; ls -la "$TREE/trunk/images" >&2 || true; exit 21; }
size=$(stat -c %s "$fw")
partitions="$TREE/trunk/configs/boards/TPLINK/$BOARD/partitions.config"; [[ -f "$partitions" ]] || exit 22
partition_max=$(awk '/Firmware/ { getline; getline; gsub(",", "", $2); print strtonum($2); exit }' "$partitions")
[[ "$partition_max" =~ ^[0-9]+$ && "$partition_max" -gt 0 ]] || { echo 'cannot parse firmware partition size' >&2; exit 23; }
# EC220: Firmware offset 0x20000, SIZE 0x780000. 0x7A0000 is Storage offset.
expected_partition_max=$((0x780000))
(( partition_max == expected_partition_max )) || { printf 'unexpected firmware partition: %d (expected %d)\n' "$partition_max" "$expected_partition_max" >&2; exit 24; }
safety_margin=$((64*1024)); safe_max=$((partition_max-safety_margin))
(( size <= safe_max )) || { echo "firmware too large: $size > safe limit $safe_max" >&2; exit 25; }
name="TL_EC220_G5-V2_OURFW-v0.4-${short}.bin"; cp "$fw" "$OUT/$name"
dd if=/dev/zero of="$OUT/128kempty.bin" bs=131072 count=1 status=none; cat "$OUT/128kempty.bin" "$OUT/$name" > "$OUT/tp_recovery.bin"; rm "$OUT/128kempty.bin"
head -c 131072 "$OUT/tp_recovery.bin" | cmp - <(head -c 131072 /dev/zero)
tail -c +131073 "$OUT/tp_recovery.bin" | cmp - "$OUT/$name"
[[ $(stat -c %s "$OUT/tp_recovery.bin") -eq $((size+131072)) ]]
sha256sum "$OUT/$name" "$OUT/tp_recovery.bin" > "$OUT/SHA256SUMS.txt"
cat > "$OUT/BUILD-REPORT.txt" <<REPORT
OURFW_VERSION=v0.4-audit-fixed
DEVICE=TP-Link EC220-G5 v2
PADAVAN_COMMIT=$actual
WEB_IMAGE=$name
WEB_IMAGE_SIZE=$size
FIRMWARE_PARTITION_MAX=$partition_max
OURFW_SAFETY_MARGIN=$safety_margin
OURFW_SAFE_MAX=$safe_max
RECOVERY_PREFIX_BYTES=131072
RECOVERY_SIZE=$(stat -c %s "$OUT/tp_recovery.bin")
KNOWN_GOOD_DANAYER_BIN_SIZE=7602180
KNOWN_GOOD_DANAYER_BIN_SHA256=3f3a42989b6b63128f12a56927f59254b93bcae389259e59438af28b71de5e02
KNOWN_GOOD_DANAYER_RECOVERY_SIZE=7733252
KNOWN_GOOD_DANAYER_RECOVERY_SHA256=4803b92bf10c15b8a41bf3ed93b30584bd2af13ade4a647dd53e2c81dbb48d47
REPORT
[ ! -f integration/padavan-user-ourfw/files/defaults.tar.bz2 ] || echo "OURFW_MUTABLE_BZIP2_BYTES=$(stat -c %s integration/padavan-user-ourfw/files/defaults.tar.bz2)" >> "$OUT/BUILD-REPORT.txt"
printf 'Artifacts ready:\n'; cat "$OUT/BUILD-REPORT.txt"; cat "$OUT/SHA256SUMS.txt"
