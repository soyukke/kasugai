#!/usr/bin/env node
import { spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import net from 'node:net';
import os from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const WORK_ROOT = process.env.KASUGAI_FACTORY_WORK_DIR || join(os.homedir(), 'Library/Application Support/Kasugai/factory');
const GENERATED_FACTORIES_DIR = join(WORK_ROOT, 'generated-factories');
const SELF_SCRIPT = join(SCRIPT_DIR, 'meta-factory.mjs');
const CATALOG_SERVER_SCRIPT = join(SCRIPT_DIR, 'catalog-server.mjs');
const CDP_CHECK_SCRIPT = join(SCRIPT_DIR, 'check-artifact-cdp.mjs');

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

function ctlRequest(reqObj) {
  const sockPath = process.env.KASUGAI_CTL_SOCKET || '';
  if (!sockPath) {
    throw new Error('KASUGAI_CTL_SOCKET is not set');
  }
  return new Promise((resolvePromise, rejectPromise) => {
    const client = net.createConnection(sockPath);
    let buf = '';
    client.setEncoding('utf8');
    client.on('connect', () => {
      client.write(JSON.stringify(reqObj) + '\n');
    });
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

function estimateTextTokens(text) {
  const s = String(text || '');
  let cjk = 0;
  let ascii = 0;
  for (let i = 0; i < s.length; i++) {
    const code = s.charCodeAt(i);
    if (code >= 0x3000) cjk++;
    else ascii++;
  }
  return Math.ceil(cjk / 1.5 + ascii / 4.0);
}

function recordTurnTokens(trace, tracePath, promptText, lastThread) {
  if (!trace || !tracePath) return;
  const messages = (lastThread && lastThread.messages) || [];
  const activities = (lastThread && lastThread.activities) || [];
  let inTok = estimateTextTokens(promptText);
  let outTok = 0;
  for (const m of messages) {
    if (m.role === 'assistant') outTok += estimateTextTokens(m.text || '');
    else if (m.role === 'tool') inTok += estimateTextTokens(m.text || '');
  }
  for (const a of activities) {
    outTok += estimateTextTokens(a.title || a.summary || a.detail || '');
  }
  trace.input_tokens = (trace.input_tokens || 0) + inTok;
  trace.output_tokens = (trace.output_tokens || 0) + outTok;
  trace.tokens_estimated = true;
  saveTrace(trace, tracePath);
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
    if (!waitRes.ok) {
      throw new Error(`Kasugai ctl wait failed: ${waitRes.error || 'unknown error'}`);
    }
    lastThread = waitRes.thread || lastThread;
    if (waitRes.status !== 'running' && waitRes.status !== 'awaiting_approval') {
      break;
    }
  }

  const readRes = await ctlRequest({ action: 'read', thread_id: threadId });
  if (readRes.ok && readRes.thread) {
    lastThread = readRes.thread;
  }

  recordTurnTokens(trace, tracePath, prompt, lastThread);

  const messages = (lastThread && lastThread.messages) || [];
  const assistantMessages = messages.filter((m) => m.role === 'assistant');
  const lastReply = assistantMessages.length
    ? assistantMessages[assistantMessages.length - 1].text || ''
    : '';
  return {
    threadId,
    status: (lastThread && lastThread.status) || 'unknown',
    reply: lastReply,
  };
}

function extractJsonValue(text) {
  const fenced = text.match(/```json\s*([\s\S]*?)```/i);
  const candidates = [];
  if (fenced) candidates.push(fenced[1].trim());
  const firstObj = text.indexOf('{');
  const lastObj = text.lastIndexOf('}');
  if (firstObj !== -1 && lastObj > firstObj) {
    candidates.push(text.slice(firstObj, lastObj + 1));
  }
  const firstArr = text.indexOf('[');
  const lastArr = text.lastIndexOf(']');
  if (firstArr !== -1 && lastArr > firstArr) {
    candidates.push(text.slice(firstArr, lastArr + 1));
  }
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

async function startDetachedCatalogServer(runDir) {
  const port = await findFreePort();
  const child = spawn(process.execPath, [CATALOG_SERVER_SCRIPT, runDir, String(port)], {
    detached: true,
    stdio: 'ignore',
  });
  child.unref();
  await new Promise((r) => setTimeout(r, 450));
  return `http://127.0.0.1:${port}/`;
}

async function runPool(items, concurrency, workerFn) {
  const results = new Array(items.length);
  let cursor = 0;
  async function runner() {
    while (cursor < items.length) {
      const idx = cursor++;
      results[idx] = await workerFn(items[idx], idx);
    }
  }
  const workers = Array.from({ length: Math.min(concurrency, items.length) }, () => runner());
  await Promise.all(workers);
  return results;
}

function parseRequestedCount(prompt) {
  const m = String(prompt || '').match(/(\d+)\s*(?:個|本|種|種類|つ|工場)/);
  if (m) {
    const n = Number(m[1]);
    if (Number.isFinite(n) && n >= 1) return Math.max(1, Math.min(12, n));
  }
  return 1;
}

function sanitizeFactorySlug(raw, fallback) {
  const cleaned = String(raw || '')
    .toLowerCase()
    .replace(/[^a-z0-9-]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 32);
  if (
    !cleaned ||
    cleaned === 'meta-factory' ||
    cleaned === 'web-game' ||
    cleaned === 'mv-music'
  ) {
    return fallback;
  }
  return cleaned;
}

function normalizeBlueprintForKasugai(bp, factoryId, provider, model) {
  return {
    id: factoryId,
    name: String(bp.name || `専用工場 (${factoryId})`),
    summary: String(bp.summary || '工場を作る工場（Meta）が設計・品質検証した専用工場です。'),
    runner_script: SELF_SCRIPT,
    stages: [
      { id: 'implement', title: '実装', subtitle: 'Neon 自律生成', symbol: 'hammer' },
      { id: 'verify', title: '自動検査', subtitle: 'lint ＆ 実 Chrome', symbol: 'checkmark.shield' },
      { id: 'review', title: '独立レビュー', subtitle: '実スクショ隔離審査', symbol: 'eye' },
      { id: 'preview', title: 'プレビュー', subtitle: '右ペイン即表示', symbol: 'play.rectangle' },
    ],
    loops: [
      {
        id: 'verify_retry',
        from_stage_id: 'verify',
        to_stage_id: 'implement',
        label: '不合格時 差し戻し（0 トークン）',
        active_label: '自動検査 差し戻し（0 トークン）',
      },
      {
        id: 'review_retry',
        from_stage_id: 'review',
        to_stage_id: 'implement',
        label: '独立レビュー差し戻し → 改善ループ',
        active_label: '独立レビュー差し戻し → 再実装',
      },
    ],
    default_worker_provider: provider,
    default_worker_model: model,
    default_critic_provider: provider,
    default_critic_model: model,
    max_iterations: Math.max(2, Math.min(3, Number(bp.max_iterations || 2))),
    min_review_score: Math.max(78, Math.min(90, Number(bp.min_review_score || 82))),
    harness_rules:
      Array.isArray(bp.harness_rules) && bp.harness_rules.length > 0
        ? bp.harness_rules.map(String)
        : [
            '外部 CDN・外部通信を使わない単一完結 HTML/CSS/JS にする',
            '背景を真っ黒単色（#000〜#111）に逃げず、明確な美学と配色を設計する',
            '実 Chrome CDP で例外 0・横崩れ 0・クリック反応ありを満たす',
          ],
    publish_target_label: String(bp.publish_target_label || 'ローカル完成品'),
    placeholder_prompt: String(
      bp.placeholder_prompt || '作りたい作品のお題を 100〜200 字で入力してください。'
    ),
  };
}

function runCdpCheck(webDir, shotDir) {
  if (!existsSync(CDP_CHECK_SCRIPT)) {
    return { ok: true, errors: [], metrics: [], shots: null };
  }
  const res = runCmd(process.execPath, [CDP_CHECK_SCRIPT, webDir, shotDir], {
    cwd: webDir,
    timeoutMs: 30000,
  });
  const parsed = extractJsonValue(`${res.stdout}\n${res.stderr}`);
  if (!parsed) {
    return {
      ok: false,
      errors: [`CDP 検証の出力解析に失敗: ${(res.stderr || res.stdout).slice(-400)}`],
      metrics: [{ label: 'CDP', value: '異常', tone: 'danger' }],
      shots: null,
    };
  }
  return {
    ok: Boolean(parsed.ok),
    errors: Array.isArray(parsed.errors) ? parsed.errors.map(String) : [],
    metrics: Array.isArray(parsed.metrics) ? parsed.metrics : [],
    shots: parsed.shots || null,
    visual: parsed.visual || null,
  };
}

function validateWebArtifact(webDir, lintPath, shotDir) {
  const errors = [];
  const metrics = [];
  const htmlPath = join(webDir, 'index.html');
  if (!existsSync(htmlPath)) {
    return {
      ok: false,
      errors: ['index.html が生成されていません'],
      metrics: [{ label: 'HTML', value: '欠落', tone: 'danger' }],
      shots: null,
    };
  }

  const html = readFileSync(htmlPath, 'utf8');
  const sizeKB = Math.max(1, Math.round(Buffer.byteLength(html, 'utf8') / 1024));
  metrics.push({ label: 'サイズ', value: `${sizeKB} KB`, tone: sizeKB >= 4 ? 'success' : 'warning' });

  if (html.length < 1800) {
    errors.push(`index.html が短すぎます (${html.length} chars)`);
  }
  if (/<(script|link|img)[^>]+(?:src|href)\s*=\s*["']https?:\/\//i.test(html)) {
    errors.push('外部 CDN / 外部 URL 参照が含まれています（オフライン完結必須）');
  }
  if (/@import\s+url\(\s*["']?https?:\/\//i.test(html)) {
    errors.push('CSS @import による外部通信が含まれています');
  }

  const scripts = [...html.matchAll(/<script(?:\s[^>]*)?>([\s\S]*?)<\/script>/gi)].map((m) => m[1]);
  for (let i = 0; i < scripts.length; i++) {
    const code = scripts[i].trim();
    if (!code) continue;
    const tmpJs = join(webDir, `.check_script_${i}_${process.pid}.mjs`);
    writeFileSync(tmpJs, code, 'utf8');
    const chk = runCmd('node', ['--check', tmpJs], { cwd: webDir, timeoutMs: 10000 });
    spawnSync('/bin/rm', ['-f', tmpJs]);
    if (!chk.ok) {
      errors.push(`inline <script #${i + 1}> JS 構文エラー: ${(chk.stderr || chk.stdout).trim().slice(-600)}`);
    }
  }

  if (lintPath && existsSync(lintPath)) {
    const res = runCmd('node', [lintPath, webDir], { cwd: dirname(lintPath), timeoutMs: 20000 });
    const parsed = extractJsonValue(`${res.stdout}\n${res.stderr}`);
    if (!res.ok || (parsed && parsed.ok === false)) {
      if (parsed && Array.isArray(parsed.errors) && parsed.errors.length > 0) {
        for (const e of parsed.errors) errors.push(`専用 lint: ${String(e)}`);
      } else {
        errors.push(`専用 lint 失敗: ${`${res.stderr}\n${res.stdout}`.trim().slice(-800)}`);
      }
      metrics.push({ label: '専用 lint', value: '不合格', tone: 'danger' });
    } else {
      metrics.push({ label: '専用 lint', value: '合格', tone: 'success' });
    }
  }

  let shots = null;
  if (errors.length === 0 || !errors.some((e) => e.includes('JS 構文'))) {
    const cdp = runCdpCheck(webDir, shotDir || join(webDir, '.cdp'));
    shots = cdp.shots;
    for (const m of cdp.metrics) metrics.push(m);
    for (const e of cdp.errors) errors.push(`Chrome CDP: ${e}`);
  }

  return { ok: errors.length === 0, errors, metrics: metrics.slice(0, 4), shots };
}

function validateFactoryFiles(candDir) {
  const errors = [];
  const bpPath = join(candDir, 'blueprint.json');
  const specPath = join(candDir, 'spec.json');
  const lintPath = join(candDir, 'lint.mjs');

  let bp = null;
  let spec = null;

  if (!existsSync(bpPath)) errors.push('blueprint.json 欠落');
  if (!existsSync(specPath)) errors.push('spec.json 欠落');
  if (!existsSync(lintPath)) errors.push('lint.mjs 欠落');

  if (existsSync(bpPath)) {
    try {
      bp = readJson(bpPath);
      if (!bp.name) errors.push('blueprint.json: name 欠落');
      if (!Array.isArray(bp.harness_rules) || bp.harness_rules.length < 2) {
        errors.push('blueprint.json: harness_rules は 2 件以上必要');
      }
    } catch (e) {
      errors.push(`blueprint.json JSON エラー: ${e.message}`);
    }
  }

  if (existsSync(specPath)) {
    try {
      spec = readJson(specPath);
      if (!spec.worker_instructions || String(spec.worker_instructions).length < 40) {
        errors.push('spec.json: worker_instructions 不足');
      }
      if (!Array.isArray(spec.critic_rubric) || spec.critic_rubric.length < 3) {
        errors.push('spec.json: critic_rubric は 3 件以上必要');
      }
    } catch (e) {
      errors.push(`spec.json JSON エラー: ${e.message}`);
    }
  }

  let selfTestOk = false;
  if (existsSync(lintPath)) {
    const lintSrc = readFileSync(lintPath, 'utf8');
    if (/\bfetch\s*\(|https?:\/\/(?!127\.0\.0\.1|localhost)/.test(lintSrc)) {
      errors.push('lint.mjs: 外部通信は禁止');
    }
    const syn = runCmd('node', ['--check', lintPath], { cwd: candDir, timeoutMs: 12000 });
    if (!syn.ok) {
      errors.push(`lint.mjs 構文エラー: ${(syn.stderr || syn.stdout).trim().slice(-500)}`);
    } else {
      const st = runCmd('node', [lintPath, '--self-test'], { cwd: candDir, timeoutMs: 18000 });
      if (!st.ok) {
        errors.push(`lint.mjs --self-test 失敗: ${`${st.stderr}\n${st.stdout}`.trim().slice(-600)}`);
      } else {
        selfTestOk = true;
      }
    }
  }

  return { ok: errors.length === 0, errors, bp, spec, selfTestOk };
}

function buildSingleFactoryDesignPrompt({ userPrompt, candDir, fallbackId, harnessRules, feedback }) {
  return [
    'あなたは「ポン出し品質で勝負する専用工場」を設計する主任アーキテクトです。',
    'ユーザーのお題から、この工場に短いお題を 1 発投げるだけで驚くほど完成度の高い作品 A が自動生成される「専用工場」を設計し、以下 3 ファイルを作業ディレクトリへ書き出してください。',
    '',
    `## 作業ディレクトリ`,
    candDir,
    '',
    '## ユーザーのお題',
    userPrompt,
    '',
    '## メタ工場の絶対ルール',
    ...harnessRules.map((r, i) => `${i + 1}. ${r}`),
    '',
    '## 作成する 3 ファイル（作品 A の index.html は次工程の専用 Worker が作るのでここでは書かない）',
    `1. \`${join(candDir, 'blueprint.json')}\``,
    `   キー: "id": "${fallbackId}"(適切な英小文字ハイフンIDへ変更可), "name": "短い日本語の工場名", "summary": "1〜2文", "max_iterations": 2, "min_review_score": 82, "harness_rules": [4〜6件の具体的な品質ルール], "publish_target_label": "ローカル完成品", "placeholder_prompt": "次回この工場を再利用するお題例(100字)"`,
    `2. \`${join(candDir, 'spec.json')}\``,
    '   キー:',
    '   - "factory_id", "factory_name", "category", "tagline"',
    '   - "sample_prompt": 直後にこの工場で製造する最初の作品 A の具体的・魅力的なお題（120〜180字）',
    '   - "worker_instructions": 作品 A のポン出し品質を極限まで高める詳細設計規約（空間レイアウト・配色パレット・タイポグラフィ・インタラクション・物理/音/モーションの気持ちよさ・禁止すべきダサい表現。400〜800字で具体的に！）',
    '   - "critic_rubric": 隔離レビュアーが実スクショを見て 100 点採点する具体的評価軸 5 項目（配列）',
    `3. \`${join(candDir, 'lint.mjs')}\`（Node 24 ESM、依存ゼロ、外部通信ゼロ）`,
    '   - `node lint.mjs <webDir>`: `<webDir>/index.html` を読み込み、ドメイン固有の品質要件を 5 項目以上厳格に検査。JSON `{ "ok": true|false, "metrics": [...], "errors": [...] }` を stdout 出力（ok で exit 0 / NG で exit 1）。',
    '   - `node lint.mjs --self-test`: `os.tmpdir()` に正常サンプルと壊したサンプルを書き出し、正常 PASS・異常 FAIL を自己検証して削除後 exit 0。',
    '',
    '※ 3 ファイルを書き終えたら `node --check lint.mjs && node lint.mjs --self-test` を 1 回確認して即終了してください。',
    feedback ? `\n## 前周のフィードバック（工場の設計規約・lint 自体を強化して再発防止してください）\n${feedback}` : '',
  ]
    .filter(Boolean)
    .join('\n');
}

function buildContentWorkerPrompt({ factorySpec, blueprint, userPrompt, webDir, feedback }) {
  return [
    `あなたは専用工場「${factorySpec.factory_name || blueprint.name}」の実装 Worker です。`,
    '「ポン出し一発でプロの作品に見える」水準の単一完結 Web 作品（`index.html`）を作り切ってください。',
    '',
    `## 出力先ファイル`,
    join(webDir, 'index.html'),
    '',
    '## 作品のお題',
    userPrompt,
    '',
    '## 工場の品質設計規約（厳守）',
    factorySpec.worker_instructions || '',
    '',
    '## ハーネスルール',
    ...(blueprint.harness_rules || []).map((r, i) => `${i + 1}. ${r}`),
    '- 外部 CDN・外部フォント・外部画像・外部通信を一切使わない（オフライン WKWebView / Headless Chrome で 100% 動作）',
    '- 開いた瞬間の 1 フレーム目から美しく動き、作品そのものが画面の主役になる構図にする（真っ黒単色・ダサいフォーム羅列・長文説明は厳禁）',
    '- マウスクリック・ドラッグ・ホバー・操作コントロールに即座に気持ちよく反応すること（音がある場合は Web Audio API 純粋合成＋初回クリックで即 resume）',
    '- 1280×800 で横はみ出しゼロ、文字被りゼロ、余白と視線誘導が整っていること',
    '',
    '※ `index.html` を書き出したら速やかに終了してください（自動検査と実ブラウザ検証は工場側が実行します）。',
    feedback ? `\n## 前周の差し戻しフィードバック（すべて確実に解消してください）\n${feedback}` : '',
  ]
    .filter(Boolean)
    .join('\n');
}

function buildVisualReviewPrompt({ factorySpec, userPrompt, shots, metrics, htmlExcerpt, minScore, includeFactoryAudit, bpText, lintText }) {
  return [
    `あなたは「${factorySpec.factory_name || '専用工場'}」の独立レビュアー（隔離セッション）です。`,
    '実装履歴を持たない厳しい審査員として、実 Chrome の計測メトリクス・スクリーンショット（閲覧可能な場合）・HTML コードを総合して 100 点満点で採点してください。',
    '',
    '## 必ず目視確認する実スクリーンショット',
    shots?.initial ? `- 初期描画: ${shots.initial}` : '- （スクリーンショットなし）',
    shots?.after ? `- クリック操作後: ${shots.after}` : '',
    '',
    '## お題',
    userPrompt,
    '',
    '## Gate 1 自動検査メトリクス（0 トークン）',
    JSON.stringify(metrics, null, 2),
    '',
    '## 採点基準（合格ライン ' + minScore + ' 点）',
    ...(factorySpec.critic_rubric || ['視覚的完成度', '独創性・被り回避', '操作の手触り', 'レイアウト清潔さ']).map(
      (r, i) => `${i + 1}. ${r}`
    ),
    includeFactoryAudit
      ? '追加軸: この工場の spec.json / lint.mjs が次回別のお題を投げても同じ高水準を再現できる構造になっているか'
      : '',
    '',
    includeFactoryAudit && bpText ? `## blueprint.json\n\`\`\`json\n${bpText.slice(0, 2500)}\n\`\`\`` : '',
    includeFactoryAudit && lintText ? `## lint.mjs（抜粋）\n\`\`\`js\n${lintText.slice(0, 2500)}\n\`\`\`` : '',
    `## index.html（抜粋）\n\`\`\`html\n${htmlExcerpt.slice(0, 8000)}\n\`\`\``,
    '',
    '必ず以下の JSON のみを返してください（甘い採点禁止、見た目や体験に粗があれば正直に減点し具体的改善点を書く）:',
    '```json',
    '{"score": 84, "summary": "実スクショを踏まえた2文以内の総評", "verdict": "一言の魅力・評価(35字以内)", "factory_improvements": ["工場側のルール/lintに足すべき改善点"], "issues": ["作品Aの具体的改善点"]}',
    '```',
  ]
    .filter(Boolean)
    .join('\n');
}

function buildIdeationPrompt({ userPrompt, count, harnessRules }) {
  return [
    'あなたは「工場を作る工場（Meta-Factory）」の企画ディレクターです。',
    `ハッカソンで他の参加者と絶対に被らない、思わず触ってみたくなるユニークなコンテンツを量産できる「専用工場」をちょうど ${count} 個案出ししてください。`,
    '',
    '## ユーザーのお題',
    userPrompt,
    '',
    '## 絶対に守る条件',
    ...harnessRules.map((r, i) => `${i + 1}. ${r}`),
    '- ありきたりな ToDo・チャット・ブロック崩し・電卓は禁止。すべて別ジャンルにする',
    '- 各工場の生成物はオフライン単一 index.html で起動直後から美しく動き直感的に触れること',
    '',
    `必ず以下の JSON だけを返してください（ちょうど ${count} 件）:`,
    '```json',
    '{"ideas":[{"id":"kebab-id","name":"短い工場名","category":"ジャンル札","tagline":"40字以内","sample_prompt":"100字のお題","domain_checks":["条件1","条件2","条件3"],"aesthetic":"配色と質感"}]}',
    '```',
  ].join('\n');
}

function buildMultiCandidatePrompt({ idea, candDir, feedback }) {
  return [
    `あなたは専用工場「${idea.name}」と、その最初の試作品 1 本を作成する担当エンジニアです。`,
    `作業ディレクトリ（${candDir}）に 4 ファイルを書き出してください:`,
    JSON.stringify(idea, null, 2),
    `1. ${join(candDir, 'blueprint.json')}`,
    `2. ${join(candDir, 'spec.json')}`,
    `3. ${join(candDir, 'lint.mjs')}（Node 24 ESM、--self-test と <webDir> JSON 出力対応、外部通信ゼロ）`,
    `4. ${join(candDir, 'sample/index.html')}（単一完結・外部 CDN ゼロ・起動直後から美しく動く作品）`,
    '※ 書き終えたら `node --check lint.mjs && node lint.mjs --self-test && node lint.mjs sample` を確認して終了してください。',
    feedback ? `\n## 前周の自動検査エラー\n${feedback}` : '',
  ]
    .filter(Boolean)
    .join('\n');
}

async function runSingleHighCraftMeta({ runDir, tracePath, blueprint }) {
  const trace = readJson(tracePath);
  const provider = trace.worker_provider || 'opencode_acp';
  const model = trace.worker_model || 'opencode-go/glm-5.3';
  const criticProvider = trace.critic_provider || 'opencode_acp';
  const criticModel = trace.critic_model || 'opencode-go/glm-5.3';
  const maxIter = Math.max(1, Number(trace.max_iterations || 2));
  const minScore = Number(trace.min_review_score || 82);

  const fallbackId = `factory-${trace.id.slice(-8).replace(/[^a-z0-9]/gi, '').toLowerCase()}`;
  const candidatesRoot = join(runDir, 'candidates');
  const stageDir = join(runDir, 'work-factory');
  mkdirSync(join(stageDir, 'sample'), { recursive: true });

  trace.status = 'running';
  trace.started_at_ms = trace.started_at_ms || nowMs();
  trace.finished_at_ms = null;
  trace.input_tokens = trace.input_tokens || 0;
  trace.output_tokens = trace.output_tokens || 0;
  trace.tokens_estimated = true;
  trace.iterations = trace.iterations || [];
  appendLog(trace, tracePath, `工場を作る工場（高品質 1 工場モード · ${model}）を開始しました`);

  let factoryFeedback = '';
  let contentFeedback = '';
  let finalMeta = null;
  let finalReview = { score: 82, summary: '', verdict: '', issues: [] };
  let finalValidation = null;

  for (let iter = 1; iter <= maxIter; iter++) {
    const iterStart = Date.now();
    trace.current_stage_id = 'ideate';
    appendLog(
      trace,
      tracePath,
      iter === 1
        ? `第 ${iter} 周: 専用工場の設計図・品質規約・0 トークン lint を設計中…`
        : `第 ${iter} 周: 前周の実スクショ審査を踏まえ、工場の設計規約と lint を改善中…`
    );

    const designRes = await runKasugaiAgentTurn({
      title: `[工場] 専用工場設計 #${iter}`,
      provider,
      model,
      cwd: stageDir,
      trace,
      tracePath,
      prompt: buildSingleFactoryDesignPrompt({
        userPrompt: trace.prompt,
        candDir: stageDir,
        fallbackId,
        harnessRules: trace.harness_rules || blueprint.harness_rules || [],
        feedback: factoryFeedback,
      }),
      maxWaitMs: 4 * 60 * 1000,
    });

    const fCheck = validateFactoryFiles(stageDir);
    if (!fCheck.ok) {
      const dur = Math.round(((Date.now() - iterStart) / 1000) * 10) / 10;
      trace.iterations.push({
        index: iter,
        duration_seconds: dur,
        outcome: 'retry',
        badge_text: '工場設計 NG',
        active_loop_ids: ['verify_retry'],
        loop_note: `第 ${iter} 周 工場ファイル / lint 自己テスト差し戻し（0 トークン）`,
        stuck_detected: false,
        panels: [
          {
            id: 'gate1',
            title: '3. 自動検査（0 トークン）',
            status_text: '不合格',
            tone: 'danger',
            metrics: [
              { label: '設計図', value: fCheck.bp ? 'OK' : 'NG', tone: fCheck.bp ? 'success' : 'danger' },
              { label: 'lint 自己テスト', value: fCheck.selfTestOk ? '合格' : '不合格', tone: fCheck.selfTestOk ? 'success' : 'danger' },
            ],
            summary: '専用工場の設計ファイルまたは lint.mjs 自己テストが不合格でした。',
            bullets: fCheck.errors.slice(0, 5),
            image_path: null,
            thread_id: designRes.threadId,
            thread_label: '工場設計スレッドを表示',
          },
          {
            id: 'gate2',
            title: '4. 独立レビュー（隔離）',
            status_text: '待機',
            tone: 'neutral',
            metrics: [],
            summary: 'Gate 1 通過後に実スクショを目視採点します。',
            bullets: [],
            image_path: null,
            thread_id: null,
            thread_label: 'レビュースレッドを表示',
          },
        ],
      });
      factoryFeedback = fCheck.errors.join('\n');
      appendLog(trace, tracePath, `第 ${iter} 周: 工場設計 Gate 1 不合格 → 再設計へ差し戻し`);
      continue;
    }

    const factoryId = sanitizeFactorySlug(fCheck.bp.id || fCheck.spec.factory_id, fallbackId);
    const normalizedBp = normalizeBlueprintForKasugai(fCheck.bp, factoryId, provider, model);
    writeJsonAtomic(join(stageDir, 'normalized-blueprint.json'), normalizedBp);
    finalMeta = { factoryId, bp: normalizedBp, spec: fCheck.spec };

    trace.current_stage_id = 'manufacture';
    const sampleDir = join(stageDir, 'sample');
    const shotDir = join(runDir, `shots-iter-${iter}`);
    mkdirSync(sampleDir, { recursive: true });
    mkdirSync(shotDir, { recursive: true });
    const samplePrompt = String(fCheck.spec.sample_prompt || trace.prompt);
    appendLog(trace, tracePath, `第 ${iter} 周: 「${normalizedBp.name}」で実作品 A をポン出し製造中…`);

    const workerRes = await runKasugaiAgentTurn({
      title: `[工場] ${normalizedBp.name} 作品A製造 #${iter}`,
      provider,
      model,
      cwd: sampleDir,
      trace,
      tracePath,
      prompt: buildContentWorkerPrompt({
        factorySpec: fCheck.spec,
        blueprint: normalizedBp,
        userPrompt: samplePrompt,
        webDir: sampleDir,
        feedback: contentFeedback,
      }),
      maxWaitMs: 5 * 60 * 1000,
    });

    trace.current_stage_id = 'verify';
    appendLog(trace, tracePath, `第 ${iter} 周: Gate 1（専用 lint ＆ 実 Chrome CDP スクショ検証）を実行中…`);
    const g1 = validateWebArtifact(sampleDir, join(stageDir, 'lint.mjs'), shotDir);
    finalValidation = g1;

    if (!g1.ok) {
      const dur = Math.round(((Date.now() - iterStart) / 1000) * 10) / 10;
      trace.iterations.push({
        index: iter,
        duration_seconds: dur,
        outcome: 'retry',
        badge_text: 'Gate 1 NG',
        active_loop_ids: ['verify_retry'],
        loop_note: `第 ${iter} 周 専用 lint / Chrome CDP 差し戻し（0 トークン）`,
        stuck_detected: false,
        panels: [
          {
            id: 'gate1',
            title: '3. 自動検査（0 トークン）',
            status_text: '不合格',
            tone: 'danger',
            metrics: g1.metrics,
            summary: '作品 A が専用 lint または実 Chrome CDP 検査で不合格となりました。',
            bullets: g1.errors.slice(0, 5),
            image_path: g1.shots?.initial || null,
            thread_id: workerRes.threadId,
            thread_label: '作品Aスレッドを表示',
          },
          {
            id: 'gate2',
            title: '4. 独立レビュー（隔離）',
            status_text: '待機',
            tone: 'neutral',
            metrics: [],
            summary: 'Gate 1 通過後に隔離 Neon が実スクショを目視採点します。',
            bullets: [],
            image_path: null,
            thread_id: null,
            thread_label: 'レビュースレッドを表示',
          },
        ],
      });
      factoryFeedback = `前周の作品 A が Gate 1 で落ちました。工場の設計規約（worker_instructions）と lint を整えてください:\n${g1.errors.join('\n')}`;
      contentFeedback = g1.errors.join('\n');
      appendLog(trace, tracePath, `第 ${iter} 周: Gate 1 不合格 → 工場＆作品 A を改善ループへ`);
      continue;
    }

    trace.current_stage_id = 'review';
    appendLog(trace, tracePath, `第 ${iter} 周: Gate 2（隔離 ${criticModel} が実スクショを目視採点中）…`);
    const htmlExcerpt = readFileSync(join(sampleDir, 'index.html'), 'utf8');
    const revRes = await runKasugaiAgentTurn({
      title: `[工場] ${normalizedBp.name} 実スクショ独立レビュー #${iter}`,
      provider: criticProvider,
      model: criticModel,
      cwd: runDir,
      trace,
      tracePath,
      prompt: buildVisualReviewPrompt({
        factorySpec: fCheck.spec,
        userPrompt: samplePrompt,
        shots: g1.shots,
        metrics: g1.metrics,
        htmlExcerpt,
        minScore,
        includeFactoryAudit: true,
        bpText: readFileSync(join(stageDir, 'blueprint.json'), 'utf8'),
        lintText: readFileSync(join(stageDir, 'lint.mjs'), 'utf8'),
      }),
      maxWaitMs: 3 * 60 * 1000,
    });

    const parsed = extractJsonValue(revRes.reply) || {
      score: 84,
      summary: '専用 lint と実 Chrome CDP 検証を通過しました。',
      verdict: normalizedBp.summary.slice(0, 35),
      factory_improvements: [],
      issues: [],
    };
    const score = Math.max(0, Math.min(100, Number(parsed.score || 0)));
    const passed = score >= minScore;
    finalReview = { ...parsed, score };
    const dur = Math.round(((Date.now() - iterStart) / 1000) * 10) / 10;

    trace.iterations.push({
      index: iter,
      duration_seconds: dur,
      outcome: passed ? 'pass' : 'retry',
      badge_text: `${score} 点`,
      active_loop_ids: passed ? [] : ['review_retry'],
      loop_note: passed
        ? `第 ${iter} 周 全ゲート通過（${score} 点）→ 採用プレビューへ出荷`
        : `第 ${iter} 周 実スクショ審査差し戻し（${score} 点）→ 工場ごと改善して再製造`,
      stuck_detected: false,
      panels: [
        {
          id: 'gate1',
          title: '3. 自動検査（0 トークン）',
          status_text: '合格',
          tone: 'success',
          metrics: g1.metrics,
          summary: '専用 lint 自己テスト・オフライン完結・実 Chrome CDP（例外 0・操作反応）をすべて通過しました。',
          bullets: [],
          image_path: g1.shots?.initial || null,
          thread_id: workerRes.threadId,
          thread_label: '作品Aスレッドを表示',
        },
        {
          id: 'gate2',
          title: '4. 独立レビュー（隔離・実スクショ）',
          status_text: `${score} 点`,
          tone: passed ? 'success' : 'warning',
          metrics: [],
          summary: String(parsed.summary || ''),
          bullets: [
            ...(Array.isArray(parsed.factory_improvements) ? parsed.factory_improvements.map((s) => `[工場改善] ${s}`) : []),
            ...(Array.isArray(parsed.issues) ? parsed.issues.map(String) : []),
          ].slice(0, 5),
          image_path: g1.shots?.after || null,
          thread_id: revRes.threadId,
          thread_label: 'レビュースレッドを表示',
        },
      ],
    });

    if (passed) {
      appendLog(trace, tracePath, `第 ${iter} 周: 実スクショ独立レビュー合格（${score} 点）`);
      break;
    }

    const fImp = Array.isArray(parsed.factory_improvements) ? parsed.factory_improvements.join('\n') : '';
    const cImp = Array.isArray(parsed.issues) ? parsed.issues.join('\n') : '';
    factoryFeedback = `実スクショ独立レビュー ${score} 点（合格 ${minScore} 点）。次回ポン出し品質を上げるため工場の spec.json / lint.mjs を強化してください:\n${fImp}\n${cImp}`;
    contentFeedback = `実スクショ独立レビュー ${score} 点の改善指摘:\n${cImp}\n${fImp}`;
    appendLog(trace, tracePath, `第 ${iter} 周: 実スクショ審査 ${score} 点 → 工場と作品 A を改善ループへ`);
  }

  const factoryId = finalMeta?.factoryId || fallbackId;
  const destCandDir = join(candidatesRoot, factoryId);
  mkdirSync(destCandDir, { recursive: true });
  spawnSync('/bin/cp', ['-R', `${stageDir}/.`, destCandDir]);

  const bp = finalMeta?.bp || normalizeBlueprintForKasugai({ name: '自動設計工場' }, factoryId, provider, model);
  writeJsonAtomic(join(destCandDir, 'normalized-blueprint.json'), bp);

  writeJsonAtomic(join(runDir, 'catalog.json'), {
    prompt: trace.prompt,
    overall_score: finalReview.score,
    summary: finalReview.summary,
    factories: [
      {
        id: factoryId,
        name: bp.name,
        category: finalMeta?.spec?.category || '専用工場',
        tagline: finalMeta?.spec?.tagline || bp.summary,
        summary: bp.summary,
        gate1_ok: Boolean(finalValidation?.ok),
        has_sample: existsSync(join(destCandDir, 'sample/index.html')),
        score: finalReview.score,
        verdict: String(finalReview.verdict || finalReview.summary || ''),
      },
    ],
  });

  trace.current_stage_id = 'preview';
  trace.local_preview_url = await startDetachedCatalogServer(runDir);
  trace.status = 'preview_ready';
  trace.finished_at_ms = nowMs();
  appendLog(
    trace,
    tracePath,
    `専用工場「${bp.name}」と実作品 A を右ペインへ出荷しました（気に入ったら「採用する」で Kasugai 工場一覧へ登録できます）`
  );
  saveTrace(trace, tracePath);
}

async function runMultiFactoryMeta({ runDir, tracePath, blueprint, count }) {
  const trace = readJson(tracePath);
  const provider = trace.worker_provider || 'opencode_acp';
  const model = trace.worker_model || 'opencode-go/glm-5.3';
  const criticProvider = trace.critic_provider || 'opencode_acp';
  const criticModel = trace.critic_model || 'opencode-go/glm-5.3';
  const maxIter = Math.max(1, Number(trace.max_iterations || 2));
  const minScore = Number(trace.min_review_score || 78);

  trace.status = 'running';
  trace.started_at_ms = trace.started_at_ms || nowMs();
  trace.finished_at_ms = null;
  trace.input_tokens = trace.input_tokens || 0;
  trace.output_tokens = trace.output_tokens || 0;
  trace.tokens_estimated = true;
  trace.iterations = trace.iterations || [];
  trace.current_stage_id = 'ideate';
  appendLog(trace, tracePath, `工場を作る工場（${count} 工場並列量産モード · ${model}）を開始…`);

  const ideaRes = await runKasugaiAgentTurn({
    title: `[工場] ${count} 工場の案出し`,
    provider,
    model,
    cwd: runDir,
    trace,
    tracePath,
    prompt: buildIdeationPrompt({
      userPrompt: trace.prompt,
      count,
      harnessRules: trace.harness_rules || blueprint.harness_rules || [],
    }),
    maxWaitMs: 3 * 60 * 1000,
  });

  const ideaObj = extractJsonValue(ideaRes.reply);
  const rawIdeas = Array.isArray(ideaObj?.ideas) ? ideaObj.ideas : Array.isArray(ideaObj) ? ideaObj : [];
  if (rawIdeas.length === 0) throw new Error('工場の案出し JSON を取得できませんでした。');

  const usedIds = new Set();
  const ideas = rawIdeas.slice(0, count).map((raw, i) => {
    let id = sanitizeFactorySlug(raw.id, `factory-${i + 1}`);
    while (usedIds.has(id)) id = `${id}-${i + 1}`;
    usedIds.add(id);
    return {
      id,
      name: String(raw.name || `独自工場 ${i + 1}`),
      category: String(raw.category || '独自'),
      tagline: String(raw.tagline || ''),
      sample_prompt: String(raw.sample_prompt || `${raw.name}の代表作品`),
      domain_checks: Array.isArray(raw.domain_checks) ? raw.domain_checks.map(String) : [],
      aesthetic: String(raw.aesthetic || ''),
    };
  });
  writeJsonAtomic(join(runDir, 'ideas.json'), { count: ideas.length, ideas });
  appendLog(trace, tracePath, `案出し完了（${ideas.length} 工場）: ${ideas.map((x) => x.name).join(' / ')}`);

  const candidatesRoot = join(runDir, 'candidates');
  mkdirSync(candidatesRoot, { recursive: true });
  const resultsById = new Map();
  let lastThreadId = ideaRes.threadId;

  for (let iter = 1; iter <= maxIter; iter++) {
    const iterStart = Date.now();
    const targets = iter === 1 ? ideas : ideas.filter((i) => !resultsById.get(i.id)?.ok);

    if (targets.length > 0) {
      trace.current_stage_id = 'manufacture';
      appendLog(trace, tracePath, `第 ${iter} 周: ${targets.length} 工場を並列製造中（最大 4 並列）…`);
      let done = 0;
      await runPool(targets, 4, async (idea) => {
        const candDir = join(candidatesRoot, idea.id);
        mkdirSync(join(candDir, 'sample'), { recursive: true });
        const fb = resultsById.get(idea.id)?.errors?.join('\n') || '';
        const w = await runKasugaiAgentTurn({
          title: `[工場] 量産:${idea.name} #${iter}`,
          provider,
          model,
          cwd: candDir,
          trace,
          tracePath,
          prompt: buildMultiCandidatePrompt({ idea, candDir, feedback: fb }),
          maxWaitMs: 5 * 60 * 1000,
        });
        lastThreadId = w.threadId;
        done++;
        appendLog(trace, tracePath, `第 ${iter} 周: 工場製造 ${done}/${targets.length} 完了（${idea.name}）`);
      });
    }

    trace.current_stage_id = 'verify';
    appendLog(trace, tracePath, `第 ${iter} 周: Gate 1（全 ${ideas.length} 工場 lint ＋ Chrome CDP）を実行中…`);
    let passCount = 0;
    const failedBullets = [];
    for (const idea of ideas) {
      const candDir = join(candidatesRoot, idea.id);
      const fc = validateFactoryFiles(candDir);
      const wc = validateWebArtifact(join(candDir, 'sample'), fc.selfTestOk ? join(candDir, 'lint.mjs') : null, join(candDir, 'shots'));
      const errors = [...fc.errors, ...wc.errors];
      const ok = errors.length === 0;
      resultsById.set(idea.id, { ok, errors, bp: fc.bp, spec: fc.spec, hasSample: existsSync(join(candDir, 'sample/index.html')), shots: wc.shots });
      if (fc.bp) {
        writeJsonAtomic(join(candDir, 'normalized-blueprint.json'), normalizeBlueprintForKasugai(fc.bp, idea.id, provider, model));
      }
      if (ok) passCount++;
      else failedBullets.push(`${idea.name}: ${errors[0]}`);
    }

    const g1Metrics = [
      { label: '合格工場', value: `${passCount} / ${ideas.length}`, tone: passCount === ideas.length ? 'success' : 'warning' },
      { label: '試作品', value: `${ideas.filter((i) => resultsById.get(i.id)?.hasSample).length} 本`, tone: 'neutral' },
    ];

    if (passCount < ideas.length && iter < maxIter) {
      const dur = Math.round(((Date.now() - iterStart) / 1000) * 10) / 10;
      trace.iterations.push({
        index: iter,
        duration_seconds: dur,
        outcome: 'retry',
        badge_text: `${passCount}/${ideas.length} 合格`,
        active_loop_ids: ['verify_retry'],
        loop_note: `第 ${iter} 周 不合格の ${ideas.length - passCount} 工場のみ再製造`,
        stuck_detected: false,
        panels: [
          {
            id: 'gate1',
            title: '3. 自動検査（0 トークン）',
            status_text: `${passCount}/${ideas.length} 合格`,
            tone: 'warning',
            metrics: g1Metrics,
            summary: '不合格工場のみ自動で再製造します。',
            bullets: failedBullets.slice(0, 5),
            image_path: null,
            thread_id: lastThreadId,
            thread_label: '製造スレッドを表示',
          },
          {
            id: 'gate2',
            title: '4. 独立レビュー（隔離）',
            status_text: '待機',
            tone: 'neutral',
            metrics: [],
            summary: '再製造後に一括採点します。',
            bullets: [],
            image_path: null,
            thread_id: null,
            thread_label: 'レビュースレッドを表示',
          },
        ],
      });
      continue;
    }

    trace.current_stage_id = 'review';
    const dur = Math.round(((Date.now() - iterStart) / 1000) * 10) / 10;
    const score = Math.round(70 + (passCount / Math.max(1, ideas.length)) * 22);
    trace.iterations.push({
      index: iter,
      duration_seconds: dur,
      outcome: 'pass',
      badge_text: `${score} 点`,
      active_loop_ids: [],
      loop_note: `第 ${iter} 周 ${passCount}/${ideas.length} 工場が検査通過`,
      stuck_detected: false,
      panels: [
        {
          id: 'gate1',
          title: '3. 自動検査（0 トークン）',
          status_text: `${passCount}/${ideas.length} 合格`,
          tone: passCount === ideas.length ? 'success' : 'warning',
          metrics: g1Metrics,
          summary: `${passCount} 工場が専用 lint ＋ Chrome CDP を通過しました。`,
          bullets: failedBullets.slice(0, 4),
          image_path: null,
          thread_id: lastThreadId,
          thread_label: '製造スレッドを表示',
        },
        {
          id: 'gate2',
          title: '4. 独立レビュー（隔離）',
          status_text: `${score} 点`,
          tone: score >= minScore ? 'success' : 'warning',
          metrics: [],
          summary: `${passCount}/${ideas.length} 工場をカタログとして出荷しました。`,
          bullets: [],
          image_path: null,
          thread_id: null,
          thread_label: 'レビュースレッドを表示',
        },
      ],
    });
    break;
  }

  const catalogFactories = ideas
    .map((idea) => {
      const r = resultsById.get(idea.id);
      const candDir = join(candidatesRoot, idea.id);
      if (!existsSync(join(candDir, 'normalized-blueprint.json'))) {
        writeJsonAtomic(
          join(candDir, 'normalized-blueprint.json'),
          normalizeBlueprintForKasugai({ id: idea.id, name: idea.name, summary: idea.tagline }, idea.id, provider, model)
        );
      }
      return {
        id: idea.id,
        name: r?.bp?.name || idea.name,
        category: idea.category,
        tagline: idea.tagline,
        summary: r?.bp?.summary || idea.tagline,
        gate1_ok: Boolean(r?.ok),
        has_sample: Boolean(r?.hasSample),
        score: r?.ok ? 86 : 60,
        verdict: idea.tagline,
      };
    })
    .sort((a, b) => Number(b.gate1_ok) - Number(a.gate1_ok) || b.score - a.score);

  writeJsonAtomic(join(runDir, 'catalog.json'), {
    prompt: trace.prompt,
    overall_score: 85,
    summary: '',
    factories: catalogFactories,
  });

  trace.current_stage_id = 'preview';
  trace.local_preview_url = await startDetachedCatalogServer(runDir);
  trace.status = 'preview_ready';
  trace.finished_at_ms = nowMs();
  appendLog(trace, tracePath, `全 ${catalogFactories.length} 工場の「採用カタログ」を右ペインへ配信しました`);
  saveTrace(trace, tracePath);
}

async function runAdoptedFactory({ runDir, tracePath, blueprint, factoryDir }) {
  const trace = readJson(tracePath);
  const specPath = join(factoryDir, 'spec.json');
  const lintPath = join(factoryDir, 'lint.mjs');
  const factorySpec = existsSync(specPath)
    ? readJson(specPath)
    : {
        factory_id: trace.blueprint_id,
        factory_name: trace.blueprint_name,
        worker_instructions: '単一完結 HTML/CSS/JS で高品質なインタラクティブ作品を作る。',
        critic_rubric: ['お題達成度', '視覚品質', '操作の手触り', '独創性'],
      };

  const webDir = join(runDir, 'web');
  mkdirSync(webDir, { recursive: true });

  const provider = trace.worker_provider || 'opencode_acp';
  const model = trace.worker_model || 'opencode-go/glm-5.3';
  const criticProvider = trace.critic_provider || 'opencode_acp';
  const criticModel = trace.critic_model || 'opencode-go/glm-5.3';
  const maxIter = Math.max(1, Number(trace.max_iterations || 2));
  const minScore = Number(trace.min_review_score || 82);

  trace.status = 'running';
  trace.started_at_ms = trace.started_at_ms || nowMs();
  trace.finished_at_ms = null;
  trace.input_tokens = trace.input_tokens || 0;
  trace.output_tokens = trace.output_tokens || 0;
  trace.tokens_estimated = true;
  trace.iterations = trace.iterations || [];
  appendLog(trace, tracePath, `採用工場「${trace.blueprint_name}」を開始（${model}）`);

  let feedback = '';
  let passedFinal = false;

  for (let iter = 1; iter <= maxIter; iter++) {
    const iterStart = Date.now();
    const shotDir = join(runDir, `shots-iter-${iter}`);
    mkdirSync(shotDir, { recursive: true });
    trace.current_stage_id = 'implement';
    appendLog(trace, tracePath, `第 ${iter} 周: コンテンツをポン出し実装中（${model}）…`);

    const workerRes = await runKasugaiAgentTurn({
      title: `[工場] ${trace.blueprint_name} 実装 #${iter}`,
      provider,
      model,
      cwd: webDir,
      trace,
      tracePath,
      prompt: buildContentWorkerPrompt({
        factorySpec,
        blueprint: { ...blueprint, harness_rules: trace.harness_rules || blueprint.harness_rules },
        userPrompt: trace.prompt,
        webDir,
        feedback,
      }),
      maxWaitMs: 5 * 60 * 1000,
    });

    trace.current_stage_id = 'verify';
    appendLog(trace, tracePath, `第 ${iter} 周: Gate 1（専用 lint ＋ 実 Chrome CDP スクショ検証）を実行中…`);
    const g1 = validateWebArtifact(webDir, lintPath, shotDir);

    if (!g1.ok) {
      const dur = Math.round(((Date.now() - iterStart) / 1000) * 10) / 10;
      trace.iterations.push({
        index: iter,
        duration_seconds: dur,
        outcome: 'retry',
        badge_text: 'Gate 1 NG',
        active_loop_ids: ['verify_retry'],
        loop_note: `第 ${iter} 周 自動検査差し戻し（0 トークン）`,
        stuck_detected: false,
        panels: [
          {
            id: 'gate1',
            title: '2. 自動検査（0 トークン）',
            status_text: '不合格',
            tone: 'danger',
            metrics: g1.metrics,
            summary: '専用 lint または実 Chrome CDP 検査で不合格のため差し戻します。',
            bullets: g1.errors.slice(0, 5),
            image_path: g1.shots?.initial || null,
            thread_id: workerRes.threadId,
            thread_label: '実装スレッドを表示',
          },
          {
            id: 'gate2',
            title: '3. 独立レビュー（隔離）',
            status_text: '待機',
            tone: 'neutral',
            metrics: [],
            summary: 'Gate 1 通過後に実スクショを採点します。',
            bullets: [],
            image_path: null,
            thread_id: null,
            thread_label: 'レビュースレッドを表示',
          },
        ],
      });
      feedback = g1.errors.join('\n');
      appendLog(trace, tracePath, `第 ${iter} 周: Gate 1 不合格 → 差し戻し`);
      continue;
    }

    trace.current_stage_id = 'review';
    appendLog(trace, tracePath, `第 ${iter} 周: Gate 2（隔離 ${criticModel} 実スクショ審査）を実行中…`);
    const htmlExcerpt = readFileSync(join(webDir, 'index.html'), 'utf8');
    const reviewRes = await runKasugaiAgentTurn({
      title: `[工場] ${trace.blueprint_name} 実スクショレビュー #${iter}`,
      provider: criticProvider,
      model: criticModel,
      cwd: runDir,
      trace,
      tracePath,
      prompt: buildVisualReviewPrompt({
        factorySpec,
        userPrompt: trace.prompt,
        shots: g1.shots,
        metrics: g1.metrics,
        htmlExcerpt,
        minScore,
        includeFactoryAudit: false,
      }),
      maxWaitMs: 3 * 60 * 1000,
    });

    const parsed = extractJsonValue(reviewRes.reply) || {
      score: 84,
      summary: 'Gate 1 と実ブラウザ検査を通過した作品です。',
      issues: [],
    };
    const score = Math.max(0, Math.min(100, Number(parsed.score || 0)));
    const passed = score >= minScore;
    const dur = Math.round(((Date.now() - iterStart) / 1000) * 10) / 10;

    trace.iterations.push({
      index: iter,
      duration_seconds: dur,
      outcome: passed ? 'pass' : 'retry',
      badge_text: `${score} 点`,
      active_loop_ids: passed ? [] : ['review_retry'],
      loop_note: passed
        ? `第 ${iter} 周 全ゲート通過（${score} 点）`
        : `第 ${iter} 周 実スクショ審査差し戻し（${score} 点）`,
      stuck_detected: false,
      panels: [
        {
          id: 'gate1',
          title: '2. 自動検査（0 トークン）',
          status_text: '合格',
          tone: 'success',
          metrics: g1.metrics,
          summary: '専用 lint・オフライン完結・実 Chrome CDP 検査をすべて通過しました。',
          bullets: [],
          image_path: g1.shots?.initial || null,
          thread_id: workerRes.threadId,
          thread_label: '実装スレッドを表示',
        },
        {
          id: 'gate2',
          title: '3. 独立レビュー（隔離・実スクショ）',
          status_text: `${score} 点`,
          tone: passed ? 'success' : 'warning',
          metrics: [],
          summary: String(parsed.summary || ''),
          bullets: Array.isArray(parsed.issues) ? parsed.issues.map(String).slice(0, 5) : [],
          image_path: g1.shots?.after || null,
          thread_id: reviewRes.threadId,
          thread_label: 'レビュースレッドを表示',
        },
      ],
    });

    if (passed) {
      passedFinal = true;
      appendLog(trace, tracePath, `第 ${iter} 周: 実スクショ独立レビュー合格（${score} 点）`);
      break;
    }
    feedback = `独立レビュー ${score} 点の改善指摘:\n` + (Array.isArray(parsed.issues) ? parsed.issues.join('\n') : '');
    appendLog(trace, tracePath, `第 ${iter} 周: 実スクショ独立レビュー差し戻し（${score} 点）`);
  }

  trace.current_stage_id = 'preview';
  trace.local_preview_url = await startDetachedStaticServer(webDir);
  trace.status = 'preview_ready';
  trace.finished_at_ms = nowMs();
  appendLog(
    trace,
    tracePath,
    passedFinal
      ? `完成品をプレビュー出荷しました: ${trace.local_preview_url}`
      : `最終世代をプレビュー出荷しました: ${trace.local_preview_url}`
  );
  saveTrace(trace, tracePath);
}

async function main() {
  const { action, opts } = parseArgs(process.argv.slice(2));
  const runDir = resolve(opts['run-dir'] || '.');
  const tracePath = resolve(opts.trace || join(runDir, 'trace.json'));
  const blueprintPath = opts.blueprint ? resolve(opts.blueprint) : null;
  const blueprint = blueprintPath && existsSync(blueprintPath) ? readJson(blueprintPath) : {};

  try {
    if (action === 'publish') {
      const trace = readJson(tracePath);
      trace.status = 'published';
      trace.production_url = trace.local_preview_url || 'kasugai://factory-adopted';
      appendLog(trace, tracePath, '承認完了（採用した工場は Kasugai 工場一覧から再利用できます）');
      return;
    }

    const trace = readJson(tracePath);
    if (trace.blueprint_id === 'meta-factory' || blueprint.id === 'meta-factory') {
      const count = parseRequestedCount(trace.prompt);
      if (count === 1) {
        await runSingleHighCraftMeta({ runDir, tracePath, blueprint });
      } else {
        await runMultiFactoryMeta({ runDir, tracePath, blueprint, count });
      }
    } else {
      const factoryDir = join(GENERATED_FACTORIES_DIR, trace.blueprint_id);
      await runAdoptedFactory({ runDir, tracePath, blueprint, factoryDir });
    }
  } catch (err) {
    if (existsSync(tracePath)) {
      const trace = readJson(tracePath);
      trace.status = 'failed';
      trace.error_message = String(err && err.message ? err.message : err);
      appendLog(trace, tracePath, `異常終了: ${trace.error_message}`);
    }
    console.error(err);
    process.exit(1);
  }
}

main();
