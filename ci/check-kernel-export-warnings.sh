#!/bin/bash
set -euo pipefail
LOG=${1:-build.log}
REPORT=${2:-MODULE-EXPORTS.txt}
: > "$REPORT"
[[ -f "$LOG" ]] || { echo 'MODULE_EXPORTS=FAILED' | tee -a "$REPORT"; echo 'ERROR=build log missing' | tee -a "$REPORT"; exit 60; }

mapfile -t dupes < <(grep -F ' exported twice.' "$LOG" || true)
if (( ${#dupes[@]} == 0 )); then
  echo 'MODULE_EXPORTS=OK' | tee -a "$REPORT"
  echo 'KNOWN_WG_AWG_DUPLICATE=absent' | tee -a "$REPORT"
  echo 'UNEXPECTED=0' | tee -a "$REPORT"
  echo 'WG_AWG_MUTUAL_EXCLUSION=ENFORCED' | tee -a "$REPORT"
  exit 0
fi

known=0
unexpected=0
for line in "${dupes[@]}"; do
  if [[ "$line" == *"'ip_tunnel_get_stats64' exported twice."* ]]; then
    ((known+=1))
  else
    ((unexpected+=1))
    printf 'UNEXPECTED_LINE=%s\n' "$line" >> "$REPORT"
  fi
done

# The one known collision must be the exact WireGuard/AmneziaWG pair observed in
# the pinned EC220 build. Do not silently bless the same symbol from another module.
if (( known > 0 )); then
  grep -Fq "Previous export was in net/amneziawg/amneziawg.ko" "$LOG" || {
    echo 'MODULE_EXPORTS=FAILED' | tee -a "$REPORT"
    echo 'ERROR=known symbol collision came from unexpected module' | tee -a "$REPORT"
    exit 61
  }
fi
if (( known > 1 )); then
  echo 'MODULE_EXPORTS=FAILED' | tee -a "$REPORT"
  echo "ERROR=known WG/AWG duplicate appeared $known times" | tee -a "$REPORT"
  exit 62
fi
if (( unexpected > 0 )); then
  echo 'MODULE_EXPORTS=FAILED' | tee -a "$REPORT"
  echo "UNEXPECTED=$unexpected" | tee -a "$REPORT"
  exit 63
fi

echo 'MODULE_EXPORTS=OK' | tee -a "$REPORT"
echo 'KNOWN_WG_AWG_DUPLICATE=present' | tee -a "$REPORT"
echo 'UNEXPECTED=0' | tee -a "$REPORT"
echo 'WG_AWG_MUTUAL_EXCLUSION=ENFORCED' | tee -a "$REPORT"
