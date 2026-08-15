# EC220 OURFW v0.6.0 — build-ready report

## Target

- TP-Link EC220-G5 v2
- Padavan commit: `0e6caa2749a8814345c8a0d496a2fde2e6746a7d`
- Firmware partition: `0x780000`
- CI safe max: partition minus 64 KiB
- Storage: `0x20000` = 128 KiB

## Layer state before real MIPS CI

### CORE
Pinned Padavan EC220 hardware/network base, Dropbear/httpd/updater, OURFW loader/API bridge. v0.6 additionally enables HTTPS capability in the Padavan httpd build.

### BUILTINS
WG/AWG/nfqws/NFQUEUE/SFE + OpenSSL/HTTPS/SFTP/OpenVPN/ZRAM/curl are requested in `build.config` and verified by post-build ROMFS/final-image checks. Their real presence is not claimed until the v0.6 MIPS CI artifact passes.

### OURFW
OpenVPN/failover, Smart Routing, AdBlock Lite, ZRAM manager, InetDetect-aware Watchdog, WebUI, backup/update/rollback are implemented in mutable `/etc/storage/ourfw`.

## Local pre-CI verification

Required before packaging:
- all router-side shell syntax checks;
- Python compile checks;
- mock Padavan integration twice/idempotently;
- v0.3/v0.5/v0.6 regression suites;
- ROMFS verifier mock;
- runtime mock;
- deterministic `defaults.tar.bz2`;
- Storage budget below 128 KiB.

A green source-side test suite does NOT make this a flashable firmware. First obtain a green real MIPS CI with both `ROMFS_VERIFY=OK` and `IMAGE_VERIFY=OK`, then independently audit the resulting Artifact before TFTP.
