import AppKit
import Foundation
import WebKit

struct BrowserRectSnapshot: Codable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct BrowserElementSnapshot: Codable {
    let ref: String
    let tag: String
    let role: String
    let text: String
    let placeholder: String
    let value: String
    let draggable: Bool
    let disabled: Bool
    let rect: BrowserRectSnapshot
}

struct BrowserConsoleEntry: Codable {
    let level: String
    let message: String
}

struct BrowserSnapshotPayload: Codable {
    let url: String
    let title: String
    let viewportWidth: Double
    let viewportHeight: Double
    let elements: [BrowserElementSnapshot]
    let textSummary: String
    let consoleLogs: [BrowserConsoleEntry]

    enum CodingKeys: String, CodingKey {
        case url
        case title
        case viewportWidth = "viewport_width"
        case viewportHeight = "viewport_height"
        case elements
        case textSummary = "text_summary"
        case consoleLogs = "console_logs"
    }
}

struct BrowserActionResult {
    let ok: Bool
    let error: String?
    let detail: String?
}

final class LocalPreviewBrowserView: NSView, WKNavigationDelegate, WKUIDelegate, NSTextFieldDelegate
{
    var onDisplayTitleChanged: ((String) -> Void)?
    var onURLChanged: ((String) -> Void)?

    private static let externalProfileUUID = UUID(
        uuid: (
            0x7A, 0x9D, 0x2F, 0x5E, 0x14, 0xB8, 0x4E, 0x6C,
            0x9D, 0x2A, 0x31, 0xF4, 0xC8, 0xE7, 0xB2, 0x01
        )
    )

    static func clearExternalBrowserData(completion: (() -> Void)? = nil) {
        if #available(macOS 14.0, *) {
            let store = WKWebsiteDataStore(forIdentifier: externalProfileUUID)
            store.removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: .distantPast
            ) {
                DispatchQueue.main.async {
                    completion?()
                }
            }
        } else {
            completion?()
        }
    }

    private static let consoleCaptureUserScript = """
        (function() {
          if (window.__kasugaiConsoleInstalled) return;
          window.__kasugaiConsoleInstalled = true;
          const logs = [];
          const push = (level, parts) => {
            try {
              const msg = Array.from(parts).map(p => {
                if (typeof p === 'string') return p;
                if (p instanceof Error) return p.message || String(p);
                try { return JSON.stringify(p); } catch (_) { return String(p); }
              }).join(' ').slice(0, 600);
              logs.push({ level, message: msg });
              if (logs.length > 50) logs.shift();
            } catch (_) {}
          };
          window.__kasugaiConsole = logs;
          const origErr = console.error;
          console.error = function(...args) { push('error', args); return origErr.apply(this, args); };
          const origWarn = console.warn;
          console.warn = function(...args) { push('warn', args); return origWarn.apply(this, args); };
          window.addEventListener('error', (e) => push('error', [e.message || 'script error']));
          window.addEventListener('unhandledrejection', (e) => push('error', [e.reason || 'unhandled rejection']));
        })();
        """

    private static let agentVisualOverlayUserScript = """
        (function() {
          if (window.__kasugaiVisual) return;
          let root = null;
          let cursor = null;
          let svg = null;
          let trailLine = null;
          let trailStart = null;
          let hideTimer = null;

          const ensureOverlay = () => {
            if (root && root.isConnected) return root;
            if (!document.documentElement) return null;
            const styleId = '__kasugai_agent_style';
            if (!document.getElementById(styleId)) {
              const st = document.createElement('style');
              st.id = styleId;
              st.textContent = `
                @keyframes kasugaiRipple {
                  0% { transform: translate(-50%,-50%) scale(0.25); opacity: 0.92; }
                  100% { transform: translate(-50%,-50%) scale(2.4); opacity: 0; }
                }
                @keyframes kasugaiBoxFade {
                  0% { opacity: 0; transform: scale(0.98); }
                  15% { opacity: 1; transform: scale(1); }
                  80% { opacity: 1; }
                  100% { opacity: 0; }
                }
              `;
              (document.head || document.documentElement).appendChild(st);
            }
            root = document.createElement('div');
            root.id = '__kasugai_agent_overlay';
            root.style.cssText = 'position:fixed;inset:0;pointer-events:none;z-index:2147483647;overflow:hidden;';

            svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
            svg.setAttribute('width', '100%');
            svg.setAttribute('height', '100%');
            svg.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;pointer-events:none;';

            trailLine = document.createElementNS('http://www.w3.org/2000/svg', 'line');
            trailLine.setAttribute('stroke', '#60a5fa');
            trailLine.setAttribute('stroke-width', '2.5');
            trailLine.setAttribute('stroke-dasharray', '6 5');
            trailLine.setAttribute('stroke-linecap', 'round');
            trailLine.style.opacity = '0';

            trailStart = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
            trailStart.setAttribute('r', '5');
            trailStart.setAttribute('fill', '#60a5fa');
            trailStart.setAttribute('stroke', '#ffffff');
            trailStart.setAttribute('stroke-width', '2');
            trailStart.style.opacity = '0';

            svg.appendChild(trailLine);
            svg.appendChild(trailStart);
            root.appendChild(svg);

            cursor = document.createElement('div');
            cursor.style.cssText = 'position:fixed;left:0;top:0;width:24px;height:24px;pointer-events:none;opacity:0;transition:transform 75ms cubic-bezier(0.22,1,0.36,1),opacity 180ms ease;will-change:transform,opacity;filter:drop-shadow(0 2px 6px rgba(0,0,0,0.45));';
            cursor.innerHTML = '<svg width="24" height="24" viewBox="0 0 24 24" fill="none"><path d="M4 3.5L18.5 11.2L11.8 13.1L8.9 19.8L4 3.5Z" fill="#60a5fa" stroke="#ffffff" stroke-width="1.8" stroke-linejoin="round"/></svg>';
            root.appendChild(cursor);

            document.documentElement.appendChild(root);
            return root;
          };

          const bumpHideTimer = () => {
            if (hideTimer) clearTimeout(hideTimer);
            hideTimer = setTimeout(() => {
              if (cursor) cursor.style.opacity = '0';
            }, 2400);
          };

          window.__kasugaiVisual = {
            move(x, y, dragging) {
              if (!ensureOverlay()) return;
              cursor.style.transition = dragging
                ? 'transform 20ms linear, opacity 120ms ease'
                : 'transform 95ms cubic-bezier(0.22,1,0.36,1), opacity 160ms ease';
              cursor.style.opacity = '1';
              cursor.style.transform = 'translate3d(' + (x - 4) + 'px,' + (y - 3) + 'px,0)' + (dragging ? ' scale(0.92)' : '');
              bumpHideTimer();
            },
            ripple(x, y, color) {
              const host = ensureOverlay();
              if (!host) return;
              const ring = document.createElement('div');
              const c = color || '#60a5fa';
              ring.style.cssText = 'position:fixed;left:' + x + 'px;top:' + y + 'px;width:28px;height:28px;border-radius:9999px;border:2.5px solid ' + c + ';background:' + c + '26;pointer-events:none;animation:kasugaiRipple 480ms cubic-bezier(0.22,1,0.36,1) forwards;';
              host.appendChild(ring);
              setTimeout(() => ring.remove(), 520);
            },
            highlight(rect, label, color) {
              const host = ensureOverlay();
              if (!host || !rect) return;
              const c = color || '#60a5fa';
              const box = document.createElement('div');
              box.style.cssText = 'position:fixed;left:' + (rect.left - 2) + 'px;top:' + (rect.top - 2) + 'px;width:' + (rect.width + 4) + 'px;height:' + (rect.height + 4) + 'px;border-radius:8px;border:2px solid ' + c + ';background:' + c + '16;box-shadow:0 0 0 3px ' + c + '24;pointer-events:none;animation:kasugaiBoxFade 820ms ease forwards;';
              if (label) {
                const tag = document.createElement('div');
                tag.textContent = label;
                tag.style.cssText = 'position:absolute;left:0;top:-22px;padding:2px 7px;border-radius:6px;background:' + c + ';color:#ffffff;font:600 10px/14px -apple-system,BlinkMacSystemFont,sans-serif;white-space:nowrap;box-shadow:0 2px 6px rgba(0,0,0,0.28);';
                box.appendChild(tag);
              }
              host.appendChild(box);
              setTimeout(() => box.remove(), 860);
            },
            dragLine(x1, y1, x2, y2) {
              if (!ensureOverlay()) return;
              trailLine.setAttribute('x1', String(x1));
              trailLine.setAttribute('y1', String(y1));
              trailLine.setAttribute('x2', String(x2));
              trailLine.setAttribute('y2', String(y2));
              trailLine.style.opacity = '0.92';
              trailStart.setAttribute('cx', String(x1));
              trailStart.setAttribute('cy', String(y1));
              trailStart.style.opacity = '1';
            },
            clearDragLine() {
              if (!trailLine || !trailStart) return;
              trailLine.style.opacity = '0';
              trailStart.style.opacity = '0';
            }
          };
        })();
        """

    private static let loopbackRuleListIdentifier = "dev.soyukke.kasugai.loopback-preview.v2"
    private static let loopbackRuleListJSON = """
        [
          {
            "trigger": { "url-filter": ".*" },
            "action": { "type": "block" }
          },
          {
            "trigger": { "url-filter": "^https?://localhost(:[0-9]+)?(/.*)?$" },
            "action": { "type": "ignore-previous-rules" }
          },
          {
            "trigger": { "url-filter": "^https?://127\\\\.0\\\\.0\\\\.1(:[0-9]+)?(/.*)?$" },
            "action": { "type": "ignore-previous-rules" }
          },
          {
            "trigger": { "url-filter": "^https?://\\\\[::1\\\\](:[0-9]+)?(/.*)?$" },
            "action": { "type": "ignore-previous-rules" }
          },
          {
            "trigger": { "url-filter": "^data:" },
            "action": { "type": "ignore-previous-rules" }
          },
          {
            "trigger": { "url-filter": "^blob:" },
            "action": { "type": "ignore-previous-rules" }
          },
          {
            "trigger": { "url-filter": "^about:" },
            "action": { "type": "ignore-previous-rules" }
          }
        ]
        """

    private let rootSurface = KasugaiSurfaceView()
    private let toolbarDivider = KasugaiSurfaceView()
    private let backButton = KasugaiFlatButton()
    private let forwardButton = KasugaiFlatButton()
    private let reloadButton = KasugaiFlatButton()
    private let urlSurface = KasugaiSurfaceView()
    private let urlModeIcon = NSImageView()
    private let urlField = NSTextField()
    private let agentStatusBadge = KasugaiSurfaceView()
    private let agentStatusDot = KasugaiSurfaceView()
    private let agentStatusLabel = NSTextField(labelWithString: "操作中")
    private var agentStatusHideWorkItem: DispatchWorkItem?
    private let noticeBanner = KasugaiSurfaceView()
    private let noticeLabel = NSTextField(labelWithString: "")
    private let emptyOverlay = KasugaiSurfaceView()
    private let emptyTitleLabel = NSTextField(labelWithString: "ローカルブラウザ")
    private let emptySubtitleLabel = NSTextField(
        wrappingLabelWithString:
            "ローカル開発サーバー（localhost / 127.0.0.1）をプレビューできます。外部サイトへの通信は遮断されます。"
    )
    private let quickPortsStack = NSStackView()
    private var quickPortButtons: [KasugaiFlatButton] = []

    private var webView: WKWebView
    private var policy: KasugaiBrowserPolicy
    private var ruleListReady = false
    private var ruleListFailed = false
    private var pendingURL: URL?
    private var hasLoadedPage = false
    private var navigationWaiters: [(Result<Void, Error>) -> Void] = []
    private var pendingUploadFileURLs: [URL]?
    private var onPendingUploadConsumed: (() -> Void)?
    private var palette: KasugaiPalette = .kasugai
    private var theme = KasugaiThemeTokens.resolve(palette: .kasugai, isLight: false)

    var currentURLString: String {
        if let url = webView.url {
            let abs = url.absoluteString
            if !abs.isEmpty && abs != "about:blank" {
                return abs
            }
        }
        if let pendingURL {
            return pendingURL.absoluteString
        }
        return urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var currentTitleString: String {
        let t = webView.title ?? ""
        if !t.isEmpty {
            return t
        }
        if let url = webView.url {
            return Self.compactTitle(for: url)
        }
        return "ブラウザ"
    }

    init(frame frameRect: NSRect, policy: KasugaiBrowserPolicy = .loopbackOnly) {
        self.policy = policy
        self.webView = Self.buildWebView(allowExternal: policy.allowExternal)
        super.init(frame: frameRect)
        setup()
        configureRuleListForCurrentPolicy()
        syncPolicyPresentation()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private static func buildWebView(allowExternal: Bool) -> WKWebView {
        let config = WKWebViewConfiguration()
        if allowExternal {
            if #available(macOS 14.0, *) {
                config.websiteDataStore = WKWebsiteDataStore(forIdentifier: externalProfileUUID)
            } else {
                config.websiteDataStore = .nonPersistent()
            }
        } else {
            config.websiteDataStore = .nonPersistent()
        }
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        let consoleScript = WKUserScript(
            source: consoleCaptureUserScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        let visualScript = WKUserScript(
            source: agentVisualOverlayUserScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(consoleScript)
        config.userContentController.addUserScript(visualScript)
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }

    private func setup() {
        setContentHuggingPriority(.init(1), for: .horizontal)
        setContentCompressionResistancePriority(.init(1), for: .horizontal)
        rootSurface.translatesAutoresizingMaskIntoConstraints = false
        rootSurface.setContentHuggingPriority(.init(1), for: .horizontal)
        rootSurface.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        backButton.buttonStyle = .ghost
        backButton.horizontalPadding = 5
        backButton.configureSymbol("chevron.left", pointSize: 11.5, weight: .medium)
        backButton.toolTip = "戻る"
        backButton.target = self
        backButton.action = #selector(handleBack)
        backButton.isEnabled = false

        forwardButton.buttonStyle = .ghost
        forwardButton.horizontalPadding = 5
        forwardButton.configureSymbol("chevron.right", pointSize: 11.5, weight: .medium)
        forwardButton.toolTip = "進む"
        forwardButton.target = self
        forwardButton.action = #selector(handleForward)
        forwardButton.isEnabled = false

        reloadButton.buttonStyle = .ghost
        reloadButton.horizontalPadding = 5
        reloadButton.configureSymbol("arrow.clockwise", pointSize: 11.5, weight: .medium)
        reloadButton.toolTip = "再読み込み"
        reloadButton.target = self
        reloadButton.action = #selector(handleReload)

        urlSurface.cornerRadius = 7
        urlSurface.strokeWidth = 1
        urlSurface.translatesAutoresizingMaskIntoConstraints = false
        urlSurface.setContentHuggingPriority(.init(1), for: .horizontal)
        urlSurface.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        urlModeIcon.imageScaling = .scaleProportionallyDown
        urlModeIcon.translatesAutoresizingMaskIntoConstraints = false

        urlField.isBordered = false
        urlField.drawsBackground = false
        urlField.focusRingType = .none
        urlField.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        urlField.placeholderString = "localhost:3000"
        urlField.lineBreakMode = .byTruncatingTail
        urlField.setContentHuggingPriority(.init(1), for: .horizontal)
        urlField.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        urlField.delegate = self
        urlField.translatesAutoresizingMaskIntoConstraints = false
        urlSurface.addSubview(urlModeIcon)
        urlSurface.addSubview(urlField)

        agentStatusBadge.cornerRadius = 6
        agentStatusBadge.strokeWidth = 1
        agentStatusBadge.isHidden = true
        agentStatusBadge.translatesAutoresizingMaskIntoConstraints = false
        agentStatusBadge.setContentHuggingPriority(.required, for: .horizontal)
        agentStatusBadge.setContentCompressionResistancePriority(.required, for: .horizontal)

        agentStatusDot.cornerRadius = 3
        agentStatusDot.translatesAutoresizingMaskIntoConstraints = false

        agentStatusLabel.font = .systemFont(ofSize: 10.5, weight: .semibold)
        agentStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        agentStatusLabel.setContentHuggingPriority(.required, for: .horizontal)

        let badgeRow = NSStackView(views: [agentStatusDot, agentStatusLabel])
        badgeRow.orientation = .horizontal
        badgeRow.alignment = .centerY
        badgeRow.spacing = 5
        badgeRow.translatesAutoresizingMaskIntoConstraints = false
        agentStatusBadge.addSubview(badgeRow)
        NSLayoutConstraint.activate([
            agentStatusBadge.heightAnchor.constraint(equalToConstant: 22),
            agentStatusDot.widthAnchor.constraint(equalToConstant: 6),
            agentStatusDot.heightAnchor.constraint(equalToConstant: 6),
            badgeRow.leadingAnchor.constraint(equalTo: agentStatusBadge.leadingAnchor, constant: 7),
            badgeRow.trailingAnchor.constraint(
                equalTo: agentStatusBadge.trailingAnchor, constant: -7),
            badgeRow.centerYAnchor.constraint(equalTo: agentStatusBadge.centerYAnchor),
        ])

        let toolbar = NSStackView(views: [
            backButton,
            forwardButton,
            urlSurface,
            agentStatusBadge,
            reloadButton,
        ])
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 4
        toolbar.setHuggingPriority(.init(1), for: .horizontal)
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        toolbarDivider.translatesAutoresizingMaskIntoConstraints = false

        noticeBanner.cornerRadius = 7
        noticeBanner.strokeWidth = 1
        noticeBanner.isHidden = true
        noticeBanner.translatesAutoresizingMaskIntoConstraints = false
        noticeLabel.font = .systemFont(ofSize: 11, weight: .medium)
        noticeLabel.lineBreakMode = .byTruncatingTail
        noticeLabel.setContentHuggingPriority(.init(1), for: .horizontal)
        noticeLabel.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        noticeLabel.translatesAutoresizingMaskIntoConstraints = false
        noticeBanner.addSubview(noticeLabel)

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isHidden = true

        emptyOverlay.translatesAutoresizingMaskIntoConstraints = false
        emptyTitleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        emptyTitleLabel.alignment = .center
        emptyTitleLabel.setContentHuggingPriority(.init(1), for: .horizontal)
        emptyTitleLabel.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        emptySubtitleLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        emptySubtitleLabel.alignment = .center
        emptySubtitleLabel.setContentHuggingPriority(.init(1), for: .horizontal)
        emptySubtitleLabel.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        quickPortsStack.orientation = .horizontal
        quickPortsStack.alignment = .centerY
        quickPortsStack.spacing = 6
        for port in [3000, 5173, 8080, 4321] {
            let btn = KasugaiFlatButton()
            btn.buttonStyle = .pill
            btn.horizontalPadding = 8
            btn.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            btn.title = ":\(port)"
            btn.tag = port
            btn.toolTip = "http://localhost:\(port) を開く"
            btn.target = self
            btn.action = #selector(handleQuickPort(_:))
            quickPortButtons.append(btn)
            quickPortsStack.addArrangedSubview(btn)
        }

        let emptyStack = NSStackView(views: [
            emptyTitleLabel,
            emptySubtitleLabel,
            quickPortsStack,
        ])
        emptyStack.orientation = .vertical
        emptyStack.alignment = .centerX
        emptyStack.spacing = 10
        emptyStack.translatesAutoresizingMaskIntoConstraints = false
        emptyOverlay.addSubview(emptyStack)

        rootSurface.addSubview(toolbar)
        rootSurface.addSubview(toolbarDivider)
        rootSurface.addSubview(noticeBanner)
        rootSurface.addSubview(webView)
        rootSurface.addSubview(emptyOverlay)
        addSubview(rootSurface)

        NSLayoutConstraint.activate([
            rootSurface.topAnchor.constraint(equalTo: topAnchor),
            rootSurface.bottomAnchor.constraint(equalTo: bottomAnchor),
            rootSurface.leadingAnchor.constraint(equalTo: leadingAnchor),
            rootSurface.trailingAnchor.constraint(equalTo: trailingAnchor),

            toolbar.topAnchor.constraint(equalTo: rootSurface.topAnchor, constant: 6),
            toolbar.leadingAnchor.constraint(equalTo: rootSurface.leadingAnchor, constant: 8),
            toolbar.trailingAnchor.constraint(equalTo: rootSurface.trailingAnchor, constant: -8),
            toolbar.heightAnchor.constraint(equalToConstant: 28),

            urlSurface.heightAnchor.constraint(equalToConstant: 26),
            urlModeIcon.leadingAnchor.constraint(equalTo: urlSurface.leadingAnchor, constant: 7),
            urlModeIcon.centerYAnchor.constraint(equalTo: urlSurface.centerYAnchor),
            urlModeIcon.widthAnchor.constraint(equalToConstant: 12),
            urlModeIcon.heightAnchor.constraint(equalToConstant: 12),
            urlField.leadingAnchor.constraint(equalTo: urlModeIcon.trailingAnchor, constant: 5),
            urlField.trailingAnchor.constraint(equalTo: urlSurface.trailingAnchor, constant: -8),
            urlField.centerYAnchor.constraint(equalTo: urlSurface.centerYAnchor),

            toolbarDivider.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 6),
            toolbarDivider.leadingAnchor.constraint(equalTo: rootSurface.leadingAnchor),
            toolbarDivider.trailingAnchor.constraint(equalTo: rootSurface.trailingAnchor),
            toolbarDivider.heightAnchor.constraint(equalToConstant: 1),

            noticeBanner.topAnchor.constraint(equalTo: toolbarDivider.bottomAnchor, constant: 8),
            noticeBanner.leadingAnchor.constraint(equalTo: rootSurface.leadingAnchor, constant: 10),
            noticeBanner.trailingAnchor.constraint(
                equalTo: rootSurface.trailingAnchor, constant: -10),
            noticeLabel.topAnchor.constraint(equalTo: noticeBanner.topAnchor, constant: 6),
            noticeLabel.bottomAnchor.constraint(equalTo: noticeBanner.bottomAnchor, constant: -6),
            noticeLabel.leadingAnchor.constraint(equalTo: noticeBanner.leadingAnchor, constant: 10),
            noticeLabel.trailingAnchor.constraint(
                equalTo: noticeBanner.trailingAnchor, constant: -10),

            webView.topAnchor.constraint(equalTo: toolbarDivider.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: rootSurface.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: rootSurface.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: rootSurface.bottomAnchor),

            emptyOverlay.topAnchor.constraint(equalTo: toolbarDivider.bottomAnchor),
            emptyOverlay.leadingAnchor.constraint(equalTo: rootSurface.leadingAnchor),
            emptyOverlay.trailingAnchor.constraint(equalTo: rootSurface.trailingAnchor),
            emptyOverlay.bottomAnchor.constraint(equalTo: rootSurface.bottomAnchor),

            emptyStack.centerXAnchor.constraint(equalTo: emptyOverlay.centerXAnchor),
            emptyStack.centerYAnchor.constraint(equalTo: emptyOverlay.centerYAnchor, constant: -12),
            emptyStack.leadingAnchor.constraint(
                greaterThanOrEqualTo: emptyOverlay.leadingAnchor, constant: 20),
            emptyStack.trailingAnchor.constraint(
                lessThanOrEqualTo: emptyOverlay.trailingAnchor, constant: -20),
        ])

        rootSurface.onAppearanceChanged = { [weak self] in
            self?.applyTheme()
        }
        applyTheme()
    }

    private func configureRuleListForCurrentPolicy() {
        if policy.allowExternal {
            ruleListFailed = false
            ruleListReady = true
            if let pending = pendingURL {
                pendingURL = nil
                loadValidatedURL(pending)
            }
            return
        }
        ruleListReady = false
        ruleListFailed = false
        installLoopbackRuleList()
    }

    func update(policy nextPolicy: KasugaiBrowserPolicy) {
        let externalToggled = policy.allowExternal != nextPolicy.allowExternal
        policy = nextPolicy
        if externalToggled {
            let previousURL = webView.url
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
            webView.stopLoading()
            webView.removeFromSuperview()

            let replacement = Self.buildWebView(allowExternal: policy.allowExternal)
            replacement.navigationDelegate = self
            replacement.uiDelegate = self
            replacement.isHidden = !hasLoadedPage
            rootSurface.addSubview(replacement, positioned: .below, relativeTo: emptyOverlay)
            NSLayoutConstraint.activate([
                replacement.topAnchor.constraint(equalTo: toolbarDivider.bottomAnchor),
                replacement.leadingAnchor.constraint(equalTo: rootSurface.leadingAnchor),
                replacement.trailingAnchor.constraint(equalTo: rootSurface.trailingAnchor),
                replacement.bottomAnchor.constraint(equalTo: rootSurface.bottomAnchor),
            ])
            webView = replacement
            configureRuleListForCurrentPolicy()
            if let previousURL, policy.isAllowedURL(previousURL) {
                loadValidatedURL(previousURL)
            } else if hasLoadedPage {
                hasLoadedPage = false
                webView.isHidden = true
                emptyOverlay.isHidden = false
                urlField.stringValue = ""
                onDisplayTitleChanged?("ブラウザ")
                onURLChanged?("")
            }
        }
        syncPolicyPresentation()
    }

    private func syncPolicyPresentation() {
        let cfg = NSImage.SymbolConfiguration(pointSize: 10.5, weight: .medium)
        if policy.allowExternal {
            urlModeIcon.image = NSImage(
                systemSymbolName: "globe",
                accessibilityDescription: "外部通信許可"
            )?.withSymbolConfiguration(cfg)
            urlModeIcon.contentTintColor = theme.accent
            let allowDomains = policy.rules.filter { $0.action == .allow }.map(\.domain)
            let blockDomains = policy.rules.filter { $0.action == .block }.map(\.domain)
            if policy.allowAllExternal {
                urlModeIcon.toolTip =
                    blockDomains.isEmpty
                    ? "外部通信許可（すべての外部サイト）"
                    : "外部通信許可（すべて許可・ブロック \(blockDomains.count) 件）"
                emptySubtitleLabel.stringValue =
                    blockDomains.isEmpty
                    ? "ローカル開発サーバーおよび外部サイト（https/http）を表示できます。"
                    : "ローカルおよび外部サイト（ブロック: \(blockDomains.joined(separator: ", ")) を除く）を表示できます。"
            } else {
                urlModeIcon.toolTip =
                    allowDomains.isEmpty
                    ? "外部通信許可（許可ルール未設定）"
                    : "外部通信許可（\(allowDomains.joined(separator: ", "))）"
                emptySubtitleLabel.stringValue =
                    allowDomains.isEmpty
                    ? "設定（⌘,）で「すべての外部サイトを許可する」か許可ドメインを追加してください。"
                    : "ローカルおよび許可ドメイン（\(allowDomains.joined(separator: ", "))）を表示できます。"
            }
            urlField.placeholderString = "URL を入力（例: https://partner.steamgames.com）"
            emptyTitleLabel.stringValue = "内蔵ブラウザ"
        } else {
            urlModeIcon.image = NSImage(
                systemSymbolName: "lock.shield",
                accessibilityDescription: "ローカル限定"
            )?.withSymbolConfiguration(cfg)
            urlModeIcon.contentTintColor = theme.textMuted
            urlModeIcon.toolTip = "ローカル限定（設定で外部通信を許可可能）"
            urlField.placeholderString = "localhost:3000"
            emptyTitleLabel.stringValue = "ローカルブラウザ"
            emptySubtitleLabel.stringValue =
                "ローカル開発サーバー（localhost / 127.0.0.1）をプレビューできます。外部サイトは設定（⌘,）で許可できます。"
        }
    }

    private func installLoopbackRuleList() {
        guard let store = WKContentRuleListStore.default() else {
            ruleListFailed = true
            return
        }
        let targetWebView = webView
        store.compileContentRuleList(
            forIdentifier: Self.loopbackRuleListIdentifier,
            encodedContentRuleList: Self.loopbackRuleListJSON
        ) { [weak self] list, _ in
            DispatchQueue.main.async {
                guard let self, self.webView === targetWebView, !self.policy.allowExternal else {
                    return
                }
                guard let list else {
                    self.ruleListFailed = true
                    self.showNotice("通信遮断ルールの初期化に失敗したため読み込みを停止しました")
                    self.resolveNavigationWaiters(
                        .failure(
                            NSError(
                                domain: "KasugaiBrowser",
                                code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "content rule list failed"]
                            )
                        )
                    )
                    return
                }
                self.webView.configuration.userContentController.add(list)
                self.ruleListReady = true
                if let pending = self.pendingURL {
                    self.pendingURL = nil
                    self.loadValidatedURL(pending)
                }
            }
        }
    }

    func update(palette: KasugaiPalette) {
        self.palette = palette
        applyTheme()
    }

    func applyTheme() {
        theme = KasugaiThemeTokens.resolve(palette: palette, appearance: effectiveAppearance)
        rootSurface.fillColor = theme.canvasBg
        toolbarDivider.fillColor = theme.borderSubtle
        backButton.apply(theme: theme)
        forwardButton.apply(theme: theme)
        reloadButton.apply(theme: theme)
        urlSurface.fillColor = theme.surfaceBg
        urlSurface.strokeColor = theme.borderSubtle
        urlField.textColor = theme.textPrimary
        agentStatusBadge.fillColor = theme.accent.withAlphaComponent(0.14)
        agentStatusBadge.strokeColor = theme.accent.withAlphaComponent(0.38)
        agentStatusDot.fillColor = theme.accent
        agentStatusLabel.textColor = theme.accent
        noticeBanner.fillColor = theme.warning.withAlphaComponent(0.12)
        noticeBanner.strokeColor = theme.warning.withAlphaComponent(0.32)
        noticeLabel.textColor = theme.warning
        emptyOverlay.fillColor = theme.canvasBg
        emptyTitleLabel.textColor = theme.textPrimary
        emptySubtitleLabel.textColor = theme.textMuted
        for btn in quickPortButtons {
            btn.apply(theme: theme)
        }
        syncPolicyPresentation()
    }

    private func blockedURLMessage() -> String {
        if !policy.allowExternal {
            return "外部通信がオフです。設定（⌘,）で「内蔵ブラウザの外部通信を許可する」をオンにしてください"
        }
        return "許可ドメインに含まれていないため読み込みを停止しました"
    }

    func navigate(input raw: String) {
        guard let url = policy.normalizeURL(raw) else {
            showNotice(blockedURLMessage())
            return
        }
        hideNotice()
        urlField.stringValue = url.absoluteString
        onDisplayTitleChanged?(Self.compactTitle(for: url))
        onURLChanged?(url.absoluteString)
        loadValidatedURL(url)
    }

    func restorePersistedURL(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        guard let url = policy.normalizeURL(trimmed) else {
            urlField.stringValue = trimmed
            showNotice(blockedURLMessage())
            return
        }
        hideNotice()
        urlField.stringValue = url.absoluteString
        onDisplayTitleChanged?(Self.compactTitle(for: url))
        loadValidatedURL(url)
    }

    func reloadCurrentPage() {
        if hasLoadedPage {
            webView.reload()
        } else if !urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            navigate(input: urlField.stringValue)
        }
    }

    private func loadValidatedURL(_ url: URL) {
        if !policy.allowExternal {
            if ruleListFailed {
                showNotice("通信遮断ルールの初期化に失敗したため読み込みできません")
                return
            }
            if !ruleListReady {
                pendingURL = url
                return
            }
        }
        hasLoadedPage = true
        emptyOverlay.isHidden = true
        webView.isHidden = false
        webView.load(URLRequest(url: url))
    }

    private func showNotice(_ message: String) {
        noticeLabel.stringValue = message
        noticeBanner.isHidden = false
        rootSurface.addSubview(noticeBanner, positioned: .above, relativeTo: nil)
    }

    private func hideNotice() {
        noticeBanner.isHidden = true
    }

    private func syncNavButtons() {
        backButton.isEnabled = webView.canGoBack
        forwardButton.isEnabled = webView.canGoForward
        if let url = webView.url, policy.isAllowedURL(url) {
            let next = url.absoluteString
            if urlField.stringValue != next {
                urlField.stringValue = next
                onURLChanged?(next)
            }
            onDisplayTitleChanged?(Self.compactTitle(for: url))
        }
    }

    static func compactTitle(for url: URL) -> String {
        let host = url.host ?? "localhost"
        if let port = url.port {
            return "\(host):\(port)"
        }
        return host
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector)
        -> Bool
    {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            navigate(input: urlField.stringValue)
            return true
        }
        return false
    }

    @objc private func handleBack() {
        if webView.canGoBack {
            webView.goBack()
        }
    }

    @objc private func handleForward() {
        if webView.canGoForward {
            webView.goForward()
        }
    }

    @objc private func handleReload() {
        reloadCurrentPage()
    }

    @objc private func handleQuickPort(_ sender: NSButton) {
        navigate(input: "http://localhost:\(sender.tag)")
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if !policy.allowExternal {
            guard !ruleListFailed, ruleListReady else {
                decisionHandler(.cancel)
                return
            }
        }
        let url = navigationAction.request.url
        if url?.absoluteString == "about:blank" || policy.isAllowedURL(url) {
            decisionHandler(.allow)
        } else {
            showNotice(blockedURLMessage())
            decisionHandler(.cancel)
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil,
            let url = navigationAction.request.url,
            policy.isAllowedURL(url)
        {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        if let urls = pendingUploadFileURLs {
            pendingUploadFileURLs = nil
            let callback = onPendingUploadConsumed
            onPendingUploadConsumed = nil
            completionHandler(parameters.allowsMultipleSelection ? urls : Array(urls.prefix(1)))
            callback?()
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        if let win = window {
            panel.beginSheetModal(for: win) { response in
                completionHandler(response == .OK ? panel.urls : nil)
            }
        } else {
            completionHandler(panel.runModal() == .OK ? panel.urls : nil)
        }
    }

    private func resolveNavigationWaiters(_ result: Result<Void, Error>) {
        guard !navigationWaiters.isEmpty else {
            return
        }
        let waiters = navigationWaiters
        navigationWaiters.removeAll()
        for waiter in waiters {
            waiter(result)
        }
    }

    private func indicateAgentActivity(_ label: String) {
        agentStatusHideWorkItem?.cancel()
        agentStatusLabel.stringValue = label
        agentStatusBadge.isHidden = false
        let work = DispatchWorkItem { [weak self] in
            self?.agentStatusBadge.isHidden = true
        }
        agentStatusHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    func navigateAndWait(
        input raw: String,
        timeoutMs: Int64 = 10000,
        completion: @escaping (BrowserActionResult) -> Void
    ) {
        indicateAgentActivity("移動中")
        guard let url = policy.normalizeURL(raw) else {
            showNotice(blockedURLMessage())
            completion(
                BrowserActionResult(
                    ok: false,
                    error: policy.allowExternal
                        ? "URL is not in allowed domains"
                        : "external browser access is disabled in settings",
                    detail: nil
                )
            )
            return
        }
        if !policy.allowExternal && ruleListFailed {
            completion(
                BrowserActionResult(
                    ok: false,
                    error: "content rule list initialization failed",
                    detail: nil
                )
            )
            return
        }
        hideNotice()
        urlField.stringValue = url.absoluteString
        onDisplayTitleChanged?(Self.compactTitle(for: url))
        onURLChanged?(url.absoluteString)

        var completed = false
        let finish: (BrowserActionResult) -> Void = { result in
            guard !completed else {
                return
            }
            completed = true
            completion(result)
        }

        navigationWaiters.append { result in
            switch result {
            case .success:
                finish(BrowserActionResult(ok: true, error: nil, detail: self.currentURLString))
            case .failure(let error):
                finish(
                    BrowserActionResult(
                        ok: false,
                        error: error.localizedDescription,
                        detail: nil
                    )
                )
            }
        }

        let clampedMs = max(500, min(timeoutMs, 30000))
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(Int(clampedMs))) {
            finish(
                BrowserActionResult(
                    ok: false,
                    error: "navigation timed out",
                    detail: self.currentURLString
                )
            )
        }

        loadValidatedURL(url)
    }

    func captureSnapshot(
        maxElements: Int = 120,
        completion: @escaping (Result<BrowserSnapshotPayload, Error>) -> Void
    ) {
        let clampedMax = max(10, min(maxElements, 300))
        let script = """
            const limit = maxElements;
            const selector = 'a,button,input,textarea,select,[role="button"],[role="link"],[role="textbox"],[role="checkbox"],[role="radio"],[role="tab"],[role="menuitem"],[role="option"],[draggable="true"],[contenteditable="true"],[data-droppable],[onclick]';
            const nodes = Array.from(document.querySelectorAll(selector));
            const elements = [];
            let refIdx = 0;
            for (const el of nodes) {
              if (elements.length >= limit) break;
              if (el.closest && el.closest('#__kasugai_agent_overlay')) continue;
              const style = window.getComputedStyle(el);
              if (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0') continue;
              const r = el.getBoundingClientRect();
              if (r.width <= 0 || r.height <= 0) continue;
              refIdx += 1;
              const ref = 'e' + refIdx;
              el.setAttribute('data-kasugai-ref', ref);
              const tag = el.tagName.toLowerCase();
              const role = el.getAttribute('role') || (tag === 'a' ? 'link' : (tag === 'button' ? 'button' : ''));
              const rawText = (el.innerText || el.getAttribute('aria-label') || el.getAttribute('title') || '').replace(/\\s+/g, ' ').trim();
              const placeholder = el.getAttribute('placeholder') || '';
              let value = '';
              if ('value' in el && typeof el.value === 'string') {
                value = el.type === 'password' ? '***' : el.value.slice(0, 120);
              }
              elements.push({
                ref,
                tag,
                role,
                text: rawText.slice(0, 120),
                placeholder: placeholder.slice(0, 80),
                value,
                draggable: Boolean(el.draggable || el.getAttribute('draggable') === 'true'),
                disabled: Boolean(el.disabled || el.getAttribute('aria-disabled') === 'true'),
                rect: {
                  x: Math.round(r.left * 10) / 10,
                  y: Math.round(r.top * 10) / 10,
                  width: Math.round(r.width * 10) / 10,
                  height: Math.round(r.height * 10) / 10
                }
              });
            }
            const bodyText = (document.body ? (document.body.innerText || '') : '').replace(/\\s+/g, ' ').trim().slice(0, 2000);
            const logs = Array.isArray(window.__kasugaiConsole) ? window.__kasugaiConsole.slice(-30) : [];
            return JSON.stringify({
              url: window.location.href,
              title: document.title || '',
              viewport_width: window.innerWidth,
              viewport_height: window.innerHeight,
              elements,
              text_summary: bodyText,
              console_logs: logs
            });
            """
        webView.callAsyncJavaScript(
            script,
            arguments: ["maxElements": clampedMax],
            in: nil,
            in: .page
        ) { result in
            switch result {
            case .failure(let error):
                completion(.failure(error))
            case .success(let value):
                guard let jsonStr = value as? String,
                    let data = jsonStr.data(using: .utf8),
                    let payload = try? JSONDecoder().decode(BrowserSnapshotPayload.self, from: data)
                else {
                    completion(
                        .failure(
                            NSError(
                                domain: "KasugaiBrowser",
                                code: 2,
                                userInfo: [NSLocalizedDescriptionKey: "failed to decode snapshot"]
                            )
                        )
                    )
                    return
                }
                completion(.success(payload))
            }
        }
    }

    func captureScreenshot(
        outputPath: String? = nil,
        completion: @escaping (Result<(path: String, width: Int, height: Int), Error>) -> Void
    ) {
        indicateAgentActivity("撮影中")
        let targetURL: URL
        if let outputPath, !outputPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            targetURL = URL(fileURLWithPath: outputPath)
        } else {
            let dir = KasugaiRuntimePaths.dataDirectory()
                .appendingPathComponent("attachments", isDirectory: true)
            let shortId = String(UUID().uuidString.prefix(8)).lowercased()
            targetURL = dir.appendingPathComponent("browser-\(shortId).png")
        }

        let writeImage: (NSImage) -> Void = { image in
            guard let tiff = image.tiffRepresentation,
                let rep = NSBitmapImageRep(data: tiff),
                let png = rep.representation(using: .png, properties: [:])
            else {
                completion(
                    .failure(
                        NSError(
                            domain: "KasugaiBrowser",
                            code: 3,
                            userInfo: [NSLocalizedDescriptionKey: "failed to encode screenshot PNG"]
                        )
                    )
                )
                return
            }
            do {
                let fm = FileManager.default
                try fm.createDirectory(
                    at: targetURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
                try png.write(to: targetURL, options: .atomic)
                try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: targetURL.path)
                completion(.success((targetURL.path, rep.pixelsWide, rep.pixelsHigh)))
            } catch {
                completion(.failure(error))
            }
        }

        webView.takeSnapshot(with: nil) { [weak self] image, error in
            if let image {
                writeImage(image)
                return
            }
            guard let self,
                self.webView.bounds.width > 0,
                self.webView.bounds.height > 0,
                let rep = self.webView.bitmapImageRepForCachingDisplay(in: self.webView.bounds)
            else {
                completion(
                    .failure(
                        error
                            ?? NSError(
                                domain: "KasugaiBrowser",
                                code: 4,
                                userInfo: [NSLocalizedDescriptionKey: "screenshot unavailable"]
                            )
                    )
                )
                return
            }
            self.webView.cacheDisplay(in: self.webView.bounds, to: rep)
            let fallback = NSImage(size: self.webView.bounds.size)
            fallback.addRepresentation(rep)
            writeImage(fallback)
        }
    }

    func performClick(
        ref: String?,
        selector: String?,
        x: Double?,
        y: Double?,
        doubleClick: Bool,
        completion: @escaping (BrowserActionResult) -> Void
    ) {
        indicateAgentActivity(doubleClick ? "ダブルクリック" : "クリック")
        let script = """
            const resolveEl = () => {
              if (ref) {
                const byRef = document.querySelector('[data-kasugai-ref="' + CSS.escape(ref) + '"]');
                if (byRef) return byRef;
              }
              if (selector) {
                const bySel = document.querySelector(selector);
                if (bySel) return bySel;
              }
              if (typeof x === 'number' && typeof y === 'number') {
                return document.elementFromPoint(x, y);
              }
              return null;
            };
            const el = resolveEl();
            if (!el) return JSON.stringify({ ok: false, error: 'target element not found' });
            if (el.scrollIntoView) el.scrollIntoView({ block: 'center', inline: 'center', behavior: 'instant' });
            const r = el.getBoundingClientRect();
            const cx = typeof x === 'number' ? x : (r.left + r.width / 2);
            const cy = typeof y === 'number' ? y : (r.top + r.height / 2);
            if (window.__kasugaiVisual) {
              window.__kasugaiVisual.move(cx, cy, false);
              window.__kasugaiVisual.highlight(r, doubleClick ? 'ダブルクリック' : 'クリック', '#60a5fa');
              window.__kasugaiVisual.ripple(cx, cy, '#60a5fa');
            }
            const common = { bubbles: true, cancelable: true, view: window, clientX: cx, clientY: cy, button: 0 };
            el.dispatchEvent(new PointerEvent('pointerover', { ...common, pointerId: 1, pointerType: 'mouse' }));
            el.dispatchEvent(new MouseEvent('mouseover', common));
            el.dispatchEvent(new PointerEvent('pointerdown', { ...common, pointerId: 1, pointerType: 'mouse', buttons: 1 }));
            el.dispatchEvent(new MouseEvent('mousedown', { ...common, buttons: 1 }));
            if (typeof el.focus === 'function') el.focus();
            el.dispatchEvent(new PointerEvent('pointerup', { ...common, pointerId: 1, pointerType: 'mouse', buttons: 0 }));
            el.dispatchEvent(new MouseEvent('mouseup', { ...common, buttons: 0 }));
            if (typeof el.click === 'function') {
              el.click();
            } else {
              el.dispatchEvent(new MouseEvent('click', common));
            }
            if (doubleClick) {
              el.dispatchEvent(new MouseEvent('dblclick', { ...common, detail: 2 }));
            }
            return JSON.stringify({ ok: true, detail: el.tagName.toLowerCase() + '@' + Math.round(cx) + ',' + Math.round(cy) });
            """
        runActionScript(
            script,
            arguments: [
                "ref": ref ?? NSNull(),
                "selector": selector ?? NSNull(),
                "x": x ?? NSNull(),
                "y": y ?? NSNull(),
                "doubleClick": doubleClick,
            ],
            completion: completion
        )
    }

    func performType(
        ref: String?,
        selector: String?,
        text: String,
        clear: Bool,
        submit: Bool,
        completion: @escaping (BrowserActionResult) -> Void
    ) {
        indicateAgentActivity("入力中")
        let script = """
            let el = null;
            if (ref) el = document.querySelector('[data-kasugai-ref="' + CSS.escape(ref) + '"]');
            if (!el && selector) el = document.querySelector(selector);
            if (!el) el = document.activeElement;
            if (!el || el === document.body) return JSON.stringify({ ok: false, error: 'editable target not found' });
            if (el.scrollIntoView) el.scrollIntoView({ block: 'center', inline: 'center', behavior: 'instant' });
            const r = el.getBoundingClientRect();
            if (window.__kasugaiVisual) {
              window.__kasugaiVisual.move(r.left + r.width / 2, r.top + r.height / 2, false);
              window.__kasugaiVisual.highlight(r, '入力', '#a78bfa');
            }
            if (typeof el.focus === 'function') el.focus();
            if (el.isContentEditable) {
              el.textContent = clear ? text : ((el.textContent || '') + text);
              el.dispatchEvent(new InputEvent('input', { bubbles: true, data: text, inputType: 'insertText' }));
            } else if ('value' in el) {
              const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
              const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
              const nextValue = clear ? text : ((el.value || '') + text);
              if (setter) setter.call(el, nextValue); else el.value = nextValue;
              el.dispatchEvent(new Event('input', { bubbles: true }));
              el.dispatchEvent(new Event('change', { bubbles: true }));
            } else {
              return JSON.stringify({ ok: false, error: 'target element is not editable' });
            }
            if (submit) {
              el.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, cancelable: true, key: 'Enter', code: 'Enter' }));
              el.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true, cancelable: true, key: 'Enter', code: 'Enter' }));
              if (el.form && typeof el.form.requestSubmit === 'function') el.form.requestSubmit();
            }
            return JSON.stringify({ ok: true, detail: el.tagName.toLowerCase() });
            """
        runActionScript(
            script,
            arguments: [
                "ref": ref ?? NSNull(),
                "selector": selector ?? NSNull(),
                "text": text,
                "clear": clear,
                "submit": submit,
            ],
            completion: completion
        )
    }

    func performPress(
        key: String,
        modifiers: [String],
        completion: @escaping (BrowserActionResult) -> Void
    ) {
        let script = """
            const target = document.activeElement || document.body;
            if (!target) return JSON.stringify({ ok: false, error: 'no active element' });
            const mods = new Set(modifiers || []);
            const opts = {
              bubbles: true,
              cancelable: true,
              key,
              code: key.length === 1 ? ('Key' + key.toUpperCase()) : key,
              ctrlKey: mods.has('Control') || mods.has('ctrl'),
              metaKey: mods.has('Meta') || mods.has('cmd') || mods.has('command'),
              shiftKey: mods.has('Shift') || mods.has('shift'),
              altKey: mods.has('Alt') || mods.has('option') || mods.has('alt')
            };
            target.dispatchEvent(new KeyboardEvent('keydown', opts));
            if (key.length === 1 || key === 'Enter') {
              target.dispatchEvent(new KeyboardEvent('keypress', opts));
            }
            target.dispatchEvent(new KeyboardEvent('keyup', opts));
            return JSON.stringify({ ok: true, detail: key });
            """
        runActionScript(
            script,
            arguments: ["key": key, "modifiers": modifiers],
            completion: completion
        )
    }

    func performDrag(
        fromRef: String?,
        fromSelector: String?,
        fromX: Double?,
        fromY: Double?,
        toRef: String?,
        toSelector: String?,
        toX: Double?,
        toY: Double?,
        steps: Int,
        mode: String,
        completion: @escaping (BrowserActionResult) -> Void
    ) {
        indicateAgentActivity("ドラッグ中")
        let clampedSteps = max(2, min(steps, 40))
        let stepDelayMs = clampedSteps >= 8 ? 22 : 8
        let script = """
            const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));
            const resolvePoint = (ref, selector, x, y) => {
              let el = null;
              if (ref) el = document.querySelector('[data-kasugai-ref="' + CSS.escape(ref) + '"]');
              if (!el && selector) el = document.querySelector(selector);
              if (el) {
                if (el.scrollIntoView) el.scrollIntoView({ block: 'center', inline: 'center', behavior: 'instant' });
                const r = el.getBoundingClientRect();
                const cx = typeof x === 'number' ? x : (r.left + r.width / 2);
                const cy = typeof y === 'number' ? y : (r.top + r.height / 2);
                return { el, x: cx, y: cy, rect: r };
              }
              if (typeof x === 'number' && typeof y === 'number') {
                return { el: document.elementFromPoint(x, y), x, y, rect: null };
              }
              return null;
            };
            const src = resolvePoint(fromRef, fromSelector, fromX, fromY);
            if (!src || !src.el) return JSON.stringify({ ok: false, error: 'drag source not found' });
            const dst = resolvePoint(toRef, toSelector, toX, toY);
            if (!dst) return JSON.stringify({ ok: false, error: 'drag target not found' });

            const draggableEl = src.el.closest ? src.el.closest('[draggable="true"]') : null;
            const useHtml5 = mode === 'html5' || (mode !== 'pointer' && Boolean(draggableEl));
            const dragOrigin = draggableEl || src.el;
            const dt = useHtml5 ? new DataTransfer() : null;

            const firePointer = (target, type, x, y, buttons) => {
              if (!target) return;
              target.dispatchEvent(new PointerEvent(type, {
                bubbles: true, cancelable: true, composed: true, view: window,
                pointerId: 1, pointerType: 'mouse', isPrimary: true,
                clientX: x, clientY: y, button: 0, buttons
              }));
            };
            const fireMouse = (target, type, x, y, buttons) => {
              if (!target) return;
              target.dispatchEvent(new MouseEvent(type, {
                bubbles: true, cancelable: true, composed: true, view: window,
                clientX: x, clientY: y, button: 0, buttons
              }));
            };
            const fireDrag = (target, type, x, y) => {
              if (!target || !dt) return;
              target.dispatchEvent(new DragEvent(type, {
                bubbles: true, cancelable: true, composed: true, view: window,
                clientX: x, clientY: y, dataTransfer: dt
              }));
            };

            if (window.__kasugaiVisual) {
              window.__kasugaiVisual.move(src.x, src.y, true);
              if (src.rect) window.__kasugaiVisual.highlight(src.rect, 'ドラッグ', '#60a5fa');
              window.__kasugaiVisual.ripple(src.x, src.y, '#60a5fa');
              window.__kasugaiVisual.dragLine(src.x, src.y, src.x, src.y);
            }

            firePointer(src.el, 'pointerover', src.x, src.y, 0);
            fireMouse(src.el, 'mouseover', src.x, src.y, 0);
            firePointer(src.el, 'pointerdown', src.x, src.y, 1);
            fireMouse(src.el, 'mousedown', src.x, src.y, 1);
            if (useHtml5) {
              fireDrag(dragOrigin, 'dragstart', src.x, src.y);
            }

            let lastOver = src.el;
            for (let i = 1; i <= steps; i++) {
              const t = i / steps;
              const cx = src.x + (dst.x - src.x) * t;
              const cy = src.y + (dst.y - src.y) * t;
              if (window.__kasugaiVisual) {
                window.__kasugaiVisual.move(cx, cy, true);
                window.__kasugaiVisual.dragLine(src.x, src.y, cx, cy);
              }
              const under = document.elementFromPoint(cx, cy) || dst.el || document.body;
              firePointer(under, 'pointermove', cx, cy, 1);
              fireMouse(under, 'mousemove', cx, cy, 1);
              if (useHtml5) {
                if (under !== lastOver) {
                  fireDrag(lastOver, 'dragleave', cx, cy);
                  fireDrag(under, 'dragenter', cx, cy);
                  lastOver = under;
                }
                fireDrag(under, 'dragover', cx, cy);
              }
              await sleep(stepDelayMs);
            }

            const dropTarget = dst.el || document.elementFromPoint(dst.x, dst.y) || document.body;
            if (useHtml5) {
              if (dropTarget !== lastOver) {
                fireDrag(dropTarget, 'dragenter', dst.x, dst.y);
              }
              fireDrag(dropTarget, 'dragover', dst.x, dst.y);
              fireDrag(dropTarget, 'drop', dst.x, dst.y);
              fireDrag(dragOrigin, 'dragend', dst.x, dst.y);
            }
            firePointer(dropTarget, 'pointerup', dst.x, dst.y, 0);
            fireMouse(dropTarget, 'mouseup', dst.x, dst.y, 0);
            if (window.__kasugaiVisual) {
              window.__kasugaiVisual.clearDragLine();
              window.__kasugaiVisual.move(dst.x, dst.y, false);
              if (dst.rect) window.__kasugaiVisual.highlight(dst.rect, 'ドロップ', '#4ade80');
              window.__kasugaiVisual.ripple(dst.x, dst.y, '#4ade80');
            }
            return JSON.stringify({
              ok: true,
              detail: (useHtml5 ? 'html5+pointer' : 'pointer') + ' (' + Math.round(src.x) + ',' + Math.round(src.y) + ')->(' + Math.round(dst.x) + ',' + Math.round(dst.y) + ')'
            });
            """
        runActionScript(
            script,
            arguments: [
                "fromRef": fromRef ?? NSNull(),
                "fromSelector": fromSelector ?? NSNull(),
                "fromX": fromX ?? NSNull(),
                "fromY": fromY ?? NSNull(),
                "toRef": toRef ?? NSNull(),
                "toSelector": toSelector ?? NSNull(),
                "toX": toX ?? NSNull(),
                "toY": toY ?? NSNull(),
                "steps": clampedSteps,
                "stepDelayMs": stepDelayMs,
                "mode": mode,
            ],
            completion: completion
        )
    }

    func performDropFiles(
        ref: String?,
        selector: String?,
        x: Double?,
        y: Double?,
        filePaths: [String],
        completion: @escaping (BrowserActionResult) -> Void
    ) {
        indicateAgentActivity("アップロード中")
        guard !filePaths.isEmpty else {
            completion(BrowserActionResult(ok: false, error: "file_paths is empty", detail: nil))
            return
        }
        let fm = FileManager.default
        var validURLs: [URL] = []
        for path in filePaths.prefix(20) {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
                completion(
                    BrowserActionResult(
                        ok: false,
                        error: "file not found: \(path)",
                        detail: nil
                    )
                )
                return
            }
            validURLs.append(URL(fileURLWithPath: path))
        }

        let probeScript = """
            let el = null;
            if (ref) el = document.querySelector('[data-kasugai-ref="' + CSS.escape(ref) + '"]');
            if (!el && selector) el = document.querySelector(selector);
            if (!el && typeof x === 'number' && typeof y === 'number') el = document.elementFromPoint(x, y);
            if (!el) return JSON.stringify({ ok: false, error: 'drop target not found' });
            const fileInput = (el.tagName === 'INPUT' && el.type === 'file')
              ? el
              : (el.querySelector ? el.querySelector('input[type="file"]') : null);
            const r = el.getBoundingClientRect();
            const cx = typeof x === 'number' ? x : (r.left + r.width / 2);
            const cy = typeof y === 'number' ? y : (r.top + r.height / 2);
            if (window.__kasugaiVisual) {
              window.__kasugaiVisual.move(cx, cy, false);
              window.__kasugaiVisual.highlight(r, firstFileName, '#4ade80');
              window.__kasugaiVisual.ripple(cx, cy, '#4ade80');
            }
            if (fileInput) {
              fileInput.click();
              return JSON.stringify({ ok: true, detail: 'native-click' });
            }
            return JSON.stringify({ ok: true, detail: 'js-dropzone' });
            """

        var completed = false
        let finish: (BrowserActionResult) -> Void = { res in
            guard !completed else {
                return
            }
            completed = true
            completion(res)
        }

        var consumedNativePanel = false
        pendingUploadFileURLs = validURLs
        onPendingUploadConsumed = {
            consumedNativePanel = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                finish(
                    BrowserActionResult(
                        ok: true,
                        error: nil,
                        detail: "native-input-files:\(validURLs.count)"
                    )
                )
            }
        }

        runActionScript(
            probeScript,
            arguments: [
                "ref": ref ?? NSNull(),
                "selector": selector ?? NSNull(),
                "x": x ?? NSNull(),
                "y": y ?? NSNull(),
                "firstFileName": validURLs[0].lastPathComponent,
            ]
        ) { [weak self] probeRes in
            guard let self else {
                return
            }
            guard probeRes.ok else {
                self.pendingUploadFileURLs = nil
                self.onPendingUploadConsumed = nil
                finish(probeRes)
                return
            }
            if probeRes.detail == "native-click" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    guard let self, !completed else {
                        return
                    }
                    if consumedNativePanel {
                        return
                    }
                    self.pendingUploadFileURLs = nil
                    self.onPendingUploadConsumed = nil
                    self.performDropFilesViaDataTransfer(
                        ref: ref,
                        selector: selector,
                        x: x,
                        y: y,
                        fileURLs: validURLs,
                        completion: finish
                    )
                }
                return
            }
            self.pendingUploadFileURLs = nil
            self.onPendingUploadConsumed = nil
            self.performDropFilesViaDataTransfer(
                ref: ref,
                selector: selector,
                x: x,
                y: y,
                fileURLs: validURLs,
                completion: finish
            )
        }
    }

    private func performDropFilesViaDataTransfer(
        ref: String?,
        selector: String?,
        x: Double?,
        y: Double?,
        fileURLs: [URL],
        completion: @escaping (BrowserActionResult) -> Void
    ) {
        var encodedFiles: [[String: String]] = []
        let maxBytes = 64 * 1024 * 1024
        for url in fileURLs.prefix(10) {
            guard let data = try? Data(contentsOf: url), data.count <= maxBytes else {
                completion(
                    BrowserActionResult(
                        ok: false,
                        error:
                            "dropzone without <input type=file> exceeds 64MB limit: \(url.lastPathComponent)",
                        detail: nil
                    )
                )
                return
            }
            encodedFiles.append([
                "name": url.lastPathComponent,
                "mime": Self.mimeType(forPathExtension: url.pathExtension),
                "base64": data.base64EncodedString(),
            ])
        }

        let script = """
            let el = null;
            if (ref) el = document.querySelector('[data-kasugai-ref="' + CSS.escape(ref) + '"]');
            if (!el && selector) el = document.querySelector(selector);
            if (!el && typeof x === 'number' && typeof y === 'number') el = document.elementFromPoint(x, y);
            if (!el) return JSON.stringify({ ok: false, error: 'drop target not found' });
            const dt = new DataTransfer();
            for (const item of files) {
              const bin = atob(item.base64);
              const bytes = new Uint8Array(bin.length);
              for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
              dt.items.add(new File([bytes], item.name, { type: item.mime }));
            }
            const fileInput = (el.tagName === 'INPUT' && el.type === 'file')
              ? el
              : (el.querySelector ? el.querySelector('input[type="file"]') : null);
            if (fileInput) {
              fileInput.files = dt.files;
              fileInput.dispatchEvent(new Event('input', { bubbles: true }));
              fileInput.dispatchEvent(new Event('change', { bubbles: true }));
              return JSON.stringify({ ok: true, detail: 'input-files:' + dt.files.length });
            }
            const r = el.getBoundingClientRect();
            const cx = typeof x === 'number' ? x : (r.left + r.width / 2);
            const cy = typeof y === 'number' ? y : (r.top + r.height / 2);
            const opts = { bubbles: true, cancelable: true, composed: true, view: window, clientX: cx, clientY: cy, dataTransfer: dt };
            el.dispatchEvent(new DragEvent('dragenter', opts));
            el.dispatchEvent(new DragEvent('dragover', opts));
            el.dispatchEvent(new DragEvent('drop', opts));
            return JSON.stringify({ ok: true, detail: 'drop-files:' + dt.files.length });
            """
        runActionScript(
            script,
            arguments: [
                "ref": ref ?? NSNull(),
                "selector": selector ?? NSNull(),
                "x": x ?? NSNull(),
                "y": y ?? NSNull(),
                "files": encodedFiles,
            ],
            completion: completion
        )
    }

    func performScroll(
        ref: String?,
        selector: String?,
        deltaX: Double,
        deltaY: Double,
        completion: @escaping (BrowserActionResult) -> Void
    ) {
        let script = """
            let el = null;
            if (ref) el = document.querySelector('[data-kasugai-ref="' + CSS.escape(ref) + '"]');
            if (!el && selector) el = document.querySelector(selector);
            if (el) {
              el.scrollBy({ left: deltaX, top: deltaY, behavior: 'instant' });
              return JSON.stringify({ ok: true, detail: Math.round(el.scrollLeft) + ',' + Math.round(el.scrollTop) });
            }
            window.scrollBy({ left: deltaX, top: deltaY, behavior: 'instant' });
            return JSON.stringify({ ok: true, detail: Math.round(window.scrollX) + ',' + Math.round(window.scrollY) });
            """
        runActionScript(
            script,
            arguments: [
                "ref": ref ?? NSNull(),
                "selector": selector ?? NSNull(),
                "deltaX": deltaX,
                "deltaY": deltaY,
            ],
            completion: completion
        )
    }

    func evaluateExpression(
        _ expression: String,
        completion: @escaping (BrowserActionResult) -> Void
    ) {
        let script = """
            const fn = new Function('return (async () => { return (' + expr + '); })();');
            const val = await fn();
            if (val === undefined) return JSON.stringify({ ok: true, detail: 'undefined' });
            try {
              return JSON.stringify({ ok: true, detail: JSON.stringify(val) });
            } catch (_) {
              return JSON.stringify({ ok: true, detail: String(val) });
            }
            """
        runActionScript(script, arguments: ["expr": expression], completion: completion)
    }

    private func runActionScript(
        _ script: String,
        arguments: [String: Any],
        completion: @escaping (BrowserActionResult) -> Void
    ) {
        webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { result in
            switch result {
            case .failure(let error):
                completion(
                    BrowserActionResult(
                        ok: false,
                        error: error.localizedDescription,
                        detail: nil
                    )
                )
            case .success(let value):
                guard let jsonStr = value as? String,
                    let data = jsonStr.data(using: .utf8),
                    let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    completion(
                        BrowserActionResult(
                            ok: false,
                            error: "unexpected script response",
                            detail: nil
                        )
                    )
                    return
                }
                let ok = obj["ok"] as? Bool ?? false
                let err = obj["error"] as? String
                let detail = obj["detail"] as? String
                completion(BrowserActionResult(ok: ok, error: err, detail: detail))
            }
        }
    }

    private static func mimeType(forPathExtension ext: String) -> String {
        switch ext.lowercased() {
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "webp":
            return "image/webp"
        case "gif":
            return "image/gif"
        case "svg":
            return "image/svg+xml"
        case "pdf":
            return "application/pdf"
        case "json":
            return "application/json"
        case "txt", "md", "csv":
            return "text/plain"
        default:
            return "application/octet-stream"
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        syncNavButtons()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hideNotice()
        syncNavButtons()
        resolveNavigationWaiters(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        syncNavButtons()
        showNotice("ローカルサーバーに接続できませんでした（\(urlField.stringValue)）")
        resolveNavigationWaiters(.failure(error))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        syncNavButtons()
        let nsError = error as NSError
        if nsError.code == NSURLErrorCancelled {
            return
        }
        showNotice("ローカルサーバーに接続できませんでした（\(urlField.stringValue)）")
        resolveNavigationWaiters(.failure(error))
    }

    static func isAllowedLoopbackURL(_ url: URL?) -> Bool {
        guard let url,
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = url.host?.lowercased()
        else {
            return false
        }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    static func normalizeLoopbackURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let candidate: String
        if trimmed.allSatisfy(\.isNumber), let port = Int(trimmed), (1...65535).contains(port) {
            candidate = "http://localhost:\(port)"
        } else if trimmed.hasPrefix(":"),
            let port = Int(trimmed.dropFirst()),
            (1...65535).contains(port)
        {
            candidate = "http://localhost:\(port)"
        } else if trimmed.contains("://") {
            candidate = trimmed
        } else {
            candidate = "http://\(trimmed)"
        }
        guard let url = URL(string: candidate), isAllowedLoopbackURL(url) else {
            return nil
        }
        return url
    }

    static func runSelfTests() -> Bool {
        guard
            let u1 = normalizeLoopbackURL("3000"),
            u1.absoluteString == "http://localhost:3000",
            let u2 = normalizeLoopbackURL(":5173"),
            u2.absoluteString == "http://localhost:5173",
            let u3 = normalizeLoopbackURL("localhost:8080/api"),
            u3.absoluteString == "http://localhost:8080/api",
            let u4 = normalizeLoopbackURL("http://127.0.0.1:4000"),
            isAllowedLoopbackURL(u4),
            let u5 = normalizeLoopbackURL("http://[::1]:3000"),
            isAllowedLoopbackURL(u5),
            normalizeLoopbackURL("https://example.com") == nil,
            normalizeLoopbackURL("http://127.0.0.1.evil.com") == nil,
            normalizeLoopbackURL("http://localhost.attacker.test:3000") == nil,
            normalizeLoopbackURL("file:///etc/passwd") == nil,
            normalizeLoopbackURL("javascript:alert(1)") == nil
        else {
            return false
        }
        guard
            let data = loopbackRuleListJSON.data(using: .utf8),
            let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            parsed.count == 7,
            let store = WKContentRuleListStore.default()
        else {
            return false
        }
        var compiled = false
        var finished = false
        store.compileContentRuleList(
            forIdentifier: "\(loopbackRuleListIdentifier).selftest",
            encodedContentRuleList: loopbackRuleListJSON
        ) { list, error in
            compiled = list != nil && error == nil
            finished = true
        }
        let deadline = Date().addingTimeInterval(3.0)
        while !finished && Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.01, false)
        }
        return compiled
    }
}
