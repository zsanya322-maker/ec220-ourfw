# Архитектура OURFW v0.6

## CORE
Минимальный boot/network/recovery foundation: pinned Padavan kernel/MT7620, drivers, MTD, base network, dnsmasq/firewall, Dropbear, httpd/firmware update, HTTPS capability, immutable loader + authenticated OURFW API bridge.

## BUILTINS
То, что должно жить в firmware/rootfs: WG/AWG, nfqws/NFQUEUE, ipset/SFE, OpenSSL, OpenVPN, SFTP server, ZRAM kernel support, curl и необходимые IPv6/netfilter helpers.

## OURFW mutable
`/etc/storage/ourfw`: runtime controller, Smart Routing, WG/AWG/OpenVPN orchestration, runtime VPN failover, DNS, AdBlock Lite, nfqws, ZRAM policy, InternetDetect-aware Watchdog, diagnostics, rules/profiles/configs, WebUI, Backup/Restore и component updater.

### Update model
- config: stage -> validate -> candidate -> apply -> 90 s confirm/rollback;
- module/WebUI: SHA256 -> safe archive -> overlay -> health/apply -> 90 s confirm/rollback;
- full CORE/BUILTINS: normal firmware `.bin` update.

### VPN ownership
Native Padavan VPN-client routing is disabled in RAM while OURFW VPN is active. OURFW creates `wg0` or `tun0`, excludes encrypted transport endpoints from policy routing, and owns table/mark/kill-switch state. OpenVPN is run with `route-noexec` and sanitized profile input.

### AdBlock storage model
Sources/allow/deny are small persistent files. The generated dnsmasq blocklist is RAM-only and bind-mounted over a tiny persistent include target, preventing large flash writes and avoiding a missing-conf-file boot failure.

### Internet health
Padavan Internet Detect remains available and writes through a managed hook. OURFW consumes that state in Watchdog; pending config/component failures prefer rollback, while steady-state failure can attempt VPN fallback/repair.

### Web security
No generic shell endpoint. Padavan authentication remains in front of `/ourfw_api.cgi`; mutations require POST + per-boot CSRF. Payload chunks are bounded/base64url/SHA256-verified and target-whitelisted.
