# Subscription VPN / proxy design for EC220-G5 v2

Status: design only. Not enabled in v0.6.4.

## Goals

- Accept a provider subscription without asking the user to manually extract every node.
- Keep secret subscription URLs/tokens out of logs, diagnostics and normal status output.
- Reuse the existing OURFW Smart Routing, kill-switch, DNS policy, watchdog and rollback model.
- Avoid permanently consuming scarce 8 MB flash with large multi-protocol engines.
- Fail closed: an unsupported or malformed node must never rewrite working WAN/routing state.

## Provider shapes observed during hardware bring-up

The current provider exposes at least nodes labelled as Hysteria2 Direct, Hysteria2 WARP and a V2/Reality node. Labels alone are not trusted as protocol truth; the importer must classify the actual share URI/config.

## Phase 1 — Subscription Manager

Persistent configuration (mode 0600):

- subscription enabled flag
- provider URL or imported subscription file
- selected node IDs/names
- refresh interval and last-known-good selection metadata

Runtime only under `/tmp/ourfw/subscription/`:

- downloaded raw subscription
- decoded node list
- generated client configs
- optional protocol executable
- health/status files

Rules:

1. Fetch with the existing curl capability over HTTPS.
2. Never print the complete URL, credentials, UUIDs, passwords, keys or share URIs to syslog/diagnostics.
3. Accept common plain-text and base64 newline subscription payloads.
4. Parse schemes explicitly; unknown schemes are shown as unsupported rather than guessed.
5. Stable node ID = hash of normalized non-secret metadata, not the raw secret URI.
6. New subscription data is staged as a candidate. Existing working node remains active until parsing and health checks succeed.

## Phase 2 — Hysteria2 first

Hysteria2 is the first additional engine to investigate because it directly matches two observed provider nodes and upstream supplies Linux MIPS little-endian builds.

Architecture:

- protocol engine is downloaded after WAN is up into `/tmp/ourfw/bin/` from a pinned version/asset with an expected SHA256;
- no engine binary is written to firmware or Storage by default;
- generated Hysteria config is mode 0600;
- use a TUN interface, but OURFW owns routes/rules/kill-switch instead of delegating global auto-routing to the client;
- cache the real server endpoint and force that endpoint through native WAN to prevent tunnel recursion;
- Smart Routing marks traffic exactly as it does for wg0/tun0 today;
- watchdog checks process, TUN interface and transport reachability separately;
- startup failure restores the previous working routing state.

Before implementation we must hardware-test the correct MIPS ABI variant, RAM cost, idle CPU, throughput and reconnect behaviour on Linux 3.4.113.

`Hysteria2 WARP` should be treated as a provider node name until the actual share URI is parsed. If its client scheme is still `hysteria2://`, WARP is server-side egress detail and needs no separate router protocol.

## Phase 3 — VLESS + REALITY

Do not embed a full generic sing-box build into the 8 MB firmware image.

Investigate, in this order:

1. a minimal/stripped MIPS build containing only the required VLESS/REALITY/TUN feature set;
2. a smaller maintained client with the exact required protocol set;
3. runtime download to `/tmp` if RAM/storage and ABI tests pass.

If no implementation fits the EC220 resource envelope with margin, mark VLESS/REALITY unsupported on-router rather than compromising recovery headroom or stability.

## UI proposal

Add a `Подписка` block to VPN Engine:

- URL / import file
- `Обновить подписку`
- protocol filter
- node list with protocol, label and health only (no secrets)
- selected primary node
- optional fallback node
- refresh interval
- `Проверить без переключения`
- `Применить как кандидат`

The existing ~90 second rollback/confirm workflow remains mandatory for any routing-changing apply.

## Acceptance gates

A new engine is not promoted to normal firmware until all of these pass on real EC220 hardware:

- boot/reboot persistence of settings without persisting runtime secrets;
- WAN remains reachable if the engine fails to start;
- local WebUI/SSH remain reachable;
- endpoint recursion prevention;
- DNS and IPv6 no-leak tests;
- Smart/VPN-all/direct policies;
- process kill and network-loss recovery;
- sustained CPU/RAM/temperature/latency measurements;
- firmware and Storage budget checks;
- TFTP recovery image remains independently verifiable.
