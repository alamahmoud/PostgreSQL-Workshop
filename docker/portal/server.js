// Students MIS PostgreSQL Workshop — browser lab portal
//
// One small server, three jobs:
//   1. serve the single-page UI (public/)
//   2. manage lab containers over the Docker socket:
//        - build the lab image from /workshop on first start if missing
//        - create/start a server's container on demand
//        - stop / reset (remove) / report status incl. LAB_IS_READY
//   3. bridge browser WebSockets to `docker exec -u ubuntu bash` PTYs

'use strict';

const path = require('path');
const http = require('http');
const express = require('express');
const { WebSocketServer } = require('ws');
const Docker = require('dockerode');
const tar = require('tar-fs');

const PORT = process.env.PORT || 8080;
const LAB_IMAGE = process.env.LAB_IMAGE || 'studentsmis/pg-lab:1.0';
const LAB_NETWORK = process.env.LAB_NETWORK || 'studentsmis-labnet';
const WORKSHOP_DIR = process.env.WORKSHOP_DIR || '/workshop';

const docker = new Docker({ socketPath: '/var/run/docker.sock' });

// The three servers of the workshop. IPs match the CIDR the Lab 2 guide
// has students put into pg_hba.conf (172.28.5.0/24).
const SERVERS = {
  'lab1': {
    label: 'lab1', container: 'sm-lab1', role: 'lab1',
    lab: 'Lab 1 — Performance & Security',
    desc: 'Single server · studentsmis DB · sabotage pre-applied',
    ip: '172.28.5.20',
  },
  'pg-primary': {
    label: 'pg-primary', container: 'sm-pg-primary', role: 'lab2-primary',
    lab: 'Lab 2 — Disaster Recovery & Failover',
    desc: 'Primary · studentsmis_prod · the “Ubuntu Desktop” of the guide',
    ip: '172.28.5.10',
  },
  'pg-standby': {
    label: 'pg-standby', container: 'sm-pg-standby', role: 'lab2-standby',
    lab: 'Lab 2 — Disaster Recovery & Failover',
    desc: 'Standby · bare PostgreSQL · the “Ubuntu Console” of the guide',
    ip: '172.28.5.11',
  },
};

// ---------------------------------------------------------------- image build
let imageState = 'checking';       // checking | building | ready | error
let imageError = '';

async function ensureImage() {
  try {
    await docker.getImage(LAB_IMAGE).inspect();
    imageState = 'ready';
    console.log(`[portal] lab image ${LAB_IMAGE} present`);
    return;
  } catch (_) { /* fall through to build */ }

  imageState = 'building';
  console.log(`[portal] building ${LAB_IMAGE} from ${WORKSHOP_DIR} (first start only) ...`);
  const context = tar.pack(WORKSHOP_DIR, {
    ignore: (name) =>
      name.includes('/docker/portal') || name.endsWith('.docx') ||
      name.endsWith('.zip') || name.includes('/.git'),
  });
  try {
    const stream = await docker.buildImage(context, {
      t: LAB_IMAGE, dockerfile: 'docker/Dockerfile',
    });
    await new Promise((resolve, reject) => {
      docker.modem.followProgress(
        stream,
        (err, res) => {
          if (err) return reject(err);
          const last = res[res.length - 1] || {};
          if (last.error) return reject(new Error(last.error));
          resolve(res);
        },
        (ev) => { if (ev.stream && ev.stream.startsWith('Step')) console.log('[build]', ev.stream.trim()); }
      );
    });
    imageState = 'ready';
    console.log(`[portal] image ${LAB_IMAGE} built`);
  } catch (e) {
    imageState = 'error';
    imageError = e.message;
    console.error('[portal] image build failed:', e.message);
  }
}

async function ensureNetwork() {
  try { await docker.getNetwork(LAB_NETWORK).inspect(); }
  catch (_) {
    await docker.createNetwork({
      Name: LAB_NETWORK,
      IPAM: { Config: [{ Subnet: '172.28.5.0/24' }] },
    });
    console.log(`[portal] created network ${LAB_NETWORK}`);
  }
}

// ------------------------------------------------------------- container ops
function containerOf(id) {
  const s = SERVERS[id];
  if (!s) throw Object.assign(new Error(`unknown server '${id}'`), { status: 404 });
  return { s, c: docker.getContainer(s.container) };
}

async function inspectOrNull(c) {
  try { return await c.inspect(); }
  catch (e) { if (e.statusCode === 404) return null; throw e; }
}

async function ensureRunning(id) {
  const { s, c } = containerOf(id);
  let info = await inspectOrNull(c);
  if (!info) {
    if (imageState !== 'ready') {
      throw new Error(imageState === 'building'
        ? 'The lab image is still building — watch the banner, then try again.'
        : `Lab image not available (${imageState}${imageError ? ': ' + imageError : ''}).`);
    }
    await docker.createContainer({
      name: s.container,
      Image: LAB_IMAGE,
      Hostname: s.label,
      Env: [`LAB_ROLE=${s.role}`],
      HostConfig: { Init: true, ShmSize: 256 * 1024 * 1024, NetworkMode: LAB_NETWORK },
      NetworkingConfig: {
        EndpointsConfig: { [LAB_NETWORK]: { IPAMConfig: { IPv4Address: s.ip } } },
      },
    });
    info = await inspectOrNull(c);
  }
  if (!info.State.Running) await c.start();
  return c;
}

async function execCapture(c, cmd) {
  const exec = await c.exec({ Cmd: cmd, AttachStdout: true, AttachStderr: true });
  const stream = await exec.start({});
  await new Promise((res) => { stream.on('end', res); stream.on('error', res); stream.resume(); });
  const { ExitCode } = await exec.inspect();
  return ExitCode;
}

async function serverStatus(id) {
  const { s, c } = containerOf(id);
  const base = { id, label: s.label, lab: s.lab, desc: s.desc, ip: s.ip };
  const info = await inspectOrNull(c);
  if (!info) return { ...base, status: 'absent' };
  if (!info.State.Running) return { ...base, status: 'stopped' };
  try {
    const code = await execCapture(c, ['test', '-f', '/home/ubuntu/LAB_IS_READY']);
    return { ...base, status: code === 0 ? 'ready' : 'provisioning' };
  } catch (_) {
    return { ...base, status: 'provisioning' };
  }
}

// -------------------------------------------------------------------- express
const app = express();
app.use(express.static(path.join(__dirname, 'public')));
app.use('/vendor/xterm', express.static(path.join(__dirname, 'node_modules/@xterm/xterm')));
app.use('/vendor/addon-fit', express.static(path.join(__dirname, 'node_modules/@xterm/addon-fit')));

app.get('/api/state', async (_req, res) => {
  try {
    const servers = await Promise.all(Object.keys(SERVERS).map(serverStatus));
    res.json({ image: imageState, imageError, servers });
  } catch (e) {
    // Docker daemon unreachable — still render the rail, explain in banner.
    const servers = Object.entries(SERVERS).map(([id, s]) => ({
      id, label: s.label, lab: s.lab, desc: s.desc, ip: s.ip, status: 'unknown',
    }));
    res.json({ image: 'error', imageError: 'Docker unreachable: ' + e.message, servers });
  }
});

app.post('/api/servers/:id/start', async (req, res) => {
  try { await ensureRunning(req.params.id); res.json({ ok: true }); }
  catch (e) { res.status(e.status || 500).json({ error: e.message }); }
});

app.post('/api/servers/:id/stop', async (req, res) => {
  try {
    const { c } = containerOf(req.params.id);
    const info = await inspectOrNull(c);
    if (info && info.State.Running) await c.stop({ t: 10 });
    res.json({ ok: true });
  } catch (e) { res.status(e.status || 500).json({ error: e.message }); }
});

app.post('/api/servers/:id/reset', async (req, res) => {
  try {
    const { c } = containerOf(req.params.id);
    const info = await inspectOrNull(c);
    if (info) await c.remove({ force: true });
    res.json({ ok: true });
  } catch (e) { res.status(e.status || 500).json({ error: e.message }); }
});

// ------------------------------------------------------------------ terminals
const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: '/term' });

wss.on('connection', async (ws, req) => {
  const id = new URL(req.url, 'http://x').searchParams.get('server');
  const send = (o) => { try { ws.send(JSON.stringify(o)); } catch (_) {} };
  try {
    send({ type: 'status', text: `Connecting to ${id} ...` });
    const c = await ensureRunning(id);
    const exec = await c.exec({
      Cmd: ['bash', '-l'],
      User: 'ubuntu',
      WorkingDir: '/home/ubuntu',
      Env: ['TERM=xterm-256color'],
      Tty: true, AttachStdin: true, AttachStdout: true, AttachStderr: true,
    });
    const stream = await exec.start({ hijack: true, stdin: true, Tty: true });
    send({ type: 'ready' });

    stream.on('data', (buf) => { if (ws.readyState === 1) ws.send(buf); });
    stream.on('end', () => ws.close());
    stream.on('error', () => ws.close());

    ws.on('message', (msg, isBinary) => {
      if (isBinary) return stream.write(msg);
      let m; try { m = JSON.parse(msg.toString()); } catch { return stream.write(msg); }
      if (m.type === 'input') stream.write(m.data);
      else if (m.type === 'resize') exec.resize({ h: m.rows, w: m.cols }).catch(() => {});
    });
    ws.on('close', () => { try { stream.end(); } catch (_) {} });
  } catch (e) {
    send({ type: 'error', text: e.message });
    ws.close();
  }
});

// --------------------------------------------------------------------- start
(async () => {
  try { await ensureNetwork(); } catch (e) { console.error('[portal] network:', e.message); }
  ensureImage();   // async on purpose — UI shows build status meanwhile
  server.listen(PORT, () => console.log(`[portal] http://localhost:${PORT}`));
})();
