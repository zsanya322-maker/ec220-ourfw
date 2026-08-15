# EC220-OURFW v0.6.0

Лёгкий модульный Padavan для TP-Link EC220-G5 v2 на проверенной базе `0e6caa2749a8814345c8a0d496a2fde2e6746a7d`.

## Три слоя

### CORE — минимально изменяемый
Padavan kernel/MT7620, flash/MTD, Ethernet/Wi-Fi, WAN/LAN, IPv6, firewall/dnsmasq, Dropbear, штатный httpd/firmware updater, HTTPS capability и минимальный OURFW loader/API bridge.

### BUILTINS — тяжёлые бинарники/модули
WireGuard/AmneziaWG, nfqws/NFQUEUE, ipset/SFE, OpenSSL, OpenVPN, SFTP server, ZRAM и curl. Они меняются полной firmware-сборкой.

### OURFW — mutable `/etc/storage/ourfw`
Smart Routing, WG/AWG/OpenVPN orchestration, runtime VPN failover, AdBlock Lite, DNS policy, nfqws profiles, ZRAM policy, InternetDetect-aware Watchdog, diagnostics, WebUI, Backup/Restore, component updater и 90-секундный rollback.

## WebUI

`/ourfw/index.asp` внутри штатной авторизации Padavan.

Вкладки:
- Состояние;
- Маршрутизация;
- VPN (WG/AWG/OpenVPN + fallback);
- DPI/nfqws;
- DNS;
- AdBlock;
- Watchdog + Padavan Internet Detect;
- Сервисы (HTTPS/SFTP/OpenVPN/ZRAM);
- Backup/Update;
- Диагностика.

Опасные изменения идут как candidate: применить -> примерно 90 секунд -> Confirm или автоматический rollback.

## AdBlock Lite

DNS-level blocking через dnsmasq без тяжёлого постоянно работающего AdGuard Home. HTTPS subscriptions + allow/deny. Большая сгенерированная база живёт в `/tmp`; в flash хранится только конфигурация/маленькие списки.

## VPN

Один policy engine для WireGuard, AmneziaWG и OpenVPN. Smart Routing следует за активным интерфейсом (`wg0`/`tun0`). OpenVPN profile ограничен безопасным single-file режимом: OURFW не разрешает произвольные shell hooks/plugins/management и игнорирует pushed routes/redirect-gateway.

Failover — runtime override primary/fallback. Он не переписывает основной persistent VPN config. Автоматическое переключение выполняет Watchdog, поэтому для автоматического failover Watchdog должен быть включён.

## ZRAM

Off / Auto(25%) / 25% / 50%; алгоритм Auto/LZ4/LZO. Политика mutable, kernel support — BUILTIN.

## Flash

Разметка не меняется. Firmware `0x780000`; Storage `0x20000` (128 KiB). Перед каждой реальной сборкой CI проверяет размер и финальный SquashFS.

## Сборка/безопасность

CI использует exact Padavan commit и pinned toolchain SHA256, проверяет реальный ROMFS и затем снова вскрывает конечный `.bin`. Образ не считается кандидатом для железа без `ROMFS_VERIFY=OK` и `IMAGE_VERIFY=OK`.

Первая установка — TFTP recovery по LAN; последующие полные `.bin` — через Padavan WebUI. Большинство OURFW-патчей/дизайна/правил обновляются без полной перепрошивки.

См. `CHANGELOG-v0.6.0.md` и `BUILD-READY-v0.6.0.md`.
