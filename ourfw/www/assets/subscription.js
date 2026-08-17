(function(){
  'use strict';
  const q=s=>document.querySelector(s);
  let csrf='', nodes=[], selected={primary:'',backup:''}, hy2Confirm='';
  const result=q('#sub-result');

  function show(v,bad=false){result.textContent=typeof v==='string'?v:JSON.stringify(v,null,2);result.parentElement.classList.toggle('bad',!!bad);}
  function text(id,v){const e=q(id);if(e)e.textContent=v;}
  function safeOpId(v){return /^n[A-Za-z0-9._-]+$/.test(v||'');}

  async function rootStatus(){
    const r=await fetch('/ourfw_api.cgi?action=status',{cache:'no-store'}), raw=await r.text();
    let j;try{j=JSON.parse(raw);}catch(_){throw new Error('Некорректный status API');}
    if(j.error)throw new Error(j.error);
    csrf=j.csrf||csrf;text('#sub-version',j.version||'dev');return j;
  }

  async function post(action,p1='',p2=''){
    if(!csrf)await rootStatus();
    const body=new URLSearchParams({action,p1,p2,csrf});
    const r=await fetch('/ourfw_api.cgi',{method:'POST',cache:'no-store',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:body.toString()});
    const raw=await r.text();let j;try{j=JSON.parse(raw);}catch(_){throw new Error('Некорректный ответ API: '+raw.slice(0,160));}
    if(j.error)throw new Error(j.error);
    if(j&&j.ok===false)throw new Error(j.detail||('Операция отклонена, rc='+(j.rc==null?'?':j.rc)));
    return j;
  }

  async function moduleCall(mod,op){return post('module',mod,op);}

  function bytesToB64url(u){
    let bin='',step=0x6000;
    for(let i=0;i<u.length;i+=step){const p=u.subarray(i,Math.min(i+step,u.length));bin+=String.fromCharCode.apply(null,p);}
    return btoa(bin).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
  }

  async function saveSecretUrl(){
    const input=q('#sub-url'), url=input.value.trim();
    if(!url)throw new Error('Вставь HTTPS URL подписки');
    if(!/^https:\/\/[^\s]+$/.test(url))throw new Error('Разрешён только HTTPS URL без пробелов');
    const u=new TextEncoder().encode(url+'\n');
    if(u.length>4096)throw new Error('URL слишком длинный');
    const enc=bytesToB64url(u);
    await post('file-begin','subscription-secret',String(u.length));
    try{
      for(let i=0;i<enc.length;i+=960)await post('file-chunk','subscription-secret',enc.slice(i,i+960));
      const j=await post('file-commit','subscription-secret','');
      input.value='';
      show('URL сохранён в защищённый write-only профиль. Токен не возвращён в WebUI.');
      return j;
    }catch(e){try{await post('file-abort','subscription-secret','');}catch(_){}throw e;}
  }

  function usableNodes(){return nodes.filter(n=>n&&n.protocol==='hysteria2'&&n.engine==='hysteria'&&n.support==='experimental'&&safeOpId(n.id));}
  function fillSelect(el,chosen){
    while(el.options.length>1)el.remove(1);
    for(const n of usableNodes()){
      const o=document.createElement('option');o.value=n.id;
      const name=(n.label||n.host||n.id).slice(0,80), hp=n.host?(' @ '+n.host+(n.port?':'+n.port:'')):'';
      o.textContent=name+hp;el.appendChild(o);
    }
    el.value=chosen||'';
  }
  function renderNodes(){
    fillSelect(q('#sub-primary'),selected.primary);fillSelect(q('#sub-backup'),selected.backup);
    if(!nodes.length){text('#sub-nodes','Список пуст. Сохрани URL, включи менеджер и нажми «Обновить список узлов».');return;}
    const max=120, lines=nodes.slice(0,max).map(n=>{
      const flags=(n.primary?' [PRIMARY]':'')+(n.backup?' [BACKUP]':'');
      return `${n.id}  ${n.protocol}  ${n.label||'-'}  ${n.host||'-'}:${n.port||0}  ${n.support||'-'}${flags}`;
    });
    if(nodes.length>max)lines.push(`… ещё ${nodes.length-max} узлов не показаны`);
    text('#sub-nodes',lines.join('\n'));
  }

  function renderManager(s){
    q('#sub-enabled').checked=!!s.enabled;
    text('#sub-source-state',s.source_set?'сохранён':'не задан');
    text('#sub-node-count',String(s.nodes||0));
    text('#sub-fetch-state',(s.fetch||'idle')+' / '+(s.parse||'idle'));
  }
  function renderHy2(j){text('#hy2-state',(j&&j.detail)?j.detail:'Hysteria2 status unavailable');}

  async function loadAll(announce=true){
    try{
      await rootStatus();
      const s=await moduleCall('subscription','status');
      nodes=await moduleCall('subscription','nodes');
      selected=await moduleCall('subscription','selected');
      const h=await moduleCall('vpn','hy2-status');
      renderManager(s);renderNodes();renderHy2(h);
      if(announce)show(`Загружено узлов: ${nodes.length}; Hysteria2-совместимых: ${usableNodes().length}.`);
    }catch(e){show('Ошибка загрузки: '+e.message,true);}
  }

  async function guarded(label,fn,reload=true){
    show(label+'…');
    try{const j=await fn();show(j);if(reload)await loadAll(false);return j;}catch(e){show('Ошибка: '+e.message,true);throw e;}
  }

  async function setSelection(slot){
    const id=q(slot==='primary'?'#sub-primary':'#sub-backup').value;
    const op=id?(slot+'-'+id):('clear-'+slot);
    if(id&&!safeOpId(id))throw new Error('Некорректный ID узла');
    return moduleCall('subscription',op);
  }

  async function hy2(op){
    const j=await moduleCall('vpn',op);
    const d=j.detail||'';
    const m=d.match(/CONFIRM_TOKEN=([A-Za-z0-9._-]+)/);
    if(m){hy2Confirm=m[1];q('#hy2-confirm').disabled=false;}
    if(op==='hy2-route-off'||op==='hy2-stop'){hy2Confirm='';q('#hy2-confirm').disabled=true;}
    renderHy2(j);return j;
  }

  q('#sub-refresh-all').addEventListener('click',()=>loadAll());
  q('#sub-toggle').addEventListener('click',()=>guarded('Сохраняю состояние менеджера',()=>moduleCall('subscription',q('#sub-enabled').checked?'enable':'disable')));
  q('#sub-save-url').addEventListener('click',()=>guarded('Сохраняю защищённый URL',saveSecretUrl));
  q('#sub-refresh-feed').addEventListener('click',()=>guarded('Загружаю и разбираю подписку',()=>moduleCall('subscription','refresh')));
  q('#sub-set-primary').addEventListener('click',()=>guarded('Сохраняю primary',()=>setSelection('primary')));
  q('#sub-set-backup').addEventListener('click',()=>guarded('Сохраняю backup',()=>setSelection('backup')));
  q('#hy2-prepare').addEventListener('click',()=>guarded('Проверяю TPROXY и готовлю Hysteria2 engine',()=>hy2('hy2-prepare')));
  q('#hy2-start-primary').addEventListener('click',()=>guarded('Запускаю Hysteria2 primary',()=>hy2('hy2-start-primary')));
  q('#hy2-start-backup').addEventListener('click',()=>guarded('Запускаю Hysteria2 backup',()=>hy2('hy2-start-backup')));
  q('#hy2-arm-smart').addEventListener('click',()=>guarded('Включаю guarded TPROXY Smart',()=>hy2('hy2-arm-smart'),false));
  q('#hy2-arm-all').addEventListener('click',()=>guarded('Включаю guarded TPROXY для всего трафика',()=>hy2('hy2-arm-all'),false));
  q('#hy2-route-off').addEventListener('click',()=>guarded('Выключаю TPROXY',()=>hy2('hy2-route-off')));
  q('#hy2-stop').addEventListener('click',()=>guarded('Останавливаю Hysteria2',()=>hy2('hy2-stop')));
  q('#hy2-confirm').addEventListener('click',()=>guarded('Подтверждаю TPROXY',async()=>{
    if(!hy2Confirm)throw new Error('Нет confirmation token. Если страница была перезагружена — выключи TPROXY и включи заново.');
    const token=hy2Confirm, j=await moduleCall('vpn','hy2-confirm-'+token);hy2Confirm='';q('#hy2-confirm').disabled=true;return j;
  }));

  document.addEventListener('visibilitychange',()=>{if(!document.hidden)loadAll(false);});
  loadAll();
})();
