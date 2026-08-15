# EC220-OURFW v0.5.0 one-shot

Кастомный лёгкий Padavan для TP-Link EC220-G5 v2 на проверенной базе `0e6caa2749a8814345c8a0d496a2fde2e6746a7d`.

## Слои

### CORE — минимально изменяемый
Padavan kernel/MT7620, flash/MTD, Ethernet/Wi-Fi, базовая сеть, Dropbear SSH, штатный httpd, firmware updater, immutable OURFW loader и маленький authenticated API bridge.

### BUILTINS — тяжёлые бинарники/модули
WireGuard + `wg`, AmneziaWG + `awg`, `nfqws`/Zapret, NFQUEUE, ipset, SFE, IPv6 netfilter, BusyBox `sha256sum/base64/mount`.

### OURFW — persistent mutable `/etc/storage/ourfw`
Smart Routing, VPN orchestration, nfqws policy, DNS, Watchdog, diagnostics, WebUI, component updater, backup, 90-second rollback. Этот слой можно менять через SSH; модули и WebUI также обновляются из OURFW WebUI.

## OURFW WebUI

После установки: `/ourfw/index.asp` в той же авторизованной WebUI роутера.

Есть вкладки:
- Состояние;
- Маршрутизация;
- VPN;
- DPI / nfqws;
- DNS;
- Watchdog;
- Backup / Update;
- Диагностика.

Любая опасная настройка применяется как candidate. Если доступ пропал и изменение не подтверждено — последняя рабочая конфигурация восстанавливается примерно через 90 секунд.

## Flash layout

Разметка EC220 не меняется. Firmware partition: `0x780000`; Storage: `0x20000` (128 KiB). Mutable defaults v0.5 занимают около 28 KiB в детерминированном tar+bzip2, то есть ~21% Storage до пользовательских настроек.

## Сборка

CI всегда использует exact Padavan commit и pinned toolchain SHA256. После MIPS build выполняются:
1. проверка реального ROMFS;
2. size check против Firmware partition с 64 KiB safety margin;
3. построение `tp_recovery.bin = 128 KiB zeros + web.bin`;
4. byte-check recovery invariant;
5. разбор и проверка уже финального `.bin` встроенным SquashFS verifier.

До зелёных `ROMFS_VERIFY=OK` и `IMAGE_VERIFY=OK` образ для железа не принимается.

## Первый install и дальнейшие update

Первая установка планируется через EC220 TFTP recovery по LAN. После успешного первого запуска полноценные firmware updates можно делать через Padavan WebUI, а большую часть OURFW логики/настроек — без перепрошивки через OURFW WebUI/SSH.

См. `CHANGELOG-v0.5.0-one-shot.md` и `FIRST-CI.md`.
