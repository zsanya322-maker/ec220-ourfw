# OURFW v0.5.0 one-shot

Цель v0.5 — не делать ещё один мелкий CI-hotfix, а сразу закрыть проверку финального образа и закончить первую полезную WebUI.

## Что исправлено после v0.4.3

- `Verify built ROMFS` теперь корректно разрешает абсолютные symlink внутри target-rootfs. Поэтому `/usr/sbin/dropbear -> /usr/bin/dropbearmulti` больше не считается сломанным из-за файловой системы CI-хоста.
- После сборки проверяется не только `trunk/romfs`, но и сам готовый EC220 `.bin`: встроенный read-only SquashFS/XZ verifier проверяет CORE, BUILTINS, OURFW defaults, fallback WebUI, kernel modules, API bridge и autostart.
- В failure artifact сохраняются ROMFS/image reports, build log, images и dist.
- BusyBox `base64` включён и проверяется в ROMFS/final image.

## WebUI v0.5

- Полный редактор Smart Routing: IPv6 policy, kill-switch, VPN/DIRECT домены и IPv4/CIDR.
- Полный редактор WireGuard / AmneziaWG профиля.
- Редактор nfqws strategy + user/exclude/auto lists.
- Редактор DNS upstream.
- Редактор Watchdog.
- Backup Center: download + restore.
- Download диагностики.
- Загрузка OURFW module package через браузер.
- Отдельное обновление WebUI (`type=webui`) без полной перепрошивки.
- Все сетевые изменения идут через candidate -> 90 s confirm/rollback.

## Безопасность WebUI

- Из браузера нет generic `cmd=`/shell endpoint.
- Mutating API требует штатную авторизацию Padavan + POST + per-boot CSRF token.
- Большие данные идут короткими base64url chunks с ограничением размера и SHA-256.
- Config/list/profile payload проходят server-side whitelist/validation.
- Backup restore и component update проходят staging и transactional rollback.
- Временные копии module/WebUI rollback живут в `/tmp`, поэтому история кандидатов не съедает 128 KiB Storage.

## Что сознательно остаётся после первого железного теста

- selective IPv6 policy routing: сейчас `block` или `native`;
- multi-VPN / wg1 / failover;
- CAKE benchmarking/tuning;
- обновление transaction-core runtime через WebUI (его можно менять по SSH или полной firmware update; WebUI updater меняет модули и сам WebUI).
