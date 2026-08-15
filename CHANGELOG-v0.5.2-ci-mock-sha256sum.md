# v0.5.2 CI mock hotfix

This changes tests only; router firmware/runtime behavior is unchanged.

The ROMFS mock created:
  /usr/bin/sha256sum -> /usr/bin/busybox

Real Padavan creates:
  /usr/bin/sha256sum -> ../../bin/busybox

The bad mock symlink caused Static checks to fail before the real Padavan checkout.

After correction:
- ROMFS VERIFIER MOCK: OK
- MOCK INTEGRATION: OK
- AUDIT REGRESSIONS: OK
- V0.5 REGRESSIONS: OK
- RUNTIME MOCK: OK
- STATIC CHECKS: OK
