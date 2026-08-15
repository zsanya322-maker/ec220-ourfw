# OURFW IPv6 policy v0.5

v0.5 is intentionally simple:
- `block`: while policy VPN is enabled, global client/router IPv6 cannot silently bypass an IPv4-only VPN policy; link-local/ULA/multicast and the VPN transport endpoint are excepted where needed.
- `native`: leave IPv6 to base Padavan.

RA/DHCPv6 advertisement is not disabled in `block`; clients can retain IPv6 addressing while global forwarding is rejected. Selective IPv6 domain/IP policy routing is postponed until after the first hardware test.
