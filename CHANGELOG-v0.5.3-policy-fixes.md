# v0.5.3 policy fixes

- VPN peer DNS IPv4 is force-marked into the VPN before private/direct exclusions.
- IPv6 peer DNS is skipped until selective IPv6 routing exists, preventing accidental direct use.
- Watchdog is disabled by default on first boot; user enables it after observing the ISP.
- When watchdog is enabled and connectivity fails during a pending config/component transaction, it rolls back the candidate immediately; the existing 90-second independent guard remains.
- The three known Padavan optional-input build warnings are documented as harmless and intentionally left upstream-unchanged before first hardware boot.
