# Что куда переносим

| Функция | CORE | BUILTINS | OURFW |
|---|---:|---:|---:|
| boot/kernel/MT7620 | yes | - | - |
| Ethernet/Wi-Fi drivers | yes | - | - |
| flash/MTD/NVRAM | yes | - | - |
| basic LAN/WAN | yes | - | config/overrides |
| dnsmasq binary | yes | - | DNS policy/config |
| iptables/ipset | yes | - | routing/firewall policy |
| SSH Dropbear | yes | - | SSH policy/config where safe |
| httpd + tiny API bridge | yes | - | pages/assets/dispatcher/config |
| WireGuard kernel/userspace | - | yes | profiles/orchestration |
| AmneziaWG kernel/userspace | - | yes | profiles/orchestration |
| nfqws binary | - | yes | strategies/presets/rules |
| SFE kernel support | - | yes | policy/compatibility logic |
| Smart Routing | - | - | yes |
| watchdog | tiny fallback only | - | yes |
| diagnostics | tiny emergency status | optional tools | yes |
| component updater | tiny rescue bootstrap | - | yes |
| rollback | tiny boot-safe fallback | - | yes |
| Russian OURFW UI | fallback copy/mountpoint | - | yes |
