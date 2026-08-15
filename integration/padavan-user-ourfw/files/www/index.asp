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
  <header>
    <div class="brand"><b>OURFW</b><span id="version">…</span></div>
    <div class="head-actions"><span id="pending-pill" class="pill hidden">Ждёт подтверждения</span><button class="ghost" id="refresh">Обновить</button></div>
  </header>
  <nav>
    <button class="tab active" data-tab="status">Состояние</button>
    <button class="tab" data-tab="routing">Маршрутизация</button>
    <button class="tab" data-tab="vpn">VPN</button>
    <button class="tab" data-tab="nfqws">DPI / nfqws</button>
    <button class="tab" data-tab="dns">DNS</button>
    <button class="tab" data-tab="watchdog">Watchdog</button>
    <button class="tab" data-tab="maintenance">Backup / Update</button>
    <button class="tab" data-tab="diagnostics">Диагностика</button>
  </nav>

  <main>
    <section id="status" class="view active">
      <div class="cards">
        <article><small>WAN</small><strong id="wan">—</strong></article>
        <article><small>VPN</small><strong id="vpn-state">—</strong></article>
        <article><small>nfqws</small><strong id="nfqws-state">—</strong></article>
        <article><small>Маршрутизация</small><strong id="routing-mode">—</strong></article>
      </div>
      <section class="panel safety">
        <h2>Безопасное применение</h2>
        <p>Любое изменение сети сначала применяется как кандидат. Если доступ к роутеру пропал и ты не подтвердил настройку — OURFW вернёт последнюю рабочую конфигурацию примерно через 90 секунд.</p>
        <div class="actions">
          <button data-action="confirm" class="ok">Подтвердить изменения</button>
          <button data-action="rollback" class="warn">Откатить сейчас</button>
          <button data-action="apply">Применить всё заново</button>
        </div>
      </section>
      <section class="panel">
        <h2>Быстрое управление</h2>
        <div class="switch-grid">
          <div><span>VPN</span><div class="actions mini"><button data-module="vpn" data-op="enable" class="ok">Вкл</button><button data-module="vpn" data-op="disable" class="warn">Выкл</button></div></div>
          <div><span>nfqws</span><div class="actions mini"><button data-module="nfqws" data-op="enable" class="ok">Вкл</button><button data-module="nfqws" data-op="disable" class="warn">Выкл</button></div></div>
          <div><span>Watchdog</span><div class="actions mini"><button data-module="watchdog" data-op="enable" class="ok">Вкл</button><button data-module="watchdog" data-op="disable" class="warn">Выкл</button></div></div>
        </div>
      </section>
    </section>

    <section id="routing" class="view" data-load="routing">
      <section class="panel">
        <h2>Smart Routing</h2>
        <div class="actions"><button data-module="smart-routing" data-op="smart">Smart</button><button data-module="smart-routing" data-op="vpn-all">Всё через VPN</button><button data-module="smart-routing" data-op="off" class="ghost">Policy routing выкл</button></div>
        <div class="form-row two">
          <label>IPv6 policy<select id="routing-ipv6"><option value="block">Block — не дать обойти VPN</option><option value="native">Native — обычный IPv6</option></select></label>
          <label class="check"><input type="checkbox" id="routing-killswitch"> Kill-switch для помеченного трафика</label>
        </div>
      </section>
      <section class="panel editor-grid">
        <label>Через VPN — домены<textarea id="vpn-domains" spellcheck="false" placeholder="youtube.com&#10;example.org"></textarea></label>
        <label>Напрямую — домены<textarea id="direct-domains" spellcheck="false" placeholder="bank.example"></textarea></label>
        <label>Через VPN — IPv4/CIDR<textarea id="vpn-ips" spellcheck="false" placeholder="203.0.113.0/24"></textarea></label>
        <label>Напрямую — IPv4/CIDR<textarea id="direct-ips" spellcheck="false" placeholder="198.51.100.10"></textarea></label>
        <div class="wide actions"><button data-save-section="routing" class="ok">Сохранить маршрутизацию</button></div>
      </section>
    </section>

    <section id="vpn" class="view" data-load="vpn">
      <section class="panel">
        <h2>WireGuard / AmneziaWG</h2>
        <div class="form-row two">
          <label>Тип<select id="vpn-type"><option value="wireguard">WireGuard</option><option value="amneziawg">AmneziaWG</option></select></label>
          <label class="check"><input type="checkbox" id="vpn-peer-dns"> Использовать DNS из VPN-профиля</label>
        </div>
        <div class="actions"><button data-module="vpn" data-op="enable" class="ok">Включить VPN</button><button data-module="vpn" data-op="disable" class="warn">Выключить VPN</button></div>
      </section>
      <section class="panel">
        <h2>Профиль</h2>
        <p class="muted">Профиль хранится в persistent OURFW. PrivateKey отображается только внутри авторизованной панели роутера.</p>
        <textarea id="vpn-profile" class="code tall" spellcheck="false" placeholder="[Interface]&#10;PrivateKey = ...&#10;Address = ...&#10;&#10;[Peer]&#10;PublicKey = ...&#10;Endpoint = ...&#10;AllowedIPs = 0.0.0.0/0"></textarea>
        <div class="actions"><button data-save-section="vpn" class="ok">Сохранить VPN</button></div>
      </section>
    </section>

    <section id="nfqws" class="view" data-load="nfqws">
      <section class="panel">
        <h2>DPI / nfqws</h2>
        <div class="form-row two">
          <label>WAN interface <input id="nfqws-wan" placeholder="пусто = авто"></label>
          <label class="check"><input type="checkbox" id="nfqws-log"> Расширенный лог</label>
        </div>
        <div class="actions"><button data-module="nfqws" data-op="enable" class="ok">Включить nfqws</button><button data-module="nfqws" data-op="disable" class="warn">Выключить nfqws</button></div>
      </section>
      <section class="panel">
        <label>Стратегия nfqws<textarea id="nfqws-strategy" class="code" spellcheck="false"></textarea></label>
        <div class="editor-grid three">
          <label>User list<textarea id="nfqws-user" spellcheck="false"></textarea></label>
          <label>Exclude list<textarea id="nfqws-exclude" spellcheck="false"></textarea></label>
          <label>Auto list<textarea id="nfqws-auto" spellcheck="false"></textarea></label>
        </div>
        <div class="actions"><button data-save-section="nfqws" class="ok">Сохранить nfqws</button></div>
      </section>
    </section>

    <section id="dns" class="view" data-load="dns">
      <section class="panel">
        <h2>DNS</h2>
        <label class="check"><input type="checkbox" id="dns-enabled"> OURFW DNS policy включена</label>
        <label>Upstream DNS, по одному адресу на строку<textarea id="dns-servers" spellcheck="false" placeholder="1.1.1.1&#10;2606:4700:4700::1111"></textarea></label>
        <p class="muted">Доменные списки для VPN/Direct редактируются во вкладке «Маршрутизация» и автоматически превращаются dnsmasq в ipset.</p>
        <div class="actions"><button data-save-section="dns" class="ok">Сохранить DNS</button></div>
      </section>
    </section>

    <section id="watchdog" class="view" data-load="watchdog">
      <section class="panel">
        <h2>Watchdog</h2>
        <div class="form-grid">
          <label class="check"><input type="checkbox" id="wd-enabled"> Включён</label>
          <label>Интервал, сек<input id="wd-interval" type="number" min="10" max="3600"></label>
          <label>Ошибок до ремонта<input id="wd-fails" type="number" min="1" max="20"></label>
          <label>Что проверять<select id="wd-scope"><option value="gateway">Gateway</option><option value="internet">Internet</option><option value="vpn">VPN</option><option value="all">Всё</option></select></label>
          <label>Ping #1<input id="wd-ping1"></label><label>Ping #2<input id="wd-ping2"></label>
          <label>VPN probe<input id="wd-vpn-target"></label>
          <label>Max handshake age, сек<input id="wd-handshake" type="number" min="30" max="3600"></label>
          <label class="check danger"><input type="checkbox" id="wd-reboot"> Разрешить reboot, если repair не помог</label>
        </div>
        <div class="actions"><button data-save-section="watchdog" class="ok">Сохранить Watchdog</button><button data-module="watchdog" data-op="enable">Включить</button><button data-module="watchdog" data-op="disable" class="ghost">Выключить</button></div>
      </section>
    </section>

    <section id="maintenance" class="view">
      <section class="panel">
        <h2>Backup Center</h2>
        <p>Экспортируются только изменяемые настройки OURFW: config / profiles / rules. Восстановление тоже проходит через 90-секундный rollback.</p>
        <div class="actions"><button data-download="backup" class="ok">Скачать backup</button><label class="filebtn">Выбрать backup<input id="backup-file" type="file" accept=".bz2,.tar.bz2"></label><button id="backup-restore" class="warn">Восстановить backup</button></div>
        <span id="backup-name" class="muted"></span>
      </section>
      <section class="panel">
        <h2>Обновление компонентов OURFW</h2>
        <p>Пакет проверяется SHA-256, manifest whitelist, staging и health-check. Поддерживаются модули и отдельные пакеты WebUI (type=webui). После установки нужно подтвердить изменение; иначе компонент откатится автоматически.</p>
        <div class="actions"><label class="filebtn">Выбрать пакет<input id="component-file" type="file" accept=".bz2,.tar.bz2"></label><button id="component-install">Установить компонент</button></div>
        <span id="component-name" class="muted"></span>
      </section>
    </section>

    <section id="diagnostics" class="view">
      <section class="panel">
        <h2>Диагностика</h2>
        <p>Снимок содержит состояние OURFW, интерфейсы, policy rules, ipsets/iptables, WG/AWG, nfqws, память/uptime и последние логи.</p>
        <div class="actions"><button data-download="diagnostics" class="ok">Скачать отчёт</button><button data-action="diagnostics">Снять snapshot в /tmp</button><button data-action="baseline" class="ghost">Обновить baseline</button></div>
      </section>
      <section class="panel"><h2>Технический ответ</h2><pre id="result">Готово.</pre></section>
    </section>

    <section id="global-result" class="toastbox"><pre id="result-global">Готово.</pre></section>
  </main>
</div>
<script src="/ourfw/assets/ourfw.js"></script>
</body>
</html>
