# Архитектура OURFW v0.5

## CORE
Только то, что нужно для boot/network/recovery: Padavan kernel/MT7620, drivers, MTD, base network, Dropbear, httpd, firmware update, immutable loader + minimal authenticated OURFW API bridge.

## BUILTINS
Бинарники и kernel modules, которые неразумно хранить в 128 KiB Storage: WG/AWG, nfqws/NFQUEUE, ipset/SFE/IPv6 netfilter, BusyBox helpers.

## OURFW mutable
`/etc/storage/ourfw`: runtime controller, Smart Routing, VPN, DNS, nfqws, Watchdog, diagnostics, rules/profiles/configs, WebUI, backup and component updater.

### Update model
- config section: stage -> validate -> candidate -> apply -> 90 s confirm/rollback;
- module: SHA256 -> safe archive -> overlay -> health/apply -> 90 s confirm/rollback;
- WebUI: same component updater with `type=webui`, bind-remount, rollback on no confirm;
- full CORE/BUILTINS: normal firmware `.bin` update.

### Web security
No generic shell endpoint. Padavan authentication remains in front of `/ourfw_api.cgi`; mutations require POST+per-boot CSRF. Payload chunks are base64url, bounded, SHA256-verified and target-whitelisted.
