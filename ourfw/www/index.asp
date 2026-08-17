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
  <header class="topbar">
    <div class="brand">
      <b>OURFW</b>
      <span id="version">…</span>
      <span id="save-state" class="state-chip neutral">Проверяю…</span>
    </div>
    <button class="ghost" id="refresh">Обновить состояние</button>
  </header>

  <section id="pending-bar" class="pending-bar hidden" aria-live="polite">
    <div>
      <strong id="pending-title">Изменения уже работают, но ещё не сохранены</strong>
      <div id="pending-info">Проверь интернет и нужные сайты.</div>
    </div>
    <div class="pending-actions">
      <span class="countdown">Автооткат через <b id="pending-count">90</b> сек.</span>
      <button data-action="confirm" class="primary">Оставить и сохранить</button>
      <button data-action="rollback" class="dangerbtn">Вернуть назад</button>
    </div>
  </section>

  <nav>
    <button class="tab active" data-tab="status">Сейчас</button>
    <button class="tab" data-tab="routing">Маршрутизация</button>
    <button class="tab" data-tab="vpn">VPN</button>
    <a class="tablink" href="/ourfw/subscription.asp">VPN-подписка</a>
    <button class="tab" data-tab="nfqws">DPI / nfqws</button>
    <button class="tab" data-tab="dns">DNS</button>
    <button class="tab" data-tab="adblock">AdBlock</button>
    <button class="tab" data-tab="watchdog">Watchdog</button>
    <button class="tab" data-tab="services">Сервисы</button>
    <button class="tab" data-tab="maintenance">Backup / Update</button>
    <button class="tab" data-tab="diagnostics">Диагностика</button>
  </nav>

  <main>
    <section id="status" class="view active">
      <div class="section-head">
        <div>
          <h1>Что реально работает сейчас</h1>
          <p>Это текущее состояние роутера, а не просто сохранённые галочки.</p>
        </div>
      </div>

      <div class="cards status-cards">
        <article><small>Интернет / WAN</small><strong id="wan">—</strong><span id="wan-note">—</span></article>
        <article><small>VPN-туннель</small><strong id="vpn-state">—</strong><span id="vpn-note">—</span></article>
        <article><small>Маршрутизация</small><strong id="routing-mode">—</strong><span id="routing-note">—</span></article>
        <article><small>Правила доменов</small><strong id="dns-rule-count">—</strong><span id="rules-note">—</span></article>
        <article><small>DPI / nfqws</small><strong id="nfqws-state">—</strong><span id="nfqws-note">—</span></article>
        <article><small>ZRAM</small><strong id="zram-state">—</strong><span>Страховочная swap в RAM</span></article>
      </div>

      <section class="panel last-change">
        <div>
          <h2>Последнее изменение</h2>
          <p id="last-change">Пока нет данных.</p>
        </div>
        <span id="last-change-chip" class="state-chip neutral">—</span>
      </section>

      <section class="panel simple-help">
        <h2>Как теперь сохраняются настройки</h2>
        <div class="steps">
          <div><b>1</b><span>Меняешь нужный раздел и нажимаешь одну кнопку «Сохранить и применить».</span></div>
          <div><b>2</b><span>Изменение сразу начинает работать. Другие несвязанные сервисы не перезапускаются.</span></div>
          <div><b>3</b><span>Если всё работает — сверху нажимаешь «Оставить и сохранить». Если нет — «Вернуть назад» или ждёшь автооткат.</span></div>
        </div>
      </section>
    </section>

    <section id="routing" class="view" data-load="routing">
      <div class="section-head">
        <div><h1>Маршрутизация</h1><p>Один режим + списки. Сохранение этого раздела больше не должно рвать VPN-туннель.</p></div>
      </div>
      <section class="panel">
        <div class="form-row three">
          <label>Режим
            <select id="routing-mode-select">
              <option value="smart">Smart — только выбранное через VPN</option>
              <option value="vpn-all">Всё через VPN — кроме DIRECT</option>
              <option value="off">Выключено — обычный интернет</option>
            </select>
          </label>
          <label>IPv6
            <select id="routing-ipv6">
              <option value="block">Block — не дать обойти VPN</option>
              <option value="native">Native — обычный IPv6</option>
            </select>
          </label>
          <label class="check"><input type="checkbox" id="routing-killswitch"> Kill-switch для помеченного трафика</label>
        </div>
        <div class="live-line"><span>Сейчас:</span> <b id="routing-live">—</b></div>
      </section>
      <section class="panel editor-grid">
        <label>Через VPN — домены
          <textarea id="vpn-domains" spellcheck="false" placeholder="youtube.com&#10;api.openai.com"></textarea>
          <span class="field-help">Один домен на строку. После DNS-ответа его IP попадает в VPN-набор.</span>
        </label>
        <label>Напрямую — домены
          <textarea id="direct-domains" spellcheck="false" placeholder="bank.example"></textarea>
          <span class="field-help">Исключения, которые должны идти через обычный WAN.</span>
        </label>
        <label>Через VPN — IPv4/CIDR<textarea id="vpn-ips" spellcheck="false" placeholder="203.0.113.0/24"></textarea></label>
        <label>Напрямую — IPv4/CIDR<textarea id="direct-ips" spellcheck="false" placeholder="198.51.100.10"></textarea></label>
        <div class="wide save-row">
          <button data-save-section="routing" class="primary">Сохранить и применить маршрутизацию</button>
          <span>Будут затронуты только Routing + DNS.</span>
        </div>
      </section>
    </section>

    <section id="vpn" class="view" data-load="vpn">
      <div class="section-head">
        <div><h1>VPN</h1><p>Включение, протокол и профиль сохраняются одной операцией.</p></div>
      </div>
      <section class="panel">
        <div class="live-banner"><span>Сейчас:</span><b id="vpn-live">—</b><small id="vpn-live-note">—</small></div>
        <div class="form-grid">
          <label class="check switch-check"><input type="checkbox" id="vpn-enabled"> VPN включён</label>
          <label>Основной протокол
            <select id="vpn-type">
              <option value="wireguard">WireGuard</option>
              <option value="amneziawg">AmneziaWG</option>
              <option value="openvpn">OpenVPN</option>
            </select>
          </label>
          <label class="check"><input type="checkbox" id="vpn-peer-dns"> Использовать DNS из VPN-профиля</label>
          <label class="check"><input type="checkbox" id="vpn-failover"> Автоматический fallback</label>
          <label>Запасной протокол
            <select id="vpn-failover-type">
              <option value="openvpn">OpenVPN</option>
              <option value="amneziawg">AmneziaWG</option>
              <option value="wireguard">WireGuard</option>
            </select>
          </label>
        </div>
      </section>
      <section class="panel">
        <h2>WireGuard / AmneziaWG профиль</h2>
        <p class="muted">Ключи остаются внутри роутера. Интерфейс не показывает их в статусе или логах.</p>
        <textarea id="vpn-profile" class="code tall" spellcheck="false" autocomplete="off" placeholder="[Interface]&#10;PrivateKey = ...&#10;Address = ...&#10;&#10;[Peer]&#10;PublicKey = ...&#10;Endpoint = ...&#10;AllowedIPs = 0.0.0.0/0"></textarea>
      </section>
      <section class="panel">
        <h2>OpenVPN профиль</h2>
        <textarea id="openvpn-profile" class="code tall" spellcheck="false" placeholder="client&#10;proto udp&#10;remote vpn.example 1194"></textarea>
        <label>Логин и пароль OpenVPN — ровно две строки
          <textarea id="openvpn-auth" class="code smallarea" spellcheck="false" autocomplete="off" placeholder="username&#10;password"></textarea>
        </label>
        <div class="save-row">
          <button data-save-section="vpn" class="primary">Сохранить и применить VPN</button>
          <span>VPN будет перезапущен только при изменении этого раздела.</span>
        </div>
      </section>
    </section>

    <section id="nfqws" class="view" data-load="nfqws">
      <div class="section-head"><div><h1>DPI / nfqws</h1><p>Настройки обхода DPI применяются отдельно от VPN и маршрутизации.</p></div></div>
      <section class="panel">
        <div class="form-row three">
          <label class="check switch-check"><input type="checkbox" id="nfqws-enabled"> nfqws включён</label>
          <label>WAN interface <input id="nfqws-wan" placeholder="пусто = авто"></label>
          <label class="check"><input type="checkbox" id="nfqws-log"> Расширенный лог</label>
        </div>
        <label>Стратегия nfqws<textarea id="nfqws-strategy" class="code" spellcheck="false"></textarea></label>
        <div class="editor-grid three">
          <label>User list<textarea id="nfqws-user" spellcheck="false"></textarea></label>
          <label>Exclude list<textarea id="nfqws-exclude" spellcheck="false"></textarea></label>
          <label>Auto list<textarea id="nfqws-auto" spellcheck="false"></textarea></label>
        </div>
        <div class="save-row"><button data-save-section="nfqws" class="primary">Сохранить и применить nfqws</button><span>VPN не перезапускается.</span></div>
      </section>
    </section>

    <section id="dns" class="view" data-load="dns">
      <div class="section-head"><div><h1>DNS</h1><p>Доменные VPN/DIRECT правила редактируются в «Маршрутизация».</p></div></div>
      <section class="panel">
        <label class="check switch-check"><input type="checkbox" id="dns-enabled"> OURFW DNS policy включена</label>
        <label>Upstream DNS, по одному IPv4 на строку<textarea id="dns-servers" spellcheck="false" placeholder="1.1.1.1"></textarea></label>
        <div class="save-row"><button data-save-section="dns" class="primary">Сохранить и применить DNS</button><span>Перезапускается только dnsmasq.</span></div>
      </section>
    </section>

    <section id="adblock" class="view" data-load="adblock">
      <div class="section-head"><div><h1>AdBlock</h1><p>Блокировка и источники сохраняются одной операцией.</p></div></div>
      <section class="panel">
        <div class="form-grid">
          <label class="check switch-check"><input type="checkbox" id="ab-enabled"> AdBlock включён</label>
          <label>Лимит доменов<input id="ab-max" type="number" min="100" max="50000"></label>
          <label>Обновлять каждые, ч<input id="ab-hours" type="number" min="1" max="720"></label>
          <label class="check"><input type="checkbox" id="ab-querylog"> dnsmasq query-log</label>
        </div>
        <div class="cards mini-cards">
          <article><small>В базе</small><strong id="ab-count">0</strong></article>
          <article><small>Размер runtime</small><strong id="ab-bytes">0</strong></article>
          <article><small>Последнее обновление</small><strong id="ab-updated">—</strong></article>
        </div>
      </section>
      <section class="panel editor-grid">
        <label class="wide">HTTPS-подписки, по одной на строку<textarea id="ab-sources" class="code" spellcheck="false"></textarea></label>
        <label>Allowlist<textarea id="ab-allow" spellcheck="false"></textarea></label>
        <label>Denylist<textarea id="ab-deny" spellcheck="false"></textarea></label>
        <div class="wide save-row">
          <button data-save-section="adblock" class="primary">Сохранить и применить AdBlock</button>
          <button data-module="adblock" data-op="update" class="secondary">Обновить базу сейчас</button>
        </div>
      </section>
    </section>

    <section id="watchdog" class="view" data-load="watchdog">
      <div class="section-head"><div><h1>Watchdog</h1><p>Проверка связи и восстановление без лишних перезапусков остальных сервисов.</p></div></div>
      <section class="panel">
        <div class="form-grid">
          <label class="check switch-check"><input type="checkbox" id="wd-enabled"> Watchdog включён</label>
          <label>Интервал, сек<input id="wd-interval" type="number" min="10" max="3600"></label>
          <label>Ошибок до ремонта<input id="wd-fails" type="number" min="1" max="20"></label>
          <label>Что проверять<select id="wd-scope"><option value="gateway">Gateway</option><option value="internet">Internet</option><option value="vpn">VPN</option><option value="all">Всё</option></select></label>
          <label>Ping #1<input id="wd-ping1"></label>
          <label>Ping #2<input id="wd-ping2"></label>
          <label>VPN probe<input id="wd-vpn-target"></label>
          <label>Max handshake age, сек<input id="wd-handshake" type="number" min="30" max="3600"></label>
          <label class="check"><input type="checkbox" id="wd-inetdetect"> Использовать Internet Detect Padavan</label>
          <label>Возраст InetDetect, сек<input id="wd-inet-age" type="number" min="30" max="3600"></label>
          <label class="check danger"><input type="checkbox" id="wd-reboot"> Разрешить reboot, если repair не помог</label>
        </div>
        <div class="save-row"><button data-save-section="watchdog" class="primary">Сохранить и применить Watchdog</button><a class="linkbtn" href="/Advanced_InetDetect_Content.asp">Internet Detect Padavan</a></div>
      </section>
    </section>

    <section id="services" class="view" data-load="zram">
      <div class="section-head"><div><h1>Сервисы</h1><p>Системные возможности Padavan и ZRAM.</p></div></div>
      <section class="panel">
        <div class="cards mini-cards">
          <article><small>HTTPS WebUI</small><strong id="cap-https">—</strong></article>
          <article><small>SFTP</small><strong id="cap-sftp">—</strong></article>
          <article><small>OpenVPN</small><strong id="cap-openvpn">—</strong></article>
        </div>
        <div class="save-row"><a class="linkbtn" href="/Advanced_Services_Content.asp">Открыть сервисы Padavan</a></div>
      </section>
      <section class="panel">
        <h2>ZRAM</h2>
        <div class="form-row two">
          <label>Режим<select id="zram-mode"><option value="off">Выключен</option><option value="auto">Auto — 25% RAM</option><option value="25">25% RAM</option><option value="50">50% RAM</option></select></label>
          <label>Сжатие<select id="zram-algo"><option value="auto">Auto</option><option value="lz4">LZ4</option><option value="lzo">LZO</option></select></label>
        </div>
        <div class="save-row"><button data-save-section="zram" class="primary">Сохранить и применить ZRAM</button><span>VPN и DNS не затрагиваются.</span></div>
      </section>
    </section>

    <section id="maintenance" class="view">
      <div class="section-head"><div><h1>Backup / Update</h1><p>Редкие административные операции.</p></div></div>
      <section class="panel">
        <h2>Backup</h2>
        <div class="actions">
          <button data-download="backup" class="primary">Скачать backup</button>
          <label class="filebtn">Выбрать backup<input id="backup-file" type="file" accept=".bz2,.tar.bz2"></label>
          <button id="backup-restore" class="dangerbtn">Восстановить backup</button>
        </div>
        <span id="backup-name" class="muted"></span>
      </section>
      <section class="panel">
        <h2>Обновление компонентов OURFW</h2>
        <div class="actions">
          <label class="filebtn">Выбрать пакет<input id="component-file" type="file" accept=".bz2,.tar.bz2"></label>
          <button id="component-install" class="secondary">Установить компонент</button>
        </div>
        <span id="component-name" class="muted"></span>
      </section>
      <details class="panel advanced">
        <summary>Расширенные действия</summary>
        <p>Полный повторный apply нужен только для диагностики. В обычной настройке его использовать не надо.</p>
        <button data-action="apply" class="secondary">Применить весь стек заново</button>
      </details>
    </section>

    <section id="diagnostics" class="view">
      <div class="section-head"><div><h1>Диагностика</h1><p>Снимок сети, VPN, правил, памяти и последних логов.</p></div></div>
      <section class="panel">
        <div class="actions">
          <button data-download="diagnostics" class="primary">Скачать отчёт</button>
          <button data-action="diagnostics" class="secondary">Снять snapshot в /tmp</button>
          <button data-action="baseline" class="ghost">Обновить baseline</button>
        </div>
      </section>
    </section>

    <section id="notice" class="notice neutral" aria-live="polite">
      <strong id="notice-title">Готово</strong>
      <span id="notice-text">Состояние загружено.</span>
    </section>

    <details class="tech">
      <summary>Технические детали</summary>
      <pre id="result-global">—</pre>
    </details>
  </main>
</div>
<script src="/ourfw/assets/ourfw.js"></script>
</body>
</html>
