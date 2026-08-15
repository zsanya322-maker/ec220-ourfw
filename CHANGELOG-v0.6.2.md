# v0.6.2 — fail-closed routing/watchdog + safer firmware refresh

Второй независимый аудит реального `v0.6.1` MIPS artifact обнаружил несколько логических отказов, которые зелёный CI раньше не моделировал.

## Исправлено

- Smart Routing теперь считает установку policy-routing, kill-switch и IPv6 leak-guard атомарной критической операцией: ошибка `iptables`, `ip6tables`, `ip rule`, policy route или `ipset` завершает apply с ошибкой и запускает cleanup вместо ложного успеха.
- `vpn-ips.list` и `direct-ips.list` больше не применяются частично: невалидная сеть/ошибка `ipset add` приводит к fail-closed apply.
- Watchdog `gateway` больше не считает отсутствие default route здоровым состоянием; PPP/PPPoE-style `default dev ppp0` без `via` поддерживается через проверку живого default интерфейса.
- Для OpenVPN явный `WATCHDOG_VPN_TARGET` теперь авторитетен: живой процесс OpenVPN не маскирует мёртвый `tun0`, если target через туннель не пингуется.
- Future timestamp Padavan InetDetect больше не считается свежим состоянием.
- `WATCHDOG_FAILS=0` отклоняется.
- Firmware mutable refresh теперь выполняет shell-preflight нового дерева **до** удаления предыдущего и до подтверждения обновления.
- Если `mtd_storage.sh save` отказывается сохранять обновлённый mutable слой, loader возвращает предыдущий `/etc/storage/ourfw`.
- Storage budget OURFW ограничен собственным 64 KiB cap по умолчанию, оставляя минимум 64 KiB из 128 KiB раздела для штатных Padavan/user settings.
- Explicit DNS upstreams (включая VPN peer DNS) теперь добавляют `no-resolv`, исключая скрытый fallback dnsmasq в `/etc/resolv.conf`; невалидные VPN domains/upstreams и любой explicit IPv6 DNS отклоняются fail-closed до появления selective IPv6 VPN routing.
- Configuration rollback больше не объявляет успех, если runtime reapply старого состояния завершился ошибкой: pending сохраняется для повторной попытки guard/stale recovery.
- Component updater теперь запрещает FIFO/device/socket и другие special tar members до extraction; разрешены только обычные файлы и каталоги.

## Новые regression tests

- Fault-injection Smart Routing: IPv4 kill-switch, IPv6 reject, `ip rule`, mangle jump и `ipset add` обязаны fail-closed.
- Watchdog mock: missing gateway, PPP default route, OpenVPN dead-tunnel/live-daemon, future InetDetect timestamp.
- Loader failure mock: broken new payload and Storage-save failure обязаны вернуть старое mutable дерево.
- DNS fail-closed mock: peer DNS/custom upstream must use `no-resolv`; invalid VPN domains/peer DNS must not replace last valid generated DNS config.
- Rollback reapply mock: failed module reapply must keep pending for retry; success removes pending.
- Component-package special-file mock: FIFO inside tar must be rejected before install/pending state.
- Final SquashFS payload verifier проверяет VERSION `v0.6.2` и наличие именно новых fail-closed/rollback механизмов внутри готового `.bin`.

База Padavan и toolchain остаются pinned без изменения.
