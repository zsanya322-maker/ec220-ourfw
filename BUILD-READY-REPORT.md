# EC220-OURFW v0.5.0 one-shot — build-ready report

Pinned Padavan: `0e6caa2749a8814345c8a0d496a2fde2e6746a7d`.
Firmware partition: `0x780000`; CI safe max: 7,798,784 bytes.
Recovery invariant: 131,072 zero bytes + exact web image.

v0.4.3 proved that the MIPS build contains WG/AWG/nfqws/NFQUEUE/OURFW. Its red ROMFS check was a verifier false positive caused by an absolute Dropbear symlink. v0.5 fixes this and additionally verifies the final SquashFS inside the generated `.bin`.

v0.5 adds browser editors for routing/VPN/nfqws/DNS/watchdog, backup/restore, diagnostics download and transactional component/WebUI update.

Local pre-CI gates:
- mock integration;
- external-audit regressions;
- v0.5 regressions;
- POSIX/BusyBox shell syntax;
- Python compile;
- JavaScript syntax;
- deterministic defaults archive;
- Storage budget.

Local one-shot validation (final source state):
- `MOCK INTEGRATION: OK`
- `AUDIT REGRESSIONS: OK`
- `V0.5 REGRESSIONS: OK`
- `ROMFS VERIFIER MOCK: OK` (includes absolute Dropbear symlink)
- `RUNTIME MOCK: OK` (file transfer, backup validation, module candidate/rollback, rescue flag)
- BusyBox ash syntax: OK
- JavaScript syntax: OK
- workflow YAML parse: OK
- deterministic defaults: 28,014 bytes, SHA256 `1fdd1d0a5fa6420d3eddbdba1f88b885dab731be2cb4d8b49d5936cb61829569`

The remaining non-local gate is the real pinned MIPS CI build and final-image `IMAGE_VERIFY=OK`.
