#!/bin/sh
. /etc/storage/ourfw/runtime/ourfw-common.sh || exit 1
OUT="${1:-/tmp/ourfw-diag.txt}"
case "$OUT" in /tmp/*) ;; *) echo "diagnostic output must be /tmp" >&2; exit 2;; esac
{
  echo "=== OURFW ==="
  "$OURFW/runtime/ourfwctl.sh" status 2>&1
  echo
  echo "=== SYSTEM ==="
  date
  uname -a 2>/dev/null
  uptime 2>/dev/null
  free 2>/dev/null
  echo
  echo "=== MTD ==="
  cat /proc/mtd 2>/dev/null
  echo
  echo "=== NETWORK ==="
  ip -4 addr 2>/dev/null || ifconfig -a 2>/dev/null
  ip -4 route show table main 2>/dev/null || route -n 2>/dev/null
  echo "-- rules --"
  ip rule show 2>/dev/null
  echo "-- table 100 --"
  ip route show table 100 2>/dev/null
  echo
  echo "=== VPN ==="
  wg show 2>/dev/null || true
  awg show 2>/dev/null || true
  echo
  echo "=== IPSETS ==="
  ipset list ourfw_vpn4 2>/dev/null || true
  ipset list ourfw_direct4 2>/dev/null || true
  echo
  echo "=== OURFW IPTABLES ==="
  iptables -t mangle -S OURFW_ROUTE 2>/dev/null || true
  iptables -t filter -S OURFW_KILL 2>/dev/null || true
  echo
  echo "=== NFQWS ==="
  pidof nfqws 2>/dev/null || true
  ps 2>/dev/null | grep '[n]fqws' || true
  echo
  echo "=== STORAGE SIZE ==="
  du -ak "$OURFW" 2>/dev/null | tail -n1
  echo
  echo "=== OURFW LOG ==="
  tail -n 150 "$LOG" 2>/dev/null
  echo
  echo "=== KERNEL TAIL ==="
  dmesg 2>/dev/null | tail -n 120
} > "$OUT" 2>&1
chmod 600 "$OUT" 2>/dev/null
printf '%s\n' "$OUT"
