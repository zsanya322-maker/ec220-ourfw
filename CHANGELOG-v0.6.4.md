# OURFW v0.6.4 — hardware-confirmed compatibility fixes

This release folds fixes discovered during the first EC220-G5 v2 hardware bring-up back into the firmware source.

## Fixed

- EC220 target BusyBox `ash` does not provide the POSIX `command` builtin. Target runtime no longer uses `command -v`; OURFW now resolves executables through PATH with `have_exec()`.
- Fixed false `missing tool: modprobe` / `missing tool: iptables` detections and the downstream impact on VPN, DNS, nfqws, routing, watchdog and ZRAM helpers.
- Fixed WAN/LAN interface discovery on the real target (`eth2.2` / `br0`).
- Fixed WG/AmneziaWG handoff helper so module probing does not depend on `command -v`.
- Added mutable CSRF self-heal: `ourfwctl boot` and `status-json` create a per-boot 256-bit token if the immutable loader could not create one.
- Fixed the immutable rescue loader itself: SHA256, bzcat and restart_dhcpd discovery no longer depends on `command -v`.

## Hardware validation performed on EC220-G5 v2

- Reboot persistence: hotfix survives Storage save and full reboot.
- All required executable probes return success.
- Fresh boot log has no false `missing tool` entries.
- ZRAM auto mode: 25%, LZ4, swap active.
- WireGuard load -> AmneziaWG load -> WireGuard reload succeeds with mutual exclusion.
- AmneziaWG kernel self-tests pass; no kernel Oops/BUG/Unknown symbol observed.
- CSRF token is created as 64 hex chars with mode 0600 and WebUI mutating API becomes available.

## Still under hardware investigation

The OURFW WebUI currently polls status every 15 seconds. On the single-core MT7620A this is suspected of causing short CPU/latency spikes while the OURFW page is open. This is intentionally not declared fixed until the close-tab A/B hardware test confirms the correlation.

## Versioning

v0.6.4 is a compatibility/hardware-fix release. Subscription-based proxy/VPN support is a separate follow-up feature and is not silently added here.
