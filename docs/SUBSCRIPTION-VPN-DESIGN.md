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

Therefore subscription support is split into a tiny persistent manager in OURFW and protocol engines that are loaded only when needed. No generic multi-protocol proxy core is silently embedded into flash.

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
- optional downloaded protocol binary;
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

- `hysteria2://` and `hy2://` — first protocol target;
- `vless://` with REALITY — second target after resource tests;
- existing WireGuard/OpenVPN import remains handled by the current VPN engine rather than being reimplemented inside the subscription parser.

## Hysteria2 — first protocol target, resource fit not yet accepted

Hysteria remains the best protocol match for the provider nodes and its TUN model fits OURFW well, but the stock upstream executable is **not small enough to assume safe on this 64 MiB router**.

Upstream publishes `linux/mipsle` and a dedicated `linux/mipsle-sf` soft-float build. The latter matches the CPU/ABI class we need (`GOMIPS=softfloat`). However the real uncompressed official executable sizes are large and have grown over time:

- v2.8.0 `hysteria-linux-mipsle-sf`: 17,629,399 bytes;
- v2.8.2: 21,954,753 bytes;
- v2.12.1: 24,707,265 bytes (~23.6 MiB), SHA256 `8ca17e22f028fcd25384d4259e25254349131c096a87233078b00640afd33dd4`.

The old ~5.5 MiB observation was a compressed CI artifact size, not the current executable size. Upstream's normal release build already uses `-trimpath` and linker flags `-s -w`, so ordinary stripping will not solve the problem.

On this router `/tmp` is RAM-backed. A ~24 MiB executable stored there consumes a major fraction of physical RAM before accounting for process RSS, packet buffers, dnsmasq, Wi-Fi drivers, httpd and OURFW itself. Therefore we do **not** download/run the stock current Hysteria binary on the EC220 yet.

### Preferred next research: client-only Hysteria build

Before hardware execution, determine whether we can build a reproducible minimal client executable from pinned upstream packages that excludes server-only features, Realms, certificate/server commands and unrelated CLI surfaces.

Acceptance target for considering a hardware smoke test:

- MIPSLE soft-float;
- reproducible pinned source/toolchain;
- only client/TUN/config functionality needed by OURFW;
- materially smaller than stock upstream binary, with a practical target around <= 8-12 MiB;
- expected SHA256 produced by CI;
- no writable persistent binary cache.

If a client-only build cannot get comfortably below the resource budget, Hysteria remains unsupported on-router rather than consuming unsafe RAM.

### Binary lifecycle if a safe client build is achieved

- Do not embed it in the 8 MiB firmware image.
- Do not persist it in Storage.
- Download a pinned verified binary only when a Hysteria node is selected.
- Store it under `/tmp/ourfw/bin/` only after checking available RAM.
- Verify expected size and SHA256 before chmod/start.
- If verification fails, delete it and keep current routing untouched.
- WG/AWG/OpenVPN operation must never depend on this download.
- Keep at most one extra proxy engine binary resident in `/tmp`.

### TUN ownership model

Hysteria2 has native Linux TUN support. For EC220 we deliberately do **not** let Hysteria own global routing.

Desired config:

- TUN name: `hy0`;
- private /30 IPv4 address not overlapping LAN;
- IPv6 disabled initially for the engine;
- omit Hysteria route fields so it creates the TUN but does not install default routes;
- OURFW owns `ip rule`, routing tables, iptables marks, kill-switch and DNS policy.

This is especially important on Linux 3.4.113: OURFW-managed routes avoid depending on modern automatic-route behaviour.

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
- optional UDP probe when implemented;
- DNS policy still resolves through the intended path.

Failover requires several consecutive failures, not one packet loss.

## VLESS + REALITY — secondary engine

Two realistic upstream families exist, but both are also heavy for this router.

### Xray

Pros:

- official project supports VLESS/REALITY;
- Linux MIPS/MIPSLE is a supported release target;
- current Xray has a TUN inbound designed so the OS can own addresses/routes/rules, which maps cleanly to OURFW.

Risks:

- large binaries/resource use;
- a 2026 official issue reports a recent MIPS soft-float build crashing while an older build worked on a router-class MIPS system;
- therefore `latest` must never be downloaded blindly. Any Xray version is pinned only after EC220 ABI/startup/RAM testing.

### sing-box

Pros:

- current upstream CI explicitly builds Linux MIPSLE soft-float, including MIPS 24K-class targets;
- supports subscription-relevant protocols in one engine.

Risks:

- current MIPSLE artifacts are also large (roughly the high-teens to 20+ MiB class);
- that is too expensive to assume safe in `/tmp` on a 64 MiB router before measuring executable storage plus process RSS under traffic.

### Decision for now

Do not integrate stock Hysteria, generic sing-box or Xray into the router yet. Implement the **subscription manager/parser independently of protocol engines first**, then investigate a minimal client-only Hysteria build. If that passes the size gate, qualify it on hardware and only then connect it to Smart Routing. VLESS/REALITY comes after we know the remaining RAM/CPU budget.

This separation is intentional: the router can already understand and display a subscription, classify nodes and mark unsupported engines without risking WAN/routing stability.

## `Hysteria2 WARP` provider labels

Treat `WARP`, `Direct`, country names and similar text as node labels only.

If the actual URI scheme is `hysteria2://`/`hy2://`, OURFW needs only a Hysteria-compatible client. Whether the provider server then exits through WARP is server-side behaviour and does not require Cloudflare WARP on the router.

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
- engine state: unsupported / absent / downloaded / hash OK / running;
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

Primary/fallback can mix existing and future subscription engines, for example:

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

## Hardware acceptance gates for a Hysteria client

Before exposing Hysteria as `supported` in normal WebUI:

- client binary passes size/RAM preflight before execution;
- execute the pinned MIPSLE soft-float build successfully on the real EC220;
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

Only after that is Hysteria promoted from `experimental/unsupported` to normal support.

## Implementation order

1. subscription config + secret handling + parser;
2. node list/status API with **no routing changes**;
3. WebUI subscription block and import/update flow;
4. research/build a minimal pinned Hysteria client and enforce size/hash gates;
5. hardware ABI/RAM smoke test without routing changes;
6. Hysteria start/stop + `hy0` without policy routing;
7. `hy0` integration into Smart Routing;
8. DNS/kill-switch/watchdog integration;
9. primary/fallback node switching;
10. full hardware qualification;
11. only then investigate VLESS/REALITY engine integration.
