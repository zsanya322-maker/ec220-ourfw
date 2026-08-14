<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>OURFW</title>
  <link rel="stylesheet" href="/ourfw/assets/ourfw.css">
</head>
<body>
<div class="shell">
  <header><div><b>OURFW</b><span id="version">…</span></div><button class="ghost" id="refresh">Обновить</button></header>
  <nav>
    <button class="tab active" data-tab="status">Состояние</button>
    <button class="tab" data-tab="routing">Маршрутизация</button>
    <button class="tab" data-tab="vpn">VPN</button>
    <button class="tab" data-tab="nfqws">nfqws</button>
    <button class="tab" data-tab="service">Сервис</button>
  </nav>
  <main>
    <section id="status" class="view active">
      <div class="cards">
        <article><small>WAN</small><strong id="wan">—</strong></article>
        <article><small>VPN</small><strong id="vpn">—</strong></article>
        <article><small>nfqws</small><strong id="nfqws">—</strong></article>
        <article><small>Rollback</small><strong id="pending">—</strong></article>
      </div>
      <section class="panel">
        <h2>Безопасное применение</h2>
        <p>После изменения маршрутизации/VPN/nfqws OURFW ждёт подтверждения. Если доступ пропал — через 90 секунд вернётся последняя подтверждённая конфигурация.</p>
        <div class="actions"><button data-action="apply">Применить всё</button><button data-action="confirm" class="ok">Подтвердить</button><button data-action="rollback" class="warn">Откатить</button></div>
      </section>
    </section>

    <section id="routing" class="view">
      <section class="panel"><h2>Smart Routing</h2><p>Текущий режим: <b id="routing-mode">—</b></p>
        <div class="actions"><button data-module="smart-routing" data-op="smart">Smart</button><button data-module="smart-routing" data-op="vpn-all">Всё через VPN</button><button data-module="smart-routing" data-op="off" class="ghost">Выключить policy routing</button></div>
        <p class="muted">Списки доменов/IP остаются в /etc/storage/ourfw/rules и могут обновляться отдельным компонентом.</p>
      </section>
    </section>

    <section id="vpn" class="view">
      <section class="panel"><h2>WireGuard / AmneziaWG</h2><p>Профиль: <code>/etc/storage/ourfw/profiles/vpn.conf</code></p>
        <div class="actions"><button data-module="vpn" data-op="enable" class="ok">Включить</button><button data-module="vpn" data-op="disable" class="warn">Выключить</button></div>
        <p class="muted">Тип и параметры профиля меняются через mutable OURFW; kernel-модули wg/awg остаются встроенными.</p>
      </section>
    </section>

    <section id="nfqws" class="view">
      <section class="panel"><h2>Обход DPI / nfqws</h2><div class="actions"><button data-module="nfqws" data-op="enable" class="ok">Включить</button><button data-module="nfqws" data-op="disable" class="warn">Выключить</button></div>
        <p class="muted">Стратегия и списки — mutable; бинарник nfqws встроен в firmware.</p>
      </section>
    </section>

    <section id="service" class="view">
      <section class="panel"><h2>Watchdog</h2><div class="actions"><button data-module="watchdog" data-op="enable" class="ok">Включить</button><button data-module="watchdog" data-op="disable" class="warn">Выключить</button></div></section>
      <section class="panel"><h2>Диагностика</h2><div class="actions"><button data-action="diagnostics">Снять snapshot</button><button data-action="baseline" class="ghost">Обновить baseline</button></div></section>
      <section class="panel"><h2>Компоненты</h2><p>Updater уже поддерживает SHA-256, staging, health-check и откат. Загрузка пакетов из браузера будет mutable-доработкой после первой проверки на железе; через SSH updater работает без перепрошивки Core.</p></section>
    </section>

    <pre id="result">Готово.</pre>
  </main>
</div>
<script src="/ourfw/assets/ourfw.js"></script>
</body>
</html>
