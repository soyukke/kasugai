#!/usr/bin/env node
import { spawn, spawnSync } from 'node:child_process';
import {
  copyFileSync,
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const WORK_ROOT = process.env.KASUGAI_FACTORY_WORK_DIR || join(os.homedir(), 'Library/Application Support/Kasugai/factory');
const GENERATED_FACTORIES_DIR = join(WORK_ROOT, 'generated-factories');
const CDP_CHECK_SCRIPT = join(SCRIPT_DIR, 'check-artifact-cdp.mjs');
const KASUGAI_BLUEPRINTS_DIR = join(
  os.homedir(),
  'Library/Application Support/Kasugai/factory/blueprints'
);
const KASUGAI_RUNS_DIR = join(
  os.homedir(),
  'Library/Application Support/Kasugai/factory/runs'
);

function parseArgs(argv) {
  const action = argv[0] || 'run';
  const opts = {};
  for (let i = 1; i < argv.length; i++) {
    const key = argv[i];
    if (key.startsWith('--')) {
      const val = argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[++i] : 'true';
      opts[key.slice(2)] = val;
    }
  }
  return { action, opts };
}

function nowMs() {
  return Date.now();
}

function clockStamp() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
}

function readJson(path) {
  return JSON.parse(readFileSync(path, 'utf8'));
}

function writeJsonAtomic(path, obj) {
  mkdirSync(dirname(path), { recursive: true });
  const tmp = `${path}.tmp.${process.pid}.${Math.random().toString(16).slice(2, 8)}`;
  writeFileSync(tmp, JSON.stringify(obj, null, 2) + '\n', 'utf8');
  spawnSync('/bin/mv', ['-f', tmp, path]);
}

function saveTrace(trace, tracePath) {
  trace.updated_at_ms = nowMs();
  writeJsonAtomic(tracePath, trace);
}

function appendLog(trace, tracePath, message) {
  trace.logs = trace.logs || [];
  trace.logs.push(`[${clockStamp()}] ${message}`);
  saveTrace(trace, tracePath);
}

function runCmd(cmd, args, options = {}) {
  const start = Date.now();
  const res = spawnSync(cmd, args, {
    cwd: options.cwd,
    env: { ...process.env, ...(options.env || {}) },
    encoding: 'utf8',
    timeout: options.timeoutMs ?? 60000,
    maxBuffer: 16 * 1024 * 1024,
  });
  return {
    ok: res.status === 0 && !res.error,
    status: res.status ?? -1,
    stdout: res.stdout || '',
    stderr: res.stderr || '',
    error: res.error ? String(res.error) : '',
    seconds: (Date.now() - start) / 1000,
  };
}

function estimateTextTokens(text) {
  const s = String(text || '');
  let cjk = 0;
  let ascii = 0;
  for (let i = 0; i < s.length; i++) {
    if (s.charCodeAt(i) >= 0x3000) cjk++;
    else ascii++;
  }
  return Math.ceil(cjk / 1.5 + ascii / 4.0);
}

function ctlRequest(reqObj) {
  const sockPath = process.env.KASUGAI_CTL_SOCKET || '';
  if (!sockPath) throw new Error('KASUGAI_CTL_SOCKET is not set');
  return new Promise((resolvePromise, rejectPromise) => {
    const client = net.createConnection(sockPath);
    let buf = '';
    client.setEncoding('utf8');
    client.on('connect', () => client.write(JSON.stringify(reqObj) + '\n'));
    client.on('data', (chunk) => {
      buf += chunk;
      const nl = buf.indexOf('\n');
      if (nl !== -1) {
        const line = buf.slice(0, nl);
        client.end();
        try {
          resolvePromise(JSON.parse(line));
        } catch (err) {
          rejectPromise(err);
        }
      }
    });
    client.on('error', (err) => rejectPromise(err));
    client.on('end', () => {
      if (buf.trim()) {
        try {
          resolvePromise(JSON.parse(buf.trim()));
        } catch (err) {
          rejectPromise(err);
        }
      }
    });
  });
}

async function runKasugaiAgentTurn({
  title,
  provider = 'opencode_acp',
  model = 'opencode-go/glm-5.3',
  cwd,
  prompt,
  effort = 'high',
  maxWaitMs = 5 * 60 * 1000,
  trace = null,
  tracePath = null,
}) {
  const start = Date.now();
  const launchRes = await ctlRequest({
    action: 'launch',
    title,
    provider,
    model,
    effort,
    cwd,
    prompt,
  });
  if (!launchRes.ok || !launchRes.thread_id) {
    throw new Error(`Kasugai ctl launch failed: ${launchRes.error || 'unknown error'}`);
  }
  const threadId = launchRes.thread_id;
  const deadline = Date.now() + maxWaitMs;
  let lastThread = launchRes.thread || null;

  while (Date.now() < deadline) {
    const waitRes = await ctlRequest({
      action: 'wait',
      thread_id: threadId,
      timeout_ms: 30000,
      auto_approve: true,
    });
    if (!waitRes.ok) throw new Error(`Kasugai ctl wait failed: ${waitRes.error || 'unknown error'}`);
    lastThread = waitRes.thread || lastThread;
    if (waitRes.status !== 'running' && waitRes.status !== 'awaiting_approval') break;
  }

  const readRes = await ctlRequest({ action: 'read', thread_id: threadId });
  if (readRes.ok && readRes.thread) lastThread = readRes.thread;

  const messages = (lastThread && lastThread.messages) || [];
  const activities = (lastThread && lastThread.activities) || [];
  let inTok = estimateTextTokens(prompt);
  let outTok = 0;
  for (const m of messages) {
    if (m.role === 'assistant') outTok += estimateTextTokens(m.text || '');
    else if (m.role === 'tool') inTok += estimateTextTokens(m.text || '');
  }
  for (const a of activities) {
    outTok += estimateTextTokens(a.title || a.summary || a.detail || '');
  }

  if (trace && tracePath) {
    trace.input_tokens = (trace.input_tokens || 0) + inTok;
    trace.output_tokens = (trace.output_tokens || 0) + outTok;
    trace.tokens_estimated = true;
    saveTrace(trace, tracePath);
  }

  const assistantMessages = messages.filter((m) => m.role === 'assistant');
  const lastReply = assistantMessages.length
    ? assistantMessages[assistantMessages.length - 1].text || ''
    : '';
  return {
    threadId,
    status: (lastThread && lastThread.status) || 'unknown',
    reply: lastReply,
    seconds: (Date.now() - start) / 1000,
    inputTokens: inTok,
    outputTokens: outTok,
    totalTokens: inTok + outTok,
  };
}

function extractJsonValue(text) {
  const fenced = text.match(/```json\s*([\s\S]*?)```/i);
  const candidates = [];
  if (fenced) candidates.push(fenced[1].trim());
  const firstObj = text.indexOf('{');
  const lastObj = text.lastIndexOf('}');
  if (firstObj !== -1 && lastObj > firstObj) candidates.push(text.slice(firstObj, lastObj + 1));
  for (const raw of candidates) {
    try {
      return JSON.parse(raw);
    } catch {
      continue;
    }
  }
  return null;
}

function findFreePort() {
  return new Promise((resolvePromise, rejectPromise) => {
    const srv = net.createServer();
    srv.listen(0, '127.0.0.1', () => {
      const addr = srv.address();
      const port = typeof addr === 'object' && addr ? addr.port : 0;
      srv.close(() => resolvePromise(port));
    });
    srv.on('error', rejectPromise);
  });
}

async function startDetachedStaticServer(directory) {
  const port = await findFreePort();
  const child = spawn(
    '/usr/bin/python3',
    ['-m', 'http.server', String(port), '--bind', '127.0.0.1', '--directory', directory],
    { detached: true, stdio: 'ignore' }
  );
  child.unref();
  return `http://127.0.0.1:${port}/`;
}

function discoverOptimizableFactories() {
  const list = [];
  if (existsSync(GENERATED_FACTORIES_DIR)) {
    for (const id of readdirSync(GENERATED_FACTORIES_DIR)) {
      const dir = join(GENERATED_FACTORIES_DIR, id);
      const bpPath = join(dir, 'blueprint.json');
      if (!existsSync(bpPath)) continue;
      try {
        const bp = readJson(bpPath);
        const mtime = statSync(bpPath).mtimeMs;
        list.push({ id, name: bp.name || id, dir, bpPath, mtime, bp, installed: true });
      } catch {
        continue;
      }
    }
  }
  if (existsSync(KASUGAI_RUNS_DIR)) {
    for (const runName of readdirSync(KASUGAI_RUNS_DIR)) {
      const candRoot = join(KASUGAI_RUNS_DIR, runName, 'candidates');
      if (!existsSync(candRoot)) continue;
      for (const id of readdirSync(candRoot)) {
        if (list.some((x) => x.id === id)) continue;
        const dir = join(candRoot, id);
        const bpPath = existsSync(join(dir, 'normalized-blueprint.json'))
          ? join(dir, 'normalized-blueprint.json')
          : join(dir, 'blueprint.json');
        if (!existsSync(bpPath)) continue;
        try {
          const bp = readJson(bpPath);
          const mtime = statSync(bpPath).mtimeMs;
          list.push({ id, name: bp.name || id, dir, bpPath, mtime, bp, installed: false });
        } catch {
          continue;
        }
      }
    }
  }
  list.sort((a, b) => b.mtime - a.mtime);
  return list;
}

function resolveTargetFactory(userPrompt) {
  const factories = discoverOptimizableFactories();
  if (factories.length === 0) {
    throw new Error(
      '改善対象の専用工場がまだ見つかりません。先に「工場を作る工場（Meta）」で専用工場を 1 つ作成してから実行してください。'
    );
  }
  const lower = String(userPrompt || '').toLowerCase();
  const explicitMatch = String(userPrompt || '').match(
    /(?:対象工場|対象|工場)\s*[:：]\s*([^\n「」]+)/
  );
  const query = explicitMatch ? explicitMatch[1].trim().toLowerCase() : '';

  if (query) {
    const hit = factories.find(
      (f) =>
        f.id.toLowerCase() === query ||
        f.name.toLowerCase() === query ||
        query.includes(f.id.toLowerCase()) ||
        query.includes(f.name.toLowerCase()) ||
        f.name.toLowerCase().includes(query)
    );
    if (hit) return hit;
  }

  for (const f of factories) {
    if (lower.includes(f.id.toLowerCase()) || lower.includes(f.name.toLowerCase())) {
      return f;
    }
  }
  return factories[0];
}

function parseEvalPrompt(userPrompt, spec, bp) {
  const m = String(userPrompt || '').match(/(?:固定お題|テストお題|ベンチマークお題|お題)\s*[:：]\s*([^\n]+)/);
  if (m && m[1].trim().length >= 8) {
    return m[1].trim();
  }
  return String(spec?.sample_prompt || bp?.placeholder_prompt || 'この工場の代表作を 1 本作る');
}

function parseObjectiveWeights(userPrompt) {
  const p = String(userPrompt || '');
  const wantsSpeed = /速度|速く|時間|秒/.test(p);
  const wantsTokens = /トークン|コスト|節約|軽/.test(p);
  const wantsQuality = /品質|見た目|美|デザイン|面白/.test(p);
  return {
    quality: wantsQuality && !wantsSpeed && !wantsTokens ? 0.72 : 0.65,
    gate1: 0.2,
    timeScale: wantsSpeed ? 1.6 : 1.0,
    tokenScale: wantsTokens ? 1.6 : 1.0,
    label: [
      '品質重視',
      wantsSpeed ? '速度重視' : null,
      wantsTokens ? 'トークン重視' : null,
    ]
      .filter(Boolean)
      .join(' · '),
  };
}

function computeFitness({ quality, gate1Ok, elapsedSeconds, totalTokens, weights }) {
  const g1 = gate1Ok ? 100 : 0;
  const timePenalty = Math.min(18, Math.max(0, (elapsedSeconds - 30) * 0.12)) * weights.timeScale;
  const tokenPenalty = Math.min(14, Math.max(0, (totalTokens - 3500) / 1400)) * weights.tokenScale;
  const raw = weights.quality * quality + weights.gate1 * g1 - timePenalty - tokenPenalty;
  return {
    fitness: Math.round(Math.max(0, Math.min(100, raw)) * 10) / 10,
    timePenalty: Math.round(timePenalty * 10) / 10,
    tokenPenalty: Math.round(tokenPenalty * 10) / 10,
  };
}

function validateFactoryDir(dir) {
  const errors = [];
  const bpPath = join(dir, 'blueprint.json');
  const specPath = join(dir, 'spec.json');
  const lintPath = join(dir, 'lint.mjs');
  let bp = null;
  let spec = null;

  if (!existsSync(bpPath)) errors.push('blueprint.json 欠落');
  else {
    try {
      bp = readJson(bpPath);
    } catch (e) {
      errors.push(`blueprint.json エラー: ${e.message}`);
    }
  }
  if (!existsSync(specPath)) errors.push('spec.json 欠落');
  else {
    try {
      spec = readJson(specPath);
    } catch (e) {
      errors.push(`spec.json エラー: ${e.message}`);
    }
  }
  if (existsSync(lintPath)) {
    const syn = runCmd('node', ['--check', lintPath], { cwd: dir, timeoutMs: 12000 });
    if (!syn.ok) errors.push(`lint.mjs 構文エラー: ${(syn.stderr || syn.stdout).slice(-400)}`);
    else {
      const st = runCmd('node', [lintPath, '--self-test'], { cwd: dir, timeoutMs: 18000 });
      if (!st.ok) errors.push(`lint.mjs --self-test 失敗: ${`${st.stderr}\n${st.stdout}`.slice(-500)}`);
    }
  } else {
    errors.push('lint.mjs 欠落');
  }
  return { ok: errors.length === 0, errors, bp, spec };
}

function verifyOneShotArtifact(webDir, lintPath, shotDir) {
  const errors = [];
  const metrics = [];
  const htmlPath = join(webDir, 'index.html');
  if (!existsSync(htmlPath)) {
    return { ok: false, errors: ['index.html 欠落'], metrics: [], shots: null };
  }
  const html = readFileSync(htmlPath, 'utf8');
  if (html.length < 1500) errors.push(`index.html が短すぎます (${html.length} chars)`);
  if (/<(script|link|img)[^>]+(?:src|href)\s*=\s*["']https?:\/\//i.test(html)) {
    errors.push('外部 URL 参照が含まれています');
  }

  const scripts = [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/gi)].map((m) => m[1]);
  for (let i = 0; i < scripts.length; i++) {
    const code = scripts[i].trim();
    if (!code) continue;
    const tmpJs = join(webDir, `.opt_chk_${i}_${process.pid}.mjs`);
    writeFileSync(tmpJs, code, 'utf8');
    const chk = runCmd('node', ['--check', tmpJs], { cwd: webDir, timeoutMs: 10000 });
    spawnSync('/bin/rm', ['-f', tmpJs]);
    if (!chk.ok) errors.push(`JS 構文エラー: ${(chk.stderr || chk.stdout).slice(-500)}`);
  }

  if (lintPath && existsSync(lintPath)) {
    const res = runCmd('node', [lintPath, webDir], { cwd: dirname(lintPath), timeoutMs: 20000 });
    const parsed = extractJsonValue(`${res.stdout}\n${res.stderr}`);
    if (!res.ok || (parsed && parsed.ok === false)) {
      if (parsed && Array.isArray(parsed.errors)) {
        for (const e of parsed.errors) errors.push(`専用 lint: ${String(e)}`);
      } else {
        errors.push(`専用 lint 失敗: ${`${res.stderr}\n${res.stdout}`.slice(-600)}`);
      }
      metrics.push({ label: '専用 lint', value: '不合格', tone: 'danger' });
    } else {
      metrics.push({ label: '専用 lint', value: '合格', tone: 'success' });
    }
  }

  let shots = null;
  if (existsSync(CDP_CHECK_SCRIPT)) {
    const cdpRes = runCmd(process.execPath, [CDP_CHECK_SCRIPT, webDir, shotDir], {
      cwd: webDir,
      timeoutMs: 30000,
    });
    const parsed = extractJsonValue(`${cdpRes.stdout}\n${cdpRes.stderr}`);
    if (parsed) {
      shots = parsed.shots || null;
      if (Array.isArray(parsed.metrics)) metrics.push(...parsed.metrics);
      if (Array.isArray(parsed.errors)) {
        for (const e of parsed.errors) errors.push(`Chrome CDP: ${String(e)}`);
      }
    } else {
      errors.push('Chrome CDP 出力解析失敗');
    }
  }

  return { ok: errors.length === 0, errors, metrics: metrics.slice(0, 4), shots };
}

async function evaluateFactoryOneShot({
  genIndex,
  factoryDir,
  genDir,
  evalPrompt,
  weights,
  provider,
  model,
  criticProvider,
  criticModel,
  trace,
  tracePath,
}) {
  const bp = readJson(join(factoryDir, 'blueprint.json'));
  const spec = readJson(join(factoryDir, 'spec.json'));
  const lintPath = join(factoryDir, 'lint.mjs');
  const webDir = join(genDir, 'web');
  const shotDir = join(genDir, 'shots');
  mkdirSync(webDir, { recursive: true });
  mkdirSync(shotDir, { recursive: true });

  const workerPrompt = [
    `あなたは専用工場「${bp.name}」の実装 Worker です。`,
    '人間の途中介入なし・ポン出し一発で最高品質の単一完結 Web 作品（`index.html`）を作成してください。',
    '',
    `## 出力先ファイル`,
    join(webDir, 'index.html'),
    '',
    '## 固定ベンチマークお題',
    evalPrompt,
    '',
    '## 工場の設計規約（worker_instructions）',
    spec.worker_instructions || '',
    '',
    '## ハーネスルール',
    ...(bp.harness_rules || []).map((r, i) => `${i + 1}. ${r}`),
    '- 外部 CDN・外部通信ゼロ（オフライン WKWebView / Headless Chrome で 100% 動作）',
    '- 書き出し後、速やかに終了してください。',
  ].join('\n');

  const evalStart = Date.now();
  const workerRes = await runKasugaiAgentTurn({
    title: `[工場] 評価 v${genIndex}:${bp.name}`,
    provider,
    model,
    cwd: webDir,
    prompt: workerPrompt,
    maxWaitMs: 5 * 60 * 1000,
    trace,
    tracePath,
  });

  const g1 = verifyOneShotArtifact(webDir, lintPath, shotDir);
  const elapsedSeconds = Math.round(((Date.now() - evalStart) / 1000) * 10) / 10;

  const htmlExcerpt = existsSync(join(webDir, 'index.html'))
    ? readFileSync(join(webDir, 'index.html'), 'utf8').slice(0, 8000)
    : '';

  const criticPrompt = [
    `あなたは工場ベンチマークの厳格な隔離審査員です（世代 v${genIndex}）。`,
    '以下の実 Chrome 計測値・スクリーンショット（閲覧可能な場合）・HTML コードを総合して、ポン出し品質を 0〜100 点で採点してください。',
    '',
    '## 実スクリーンショット',
    g1.shots?.initial ? `- 初期描画: ${g1.shots.initial}` : '- （なし）',
    g1.shots?.after ? `- 操作後: ${g1.shots.after}` : '',
    '',
    '## 固定お題',
    evalPrompt,
    '',
    '## Gate 1 結果（0 トークン）',
    JSON.stringify({ ok: g1.ok, errors: g1.errors, metrics: g1.metrics }, null, 2),
    '',
    '## 採点基準',
    ...(spec.critic_rubric || ['視覚的完成度', '独創性', '操作感', 'レイアウト清潔さ']).map(
      (r, i) => `${i + 1}. ${r}`
    ),
    '',
    '## index.html（抜粋）',
    '```html',
    htmlExcerpt,
    '```',
    '',
    '必ず以下の JSON のみ返してください（甘い点数は禁止、実スクショの粗を遠慮なく減点）:',
    '```json',
    '{"score": 78, "summary": "実スクショを踏まえた2文以内の総評", "issues": ["具体的な減点理由1", "減点理由2"]}',
    '```',
  ]
    .filter(Boolean)
    .join('\n');

  const revRes = await runKasugaiAgentTurn({
    title: `[工場] 審査 v${genIndex}:${bp.name}`,
    provider: criticProvider,
    model: criticModel,
    cwd: genDir,
    prompt: criticPrompt,
    maxWaitMs: 3 * 60 * 1000,
    trace,
    tracePath,
  });

  const parsed = extractJsonValue(revRes.reply) || {
    score: g1.ok ? 78 : 45,
    summary: '実ブラウザ検証結果に基づく評価です。',
    issues: g1.errors,
  };
  const quality = Math.max(0, Math.min(100, Number(parsed.score || 0)));
  const scoreCalc = computeFitness({
    quality,
    gate1Ok: g1.ok,
    elapsedSeconds,
    totalTokens: workerRes.totalTokens,
    weights,
  });

  return {
    genIndex,
    factoryDir,
    webDir,
    shots: g1.shots,
    gate1Ok: g1.ok,
    gate1Errors: g1.errors,
    gate1Metrics: g1.metrics,
    quality,
    summary: String(parsed.summary || ''),
    issues: Array.isArray(parsed.issues) ? parsed.issues.map(String) : [],
    elapsedSeconds,
    workerTokens: workerRes.totalTokens,
    fitness: scoreCalc.fitness,
    timePenalty: scoreCalc.timePenalty,
    tokenPenalty: scoreCalc.tokenPenalty,
    workerThreadId: workerRes.threadId,
    criticThreadId: revRes.threadId,
  };
}

function buildMutatorPrompt({
  genIndex,
  bestEval,
  bestFactoryDir,
  nextFactoryDir,
  history,
  weights,
  userGoal,
}) {
  const bpText = readFileSync(join(bestFactoryDir, 'blueprint.json'), 'utf8');
  const specText = readFileSync(join(bestFactoryDir, 'spec.json'), 'utf8');
  const lintText = readFileSync(join(bestFactoryDir, 'lint.mjs'), 'utf8');
  return [
    `あなたは「工場改善工場（Optimizer）」の進化エンジニアです（第 ${genIndex} 世代の実験）。`,
    '現在のベスト工場の成績と実スクリーンショットを診断し、総合指標（Fitness）を確実に引き上げる **1 つの明確な仮説パッチ** を当てた次世代工場を作業ディレクトリへ書き出してください。',
    '',
    `## 書き出し先ディレクトリ（ここに blueprint.json / spec.json / lint.mjs / hypothesis.json の 4 ファイルを保存）`,
    nextFactoryDir,
    '',
    '## ユーザーの改善目標・重視指標',
    `${userGoal}（重み: ${weights.label}）`,
    '',
    '## 現在のベスト工場の実測成績',
    JSON.stringify(
      {
        gen: `v${bestEval.genIndex}`,
        fitness: bestEval.fitness,
        quality: bestEval.quality,
        gate1Ok: bestEval.gate1Ok,
        elapsedSeconds: bestEval.elapsedSeconds,
        workerTokens: bestEval.workerTokens,
        gate1Errors: bestEval.gate1Errors,
        criticSummary: bestEval.summary,
        criticIssues: bestEval.issues,
      },
      null,
      2
    ),
    '',
    '## 現在のベスト作品の実スクリーンショット（必ず目視して弱点を診断すること）',
    bestEval.shots?.initial ? `- 初期描画: ${bestEval.shots.initial}` : '',
    bestEval.shots?.after ? `- 操作後: ${bestEval.shots.after}` : '',
    '',
    '## これまでの実験履歴（REVERT された失敗仮説は絶対に繰り返さない）',
    JSON.stringify(history, null, 2),
    '',
    '## 現行ベスト工場のファイル',
    `### blueprint.json\n\`\`\`json\n${bpText}\n\`\`\``,
    `### spec.json\n\`\`\`json\n${specText}\n\`\`\``,
    `### lint.mjs\n\`\`\`js\n${lintText.slice(0, 5000)}\n\`\`\``,
    '',
    '## 出力要件',
    '1. 現行ベストの 3 ファイル（`blueprint.json`, `spec.json`, `lint.mjs`）をベースに、**1 つの明確な仮説**に基づいて改善版を書き出す（例: 視覚的レイアウトと配色の具体規約を強化 / 冗長な指示を削って速度とトークンを改善しつつ品質を上げる / Critic の減点項目を 0 トークン lint へ昇格させる）。',
    '2. `blueprint.json` の `id` と `runner_script` は絶対に変更しない。',
    '3. `hypothesis.json` に `{ "hypothesis": "1文の仮説", "changes": ["変更点1", "変更点2"], "expected_effect": "期待される指標変化" }` を書き出す。',
    '4. 最後に `node --check lint.mjs && node lint.mjs --self-test` を 1 回だけ確認して終了してください。',
  ]
    .filter(Boolean)
    .join('\n');
}

function renderEvolutionReportHtml({ target, evalPrompt, weights, generations, bestGenIndex }) {
  const v0 = generations[0];
  const best = generations.find((g) => g.genIndex === bestGenIndex) || v0;
  const dFit = Math.round((best.fitness - v0.fitness) * 10) / 10;
  const dQual = Math.round((best.quality - v0.quality) * 10) / 10;
  const dTime = Math.round((best.elapsedSeconds - v0.elapsedSeconds) * 10) / 10;
  const dTok = best.workerTokens - v0.workerTokens;

  const esc = (s) =>
    String(s || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');

  const chartW = 760;
  const chartH = 190;
  const padL = 44;
  const padR = 24;
  const padT = 20;
  const padB = 30;
  const innerW = chartW - padL - padR;
  const innerH = chartH - padT - padB;
  const maxX = Math.max(1, generations.length - 1);
  const px = (i) => padL + (i / maxX) * innerW;
  const py = (val) => padT + innerH - (Math.max(0, Math.min(100, val)) / 100) * innerH;

  const fitPts = generations.map((g, i) => `${px(i).toFixed(1)},${py(g.fitness).toFixed(1)}`).join(' ');
  const qualPts = generations.map((g, i) => `${px(i).toFixed(1)},${py(g.quality).toFixed(1)}`).join(' ');

  const svgNodes = generations
    .map((g, i) => {
      const cx = px(i).toFixed(1);
      const cy = py(g.fitness).toFixed(1);
      const col = g.verdict === 'BASELINE' ? '#94a3b8' : g.verdict === 'KEEP' ? '#22c55e' : '#ef4444';
      return `<circle cx="${cx}" cy="${cy}" r="6" fill="${col}" stroke="#0f131c" stroke-width="2" />
      <text x="${cx}" y="${(Number(cy) - 11).toFixed(1)}" text-anchor="middle" fill="#eef2ff" font-size="11" font-weight="700">${g.fitness}</text>
      <text x="${cx}" y="${chartH - 8}" text-anchor="middle" fill="#94a3b8" font-size="11">v${g.genIndex}</text>`;
    })
    .join('\n');

  const rowsHtml = generations
    .map((g) => {
      const badgeClass = g.verdict === 'KEEP' ? 'keep' : g.verdict === 'REVERT' ? 'revert' : 'base';
      const deltaStr =
        g.genIndex === 0
          ? '基準'
          : `${g.delta >= 0 ? '+' : ''}${g.delta}`;
      return `<tr>
        <td><strong>v${g.genIndex}</strong></td>
        <td><span class="badge ${badgeClass}">${g.verdict}</span></td>
        <td><strong>${g.fitness}</strong> <span class="muted">(${deltaStr})</span></td>
        <td>${g.quality} 点</td>
        <td>${g.gate1Ok ? '合格' : 'NG'}</td>
        <td>${g.elapsedSeconds} 秒</td>
        <td>約 ${(g.workerTokens / 1000).toFixed(1)}k</td>
        <td>${esc(g.hypothesis || '現行ベストの基準計測')}</td>
        <td><button class="open-btn" onclick="openGen(${g.genIndex})">作品を触る ↗</button></td>
      </tr>`;
    })
    .join('\n');

  return `<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>工場進化レポート — ${esc(target.name)}</title>
<style>
  :root { --bg:#0f131c; --panel:#171c28; --hi:#1f2738; --ink:#eef2ff; --muted:#94a3b8; --line:rgba(148,163,184,0.2); --accent:#6366f1; --ok:#22c55e; --danger:#ef4444; }
  * { box-sizing:border-box; margin:0; padding:0; }
  body { background:var(--bg); color:var(--ink); font-family:-apple-system,BlinkMacSystemFont,"Hiragino Sans",sans-serif; padding:18px 20px 44px; line-height:1.5; }
  .head { display:flex; justify-content:space-between; align-items:flex-end; flex-wrap:wrap; gap:12px; padding-bottom:14px; border-bottom:1px solid var(--line); margin-bottom:16px; }
  .title { font-size:20px; font-weight:800; }
  .sub { font-size:12px; color:var(--muted); margin-top:4px; }
  .kpis { display:grid; grid-template-columns:repeat(4,1fr); gap:12px; margin-bottom:16px; }
  .kpi { background:var(--panel); border:1px solid var(--line); border-radius:12px; padding:12px 14px; }
  .kpi-label { font-size:11px; color:var(--muted); font-weight:700; }
  .kpi-val { font-size:22px; font-weight:800; margin-top:2px; font-variant-numeric:tabular-nums; }
  .kpi-delta { font-size:12px; font-weight:700; margin-top:2px; }
  .good { color:#86efac; } .bad { color:#fca5a5; } .muted { color:var(--muted); }
  .panel { background:var(--panel); border:1px solid var(--line); border-radius:14px; padding:14px 16px; margin-bottom:16px; }
  .panel h2 { font-size:14px; font-weight:800; margin-bottom:10px; }
  .compare { display:grid; grid-template-columns:1fr 1fr; gap:14px; }
  .shot-card { background:var(--hi); border:1px solid var(--line); border-radius:12px; overflow:hidden; }
  .shot-card img { width:100%; display:block; aspect-ratio:16/10; object-fit:cover; background:#090c12; }
  .shot-meta { padding:10px 12px; display:flex; justify-content:space-between; align-items:center; gap:8px; }
  table { width:100%; border-collapse:collapse; font-size:12.5px; }
  th, td { padding:9px 10px; border-bottom:1px solid var(--line); text-align:left; vertical-align:middle; }
  th { color:var(--muted); font-size:11px; font-weight:700; }
  .badge { font-size:11px; font-weight:800; padding:2px 8px; border-radius:6px; }
  .badge.keep { background:rgba(34,197,94,0.18); color:#86efac; }
  .badge.revert { background:rgba(239,68,68,0.18); color:#fca5a5; }
  .badge.base { background:rgba(148,163,184,0.18); color:#cbd5e1; }
  .open-btn { background:var(--accent); color:#fff; border:0; border-radius:7px; padding:5px 10px; font-size:11.5px; font-weight:700; cursor:pointer; }
  .modal-bg { position:fixed; inset:0; background:rgba(7,10,18,0.84); display:none; align-items:center; justify-content:center; z-index:999; padding:16px; }
  .modal-bg.open { display:flex; }
  .modal { width:min(1120px,96vw); height:min(760px,90vh); background:var(--panel); border:1px solid rgba(255,255,255,0.18); border-radius:14px; overflow:hidden; display:flex; flex-direction:column; }
  .modal-head { display:flex; justify-content:space-between; align-items:center; padding:10px 14px; background:var(--hi); border-bottom:1px solid var(--line); }
  .modal-close { width:30px; height:30px; border-radius:8px; border:1px solid var(--line); background:var(--panel); color:#fff; font-size:16px; cursor:pointer; }
  .modal iframe { flex:1; border:0; width:100%; background:#111; }
</style>
</head>
<body>
  <div class="head">
    <div>
      <div class="title">工場進化レポート：${esc(target.name)}</div>
      <div class="sub">固定お題：「${esc(evalPrompt)}」 · 指標：${esc(weights.label)} · ベスト世代 v${best.genIndex} を正本へ反映済み</div>
    </div>
  </div>

  <div class="kpis">
    <div class="kpi">
      <div class="kpi-label">総合 Fitness（v0 → v${best.genIndex}）</div>
      <div class="kpi-val">${v0.fitness} → ${best.fitness}</div>
      <div class="kpi-delta ${dFit >= 0 ? 'good' : 'bad'}">${dFit >= 0 ? '+' : ''}${dFit} pt</div>
    </div>
    <div class="kpi">
      <div class="kpi-label">実スクショ品質スコア</div>
      <div class="kpi-val">${v0.quality} → ${best.quality} 点</div>
      <div class="kpi-delta ${dQual >= 0 ? 'good' : 'bad'}">${dQual >= 0 ? '+' : ''}${dQual} 点</div>
    </div>
    <div class="kpi">
      <div class="kpi-label">ポン出し稼働時間</div>
      <div class="kpi-val">${v0.elapsedSeconds} → ${best.elapsedSeconds} 秒</div>
      <div class="kpi-delta ${dTime <= 0 ? 'good' : 'bad'}">${dTime <= 0 ? '' : '+'}${dTime} 秒</div>
    </div>
    <div class="kpi">
      <div class="kpi-label">消費トークン量</div>
      <div class="kpi-val">${(v0.workerTokens / 1000).toFixed(1)}k → ${(best.workerTokens / 1000).toFixed(1)}k</div>
      <div class="kpi-delta ${dTok <= 0 ? 'good' : 'bad'}">${dTok <= 0 ? '' : '+'}${(dTok / 1000).toFixed(1)}k</div>
    </div>
  </div>

  <div class="panel">
    <h2>世代ごとの指標推移（実線：総合 Fitness / 破線：品質スコア）</h2>
    <svg viewBox="0 0 ${chartW} ${chartH}" style="width:100%; height:190px; display:block;">
      <line x1="${padL}" y1="${py(80)}" x2="${chartW - padR}" y2="${py(80)}" stroke="rgba(148,163,184,0.22)" stroke-dasharray="4 4" />
      <text x="${padL - 8}" y="${py(80) + 4}" text-anchor="end" fill="#94a3b8" font-size="10">80</text>
      <line x1="${padL}" y1="${py(50)}" x2="${chartW - padR}" y2="${py(50)}" stroke="rgba(148,163,184,0.14)" stroke-dasharray="4 4" />
      <text x="${padL - 8}" y="${py(50) + 4}" text-anchor="end" fill="#94a3b8" font-size="10">50</text>
      <polyline fill="none" stroke="#818cf8" stroke-width="2" stroke-dasharray="5 4" points="${qualPts}" />
      <polyline fill="none" stroke="#22c55e" stroke-width="3" points="${fitPts}" />
      ${svgNodes}
    </svg>
  </div>

  <div class="panel">
    <h2>ビフォーアフター比較（同じ固定お題のポン出し結果）</h2>
    <div class="compare">
      <div class="shot-card">
        <img src="gen-0/shots/shot_initial.png" alt="v0">
        <div class="shot-meta">
          <div><strong>Before · v0</strong>（Fitness ${v0.fitness} / ${v0.quality} 点 / ${v0.elapsedSeconds} 秒）</div>
          <button class="open-btn" onclick="openGen(0)">触る ↗</button>
        </div>
      </div>
      <div class="shot-card" style="border-color:rgba(34,197,94,0.6);">
        <img src="gen-${best.genIndex}/shots/shot_initial.png" alt="v${best.genIndex}">
        <div class="shot-meta">
          <div><strong>After · v${best.genIndex}（採用版）</strong>（Fitness ${best.fitness} / ${best.quality} 点 / ${best.elapsedSeconds} 秒）</div>
          <button class="open-btn" onclick="openGen(${best.genIndex})">触る ↗</button>
        </div>
      </div>
    </div>
  </div>

  <div class="panel">
    <h2>実験ログ（KEEP / REVERT 履歴）</h2>
    <table>
      <thead>
        <tr><th>世代</th><th>判定</th><th>Fitness</th><th>品質</th><th>Gate 1</th><th>時間</th><th>トークン</th><th>仮説</th><th>試作品</th></tr>
      </thead>
      <tbody>${rowsHtml}</tbody>
    </table>
  </div>

  <div class="modal-bg" id="modalBg">
    <div class="modal">
      <div class="modal-head">
        <strong id="modalTitle">試作品</strong>
        <button class="modal-close" id="modalClose">×</button>
      </div>
      <iframe id="modalFrame" src="about:blank"></iframe>
    </div>
  </div>
<script>
  function openGen(k) {
    document.getElementById('modalTitle').textContent = '世代 v' + k + ' ポン出し実作品';
    document.getElementById('modalFrame').src = 'gen-' + k + '/web/index.html';
    document.getElementById('modalBg').classList.add('open');
  }
  function closeModal() {
    document.getElementById('modalBg').classList.remove('open');
    document.getElementById('modalFrame').src = 'about:blank';
  }
  document.getElementById('modalClose').onclick = closeModal;
  document.getElementById('modalBg').onclick = (e) => { if (e.target.id === 'modalBg') closeModal(); };
</script>
</body>
</html>`;
}

async function runOptimizer({ runDir, tracePath }) {
  const trace = readJson(tracePath);
  const provider = trace.worker_provider || 'opencode_acp';
  const model = trace.worker_model || 'opencode-go/glm-5.3';
  const criticProvider = trace.critic_provider || 'opencode_acp';
  const criticModel = trace.critic_model || 'opencode-go/glm-5.3';
  const maxGen = Math.max(1, Math.min(5, Number(trace.max_iterations || 3)));

  trace.status = 'running';
  trace.started_at_ms = trace.started_at_ms || nowMs();
  trace.finished_at_ms = null;
  trace.input_tokens = trace.input_tokens || 0;
  trace.output_tokens = trace.output_tokens || 0;
  trace.tokens_estimated = true;
  trace.iterations = trace.iterations || [];

  const target = resolveTargetFactory(trace.prompt);
  const spec = existsSync(join(target.dir, 'spec.json')) ? readJson(join(target.dir, 'spec.json')) : {};
  const evalPrompt = parseEvalPrompt(trace.prompt, spec, target.bp);
  const weights = parseObjectiveWeights(trace.prompt);

  const reportRoot = join(runDir, 'report');
  mkdirSync(reportRoot, { recursive: true });

  const gen0Dir = join(reportRoot, 'gen-0');
  const gen0FactoryDir = join(gen0Dir, 'factory');
  mkdirSync(gen0FactoryDir, { recursive: true });
  copyFileSync(target.bpPath, join(gen0FactoryDir, 'blueprint.json'));
  if (existsSync(join(target.dir, 'spec.json'))) {
    copyFileSync(join(target.dir, 'spec.json'), join(gen0FactoryDir, 'spec.json'));
  } else {
    writeJsonAtomic(join(gen0FactoryDir, 'spec.json'), {
      factory_id: target.id,
      factory_name: target.name,
      sample_prompt: evalPrompt,
      worker_instructions: target.bp.summary || '',
      critic_rubric: ['視覚完成度', '独創性', '操作感', 'レイアウト清潔さ'],
    });
  }
  if (existsSync(join(target.dir, 'lint.mjs'))) {
    copyFileSync(join(target.dir, 'lint.mjs'), join(gen0FactoryDir, 'lint.mjs'));
  }

  trace.current_stage_id = 'baseline';
  appendLog(
    trace,
    tracePath,
    `工場改善工場を開始：対象「${target.name}」/ 指標「${weights.label}」/ 固定お題「${evalPrompt.slice(0, 36)}…」`
  );
  appendLog(trace, tracePath, 'v0 ベースラインを固定お題でゼロからポン出し計測中…');

  const baseEval = await evaluateFactoryOneShot({
    genIndex: 0,
    factoryDir: gen0FactoryDir,
    genDir: gen0Dir,
    evalPrompt,
    weights,
    provider,
    model,
    criticProvider,
    criticModel,
    trace,
    tracePath,
  });

  const generations = [
    { ...baseEval, verdict: 'BASELINE', delta: 0, hypothesis: '現行ベスト（v0 ベースライン）' },
  ];
  let best = generations[0];
  appendLog(
    trace,
    tracePath,
    `v0 計測完了：Fitness ${best.fitness}（品質 ${best.quality} 点 / ${best.elapsedSeconds} 秒 / 約 ${(best.workerTokens / 1000).toFixed(1)}k tok）`
  );

  const history = [];

  for (let gen = 1; gen <= maxGen; gen++) {
    const iterStart = Date.now();
    const genDir = join(reportRoot, `gen-${gen}`);
    const nextFactoryDir = join(genDir, 'factory');
    mkdirSync(nextFactoryDir, { recursive: true });

    trace.current_stage_id = 'mutate';
    appendLog(trace, tracePath, `第 ${gen} 世代: 現行ベスト（v${best.genIndex}）の実スクショと弱点を診断し仮説パッチを生成中…`);

    const mutRes = await runKasugaiAgentTurn({
      title: `[工場] 仮説パッチ v${gen}:${target.name}`,
      provider,
      model,
      cwd: nextFactoryDir,
      prompt: buildMutatorPrompt({
        genIndex: gen,
        bestEval: best,
        bestFactoryDir: best.factoryDir,
        nextFactoryDir,
        history,
        weights,
        userGoal: trace.prompt,
      }),
      maxWaitMs: 4 * 60 * 1000,
      trace,
      tracePath,
    });

    const hypObj = existsSync(join(nextFactoryDir, 'hypothesis.json'))
      ? readJson(join(nextFactoryDir, 'hypothesis.json'))
      : extractJsonValue(mutRes.reply) || {};
    const hypothesis = String(hypObj.hypothesis || `第 ${gen} 世代の設計規約・lint 強化`);

    const fCheck = validateFactoryDir(nextFactoryDir);
    if (!fCheck.ok) {
      const dur = Math.round(((Date.now() - iterStart) / 1000) * 10) / 10;
      history.push({ gen: `v${gen}`, hypothesis, verdict: 'REVERT', reason: fCheck.errors[0] });
      generations.push({
        genIndex: gen,
        factoryDir: nextFactoryDir,
        webDir: join(genDir, 'web'),
        shots: best.shots,
        gate1Ok: false,
        gate1Errors: fCheck.errors,
        gate1Metrics: [],
        quality: 0,
        summary: '改変した工場ファイル自体が検査落ちしたため自動 REVERT しました。',
        issues: fCheck.errors,
        elapsedSeconds: dur,
        workerTokens: 0,
        fitness: 0,
        verdict: 'REVERT',
        delta: Math.round((0 - best.fitness) * 10) / 10,
        hypothesis,
      });
      trace.iterations.push({
        index: gen,
        duration_seconds: dur,
        outcome: 'retry',
        badge_text: 'REVERT (構文NG)',
        active_loop_ids: ['evolve_loop'],
        loop_note: `第 ${gen} 世代 REVERT（改変工場の lint 自己テスト失敗）`,
        stuck_detected: false,
        panels: [
          {
            id: 'gate1',
            title: '3. 再計測（0 トークン）',
            status_text: 'REVERT',
            tone: 'danger',
            metrics: [{ label: '工場パッチ', value: '不正', tone: 'danger' }],
            summary: `仮説「${hypothesis}」の工場ファイルにエラーがあったため棄却しました。`,
            bullets: fCheck.errors.slice(0, 4),
            image_path: null,
            thread_id: mutRes.threadId,
            thread_label: '仮説パッチスレッドを表示',
          },
          {
            id: 'gate2',
            title: '4. 進化判定（KEEP / REVERT）',
            status_text: 'REVERT',
            tone: 'warning',
            metrics: [],
            summary: `現行ベスト v${best.genIndex}（Fitness ${best.fitness}）を維持します。`,
            bullets: [],
            image_path: null,
            thread_id: null,
            thread_label: '審査スレッドを表示',
          },
        ],
      });
      appendLog(trace, tracePath, `第 ${gen} 世代: 工場パッチ異常により REVERT`);
      continue;
    }

    trace.current_stage_id = 'evaluate';
    appendLog(trace, tracePath, `第 ${gen} 世代: 仮説「${hypothesis.slice(0, 40)}」を固定お題でゼロから再計測中…`);

    const evalRes = await evaluateFactoryOneShot({
      genIndex: gen,
      factoryDir: nextFactoryDir,
      genDir,
      evalPrompt,
      weights,
      provider,
      model,
      criticProvider,
      criticModel,
      trace,
      tracePath,
    });

    trace.current_stage_id = 'judge';
    const delta = Math.round((evalRes.fitness - best.fitness) * 10) / 10;
    const isKeep = evalRes.fitness > best.fitness;
    const verdict = isKeep ? 'KEEP' : 'REVERT';
    const record = { ...evalRes, verdict, delta, hypothesis };
    generations.push(record);
    history.push({
      gen: `v${gen}`,
      hypothesis,
      verdict,
      fitness: evalRes.fitness,
      delta,
      quality: evalRes.quality,
      elapsedSeconds: evalRes.elapsedSeconds,
      workerTokens: evalRes.workerTokens,
    });

    if (isKeep) {
      best = record;
      const installedDir = join(GENERATED_FACTORIES_DIR, target.id);
      mkdirSync(installedDir, { recursive: true });
      copyFileSync(join(nextFactoryDir, 'blueprint.json'), join(installedDir, 'blueprint.json'));
      copyFileSync(join(nextFactoryDir, 'spec.json'), join(installedDir, 'spec.json'));
      copyFileSync(join(nextFactoryDir, 'lint.mjs'), join(installedDir, 'lint.mjs'));
      mkdirSync(KASUGAI_BLUEPRINTS_DIR, { recursive: true });
      copyFileSync(join(nextFactoryDir, 'blueprint.json'), join(KASUGAI_BLUEPRINTS_DIR, `${target.id}.json`));
      appendLog(
        trace,
        tracePath,
        `第 ${gen} 世代: KEEP！（Fitness ${evalRes.fitness} / +${delta}）→ 「${target.name}」の正本を自動更新`
      );
    } else {
      appendLog(
        trace,
        tracePath,
        `第 ${gen} 世代: REVERT（Fitness ${evalRes.fitness} / ${delta}）→ v${best.genIndex}（${best.fitness}）を維持`
      );
    }

    const dur = Math.round(((Date.now() - iterStart) / 1000) * 10) / 10;
    trace.iterations.push({
      index: gen,
      duration_seconds: dur,
      outcome: isKeep ? 'passed' : 'retry',
      badge_text: `${verdict} ${delta >= 0 ? '+' : ''}${delta}`,
      active_loop_ids: gen < maxGen ? ['evolve_loop'] : [],
      loop_note: `第 ${gen} 世代 ${verdict}（Fitness ${evalRes.fitness} · 品質 ${evalRes.quality} 点 · ${evalRes.elapsedSeconds} 秒）`,
      stuck_detected: false,
      panels: [
        {
          id: 'gate1',
          title: '3. 再計測（ポン出し＆CDP）',
          status_text: evalRes.gate1Ok ? '合格' : '不合格',
          tone: evalRes.gate1Ok ? 'success' : 'danger',
          metrics: [
            { label: 'Fitness', value: `${evalRes.fitness}`, tone: isKeep ? 'success' : 'warning' },
            { label: '品質', value: `${evalRes.quality} 点`, tone: evalRes.quality >= 82 ? 'success' : 'neutral' },
            { label: '時間', value: `${evalRes.elapsedSeconds} 秒`, tone: 'neutral' },
            { label: 'トークン', value: `約 ${(evalRes.workerTokens / 1000).toFixed(1)}k`, tone: 'neutral' },
          ],
          summary: `仮説: ${hypothesis}`,
          bullets: evalRes.gate1Errors.slice(0, 4),
          image_path: evalRes.shots?.initial || null,
          thread_id: evalRes.workerThreadId,
          thread_label: '再計測スレッドを表示',
        },
        {
          id: 'gate2',
          title: '4. 進化判定（KEEP / REVERT）',
          status_text: `${verdict} (${delta >= 0 ? '+' : ''}${delta})`,
          tone: isKeep ? 'success' : 'warning',
          metrics: [],
          summary: isKeep
            ? `過去ベストを上回ったため KEEP 採用し、「${target.name}」正本を更新しました。${evalRes.summary}`
            : `過去ベスト（v${best.genIndex}: ${best.fitness}）を下回ったため REVERT しました。${evalRes.summary}`,
          bullets: evalRes.issues.slice(0, 4),
          image_path: evalRes.shots?.after || null,
          thread_id: evalRes.criticThreadId,
          thread_label: '審査スレッドを表示',
        },
      ],
    });
    saveTrace(trace, tracePath);
  }

  trace.current_stage_id = 'report';
  const html = renderEvolutionReportHtml({
    target,
    evalPrompt,
    weights,
    generations,
    bestGenIndex: best.genIndex,
  });
  writeFileSync(join(reportRoot, 'index.html'), html, 'utf8');
  writeJsonAtomic(join(runDir, 'evolution-summary.json'), {
    target: { id: target.id, name: target.name },
    evalPrompt,
    weights,
    bestGenIndex: best.genIndex,
    generations: generations.map((g) => ({
      genIndex: g.genIndex,
      verdict: g.verdict,
      fitness: g.fitness,
      delta: g.delta,
      quality: g.quality,
      gate1Ok: g.gate1Ok,
      elapsedSeconds: g.elapsedSeconds,
      workerTokens: g.workerTokens,
      hypothesis: g.hypothesis,
    })),
  });

  trace.local_preview_url = await startDetachedStaticServer(reportRoot);
  trace.status = 'preview_ready';
  trace.finished_at_ms = nowMs();
  appendLog(
    trace,
    tracePath,
    `進化レポートを右ペインへ配信しました（v0: ${generations[0].fitness} → ベスト v${best.genIndex}: ${best.fitness}）`
  );
  saveTrace(trace, tracePath);
}

async function main() {
  const { action, opts } = parseArgs(process.argv.slice(2));
  const runDir = resolve(opts['run-dir'] || '.');
  const tracePath = resolve(opts.trace || join(runDir, 'trace.json'));

  try {
    if (action === 'publish') {
      const trace = readJson(tracePath);
      trace.status = 'published';
      trace.production_url = trace.local_preview_url || 'kasugai://factory-evolved';
      appendLog(trace, tracePath, '進化済み工場を確定しました');
      return;
    }
    await runOptimizer({ runDir, tracePath });
  } catch (err) {
    if (existsSync(tracePath)) {
      const trace = readJson(tracePath);
      trace.status = 'failed';
      trace.finished_at_ms = nowMs();
      trace.error_message = String(err && err.message ? err.message : err);
      appendLog(trace, tracePath, `異常終了: ${trace.error_message}`);
    }
    console.error(err);
    process.exit(1);
  }
}

main();
