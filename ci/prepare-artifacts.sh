#!/bin/bash
set -euo pipefail
TREE=${1:-padavan-ng}
OUT=${2:-dist}
PINNED=0e6caa2749a8814345c8a0d496a2fde2e6746a7d
BOARD=TL_EC220_G5-V2
mkdir -p "$OUT"

actual=$(git -C "$TREE" rev-parse HEAD)
[[ "$actual" == "$PINNED" ]] || { echo "wrong upstream commit: $actual" >&2; exit 20; }

# Pick the image by exact board prefix; mtime-based selection is unstable and
# could grab an unrelated leftover file from images/. Prefer the flash .bin
# and fall back to .trx only when no .bin was produced.
fw=$(find "$TREE/trunk/images" -maxdepth 1 -type f -name "${BOARD}_*.bin" | sort)
[[ -z "$fw" ]] && fw=$(find "$TREE/trunk/images" -maxdepth 1 -type f -name "${BOARD}_*.trx" | sort)
[[ "$(printf '%s\n' "$fw" | grep -c .)" -eq 1 ]] || { echo "firmware image not found or ambiguous: ${fw:-none}" >&2; exit 21; }
size=$(stat -c %s "$fw")

# Parse the target's own partition map like the known-good danayer workflow.
partitions="$TREE/trunk/configs/boards/TPLINK/$BOARD/partitions.config"
[[ -f "$partitions" ]] || { echo "partition map missing: $partitions" >&2; exit 22; }
partition_max=$(awk '/Firmware/ { getline; getline; gsub(",", "", $2); print strtonum($2); exit }' "$partitions")
[[ "$partition_max" =~ ^[0-9]+$ && "$partition_max" -gt 0 ]] || { echo 'cannot parse firmware partition size' >&2; exit 23; }

# Verified against the pinned board file: the "Firmware" partition is
# 0x780000 (Storage starts at 0x7A0000). Refuse a surprise repartition
# instead of silently trusting a changed upstream board file.
expected_partition_max=$((0x780000))
(( partition_max == expected_partition_max )) || {
  printf 'unexpected firmware partition: %d (expected %d)\n' "$partition_max" "$expected_partition_max" >&2
  exit 24
}

# OURFW deliberately reserves 64 KiB headroom inside the firmware partition.
safety_margin=$((64*1024))
safe_max=$((partition_max-safety_margin))
if (( size > safe_max )); then
  echo "firmware too large: $size > safe limit $safe_max" >&2
  exit 25
fi

name="TL_EC220_G5-V2_OURFW-v0.3-${actual:0:10}.bin"
cp "$fw" "$OUT/$name"
dd if=/dev/zero of="$OUT/128kempty.bin" bs=131072 count=1 status=none
cat "$OUT/128kempty.bin" "$OUT/$name" > "$OUT/tp_recovery.bin"
rm "$OUT/128kempty.bin"

# Recovery invariant proven by the user's known-good danayer pair:
# exactly 128 KiB zero prefix followed byte-for-byte by the web .bin.
head -c 131072 "$OUT/tp_recovery.bin" | cmp - <(head -c 131072 /dev/zero)
tail -c +131073 "$OUT/tp_recovery.bin" | cmp - "$OUT/$name"
[[ $(stat -c %s "$OUT/tp_recovery.bin") -eq $((size+131072)) ]]

sha256sum "$OUT/$name" "$OUT/tp_recovery.bin" > "$OUT/SHA256SUMS.txt"
cat > "$OUT/BUILD-REPORT.txt" <<REPORT
OURFW_VERSION=v0.3
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

if command -v bzip2 >/dev/null 2>&1; then
  packed=$(tar -C ourfw -cf - . | bzip2 -9 | wc -c)
  echo "OURFW_MUTABLE_BZIP2_BYTES=$packed" >> "$OUT/BUILD-REPORT.txt"
fi

printf 'Artifacts ready:\n'
cat "$OUT/BUILD-REPORT.txt"
cat "$OUT/SHA256SUMS.txt"
