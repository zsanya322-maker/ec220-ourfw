# EC220 OURFW v0.6.2 — pre-CI audit state

Target: TP-Link EC220-G5 v2. Padavan source remains pinned to `0e6caa2749a8814345c8a0d496a2fde2e6746a7d`.

Before real MIPS CI, v0.6.2 adds fail-closed network-policy fault injection, watchdog liveness regressions, firmware-refresh rollback-on-preflight/save-failure tests and a conservative 64 KiB OURFW Storage cap.

Independent host-side checks performed before commit:
- Smart Routing normal policy mock: OK.
- Critical-rule fault injection (IPv4 kill, IPv6 reject, ip rule, PREROUTING jump, ipset add): all rejected with non-zero status and cleanup.
- Watchdog missing-gateway / PPP default / OpenVPN target / future InetDetect cases: OK.
- Loader broken-candidate and Storage-save refusal rollback: OK.
- WG/AWG handoff compatibility: OK.
- Router-side modified shell syntax: OK.
- v0.6.2 payload compressed size is below the new 64 KiB own-layer cap.

A green source-side suite is not enough for flashing. Require real MIPS CI, MODULE_EXPORTS=OK, ROMFS_VERIFY=OK, IMAGE_VERIFY=OK, PAYLOAD_VERIFY=OK, then independently audit the produced artifact again.
