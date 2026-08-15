# v0.6.0 — OpenVPN / HTTPS / SFTP / ZRAM / AdBlock / InetDetect

База Padavan не менялась: `0e6caa2749a8814345c8a0d496a2fde2e6746a7d`.

## BUILTINS

- OpenSSL + HTTPS support для штатного Padavan httpd.
- SFTP server (`sftp-server`) вместе с существующим Dropbear SSH/SCP.
- OpenVPN client binary/crypto.
- ZRAM kernel support.
- curl для HTTPS-подписок AdBlock Lite.
- Сохранены WG/AWG, nfqws/NFQUEUE, ipset, SFE/HW NAT, IPv6.

## OURFW mutable

- OpenVPN orchestration без штатного Padavan policy routing: `tun0`, `route-noexec`, запрет script/plugin/management directives, single-file inline cert profile.
- Общий VPN engine: WireGuard / AmneziaWG / OpenVPN.
- Runtime failover primary <-> fallback, управляемый Watchdog без записи override во flash.
- Smart Routing и kill-switch автоматически следуют за активным `wg0`/`tun0`.
- AdBlock Lite на dnsmasq: HTTPS blocklists, allow/deny, лимит доменов, runtime list только в RAM.
- ZRAM manager: Off / Auto(25%) / 25% / 50%; LZ4/LZO auto.
- Padavan Internet Detect hook -> OURFW Watchdog и ранний rollback pending-конфигурации.
- WebUI: вкладки AdBlock и Сервисы, OpenVPN profile/auth, failover, ZRAM, Internet Detect.
- Backup/rollback/update/CSRF/chunk-upload модель v0.5 сохранена.

## Safety

- OpenVPN не принимает external file directives и команды/плагины/hooks из загружаемого профиля.
- OpenVPN transport endpoint исключается из policy-VPN, включая несколько `remote` строк.
- OpenVPN pushed routes/redirect-gateway не получают контроль над маршрутами OURFW.
- AdBlock принимает только HTTPS sources, ограничивает каждый download 2 MiB и размер итоговой базы.
- Большой AdBlock dnsmasq-файл не пишется в 128 KiB flash Storage.
- Watchdog по умолчанию выключен; reboot остаётся opt-in.
- ZRAM использует переносимый BusyBox `swapon -p`, без необязательного discard-флага.

## Не включено намеренно

StrongSwan/IPsec, Tor, Privoxy, DNSCrypt, Stubby/DoH, Lua, xUPNPd, Socat, CAKE/FQ-CoDel.
CAKE/FQ-CoDel оставлены до реальных замеров bufferbloat/CPU на EC220.
