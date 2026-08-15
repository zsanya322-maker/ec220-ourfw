# OURFW v0.6.4 — hardware-confirmed compatibility fixes

This release folds fixes discovered during the first EC220-G5 v2 hardware bring-up back into the firmware source.

## Fixed

- EC220 target BusyBox `ash` does not provide the POSIX `command` builtin. Target runtime no longer uses `command -v`; OURFW now resolves executables through PATH with `have_exec()`.
- Fixed false `missing tool: modprobe` / `missing tool: iptables` detections and the downstream impact on VPN, DNS, nfqws, routing, watchdog and ZRAM helpers.
- Fixed WAN/LAN interface discovery on the real target (`eth2.2` / `br0`).
- Fixed WG/AmneziaWG handoff helper so module probing does not depend on `command -v`.
- Added mutable CSRF self-heal: `ourfwctl boot` and `status-json` create a per-boot 256-bit token if the immutable loader could not create one.
- Fixed the immutable rescue loader itself: SHA256, bzcat and restart_dhcpd discovery no longer depends on `command -v`.
- Removed the automatic 15-second OURFW WebUI status polling after hardware A/B confirmed that it caused recurring CPU spikes and elevated local ping to `192.168.1.1` while the page was open. The production payload now refreshes once on page load, after actions, on explicit Refresh, and when a hidden browser tab becomes visible again.

## Hardware validation performed on EC220-G5 v2

- Reboot persistence: hotfix survives Storage save and full reboot.
- All required executable probes return success.
- Fresh boot log has no false `missing tool` entries.
- ZRAM auto mode: 25%, LZ4, swap active.
- WireGuard load -> AmneziaWG load -> WireGuard reload succeeds with mutual exclusion.
- AmneziaWG kernel self-tests pass; no kernel Oops/BUG/Unknown symbol observed.
- CSRF token is created as 64 hex chars with mode 0600 and WebUI mutating API becomes available.
- WebUI close/open A/B: recurring router CPU/local-latency spikes disappear when OURFW is closed and return while its 15-second status poll is active; periodic polling is therefore disabled in v0.6.4 payload generation.

## Versioning

v0.6.4 is a compatibility/hardware-fix release. Subscription-based proxy/VPN support is a separate follow-up feature and is not silently added here.
