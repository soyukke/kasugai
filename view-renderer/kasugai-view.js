(() => {
  const root = document.documentElement;
  const container = document.getElementById("app") || document.getElementById("root") || document.body;

  const COPY_ICON_SVG =
    '<svg width="13" height="13" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round">' +
    '<rect x="5.5" y="5.5" width="8" height="8" rx="1.6"/>' +
    '<path d="M10.5 5.5V3.9A1.4 1.4 0 0 0 9.1 2.5H3.9A1.4 1.4 0 0 0 2.5 3.9V9.1A1.4 1.4 0 0 0 3.9 10.5H5.5"/>' +
    "</svg>";

  const CHECK_ICON_SVG =
    '<svg width="13" height="13" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">' +
    '<path d="M3.2 8.4L6.5 11.7L13 4.8"/>' +
    "</svg>";

  function copyTextToClipboard(text, onDone) {
    const raw = String(text || "");
    if (!raw) {
      return;
    }
    const fallback = () => {
      const area = document.createElement("textarea");
      area.value = raw;
      area.setAttribute("readonly", "");
      area.style.position = "fixed";
      area.style.opacity = "0";
      document.body.append(area);
      area.select();
      try {
        document.execCommand("copy");
        onDone();
      } catch {}
      area.remove();
    };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(raw).then(onDone).catch(fallback);
    } else {
      fallback();
    }
  }

  function escapeHtml(text) {
    return String(text)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;");
  }

  function openLightbox(src, caption) {
    const existing = document.querySelector(".lightbox");
    if (existing) {
      existing.remove();
    }
    const overlay = document.createElement("div");
    overlay.className = "lightbox";
    const img = document.createElement("img");
    img.src = src;
    img.alt = caption || "";
    const label = document.createElement("div");
    label.className = "lightbox-caption";
    label.textContent = caption || "";
    overlay.append(img, label);
    overlay.addEventListener("click", () => {
      if (overlay.classList.contains("is-closing")) {
        return;
      }
      if (window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
        overlay.remove();
        return;
      }
      overlay.classList.add("is-closing");
      const done = () => overlay.remove();
      overlay.addEventListener("animationend", done, { once: true });
      setTimeout(done, 180);
    });
    document.body.append(overlay);
  }

  function lookupMediaEntry(target, mediaMap) {
    if (!mediaMap || !target) {
      return null;
    }
    const candidates = [target];
    try {
      const decoded = decodeURIComponent(target);
      if (decoded !== target) {
        candidates.push(decoded);
      }
    } catch {}
    if (target.startsWith("file://")) {
      const stripped = target.slice("file://".length).split("#")[0];
      candidates.push(stripped);
      try {
        const decodedStripped = decodeURIComponent(stripped);
        if (decodedStripped !== stripped) {
          candidates.push(decodedStripped);
        }
      } catch {}
    }
    for (const key of candidates) {
      const entry = mediaMap[key];
      if (entry && typeof entry.url === "string" && entry.url.startsWith("kasugai-view://app/attachment/")) {
        return entry;
      }
    }
    return null;
  }

  function renderInline(text, mediaMap) {
    const codeSpans = [];
    let safe = String(text).replace(/`([^`\n]+)`/g, (_, code) => {
      const token = `\u0000CODE${codeSpans.length}\u0000`;
      codeSpans.push(`<code>${escapeHtml(code)}</code>`);
      return token;
    });

    const mediaSpans = [];
    safe = safe.replace(/!?\[([^\]]*)\]\(([^)\s]+)\)/g, (full, label, target) => {
      const entry = lookupMediaEntry(target, mediaMap);
      if (!entry) {
        return full;
      }
      const token = `\u0000MEDIA${mediaSpans.length}\u0000`;
      const alt = escapeHtml(label || entry.name || basename(target));
      const src = escapeHtml(entry.url);
      if (entry.kind === "image") {
        mediaSpans.push(
          `<span class="inline-media inline-media-image" data-media-src="${src}" data-media-label="${alt}">` +
            `<img class="attachment-thumb" src="${src}" alt="${alt}">` +
            `<span class="inline-media-caption">${alt}</span>` +
            `</span>`
        );
      } else if (entry.kind === "audio") {
        mediaSpans.push(
          `<span class="inline-media inline-media-audio">` +
            `<span class="inline-media-audio-head"><span class="inline-media-badge">音声</span><span class="inline-media-name">${alt}</span></span>` +
            `<audio class="attachment-audio" controls preload="metadata" src="${src}"></audio>` +
            `</span>`
        );
      } else if (entry.kind === "video") {
        mediaSpans.push(
          `<span class="inline-media inline-media-video">` +
            `<video class="attachment-video" controls playsinline preload="metadata" src="${src}"></video>` +
            `<span class="inline-media-caption">${alt}</span>` +
            `</span>`
        );
      } else {
        return full;
      }
      return token;
    });

    safe = escapeHtml(safe);
    safe = safe.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
    safe = safe.replace(/\*([^*\n]+)\*/g, "<em>$1</em>");
    safe = safe.replace(
      /\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/g,
      '<a href="$2" rel="noreferrer noopener">$1</a>'
    );
    safe = safe.replace(
      /\[([^\]]+)\]\((kasugai-thread:\/\/(\d+))\)/g,
      (_, label, href, tid) =>
        `<a href="${href}" data-thread-id="${tid}" class="thread-link">${label}</a>`
    );
    safe = safe.replace(
      /\[([^\]]+)\]\((file:\/\/[^)\s]+)\)/g,
      (_, label, href) =>
        `<a href="${href}" data-file-href="${href}" class="file-link" title="${href.slice(7)}">${label}</a>`
    );
    safe = safe.replace(
      /\[([^\]]+)\]\((\/[^)\s]+)\)/g,
      (_, label, rawPath) =>
        `<a href="file://${rawPath}" data-file-href="file://${rawPath}" class="file-link" title="${rawPath}">${label}</a>`
    );

    safe = safe.replace(/\u0000MEDIA(\d+)\u0000/g, (_, idx) => mediaSpans[Number(idx)] || "");
    return safe.replace(/\u0000CODE(\d+)\u0000/g, (_, idx) => codeSpans[Number(idx)] || "");
  }

  const SYNTAX_LANGS = (() => {
    const set = (words) => new Set(words.split(" "));
    const cLike = { line: "//", block: true };
    const hashLike = { line: "#" };
    const swift = {
      ...cLike,
      keywords: set(
        "import class struct enum protocol extension func var let init deinit subscript typealias associatedtype guard if else switch case default where for while repeat in return break continue fallthrough throw throws rethrows try catch do defer async await actor nonisolated isolated private fileprivate internal public open static final override mutating nonmutating lazy weak unowned inout some any self Self super as is"
      ),
      literals: set("true false nil"),
    };
    const kizu = {
      ...cLike,
      keywords: set(
        "fn let var mut if else match while for in return break continue struct enum type trait impl mod use pub const as machine state event transition on when extern unsafe self Self where import export"
      ),
      literals: set("true false null none some ok err"),
    };
    const jsTs = {
      ...cLike,
      keywords: set(
        "import export from as default const let var function return if else switch case break continue for while do in of try catch finally throw new delete typeof instanceof void class extends implements interface type enum namespace abstract readonly private public protected static async await yield this super get set declare satisfies keyof infer"
      ),
      literals: set("true false null undefined NaN Infinity"),
    };
    const rust = {
      ...cLike,
      keywords: set(
        "fn let mut const static pub mod use crate super self Self struct enum trait impl type where for while loop if else match in return break continue as ref move async await unsafe extern dyn"
      ),
      literals: set("true false Some None Ok Err"),
    };
    const go = {
      ...cLike,
      keywords: set(
        "package import func var const type struct interface map chan go defer if else switch case default select for range return break continue goto fallthrough"
      ),
      literals: set("true false nil iota"),
    };
    const zig = {
      ...cLike,
      keywords: set(
        "const var fn pub extern export inline comptime struct enum union error if else switch while for break continue return try catch orelse defer errdefer test and or unreachable undefined async await"
      ),
      literals: set("true false null"),
    };
    const cCpp = {
      ...cLike,
      keywords: set(
        "if else switch case default for while do break continue return goto struct union enum typedef const volatile static extern inline register auto sizeof class namespace template typename public private protected virtual override final new delete try catch throw using constexpr noexcept nullptr"
      ),
      literals: set("true false NULL nullptr"),
    };
    const python = {
      ...hashLike,
      keywords: set(
        "import from as def class return if elif else for while break continue pass try except finally raise with yield lambda and or not in is global nonlocal assert del async await match case"
      ),
      literals: set("True False None"),
    };
    const shell = {
      ...hashLike,
      keywords: set(
        "if then else elif fi for while until do done case esac in function local export readonly return exit break continue set unset shift trap"
      ),
      literals: set("true false"),
    };
    const sql = {
      line: "--",
      block: true,
      keywords: set(
        "SELECT FROM WHERE JOIN LEFT RIGHT INNER OUTER ON AS AND OR NOT IN IS NULL LIKE ORDER BY GROUP HAVING LIMIT OFFSET INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE INDEX VIEW DROP ALTER DISTINCT UNION ALL CASE WHEN THEN ELSE END"
      ),
      literals: set("TRUE FALSE NULL"),
      caseInsensitive: true,
    };
    const tla = {
      line: "\\*",
      tlaBlock: true,
      keywords: set(
        "MODULE EXTENDS VARIABLES VARIABLE CONSTANTS CONSTANT ASSUME THEOREM LOCAL INSTANCE LET IN IF THEN ELSE CASE OTHER CHOOSE UNCHANGED EXCEPT DOMAIN SUBSET UNION ENABLED"
      ),
      literals: set("TRUE FALSE"),
    };
    const json = { mode: "json", literals: set("true false null") };
    const toml = { mode: "toml", ...hashLike, literals: set("true false") };
    const yaml = { mode: "yaml", ...hashLike, literals: set("true false null yes no") };
    const css = { mode: "css", block: true, keywords: set("from to and or not only") };
    const markup = { mode: "markup" };
    return {
      swift,
      kizu,
      js: jsTs,
      ts: jsTs,
      tsx: jsTs,
      jsx: jsTs,
      mjs: jsTs,
      cjs: jsTs,
      javascript: jsTs,
      typescript: jsTs,
      rs: rust,
      rust,
      go,
      zig,
      c: cCpp,
      h: cCpp,
      cc: cCpp,
      cpp: cCpp,
      hpp: cCpp,
      m: cCpp,
      mm: cCpp,
      py: python,
      python,
      sh: shell,
      bash: shell,
      zsh: shell,
      just: shell,
      sql,
      tla,
      json,
      jsonc: { ...json, ...cLike },
      toml,
      yml: yaml,
      yaml,
      css,
      scss: { ...css, ...cLike },
      html: markup,
      htm: markup,
      xml: markup,
      svg: markup,
      plist: markup,
      entitlements: markup,
    };
  })();

  function detectHighlightLang(hintOrPath) {
    const raw = String(hintOrPath || "").trim().toLowerCase();
    if (!raw) {
      return null;
    }
    if (SYNTAX_LANGS[raw]) {
      return SYNTAX_LANGS[raw];
    }
    const base = basename(raw);
    if (base === "justfile" || base === "makefile") {
      return SYNTAX_LANGS.sh;
    }
    if (base.endsWith(".plist.in")) {
      return SYNTAX_LANGS.xml;
    }
    const dot = base.lastIndexOf(".");
    if (dot >= 0 && dot < base.length - 1) {
      const ext = base.slice(dot + 1);
      if (SYNTAX_LANGS[ext]) {
        return SYNTAX_LANGS[ext];
      }
    }
    return null;
  }

  function isIdentStart(ch) {
    const c = ch.charCodeAt(0);
    return (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c === 95 || c === 36;
  }

  function isIdentPart(ch) {
    const c = ch.charCodeAt(0);
    return (
      (c >= 65 && c <= 90) ||
      (c >= 97 && c <= 122) ||
      (c >= 48 && c <= 57) ||
      c === 95 ||
      c === 36
    );
  }

  function isDigit(ch) {
    const c = ch.charCodeAt(0);
    return c >= 48 && c <= 57;
  }

  function scanQuoted(line, start, quote) {
    let i = start + 1;
    while (i < line.length) {
      if (line[i] === "\\" && i + 1 < line.length) {
        i += 2;
        continue;
      }
      if (line[i] === quote) {
        return i + 1;
      }
      i += 1;
    }
    return line.length;
  }

  function tokenizeMarkupLine(line) {
    const out = [];
    let i = 0;
    const n = line.length;
    while (i < n) {
      if (line.startsWith("<!--", i)) {
        const end = line.indexOf("-->", i + 4);
        const to = end >= 0 ? end + 3 : n;
        out.push({ start: i, end: to, cls: "tok-comment" });
        i = to;
        continue;
      }
      if (line[i] === "<") {
        let j = i + 1;
        if (j < n && (line[j] === "/" || line[j] === "!")) {
          j += 1;
        }
        const tagStart = j;
        while (j < n && /[A-Za-z0-9:_-]/.test(line[j])) {
          j += 1;
        }
        if (j > tagStart) {
          out.push({ start: i, end: tagStart, cls: "tok-punct" });
          out.push({ start: tagStart, end: j, cls: "tok-kw" });
          i = j;
          while (i < n && line[i] !== ">") {
            if (line[i] === '"' || line[i] === "'") {
              const end = scanQuoted(line, i, line[i]);
              out.push({ start: i, end, cls: "tok-str" });
              i = end;
              continue;
            }
            if (/[A-Za-z_:]/.test(line[i])) {
              let k = i + 1;
              while (k < n && /[A-Za-z0-9:_-]/.test(line[k])) {
                k += 1;
              }
              out.push({ start: i, end: k, cls: "tok-prop" });
              i = k;
              continue;
            }
            const pStart = i;
            i += 1;
            out.push({ start: pStart, end: i, cls: "" });
          }
          if (i < n && line[i] === ">") {
            out.push({ start: i, end: i + 1, cls: "tok-punct" });
            i += 1;
          }
          continue;
        }
      }
      const nextTag = line.indexOf("<", i + 1);
      const to = nextTag >= 0 ? nextTag : n;
      out.push({ start: i, end: to, cls: "" });
      i = to;
    }
    return out;
  }

  function tokenizeCodeLine(line, spec) {
    if (!spec || !line || line.length > 2000) {
      return line ? [{ start: 0, end: line.length, cls: "" }] : [];
    }
    if (spec.mode === "markup") {
      return tokenizeMarkupLine(line);
    }
    const out = [];
    const n = line.length;
    let i = 0;

    const pushPlain = (start, end) => {
      if (end <= start) {
        return;
      }
      const prev = out[out.length - 1];
      if (prev && prev.cls === "" && prev.end === start) {
        prev.end = end;
      } else {
        out.push({ start, end, cls: "" });
      }
    };

    if (spec.mode === "toml") {
      const trimmed = line.trimStart();
      const lead = line.length - trimmed.length;
      if (trimmed.startsWith("[")) {
        const close = line.indexOf("]", lead);
        if (close > lead) {
          pushPlain(0, lead);
          out.push({ start: lead, end: close + 1, cls: "tok-type" });
          i = close + 1;
        }
      }
    }

    while (i < n) {
      const ch = line[i];

      if (spec.line && line.startsWith(spec.line, i)) {
        out.push({ start: i, end: n, cls: "tok-comment" });
        break;
      }
      if (spec.block && ch === "/" && line[i + 1] === "*") {
        const close = line.indexOf("*/", i + 2);
        const end = close >= 0 ? close + 2 : n;
        out.push({ start: i, end, cls: "tok-comment" });
        i = end;
        continue;
      }
      if (spec.tlaBlock && ch === "(" && line[i + 1] === "*") {
        const close = line.indexOf("*)", i + 2);
        const end = close >= 0 ? close + 2 : n;
        out.push({ start: i, end, cls: "tok-comment" });
        i = end;
        continue;
      }

      if (ch === '"' || ch === "'" || ch === "`") {
        const end = scanQuoted(line, i, ch);
        let cls = "tok-str";
        if (spec.mode === "json") {
          let probe = end;
          while (probe < n && (line[probe] === " " || line[probe] === "\t")) {
            probe += 1;
          }
          if (line[probe] === ":") {
            cls = "tok-prop";
          }
        }
        out.push({ start: i, end, cls });
        i = end;
        continue;
      }

      if (spec.mode === "css" && ch === "-" && line[i + 1] === "-") {
        let j = i + 2;
        while (j < n && /[A-Za-z0-9_-]/.test(line[j])) {
          j += 1;
        }
        if (j > i + 2) {
          out.push({ start: i, end: j, cls: "tok-attr" });
          i = j;
          continue;
        }
      }

      if (
        (ch === "@" || (ch === "#" && spec.line !== "#")) &&
        i + 1 < n &&
        /[A-Za-z0-9_-]/.test(line[i + 1])
      ) {
        let j = i + 1;
        while (j < n && /[A-Za-z0-9_-]/.test(line[j])) {
          j += 1;
        }
        const cls = spec.mode === "css" && ch === "#" ? "tok-num" : "tok-attr";
        out.push({ start: i, end: j, cls });
        i = j;
        continue;
      }

      if (isDigit(ch) || (ch === "." && i + 1 < n && isDigit(line[i + 1]))) {
        let j = i + 1;
        while (j < n && /[0-9A-Fa-f_xXoObB.eE%]/.test(line[j])) {
          j += 1;
        }
        if (spec.mode === "css") {
          while (j < n && /[a-z%]/.test(line[j])) {
            j += 1;
          }
        }
        out.push({ start: i, end: j, cls: "tok-num" });
        i = j;
        continue;
      }

      if (isIdentStart(ch)) {
        let j = i + 1;
        while (j < n && (isIdentPart(line[j]) || (spec.mode === "css" && line[j] === "-"))) {
          j += 1;
        }
        const word = line.slice(i, j);
        const lookup = spec.caseInsensitive ? word.toUpperCase() : word;
        let probe = j;
        while (probe < n && (line[probe] === " " || line[probe] === "\t")) {
          probe += 1;
        }
        const prevNonSpace = i > 0 ? line[i - 1] : "";
        let cls = "";
        if (spec.literals && spec.literals.has(lookup)) {
          cls = "tok-lit";
        } else if (spec.keywords && spec.keywords.has(lookup)) {
          cls = "tok-kw";
        } else if (
          (spec.mode === "css" || spec.mode === "yaml") &&
          line[probe] === ":" &&
          line[probe + 1] !== ":"
        ) {
          cls = "tok-prop";
        } else if (spec.mode === "toml" && line[probe] === "=") {
          cls = "tok-prop";
        } else if (line[probe] === "(") {
          cls = "tok-fn";
        } else if (
          word.length >= 2 &&
          word[0] >= "A" &&
          word[0] <= "Z" &&
          /[a-z]/.test(word)
        ) {
          cls = "tok-type";
        } else if (prevNonSpace === ".") {
          cls = "tok-prop";
        }
        if (cls) {
          out.push({ start: i, end: j, cls });
        } else {
          pushPlain(i, j);
        }
        i = j;
        continue;
      }

      pushPlain(i, i + 1);
      i += 1;
    }

    return out;
  }

  function renderHighlightedLine(text, langSpec, emphRange, emphCls) {
    if (!text) {
      return " ";
    }
    const tokens = tokenizeCodeLine(text, langSpec);
    const hasEmph = emphRange && emphRange[1] > emphRange[0];
    const parts = [];
    for (const tok of tokens) {
      const wrapTok = (sub) =>
        tok.cls ? `<span class="${tok.cls}">${escapeHtml(sub)}</span>` : escapeHtml(sub);
      if (!hasEmph || tok.end <= emphRange[0] || tok.start >= emphRange[1]) {
        parts.push(wrapTok(text.slice(tok.start, tok.end)));
        continue;
      }
      if (tok.start < emphRange[0]) {
        parts.push(wrapTok(text.slice(tok.start, emphRange[0])));
      }
      const midStart = Math.max(tok.start, emphRange[0]);
      const midEnd = Math.min(tok.end, emphRange[1]);
      parts.push(`<mark class="${emphCls}">${wrapTok(text.slice(midStart, midEnd))}</mark>`);
      if (tok.end > emphRange[1]) {
        parts.push(wrapTok(text.slice(emphRange[1], tok.end)));
      }
    }
    return parts.join("") || " ";
  }

  function computeIntralineDiff(oldText, newText) {
    if (!oldText || !newText || oldText === newText) {
      return null;
    }
    const maxLen = Math.max(oldText.length, newText.length);
    if (maxLen > 600) {
      return null;
    }
    let prefix = 0;
    const minLen = Math.min(oldText.length, newText.length);
    while (prefix < minLen && oldText[prefix] === newText[prefix]) {
      prefix += 1;
    }
    let suffix = 0;
    while (
      suffix < minLen - prefix &&
      oldText[oldText.length - 1 - suffix] === newText[newText.length - 1 - suffix]
    ) {
      suffix += 1;
    }
    if (prefix + suffix < Math.floor(minLen * 0.25)) {
      return null;
    }
    return {
      oldRange: [prefix, oldText.length - suffix],
      newRange: [prefix, newText.length - suffix],
    };
  }

  function renderCodeBlock(lang, codeText) {
    const label = escapeHtml(lang || "code");
    const spec = detectHighlightLang(lang);
    const body = spec
      ? String(codeText || "")
          .split("\n")
          .map((line) => (line ? renderHighlightedLine(line, spec, null, "") : ""))
          .join("\n")
      : escapeHtml(codeText);
    return (
      `<div class="code-block">` +
      `<div class="code-block-header"><span>${label}</span>` +
      `<button type="button" class="code-copy-btn" aria-label="コードをコピー" title="コードをコピー">${COPY_ICON_SVG}</button></div>` +
      `<pre><code>${body}</code></pre></div>`
    );
  }

  function splitTableRow(line) {
    let trimmed = String(line || "").trim();
    if (trimmed.startsWith("|")) {
      trimmed = trimmed.slice(1);
    }
    if (trimmed.endsWith("|") && !trimmed.endsWith("\\|")) {
      trimmed = trimmed.slice(0, -1);
    }
    const cells = [];
    let current = "";
    let inCode = false;
    for (let i = 0; i < trimmed.length; i += 1) {
      const ch = trimmed[i];
      if (ch === "\\" && i + 1 < trimmed.length && trimmed[i + 1] === "|") {
        current += "|";
        i += 1;
        continue;
      }
      if (ch === "`") {
        inCode = !inCode;
        current += ch;
        continue;
      }
      if (ch === "|" && !inCode) {
        cells.push(current.trim());
        current = "";
        continue;
      }
      current += ch;
    }
    cells.push(current.trim());
    return cells;
  }

  function parseTableDelimiter(line) {
    const trimmed = String(line || "").trim();
    if (!trimmed.includes("-") || !trimmed.includes("|")) {
      return null;
    }
    const rawCells = splitTableRow(trimmed);
    if (rawCells.length < 1) {
      return null;
    }
    const aligns = [];
    for (const cell of rawCells) {
      if (!/^:?-{3,}:?$/.test(cell)) {
        return null;
      }
      if (cell.startsWith(":") && cell.endsWith(":")) {
        aligns.push("center");
      } else if (cell.endsWith(":")) {
        aligns.push("right");
      } else if (cell.startsWith(":")) {
        aligns.push("left");
      } else {
        aligns.push("");
      }
    }
    return aligns;
  }

  function isTableStart(lines, index) {
    if (index + 1 >= lines.length) {
      return false;
    }
    const header = lines[index];
    const delim = lines[index + 1];
    if (!header || !header.includes("|")) {
      return false;
    }
    const aligns = parseTableDelimiter(delim);
    if (!aligns) {
      return false;
    }
    const headerCells = splitTableRow(header);
    return headerCells.length === aligns.length;
  }

  function matchHeadingLine(line) {
    const match = String(line || "").match(/^(#{1,4})\s+(.+)$/);
    if (!match || !match[2].trim()) {
      return null;
    }
    return { level: match[1].length, content: match[2] };
  }

  function isHorizontalRuleLine(line) {
    return /^\s*(?:-{3,}|\*{3,}|_{3,})\s*$/.test(String(line || ""));
  }

  function matchListLine(line) {
    const ul = String(line || "").match(/^(\s*)[-*+]\s+(.*)$/);
    if (ul) {
      return { kind: "ul", indent: ul[1].length, start: 1, content: ul[2] };
    }
    const ol = String(line || "").match(/^(\s*)(\d+)\.\s+(.*)$/);
    if (ol) {
      return { kind: "ol", indent: ol[1].length, start: Number(ol[2]), content: ol[3] };
    }
    return null;
  }

  function parseListBlock(lines, startIndex, mediaMap) {
    const first = matchListLine(lines[startIndex]);
    if (!first) {
      return null;
    }
    const listKind = first.kind;
    const baseIndent = first.indent;
    const startNum = first.start;
    const items = [];
    let i = startIndex;

    while (i < lines.length) {
      const m = matchListLine(lines[i]);
      if (!m || m.kind !== listKind || m.indent !== baseIndent) {
        break;
      }
      const parts = [renderInline(m.content, mediaMap)];
      i += 1;

      while (i < lines.length) {
        if (lines[i].trim() === "") {
          let look = i;
          while (look < lines.length && lines[look].trim() === "") {
            look += 1;
          }
          if (look >= lines.length) {
            break;
          }
          const nextList = matchListLine(lines[look]);
          if (nextList && nextList.indent > baseIndent) {
            i = look;
            continue;
          }
          if (nextList && nextList.kind === listKind && nextList.indent === baseIndent) {
            i = look;
            break;
          }
          break;
        }
        const sub = matchListLine(lines[i]);
        if (sub) {
          if (sub.indent > baseIndent) {
            const nested = parseListBlock(lines, i, mediaMap);
            if (nested) {
              parts.push(nested.html);
              i = nested.nextIndex;
              continue;
            }
          }
          break;
        }
        const leadSpaces = lines[i].match(/^(\s*)/)[1].length;
        if (leadSpaces > baseIndent && !lines[i].trim().startsWith("```")) {
          parts.push(`<br>${renderInline(lines[i].trim(), mediaMap)}`);
          i += 1;
          continue;
        }
        break;
      }

      items.push(`<li>${parts.join("")}</li>`);
    }

    const openTag =
      listKind === "ol" && startNum !== 1 ? `<ol start="${startNum}">` : `<${listKind}>`;
    return { html: `${openTag}${items.join("")}</${listKind}>`, nextIndex: i };
  }

  function renderMarkdown(source, mediaMap) {
    const lines = String(source || "").replace(/\r\n/g, "\n").split("\n");
    const out = [];
    let i = 0;

    while (i < lines.length) {
      const line = lines[i];

      if (line.trim().startsWith("```")) {
        const lang = line.trim().slice(3).trim();
        const codeLines = [];
        i += 1;
        while (i < lines.length && !lines[i].trim().startsWith("```")) {
          codeLines.push(lines[i]);
          i += 1;
        }
        if (i < lines.length) {
          i += 1;
        }
        if (lang.toLowerCase() === "compare") {
          const parsedCompare = parseCompareBlock(codeLines, mediaMap);
          if (parsedCompare) {
            out.push(
              `<div class="img-compare-placeholder"` +
                ` data-before-src="${escapeHtml(parsedCompare.before.src)}"` +
                ` data-before-label="${escapeHtml(parsedCompare.before.label)}"` +
                ` data-after-src="${escapeHtml(parsedCompare.after.src)}"` +
                ` data-after-label="${escapeHtml(parsedCompare.after.label)}"></div>`
            );
            continue;
          }
        }
        out.push(renderCodeBlock(lang, codeLines.join("\n")));
        continue;
      }

      if (line.trim() === "") {
        i += 1;
        continue;
      }

      if (isHorizontalRuleLine(line)) {
        out.push("<hr>");
        i += 1;
        continue;
      }

      if (isTableStart(lines, i)) {
        const headerCells = splitTableRow(lines[i]);
        const aligns = parseTableDelimiter(lines[i + 1]);
        i += 2;
        const bodyRows = [];
        while (
          i < lines.length &&
          lines[i].trim() !== "" &&
          lines[i].includes("|") &&
          !lines[i].trim().startsWith("```")
        ) {
          bodyRows.push(splitTableRow(lines[i]));
          i += 1;
        }
        const thHtml = headerCells
          .map((cell, idx) => {
            const align = aligns[idx] ? ` style="text-align:${aligns[idx]}"` : "";
            return `<th${align}>${renderInline(cell, mediaMap)}</th>`;
          })
          .join("");
        const trHtml = bodyRows
          .map((row) => {
            const tds = aligns
              .map((alignVal, idx) => {
                const align = alignVal ? ` style="text-align:${alignVal}"` : "";
                return `<td${align}>${renderInline(row[idx] || "", mediaMap)}</td>`;
              })
              .join("");
            return `<tr>${tds}</tr>`;
          })
          .join("");
        out.push(
          `<div class="md-table-wrap"><table class="md-table"><thead><tr>${thHtml}</tr></thead><tbody>${trHtml}</tbody></table></div>`
        );
        continue;
      }

      const heading = matchHeadingLine(line);
      if (heading) {
        out.push(`<h${heading.level}>${renderInline(heading.content, mediaMap)}</h${heading.level}>`);
        i += 1;
        continue;
      }

      if (line.startsWith("> ")) {
        const quote = [];
        while (i < lines.length && lines[i].startsWith("> ")) {
          quote.push(renderInline(lines[i].slice(2), mediaMap));
          i += 1;
        }
        out.push(`<blockquote><p>${quote.join("<br>")}</p></blockquote>`);
        continue;
      }

      const listBlock = parseListBlock(lines, i, mediaMap);
      if (listBlock) {
        out.push(listBlock.html);
        i = listBlock.nextIndex;
        continue;
      }

      const para = [];
      while (
        i < lines.length &&
        lines[i].trim() !== "" &&
        !lines[i].trim().startsWith("```") &&
        !isHorizontalRuleLine(lines[i]) &&
        !isTableStart(lines, i) &&
        !matchHeadingLine(lines[i]) &&
        !lines[i].startsWith("> ") &&
        !matchListLine(lines[i])
      ) {
        para.push(renderInline(lines[i], mediaMap));
        i += 1;
      }
      if (para.length === 0) {
        para.push(renderInline(lines[i], mediaMap));
        i += 1;
      }
      out.push(`<p>${para.join("<br>")}</p>`);
    }

    return out.join("\n");
  }

  function parseCompareBlock(codeLines, mediaMap) {
    let beforeItem = null;
    let afterItem = null;
    const positional = [];

    for (const rawLine of codeLines) {
      const line = rawLine.trim();
      if (!line) {
        continue;
      }
      const keyMatch = line.match(/^(before|after|変更前|変更後)\s*:\s*(.+)$/i);
      const valuePart = keyMatch ? keyMatch[2].trim() : line;
      const mdMatch = valuePart.match(/^!?\[([^\]]*)\]\(([^)\s]+)\)$/);
      const target = mdMatch ? mdMatch[2] : valuePart.split(/\s+/)[0];
      const entry = lookupMediaEntry(target, mediaMap);
      if (!entry || entry.kind !== "image") {
        continue;
      }
      const label = (mdMatch && mdMatch[1]) || entry.name || basename(target);
      const item = { src: entry.url, label };
      if (keyMatch) {
        const key = keyMatch[1].toLowerCase();
        if (key === "before" || key === "変更前") {
          beforeItem = item;
        } else {
          afterItem = item;
        }
      } else {
        positional.push(item);
      }
    }

    if (!beforeItem && positional.length >= 1) {
      beforeItem = positional[0];
    }
    if (!afterItem && positional.length >= 2) {
      afterItem = positional[1];
    }
    if (beforeItem && afterItem) {
      return { before: beforeItem, after: afterItem };
    }
    return null;
  }

  function isBeforeAfterLabels(labelA, labelB) {
    const a = String(labelA || "").toLowerCase();
    const b = String(labelB || "").toLowerCase();
    const hasBefore = /(before|old|prev|変更前|修正前|適用前)/.test(a);
    const hasAfter = /(after|new|next|変更後|修正後|適用後)/.test(b);
    return hasBefore && hasAfter;
  }

  function buildImageCompareWidget(before, after, options) {
    const opts = options || {};
    const items = Array.isArray(opts.items) && opts.items.length >= 2 ? opts.items : null;
    let currentBefore = before;
    let currentAfter = after;
    let activeMode = opts.defaultMode || "slider";
    let sliderPercent = 50;
    let onionOpacity = 50;

    const card = document.createElement("section");
    card.className = "img-compare-card";

    const header = document.createElement("header");
    header.className = "img-compare-header";

    const titleWrap = document.createElement("div");
    titleWrap.className = "img-compare-title-wrap";

    const titleEl = document.createElement("span");
    titleEl.className = "img-compare-title";
    titleEl.textContent = opts.title || "前後比較";

    const metaEl = document.createElement("span");
    metaEl.className = "img-compare-meta";

    titleWrap.append(titleEl, metaEl);

    const controls = document.createElement("div");
    controls.className = "img-compare-controls";

    if (items && items.length > 2) {
      const beforeSelect = document.createElement("select");
      beforeSelect.className = "img-compare-select";
      beforeSelect.title = "変更前の画像";
      const afterSelect = document.createElement("select");
      afterSelect.className = "img-compare-select";
      afterSelect.title = "変更後の画像";
      items.forEach((it, idx) => {
        const optA = document.createElement("option");
        optA.value = String(idx);
        optA.textContent = `前: ${it.label}`;
        if (it.src === currentBefore.src) {
          optA.selected = true;
        }
        beforeSelect.append(optA);

        const optB = document.createElement("option");
        optB.value = String(idx);
        optB.textContent = `後: ${it.label}`;
        if (it.src === currentAfter.src) {
          optB.selected = true;
        }
        afterSelect.append(optB);
      });
      beforeSelect.addEventListener("change", () => {
        const idx = Number(beforeSelect.value);
        if (items[idx]) {
          currentBefore = items[idx];
          renderBody();
        }
      });
      afterSelect.addEventListener("change", () => {
        const idx = Number(afterSelect.value);
        if (items[idx]) {
          currentAfter = items[idx];
          renderBody();
        }
      });
      controls.append(beforeSelect, afterSelect);
    }

    const modeGroup = document.createElement("div");
    modeGroup.className = "img-compare-modes";
    const modes = [
      { id: "slider", label: "スライダー" },
      { id: "side", label: "並列" },
      { id: "onion", label: "重ね合わせ" },
    ];
    const modeButtons = new Map();
    for (const m of modes) {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "img-compare-mode-btn";
      btn.textContent = m.label;
      btn.addEventListener("click", () => {
        if (activeMode !== m.id) {
          activeMode = m.id;
          syncModeButtons();
          renderBody();
        }
      });
      modeButtons.set(m.id, btn);
      modeGroup.append(btn);
    }
    controls.append(modeGroup);
    header.append(titleWrap, controls);

    const body = document.createElement("div");
    body.className = "img-compare-body";

    card.append(header, body);

    function syncModeButtons() {
      for (const [id, btn] of modeButtons.entries()) {
        btn.classList.toggle("is-active", id === activeMode);
      }
    }

    function updateMeta(beforeDims, afterDims) {
      const parts = [];
      if (beforeDims) {
        parts.push(`前 ${beforeDims}`);
      } else if (currentBefore.size) {
        parts.push(`前 ${currentBefore.size}`);
      }
      if (afterDims) {
        parts.push(`後 ${afterDims}`);
      } else if (currentAfter.size) {
        parts.push(`後 ${currentAfter.size}`);
      }
      metaEl.textContent = parts.join(" → ");
    }

    function renderBody() {
      body.replaceChildren();
      let beforeDims = "";
      let afterDims = "";
      updateMeta("", "");

      if (activeMode === "slider") {
        const stage = document.createElement("div");
        stage.className = "img-compare-stage";
        stage.tabIndex = 0;
        stage.setAttribute("role", "slider");
        stage.setAttribute("aria-label", "画像の前後比較スライダー");
        stage.setAttribute("aria-valuemin", "0");
        stage.setAttribute("aria-valuemax", "100");
        stage.setAttribute("aria-valuenow", String(Math.round(sliderPercent)));
        stage.style.setProperty("--compare-pos", `${sliderPercent}%`);

        const afterImg = document.createElement("img");
        afterImg.className = "img-compare-after";
        afterImg.src = currentAfter.src;
        afterImg.alt = currentAfter.label;
        afterImg.draggable = false;
        afterImg.addEventListener("load", () => {
          afterDims = `${afterImg.naturalWidth}×${afterImg.naturalHeight}${currentAfter.size ? ` (${currentAfter.size})` : ""}`;
          updateMeta(beforeDims, afterDims);
        });

        const beforeImg = document.createElement("img");
        beforeImg.className = "img-compare-before";
        beforeImg.src = currentBefore.src;
        beforeImg.alt = currentBefore.label;
        beforeImg.draggable = false;
        beforeImg.addEventListener("load", () => {
          beforeDims = `${beforeImg.naturalWidth}×${beforeImg.naturalHeight}${currentBefore.size ? ` (${currentBefore.size})` : ""}`;
          updateMeta(beforeDims, afterDims);
        });

        const divider = document.createElement("div");
        divider.className = "img-compare-divider";
        const handle = document.createElement("span");
        handle.className = "img-compare-handle";
        handle.innerHTML =
          '<svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">' +
          '<path d="M5.5 4.5L2 8l3.5 3.5"/><path d="M10.5 4.5L14 8l-3.5 3.5"/></svg>';
        divider.append(handle);

        const beforeTag = document.createElement("span");
        beforeTag.className = "img-compare-tag is-before";
        beforeTag.textContent = currentBefore.tag || currentBefore.label || "Before";

        const afterTag = document.createElement("span");
        afterTag.className = "img-compare-tag is-after";
        afterTag.textContent = currentAfter.tag || currentAfter.label || "After";

        function setPercent(pct) {
          sliderPercent = Math.max(0, Math.min(100, pct));
          stage.style.setProperty("--compare-pos", `${sliderPercent.toFixed(2)}%`);
          stage.setAttribute("aria-valuenow", String(Math.round(sliderPercent)));
        }

        function updateFromClientX(clientX) {
          const rect = stage.getBoundingClientRect();
          if (rect.width <= 0) {
            return;
          }
          setPercent(((clientX - rect.left) / rect.width) * 100);
        }

        stage.addEventListener("pointerdown", (ev) => {
          ev.preventDefault();
          stage.setPointerCapture(ev.pointerId);
          updateFromClientX(ev.clientX);
          const onMove = (moveEv) => {
            updateFromClientX(moveEv.clientX);
          };
          const onUp = () => {
            stage.removeEventListener("pointermove", onMove);
            stage.removeEventListener("pointerup", onUp);
            stage.removeEventListener("pointercancel", onUp);
          };
          stage.addEventListener("pointermove", onMove);
          stage.addEventListener("pointerup", onUp);
          stage.addEventListener("pointercancel", onUp);
        });

        stage.addEventListener("keydown", (ev) => {
          if (ev.key === "ArrowLeft") {
            ev.preventDefault();
            setPercent(sliderPercent - (ev.shiftKey ? 10 : 2));
          } else if (ev.key === "ArrowRight") {
            ev.preventDefault();
            setPercent(sliderPercent + (ev.shiftKey ? 10 : 2));
          }
        });

        stage.append(afterImg, beforeImg, divider, beforeTag, afterTag);
        body.append(stage);
      } else if (activeMode === "side") {
        const grid = document.createElement("div");
        grid.className = "img-compare-side";

        for (const sideItem of [
          { info: currentBefore, badge: currentBefore.tag || "Before" },
          { info: currentAfter, badge: currentAfter.tag || "After" },
        ]) {
          const fig = document.createElement("figure");
          fig.className = "img-compare-side-cell";
          const img = document.createElement("img");
          img.src = sideItem.info.src;
          img.alt = sideItem.info.label;
          img.addEventListener("click", () => openLightbox(sideItem.info.src, sideItem.info.label));
          const cap = document.createElement("figcaption");
          cap.className = "img-compare-side-cap";
          const leftCap = document.createElement("span");
          leftCap.textContent = sideItem.badge;
          const rightCap = document.createElement("span");
          rightCap.textContent = sideItem.info.size || sideItem.info.label;
          cap.append(leftCap, rightCap);
          fig.append(img, cap);
          grid.append(fig);
        }
        body.append(grid);
      } else {
        const stage = document.createElement("div");
        stage.className = "img-compare-onion-stage";
        const baseImg = document.createElement("img");
        baseImg.className = "img-compare-onion-base";
        baseImg.src = currentBefore.src;
        baseImg.alt = currentBefore.label;
        const topImg = document.createElement("img");
        topImg.className = "img-compare-onion-top";
        topImg.src = currentAfter.src;
        topImg.alt = currentAfter.label;
        topImg.style.opacity = String(onionOpacity / 100);
        stage.append(baseImg, topImg);

        const bar = document.createElement("div");
        bar.className = "img-compare-onion-bar";
        const beforeLbl = document.createElement("span");
        beforeLbl.textContent = currentBefore.tag || "Before";
        const range = document.createElement("input");
        range.type = "range";
        range.min = "0";
        range.max = "100";
        range.value = String(onionOpacity);
        const afterLbl = document.createElement("span");
        afterLbl.textContent = `${currentAfter.tag || "After"} (${onionOpacity}%)`;
        range.addEventListener("input", () => {
          onionOpacity = Number(range.value);
          topImg.style.opacity = String(onionOpacity / 100);
          afterLbl.textContent = `${currentAfter.tag || "After"} (${onionOpacity}%)`;
        });
        bar.append(beforeLbl, range, afterLbl);
        body.append(stage, bar);
      }
    }

    syncModeButtons();
    renderBody();
    return card;
  }

  function basename(path) {
    const parts = String(path || "").split("/");
    return parts[parts.length - 1] || String(path || "");
  }

  function buildMediaElement(entry, rawPath) {
    const figure = document.createElement("figure");
    figure.className = "attachment-figure";
    const name = entry.name || basename(rawPath);

    if (entry.kind === "image") {
      const img = document.createElement("img");
      img.className = "attachment-thumb";
      img.src = entry.url;
      img.alt = name;
      img.addEventListener("click", () => openLightbox(entry.url, name));
      figure.append(img);
    } else if (entry.kind === "audio") {
      const audio = document.createElement("audio");
      audio.className = "attachment-audio";
      audio.controls = true;
      audio.preload = "metadata";
      audio.src = entry.url;
      figure.append(audio);
    } else if (entry.kind === "video") {
      const video = document.createElement("video");
      video.className = "attachment-video";
      video.controls = true;
      video.playsInline = true;
      video.preload = "metadata";
      video.src = entry.url;
      figure.append(video);
    }

    const cap = document.createElement("figcaption");
    cap.className = "attachment-caption";
    cap.textContent = name;
    figure.append(cap);
    return figure;
  }

  function postNativeFileLink(href) {
    if (
      !href ||
      !window.webkit ||
      !window.webkit.messageHandlers ||
      !window.webkit.messageHandlers.kasugaiLink
    ) {
      return;
    }
    window.webkit.messageHandlers.kasugaiLink.postMessage(href);
  }

  function bindInteractiveBody(rootEl) {
    const fileLinks = rootEl.querySelectorAll("a.file-link");
    for (const link of fileLinks) {
      link.addEventListener("click", (ev) => {
        const href = link.dataset.fileHref || link.getAttribute("href") || "";
        if (!href) {
          return;
        }
        ev.preventDefault();
        postNativeFileLink(href);
      });
    }
    const threadLinks = rootEl.querySelectorAll("a.thread-link");
    for (const link of threadLinks) {
      link.addEventListener("click", (ev) => {
        const tid = link.dataset.threadId || "";
        if (!tid) {
          return;
        }
        ev.preventDefault();
        postNativeFileLink(`kasugai-thread://${tid}`);
      });
    }
    const thumbs = rootEl.querySelectorAll(".inline-media img.attachment-thumb");
    for (const img of thumbs) {
      img.addEventListener("click", () => openLightbox(img.src, img.alt));
    }
    const comparePlaceholders = rootEl.querySelectorAll(".img-compare-placeholder");
    for (const holder of comparePlaceholders) {
      const beforeSrc = holder.dataset.beforeSrc || "";
      const afterSrc = holder.dataset.afterSrc || "";
      if (!beforeSrc || !afterSrc) {
        continue;
      }
      const widget = buildImageCompareWidget(
        { src: beforeSrc, label: holder.dataset.beforeLabel || "Before", tag: "Before" },
        { src: afterSrc, label: holder.dataset.afterLabel || "After", tag: "After" },
        { title: "前後比較", defaultMode: "slider" }
      );
      holder.replaceWith(widget);
    }
    const copyBtns = rootEl.querySelectorAll(".code-copy-btn");
    for (const btn of copyBtns) {
      btn.addEventListener("click", () => {
        const codeEl = btn.closest(".code-block")?.querySelector("pre code");
        const raw = codeEl ? codeEl.textContent || "" : "";
        if (!raw) {
          return;
        }
        copyTextToClipboard(raw, () => {
          btn.innerHTML = CHECK_ICON_SVG;
          btn.classList.add("is-copied");
          btn.title = "コピー済み";
          setTimeout(() => {
            btn.innerHTML = COPY_ICON_SVG;
            btn.classList.remove("is-copied");
            btn.title = "コードをコピー";
          }, 1400);
        });
      });
    }
  }

  function buildMessageBlock(message, streaming, mediaMap, pendingMode) {
    const roleName = message.role || "assistant";
    const mode = pendingMode === true ? "queued" : String(pendingMode || "");
    const isQueued = mode === "queued";
    const isSteered = mode === "steered";
    const article = document.createElement("article");
    article.className = `message role-${roleName}${streaming ? " role-streaming" : ""}${isQueued ? " role-queued" : ""}${isSteered ? " role-steered" : ""}`;

    const body = document.createElement("div");
    body.className = "message-body";
    body.innerHTML = renderMarkdown(message.text || "", mediaMap);
    bindInteractiveBody(body);
    article.append(body);

    if (Array.isArray(message.attachments) && message.attachments.length > 0) {
      const strip = document.createElement("div");
      strip.className = "attachments";
      for (const path of message.attachments) {
        const key = String(path);
        const entry = mediaMap && mediaMap[key];
        if (entry && typeof entry.url === "string" && entry.url.startsWith("kasugai-view://app/attachment/")) {
          strip.append(buildMediaElement(entry, key));
        } else {
          const chip = document.createElement("button");
          chip.type = "button";
          chip.className = "attachment-chip";
          chip.textContent = basename(key);
          chip.title = key;
          chip.addEventListener("click", () => {
            postNativeFileLink(key.startsWith("file://") ? key : `file://${key}`);
          });
          strip.append(chip);
        }
      }
      article.append(strip);
    }

    const messageImages = [];
    const seenImageSrcs = new Set();
    for (const node of body.querySelectorAll(".inline-media-image")) {
      const src = node.dataset.mediaSrc || "";
      if (src && !seenImageSrcs.has(src)) {
        seenImageSrcs.add(src);
        messageImages.push({
          src,
          label: node.dataset.mediaLabel || "画像",
        });
      }
    }
    for (const img of article.querySelectorAll(".attachments img.attachment-thumb")) {
      const src = img.getAttribute("src") || "";
      if (src && !seenImageSrcs.has(src)) {
        seenImageSrcs.add(src);
        messageImages.push({
          src,
          label: img.getAttribute("alt") || "画像",
        });
      }
    }
    if (messageImages.length >= 2 && !body.querySelector(".img-compare-card")) {
      const autoExpand =
        messageImages.length === 2 &&
        isBeforeAfterLabels(messageImages[0].label, messageImages[1].label);
      const compareSection = document.createElement("div");
      compareSection.className = "chat-compare-section";
      let compareOpen = autoExpand;
      let compareWidget = null;

      const toggleBtn = document.createElement("button");
      toggleBtn.type = "button";
      toggleBtn.className = compareOpen ? "chat-compare-toggle is-open" : "chat-compare-toggle";
      toggleBtn.textContent = compareOpen ? "前後比較を閉じる" : "画像を前後比較（スライダー）";

      function syncCompareSection() {
        toggleBtn.classList.toggle("is-open", compareOpen);
        toggleBtn.textContent = compareOpen ? "前後比較を閉じる" : "画像を前後比較（スライダー）";
        if (compareOpen) {
          if (!compareWidget) {
            compareWidget = buildImageCompareWidget(
              {
                src: messageImages[0].src,
                label: messageImages[0].label,
                tag: `Before · ${messageImages[0].label}`,
              },
              {
                src: messageImages[1].src,
                label: messageImages[1].label,
                tag: `After · ${messageImages[1].label}`,
              },
              {
                title: "画像比較",
                items: messageImages,
                defaultMode: "slider",
              }
            );
            compareSection.append(compareWidget);
          } else {
            compareWidget.hidden = false;
          }
        } else if (compareWidget) {
          compareWidget.hidden = true;
        }
      }

      toggleBtn.addEventListener("click", () => {
        compareOpen = !compareOpen;
        syncCompareSection();
      });

      compareSection.append(toggleBtn);
      syncCompareSection();
      article.append(compareSection);
    }

    if (isQueued || isSteered) {
      const meta = document.createElement("div");
      meta.className = isSteered ? "message-queue-meta is-steered" : "message-queue-meta";
      const dot = document.createElement("span");
      dot.className = isSteered ? "message-queue-dot is-steered" : "message-queue-dot";
      const label = document.createElement("span");
      label.textContent = isSteered ? "差し込み送信" : "待機中";
      meta.append(dot, label);
      article.append(meta);
    }

    if (roleName !== "user" && !streaming && message.text) {
      const actions = document.createElement("div");
      actions.className = "message-actions";
      const copyBtn = document.createElement("button");
      copyBtn.type = "button";
      copyBtn.className = "message-copy-btn";
      copyBtn.setAttribute("aria-label", "コピー");
      copyBtn.title = "コピー";
      copyBtn.innerHTML = COPY_ICON_SVG;
      copyBtn.addEventListener("click", () => {
        copyTextToClipboard(String(message.text), () => {
          copyBtn.innerHTML = CHECK_ICON_SVG;
          copyBtn.classList.add("is-copied");
          actions.classList.add("is-copied");
          copyBtn.title = "コピー済み";
          setTimeout(() => {
            copyBtn.innerHTML = COPY_ICON_SVG;
            copyBtn.classList.remove("is-copied");
            actions.classList.remove("is-copied");
            copyBtn.title = "コピー";
          }, 1400);
        });
      });
      actions.append(copyBtn);
      article.append(actions);
    }

    return article;
  }

  const ACTIVITY_RECENT_LIMIT = 3;
  const expandedActivityPanels = new Set();
  const livePanelOpenOverride = new Map();

  function filterVisibleActivities(items, isLive) {
    return items.filter((act) => act && act.kind !== "thought");
  }

  function selectActivityWindow(visible, expanded) {
    if (expanded || visible.length <= ACTIVITY_RECENT_LIMIT) {
      return { shown: visible, hiddenCount: 0 };
    }
    const cutoff = visible.length - ACTIVITY_RECENT_LIMIT;
    const shown = [];
    for (let idx = 0; idx < visible.length; idx += 1) {
      const act = visible[idx];
      if (idx >= cutoff || act.status === "failed") {
        shown.push(act);
      }
    }
    return { shown, hiddenCount: visible.length - shown.length };
  }

  function buildActivityRow(act) {
    const row = document.createElement("div");
    row.className = "activity-row";

    const dot = document.createElement("span");
    dot.className = `activity-dot ${act.status || "completed"}`;

    const title = document.createElement("span");
    title.className = "activity-title";
    title.textContent = act.title || "処理";

    const status = document.createElement("span");
    status.className = "activity-status";
    status.textContent = act.status === "failed" ? "失敗" : "";

    row.append(dot, title, status);
    if (act.detail) {
      const detail = document.createElement("span");
      detail.className = "activity-detail";
      detail.textContent = act.detail;
      row.append(detail);
    }
    return row;
  }

  function extractCliFlagValue(commandText, flagName) {
    const re = new RegExp(`(?:^|\\s)${flagName}\\s+`, "g");
    const m = re.exec(commandText);
    if (!m) {
      return "";
    }
    let idx = m.index + m[0].length;
    const n = commandText.length;
    if (idx >= n) {
      return "";
    }
    const quote = commandText[idx];
    if (quote === '"' || quote === "'") {
      idx += 1;
      let out = "";
      while (idx < n) {
        const ch = commandText[idx];
        if (quote === '"' && ch === "\\" && idx + 1 < n) {
          const next = commandText[idx + 1];
          if (next === "n") {
            out += "\n";
          } else if (next === "t") {
            out += "\t";
          } else {
            out += next;
          }
          idx += 2;
          continue;
        }
        if (ch === quote) {
          break;
        }
        out += ch;
        idx += 1;
      }
      return out;
    }
    let end = idx;
    while (end < n && !/\s/.test(commandText[end])) {
      end += 1;
    }
    return commandText.slice(idx, end);
  }

  function parseInterSessionActivity(act) {
    if (!act || act.kind === "thought") {
      return null;
    }
    const raw = `${String(act.title || "")}\n${String(act.detail || "")}`;
    const sendMatch = raw.match(/\bctl\s+send\b/);
    const launchMatch = !sendMatch && raw.match(/\bctl\s+launch\b/);
    if (sendMatch || launchMatch) {
      const kind = sendMatch ? "send" : "launch";
      const threadRaw = extractCliFlagValue(raw, "--thread");
      const threadId = /^\d+$/.test(threadRaw) ? Number(threadRaw) : null;
      const prompt = extractCliFlagValue(raw, "--prompt");
      const title = extractCliFlagValue(raw, "--title");
      if (!prompt && !threadId && !title) {
        return null;
      }
      return {
        kind,
        threadId,
        title,
        prompt,
        status: act.status || "completed",
      };
    }
    if (/\bkasugai_send_thread\b/.test(raw) || /\bkasugai_launch_thread\b/.test(raw)) {
      const kind = /\bkasugai_send_thread\b/.test(raw) ? "send" : "launch";
      const tidMatch = raw.match(/"thread_id"\s*:\s*(\d+)/);
      const promptMatch = raw.match(/"prompt"\s*:\s*"((?:\\.|[^"\\])*)"/);
      const titleMatch = raw.match(/"title"\s*:\s*"((?:\\.|[^"\\])*)"/);
      const unescapeJson = (s) => {
        try {
          return JSON.parse(`"${s}"`);
        } catch (_) {
          return s;
        }
      };
      const threadId = tidMatch ? Number(tidMatch[1]) : null;
      const prompt = promptMatch ? unescapeJson(promptMatch[1]) : "";
      const title = titleMatch ? unescapeJson(titleMatch[1]) : "";
      if (!prompt && !threadId && !title) {
        return null;
      }
      return {
        kind,
        threadId,
        title,
        prompt,
        status: act.status || "completed",
      };
    }
    return null;
  }

  function buildSessionHandoffCard(handoff, threadIndex) {
    const card = document.createElement("div");
    card.className = "session-handoff-card";
    if (handoff.status === "failed") {
      card.classList.add("is-failed");
    }

    const head = document.createElement("div");
    head.className = "session-handoff-head";

    const kindBadge = document.createElement("span");
    kindBadge.className = "session-handoff-kind";
    kindBadge.innerHTML =
      '<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' +
      '<path d="M2.5 8h10"/><path d="M8.8 4.2L12.6 8l-3.8 3.8"/></svg>' +
      `<span>${handoff.kind === "launch" ? "別セッションを起動" : "別セッションへ送信"}</span>`;
    head.append(kindBadge);

    const info =
      handoff.threadId && threadIndex && threadIndex[String(handoff.threadId)]
        ? threadIndex[String(handoff.threadId)]
        : null;
    const labelParts = [];
    if (info && info.project_name) {
      labelParts.push(info.project_name);
    }
    if (info && info.title) {
      labelParts.push(info.title);
    } else if (handoff.title) {
      labelParts.push(handoff.title);
    } else if (handoff.threadId) {
      labelParts.push(`スレッド ${handoff.threadId}`);
    }
    const targetText = labelParts.join(" · ") || "セッション";

    if (handoff.threadId && handoff.threadId > 0) {
      const linkBtn = document.createElement("button");
      linkBtn.type = "button";
      linkBtn.className = "session-handoff-link";
      linkBtn.dataset.threadId = String(handoff.threadId);
      linkBtn.title = `${targetText} を開く`;

      const dot = document.createElement("span");
      dot.className = `session-handoff-dot ${info && info.status === "running" ? "is-running" : ""}`;

      const textSpan = document.createElement("span");
      textSpan.className = "session-handoff-target";
      textSpan.textContent = targetText;

      const arrow = document.createElement("span");
      arrow.className = "session-handoff-arrow";
      arrow.textContent = "↗";

      linkBtn.append(dot, textSpan, arrow);
      linkBtn.addEventListener("click", () => {
        postNativeFileLink(`kasugai-thread://${handoff.threadId}`);
      });
      head.append(linkBtn);
    } else {
      const labelSpan = document.createElement("span");
      labelSpan.className = "session-handoff-target-static";
      labelSpan.textContent = targetText;
      head.append(labelSpan);
    }

    card.append(head);

    if (handoff.prompt) {
      const body = document.createElement("div");
      body.className = "session-handoff-prompt";
      body.textContent = handoff.prompt;
      card.append(body);
    }

    return card;
  }

  function buildActivityPanel(items, isLive, panelId) {
    const visible = filterVisibleActivities(items, isLive);
    if (visible.length === 0) {
      return null;
    }

    const panelKey = panelId || (isLive ? "live" : "done");
    const panel = document.createElement("details");
    panel.className = isLive ? "activity-panel activity-live" : "activity-panel";
    const defaultOpen = Boolean(isLive || visible.some((a) => a.status === "running"));
    if (isLive && livePanelOpenOverride.has(panelKey)) {
      panel.open = Boolean(livePanelOpenOverride.get(panelKey));
    } else {
      panel.open = defaultOpen;
    }
    if (isLive) {
      panel.addEventListener("toggle", () => {
        livePanelOpenOverride.set(panelKey, panel.open);
      });
    }

    const summary = document.createElement("summary");
    summary.className = "activity-summary";

    const left = document.createElement("span");
    left.className = "activity-summary-left";
    const leadDot = document.createElement("span");
    const runningItem = visible.find((a) => a.status === "running");
    leadDot.className = `activity-dot ${runningItem || isLive ? "running" : "completed"}`;
    const heading = document.createElement("span");
    heading.className = "activity-summary-heading";
    if (isLive) {
      heading.textContent = "作業中…";
    } else {
      heading.textContent = `${visible.length} 件の操作`;
    }
    left.append(leadDot, heading);

    const right = document.createElement("span");
    right.className = "activity-summary-right";
    if (isLive) {
      const count = document.createElement("span");
      count.className = "activity-count";
      count.textContent = `${visible.length} 件`;
      right.append(count);
    }
    const chevron = document.createElement("span");
    chevron.className = "activity-chevron";
    chevron.textContent = "▸";
    right.append(chevron);

    summary.append(left, right);

    const list = document.createElement("div");
    list.className = "activity-list";

    function renderActivityRows() {
      list.replaceChildren();
      const expanded = expandedActivityPanels.has(panelKey);
      const { shown, hiddenCount } = selectActivityWindow(visible, expanded);
      if (hiddenCount > 0 || (expanded && visible.length > ACTIVITY_RECENT_LIMIT)) {
        const toggleBtn = document.createElement("button");
        toggleBtn.type = "button";
        toggleBtn.className = "activity-expand-btn";
        toggleBtn.textContent =
          hiddenCount > 0
            ? `前の ${hiddenCount} 件を表示`
            : `最新の ${ACTIVITY_RECENT_LIMIT} 件のみ表示`;
        toggleBtn.addEventListener("click", (ev) => {
          ev.preventDefault();
          ev.stopPropagation();
          if (expandedActivityPanels.has(panelKey)) {
            expandedActivityPanels.delete(panelKey);
          } else {
            expandedActivityPanels.add(panelKey);
          }
          renderActivityRows();
        });
        list.append(toggleBtn);
      }
      for (const act of shown) {
        list.append(buildActivityRow(act));
      }
    }

    renderActivityRows();
    panel.append(summary, list);
    return panel;
  }

  function buildWelcomeHero() {
    const hero = document.createElement("section");
    hero.className = "welcome-hero";

    const mark = document.createElement("div");
    mark.className = "welcome-mark";
    mark.innerHTML =
      '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round">' +
      '<path d="M5 17V7h14v10"/>' +
      '<circle cx="5" cy="17" r="2" fill="currentColor"/>' +
      '<circle cx="19" cy="17" r="2" fill="currentColor"/>' +
      "</svg>";

    const title = document.createElement("h2");
    title.className = "welcome-title";
    title.textContent = "Kasugai";

    hero.append(mark, title);
    return hero;
  }

  function setAppearance(theme, palette) {
    root.dataset.theme = theme === "light" ? "light" : "dark";
    if (typeof palette === "string" && palette) {
      root.dataset.palette = palette;
    }
  }

  let lastRenderedThreadId = null;
  let lastRenderedChatSignature = "";
  let chatRenderCount = 0;
  let isCurrentChatBusy = false;
  let isChatModeActive = false;

  const scrollToBottomBtn = (() => {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "scroll-to-bottom-btn";
    btn.setAttribute("aria-label", "最新のメッセージへ移動");

    const dot = document.createElement("span");
    dot.className = "scroll-to-bottom-dot";

    const icon = document.createElement("span");
    icon.innerHTML =
      '<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">' +
      '<path d="M8 3v10"/><path d="M3.8 9.2L8 13.4l4.2-4.2"/></svg>';
    icon.style.display = "inline-flex";

    const label = document.createElement("span");
    label.textContent = "最新へ";

    btn.append(dot, icon, label);
    btn.addEventListener("click", () => {
      const reduced =
        window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
      window.scrollTo({
        top: document.documentElement.scrollHeight,
        behavior: reduced ? "auto" : "smooth",
      });
    });
    document.body.append(btn);
    return btn;
  })();

  function syncScrollToBottomButton() {
    if (!isChatModeActive) {
      scrollToBottomBtn.classList.remove("is-visible", "is-live");
      return;
    }
    const docEl = document.documentElement;
    const maxScroll = Math.max(0, docEl.scrollHeight - window.innerHeight);
    const gap = docEl.scrollHeight - (window.scrollY + window.innerHeight);
    const threshold = Math.max(420, Math.round(window.innerHeight * 0.75));
    const show = maxScroll > threshold && gap > threshold;
    scrollToBottomBtn.classList.toggle("is-visible", show);
    scrollToBottomBtn.classList.toggle("is-live", show && isCurrentChatBusy);
  }

  window.addEventListener("scroll", syncScrollToBottomButton, { passive: true });
  window.addEventListener("resize", syncScrollToBottomButton, { passive: true });

  function buildBusyIndicator(status, pendingApproval, liveActs) {
    const row = document.createElement("div");
    row.className = "busy-indicator";
    row.dataset.liveTail = "1";
    const dot = document.createElement("span");
    const isApproval = status === "awaiting_approval" || (pendingApproval && pendingApproval.active);
    dot.className = isApproval ? "activity-dot awaiting" : "activity-dot running";
    const text = document.createElement("span");
    text.className = "busy-text";
    if (isApproval) {
      const toolLabel =
        pendingApproval && pendingApproval.tool_name ? `（${pendingApproval.tool_name}）` : "";
      text.textContent = `ツール実行の承認待ち…${toolLabel}`;
    } else if ((liveActs || []).some((a) => a && a.kind === "thought")) {
      text.textContent = "思考中…";
    } else {
      text.textContent = "応答を生成中…";
    }
    row.append(dot, text);
    return row;
  }

  const THREAD_MOTION_CLASSES = [
    "thread-leave-to-top",
    "thread-leave-to-bottom",
    "thread-leave-to-left",
    "thread-leave-to-right",
    "thread-enter-from-bottom",
    "thread-enter-from-top",
    "thread-enter-from-left",
    "thread-enter-from-right",
  ];
  let threadSwitchToken = 0;
  let threadSwitchTimer = null;
  let pendingThreadCommit = null;

  function threadMotionClasses(transitionDir) {
    if (transitionDir === "from_bottom") {
      return { leave: "thread-leave-to-top", enter: "thread-enter-from-bottom" };
    }
    if (transitionDir === "from_top") {
      return { leave: "thread-leave-to-bottom", enter: "thread-enter-from-top" };
    }
    if (transitionDir === "from_right") {
      return { leave: "thread-leave-to-left", enter: "thread-enter-from-right" };
    }
    return { leave: "thread-leave-to-left", enter: "thread-enter-from-left" };
  }

  function triggerThreadEnter(targetEl, enterClass) {
    if (!targetEl) {
      return;
    }
    if (window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      targetEl.classList.remove(...THREAD_MOTION_CLASSES);
      return;
    }
    targetEl.classList.remove(...THREAD_MOTION_CLASSES);
    void targetEl.offsetWidth;
    targetEl.classList.add(enterClass);
    targetEl.addEventListener(
      "animationend",
      () => {
        targetEl.classList.remove(enterClass);
      },
      { once: true }
    );
  }

  function commitThreadDom(thread, mediaMap, threadIndex, signature, isNewThread, enterClass) {
    const messages = Array.isArray(thread.messages) ? thread.messages : [];
    const queue = Array.isArray(thread.queue) ? thread.queue : [];
    const activities = Array.isArray(thread.activities) ? thread.activities : [];
    const streaming = typeof thread.streaming_text === "string" ? thread.streaming_text : "";
    const lastError = typeof thread.last_error === "string" ? thread.last_error : "";
    const pendingApproval = thread.pending_approval || null;
    const isBusy = thread.status === "running" || thread.status === "awaiting_approval";
    isChatModeActive = true;
    isCurrentChatBusy = isBusy;

    const docEl = document.documentElement;
    const scrollBottomGap = docEl.scrollHeight - (window.scrollY + window.innerHeight);
    const wasNearBottom = isNewThread || scrollBottomGap <= 80;
    const prevScrollY = window.scrollY;

    lastRenderedThreadId = thread.id;
    lastRenderedChatSignature = signature;
    chatRenderCount += 1;
    container.dataset.renderCount = String(chatRenderCount);

    if (
      messages.length === 0 &&
      queue.length === 0 &&
      !streaming &&
      !lastError &&
      activities.length === 0 &&
      !isBusy
    ) {
      container.replaceChildren(buildWelcomeHero());
      if (enterClass) {
        triggerThreadEnter(container, enterClass);
      }
      syncScrollToBottomButton();
      return true;
    }

    const activeTurnId = Number(thread.active_turn_id || 0);
    const activitiesByTurn = new Map();
    for (const act of activities) {
      const tid = Number(act.turn_id || 0);
      if (tid <= 0) {
        continue;
      }
      if (!activitiesByTurn.has(tid)) {
        activitiesByTurn.set(tid, []);
      }
      activitiesByTurn.get(tid).push(act);
    }

    let list = !isNewThread ? container.querySelector(":scope > section.messages") : null;
    if (!list) {
      container.replaceChildren();
      list = document.createElement("section");
      list.className = "messages";
      container.append(list);
    } else {
      for (const stale of Array.from(container.querySelectorAll(":scope > [data-live-tail='1']"))) {
        stale.remove();
      }
      for (const stale of Array.from(list.querySelectorAll(":scope > [data-live-tail='1']"))) {
        stale.remove();
      }
    }

    const existingNodes = new Map();
    for (const child of Array.from(list.children)) {
      if (child.dataset && child.dataset.stableKey) {
        existingNodes.set(child.dataset.stableKey, child);
      }
    }

    let trailingUserStart = messages.length;
    if (isBusy) {
      while (trailingUserStart > 0 && messages[trailingUserStart - 1].role === "user") {
        trailingUserStart -= 1;
      }
    }
    const splitSteeredIndex =
      isBusy && messages.length - trailingUserStart > 1 ? trailingUserStart + 1 : messages.length;
    const stableMessages = messages.slice(0, splitSteeredIndex);
    const pendingSteeredMessages = messages.slice(splitSteeredIndex);

    const desiredStable = [];
    const renderedActivityTurns = new Set();
    for (let idx = 0; idx < stableMessages.length; idx += 1) {
      const msg = stableMessages[idx];
      const msgTurnId = Number(msg.turn_id || 0);
      if (msg.role === "assistant" && msgTurnId > 0 && !renderedActivityTurns.has(msgTurnId)) {
        const turnActs = activitiesByTurn.get(msgTurnId);
        if (turnActs && turnActs.length > 0) {
          const panelId = `t:${thread.id}:turn:${msgTurnId}`;
          const actKey = `act:${msgTurnId}:${JSON.stringify(turnActs)}`;
          let actNode = existingNodes.get(actKey);
          if (!actNode) {
            actNode = buildActivityPanel(turnActs, false, panelId);
            if (actNode) {
              actNode.dataset.stableKey = actKey;
            }
          }
          if (actNode) {
            desiredStable.push(actNode);
          }
          const handoffs = turnActs.map(parseInterSessionActivity).filter(Boolean);
          for (let hIdx = 0; hIdx < handoffs.length; hIdx += 1) {
            const handoff = handoffs[hIdx];
            const info =
              handoff.threadId && threadIndex ? threadIndex[String(handoff.threadId)] || null : null;
            const hKey = `handoff:${msgTurnId}:${hIdx}:${JSON.stringify(handoff)}:${JSON.stringify(info)}`;
            let hNode = existingNodes.get(hKey);
            if (!hNode) {
              hNode = buildSessionHandoffCard(handoff, threadIndex);
              hNode.dataset.stableKey = hKey;
            }
            desiredStable.push(hNode);
          }
          renderedActivityTurns.add(msgTurnId);
        }
      }
      const msgKey = `msg:${msg.id || idx}:${msg.role}:${msg.text || ""}:${JSON.stringify(msg.attachments || [])}`;
      let msgNode = existingNodes.get(msgKey);
      if (!msgNode) {
        msgNode = buildMessageBlock(msg, false, mediaMap);
        msgNode.dataset.stableKey = msgKey;
      }
      desiredStable.push(msgNode);
    }

    const desiredSet = new Set(desiredStable);
    for (const child of Array.from(list.children)) {
      if (!desiredSet.has(child)) {
        child.remove();
      }
    }
    for (let idx = 0; idx < desiredStable.length; idx += 1) {
      const node = desiredStable[idx];
      if (list.children[idx] !== node) {
        list.insertBefore(node, list.children[idx] || null);
      }
    }

    const liveActs =
      isBusy && activeTurnId > 0 && !renderedActivityTurns.has(activeTurnId)
        ? activitiesByTurn.get(activeTurnId) || []
        : [];
    let hasLivePanel = false;
    if (liveActs.length > 0) {
      const livePanelId = `t:${thread.id}:turn:${activeTurnId}`;
      const livePanel = buildActivityPanel(liveActs, true, livePanelId);
      if (livePanel) {
        livePanel.dataset.liveTail = "1";
        list.append(livePanel);
        hasLivePanel = true;
      }
      const liveHandoffs = liveActs.map(parseInterSessionActivity).filter(Boolean);
      for (const handoff of liveHandoffs) {
        const hNode = buildSessionHandoffCard(handoff, threadIndex);
        hNode.dataset.liveTail = "1";
        list.append(hNode);
      }
      renderedActivityTurns.add(activeTurnId);
    }

    const isApproval =
      thread.status === "awaiting_approval" || (pendingApproval && pendingApproval.active);
    if (streaming) {
      const streamNode = buildMessageBlock(
        {
          role: "assistant",
          provider: thread.provider_name || thread.provider || "",
          model: thread.model || "",
          text: streaming,
          attachments: [],
        },
        true,
        mediaMap
      );
      streamNode.dataset.liveTail = "1";
      list.append(streamNode);
    } else if (isBusy && (isApproval || !hasLivePanel)) {
      list.append(buildBusyIndicator(thread.status, pendingApproval, liveActs));
    }

    for (const item of pendingSteeredMessages) {
      const steeredNode = buildMessageBlock(item, false, mediaMap, "steered");
      steeredNode.dataset.liveTail = "1";
      list.append(steeredNode);
    }

    for (const item of queue) {
      const queuedNode = buildMessageBlock(
        {
          role: "user",
          text: item.text || "",
          attachments: Array.isArray(item.attachments) ? item.attachments : [],
        },
        false,
        mediaMap,
        "queued"
      );
      queuedNode.dataset.liveTail = "1";
      list.append(queuedNode);
    }

    if (lastError) {
      const isUserStop = lastError === "ターンを停止しました";
      const errBanner = document.createElement("section");
      errBanner.className = isUserStop ? "banner notice" : "banner error";
      errBanner.dataset.liveTail = "1";
      if (isUserStop) {
        const heading = document.createElement("p");
        heading.className = "banner-title";
        heading.textContent = "ターンを停止しました";
        errBanner.append(heading);
      } else {
        const heading = document.createElement("p");
        heading.className = "banner-title";
        heading.textContent = "前回のターンでエラーが発生しました";
        const detail = document.createElement("p");
        detail.textContent = lastError;
        errBanner.append(heading, detail);
      }
      container.append(errBanner);
    }

    if (wasNearBottom) {
      window.scrollTo(0, document.documentElement.scrollHeight);
    } else {
      window.scrollTo(0, prevScrollY);
    }
    syncScrollToBottomButton();
    if (enterClass) {
      triggerThreadEnter(container, enterClass);
    }
    return true;
  }

  function renderThread(payloadJson, mediaMapJson, transitionDir, threadIndexJson) {
    const thread = typeof payloadJson === "string" ? JSON.parse(payloadJson) : payloadJson;
    const mediaMap = typeof mediaMapJson === "string" && mediaMapJson
      ? JSON.parse(mediaMapJson)
      : {};
    const threadIndex = typeof threadIndexJson === "string" && threadIndexJson
      ? JSON.parse(threadIndexJson)
      : {};
    if (!container.classList.contains("canvas") || container.classList.contains("diff-canvas")) {
      container.className = "canvas";
    }
    if (!thread) {
      if (threadSwitchTimer !== null) {
        clearTimeout(threadSwitchTimer);
        threadSwitchTimer = null;
      }
      pendingThreadCommit = null;
      lastRenderedThreadId = null;
      lastRenderedChatSignature = "";
      container.classList.remove(...THREAD_MOTION_CLASSES);
      container.innerHTML =
        '<section class="empty-state"><h2 class="empty-title">スレッドが選択されていません</h2>' +
        '<p class="empty-body">左のサイドバーからスレッドを選択するか、新規スレッドを作成してください。</p></section>';
      return true;
    }

    const messages = Array.isArray(thread.messages) ? thread.messages : [];
    const queue = Array.isArray(thread.queue) ? thread.queue : [];
    const activities = Array.isArray(thread.activities) ? thread.activities : [];
    const streaming = typeof thread.streaming_text === "string" ? thread.streaming_text : "";
    const lastError = typeof thread.last_error === "string" ? thread.last_error : "";
    const pendingApproval = thread.pending_approval || null;
    const signature = JSON.stringify({
      id: thread.id,
      status: thread.status,
      active_turn_id: thread.active_turn_id || 0,
      messages,
      queue,
      activities,
      streaming,
      lastError,
      pendingApproval,
      mediaMap,
      threadIndex,
    });

    if (pendingThreadCommit) {
      if (pendingThreadCommit.thread.id === thread.id) {
        pendingThreadCommit.thread = thread;
        pendingThreadCommit.mediaMap = mediaMap;
        pendingThreadCommit.threadIndex = threadIndex;
        pendingThreadCommit.signature = signature;
        return true;
      }
      if (threadSwitchTimer !== null) {
        clearTimeout(threadSwitchTimer);
        threadSwitchTimer = null;
      }
      const motion = threadMotionClasses(transitionDir);
      pendingThreadCommit = null;
      threadSwitchToken += 1;
      return commitThreadDom(thread, mediaMap, threadIndex, signature, true, motion.enter);
    }

    if (signature === lastRenderedChatSignature) {
      return true;
    }

    const hadPreviousThread = lastRenderedThreadId !== null;
    const isNewThread = lastRenderedThreadId !== thread.id;
    const reducedMotion =
      window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    const shouldAnimateSwitch =
      isNewThread && hadPreviousThread && transitionDir !== "none" && !reducedMotion;

    if (!shouldAnimateSwitch) {
      return commitThreadDom(thread, mediaMap, threadIndex, signature, isNewThread, null);
    }

    const motion = threadMotionClasses(transitionDir);
    threadSwitchToken += 1;
    const myToken = threadSwitchToken;
    pendingThreadCommit = {
      thread,
      mediaMap,
      threadIndex,
      signature,
      enterClass: motion.enter,
    };

    container.classList.remove(...THREAD_MOTION_CLASSES);
    void container.offsetWidth;
    container.classList.add(motion.leave);

    threadSwitchTimer = setTimeout(() => {
      threadSwitchTimer = null;
      if (threadSwitchToken !== myToken || !pendingThreadCommit) {
        return;
      }
      const next = pendingThreadCommit;
      pendingThreadCommit = null;
      commitThreadDom(
        next.thread,
        next.mediaMap,
        next.threadIndex,
        next.signature,
        true,
        next.enterClass
      );
    }, 85);
    return true;
  }

  function diffStatusBadgeInfo(code) {
    if (code === "?" || code === "A") {
      return { text: code === "?" ? "U" : "A", label: code === "?" ? "新規" : "追加", cls: "is-added" };
    }
    if (code === "D") {
      return { text: "D", label: "削除", cls: "is-deleted" };
    }
    if (code === "R") {
      return { text: "R", label: "移動", cls: "is-renamed" };
    }
    return { text: "M", label: "変更", cls: "is-modified" };
  }

  function parsePatchRows(patchText) {
    if (!patchText) {
      return [];
    }
    const lines = String(patchText).split("\n");
    const rows = [];
    let oldNo = 0;
    let newNo = 0;
    let inHunk = false;

    for (const line of lines) {
      if (
        line.startsWith("diff --git ") ||
        line.startsWith("index ") ||
        line.startsWith("new file mode") ||
        line.startsWith("deleted file mode") ||
        line.startsWith("--- ") ||
        line.startsWith("+++ ")
      ) {
        continue;
      }

      if (line.startsWith("@@")) {
        const match = line.match(/@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/);
        if (match) {
          oldNo = Number(match[1]);
          newNo = Number(match[2]);
          inHunk = true;
        }
        rows.push({ kind: "hunk", text: line });
        continue;
      }

      if (!inHunk && line === "") {
        continue;
      }

      if (line.startsWith("+")) {
        rows.push({ kind: "add", oldNo: "", newNo: inHunk ? String(newNo) : "", text: line.slice(1) });
        newNo += 1;
      } else if (line.startsWith("-")) {
        rows.push({ kind: "del", oldNo: inHunk ? String(oldNo) : "", newNo: "", text: line.slice(1) });
        oldNo += 1;
      } else {
        const content = line.startsWith(" ") ? line.slice(1) : line;
        rows.push({
          kind: "ctx",
          oldNo: inHunk ? String(oldNo) : "",
          newNo: inHunk ? String(newNo) : "",
          text: content,
        });
        if (inHunk) {
          oldNo += 1;
          newNo += 1;
        }
      }
    }
    return rows;
  }

  function buildUnifiedPatchTable(rows, wordWrap, filePath) {
    const table = document.createElement("div");
    table.className = wordWrap ? "diff-code-table is-wrap" : "diff-code-table";
    if (rows.length === 0) {
      const note = document.createElement("div");
      note.className = "diff-empty-patch";
      note.textContent = "テキスト差分はありません（バイナリまたは空ファイル）";
      table.append(note);
      return table;
    }

    const langSpec = detectHighlightLang(filePath);
    const emphByIndex = new Map();
    let idx = 0;
    while (idx < rows.length) {
      if (rows[idx].kind !== "del" && rows[idx].kind !== "add") {
        idx += 1;
        continue;
      }
      const delIdx = [];
      const addIdx = [];
      while (idx < rows.length && (rows[idx].kind === "del" || rows[idx].kind === "add")) {
        if (rows[idx].kind === "del") {
          delIdx.push(idx);
        } else {
          addIdx.push(idx);
        }
        idx += 1;
      }
      const pairs = Math.min(delIdx.length, addIdx.length);
      if (delIdx.length === addIdx.length || pairs === 1) {
        for (let k = 0; k < pairs; k += 1) {
          const intra = computeIntralineDiff(rows[delIdx[k]].text, rows[addIdx[k]].text);
          if (intra) {
            emphByIndex.set(delIdx[k], { range: intra.oldRange, cls: "diff-emph-del" });
            emphByIndex.set(addIdx[k], { range: intra.newRange, cls: "diff-emph-add" });
          }
        }
      }
    }

    for (let i = 0; i < rows.length; i += 1) {
      const item = rows[i];
      if (item.kind === "hunk") {
        const row = document.createElement("div");
        row.className = "diff-row diff-hunk";
        const gutter = document.createElement("span");
        gutter.className = "diff-gutter diff-gutter-hunk";
        gutter.textContent = "⋯";
        const code = document.createElement("span");
        code.className = "diff-code";
        code.textContent = item.text;
        row.append(gutter, code);
        table.append(row);
        continue;
      }

      const row = document.createElement("div");
      row.className =
        item.kind === "add"
          ? "diff-row diff-add"
          : item.kind === "del"
            ? "diff-row diff-del"
            : "diff-row";

      const lnCell = document.createElement("span");
      lnCell.className = "diff-ln";
      lnCell.textContent = item.kind === "del" ? item.oldNo : item.newNo;

      const codeCell = document.createElement("span");
      codeCell.className = "diff-code";
      const emph = emphByIndex.get(i);
      codeCell.innerHTML = renderHighlightedLine(
        item.text,
        langSpec,
        emph ? emph.range : null,
        emph ? emph.cls : ""
      );

      row.append(lnCell, codeCell);
      table.append(row);
    }
    return table;
  }

  function buildSplitPatchTable(rows, wordWrap, filePath) {
    const table = document.createElement("div");
    table.className = wordWrap ? "diff-split-table is-wrap" : "diff-split-table";
    if (rows.length === 0) {
      const note = document.createElement("div");
      note.className = "diff-empty-patch";
      note.textContent = "テキスト差分はありません（バイナリまたは空ファイル）";
      table.append(note);
      return table;
    }

    const langSpec = detectHighlightLang(filePath);
    let i = 0;
    while (i < rows.length) {
      const item = rows[i];
      if (item.kind === "hunk") {
        const row = document.createElement("div");
        row.className = "diff-split-hunk";
        row.textContent = item.text;
        table.append(row);
        i += 1;
        continue;
      }

      if (item.kind === "ctx") {
        table.append(buildSplitRow(item, item, langSpec, null));
        i += 1;
        continue;
      }

      const dels = [];
      const adds = [];
      while (i < rows.length && (rows[i].kind === "del" || rows[i].kind === "add")) {
        if (rows[i].kind === "del") {
          dels.push(rows[i]);
        } else {
          adds.push(rows[i]);
        }
        i += 1;
      }
      const pairCount = Math.max(dels.length, adds.length);
      for (let k = 0; k < pairCount; k += 1) {
        const l = dels[k] || null;
        const r = adds[k] || null;
        const intra = l && r ? computeIntralineDiff(l.text, r.text) : null;
        table.append(buildSplitRow(l, r, langSpec, intra));
      }
    }
    return table;
  }

  function buildSplitRow(left, right, langSpec, intra) {
    const row = document.createElement("div");
    row.className = "diff-split-row";

    const leftCell = document.createElement("div");
    leftCell.className =
      left && left.kind === "del"
        ? "diff-split-side diff-del"
        : left
          ? "diff-split-side"
          : "diff-split-side diff-split-empty";
    const lNo = document.createElement("span");
    lNo.className = "diff-ln";
    lNo.textContent = left ? left.oldNo : "";
    const lCode = document.createElement("span");
    lCode.className = "diff-code";
    lCode.innerHTML = left
      ? renderHighlightedLine(left.text, langSpec, intra ? intra.oldRange : null, "diff-emph-del")
      : " ";
    leftCell.append(lNo, lCode);

    const rightCell = document.createElement("div");
    rightCell.className =
      right && right.kind === "add"
        ? "diff-split-side diff-add"
        : right
          ? "diff-split-side"
          : "diff-split-side diff-split-empty";
    const rNo = document.createElement("span");
    rNo.className = "diff-ln";
    rNo.textContent = right ? right.newNo : "";
    const rCode = document.createElement("span");
    rCode.className = "diff-code";
    rCode.innerHTML = right
      ? renderHighlightedLine(right.text, langSpec, intra ? intra.newRange : null, "diff-emph-add")
      : " ";
    rightCell.append(rNo, rCode);

    row.append(leftCell, rightCell);
    return row;
  }

  function buildDirectoryTree(files) {
    const root = { name: "", fullPath: "", dirs: new Map(), files: [] };
    for (const file of files) {
      const parts = String(file.path || "").split("/").filter(Boolean);
      if (parts.length === 0) {
        continue;
      }
      let cur = root;
      let prefix = "";
      for (let i = 0; i < parts.length - 1; i += 1) {
        const seg = parts[i];
        prefix = prefix ? `${prefix}/${seg}` : seg;
        if (!cur.dirs.has(seg)) {
          cur.dirs.set(seg, { name: seg, fullPath: prefix, dirs: new Map(), files: [] });
        }
        cur = cur.dirs.get(seg);
      }
      cur.files.push({ name: parts[parts.length - 1], file });
    }

    function compactNode(node) {
      const compactedDirs = [];
      for (const child of node.dirs.values()) {
        let cur = child;
        let label = cur.name;
        while (cur.files.length === 0 && cur.dirs.size === 1) {
          const onlyChild = cur.dirs.values().next().value;
          label = `${label}/${onlyChild.name}`;
          cur = onlyChild;
        }
        const sub = compactNode(cur);
        compactedDirs.push({
          label,
          fullPath: cur.fullPath,
          dirs: sub.dirs,
          files: sub.files,
        });
      }
      compactedDirs.sort((a, b) => a.label.localeCompare(b.label));
      const sortedFiles = [...node.files].sort((a, b) => a.name.localeCompare(b.name));
      return { dirs: compactedDirs, files: sortedFiles };
    }

    return compactNode(root);
  }

  function collectTreeDirPaths(treeNode, out) {
    for (const dir of treeNode.dirs) {
      out.push(dir.fullPath);
      collectTreeDirPaths(dir, out);
    }
  }

  function collectOrderedFiles(treeNode, out) {
    for (const dir of treeNode.dirs) {
      collectOrderedFiles(dir, out);
    }
    for (const leaf of treeNode.files) {
      out.push(leaf.file);
    }
  }

  const diffUiState = {
    selectedPath: null,
    treeOpen: true,
    splitMode: false,
    wordWrap: true,
    treeWidth: 196,
    collapsedDirs: new Set(),
  };

  function makeSvg(body, size) {
    const s = size || 13;
    return `<svg width="${s}" height="${s}" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.45" stroke-linecap="round" stroke-linejoin="round">${body}</svg>`;
  }

  function renderDiff(payloadJson, focusFilePath, diffMediaJson) {
    isChatModeActive = false;
    isCurrentChatBusy = false;
    syncScrollToBottomButton();
    const report = typeof payloadJson === "string" ? JSON.parse(payloadJson) : payloadJson;
    const diffMediaMap =
      typeof diffMediaJson === "string" && diffMediaJson
        ? JSON.parse(diffMediaJson)
        : diffMediaJson && typeof diffMediaJson === "object"
          ? diffMediaJson
          : {};
    container.replaceChildren();
    container.className = "canvas diff-workbench-root";

    if (!report) {
      return true;
    }
    if (!report.is_git_repo) {
      const empty = document.createElement("section");
      empty.className = "empty-state";
      const title = document.createElement("h2");
      title.className = "empty-title";
      title.textContent = "このフォルダは Git リポジトリではありません";
      const body = document.createElement("p");
      body.className = "empty-body";
      body.textContent =
        "左上のプロジェクト切替から Git 管理下のフォルダを追加すると、変更ファイル一覧と差分が表示されます。";
      empty.append(title, body);
      container.append(empty);
      return true;
    }

    const files = Array.isArray(report.files) ? report.files : [];
    const statusLines = Array.isArray(report.status_lines) ? report.status_lines : [];
    const diffText = typeof report.unified_diff === "string" ? report.unified_diff : "";

    if (files.length === 0 && statusLines.length === 0 && !diffText) {
      const empty = document.createElement("section");
      empty.className = "empty-state";
      const title = document.createElement("h2");
      title.className = "empty-title";
      title.textContent = "変更差分がありません";
      const body = document.createElement("p");
      body.className = "empty-body";
      body.textContent = report.branch ? `ブランチ: ${report.branch}` : report.directory || "";
      empty.append(title, body);
      container.append(empty);
      return true;
    }

    const normalizedFiles =
      files.length > 0
        ? files
        : statusLines.map((line) => ({
            path: String(line).slice(3).trim(),
            status: String(line).startsWith("??") ? "?" : "M",
            insertions: 0,
            deletions: 0,
            patch: diffText,
          }));

    const tree = buildDirectoryTree(normalizedFiles);
    const orderedFiles = [];
    collectOrderedFiles(tree, orderedFiles);
    const allDirPaths = [];
    collectTreeDirPaths(tree, allDirPaths);

    if (focusFilePath && orderedFiles.some((f) => f.path === focusFilePath)) {
      diffUiState.selectedPath = focusFilePath;
    } else if (!diffUiState.selectedPath || !orderedFiles.some((f) => f.path === diffUiState.selectedPath)) {
      diffUiState.selectedPath = orderedFiles[0] ? orderedFiles[0].path : null;
    }

    if (diffUiState.selectedPath) {
      for (const dirPath of allDirPaths) {
        if (diffUiState.selectedPath.startsWith(`${dirPath}/`)) {
          diffUiState.collapsedDirs.delete(dirPath);
        }
      }
    }

    const topBar = document.createElement("header");
    topBar.className = "diff-top-bar";

    const workbench = document.createElement("div");
    workbench.className = "diff-workbench";

    const codePane = document.createElement("section");
    codePane.className = "diff-code-pane";

    const resizeHandle = document.createElement("div");
    resizeHandle.className = "diff-tree-resizer";
    resizeHandle.title = "ファイルツリーの幅を変更";

    const treePane = document.createElement("aside");
    treePane.className = "diff-tree-pane";

    resizeHandle.addEventListener("pointerdown", (ev) => {
      if (workbench.classList.contains("is-stacked")) {
        return;
      }
      ev.preventDefault();
      const startX = ev.clientX;
      const startW = diffUiState.treeWidth;
      resizeHandle.setPointerCapture(ev.pointerId);
      const onMove = (moveEv) => {
        const delta = startX - moveEv.clientX;
        const maxW = Math.max(170, Math.min(340, workbench.clientWidth - 260));
        diffUiState.treeWidth = Math.max(150, Math.min(maxW, startW + delta));
        treePane.style.width = `${diffUiState.treeWidth}px`;
      };
      const onUp = () => {
        resizeHandle.removeEventListener("pointermove", onMove);
        resizeHandle.removeEventListener("pointerup", onUp);
      };
      resizeHandle.addEventListener("pointermove", onMove);
      resizeHandle.addEventListener("pointerup", onUp);
    });

    function syncResponsiveMode() {
      const width = container.clientWidth || window.innerWidth || 600;
      const isNarrow = width < 520;
      workbench.classList.toggle("is-stacked", isNarrow);
      topBar.classList.toggle("is-narrow", isNarrow);
      if (!isNarrow) {
        const maxW = Math.max(160, Math.min(320, Math.floor(width * 0.42)));
        const clamped = Math.max(150, Math.min(maxW, diffUiState.treeWidth));
        treePane.style.width = `${clamped}px`;
      } else {
        treePane.style.width = "";
      }
    }

    function renderTopBar() {
      topBar.replaceChildren();
      const selectedIdx = orderedFiles.findIndex((f) => f.path === diffUiState.selectedPath);

      const left = document.createElement("div");
      left.className = "diff-top-left";

      const totalCount = document.createElement("span");
      totalCount.className = "diff-top-summary";
      totalCount.textContent = `${orderedFiles.length} 件`;
      left.append(totalCount);

      if (Number(report.insertions || 0) > 0) {
        const addEl = document.createElement("span");
        addEl.className = "diff-stat-add";
        addEl.textContent = `+${report.insertions}`;
        left.append(addEl);
      }
      if (Number(report.deletions || 0) > 0) {
        const delEl = document.createElement("span");
        delEl.className = "diff-stat-del";
        delEl.textContent = `-${report.deletions}`;
        left.append(delEl);
      }

      const right = document.createElement("div");
      right.className = "diff-top-right";

      if (orderedFiles.length > 1) {
        const stepper = document.createElement("div");
        stepper.className = "diff-btn-group";

        const prevBtn = document.createElement("button");
        prevBtn.type = "button";
        prevBtn.className = "diff-icon-btn";
        prevBtn.title = "前のファイル";
        prevBtn.disabled = selectedIdx <= 0;
        prevBtn.innerHTML = makeSvg('<path d="M10 3.5L5.5 8L10 12.5"/>', 12);
        prevBtn.addEventListener("click", () => {
          if (selectedIdx > 0) {
            diffUiState.selectedPath = orderedFiles[selectedIdx - 1].path;
            renderAll();
          }
        });

        const pos = document.createElement("span");
        pos.className = "diff-file-pos";
        pos.textContent = `${Math.max(1, selectedIdx + 1)}/${orderedFiles.length}`;

        const nextBtn = document.createElement("button");
        nextBtn.type = "button";
        nextBtn.className = "diff-icon-btn";
        nextBtn.title = "次のファイル";
        nextBtn.disabled = selectedIdx >= orderedFiles.length - 1;
        nextBtn.innerHTML = makeSvg('<path d="M6 3.5L10.5 8L6 12.5"/>', 12);
        nextBtn.addEventListener("click", () => {
          if (selectedIdx < orderedFiles.length - 1) {
            diffUiState.selectedPath = orderedFiles[selectedIdx + 1].path;
            renderAll();
          }
        });

        stepper.append(prevBtn, pos, nextBtn);
        right.append(stepper);
      }

      const layoutGroup = document.createElement("div");
      layoutGroup.className = "diff-btn-group diff-split-toggle";

      const unifiedBtn = document.createElement("button");
      unifiedBtn.type = "button";
      unifiedBtn.className = !diffUiState.splitMode ? "diff-icon-btn is-active" : "diff-icon-btn";
      unifiedBtn.title = "統一表示";
      unifiedBtn.innerHTML = makeSvg(
        '<rect x="2" y="2.5" width="12" height="11" rx="1.6"/><line x1="2" y1="6.2" x2="14" y2="6.2"/><line x1="2" y1="9.8" x2="14" y2="9.8"/>',
        12
      );
      unifiedBtn.addEventListener("click", () => {
        if (diffUiState.splitMode) {
          diffUiState.splitMode = false;
          renderAll();
        }
      });

      const splitBtn = document.createElement("button");
      splitBtn.type = "button";
      splitBtn.className = diffUiState.splitMode ? "diff-icon-btn is-active" : "diff-icon-btn";
      splitBtn.title = "分割表示";
      splitBtn.innerHTML = makeSvg(
        '<rect x="2" y="2.5" width="12" height="11" rx="1.6"/><line x1="8" y1="2.5" x2="8" y2="13.5"/>',
        12
      );
      splitBtn.addEventListener("click", () => {
        if (!diffUiState.splitMode) {
          diffUiState.splitMode = true;
          renderAll();
        }
      });

      layoutGroup.append(unifiedBtn, splitBtn);
      right.append(layoutGroup);

      const wrapBtn = document.createElement("button");
      wrapBtn.type = "button";
      wrapBtn.className = diffUiState.wordWrap ? "diff-icon-btn is-active" : "diff-icon-btn";
      wrapBtn.title = diffUiState.wordWrap ? "行の折り返しをオフ" : "行の折り返しをオン";
      wrapBtn.innerHTML = makeSvg(
        '<path d="M2.5 4h11M2.5 8h8.5a2 2 0 1 1 0 4H8.5"/><path d="M10 10.5L8.3 12l1.7 1.5"/><path d="M2.5 12h3"/>',
        12
      );
      wrapBtn.addEventListener("click", () => {
        diffUiState.wordWrap = !diffUiState.wordWrap;
        renderAll();
      });

      const treeToggleBtn = document.createElement("button");
      treeToggleBtn.type = "button";
      treeToggleBtn.className = diffUiState.treeOpen ? "diff-icon-btn is-active" : "diff-icon-btn";
      treeToggleBtn.title = diffUiState.treeOpen ? "ファイルツリーを隠す" : "ファイルツリーを表示";
      treeToggleBtn.innerHTML = makeSvg(
        '<rect x="1.8" y="2.4" width="12.4" height="11.2" rx="1.8"/><line x1="10" y1="2.4" x2="10" y2="13.6"/>',
        12
      );
      treeToggleBtn.addEventListener("click", () => {
        diffUiState.treeOpen = !diffUiState.treeOpen;
        renderAll();
      });

      right.append(wrapBtn, treeToggleBtn);
      topBar.append(left, right);
    }

    function renderTreePane() {
      treePane.replaceChildren();
      treePane.hidden = !diffUiState.treeOpen;
      resizeHandle.hidden = !diffUiState.treeOpen;
      if (!diffUiState.treeOpen) {
        return;
      }

      const header = document.createElement("div");
      header.className = "diff-tree-header";

      const title = document.createElement("span");
      title.className = "diff-tree-title";
      title.textContent = "ファイル";

      const count = document.createElement("span");
      count.className = "diff-tree-count";
      count.textContent = String(orderedFiles.length);

      header.append(title, count);

      if (allDirPaths.length > 0) {
        const allExpanded = allDirPaths.every((p) => !diffUiState.collapsedDirs.has(p));
        const toggleDirsBtn = document.createElement("button");
        toggleDirsBtn.type = "button";
        toggleDirsBtn.className = "diff-icon-btn";
        toggleDirsBtn.title = allExpanded ? "フォルダをすべて折りたたむ" : "フォルダをすべて展開";
        toggleDirsBtn.innerHTML = allExpanded
          ? makeSvg('<path d="M4.5 2.5L8 5.8L11.5 2.5"/><path d="M4.5 13.5L8 10.2L11.5 13.5"/>', 12)
          : makeSvg('<path d="M4.5 5.8L8 2.5L11.5 5.8"/><path d="M4.5 10.2L8 13.5L11.5 10.2"/>', 12);
        toggleDirsBtn.addEventListener("click", () => {
          if (allExpanded) {
            for (const p of allDirPaths) {
              diffUiState.collapsedDirs.add(p);
            }
          } else {
            diffUiState.collapsedDirs.clear();
          }
          renderTreePane();
        });
        header.append(toggleDirsBtn);
      }

      const body = document.createElement("div");
      body.className = "diff-tree-body";

      function appendTreeNodes(node, depth) {
        for (const dir of node.dirs) {
          const isCollapsed = diffUiState.collapsedDirs.has(dir.fullPath);
          const dirBtn = document.createElement("button");
          dirBtn.type = "button";
          dirBtn.className = "diff-tree-dir";
          dirBtn.style.paddingLeft = `${8 + depth * 12}px`;
          dirBtn.title = dir.fullPath;

          const chevron = document.createElement("span");
          chevron.className = "diff-tree-chevron";
          chevron.textContent = isCollapsed ? "▸" : "▾";

          const folderMark = document.createElement("span");
          folderMark.className = "diff-tree-folder-icon";
          folderMark.innerHTML = makeSvg(
            '<path d="M1.8 4.2A1.2 1.2 0 0 1 3 3h3l1.3 1.5H13a1.2 1.2 0 0 1 1.2 1.2v6.1A1.2 1.2 0 0 1 13 13H3a1.2 1.2 0 0 1-1.2-1.2V4.2Z"/>',
            12
          );

          const label = document.createElement("span");
          label.className = "diff-tree-dir-name";
          label.textContent = dir.label;

          dirBtn.append(chevron, folderMark, label);
          dirBtn.addEventListener("click", () => {
            if (isCollapsed) {
              diffUiState.collapsedDirs.delete(dir.fullPath);
            } else {
              diffUiState.collapsedDirs.add(dir.fullPath);
            }
            renderTreePane();
          });
          body.append(dirBtn);

          if (!isCollapsed) {
            appendTreeNodes(dir, depth + 1);
          }
        }

        for (const leaf of node.files) {
          const entry = leaf.file;
          const isSelected = entry.path === diffUiState.selectedPath;
          const fileBtn = document.createElement("button");
          fileBtn.type = "button";
          fileBtn.className = isSelected ? "diff-tree-file is-selected" : "diff-tree-file";
          fileBtn.style.paddingLeft = `${16 + depth * 12}px`;
          fileBtn.title = entry.path;

          const badgeInfo = diffStatusBadgeInfo(entry.status);
          const statusEl = document.createElement("span");
          statusEl.className = `diff-tree-status ${badgeInfo.cls}`;
          statusEl.textContent = badgeInfo.text;

          const nameEl = document.createElement("span");
          nameEl.className = "diff-tree-file-name";
          nameEl.textContent = leaf.name;

          const statEl = document.createElement("span");
          statEl.className = "diff-tree-file-stats";
          if (Number(entry.insertions || 0) > 0) {
            const a = document.createElement("span");
            a.className = "diff-stat-add";
            a.textContent = `+${entry.insertions}`;
            statEl.append(a);
          }
          if (Number(entry.deletions || 0) > 0) {
            const d = document.createElement("span");
            d.className = "diff-stat-del";
            d.textContent = `-${entry.deletions}`;
            statEl.append(d);
          }

          fileBtn.append(statusEl, nameEl, statEl);
          fileBtn.addEventListener("click", () => {
            diffUiState.selectedPath = entry.path;
            renderAll();
          });
          body.append(fileBtn);
        }
      }

      appendTreeNodes(tree, 0);
      treePane.append(header, body);
    }

    function renderCodePane() {
      codePane.replaceChildren();
      const selectedIdx = orderedFiles.findIndex((f) => f.path === diffUiState.selectedPath);
      const activeFile = selectedIdx >= 0 ? orderedFiles[selectedIdx] : orderedFiles[0];
      if (!activeFile) {
        return;
      }

      const fileBar = document.createElement("div");
      fileBar.className = "diff-file-bar";

      const badgeInfo = diffStatusBadgeInfo(activeFile.status);
      const badge = document.createElement("span");
      badge.className = `diff-status-badge ${badgeInfo.cls}`;
      badge.textContent = badgeInfo.label;

      const pathBtn = document.createElement("button");
      pathBtn.type = "button";
      pathBtn.className = "diff-file-path-btn";
      pathBtn.title = `${activeFile.path}（クリックしてパスをコピー）`;

      function renderPathBtnContent(copied) {
        pathBtn.replaceChildren();
        const slashIdx = activeFile.path.lastIndexOf("/");
        if (slashIdx > 0) {
          const dirEl = document.createElement("span");
          dirEl.className = "diff-file-path-dir";
          dirEl.textContent = activeFile.path.slice(0, slashIdx + 1);
          const nameEl = document.createElement("span");
          nameEl.className = "diff-file-path-name";
          nameEl.textContent = activeFile.path.slice(slashIdx + 1);
          pathBtn.append(dirEl, nameEl);
        } else {
          const nameEl = document.createElement("span");
          nameEl.className = "diff-file-path-name";
          nameEl.textContent = activeFile.path;
          pathBtn.append(nameEl);
        }
        if (copied) {
          const noteEl = document.createElement("span");
          noteEl.className = "diff-file-path-copied";
          noteEl.textContent = "（コピー済み）";
          pathBtn.append(noteEl);
        }
      }
      renderPathBtnContent(false);
      pathBtn.addEventListener("click", () => {
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard
            .writeText(activeFile.path)
            .then(() => {
              renderPathBtnContent(true);
              setTimeout(() => {
                renderPathBtnContent(false);
              }, 1200);
            })
            .catch(() => {});
        }
      });

      const stats = document.createElement("div");
      stats.className = "diff-file-bar-right";
      if (Number(activeFile.insertions || 0) > 0) {
        const a = document.createElement("span");
        a.className = "diff-stat-add";
        a.textContent = `+${activeFile.insertions}`;
        stats.append(a);
      }
      if (Number(activeFile.deletions || 0) > 0) {
        const d = document.createElement("span");
        d.className = "diff-stat-del";
        d.textContent = `-${activeFile.deletions}`;
        stats.append(d);
      }

      const copyBtn = document.createElement("button");
      copyBtn.type = "button";
      copyBtn.className = "diff-icon-btn";
      copyBtn.title = "差分をコピー";
      copyBtn.innerHTML = makeSvg(
        '<rect x="5" y="5" width="8.5" height="8.5" rx="1.5"/><path d="M11 5V3.5A1.5 1.5 0 0 0 9.5 2H3.5A1.5 1.5 0 0 0 2 3.5v6A1.5 1.5 0 0 0 3.5 11H5"/>',
        12
      );
      copyBtn.addEventListener("click", () => {
        const text = activeFile.patch || "";
        if (!text || !navigator.clipboard || !navigator.clipboard.writeText) {
          return;
        }
        navigator.clipboard
          .writeText(text)
          .then(() => {
            copyBtn.classList.add("is-active");
            copyBtn.title = "コピー済み";
            setTimeout(() => {
              copyBtn.classList.remove("is-active");
              copyBtn.title = "差分をコピー";
            }, 1200);
          })
          .catch(() => {});
      });
      stats.append(copyBtn);

      fileBar.append(badge, pathBtn, stats);

      const scrollBody = document.createElement("div");
      scrollBody.className = diffUiState.wordWrap
        ? "diff-code-scroll is-wrap"
        : "diff-code-scroll";
      const imageDiff = diffMediaMap[activeFile.path];
      if (imageDiff && (imageDiff.before_url || imageDiff.after_url)) {
        const wrap = document.createElement("div");
        wrap.className = "diff-image-wrap";
        if (imageDiff.before_url && imageDiff.after_url) {
          const widget = buildImageCompareWidget(
            {
              src: imageDiff.before_url,
              label: `HEAD · ${basename(activeFile.path)}`,
              tag: "Before (HEAD)",
              size: imageDiff.before_size || "",
            },
            {
              src: imageDiff.after_url,
              label: basename(activeFile.path),
              tag: "After (作業ツリー)",
              size: imageDiff.after_size || "",
            },
            { title: "画像差分", defaultMode: "slider" }
          );
          wrap.append(widget);
        } else {
          const isAdded = Boolean(imageDiff.after_url);
          const single = document.createElement("div");
          single.className = "diff-image-single";
          const img = document.createElement("img");
          const src = isAdded ? imageDiff.after_url : imageDiff.before_url;
          const size = isAdded ? imageDiff.after_size : imageDiff.before_size;
          img.src = src;
          img.alt = basename(activeFile.path);
          img.addEventListener("click", () => openLightbox(src, activeFile.path));
          const meta = document.createElement("div");
          meta.className = "diff-image-single-meta";
          meta.textContent = isAdded
            ? `追加された画像${size ? ` · ${size}` : ""}`
            : `削除された画像（HEAD）${size ? ` · ${size}` : ""}`;
          img.addEventListener("load", () => {
            meta.textContent = `${isAdded ? "追加された画像" : "削除された画像（HEAD）"} · ${img.naturalWidth}×${img.naturalHeight}${size ? ` · ${size}` : ""}`;
          });
          single.append(img, meta);
          wrap.append(single);
        }
        scrollBody.append(wrap);
      } else {
        const parsedRows = parsePatchRows(activeFile.patch);
        const useSplit = diffUiState.splitMode && !workbench.classList.contains("is-stacked");
        const table = useSplit
          ? buildSplitPatchTable(parsedRows, diffUiState.wordWrap, activeFile.path)
          : buildUnifiedPatchTable(parsedRows, diffUiState.wordWrap, activeFile.path);
        scrollBody.append(table);
      }

      codePane.append(fileBar, scrollBody);
    }

    function renderAll() {
      syncResponsiveMode();
      renderTopBar();
      renderTreePane();
      renderCodePane();
    }

    workbench.append(codePane, resizeHandle, treePane);
    container.append(topBar, workbench);
    renderAll();

    if (typeof ResizeObserver === "function") {
      if (container._diffResizeObserver) {
        container._diffResizeObserver.disconnect();
      }
      let lastStacked = workbench.classList.contains("is-stacked");
      const observer = new ResizeObserver(() => {
        syncResponsiveMode();
        const nowStacked = workbench.classList.contains("is-stacked");
        if (nowStacked !== lastStacked) {
          lastStacked = nowStacked;
          renderCodePane();
        }
      });
      observer.observe(container);
      container._diffResizeObserver = observer;
    }
    return true;
  }

  function renderFilePreview(payloadJson) {
    isChatModeActive = false;
    isCurrentChatBusy = false;
    syncScrollToBottomButton();
    const file = typeof payloadJson === "string" ? JSON.parse(payloadJson) : payloadJson;
    container.replaceChildren();
    container.className = "canvas diff-canvas";

    if (!file) {
      const empty = document.createElement("section");
      empty.className = "empty-state";
      const title = document.createElement("h2");
      title.className = "empty-title";
      title.textContent = "ファイルが選択されていません";
      const body = document.createElement("p");
      body.className = "empty-body";
      body.textContent = "右ペインの「+」から「ファイル」タブを開いてファイルを選択すると、ここにプレビューが表示されます。";
      empty.append(title, body);
      container.append(empty);
      return true;
    }

    const header = document.createElement("header");
    header.className = "file-preview-header";
    const name = document.createElement("span");
    name.className = "file-preview-name";
    name.textContent = file.name || basename(file.path);
    const meta = document.createElement("span");
    meta.className = "file-preview-meta";
    meta.textContent = file.size_label || "";
    header.append(name, meta);
    container.append(header);

    if (file.kind === "image" && file.media_url) {
      const stage = document.createElement("section");
      stage.className = "file-media-stage";
      const img = document.createElement("img");
      img.src = file.media_url;
      img.alt = file.name || "";
      img.addEventListener("click", () => openLightbox(file.media_url, file.name || ""));
      stage.append(img);
      container.append(stage);
      return true;
    }

    if (file.kind === "audio" && file.media_url) {
      const stage = document.createElement("section");
      stage.className = "file-media-stage";
      const audio = document.createElement("audio");
      audio.controls = true;
      audio.preload = "metadata";
      audio.src = file.media_url;
      stage.append(audio);
      container.append(stage);
      return true;
    }

    if (file.kind === "video" && file.media_url) {
      const stage = document.createElement("section");
      stage.className = "file-media-stage";
      const video = document.createElement("video");
      video.controls = true;
      video.playsInline = true;
      video.preload = "metadata";
      video.src = file.media_url;
      stage.append(video);
      container.append(stage);
      return true;
    }

    if (file.kind === "markdown") {
      const box = document.createElement("article");
      box.className = "file-markdown message-body";
      box.innerHTML = renderMarkdown(file.text || "", {});
      bindInteractiveBody(box);
      container.append(box);
      return true;
    }

    if (file.kind === "text") {
      const pre = document.createElement("div");
      pre.className = "file-code";
      const langSpec = detectHighlightLang(file.path || file.name);
      const lines = String(file.text || "").replace(/\r\n/g, "\n").split("\n");
      const hlStart = Number(file.highlight_line_start || 0);
      const hlEnd = Number(file.highlight_line_end || hlStart);
      let firstHighlightRow = null;
      for (let idx = 0; idx < lines.length; idx += 1) {
        const lineNo = idx + 1;
        const row = document.createElement("div");
        const isHighlighted = hlStart > 0 && lineNo >= hlStart && lineNo <= hlEnd;
        row.className = isHighlighted ? "file-code-row is-highlighted" : "file-code-row";
        row.dataset.line = String(lineNo);
        const num = document.createElement("span");
        num.className = "file-line-no";
        num.textContent = String(lineNo);
        const content = document.createElement("span");
        content.className = "file-line-text";
        content.innerHTML = renderHighlightedLine(lines[idx], langSpec, null, "");
        row.append(num, content);
        if (isHighlighted && !firstHighlightRow) {
          firstHighlightRow = row;
        }
        pre.append(row);
      }
      container.append(pre);
      if (firstHighlightRow) {
        requestAnimationFrame(() => {
          firstHighlightRow.scrollIntoView({ block: "center" });
        });
      }
      return true;
    }

    const binary = document.createElement("section");
    binary.className = "empty-state";
    const title = document.createElement("h2");
    title.className = "empty-title";
    title.textContent = "バイナリファイル";
    const body = document.createElement("p");
    body.className = "empty-body";
    body.textContent = file.path || "";
    binary.append(title, body);
    container.append(binary);
    return true;
  }

  window.kasugaiView = {
    setAppearance,
    renderThread,
    renderDiff,
    renderFilePreview,
  };
})();
