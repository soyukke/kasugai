#!/usr/bin/env node
import { spawn } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import http from 'node:http';
import { tmpdir } from 'node:os';
import { extname, join, resolve } from 'node:path';

const CHROME_BIN = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

function mimeFor(p) {
  const e = extname(p).toLowerCase();
  if (e === '.html') return 'text/html; charset=utf-8';
  if (e === '.js' || e === '.mjs') return 'application/javascript; charset=utf-8';
  if (e === '.css') return 'text/css; charset=utf-8';
  if (e === '.json') return 'application/json; charset=utf-8';
  if (e === '.svg') return 'image/svg+xml';
  if (e === '.png') return 'image/png';
  return 'application/octet-stream';
}

function startStatic(webDir) {
  return new Promise((resolvePromise, rejectPromise) => {
    const server = http.createServer((req, res) => {
      const u = new URL(req.url || '/', 'http://127.0.0.1');
      let rel = decodeURIComponent(u.pathname).replace(/^\/+/, '');
      if (rel === 'favicon.ico') {
        res.writeHead(204);
        res.end();
        return;
      }
      if (!rel || rel.endsWith('/')) rel += 'index.html';
      const target = resolve(join(webDir, rel));
      if (!target.startsWith(resolve(webDir)) || !existsSync(target)) {
        res.writeHead(404);
        res.end('Not found');
        return;
      }
      res.writeHead(200, { 'Content-Type': mimeFor(target), 'Cache-Control': 'no-store' });
      res.end(readFileSync(target));
    });
    server.on('error', rejectPromise);
    server.listen(0, '127.0.0.1', () => {
      const addr = server.address();
      resolvePromise({ server, url: `http://127.0.0.1:${addr.port}/` });
    });
  });
}

function launchChrome(profileDir) {
  return new Promise((resolvePromise, rejectPromise) => {
    const proc = spawn(
      CHROME_BIN,
      [
        '--headless=new',
        '--disable-gpu',
        '--no-sandbox',
        '--disable-background-networking',
        '--disable-default-apps',
        '--disable-extensions',
        '--mute-audio',
        '--remote-debugging-port=0',
        `--user-data-dir=${profileDir}`,
        'about:blank',
      ],
      { stdio: ['ignore', 'pipe', 'pipe'] }
    );
    let stderr = '';
    let settled = false;
    const timer = setTimeout(() => {
      if (!settled) {
        settled = true;
        try {
          proc.kill('SIGKILL');
        } catch {
            }
        rejectPromise(new Error(`Chrome startup timeout: ${stderr.slice(-400)}`));
      }
    }, 15000);
    proc.stderr.on('data', (chunk) => {
      stderr += chunk.toString('utf8');
      const m = stderr.match(/DevTools listening on (ws:\/\/[^\s]+)/);
      if (m && !settled) {
        settled = true;
        clearTimeout(timer);
        resolvePromise({ proc, browserWsUrl: m[1] });
      }
    });
    proc.on('exit', (code) => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        rejectPromise(new Error(`Chrome exited early (${code}): ${stderr.slice(-400)}`));
      }
    });
  });
}

class CDPClient {
  constructor(wsUrl) {
    this.ws = new WebSocket(wsUrl);
    this.nextId = 1;
    this.pending = new Map();
    this.listeners = new Map();
    this.ready = new Promise((resolvePromise, rejectPromise) => {
      this.ws.addEventListener('open', () => resolvePromise());
      this.ws.addEventListener('error', (e) => rejectPromise(new Error(String(e.message || 'ws error'))));
    });
    this.ws.addEventListener('message', (ev) => {
      const msg = JSON.parse(String(ev.data));
      if (msg.id && this.pending.has(msg.id)) {
        const { resolvePromise, rejectPromise } = this.pending.get(msg.id);
        this.pending.delete(msg.id);
        if (msg.error) rejectPromise(new Error(msg.error.message || JSON.stringify(msg.error)));
        else resolvePromise(msg.result);
      } else if (msg.method) {
        const list = this.listeners.get(msg.method) || [];
        for (const fn of list) fn(msg.params || {});
      }
    });
  }

  on(method, fn) {
    const list = this.listeners.get(method) || [];
    list.push(fn);
    this.listeners.set(method, list);
  }

  async send(method, params = {}) {
    await this.ready;
    const id = this.nextId++;
    return new Promise((resolvePromise, rejectPromise) => {
      this.pending.set(id, { resolvePromise, rejectPromise });
      this.ws.send(JSON.stringify({ id, method, params }));
    });
  }

  close() {
    try {
      this.ws.close();
    } catch {
    }
  }
}

async function sleep(ms) {
  await new Promise((r) => setTimeout(r, ms));
}

async function analyzeScreenshotsInPage(cdp, initialB64, afterB64) {
  const expr = `(async () => {
    const load = (b64) => new Promise((res, rej) => {
      const img = new Image();
      img.onload = () => res(img);
      img.onerror = rej;
      img.src = 'data:image/png;base64,' + b64;
    });
    const a = await load(${JSON.stringify(initialB64)});
    const b = await load(${JSON.stringify(afterB64)});
    const w = 160, h = 100;
    const c1 = document.createElement('canvas'); c1.width = w; c1.height = h;
    const x1 = c1.getContext('2d'); x1.drawImage(a, 0, 0, w, h);
    const d1 = x1.getImageData(0, 0, w, h).data;
    const c2 = document.createElement('canvas'); c2.width = w; c2.height = h;
    const x2 = c2.getContext('2d'); x2.drawImage(b, 0, 0, w, h);
    const d2 = x2.getImageData(0, 0, w, h).data;
    let lumaSum = 0, lumaSq = 0, darkPixels = 0, diffPixels = 0, colorfulPixels = 0;
    const hueBuckets = new Set();
    const n = w * h;
    for (let i = 0; i < d1.length; i += 4) {
      const r = d1[i], g = d1[i+1], bl = d1[i+2];
      const l1 = 0.299 * r + 0.587 * g + 0.114 * bl;
      lumaSum += l1;
      lumaSq += l1 * l1;
      if (r < 20 && g < 20 && bl < 20) darkPixels++;
      const mx = Math.max(r, g, bl), mn = Math.min(r, g, bl);
      if (mx - mn > 28) {
        colorfulPixels++;
        hueBuckets.add(Math.floor(((r > g ? (r > bl ? 0 : 2) : (g > bl ? 1 : 2)) * 4) + ((mx - mn) / 64)));
      }
      const diff = Math.abs(r - d2[i]) + Math.abs(g - d2[i+1]) + Math.abs(bl - d2[i+2]);
      if (diff > 18) diffPixels++;
    }
    const mean = lumaSum / n;
    const std = Math.sqrt(Math.max(0, lumaSq / n - mean * mean));
    return {
      meanLuma: Math.round(mean * 10) / 10,
      lumaStd: Math.round(std * 10) / 10,
      darkRatio: Math.round((darkPixels / n) * 1000) / 1000,
      colorfulRatio: Math.round((colorfulPixels / n) * 1000) / 1000,
      hueBuckets: hueBuckets.size,
      diffRatio: Math.round((diffPixels / n) * 1000) / 1000,
    };
  })()`;
  const res = await cdp.send('Runtime.evaluate', {
    expression: expr,
    awaitPromise: true,
    returnByValue: true,
  });
  return res?.result?.value || { meanLuma: 0, lumaStd: 0, darkRatio: 1, diffRatio: 0 };
}

async function main() {
  const webDir = resolve(process.argv[2] || '.');
  const outDir = resolve(process.argv[3] || join(webDir, '.cdp-out'));
  mkdirSync(outDir, { recursive: true });

  if (!existsSync(CHROME_BIN)) {
    console.log(JSON.stringify({ ok: true, skipped: true, errors: [], metrics: [] }));
    return;
  }

  const profileDir = mkdtempSync(join(tmpdir(), 'kasugai-cdp-'));
  let server = null;
  let chromeProc = null;
  let cdp = null;

  try {
    const srv = await startStatic(webDir);
    server = srv.server;
    const launched = await launchChrome(profileDir);
    chromeProc = launched.proc;

    const portMatch = launched.browserWsUrl.match(/127\.0\.0\.1:(\d+)/);
    const listRes = await fetch(`http://127.0.0.1:${portMatch[1]}/json/list`);
    const targets = await listRes.json();
    const pageTarget = targets.find((t) => t.type === 'page') || targets[0];
    if (!pageTarget?.webSocketDebuggerUrl) {
      throw new Error('No Chrome page target found');
    }

    cdp = new CDPClient(pageTarget.webSocketDebuggerUrl);
    await cdp.send('Page.enable');
    await cdp.send('Runtime.enable');
    await cdp.send('Log.enable');
    await cdp.send('Emulation.setDeviceMetricsOverride', {
      width: 1280,
      height: 800,
      deviceScaleFactor: 1,
      mobile: false,
    });

    const consoleErrors = [];
    const pageExceptions = [];
    cdp.on('Runtime.exceptionThrown', (p) => {
      const msg = p?.exceptionDetails?.exception?.description || p?.exceptionDetails?.text || 'exception';
      pageExceptions.push(String(msg).slice(0, 300));
    });
    cdp.on('Runtime.consoleAPICalled', (p) => {
      if (p.type === 'error') {
        const text = (p.args || []).map((a) => a.value ?? a.description ?? '').join(' ');
        consoleErrors.push(text.slice(0, 300));
      }
    });
    cdp.on('Log.entryAdded', (p) => {
      if (p?.entry?.level === 'error') {
        consoleErrors.push(String(p.entry.text || '').slice(0, 300));
      }
    });

    await cdp.send('Page.navigate', { url: srv.url });
    await sleep(1100);

    const domRes = await cdp.send('Runtime.evaluate', {
      expression: `(() => {
        const html = document.documentElement;
        const body = document.body;
        const overflowX = html.scrollWidth - html.clientWidth;
        const interactive = document.querySelectorAll('button, input, select, canvas, svg, [role="button"]').length;
        const textLen = (body ? body.innerText : '').trim().length;
        const canvases = Array.from(document.querySelectorAll('canvas')).map(c => ({ w: c.width, h: c.height }));
        const svgs = document.querySelectorAll('svg').length;
        const btn = document.querySelector('button');
        const btnRect = btn ? btn.getBoundingClientRect() : null;
        return {
          overflowX,
          interactive,
          textLen,
          canvases,
          svgs,
          btnPoint: btnRect && btnRect.width > 4 ? { x: btnRect.left + btnRect.width / 2, y: btnRect.top + btnRect.height / 2 } : null,
        };
      })()`,
      returnByValue: true,
    });
    const dom = domRes?.result?.value || {};

    const shot1 = await cdp.send('Page.captureScreenshot', { format: 'png' });
    const shot1Path = join(outDir, 'shot_initial.png');
    writeFileSync(shot1Path, Buffer.from(shot1.data, 'base64'));

    const clickPoints = [
      { x: 640, y: 400 },
      { x: 520, y: 360 },
      dom.btnPoint || { x: 740, y: 420 },
    ];
    for (const pt of clickPoints) {
      await cdp.send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: pt.x, y: pt.y });
      await cdp.send('Input.dispatchMouseEvent', { type: 'mousePressed', x: pt.x, y: pt.y, button: 'left', clickCount: 1 });
      await sleep(70);
      await cdp.send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: pt.x, y: pt.y, button: 'left', clickCount: 1 });
      await sleep(160);
    }
    await sleep(450);

    const shot2 = await cdp.send('Page.captureScreenshot', { format: 'png' });
    const shot2Path = join(outDir, 'shot_after.png');
    writeFileSync(shot2Path, Buffer.from(shot2.data, 'base64'));

    const visual = await analyzeScreenshotsInPage(cdp, shot1.data, shot2.data);

    const errors = [];
    if (pageExceptions.length > 0) errors.push(`実行時例外 ${pageExceptions.length} 件: ${pageExceptions[0]}`);
    if (consoleErrors.length > 0) errors.push(`Console エラー ${consoleErrors.length} 件: ${consoleErrors[0]}`);
    if ((dom.overflowX || 0) > 6) errors.push(`横はみ出し検出 (overflowX=${dom.overflowX}px)`);
    if (visual.lumaStd < 4.5) errors.push(`画面がほぼ単色・空白に見えます (lumaStd=${visual.lumaStd})`);
    if (visual.darkRatio > 0.88) errors.push(`背景が真っ黒すぎます (darkRatio=${Math.round(visual.darkRatio * 100)}%)`);
    if ((dom.interactive || 0) < 1) errors.push('操作要素（canvas/svg/button/input）が見つかりません');

    const metrics = [
      {
        label: 'CDP エラー',
        value: `${pageExceptions.length + consoleErrors.length} 件`,
        tone: pageExceptions.length + consoleErrors.length === 0 ? 'success' : 'danger',
      },
      {
        label: '画面変化',
        value: `${Math.round(visual.diffRatio * 100)}%`,
        tone: visual.diffRatio >= 0.01 ? 'success' : 'warning',
      },
      {
        label: '明度コントラスト',
        value: `σ=${visual.lumaStd}`,
        tone: visual.lumaStd >= 12 ? 'success' : visual.lumaStd >= 4.5 ? 'neutral' : 'danger',
      },
    ];

    const out = {
      ok: errors.length === 0,
      errors,
      metrics,
      visual,
      dom,
      shots: { initial: shot1Path, after: shot2Path },
    };
    console.log(JSON.stringify(out, null, 2));
    process.exitCode = out.ok ? 0 : 1;
  } finally {
    if (cdp) cdp.close();
    if (chromeProc) {
      try {
        chromeProc.kill('SIGKILL');
      } catch {
        }
    }
    if (server) server.close();
    try {
      rmSync(profileDir, { recursive: true, force: true });
    } catch {
    }
  }
}

main().catch((err) => {
  console.log(JSON.stringify({ ok: false, errors: [`CDP 検証異常: ${err.message}`], metrics: [] }));
  process.exit(1);
});
