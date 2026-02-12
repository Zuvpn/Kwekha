let TOKEN = localStorage.getItem('kwekha_token') || '';
let refreshTimer = null;
let statsTimer = null;

const SCHEMES = [
  {v:"relay+wss", label:"⭐ relay+wss (Recommended)"},
  {v:"relay+ws", label:"⭐ relay+ws"},
  {v:"tunnel+tcp", label:"tunnel+tcp (Simple)"},
  {v:"relay+tcp", label:"relay+tcp"},
  {v:"relay+tls", label:"relay+tls"},
];

function qs(id){ return document.getElementById(id); }
function setOut(x){ qs('out').textContent = (typeof x === 'string') ? x : JSON.stringify(x, null, 2); }
function toast(msg, ms=2500){
  const el = qs('toast'); el.textContent = msg; el.classList.remove('hidden');
  clearTimeout(el._t); el._t = setTimeout(()=>el.classList.add('hidden'), ms);
}

async function api(path, opts={}){
  opts.headers = opts.headers || {};
  if (TOKEN) opts.headers['Authorization'] = 'Bearer ' + TOKEN;
  if (opts.json){
    opts.headers['Content-Type'] = 'application/json';
    opts.body = JSON.stringify(opts.json);
    delete opts.json;
  }
  const res = await fetch(path, opts);
  const txt = await res.text();
  if (!res.ok) throw new Error(txt || res.statusText);
  try { return JSON.parse(txt); } catch { return txt; }
}

function showLogin(){
  qs('loginCard').classList.remove('hidden');
  qs('appShell').classList.add('hidden');
}
function showApp(){
  qs('loginCard').classList.add('hidden');
  qs('appShell').classList.remove('hidden');
}

function setActiveTab(tab){
  document.querySelectorAll('.tab').forEach(b=>b.classList.remove('active'));
  document.querySelector(`.tab[data-tab="${tab}"]`).classList.add('active');
  document.querySelectorAll('.tabpane').forEach(p=>p.classList.add('hidden'));
  qs(`tab-${tab}`).classList.remove('hidden');

  if (tab === 'services') loadServices();
  if (tab === 'stats') loadStats();
  if (tab === 'settings') loadSettings();
}

async function loadHealth(){
  try{
    const h = await api('/api/health');
    qs('healthBadge').textContent = 'OK • ' + h.bind;
    qs('healthBadge').style.color='#9aa7b2';
  }catch{
    qs('healthBadge').textContent='OFFLINE';
    qs('healthBadge').style.color='#ff453a';
  }
}

function statusClass(s){
  s=(s||'').toLowerCase();
  if (s.includes('active')) return 'active';
  if (s.includes('failed')) return 'failed';
  return 'inactive';
}

async function loadServices(){
  await loadHealth();
  if (refreshTimer) clearInterval(refreshTimer);
  const v=parseInt(qs('refreshSel').value,10);
  if (v>0) refreshTimer=setInterval(loadServices, v*1000);

  try{
    const data = await api('/api/services');
    const body = qs('svcBody'); body.innerHTML='';
    (data.services||[]).forEach(s=>{
      const tr=document.createElement('tr');
      tr.innerHTML = `
        <td><b>${s.name}</b><div class="muted small">${s.unit}</div></td>
        <td class="status ${statusClass(s.active)}">${s.active}</td>
        <td>${s.enabled}</td>
        <td>
          <button class="btn" data-a="start">Start</button>
          <button class="btn" data-a="stop">Stop</button>
          <button class="btn" data-a="restart">Restart</button>
        </td>
        <td>
          <button class="btn" data-i="status">Status</button>
          <button class="btn" data-i="logs">Logs</button>
        </td>`;
      tr.querySelectorAll('button[data-a]').forEach(btn=>{
        btn.onclick = async ()=>{
          const a=btn.getAttribute('data-a');
          try{ setOut(await api(`/api/service/action?name=${encodeURIComponent(s.name)}&action=${a}`, {method:'POST'}));
            toast(`✅ ${s.name}: ${a}`); await loadServices();
          }catch(e){ setOut(String(e)); toast('❌ '+e); }
        };
      });
      tr.querySelectorAll('button[data-i]').forEach(btn=>{
        btn.onclick = async ()=>{
          const k=btn.getAttribute('data-i');
          try{
            if (k==='status') setOut(await api(`/api/service/status?name=${encodeURIComponent(s.name)}`));
            else setOut(await api(`/api/service/logs?name=${encodeURIComponent(s.name)}&lines=200`));
          }catch(e){ setOut(String(e)); toast('❌ '+e); }
        };
      });
      body.appendChild(tr);
    });
    if (!data.services || data.services.length===0){
      body.innerHTML = `<tr><td colspan="5" class="muted">No gost-kwekha-* services found.</td></tr>`;
    }
    setOut(data);
  }catch(e){
    setOut(String(e)); toast('❌ '+e); showLogin();
  }
}

function genUUID(){
  // client-side UUID v4
  const b = crypto.getRandomValues(new Uint8Array(16));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  const h=[...b].map(x=>x.toString(16).padStart(2,'0')).join('');
  return `${h.slice(0,8)}-${h.slice(8,12)}-${h.slice(12,16)}-${h.slice(16,20)}-${h.slice(20)}`;
}

function createReqFromForm(){
  return {
    name: qs('c_name').value.trim(),
    role: qs('c_role').value,
    scheme: qs('c_scheme').value,
    peer: qs('c_peer').value.trim(),
    ports_csv: qs('c_ports').value.trim(),
    dest_mode: qs('c_destmode').value,
    dest_host: qs('c_desthost').value.trim(),
    tunnel_id: qs('c_tid').value.trim(),
  };
}

async function previewCreate(){
  try{
    const plan = await api('/api/tunnel/preview', {method:'POST', json: createReqFromForm()});
    qs('createPreview').textContent = JSON.stringify(plan, null, 2);
    setOut(plan);
    return plan;
  }catch(e){
    qs('createPreview').textContent = String(e);
    setOut(String(e));
    throw e;
  }
}

async function doCreate(){
  try{
    const plan = await api('/api/tunnel/create', {method:'POST', json: createReqFromForm()});
    qs('createPreview').textContent = JSON.stringify(plan, null, 2);
    setOut(plan);
    toast('✅ Created & Started');
    setActiveTab('services');
  }catch(e){
    setOut(String(e));
    toast('❌ '+e);
  }
}

async function loadStats(){
  await loadHealth();
  if (statsTimer) clearInterval(statsTimer);
  const v=parseInt(qs('statsSel').value,10);
  if (v>0) statsTimer=setInterval(loadStats, v*1000);

  try{
    const st = await api('/api/stats');
    qs('cpuVal').textContent = (st.cpu_percent||0).toFixed(1) + '%';
    qs('ramVal').textContent = `${st.mem_used_mb} / ${st.mem_total_mb} MB`;
    qs('netVal').textContent = `RX ${st.net_rx_mb.toFixed(1)} MB • TX ${st.net_tx_mb.toFixed(1)} MB`;
    qs('connVal').textContent = String(st.connections);
    qs('statsRaw').textContent = JSON.stringify(st, null, 2);
    setOut(st);
  }catch(e){
    setOut(String(e));
    toast('❌ '+e);
  }
}

async function loadSettings(){
  await loadHealth();
  try{
    const g = await api('/api/healthcheck/get');
    qs('hcSel').value = String(g.interval_min || 0);
    qs('settingsOut').textContent = JSON.stringify(g, null, 2);
    setOut(g);
  }catch(e){
    setOut(String(e)); toast('❌ '+e);
  }
}

async function saveSettings(){
  try{
    const v = parseInt(qs('hcSel').value,10);
    const res = await api('/api/healthcheck/set', {method:'POST', json:{interval_min:v}});
    qs('settingsOut').textContent = JSON.stringify(res, null, 2);
    setOut(res);
    toast('✅ Saved');
  }catch(e){
    setOut(String(e)); toast('❌ '+e);
  }
}

async function runHealthCheckNow(){
  try{
    const res = await api('/api/healthcheck/run', {method:'POST'});
    setOut(res);
    toast('✅ Started healthcheck');
  }catch(e){
    setOut(String(e)); toast('❌ '+e);
  }
}

function init(){
  // tabs
  document.querySelectorAll('.tab').forEach(btn=>{
    btn.onclick = ()=> setActiveTab(btn.getAttribute('data-tab'));
  });

  // login
  qs('logoutBtn').onclick=()=>{ TOKEN=''; localStorage.removeItem('kwekha_token'); toast('Logged out'); showLogin(); };
  qs('loginBtn').onclick=()=>{ const v=qs('tokenInput').value.trim(); if(!v) return toast('Token required');
    TOKEN=v; localStorage.setItem('kwekha_token', TOKEN); toast('✅ Token saved'); showApp(); setActiveTab('services'); };
  qs('refreshBtn').onclick=loadServices;
  qs('refreshSel').onchange=loadServices;

  // create
  SCHEMES.forEach(s=>{
    const o=document.createElement('option');
    o.value=s.v; o.textContent=s.label;
    qs('c_scheme').appendChild(o);
  });
  qs('c_destmode').onchange=()=>{
    if (qs('c_destmode').value === 'remote') qs('destHostWrap').classList.remove('hidden');
    else qs('destHostWrap').classList.add('hidden');
  };
  qs('genTidBtn').onclick=()=>{ qs('c_tid').value = genUUID(); toast('UUID generated'); };
  qs('previewBtn').onclick=previewCreate;
  qs('createBtn').onclick=doCreate;
  qs('copyPreviewBtn').onclick=async()=>{ try{ await navigator.clipboard.writeText(qs('createPreview').textContent); toast('Copied'); }catch{ toast('Copy failed'); } };

  // stats
  qs('statsBtn').onclick=loadStats;
  qs('statsSel').onchange=loadStats;

  // settings
  qs('saveHcBtn').onclick=saveSettings;
  qs('runHcBtn').onclick=runHealthCheckNow;

  // output copy
  qs('copyOutBtn').onclick=async()=>{ try{ await navigator.clipboard.writeText(qs('out').textContent); toast('Copied'); }catch{ toast('Copy failed'); } };

  if (TOKEN){
    showApp();
    setActiveTab('services');
  } else {
    showLogin();
  }
  loadHealth();
}
init();
