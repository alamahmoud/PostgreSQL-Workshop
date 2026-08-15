/* CarvedRock lab portal — frontend */
'use strict';

const rail = document.getElementById('rail');
const tabsEl = document.getElementById('tabs');
const panesEl = document.getElementById('panes');
const emptyEl = document.getElementById('empty');
const banner = document.getElementById('imgbanner');

const STATUS_TXT = {
  absent: 'not created', stopped: 'stopped',
  provisioning: 'provisioning', ready: 'ready', unknown: 'unknown',
};

let state = { image: 'checking', servers: [] };
const terms = new Map();   // tabId -> {term, fit, ws, serverId}
let tabSeq = 0;

/* ------------------------------------------------------------- rail render */
function render() {
  // image build banner
  if (state.image === 'building') {
    banner.style.display = 'block'; banner.classList.remove('error');
    banner.textContent = 'Building the lab image (first start only, a few minutes) — servers unlock when it finishes.';
  } else if (state.image === 'error') {
    banner.style.display = 'block'; banner.classList.add('error');
    banner.textContent = 'Lab image build failed: ' + (state.imageError || 'see portal logs (docker compose logs portal)');
  } else banner.style.display = 'none';

  const groups = {};
  for (const s of state.servers) (groups[s.lab] ||= []).push(s);

  rail.innerHTML = '';
  for (const [lab, servers] of Object.entries(groups)) {
    const g = document.createElement('div'); g.className = 'labgroup';
    const h = document.createElement('h2'); h.textContent = lab; g.appendChild(h);
    for (const s of servers) g.appendChild(card(s));
    rail.appendChild(g);
  }
}

function card(s) {
  const el = document.createElement('div'); el.className = 'server';
  el.innerHTML = `
    <div class="row1">
      <span class="led ${s.status}"></span>
      <span class="name">${s.label}</span>
      <span class="st">${STATUS_TXT[s.status] || s.status}</span>
    </div>
    <div class="prompt">ubuntu@${s.label}:~$ &nbsp;·&nbsp; ${s.ip}</div>
    <div class="desc">${s.desc}</div>
    <div class="acts"></div>`;
  const acts = el.querySelector('.acts');

  const open = btn('Open terminal', 'primary', () => openTerminal(s.id));
  open.disabled = state.image !== 'ready' && s.status === 'absent';
  acts.appendChild(open);

  if (s.status === 'ready' || s.status === 'provisioning') {
    acts.appendChild(btn('Stop', '', () => act(s.id, 'stop')));
  }
  if (s.status !== 'absent') {
    acts.appendChild(btn('Reset', '', () => {
      if (confirm(`Reset ${s.label}? The container is removed and rebuilt pristine on next open.`))
        act(s.id, 'reset');
    }));
  }
  if (s.status === 'stopped') acts.appendChild(btn('Start', '', () => act(s.id, 'start')));
  return el;
}

function btn(txt, cls, fn) {
  const b = document.createElement('button');
  b.textContent = txt; if (cls) b.className = cls;
  b.addEventListener('click', fn); return b;
}

async function act(id, action) {
  try {
    const r = await fetch(`/api/servers/${id}/${action}`, { method: 'POST' });
    if (!r.ok) alert((await r.json()).error || `${action} failed`);
  } catch (e) { alert(e.message); }
  poll();
}

/* --------------------------------------------------------------- terminals */
function openTerminal(serverId) {
  const tabId = 't' + (++tabSeq);

  const tab = document.createElement('div');
  tab.className = 'tab'; tab.dataset.tab = tabId;
  tab.innerHTML = `<span>${serverId}</span><span class="x" title="Close">✕</span>`;
  tab.addEventListener('click', () => activate(tabId));
  tab.querySelector('.x').addEventListener('click', (e) => { e.stopPropagation(); closeTab(tabId); });
  tabsEl.appendChild(tab);

  const pane = document.createElement('div');
  pane.className = 'pane'; pane.dataset.pane = tabId;
  pane.innerHTML = '<div class="term"></div>';
  panesEl.appendChild(pane);

  const term = new Terminal({
    fontFamily: "ui-monospace,'Cascadia Mono','JetBrains Mono',Menlo,Consolas,monospace",
    fontSize: 14, cursorBlink: true, scrollback: 8000,
    theme: {
      background: '#0e141b', foreground: '#d8dfe8', cursor: '#5b9dd9',
      selectionBackground: '#33679155',
    },
  });
  const fit = new FitAddon.FitAddon();
  term.loadAddon(fit);
  term.open(pane.querySelector('.term'));

  const proto = location.protocol === 'https:' ? 'wss' : 'ws';
  const ws = new WebSocket(`${proto}://${location.host}/term?server=${serverId}`);
  ws.binaryType = 'arraybuffer';

  ws.onmessage = (ev) => {
    if (typeof ev.data === 'string') {
      try {
        const m = JSON.parse(ev.data);
        if (m.type === 'status') term.writeln(`\x1b[38;5;110m${m.text}\x1b[0m`);
        else if (m.type === 'error') term.writeln(`\x1b[38;5;203m${m.text}\x1b[0m`);
        else if (m.type === 'ready') { fit.fit(); sendResize(); }
        return;
      } catch (_) { term.write(ev.data); return; }
    }
    term.write(new Uint8Array(ev.data));
  };
  ws.onclose = () => term.writeln('\r\n\x1b[38;5;110m[session closed — close this tab, or open a new terminal]\x1b[0m');

  term.onData((d) => { if (ws.readyState === 1) ws.send(JSON.stringify({ type: 'input', data: d })); });
  const sendResize = () => {
    if (ws.readyState === 1) ws.send(JSON.stringify({ type: 'resize', cols: term.cols, rows: term.rows }));
  };
  term.onResize(sendResize);

  terms.set(tabId, { term, fit, ws, serverId });
  activate(tabId);
  poll();
}

function activate(tabId) {
  document.querySelectorAll('.tab').forEach(t => t.classList.toggle('active', t.dataset.tab === tabId));
  document.querySelectorAll('.pane').forEach(p => p.classList.toggle('active', p.dataset.pane === tabId));
  emptyEl.style.display = 'none';
  const t = terms.get(tabId);
  if (t) requestAnimationFrame(() => { t.fit.fit(); t.term.focus(); });
}

function closeTab(tabId) {
  const t = terms.get(tabId);
  if (t) { try { t.ws.close(); } catch (_) {} t.term.dispose(); terms.delete(tabId); }
  document.querySelector(`.tab[data-tab="${tabId}"]`)?.remove();
  document.querySelector(`.pane[data-pane="${tabId}"]`)?.remove();
  const last = [...terms.keys()].pop();
  if (last) activate(last); else emptyEl.style.display = 'flex';
}

window.addEventListener('resize', () => {
  for (const t of terms.values()) if (t) { t.fit.fit(); }
});

/* ----------------------------------------------------------------- polling */
async function poll() {
  try {
    const r = await fetch('/api/state');
    if (r.ok) { state = await r.json(); render(); }
  } catch (_) { /* portal restarting; keep last view */ }
}
poll();
setInterval(poll, 3000);
