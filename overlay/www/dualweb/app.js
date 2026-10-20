const $=id=>document.getElementById(id);let wanPending=false;
async function api(path,opts={}){const r=await fetch('/api/'+path,{credentials:'same-origin',...opts,headers:{'Content-Type':'application/json',...(opts.headers||{})}});let d={};try{d=await r.json()}catch{}if(!r.ok)throw new Error(d.error||('HTTP '+r.status));return d}
function msg(id,text,error=false){$(id).textContent=text;$(id).classList.toggle('error',error)}function toast(t){$('toast').textContent=t;$('toast').style.display='block';setTimeout(()=>$('toast').style.display='none',3500)}
async function loginCheck(){try{await api('status');$('loginCard').hidden=true;$('app').hidden=false;await refreshAll()}catch{$('loginCard').hidden=false;$('app').hidden=true}}
$('loginForm').addEventListener('submit',async e=>{e.preventDefault();msg('loginMsg','正在登录…');try{await api('login',{method:'POST',body:JSON.stringify({password:$('password').value})});$('password').value='';await loginCheck()}catch(e){msg('loginMsg',e.message,true)}});
$('logout').onclick=async()=>{try{await api('logout',{method:'POST',body:'{}'})}catch{}location.reload()};
async function refreshStatus(){const s=await api('status');$('uptime').textContent=s.uptime||'—';$('hostname').textContent=(s.hostname||'ImmortalWrt')+' · '+(s.version||'');$('cpu').textContent=s.cpu||'—';$('memory').textContent=s.memory||'—';$('memDetail').textContent=s.memDetail||'';$('wanStatus').textContent=s.wan?.up?'在线':'未连接';$('wanAddress').textContent=s.wan?.ip||'未获取 IP';if(s.wan?.proto){$('proto').value=s.wan.proto;toggleProto()}if(s.wan?.username)$('username').value=s.wan.username;if(s.wan?.ipaddr)$('ipaddr').value=s.wan.ipaddr;if(s.wan?.netmask)$('netmask').value=s.wan.netmask;if(s.wan?.gateway)$('gateway').value=s.wan.gateway;if(s.wan?.dns)$('dns').value=s.wan.dns.join(', ')}
async function refreshAll(){try{await refreshStatus()}catch(e){toast(e.message)}}
function toggleProto(){const p=$('proto').value;document.querySelectorAll('.pppoe').forEach(x=>x.hidden=p!=='pppoe');document.querySelectorAll('.static').forEach(x=>x.hidden=p!=='static')}$('proto').onchange=toggleProto;
$('wanForm').addEventListener('submit',async e=>{e.preventDefault();if(!confirm('将修改 WAN 并重载网络。若 120 秒内没有确认，系统会尝试自动恢复旧配置。继续？'))return;const p=$('proto').value;const data={proto:p,dns:$('dns').value};if(p==='pppoe'){data.username=$('username').value;data.password=$('wanPassword').value}else if(p==='static'){data.ipaddr=$('ipaddr').value;data.netmask=$('netmask').value;data.gateway=$('gateway').value}try{const d=await api('wan/apply',{method:'POST',body:JSON.stringify(data)});wanPending=true;$('confirmWan').hidden=false;msg('wanMsg','配置已应用。请确认管理连接正常；120 秒后未确认将自动回滚。回滚 ID：'+d.rollbackId);toast('WAN 已应用，等待确认')}catch(e){msg('wanMsg',e.message,true)}});
$('confirmWan').onclick=async()=>{try{await api('wan/confirm',{method:'POST',body:'{}'});wanPending=false;$('confirmWan').hidden=true;msg('wanMsg','已确认，自动回滚已取消。');toast('WAN 配置已确认')}catch(e){msg('wanMsg',e.message,true)}};
function showWebSection(which){
 const router=which==='router',zash=which==='zashboard',openbox=which==='openbox';
 $('routerControls').hidden=!router;
 $('zashboardPanel').hidden=!zash;
 $('openBoxPanel').hidden=!openbox;
 $('showRouter').classList.toggle('primary',router);
 $('showZashboard').classList.toggle('primary',zash);
 $('showOpenBox').classList.toggle('primary',openbox);
 if(zash){const frame=$('zashboardFrame');if(!frame.dataset.loaded){const port=location.port||(location.protocol==='https:'?'443':'80');const query='hostname='+encodeURIComponent(location.hostname)+'&port='+encodeURIComponent(port)+'&secondaryPath='+encodeURIComponent('/clash');frame.src='/zashboard/#/setup?'+query;frame.dataset.loaded='1';}}
 if(openbox){const frame=$('openBoxFrame');if(!frame.dataset.loaded){frame.src='/openbox/';frame.dataset.loaded='1';}}
}
$('showRouter').addEventListener('click',()=>showWebSection('router'));
$('showZashboard').addEventListener('click',()=>showWebSection('zashboard'));
$('showOpenBox').addEventListener('click',()=>showWebSection('openbox'));
$('reloadZashboard').addEventListener('click',()=>{const frame=$('zashboardFrame');if(frame.src)frame.src=frame.src});
$('reloadOpenBox').addEventListener('click',()=>{const frame=$('openBoxFrame');if(frame.src)frame.src=frame.src});
async function runConnectivity(){const b=$('runConnectivity');b.disabled=true;b.textContent='测试中…';msg('connectivityMsg','正在由路由器测试阿里云、Google、GitHub 和 Telegram…');try{const d=await api('connectivity');const grid=$('connectivityGrid');grid.innerHTML='';(d.results||[]).forEach(r=>{const card=document.createElement('article');card.className='probe-card '+(r.ok?'online':'offline');const top=document.createElement('div');top.className='probe-top';const name=document.createElement('strong');name.textContent=r.name;const state=document.createElement('span');state.className='probe-state';state.textContent=r.ok?'可连接':'失败';top.append(name,state);const latency=document.createElement('div');latency.className='probe-latency';latency.textContent=r.ok?(r.latencyMs+' ms'):'—';const status=document.createElement('div');status.className='probe-meta';status.textContent='HTTP：'+(r.status||'无响应');const ip=document.createElement('div');ip.className='probe-meta';ip.textContent='目标 IP：'+(r.targetIP||'未获取');card.append(top,latency,status,ip);if(r.error){const err=document.createElement('div');err.className='probe-meta probe-error';err.textContent=r.error;card.append(err)}grid.append(card)});msg('connectivityMsg','测试完成 · '+(d.checkedAt||''));}catch(e){msg('connectivityMsg','测试失败：'+e.message,true)}finally{b.disabled=false;b.textContent='重新测试'}}
$('runConnectivity').addEventListener('click',runConnectivity);
$('passwordForm').addEventListener('submit',async e=>{e.preventDefault();try{await api('password/change',{method:'POST',body:JSON.stringify({old:$('oldPassword').value,new:$('newPassword').value})});$('oldPassword').value='';$('newPassword').value='';msg('passwordMsg','密码已更新，请妥善保管。');toast('首页密码已更新')}catch(e){msg('passwordMsg',e.message,true)}});
loginCheck();setInterval(()=>{if(!$('app').hidden)refreshStatus().catch(()=>{})},10000);
