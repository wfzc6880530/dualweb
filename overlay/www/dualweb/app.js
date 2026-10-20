const $=id=>document.getElementById(id);let wanPending=false;const base=location.protocol+'//'+location.hostname;
$('luciLink').href=base+':8080/';$('luciButton').href=base+':8080/';$('openBoxLink').href=base+':8080/cgi-bin/luci/admin/services/openbox';$('openBoxLink').target='_blank';$('openBoxLink').rel='noopener';
async function api(path,opts={}){const r=await fetch('/api/'+path,{credentials:'same-origin',...opts,headers:{'Content-Type':'application/json',...(opts.headers||{})}});let d={};try{d=await r.json()}catch{}if(!r.ok)throw new Error(d.error||('HTTP '+r.status));return d}
function msg(id,text,error=false){$(id).textContent=text;$(id).classList.toggle('error',error)}function toast(t){$('toast').textContent=t;$('toast').style.display='block';setTimeout(()=>$('toast').style.display='none',3500)}
async function loginCheck(){try{await api('status');$('loginCard').hidden=true;$('app').hidden=false;await refreshAll()}catch{$('loginCard').hidden=false;$('app').hidden=true}}
$('loginForm').addEventListener('submit',async e=>{e.preventDefault();msg('loginMsg','正在登录…');try{await api('login',{method:'POST',body:JSON.stringify({password:$('password').value})});$('password').value='';await loginCheck()}catch(e){msg('loginMsg',e.message,true)}});
$('logout').onclick=async()=>{try{await api('logout',{method:'POST',body:'{}'})}catch{}location.reload()};
async function refreshStatus(){const s=await api('status');$('uptime').textContent=s.uptime||'—';$('hostname').textContent=(s.hostname||'ImmortalWrt')+' · '+(s.version||'');$('cpu').textContent=s.cpu||'—';$('memory').textContent=s.memory||'—';$('memDetail').textContent=s.memDetail||'';$('wanStatus').textContent=s.wan?.up?'在线':'未连接';$('wanAddress').textContent=s.wan?.ip||'未获取 IP';$('proxyPill').textContent=s.nikki?'Nikki 运行中':'Nikki 已停止';$('proxyPill').style.color=s.nikki?'var(--green)':'var(--muted)';if(s.wan?.proto){$('proto').value=s.wan.proto;toggleProto()}if(s.wan?.username)$('username').value=s.wan.username;if(s.wan?.ipaddr)$('ipaddr').value=s.wan.ipaddr;if(s.wan?.netmask)$('netmask').value=s.wan.netmask;if(s.wan?.gateway)$('gateway').value=s.wan.gateway;if(s.wan?.dns)$('dns').value=s.wan.dns.join(', ')}
async function refreshNodes(){try{const d=await api('proxies');const sel=$('group');const prev=sel.value;sel.innerHTML='';(d.groups||[]).forEach(g=>{let o=document.createElement('option');o.value=g.name;o.textContent=g.name+(g.now?' · '+g.now:'');sel.append(o)});if(prev)sel.value=prev;await loadNodes()}catch(e){msg('proxyMsg','读取 Mihomo 失败：'+e.message+'。请在 Nikki 生效配置中启用本机控制器 127.0.0.1:9090。',true)}}
async function loadNodes(){const g=$('group').value;if(!g)return;try{const d=await api('proxies/'+encodeURIComponent(g));$('node').innerHTML='';(d.all||[]).forEach(n=>{let o=document.createElement('option');o.value=n;o.textContent=n+(n===d.now?' · 当前':'');$('node').append(o)});if(d.now)$('node').value=d.now}catch(e){msg('proxyMsg',e.message,true)}}
async function refreshAll(){try{await refreshStatus()}catch(e){toast(e.message)}await refreshNodes()}
$('group').onchange=loadNodes;$('refreshNodes').onclick=refreshNodes;
$('selectNode').onclick=async()=>{try{await api('select',{method:'POST',body:JSON.stringify({group:$('group').value,node:$('node').value})});msg('proxyMsg','节点已切换');await refreshNodes()}catch(e){msg('proxyMsg',e.message,true)}};
for(const [id,action] of [['proxyStart','start'],['proxyStop','stop'],['proxyRestart','restart']])$(id).onclick=async()=>{try{await api('proxy/'+action,{method:'POST',body:'{}'});msg('proxyMsg','已执行 '+action);await refreshStatus()}catch(e){msg('proxyMsg',e.message,true)}};
function toggleProto(){const p=$('proto').value;document.querySelectorAll('.pppoe').forEach(x=>x.hidden=p!=='pppoe');document.querySelectorAll('.static').forEach(x=>x.hidden=p!=='static')}$('proto').onchange=toggleProto;
$('wanForm').addEventListener('submit',async e=>{e.preventDefault();if(!confirm('将修改 WAN 并重载网络。若 120 秒内没有确认，系统会尝试自动恢复旧配置。继续？'))return;const p=$('proto').value;const data={proto:p,dns:$('dns').value};if(p==='pppoe'){data.username=$('username').value;data.password=$('wanPassword').value}else if(p==='static'){data.ipaddr=$('ipaddr').value;data.netmask=$('netmask').value;data.gateway=$('gateway').value}try{const d=await api('wan/apply',{method:'POST',body:JSON.stringify(data)});wanPending=true;$('confirmWan').hidden=false;msg('wanMsg','配置已应用。请确认管理连接正常；120 秒后未确认将自动回滚。回滚 ID：'+d.rollbackId);toast('WAN 已应用，等待确认')}catch(e){msg('wanMsg',e.message,true)}});
$('confirmWan').onclick=async()=>{try{await api('wan/confirm',{method:'POST',body:'{}'});wanPending=false;$('confirmWan').hidden=true;msg('wanMsg','已确认，自动回滚已取消。');toast('WAN 配置已确认')}catch(e){msg('wanMsg',e.message,true)}};
function showWebSection(which){
 const router=which==='router';
 $('routerControls').hidden=!router;
 $('zashboardPanel').hidden=router;
 $('showRouter').classList.toggle('primary',router);
 $('showZashboard').classList.toggle('primary',!router);
 if(!router){
  const frame=$('zashboardFrame');
  if(!frame.dataset.loaded){
   const port=location.port || (location.protocol==='https:'?'443':'80');
   const query='hostname='+encodeURIComponent(location.hostname)+'&port='+encodeURIComponent(port)+'&secondaryPath='+encodeURIComponent('/clash');
   frame.src='/zashboard/#/setup?'+query;
   frame.dataset.loaded='1';
  }
 }
}
$('showRouter').addEventListener('click',()=>showWebSection('router'));
$('showZashboard').addEventListener('click',()=>showWebSection('zashboard'));
$('reloadZashboard').addEventListener('click',()=>{
 const frame=$('zashboardFrame');
 if(frame.src) frame.src=frame.src;
});
loginCheck();setInterval(()=>{if(!$('app').hidden)refreshStatus().catch(()=>{})},10000);

$('passwordForm').addEventListener('submit',async e=>{e.preventDefault();try{await api('password/change',{method:'POST',body:JSON.stringify({old:$('oldPassword').value,new:$('newPassword').value})});$('oldPassword').value='';$('newPassword').value='';msg('passwordMsg','密码已更新，请妥善保管。');toast('首页密码已更新')}catch(e){msg('passwordMsg',e.message,true)}});
