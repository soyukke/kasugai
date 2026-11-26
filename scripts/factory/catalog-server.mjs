#!/usr/bin/env node
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import { dirname, extname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const WORK_ROOT = process.env.KASUGAI_FACTORY_WORK_DIR || join(os.homedir(), 'Library/Application Support/Kasugai/factory');
const GENERATED_FACTORIES_DIR = join(WORK_ROOT, 'generated-factories');
const KASUGAI_BLUEPRINTS_DIR = join(
  os.homedir(),
  'Library/Application Support/Kasugai/factory/blueprints'
);

const args = process.argv.slice(2);
const runDir = resolve(args[0] || '.');
const port = Number(args[1] || '0');
const tracePath = join(runDir, 'trace.json');
const catalogJsonPath = join(runDir, 'catalog.json');
const adoptedJsonPath = join(runDir, 'adopted.json');

function readJsonSafe(p, fallback) {
  try {
    return JSON.parse(readFileSync(p, 'utf8'));
  } catch {
    return fallback;
  }
}

function writeJson(p, obj) {
  mkdirSync(dirname(p), { recursive: true });
  writeFileSync(p, JSON.stringify(obj, null, 2) + '\n', 'utf8');
}

function appendTraceLog(msg) {
  if (!existsSync(tracePath)) return;
  try {
    const tr = JSON.parse(readFileSync(tracePath, 'utf8'));
    const d = new Date();
    const pad = (n) => String(n).padStart(2, '0');
    const stamp = `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
    tr.logs = tr.logs || [];
    tr.logs.push(`[${stamp}] ${msg}`);
    tr.updated_at_ms = Date.now();
    writeJson(tracePath, tr);
  } catch {
    return;
  }
}

function getAdoptedIds() {
  const data = readJsonSafe(adoptedJsonPath, { adopted: [] });
  return Array.isArray(data.adopted) ? data.adopted : [];
}

function setAdoptedIds(ids) {
  writeJson(adoptedJsonPath, { adopted: [...new Set(ids)] });
}

function adoptFactory(factoryId) {
  const catalog = readJsonSafe(catalogJsonPath, { factories: [] });
  const item = (catalog.factories || []).find((f) => f.id === factoryId);
  if (!item) return { ok: false, error: '工場が見つかりません' };

  const candDir = join(runDir, 'candidates', factoryId);
  const bpSrc = join(candDir, 'normalized-blueprint.json');
  const specSrc = join(candDir, 'spec.json');
  const lintSrc = join(candDir, 'lint.mjs');
  if (!existsSync(bpSrc)) return { ok: false, error: '設計図が見つかりません' };

  const destDir = join(GENERATED_FACTORIES_DIR, factoryId);
  mkdirSync(destDir, { recursive: true });
  copyFileSync(bpSrc, join(destDir, 'blueprint.json'));
  if (existsSync(specSrc)) copyFileSync(specSrc, join(destDir, 'spec.json'));
  if (existsSync(lintSrc)) copyFileSync(lintSrc, join(destDir, 'lint.mjs'));

  mkdirSync(KASUGAI_BLUEPRINTS_DIR, { recursive: true });
  copyFileSync(bpSrc, join(KASUGAI_BLUEPRINTS_DIR, `${factoryId}.json`));

  const ids = getAdoptedIds();
  if (!ids.includes(factoryId)) {
    ids.push(factoryId);
    setAdoptedIds(ids);
    appendTraceLog(`工場「${item.name}」を採用しました → Kasugai 工場一覧に登録済み`);
  }
  return { ok: true, adopted: getAdoptedIds(), name: item.name };
}

function unadoptFactory(factoryId) {
  const bpDest = join(KASUGAI_BLUEPRINTS_DIR, `${factoryId}.json`);
  if (existsSync(bpDest)) {
    try {
      unlinkSync(bpDest);
    } catch {
    }
  }
  const ids = getAdoptedIds().filter((x) => x !== factoryId);
  setAdoptedIds(ids);
  appendTraceLog(`工場「${factoryId}」の採用を取り消しました`);
  return { ok: true, adopted: ids };
}

function mimeFor(path) {
  const ext = extname(path).toLowerCase();
  if (ext === '.html') return 'text/html; charset=utf-8';
  if (ext === '.js' || ext === '.mjs') return 'application/javascript; charset=utf-8';
  if (ext === '.css') return 'text/css; charset=utf-8';
  if (ext === '.json') return 'application/json; charset=utf-8';
  if (ext === '.svg') return 'image/svg+xml';
  if (ext === '.png') return 'image/png';
  return 'application/octet-stream';
}

function readBody(req) {
  return new Promise((resolvePromise) => {
    let raw = '';
    req.setEncoding('utf8');
    req.on('data', (chunk) => {
      raw += chunk;
      if (raw.length > 65536) raw = raw.slice(0, 65536);
    });
    req.on('end', () => resolvePromise(raw));
  });
}

function renderCatalogHtml() {
  return `<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>工場カタログ（採用選択）</title>
<style>
  :root {
    --bg: #0f131c;
    --panel: #171c28;
    --panel-hi: #1e2536;
    --ink: #eef2ff;
    --muted: #94a3b8;
    --line: rgba(148, 163, 184, 0.2);
    --accent: #6366f1;
    --accent-hi: #818cf8;
    --ok: #22c55e;
    --warn: #f59e0b;
    --danger: #ef4444;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    background: var(--bg);
    color: var(--ink);
    font-family: -apple-system, BlinkMacSystemFont, "Hiragino Sans", sans-serif;
    padding: 18px 20px 44px;
    line-height: 1.5;
  }
  .header {
    display: flex;
    flex-wrap: wrap;
    justify-content: space-between;
    align-items: flex-end;
    gap: 12px;
    padding-bottom: 16px;
    margin-bottom: 18px;
    border-bottom: 1px solid var(--line);
  }
  .title { font-size: 20px; font-weight: 800; letter-spacing: -0.01em; }
  .subtitle { font-size: 12px; color: var(--muted); margin-top: 4px; max-width: 680px; }
  .controls { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; }
  .pill {
    font-size: 12px;
    font-weight: 700;
    padding: 5px 11px;
    border-radius: 999px;
    background: var(--panel-hi);
    border: 1px solid var(--line);
    color: var(--ink);
  }
  .pill.ok { border-color: rgba(34, 197, 94, 0.45); color: #86efac; background: rgba(34, 197, 94, 0.12); }
  .filter-btn {
    font-size: 12px;
    font-weight: 700;
    padding: 6px 12px;
    border-radius: 8px;
    background: var(--panel);
    color: var(--muted);
    border: 1px solid var(--line);
    cursor: pointer;
  }
  .filter-btn.active { background: var(--accent); color: #fff; border-color: var(--accent); }
  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(330px, 1fr));
    gap: 16px;
  }
  .grid.single {
    grid-template-columns: 1fr;
    max-width: 1040px;
    margin: 0 auto;
  }
  .grid.single .preview-box {
    height: 480px;
  }
  .grid.single .preview-box iframe {
    width: 100%;
    height: 100%;
    transform: none;
  }
  .card {
    background: var(--panel);
    border: 1px solid var(--line);
    border-radius: 14px;
    overflow: hidden;
    display: flex;
    flex-direction: column;
    transition: border-color 0.15s ease, transform 0.15s ease;
  }
  .card.adopted {
    border-color: rgba(34, 197, 94, 0.7);
    box-shadow: 0 0 0 1px rgba(34, 197, 94, 0.35);
  }
  .preview-box {
    position: relative;
    width: 100%;
    height: 200px;
    background: #0b0e16;
    border-bottom: 1px solid var(--line);
    overflow: hidden;
  }
  .preview-box iframe {
    width: 200%;
    height: 200%;
    transform: scale(0.5);
    transform-origin: 0 0;
    border: 0;
    background: #111;
  }
  .expand-btn {
    position: absolute;
    right: 8px;
    bottom: 8px;
    font-size: 11px;
    font-weight: 700;
    padding: 5px 10px;
    border-radius: 7px;
    background: rgba(15, 19, 28, 0.88);
    color: #fff;
    border: 1px solid rgba(255, 255, 255, 0.2);
    cursor: pointer;
  }
  .expand-btn:hover { background: var(--accent); }
  .card-body {
    padding: 14px 15px 15px;
    display: flex;
    flex-direction: column;
    gap: 8px;
    flex: 1;
  }
  .meta-row {
    display: flex;
    align-items: center;
    gap: 6px;
    flex-wrap: wrap;
  }
  .tag {
    font-size: 11px;
    font-weight: 700;
    padding: 2px 8px;
    border-radius: 6px;
    background: var(--panel-hi);
    color: #cbd5e1;
  }
  .tag.score { background: rgba(99, 102, 241, 0.2); color: #c7d2fe; }
  .tag.pass { background: rgba(34, 197, 94, 0.16); color: #86efac; }
  .tag.fail { background: rgba(239, 68, 68, 0.18); color: #fca5a5; }
  .card-title { font-size: 16px; font-weight: 800; color: #fff; }
  .card-desc { font-size: 12.5px; color: var(--muted); }
  .verdict {
    font-size: 12px;
    color: #e2e8f0;
    background: rgba(255, 255, 255, 0.04);
    border-left: 3px solid var(--accent-hi);
    padding: 6px 9px;
    border-radius: 4px;
  }
  .actions {
    margin-top: auto;
    padding-top: 8px;
    display: flex;
    gap: 8px;
  }
  .btn {
    flex: 1;
    padding: 9px 12px;
    border-radius: 9px;
    font-size: 13px;
    font-weight: 800;
    border: 1px solid transparent;
    cursor: pointer;
    transition: opacity 0.15s ease;
  }
  .btn:hover { opacity: 0.92; }
  .btn-adopt { background: var(--accent); color: #fff; }
  .btn-adopted { background: rgba(34, 197, 94, 0.16); color: #86efac; border-color: rgba(34, 197, 94, 0.5); }
  .btn-ghost {
    flex: 0 0 auto;
    background: var(--panel-hi);
    color: #cbd5e1;
    border-color: var(--line);
    font-weight: 700;
    font-size: 12px;
  }
  .modal-backdrop {
    position: fixed;
    inset: 0;
    background: rgba(7, 10, 18, 0.82);
    display: none;
    align-items: center;
    justify-content: center;
    z-index: 999;
    padding: 18px;
  }
  .modal-backdrop.open { display: flex; }
  .modal {
    width: min(1100px, 96vw);
    height: min(760px, 90vh);
    background: var(--panel);
    border: 1px solid rgba(255, 255, 255, 0.16);
    border-radius: 14px;
    overflow: hidden;
    display: flex;
    flex-direction: column;
  }
  .modal-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 10px 14px;
    background: var(--panel-hi);
    border-bottom: 1px solid var(--line);
    gap: 10px;
  }
  .modal-title { font-size: 14px; font-weight: 800; }
  .modal-close {
    width: 30px;
    height: 30px;
    border-radius: 8px;
    border: 1px solid var(--line);
    background: var(--panel);
    color: #fff;
    font-size: 16px;
    cursor: pointer;
  }
  .modal-body { flex: 1; overflow: auto; position: relative; }
  .modal-body iframe { width: 100%; height: 100%; border: 0; background: #111; }
  .code-view {
    padding: 16px;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 12px;
    white-space: pre-wrap;
    color: #dbeafe;
  }
  .toast {
    position: fixed;
    bottom: 16px;
    left: 50%;
    transform: translateX(-50%);
    background: #16a34a;
    color: #fff;
    padding: 9px 16px;
    border-radius: 999px;
    font-size: 13px;
    font-weight: 800;
    display: none;
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.45);
    z-index: 1200;
  }
  .toast.show { display: block; }
</style>
</head>
<body>
  <div class="header">
    <div>
      <div class="title" id="headTitle">工場カタログ</div>
      <div class="subtitle" id="headSub">気に入った工場の「採用する」を押すと Kasugai の工場一覧（＋ボタン）に即登録されます。</div>
    </div>
    <div class="controls">
      <span class="pill" id="statTotal">0 工場</span>
      <span class="pill ok" id="statAdopted">採用済み 0</span>
      <button class="filter-btn active" id="fAll">すべて</button>
      <button class="filter-btn" id="fAdopted">採用済み</button>
    </div>
  </div>
  <div class="grid" id="grid"></div>

  <div class="modal-backdrop" id="modalBackdrop">
    <div class="modal" id="modalBox">
      <div class="modal-head">
        <div class="modal-title" id="modalTitle">プレビュー</div>
        <div style="display:flex; gap:8px; align-items:center;">
          <button class="btn btn-adopt" id="modalAdoptBtn" style="padding:5px 12px; font-size:12px;">採用する</button>
          <button class="modal-close" id="modalClose" aria-label="閉じる">×</button>
        </div>
      </div>
      <div class="modal-body" id="modalBody"></div>
    </div>
  </div>

  <div class="toast" id="toast"></div>

<script>
  let state = { catalog: { factories: [] }, adopted: [] };
  let filterMode = 'all';
  let modalFactoryId = null;

  function showToast(msg) {
    const el = document.getElementById('toast');
    el.textContent = msg;
    el.classList.add('show');
    clearTimeout(window.__toastTimer);
    window.__toastTimer = setTimeout(() => el.classList.remove('show'), 2600);
  }

  async function refresh() {
    const res = await fetch('/api/state');
    state = await res.json();
    render();
  }

  async function toggleAdopt(id) {
    const isAdopted = state.adopted.includes(id);
    const res = await fetch(isAdopted ? '/api/unadopt' : '/api/adopt', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id }),
    });
    const out = await res.json();
    if (out.ok) {
      state.adopted = out.adopted;
      showToast(isAdopted ? '採用を取り消しました' : '採用しました！左の「工場 ＋」からすぐ使えます');
      render();
      if (modalFactoryId === id) syncModalAdoptBtn();
    }
  }

  function syncModalAdoptBtn() {
    const btn = document.getElementById('modalAdoptBtn');
    const adopted = state.adopted.includes(modalFactoryId);
    btn.textContent = adopted ? '採用済み ✓（解除）' : 'この工場を採用する';
    btn.className = 'btn ' + (adopted ? 'btn-adopted' : 'btn-adopt');
  }

  function openSampleModal(f) {
    modalFactoryId = f.id;
    document.getElementById('modalTitle').textContent = f.name + ' — 試作品プレビュー';
    document.getElementById('modalBody').innerHTML = '<iframe src="/samples/' + encodeURIComponent(f.id) + '/index.html"></iframe>';
    syncModalAdoptBtn();
    document.getElementById('modalBackdrop').classList.add('open');
  }

  async function openSpecModal(f) {
    modalFactoryId = f.id;
    document.getElementById('modalTitle').textContent = f.name + ' — 設計図 ＆ 0 トークン lint.mjs';
    const res = await fetch('/api/source/' + encodeURIComponent(f.id));
    const data = await res.json();
    const pre = document.createElement('div');
    pre.className = 'code-view';
    pre.textContent = '=== blueprint.json ===\\n' + (data.blueprint || '') + '\\n\\n=== lint.mjs ===\\n' + (data.lint || '');
    const body = document.getElementById('modalBody');
    body.innerHTML = '';
    body.appendChild(pre);
    syncModalAdoptBtn();
    document.getElementById('modalBackdrop').classList.add('open');
  }

  function closeModal() {
    document.getElementById('modalBackdrop').classList.remove('open');
    document.getElementById('modalBody').innerHTML = '';
    modalFactoryId = null;
  }

  document.getElementById('modalClose').onclick = closeModal;
  document.getElementById('modalBackdrop').onclick = (e) => {
    if (e.target.id === 'modalBackdrop') closeModal();
  };
  document.getElementById('modalAdoptBtn').onclick = () => {
    if (modalFactoryId) toggleAdopt(modalFactoryId);
  };
  document.getElementById('fAll').onclick = () => {
    filterMode = 'all';
    document.getElementById('fAll').classList.add('active');
    document.getElementById('fAdopted').classList.remove('active');
    render();
  };
  document.getElementById('fAdopted').onclick = () => {
    filterMode = 'adopted';
    document.getElementById('fAdopted').classList.add('active');
    document.getElementById('fAll').classList.remove('active');
    render();
  };

  function render() {
    const factories = (state.catalog && state.catalog.factories) || [];
    const passedCount = factories.filter((f) => f.gate1_ok).length;
    document.getElementById('headTitle').textContent =
      '自動量産された工場カタログ（' + factories.length + ' 工場）';
    document.getElementById('statTotal').textContent =
      'Gate 1 合格 ' + passedCount + ' / ' + factories.length;
    document.getElementById('statAdopted').textContent = '採用済み ' + state.adopted.length;

    const list = filterMode === 'adopted'
      ? factories.filter((f) => state.adopted.includes(f.id))
      : factories;

    const grid = document.getElementById('grid');
    grid.className = 'grid' + (list.length === 1 ? ' single' : '');
    grid.innerHTML = '';
    for (const f of list) {
      const adopted = state.adopted.includes(f.id);
      const card = document.createElement('div');
      card.className = 'card' + (adopted ? ' adopted' : '');

      const preview = document.createElement('div');
      preview.className = 'preview-box';
      if (f.has_sample) {
        const ifr = document.createElement('iframe');
        ifr.src = '/samples/' + encodeURIComponent(f.id) + '/index.html';
        ifr.loading = 'lazy';
        preview.appendChild(ifr);
        const exp = document.createElement('button');
        exp.className = 'expand-btn';
        exp.textContent = '拡大して触る ↗';
        exp.onclick = () => openSampleModal(f);
        preview.appendChild(exp);
      }
      card.appendChild(preview);

      const body = document.createElement('div');
      body.className = 'card-body';

      const meta = document.createElement('div');
      meta.className = 'meta-row';
      meta.innerHTML =
        '<span class="tag">' + (f.category || '独自') + '</span>' +
        '<span class="tag ' + (f.gate1_ok ? 'pass' : 'fail') + '">' + (f.gate1_ok ? 'lint 合格' : 'lint 要確認') + '</span>' +
        (typeof f.score === 'number' ? '<span class="tag score">' + f.score + ' 点</span>' : '');
      body.appendChild(meta);

      const t = document.createElement('div');
      t.className = 'card-title';
      t.textContent = f.name;
      body.appendChild(t);

      const d = document.createElement('div');
      d.className = 'card-desc';
      d.textContent = f.summary || f.tagline || '';
      body.appendChild(d);

      if (f.verdict) {
        const v = document.createElement('div');
        v.className = 'verdict';
        v.textContent = f.verdict;
        body.appendChild(v);
      }

      const actions = document.createElement('div');
      actions.className = 'actions';

      const adoptBtn = document.createElement('button');
      adoptBtn.className = 'btn ' + (adopted ? 'btn-adopted' : 'btn-adopt');
      adoptBtn.textContent = adopted ? '採用済み ✓' : '採用する';
      adoptBtn.onclick = () => toggleAdopt(f.id);
      actions.appendChild(adoptBtn);

      const specBtn = document.createElement('button');
      specBtn.className = 'btn btn-ghost';
      specBtn.textContent = '設計図';
      specBtn.onclick = () => openSpecModal(f);
      actions.appendChild(specBtn);

      body.appendChild(actions);
      card.appendChild(body);
      grid.appendChild(card);
    }
  }

  refresh();
</script>
</body>
</html>`;
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url || '/', 'http://127.0.0.1');
  const pathname = decodeURIComponent(url.pathname);

  if (req.method === 'GET' && (pathname === '/' || pathname === '/index.html')) {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(renderCatalogHtml());
    return;
  }

  if (req.method === 'GET' && pathname === '/api/state') {
    const catalog = readJsonSafe(catalogJsonPath, { factories: [] });
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(JSON.stringify({ catalog, adopted: getAdoptedIds() }));
    return;
  }

  if (req.method === 'GET' && pathname.startsWith('/api/source/')) {
    const id = pathname.slice('/api/source/'.length).replace(/[^a-z0-9-]/gi, '');
    const candDir = join(runDir, 'candidates', id);
    const blueprint = existsSync(join(candDir, 'normalized-blueprint.json'))
      ? readFileSync(join(candDir, 'normalized-blueprint.json'), 'utf8')
      : '';
    const lint = existsSync(join(candDir, 'lint.mjs'))
      ? readFileSync(join(candDir, 'lint.mjs'), 'utf8')
      : '';
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify({ blueprint, lint }));
    return;
  }

  if (req.method === 'POST' && pathname === '/api/adopt') {
    const raw = await readBody(req);
    let body = {};
    try {
      body = JSON.parse(raw || '{}');
    } catch {
      body = {};
    }
    const result = adoptFactory(String(body.id || ''));
    res.writeHead(result.ok ? 200 : 400, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify(result));
    return;
  }

  if (req.method === 'POST' && pathname === '/api/unadopt') {
    const raw = await readBody(req);
    let body = {};
    try {
      body = JSON.parse(raw || '{}');
    } catch {
      body = {};
    }
    const result = unadoptFactory(String(body.id || ''));
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(JSON.stringify(result));
    return;
  }

  if (req.method === 'GET' && pathname.startsWith('/samples/')) {
    const parts = pathname.slice('/samples/'.length).split('/').filter(Boolean);
    const id = (parts[0] || '').replace(/[^a-z0-9-]/gi, '');
    const rel = parts.slice(1).join('/') || 'index.html';
    const filePath = resolve(join(runDir, 'candidates', id, 'sample', rel));
    const allowedRoot = resolve(join(runDir, 'candidates', id, 'sample'));
    if (filePath.startsWith(allowedRoot) && existsSync(filePath)) {
      res.writeHead(200, { 'Content-Type': mimeFor(filePath), 'Cache-Control': 'no-store' });
      res.end(readFileSync(filePath));
      return;
    }
  }

  res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end('Not Found');
});

server.listen(port, '127.0.0.1', () => {
  const addr = server.address();
  const actualPort = typeof addr === 'object' && addr ? addr.port : port;
  process.stdout.write(`LISTENING http://127.0.0.1:${actualPort}/\n`);
});
