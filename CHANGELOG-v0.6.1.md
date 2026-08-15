# v0.6.1 — WG/AWG handoff + mutable firmware refresh + CI export gate

Hotfix после независимого аудита реального v0.6.0 MIPS artifact.

## Исправлено

- WireGuard и AmneziaWG kernel modules теперь считаются взаимоисключающими: перед загрузкой одного OURFW гарантированно выгружает другой и проверяет состояние `/proc/modules`.
- Если конфликтующий модуль не удалось выгрузить, переключение завершается fail-closed вместо попытки загрузить второй модуль поверх первого.
- VPN cleanup удаляет фактический ранее активный интерфейс и текущий `VPN_INTERFACE`, а не только жёстко заданный `wg0`.
- Immutable loader теперь сравнивает VERSION firmware defaults с mutable `/etc/storage/ourfw` и при обновлении пересеивает код из firmware, сохраняя пользовательские `config/`, `profiles/`, `rules/`.
- При ошибке refresh loader возвращает старое mutable дерево; базовый Padavan продолжает загрузку.

## Новые проверки

- Динамический WG -> AWG -> WG module-handoff mock с эмуляцией duplicate-symbol поведения Linux 3.4.
- Fail-closed test, когда удаление конфликтующего kernel module запрещено.
- Loader upgrade mock `v0.6.0 -> v0.6.1` с проверкой сохранения config/profile/rules и появления новых runtime files.
- Real-MIPS build log scanner: любые новые `exported twice` ломают CI; известный конфликт `ip_tunnel_get_stats64` WireGuard/AmneziaWG разрешается только вместе с runtime mutual-exclusion guard.
- Отдельная финальная проверка mutable payload внутри SquashFS `.bin`: VERSION, module-handoff и firmware-refresh loader.

База Padavan остаётся pinned: `0e6caa2749a8814345c8a0d496a2fde2e6746a7d`.
