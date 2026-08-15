# OURFW v0.7 — Subscription Manager architecture

Status: design/implementation contract. Must not change v0.6.4 routing behaviour.

## Why this is a separate layer

A provider subscription is untrusted input and can disappear, expire, change format or contain unsupported nodes. It must never sit on the critical path of an already working WireGuard/AmneziaWG/OpenVPN configuration.

The manager therefore has three jobs only:

1. acquire a provider feed;
2. parse it into sanitized node records;
3. materialize one selected node as a candidate configuration for a protocol engine.

It does not own global routes, iptables, DNS or kill-switch. The existing OURFW VPN/Smart Routing layers remain the only owners of those policies.

## Module boundary

Proposed files:

- `ourfw/modules/subscription/api.sh` — narrow UI/API dispatcher;
- `ourfw/modules/subscription/apply.sh` — persistent manager settings only;
- `ourfw/modules/subscription/fetch.sh` — size-limited HTTPS acquisition;
- `ourfw/modules/subscription/parse.sh` — wrapper around the strict parser utility;
- `ourfw/modules/subscription/materialize.sh` — create one engine candidate under `/tmp`;
- `ourfw/modules/subscription/health.sh` — manager state, never tunnel health;
- `ourfw/config/subscription.conf` — non-secret manager policy;
- `ourfw/profiles/subscription.secret` — source URL/token and selected secret node data, mode 0600;
- `ourfw/rules/subscription.allow-hosts` — optional explicit fetch-host allow list;

The protocol engine remains under `modules/vpn` initially. If Hysteria/VLESS support grows, engines can later move to `modules/engines/<name>` without changing the subscription format.

## Persistent versus volatile data

Persist only what is needed to recover after reboot:

- provider source URL/import mode;
- update policy;
- selected primary/fallback stable IDs;
- selected node's last-known-good secret material;
- last-known-good non-secret metadata;
- pinned engine version/hash policy.

Do **not** persist the whole provider response or every node's credentials.

Volatile `/tmp/ourfw/subscription/`:

- `raw.feed` — mode 0600;
- `nodes.meta` — sanitized, no credentials;
- `nodes.secret/` — per-session mode 0600 records;
- `candidate/` — generated config for one selected engine;
- `fetch.status`, `parse.status`, `probe.status`;
- optional engine binary under `/tmp/ourfw/bin/` after resource checks.

## Fetch contract

The fetcher must:

- use HTTPS by default;
- use existing CA bundle verification;
- have connect and total timeouts;
- enforce an explicit maximum response size before parsing;
- refuse redirects to unsupported schemes;
- write to a temporary mode-0600 file and atomically rename only after success;
- never put the complete source URL into argv-visible logs, syslog, diagnostics or normal status JSON;
- keep the previous last-known-good selection when refresh fails.

Recommended initial limits:

- raw feed <= 512 KiB;
- <= 512 nodes;
- decoded individual share URI <= 8 KiB;
- display label <= 160 UTF-8 bytes after sanitization.

These are abuse/resource limits, not protocol limits, and can be adjusted after observing the real provider.

## Parser contract

Do not `source`, `eval`, shell-expand or execute subscription content.

Because BusyBox shell is a poor and fragile URI parser, the long-term implementation should use a tiny purpose-built parser utility (preferably C) and let shell only orchestrate files/processes.

Parser input forms for phase 1:

1. plain newline-separated share URIs;
2. one outer base64 payload that decodes to newline-separated URIs.

Do not add Clash YAML / sing-box JSON until a real provider feed requires them.

Recognized schemes in phase 1:

- `hysteria2://`, `hy2://`;
- `vless://` (metadata/import only initially);
- `wireguard://` only if the real provider uses a defined share form;
- OpenVPN only as an explicit imported `.ovpn`, not guessed from a text subscription.

Unknown schemes become `unsupported` records; they are never silently coerced.

## Internal node record

Public metadata record (safe for UI):

```text
id=<stable opaque id>
protocol=hysteria2|vless|wireguard|openvpn|unsupported
label=<sanitized label>
host=<hostname or redacted endpoint class>
port=<number>
transport=udp|tcp|unknown
engine=hysteria|xray|singbox|native|none
support=ready|experimental|unsupported
flags=...
```

Secret record, mode 0600 and never returned by normal status:

```text
id=...
raw_scheme=...
auth=...
sni=...
obfs_type=...
obfs_secret=...
uuid=...
public_key=...
short_id=...
flow=...
```

Actual fields vary by protocol. Missing/unknown fields are preserved as unsupported metadata rather than shell text.

Stable IDs must not hash the raw secret URI directly into something reusable as a credential oracle. Use normalized non-secret identity plus an installation-local random salt.

## Materialization contract

`materialize <node-id>` is read-only with respect to current networking.

It may only:

- resolve the selected session secret record;
- generate `/tmp/ourfw/subscription/candidate/*` mode 0600;
- report required engine and features;
- reject unsupported combinations;
- produce a redacted candidate summary.

A separate explicit VPN candidate-apply transaction is required before routes or firewall change.

## Probe without switching

`Проверить без переключения` should be possible where the engine supports it.

The probe must not install default routes or alter Smart Routing. It can:

- resolve the server using native WAN;
- validate TLS/config syntax;
- establish a short engine handshake in an isolated mode;
- report elapsed time and a coarse health result;
- terminate the test process and delete temporary secrets.

Do not present ICMP ping as "VPN latency" when the protocol server does not answer ICMP.

## Routing ownership

Subscription Manager: no routes.

Protocol engine adapter:

- process lifecycle;
- tunnel/TProxy listener lifecycle;
- endpoint information;
- engine-specific health.

Smart Routing:

- policy marks;
- policy routing tables;
- iptables/ip6tables;
- DIRECT endpoint exceptions;
- kill-switch;
- IPv6 no-leak policy.

DNS module:

- peer/provider DNS policy;
- fail-closed resolver changes.

This keeps the existing rollback model usable for every future engine.

## Refresh behaviour

Default: manual.

Optional automatic refresh: once every 24 hours, with random jitter after WAN is established. Never tie it to WebUI refresh and never run it every few minutes.

A successful feed refresh may change the displayed node list but **must not** silently replace the active node. If the active node disappears, keep the persisted last-known-good selected config and show `removed by provider / still active locally` until the user or failover policy chooses another candidate.

## Secrets and diagnostics

Redact by construction, not by post-processing.

Normal status/API may expose:

- provider hostname only, optionally masked;
- last refresh time/result;
- number of nodes;
- selected node ID/label/protocol;
- engine compatibility;
- health category.

Never expose:

- full subscription URL/query/token;
- raw share URIs;
- passwords/auth strings;
- UUIDs;
- private/public REALITY credential material if it identifies the account;
- WireGuard private keys;
- generated engine config files.

Diagnostics export gets only sanitized metadata and explicit error categories.

## v0.7 phases

### v0.7a — parser/manager only

- config + secret storage;
- fetch/import;
- parser;
- sanitized node table;
- no new proxy binary;
- no routing changes.

### v0.7b — experimental Hysteria adapter

Only after a small MIPSLE-softfloat client build and target capability checks pass.

### v0.7c — Smart Routing integration

Only after process/RAM/CPU/endpoint-recursion tests are green.

### v0.7d — failover

Primary/fallback across qualified engines.

VLESS/REALITY remains metadata-only until an engine is separately qualified on EC220.

## Non-negotiable regression gates

- malformed feed cannot crash controller or corrupt Storage;
- parser never executes input;
- secrets never appear in status/diagnostics/logs;
- failed refresh preserves last-known-good config;
- parser/manager can be disabled/removed without touching native WAN;
- v0.6.4 WG/AWG/OpenVPN behaviour is byte/logic compatible unless deliberately changed;
- no periodic WebUI/background polling regression;
- Storage and firmware budgets remain enforced.
