<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>OURFW — Подписки / Hysteria2</title>
  <link rel="stylesheet" href="/ourfw/assets/ourfw.css">
</head>
<body>
<div class="shell">
  <header>
    <div class="brand"><b>OURFW</b><span id="sub-version">v0.7.0</span></div>
    <div class="head-actions"><a class="linkbtn" href="/ourfw/index.asp">← Основная панель</a><button class="ghost" id="sub-refresh-all">Обновить</button></div>
  </header>
  <main>
    <section class="panel">
      <h2>VPN Subscription</h2>
      <div class="cards mini-cards">
        <article><small>Источник</small><strong id="sub-source-state">—</strong></article>
        <article><small>Узлов</small><strong id="sub-node-count">0</strong></article>
        <article><small>Fetch / parse</small><strong id="sub-fetch-state">—</strong></article>
      </div>
      <div class="form-row two">
        <label class="check"><input type="checkbox" id="sub-enabled"> Менеджер подписки включён</label>
        <label>HTTPS URL подписки
          <input type="password" id="sub-url" autocomplete="off" spellcheck="false" placeholder="https://provider.example/sub?...">
        </label>
      </div>
      <p class="muted">URL — write-only секрет: WebUI никогда не читает его обратно и API не возвращает токен/credentials. После сохранения поле очищается. Обновление списка выполняется только вручную.</p>
      <div class="actions">
        <button id="sub-toggle" class="ok">Применить Вкл/Выкл</button>
        <button id="sub-save-url" class="ok">Сохранить URL</button>
        <button id="sub-refresh-feed">Обновить список узлов</button>
      </div>
    </section>

    <section class="panel">
      <h2>Primary / backup</h2>
      <p class="muted">В селекторах показываются только узлы, которые текущий экспериментальный Hysteria2 runtime умеет запускать. Остальные найденные протоколы остаются видны в списке ниже, но не передаются движку.</p>
      <div class="form-row two">
        <label>Primary<select id="sub-primary"><option value="">— не выбран —</option></select></label>
        <label>Backup<select id="sub-backup"><option value="">— не выбран —</option></select></label>
      </div>
      <div class="actions">
        <button id="sub-set-primary" class="ok">Сохранить primary</button>
        <button id="sub-set-backup">Сохранить backup</button>
      </div>
      <pre id="sub-nodes">Узлы ещё не загружены.</pre>
    </section>

    <section class="panel safety">
      <h2>Hysteria2 + TPROXY</h2>
      <p class="muted">Ничего не включается на boot. «Подготовить» скачивает только pinned Hysteria2 engine с проверкой размера/SHA-256. TPROXY маршрутизация после включения требует подтверждения и сама откатывается примерно через 90 секунд.</p>
      <div class="actions">
        <button id="hy2-prepare">Подготовить engine</button>
        <button id="hy2-start-primary" class="ok">Старт primary</button>
        <button id="hy2-start-backup">Старт backup</button>
        <button id="hy2-arm-smart">TPROXY Smart</button>
        <button id="hy2-arm-all">TPROXY весь трафик</button>
        <button id="hy2-confirm" class="ok" disabled>Подтвердить TPROXY</button>
        <button id="hy2-route-off" class="ghost">Выключить TPROXY</button>
        <button id="hy2-stop" class="warn">Стоп Hysteria2</button>
      </div>
      <pre id="hy2-state">Статус ещё не загружен.</pre>
    </section>

    <section class="panel"><h2>Технический ответ</h2><pre id="sub-result">Готово.</pre></section>
  </main>
</div>
<script src="/ourfw/assets/subscription.js"></script>
</body>
</html>
