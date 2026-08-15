# Архитектура OURFW v0.4-audit-fixed

## CORE — минимально неизменяемый

- Linux/MT7620, MTD/flash/filesystems.
- Ethernet/switch и Wi-Fi drivers.
- init/BusyBox/NVRAM и базовый network bring-up.
- dnsmasq + необходимый netfilter/iptables/ipset.
- Dropbear SSH.
- штатный Padavan httpd + маленький фиксированный OURFW API bridge.
- `mtd_storage.sh`.
- immutable loader + fallback WebUI/defaults.
- штатный механизм firmware update.

CORE не содержит Smart Routing policy, VPN orchestration, nfqws presets, watchdog policy или основной OURFW UI.

## BUILTINS — низкоуровневые/крупные компоненты

Живут в SquashFS и меняются только полноценным firmware `.bin`:

- WireGuard kernel module + `wg`.
- AmneziaWG kernel module + `awg`.
- `nfqws`.
- SFE/netfilter/NFQUEUE kernel support.

## OURFW — mutable

`/etc/storage/ourfw`:

- `runtime/` orchestration/updater/rollback/API dispatcher;
- `config/` строгие key=value настройки;
- `modules/` Smart Routing, VPN, nfqws, DNS, watchdog, diagnostics;
- `profiles/`, `rules/`;
- `www/` mutable WebUI;
- runtime-created `history/`, `rollback/`.

### UI

SquashFS содержит fallback `/www/ourfw`. Loader делает bind mount mutable `/etc/storage/ourfw/www` на этот каталог. Если mount/OURFW сломан — остаётся базовый Padavan и встроенный fallback.

### API

`/ourfw_api.cgi` — маленький bridge внутри штатного Padavan httpd. Он валидирует короткие argv-токены и запускает **только** `/etc/storage/ourfw/runtime/ourfw-api.sh`. Сам dispatcher остаётся mutable. Arbitrary shell/API отсутствует.

## Обновления

### Конфиг

last-good snapshot -> apply -> 90 sec pending -> confirm -> `mtd_storage.sh save`; без confirm — restore + reapply.

### Компонент

SHA256 -> archive validation -> staging -> backup -> install -> health-check -> 90 sec pending; только confirm сохраняет Storage. Иначе updater возвращает старую версию.

### Полная firmware

Нужна только для CORE/BUILTINS/kernel/rootfs изменений. После первой TFTP установки — обычный Padavan web `.bin`, если первая аппаратная проверка updater проходит.

## IPv6 policy in v0.4-audit-fixed

Smart Routing itself is IPv4-first. To avoid a silent AAAA/IPv6 bypass of VPN policy, default `IPV6_POLICY=block` installs an IPv6 forwarding guard while `smart`/`vpn-all` is active: LAN IPv6 cannot leave directly outside `wg0`. `IPV6_POLICY=native` explicitly opts back into native IPv6. Full selective IPv6 policy-routing is deferred until after first hardware validation.
