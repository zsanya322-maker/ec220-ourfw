# OURFW IPv6 policy (v0.4)

`IPV6_POLICY=block` is a no-leak guard, not selective IPv6 policy routing yet.
It activates only when `VPN_ENABLED=1` and a policy-routing mode is active.
Both forwarded LAN traffic and router-originated global IPv6 are guarded at the
head of the filter chains. Link-local, multicast/NDP, ULA and the cached IPv6
VPN transport endpoint remain allowed.

Padavan RA/DHCPv6 advertisement is intentionally not disabled in v0.4. Clients
may retain IPv6 addresses while global direct forwarding is rejected. This keeps
the mutable guard reversible without reconfiguring the base IPv6 service. Full
selective IPv6 routing/RA coordination is a later OURFW module update.
