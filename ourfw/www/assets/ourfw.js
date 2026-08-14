(function(){
  const q=(s)=>document.querySelector(s), out=q('#result');
  const text=(id,v)=>{const e=q(id);if(e)e.textContent=v};
  async function call(params, method='GET'){
    const body=new URLSearchParams(params);
    const opt={cache:'no-store'};
    let url='/ourfw_api.cgi';
    if(method==='POST'){opt.method='POST';opt.headers={'Content-Type':'application/x-www-form-urlencoded'};opt.body=body.toString();}
    else url+='?'+body.toString();
    const r=await fetch(url,opt); return r.json();
  }
  async function status(){
    try{
      const j=await call({action:'status'});
      if(j.error)throw new Error(j.error);
      text('#version',j.version||'dev'); text('#wan',j.wan_if||'—');
      text('#vpn',j.vpn_enabled?(j.vpn_up?'работает':'включён / tunnel down'):'выключен');
      text('#nfqws',j.nfqws_enabled?(j.nfqws_up?'работает':'включён / process down'):'выключен');
      text('#pending',j.pending?'ЖДЁТ подтверждения':'нет'); text('#routing-mode',j.routing_mode||'—');
    }catch(e){out.textContent='API недоступен: '+e.message;}
  }
  async function action(name,p1='',p2=''){
    out.textContent='Выполняю: '+name+'…';
    try{const j=await call({action:name,p1,p2},'POST');out.textContent=JSON.stringify(j,null,2);setTimeout(status,500);}
    catch(e){out.textContent='Ошибка: '+e.message;}
  }
  document.addEventListener('click',e=>{
    const t=e.target.closest('button'); if(!t)return;
    if(t.dataset.tab){document.querySelectorAll('.tab,.view').forEach(x=>x.classList.remove('active'));t.classList.add('active');q('#'+t.dataset.tab).classList.add('active');return;}
    if(t.dataset.action) action(t.dataset.action);
    if(t.dataset.module) action('module',t.dataset.module,t.dataset.op||'status');
  });
  q('#refresh').addEventListener('click',status); status(); setInterval(status,15000);
})();
