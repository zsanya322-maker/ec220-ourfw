(function(){
  'use strict';
  const q=s=>document.querySelector(s), qa=s=>Array.from(document.querySelectorAll(s));
  const out=q('#result-global'), files={}, loaded=new Set();
  let csrf='', apiBusy=0;

  function show(msg, bad=false){out.textContent=typeof msg==='string'?msg:JSON.stringify(msg,null,2);out.parentElement.classList.toggle('bad',!!bad);}
  function text(id,v){const e=q(id);if(e)e.textContent=v;}
  function checked(id,v){const e=q(id);if(e)e.checked=!!v;}
  function value(id,v){const e=q(id);if(e)e.value=v==null?'':v;}

  async function call(params,method='GET'){
    const body=new URLSearchParams(params), opt={cache:'no-store'};let url='/ourfw_api.cgi';
    if(method==='POST'){
      if(!csrf)throw new Error('CSRF token unavailable; обнови состояние');
      body.set('csrf',csrf);opt.method='POST';opt.headers={'Content-Type':'application/x-www-form-urlencoded'};opt.body=body.toString();
    }else url+='?'+body.toString();
    apiBusy++;
    try{
      const r=await fetch(url,opt);const raw=await r.text();let j;
      try{j=JSON.parse(raw);}catch(_){throw new Error('Некорректный ответ API: '+raw.slice(0,160));}
      if(j.error)throw new Error(j.error);return j;
    }finally{apiBusy--;}
  }

  async function status(){
    if(apiBusy)return;
    try{
      const j=await call({action:'status'});csrf=j.csrf||csrf;
      text('#version',j.version||'dev');text('#wan',j.wan_if||'—');text('#routing-mode',j.routing_mode||'—');
      text('#vpn-state',j.vpn_enabled?((j.vpn_type||'VPN')+': '+(j.vpn_up?'работает':'tunnel down')):'выключен');
      text('#nfqws-state',j.nfqws_enabled?(j.nfqws_up?'работает':'включён / process down'):'выключен');
      text('#adblock-state',j.adblock_enabled?((j.adblock_domains||0)+' доменов'):'выключен');
      text('#zram-state',j.zram_active?((j.zram_mode||'auto')+' / active'):(j.zram_mode||'off'));
      text('#cap-https',j.https_cap?'есть':'нет');text('#cap-sftp',j.sftp_cap?'есть':'нет');text('#cap-openvpn',j.openvpn_cap?'есть':'нет');
      const pill=q('#pending-pill');pill.classList.toggle('hidden',!j.pending);
    }catch(e){show('API недоступен: '+e.message,true);}
  }

  async function action(name,p1='',p2=''){
    show('Выполняю: '+name+'…');
    try{const j=await call({action:name,p1,p2},'POST');show(j);await status();return j;}catch(e){show('Ошибка: '+e.message,true);throw e;}
  }

  function b64urlToBytes(s){
    s=s.replace(/-/g,'+').replace(/_/g,'/');while(s.length%4)s+='=';
    const bin=atob(s),u=new Uint8Array(bin.length);for(let i=0;i<bin.length;i++)u[i]=bin.charCodeAt(i);return u;
  }
  function bytesToB64url(u){
    let bin='';const step=0x6000;
    for(let i=0;i<u.length;i+=step){const part=u.subarray(i,Math.min(i+step,u.length));bin+=String.fromCharCode.apply(null,part);}
    return btoa(bin).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
  }
  function utf8(s){return new TextEncoder().encode(s);}
  function unutf8(u){return new TextDecoder().decode(u);}
  async function sha256Hex(u){
    // Do not depend on WebCrypto: router UI is normally plain HTTP on a LAN IP,
    // where browsers may disable crypto.subtle. Compact SHA-256 fallback works
    // for our small config/component files.
    if(window.crypto&&crypto.subtle){try{const h=new Uint8Array(await crypto.subtle.digest('SHA-256',u));return Array.from(h,b=>b.toString(16).padStart(2,'0')).join('');}catch(_){}}
    const K=[0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
    const rotr=(x,n)=>(x>>>n)|(x<<(32-n)), l=u.length, bitHi=Math.floor((l*8)/0x100000000), bitLo=(l*8)>>>0;
    const n=((l+9+63)>>6)<<6, m=new Uint8Array(n);m.set(u);m[l]=0x80;
    const dv=new DataView(m.buffer);dv.setUint32(n-8,bitHi,false);dv.setUint32(n-4,bitLo,false);
    let h=[0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19],w=new Uint32Array(64);
    for(let o=0;o<n;o+=64){for(let i=0;i<16;i++)w[i]=dv.getUint32(o+i*4,false);for(let i=16;i<64;i++){const a=w[i-15],b=w[i-2],s0=rotr(a,7)^rotr(a,18)^(a>>>3),s1=rotr(b,17)^rotr(b,19)^(b>>>10);w[i]=(w[i-16]+s0+w[i-7]+s1)>>>0;}let[a,b,c,d,e,f,g,hh]=h;for(let i=0;i<64;i++){const S1=rotr(e,6)^rotr(e,11)^rotr(e,25),ch=(e&f)^((~e)&g),t1=(hh+S1+ch+K[i]+w[i])>>>0,S0=rotr(a,2)^rotr(a,13)^rotr(a,22),maj=(a&b)^(a&c)^(b&c),t2=(S0+maj)>>>0;hh=g;g=f;f=e;e=(d+t1)>>>0;d=c;c=b;b=a;a=(t1+t2)>>>0;}h=[(h[0]+a)>>>0,(h[1]+b)>>>0,(h[2]+c)>>>0,(h[3]+d)>>>0,(h[4]+e)>>>0,(h[5]+f)>>>0,(h[6]+g)>>>0,(h[7]+hh)>>>0];}
    return h.map(x=>x.toString(16).padStart(8,'0')).join('');
  }

  async function getFile(target){
    const j=await call({action:'file-get',p1:target},'POST');const s=unutf8(b64urlToBytes(j.data||''));files[target]=s;return s;
  }
  async function uploadBytes(target,u,finish='file-stage'){
    const digest=await sha256Hex(u), enc=bytesToB64url(u);
    await call({action:'file-begin',p1:target,p2:digest},'POST');
    try{
      for(let i=0;i<enc.length;i+=960)await call({action:'file-chunk',p1:target,p2:enc.slice(i,i+960)},'POST');
      return await call({action:finish,p1:target},'POST');
    }catch(e){try{await call({action:'file-abort',p1:target},'POST');}catch(_){}throw e;}
  }
  async function stageText(target,s){return uploadBytes(target,utf8(s),'file-stage');}
  async function saveSection(section,payloads){
    show('Проверяю и загружаю раздел «'+section+'»…');
    try{
      for(const [target,data] of Object.entries(payloads)){await stageText(target,data);files[target]=data;}
      const j=await call({action:'section-commit',p1:section},'POST');show('Применено как кандидат. Проверь доступ и нажми «Подтвердить изменения».\n'+JSON.stringify(j,null,2));await status();return j;
    }catch(e){try{await call({action:'section-abort',p1:section},'POST');}catch(_){}show('Ошибка сохранения: '+e.message,true);throw e;}
  }

  function kvGet(s,k,def=''){const m=s.match(new RegExp('^\\s*'+k+'=([^\\r\\n]*)','m'));return m?m[1].trim():def;}
  function kvSet(s,k,v){
    const re=new RegExp('^\\s*'+k+'=[^\\r\\n]*','m');const line=k+'='+v;
    return re.test(s)?s.replace(re,line):(s.replace(/\s*$/,'')+'\n'+line+'\n');
  }

  async function loadRouting(){
    const [cfg,vd,dd,vi,di]=await Promise.allSequential([
      ()=>getFile('routing-config'),()=>getFile('vpn-domains'),()=>getFile('direct-domains'),()=>getFile('vpn-ips'),()=>getFile('direct-ips')]);
    value('#routing-ipv6',kvGet(cfg,'IPV6_POLICY','block'));checked('#routing-killswitch',kvGet(cfg,'KILLSWITCH','1')==='1');
    value('#vpn-domains',vd);value('#direct-domains',dd);value('#vpn-ips',vi);value('#direct-ips',di);
  }
  async function loadVpn(){
    const [cfg,wg,ovpn,auth]=await Promise.allSequential([()=>getFile('vpn-config'),()=>getFile('vpn-profile'),()=>getFile('openvpn-profile'),()=>getFile('openvpn-auth')]);
    value('#vpn-type',kvGet(cfg,'VPN_TYPE','wireguard'));checked('#vpn-peer-dns',kvGet(cfg,'VPN_USE_PEER_DNS','0')==='1');
    checked('#vpn-failover',kvGet(cfg,'VPN_FAILOVER_ENABLED','0')==='1');value('#vpn-failover-type',kvGet(cfg,'VPN_FAILOVER_TYPE','openvpn'));
    value('#vpn-profile',wg);value('#openvpn-profile',ovpn);value('#openvpn-auth',auth);
  }
  async function loadNfqws(){
    const [cfg,strat,user,exc,auto]=await Promise.allSequential([
      ()=>getFile('nfqws-config'),()=>getFile('nfqws-strategy'),()=>getFile('nfqws-user'),()=>getFile('nfqws-exclude'),()=>getFile('nfqws-auto')]);
    value('#nfqws-wan',kvGet(cfg,'NFQWS_WAN_IF',''));checked('#nfqws-log',kvGet(cfg,'NFQWS_LOG','0')==='1');
    value('#nfqws-strategy',strat);value('#nfqws-user',user);value('#nfqws-exclude',exc);value('#nfqws-auto',auto);
  }
  async function loadDns(){
    const [cfg,servers]=await Promise.allSequential([()=>getFile('dns-config'),()=>getFile('dns-servers')]);checked('#dns-enabled',kvGet(cfg,'DNS_ENABLED','1')==='1');value('#dns-servers',servers);
  }
  async function loadAdblock(){
    const [cfg,sources,allow,deny]=await Promise.allSequential([()=>getFile('adblock-config'),()=>getFile('adblock-sources'),()=>getFile('adblock-allow'),()=>getFile('adblock-deny')]);
    checked('#ab-enabled',kvGet(cfg,'ADBLOCK_ENABLED','0')==='1');value('#ab-max',kvGet(cfg,'ADBLOCK_MAX_DOMAINS','15000'));value('#ab-hours',kvGet(cfg,'ADBLOCK_REFRESH_HOURS','24'));checked('#ab-querylog',kvGet(cfg,'ADBLOCK_QUERY_LOG','0')==='1');
    value('#ab-sources',sources);value('#ab-allow',allow);value('#ab-deny',deny);
    try{const j=await call({action:'module',p1:'adblock',p2:'status'},'POST');text('#ab-count',String(j.domains||0));text('#ab-bytes',humanBytes(j.bytes||0));text('#ab-updated',formatEpoch(j.updated||0));}catch(_){}
  }
  async function loadWatchdog(){
    const cfg=await getFile('watchdog-config');checked('#wd-enabled',kvGet(cfg,'WATCHDOG_ENABLED','0')==='1');value('#wd-interval',kvGet(cfg,'WATCHDOG_INTERVAL','30'));value('#wd-fails',kvGet(cfg,'WATCHDOG_FAILS','3'));value('#wd-scope',kvGet(cfg,'WATCHDOG_SCOPE','all'));value('#wd-ping1',kvGet(cfg,'PING_TARGET1','1.1.1.1'));value('#wd-ping2',kvGet(cfg,'PING_TARGET2','8.8.8.8'));value('#wd-vpn-target',kvGet(cfg,'WATCHDOG_VPN_TARGET','1.1.1.1'));value('#wd-handshake',kvGet(cfg,'WATCHDOG_VPN_HANDSHAKE_MAX_AGE','180'));checked('#wd-inetdetect',kvGet(cfg,'WATCHDOG_USE_INETDETECT','1')==='1');value('#wd-inet-age',kvGet(cfg,'WATCHDOG_INETDETECT_MAX_AGE','180'));checked('#wd-reboot',kvGet(cfg,'WATCHDOG_REBOOT','0')==='1');
  }
  async function loadZram(){
    const cfg=await getFile('zram-config');value('#zram-mode',kvGet(cfg,'ZRAM_MODE','auto'));value('#zram-algo',kvGet(cfg,'ZRAM_ALGO','auto'));
  }

  function humanBytes(n){n=Number(n)||0;if(n<1024)return n+' B';if(n<1048576)return (n/1024).toFixed(1)+' KiB';return (n/1048576).toFixed(1)+' MiB';}
  function formatEpoch(n){n=Number(n)||0;if(!n)return 'ещё не обновлялся';try{return new Date(n*1000).toLocaleString();}catch(_){return String(n);}}

  // Sequential helper avoids races through Padavan's single /tmp API response file.
  Promise.allSequential=async fs=>{const r=[];for(const f of fs)r.push(await f());return r;};
  async function ensureLoaded(section){
    if(!section||loaded.has(section))return;show('Загружаю настройки…');
    try{
      if(section==='routing')await loadRouting();if(section==='vpn')await loadVpn();if(section==='nfqws')await loadNfqws();if(section==='dns')await loadDns();if(section==='adblock')await loadAdblock();if(section==='watchdog')await loadWatchdog();if(section==='zram')await loadZram();
      loaded.add(section);show('Настройки загружены.');
    }catch(e){show('Не удалось загрузить настройки: '+e.message,true);}
  }

  async function saveNamed(section){
    if(section==='routing'){
      let c=files['routing-config']||'';c=kvSet(c,'IPV6_POLICY',q('#routing-ipv6').value);c=kvSet(c,'KILLSWITCH',q('#routing-killswitch').checked?'1':'0');
      return saveSection('routing',{'routing-config':c,'vpn-domains':q('#vpn-domains').value,'direct-domains':q('#direct-domains').value,'vpn-ips':q('#vpn-ips').value,'direct-ips':q('#direct-ips').value});
    }
    if(section==='vpn'){
      let c=files['vpn-config']||'';c=kvSet(c,'VPN_TYPE',q('#vpn-type').value);c=kvSet(c,'VPN_USE_PEER_DNS',q('#vpn-peer-dns').checked?'1':'0');c=kvSet(c,'VPN_FAILOVER_ENABLED',q('#vpn-failover').checked?'1':'0');c=kvSet(c,'VPN_FAILOVER_TYPE',q('#vpn-failover-type').value);
      return saveSection('vpn',{'vpn-config':c,'vpn-profile':q('#vpn-profile').value,'openvpn-profile':q('#openvpn-profile').value,'openvpn-auth':q('#openvpn-auth').value});
    }
    if(section==='nfqws'){
      let c=files['nfqws-config']||'';c=kvSet(c,'NFQWS_WAN_IF',q('#nfqws-wan').value.trim());c=kvSet(c,'NFQWS_LOG',q('#nfqws-log').checked?'1':'0');
      return saveSection('nfqws',{'nfqws-config':c,'nfqws-strategy':q('#nfqws-strategy').value,'nfqws-user':q('#nfqws-user').value,'nfqws-exclude':q('#nfqws-exclude').value,'nfqws-auto':q('#nfqws-auto').value});
    }
    if(section==='dns'){
      let c=files['dns-config']||'';c=kvSet(c,'DNS_ENABLED',q('#dns-enabled').checked?'1':'0');return saveSection('dns',{'dns-config':c,'dns-servers':q('#dns-servers').value});
    }
    if(section==='adblock'){
      let c=files['adblock-config']||'';const pairs={ADBLOCK_ENABLED:q('#ab-enabled').checked?'1':'0',ADBLOCK_MAX_DOMAINS:q('#ab-max').value,ADBLOCK_REFRESH_HOURS:q('#ab-hours').value,ADBLOCK_QUERY_LOG:q('#ab-querylog').checked?'1':'0'};for(const [k,v] of Object.entries(pairs))c=kvSet(c,k,v);
      return saveSection('adblock',{'adblock-config':c,'adblock-sources':q('#ab-sources').value,'adblock-allow':q('#ab-allow').value,'adblock-deny':q('#ab-deny').value});
    }
    if(section==='watchdog'){
      let c=files['watchdog-config']||'';const pairs={WATCHDOG_ENABLED:q('#wd-enabled').checked?'1':'0',WATCHDOG_INTERVAL:q('#wd-interval').value,WATCHDOG_FAILS:q('#wd-fails').value,WATCHDOG_SCOPE:q('#wd-scope').value,PING_TARGET1:q('#wd-ping1').value.trim(),PING_TARGET2:q('#wd-ping2').value.trim(),WATCHDOG_REBOOT:q('#wd-reboot').checked?'1':'0',WATCHDOG_VPN_TARGET:q('#wd-vpn-target').value.trim(),WATCHDOG_VPN_HANDSHAKE_MAX_AGE:q('#wd-handshake').value,WATCHDOG_USE_INETDETECT:q('#wd-inetdetect').checked?'1':'0',WATCHDOG_INETDETECT_MAX_AGE:q('#wd-inet-age').value};for(const [k,v] of Object.entries(pairs))c=kvSet(c,k,v);return saveSection('watchdog',{'watchdog-config':c});
    }
    if(section==='zram'){
      let c=files['zram-config']||'';c=kvSet(c,'ZRAM_MODE',q('#zram-mode').value);c=kvSet(c,'ZRAM_ALGO',q('#zram-algo').value);return saveSection('zram',{'zram-config':c});
    }
  }

  function downloadBlob(name,u,type='application/octet-stream'){const blob=new Blob([u],{type}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=name;document.body.appendChild(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);}
  async function exportDownload(kind){
    show('Готовлю '+kind+'…');try{const actionName=kind==='backup'?'backup-export':'diagnostics-export';const j=await call({action:actionName},'POST');downloadBlob(j.name||('ourfw-'+kind),b64urlToBytes(j.data||''),kind==='diagnostics'?'text/plain':'application/x-bzip2');show(kind==='backup'?'Backup скачан.':'Диагностика скачана.');}catch(e){show('Ошибка экспорта: '+e.message,true);}
  }
  async function uploadSpecial(target,file){if(!file)throw new Error('Сначала выбери файл');const u=new Uint8Array(await file.arrayBuffer());show('Загружаю '+file.name+' ('+u.length+' байт)…');const j=await uploadBytes(target,u,'file-commit');show('Пакет применён как кандидат. Проверь работу и подтверди.\n'+JSON.stringify(j,null,2));await status();}

  async function moduleAction(mod,op){
    const j=await action('module',mod,op);
    if(mod==='adblock'){loaded.delete('adblock');await ensureLoaded('adblock');}
    if(mod==='zram'){loaded.delete('zram');await ensureLoaded('zram');}
    return j;
  }

  document.addEventListener('click',async e=>{
    const t=e.target.closest('button');if(!t)return;
    try{
      if(t.dataset.tab){qa('.tab,.view').forEach(x=>x.classList.remove('active'));t.classList.add('active');const v=q('#'+t.dataset.tab);v.classList.add('active');await ensureLoaded(v.dataset.load);return;}
      if(t.dataset.action){await action(t.dataset.action);return;}
      if(t.dataset.module){await moduleAction(t.dataset.module,t.dataset.op||'status');return;}
      if(t.dataset.saveSection){await saveNamed(t.dataset.saveSection);return;}
      if(t.dataset.download){await exportDownload(t.dataset.download);return;}
    }catch(_){/* already shown */}
  });
  q('#refresh').addEventListener('click',status);
  q('#backup-file').addEventListener('change',e=>text('#backup-name',e.target.files[0]?e.target.files[0].name:''));
  q('#component-file').addEventListener('change',e=>text('#component-name',e.target.files[0]?e.target.files[0].name:''));
  q('#backup-restore').addEventListener('click',async()=>{try{await uploadSpecial('backup-import',q('#backup-file').files[0]);}catch(e){show('Restore: '+e.message,true);}});
  q('#component-install').addEventListener('click',async()=>{try{await uploadSpecial('component-package',q('#component-file').files[0]);}catch(e){show('Update: '+e.message,true);}});

  status();setInterval(status,15000);
})();
