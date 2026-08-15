# EC220 OURFW v0.6.3 — pre-CI audit state

Target: TP-Link EC220-G5 v2. Padavan source remains pinned to `0e6caa2749a8814345c8a0d496a2fde2e6746a7d`.

`v0.6.3` keeps all `v0.6.2` fail-closed routing/watchdog/DNS/rollback/updater fixes and additionally hardens the native Padavan HTTPS certificate generator from RSA-1024 default to RSA-2048 default.

Required gates before considering the image for hardware testing:
- complete existing static/runtime/fault-injection regression suite;
- HTTPS hardening idempotency mock;
- real pinned MIPS build;
- `MODULE_EXPORTS=OK`;
- `ROMFS_VERIFY=OK`;
- `IMAGE_VERIFY=OK`;
- `PAYLOAD_VERIFY=OK`;
- `HTTPS_VERIFY=OK` from the final SquashFS;
- independent artifact digest/recovery/layout/log audit.

A green CI artifact is still not proof of real-router runtime behavior. Physical EC220 validation remains required before treating the firmware as field-proven.
