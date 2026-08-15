# Subscription VPN / proxy design for EC220-G5 v2

Status: implementation plan. Not enabled in v0.6.4.

## Hardware constraints that drive the design

Observed target:

- MediaTek MT7620A, single-core MIPS32 little-endian;
- Linux 3.4.113;
- 64 MiB RAM;
- 8 MiB flash;
- firmware partition headroom is much smaller than modern proxy binaries;
- Storage is intentionally kept small and must not become a binary cache.

Therefore subscription support is split into a tiny persistent manager in OURFW and protocol engines that are loaded only when needed. No generic 15-25 MiB proxy core is silently embedded into flash.

## Goals

- Accept a provider subscription without asking the user to manually extract every node.
- Keep secret subscription URLs/tokens out of logs, diagnostics and normal status output.
- Reuse the existing OURFW Smart Routing, kill-switch, DNS policy, watchdog and rollback model.
- Preserve native WAN, WebUI and SSH if a subscription or engine is broken.
- Prefer one active extra engine at a time to protect RAM and CPU.
- Fail closed: an unsupported or malformed node must never rewrite working WAN/routing state.

## Subscription Manager

Persistent data under `/etc/storage/ourfw/` (secret files mode 0600):

- enabled flag;
- provider URL or imported subscription file;
- refresh policy;
- selected primary/fallback node IDs;
- last-known-good node metadata;
- pinned engine version + expected SHA256 metadata.

Runtime only under `/tmp/ourfw/subscription/`:

- downloaded raw subscription;
- decoded node list;
- generated engine configs;
- downloaded protocol binary;
- endpoint cache;
- health/status files.

The raw subscription and generated configs are never included in diagnostics.

### Import pipeline

1. Fetch HTTPS with existing `curl`, or accept an uploaded file.
2. Cap response size before parsing.
3. Detect plain newline share links vs base64-wrapped newline payload.
4. Parse each URI by scheme; do not infer protocol from display names.
5. Normalize non-secret metadata and create a stable node ID.
6. Keep unsupported schemes visible but inert.
7. Stage the parsed result; do not touch current routing yet.
8. Allow `Проверить без переключения` for an individual node.
9. Only a healthy candidate can enter the normal OURFW apply/rollback transaction.

Initial URI schemes:

- `hysteria2://` and `hy2://` — implementation target #1;
- `vless://` with REALITY — implementation target #2 after resource tests;
- existing WireGuard/OpenVPN import remains handled by the current VPN engine rather than being reimplemented inside the subscription parser.

## Hysteria2 — primary new engine

This is now the preferred first implementation.

Upstream publishes both `linux/mipsle` and a dedicated `linux/mipsle-sf` soft-float build. The soft-float little-endian variant is the first binary to test on MT7620A. Recent upstream CI artifacts are about 5.5 MiB for this architecture, which is dramatically more realistic for a 64 MiB router than sing-box/Xray class binaries.

### Binary lifecycle

- Do not embed Hysteria in the 8 MiB firmware image.
- Do not persist it in Storage.
- Download a pinned `hysteria-linux-mipsle-sf` after WAN is available to `/tmp/ourfw/bin/hysteria`.
- Verify an expected SHA256 before chmod/start.
- If verification fails, delete it and keep current routing untouched.
- Only download it when a Hysteria node is selected; WG/AWG/OpenVPN operation must not depend on this download.
- Keep at most one extra proxy engine binary resident in `/tmp`.

A future optimisation may use a smaller self-built pinned Hysteria binary, but only if its source/toolchain is reproducible and it passes the same hardware tests.

### TUN ownership model

Hysteria2 has native Linux TUN support. For EC220 we deliberately do **not** let Hysteria own global routing.

Desired config:

- TUN name: `hy0`;
- private /30 IPv4 address not overlapping LAN;
- IPv6 disabled initially for the engine;
- omit Hysteria route fields so it creates the TUN but does not install default routes;
- OURFW owns `ip rule`, routing tables, iptables marks, kill-switch and DNS policy.

This is especially important on our Linux 3.4.113: upstream documents automatic-route compatibility problems on kernels before 4.17. OURFW-managed routes avoid depending on that path.

### Endpoint recursion prevention

Before enabling policy routes:

1. resolve the Hysteria server hostname through native WAN DNS;
2. cache all resolved endpoint IPs;
3. install explicit native-WAN routes for those endpoint IPs;
4. start Hysteria and wait for `hy0` + process health;
5. only then enable Smart Routing marks toward `hy0`.

If the provider rotates the endpoint IP, refresh the native-WAN exception before changing policy routes.

### Smart Routing integration

The Smart Routing UI should not care whether the selected tunnel is `wg0`, AWG, OpenVPN `tun0` or Hysteria `hy0`.

Add an engine abstraction returning:

- engine type;
- tunnel interface;
- endpoint IP set that must stay DIRECT;
- process/handshake health;
- peer DNS if applicable;
- start/stop/reload callbacks.

Existing policies remain:

- DIRECT;
- selected domains/IPs through VPN;
- all traffic through VPN;
- kill-switch;
- IPv6 block/no-leak policy.

### Hysteria health

Do not treat `process exists` as healthy. Check separately:

- binary hash accepted;
- process alive;
- `hy0` exists and is UP;
- expected TUN address present;
- server endpoint still has a native-WAN route;
- one TCP/HTTPS probe through the tunnel succeeds;
- optional UDP probe when we implement it;
- DNS policy still resolves through the intended path.

Failover requires several consecutive failures, not one packet loss.

## VLESS + REALITY — secondary engine

Two realistic upstream families exist, but both are much heavier than native Hysteria on this router.

### Xray

Pros:

- official project supports VLESS/REALITY;
- Linux MIPS/MIPSLE is a supported release target;
- current Xray also has a TUN inbound specifically designed so the OS owns addresses/routes/rules, which maps cleanly to OURFW.

Risks:

- release packages/binaries are far larger than Hysteria;
- a 2026 issue in the official repository reports a recent MIPS soft-float build crashing while an older build worked on a router-class MIPS system;
- therefore `latest` must never be downloaded blindly. Any Xray version would be pinned only after an EC220 ABI/startup/RAM test.

### sing-box

Pros:

- current upstream CI explicitly builds Linux MIPSLE soft-float, including MIPS 24K-class targets;
- supports subscription-relevant protocols in one engine.

Risks:

- observed current MIPSLE artifacts are roughly 16-24 MiB, several times Hysteria's size;
- that is too expensive to assume safe in `/tmp` on a 64 MiB router before measuring process RSS and traffic load.

### Decision for now

Do not implement generic sing-box or Xray first. Implement Hysteria2 cleanly, measure the remaining RAM/CPU budget, then test one pinned VLESS/REALITY engine on hardware. If neither fits with margin, VLESS/REALITY remains unsupported on-router and the subscription UI will mark those nodes accordingly rather than destabilising the device.

## `Hysteria2 WARP` provider labels

Treat `WARP`, `Direct`, country names and similar text as node labels only.

If the actual URI scheme is `hysteria2://`/`hy2://`, OURFW needs only Hysteria2. Whether the provider server then exits through WARP is server-side behaviour and does not require Cloudflare WARP on the router.

## UI proposal

Add a `Подписка` block to VPN Engine:

- enable/disable subscription;
- URL or imported file;
- masked URL display after save;
- `Обновить подписку`;
- last successful update time;
- node table: name, detected protocol, compatibility, health, latency/probe result;
- protocol filter;
- selected primary node;
- optional fallback node;
- `Проверить без переключения`;
- `Применить как кандидат`;
- engine binary state: absent / downloaded / hash OK / running;
- explicit resource warning for engines not yet certified on EC220.

No secret URI, UUID, auth token, password, private key or subscription URL is returned by the normal status API.

## Refresh policy

Automatic subscription refresh is intentionally conservative:

- default: manual;
- optional: once per 24 h;
- never poll every few minutes;
- refresh only when WAN is up;
- failed refresh keeps last-known-good parsed nodes;
- changed subscription never switches the active tunnel until candidate health passes.

This follows the hardware lesson from OURFW WebUI polling: periodic background work must be justified on MT7620A.

## Failover model

Primary/fallback can mix existing and subscription engines, for example:

- Hysteria2 primary -> WireGuard fallback;
- WireGuard primary -> Hysteria2 fallback;
- Hysteria2 primary -> Hysteria2 secondary node.

Failover sequence:

1. detect repeated health failure;
2. keep router management traffic DIRECT;
3. prepare candidate engine without deleting previous config;
4. validate endpoint route + tunnel health;
5. atomically switch Smart Routing target interface;
6. re-check DNS/no-leak state;
7. if validation fails, restore previous last-known-good state.

WG/AWG kernel module mutual exclusion remains a separate engine-specific rule.

## Hardware acceptance gates for Hysteria2

Before exposing Hysteria as `supported` in normal WebUI:

- execute `hysteria-linux-mipsle-sf` successfully on the real EC220;
- record ELF/ABI and startup output;
- idle RAM/RSS after 5 and 30 minutes;
- idle CPU with WebUI closed;
- local ping to router while idle;
- WAN speed at several traffic levels;
- CPU usage under TCP and UDP load;
- 10+ reconnect cycles;
- WAN cable loss/restore;
- process kill/restart;
- server DNS/IP change behaviour;
- endpoint recursion prevention;
- Smart/VPN-all/DIRECT rule tests;
- DNS leak and IPv6 leak tests;
- WebUI + SSH always remain reachable;
- watchdog recovery without reboot loop;
- one full router reboot and automatic engine redownload/start;
- free RAM remains comfortably above the safety floor;
- no kernel Oops/BUG/Unknown symbol.

Only after that do we decide whether Hysteria should be on by default, optional, or marked experimental.

## Implementation order

1. subscription parser + masked persistent config;
2. node list/status API with no routing changes;
3. Hysteria2 pinned downloader + SHA256 verifier;
4. Hysteria dry-run/start/stop without policy routing;
5. `hy0` integration into Smart Routing;
6. DNS/kill-switch/watchdog integration;
7. primary/fallback node switching;
8. hardware qualification;
9. only then investigate VLESS/REALITY engine integration.
