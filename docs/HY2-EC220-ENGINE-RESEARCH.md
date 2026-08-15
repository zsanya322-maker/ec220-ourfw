# EC220 Hysteria2 engine research

Status: research only. No router binary is produced or executed by v0.6.4.

## Baseline fact

The current upstream Hysteria v2.12.1 `hysteria-linux-mipsle-sf` executable is 24,707,265 bytes and is therefore too large to treat as a routine `/tmp` dependency on a 64 MiB router without measuring both RAM-backed file cost and process RSS.

## Candidate A: TUN-only client

Advantages:

- clean interface contract for existing Smart Routing;
- no transparent-proxy packet interception rules needed;
- Hysteria can create a named interface while OURFW keeps ownership of policy routes.

Disadvantages:

- Hysteria's TUN implementation imports `sing-tun` and SagerNet common stack packages;
- likely materially larger binary/dependency graph;
- old Linux 3.4 target needs extra compatibility validation.

## Candidate B: TPROXY-only client

Advantages:

- Hysteria Linux TCP/UDP TProxy code depends on the core client plus a small `go-tproxy` layer rather than `sing-tun`;
- potentially much smaller executable;
- transparent TCP and UDP are both possible.

Disadvantages:

- exact EC220 Padavan kernel/iptables TPROXY capability is not yet proven;
- Smart Routing must own additional mangle/mark/policy rules;
- interactions with HW NAT/SFE/nfqws require explicit testing.

## Exact target capability gate before choosing TPROXY

Read-only checks on the live router / built image:

- `iptables -t mangle -j TPROXY -h` extension availability;
- `/proc/net/ip_tables_targets` / module list;
- presence/absence of `xt_TPROXY.ko` and socket match modules;
- IP rule/table support already known from OURFW, but TPROXY-specific mark routing must be tested independently;
- no persistent changes during this capability probe.

If TPROXY support is absent, do not add kernel features just for Hysteria until firmware-size impact is measured.

## Minimal client feature matrix

Required for first provider test:

- Linux MIPSLE softfloat;
- Hysteria core client;
- direct UDP transport;
- auth;
- TLS + SNI + optional insecure/cert pin as present in provider URI;
- reconnect;
- TCP and UDP transparent transport using the selected backend;
- Salamander obfs only if real provider nodes require it;
- port hopping only if real provider nodes require it.

Explicitly exclude initially:

- server mode;
- Cobra/Viper UI;
- self-update;
- cert/ACME;
- Realms/STUN/NAT-PMP/UPnP;
- Mimic/XDP;
- QR/share command;
- speed test;
- SOCKS5 and HTTP proxy listeners;
- TCP/UDP forwarding modes;
- redirect mode;
- unused obfuscators;
- both TUN and TPROXY in the same binary.

## Reproducible build matrix

Produce two experimental artifacts in CI, never inside firmware:

- `hy2-ec220-tproxy-mipsle-sf`
- `hy2-ec220-tun-mipsle-sf`

Environment:

```text
GOOS=linux
GOARCH=mipsle
GOMIPS=softfloat
CGO_ENABLED=0
```

Build with pinned upstream source and `-trimpath -ldflags='-s -w'`.

For every artifact record:

- upstream commit;
- Go version;
- module graph lock/checksums;
- byte size;
- SHA256;
- ELF architecture from an independent verifier.

## Promotion gates

Do not copy an engine to the router unless:

1. binary size is within the current research budget (target <= 8-12 MiB, lower preferred);
2. target backend capability is proven;
3. static artifact checks pass;
4. router has a safe free-RAM margin before download/execution.

First live test is ABI/startup only, with **no traffic interception or routing changes**.

Then measure:

- file size cost in `/tmp`;
- process RSS/VSZ;
- idle CPU;
- local ping to `192.168.1.1`;
- stability for 30 minutes;
- clean SIGTERM/kill/restart.

Only after that test a single provider node, then transparent routing, then Smart Routing integration.

## Decision rule

- If TPROXY-only is small and target capability exists: prefer it for EC220.
- If TPROXY is unavailable but TUN-only fits resource budget: use TUN.
- If neither fits with comfortable RAM/CPU margin: Hysteria remains unsupported on this router; Subscription Manager still works and reports those nodes as unsupported.
