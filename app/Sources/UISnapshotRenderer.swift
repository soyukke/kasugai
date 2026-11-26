import AppKit
import Foundation

enum KasugaiUISnapshotRenderer {
    static func runCLI(arguments: [String]) -> Int32 {
        let outDirPath: String
        if let idx = arguments.firstIndex(of: "--out"), idx + 1 < arguments.count {
            outDirPath = arguments[idx + 1]
        } else if let first = arguments.first, !first.hasPrefix("-") {
            outDirPath = first
        } else {
            outDirPath =
                FileManager.default.temporaryDirectory
                .appendingPathComponent("kasugai-ui-snapshots", isDirectory: true).path
        }

        let outDir = URL(fileURLWithPath: outDirPath, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        } catch {
            fputs("ui-snapshot: failed to create output directory: \(error)\n", stderr)
            return EXIT_FAILURE
        }

        _ = NSApplication.shared
        var written: [String] = []

        let sampleProviders = [
            KasugaiProviderSpec(
                id: "claude_code",
                displayName: "Claude Code",
                transport: "claude_stream_json",
                defaultModel: "default",
                ready: true,
                launchSpec: ""
            ),
            KasugaiProviderSpec(
                id: "codex",
                displayName: "Codex",
                transport: "codex_app_server",
                defaultModel: "default",
                ready: true,
                launchSpec: ""
            ),
            KasugaiProviderSpec(
                id: "opencode_acp",
                displayName: "OpenCode",
                transport: "acp_stdio",
                defaultModel: "default",
                ready: true,
                launchSpec: ""
            ),
            KasugaiProviderSpec(
                id: "antigravity_acp",
                displayName: "Antigravity (ACP)",
                transport: "acp_stdio",
                defaultModel: "default",
                ready: true,
                launchSpec: ""
            ),
        ]

        let variants: [(name: String, provider: String, model: String, isLight: Bool)] = [
            ("model-picker-claude-dark", "claude_code", "claude-opus-5-5", false),
            ("model-picker-codex-dark", "codex", "gpt-5.4", false),
            ("model-picker-antigravity-dark", "antigravity_acp", "gemini-4-neon-high", false),
            ("model-picker-claude-light", "claude_code", "claude-opus-5-5", true),
        ]

        for variant in variants {
            let appearance = NSAppearance(named: variant.isLight ? .aqua : .darkAqua)
            let theme = KasugaiThemeTokens.resolve(palette: .kasugai, isLight: variant.isLight)
            let picker = ModelPickerPopoverViewController(
                providers: sampleProviders,
                activeProviderId: variant.provider,
                activeModelId: variant.model,
                activeEffort: "high",
                discoveredModels: [],
                theme: theme
            )
            let size = ModelPickerPopoverViewController.fixedPopoverSize
            if let path = renderOffscreen(
                view: picker.view,
                size: size,
                appearance: appearance,
                to: outDir.appendingPathComponent("\(variant.name).png")
            ) {
                written.append(path)
            }
        }

        let sampleAttachImg = NSImage(size: NSSize(width: 48, height: 48), flipped: false) { rect in
            NSColor.systemIndigo.setFill()
            rect.fill()
            NSColor.white.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 12, dy: 12)).fill()
            return true
        }
        let sampleImgURL = outDir.appendingPathComponent("image-sample.png")
        if let tiff = sampleAttachImg.tiffRepresentation,
            let bmp = NSBitmapImageRep(data: tiff),
            let png = bmp.representation(using: .png, properties: [:])
        {
            try? png.write(to: sampleImgURL, options: .atomic)
        }

        for isLight in [false, true] {
            let suffix = isLight ? "light" : "dark"
            let appearance = NSAppearance(named: isLight ? .aqua : .darkAqua)
            let composer = ComposerView(frame: NSRect(x: 0, y: 0, width: 760, height: 120))
            composer.appearance = appearance
            composer.applyTheme()
            composer.restoreDraft(
                KasugaiComposerDraft(
                    text: "⌘V で貼り付けた画像と送信ボタンの表示確認",
                    attachments: [sampleImgURL.path]
                )
            )
            composer.layoutSubtreeIfNeeded()
            let fitH = max(112, ceil(composer.fittingSize.height))
            if let path = renderOffscreen(
                view: composer,
                size: NSSize(width: 760, height: fitH),
                appearance: appearance,
                to: outDir.appendingPathComponent("composer-\(suffix).png")
            ) {
                written.append(path)
            }
            if !isLight {
                composer.setTurnActiveForSnapshot(true)
                composer.layoutSubtreeIfNeeded()
                if let busyPath = renderOffscreen(
                    view: composer,
                    size: NSSize(width: 760, height: fitH),
                    appearance: appearance,
                    to: outDir.appendingPathComponent("composer-busy-dark.png")
                ) {
                    written.append(busyPath)
                }
            }
        }

        let core = KasugaiCore(projectName: "kasugai", projectPath: "/workspace/kasugai")
        if let core {
            let sampleDiff = GitDiffReport(
                directory: "/workspace/kasugai",
                branch: "main",
                isGitRepo: true,
                filesChanged: 4,
                insertions: 128,
                deletions: 34,
                statusLines: [],
                unifiedDiff: "",
                files: []
            )
            let windowModes: [(name: String, isLight: Bool, openRightPane: Bool, size: NSSize)] = [
                ("main-window-card-dark", false, false, NSSize(width: 1180, height: 480)),
                ("main-window-card-light", true, false, NSSize(width: 1180, height: 480)),
                ("main-window-split-dark", false, true, NSSize(width: 1180, height: 420)),
            ]
            for mode in windowModes {
                let appearance = NSAppearance(named: mode.isLight ? .aqua : .darkAqua)
                var settings = KasugaiAppSettings.defaultValue
                settings.appearance = mode.isLight ? .light : .dark
                let mainVC = MainSplitViewController(
                    core: core,
                    settings: settings,
                    storePath: outDir.appendingPathComponent("snap-events.jsonl").path,
                    draftStorePath: outDir.appendingPathComponent("snap-drafts.json").path
                )
                let window = NSWindow(
                    contentRect: NSRect(origin: .zero, size: mode.size),
                    styleMask: [
                        .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView,
                    ],
                    backing: .buffered,
                    defer: false
                )
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.appearance = appearance
                window.contentViewController = mainVC
                window.setContentSize(mode.size)
                mainVC.applySettings(settings)
                mainVC.updateDiffPreviewForSnapshot(sampleDiff)
                if mode.openRightPane {
                    mainVC.openDiffTab(focusFile: nil)
                }
                window.layoutIfNeeded()
                mainVC.view.layoutSubtreeIfNeeded()
                mainVC.view.displayIfNeeded()
                if let contentView = window.contentView,
                    let rep = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds)
                {
                    contentView.cacheDisplay(in: contentView.bounds, to: rep)
                    if let png = rep.representation(using: .png, properties: [:]) {
                        let url = outDir.appendingPathComponent("\(mode.name).png")
                        if (try? png.write(to: url, options: .atomic)) != nil {
                            written.append(url.path)
                        }
                    }
                }
            }

            let settingsSizes: [(name: String, size: NSSize, openRight: Bool, scrollBottom: Bool)] =
                [
                    ("settings-wide-dark", NSSize(width: 1180, height: 820), false, false),
                    ("settings-lower-dark", NSSize(width: 1180, height: 820), false, true),
                    ("settings-split-dark", NSSize(width: 1180, height: 820), true, false),
                ]
            for item in settingsSizes {
                let appearance = NSAppearance(named: .darkAqua)
                var settings = KasugaiAppSettings.defaultValue
                settings.appearance = .dark
                settings.allowExternalBrowser = true
                settings.externalBrowserAllowAll = true
                settings.externalBrowserRules = [
                    KasugaiBrowserDomainRule(action: .allow, domain: "partner.steamgames.com"),
                    KasugaiBrowserDomainRule(action: .block, domain: "ads.example.com"),
                ]
                let mainVC = MainSplitViewController(
                    core: core,
                    settings: settings,
                    storePath: outDir.appendingPathComponent("snap-events.jsonl").path,
                    draftStorePath: outDir.appendingPathComponent("snap-drafts.json").path
                )
                let window = NSWindow(
                    contentRect: NSRect(origin: .zero, size: item.size),
                    styleMask: [
                        .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView,
                    ],
                    backing: .buffered,
                    defer: false
                )
                window.titleVisibility = .hidden
                window.titlebarAppearsTransparent = true
                window.appearance = appearance
                window.contentViewController = mainVC
                window.setContentSize(item.size)
                mainVC.applySettings(settings)
                if item.openRight {
                    mainVC.openDiffTab(focusFile: nil)
                }
                mainVC.showSettingsScreen(true)
                window.layoutIfNeeded()
                mainVC.view.layoutSubtreeIfNeeded()
                if item.scrollBottom {
                    mainVC.scrollSettingsToBottomForSnapshot()
                }
                mainVC.view.displayIfNeeded()
                if let contentView = window.contentView,
                    let rep = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds)
                {
                    contentView.cacheDisplay(in: contentView.bounds, to: rep)
                    if let png = rep.representation(using: .png, properties: [:]) {
                        let url = outDir.appendingPathComponent("\(item.name).png")
                        if (try? png.write(to: url, options: .atomic)) != nil {
                            written.append(url.path)
                        }
                    }
                }
            }

            let rlSize = NSSize(width: 1180, height: 760)
            let rlAppearance = NSAppearance(named: .darkAqua)
            var rlSettings = KasugaiAppSettings.defaultValue
            rlSettings.appearance = .dark
            let rlMainVC = MainSplitViewController(
                core: core,
                settings: rlSettings,
                storePath: outDir.appendingPathComponent("snap-events.jsonl").path,
                draftStorePath: outDir.appendingPathComponent("snap-drafts.json").path
            )
            let rlWindow = NSWindow(
                contentRect: NSRect(origin: .zero, size: rlSize),
                styleMask: [
                    .titled, .closable, .miniaturizable, .resizable, .fullSizeContentView,
                ],
                backing: .buffered,
                defer: false
            )
            rlWindow.titleVisibility = .hidden
            rlWindow.titlebarAppearsTransparent = true
            rlWindow.appearance = rlAppearance
            rlWindow.contentViewController = rlMainVC
            rlWindow.setContentSize(rlSize)
            rlMainVC.applySettings(rlSettings)
            rlMainVC.showRateLimitsScreen(true)
            rlWindow.layoutIfNeeded()
            rlMainVC.view.layoutSubtreeIfNeeded()
            rlMainVC.view.displayIfNeeded()
            if let contentView = rlWindow.contentView,
                let rep = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds)
            {
                contentView.cacheDisplay(in: contentView.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) {
                    let url = outDir.appendingPathComponent("rate-limits-dark.png")
                    if (try? png.write(to: url, options: .atomic)) != nil {
                        written.append(url.path)
                    }
                }
            }
        }

        let factorySize = NSSize(width: 820, height: 640)
        let darkApp = NSAppearance(named: .darkAqua)
        let gameBp =
            FactoryBlueprint.builtInDefaults().first(where: { $0.id == "web-game" })
            ?? FactoryBlueprint.builtInDefaults()[0]
        let sampleRunning = FactoryRunRecord(
            id: "snap-running",
            parentRunId: nil,
            childRunIds: ["bgm_factory": "snap-child-bgm"],
            blueprintId: gameBp.id,
            blueprintName: gameBp.name,
            title: "終電を逃した会社員が 1 ボタンで…",
            prompt: "終電を逃した会社員が 1 ボタンで障害物を跳び越える即死アクションゲーム。8bit 調の合成効果音と 1 画面 1 行の短い演出。",
            slug: "demo-game",
            status: .running,
            currentStageId: "review",
            stages: gameBp.stages,
            loops: gameBp.loops,
            workerProvider: "opencode_acp",
            workerModel: "opencode-go/glm-5.3",
            criticProvider: "antigravity_acp",
            criticModel: "gemini-4-neon",
            maxIterations: 3,
            minReviewScore: 80,
            harnessRules: gameBp.harnessRules,
            publishTargetLabel: gameBp.publishTargetLabel,
            createdAtMs: 1_795_670_000_000,
            updatedAtMs: 1_795_670_092_000,
            startedAtMs: 1_795_670_000_000,
            finishedAtMs: 1_795_670_092_000,
            inputTokens: 11_400,
            outputTokens: 3_200,
            tokensEstimated: true,
            iterations: [
                FactoryIterationRecord(
                    index: 1,
                    durationSeconds: 26.8,
                    outcome: "retry",
                    badgeText: "62 点",
                    activeLoopIds: ["review_retry"],
                    loopNote: "第 1 周 レビュー差し戻し（62 点）→ 再実装",
                    stuckDetected: false,
                    panels: [
                        FactoryGatePanel(
                            id: "gate1",
                            title: "3. 自動検査（0 トークン）",
                            statusText: "合格",
                            tone: .success,
                            metrics: [
                                FactoryMetricItem(label: "ビルド", value: "1.4 秒", tone: .neutral),
                                FactoryMetricItem(label: "WASM", value: "184 KB", tone: .neutral),
                                FactoryMetricItem(label: "CDP エラー", value: "0 件", tone: .success),
                            ],
                            summary: "自動プレイ: 生存 8.2 秒 / ゲームオーバー到達",
                            bullets: [],
                            imagePath: nil,
                            threadId: 11,
                            threadLabel: "1. 実装スレッドを表示"
                        ),
                        FactoryGatePanel(
                            id: "gate2",
                            title: "4. 独立レビュー（隔離）",
                            statusText: "62 点",
                            tone: .warning,
                            metrics: [],
                            summary: "動作は安定しているが、障害物の視認性と手応えが不足しています。",
                            bullets: [
                                "背景と障害物のコントラストが弱く初見で識別しにくい",
                                "ジャンプ着地時の演出と効果音のメリハリを追加してください",
                            ],
                            imagePath: nil,
                            threadId: 12,
                            threadLabel: "4. レビュースレッドを表示"
                        ),
                    ]
                ),
                FactoryIterationRecord(
                    index: 2,
                    durationSeconds: 18.4,
                    outcome: "running",
                    badgeText: nil,
                    activeLoopIds: [],
                    loopNote: nil,
                    stuckDetected: false,
                    panels: [
                        FactoryGatePanel(
                            id: "gate1",
                            title: "3. 自動検査（0 トークン）",
                            statusText: "合格",
                            tone: .success,
                            metrics: [
                                FactoryMetricItem(label: "ビルド", value: "1.2 秒", tone: .neutral),
                                FactoryMetricItem(label: "WASM", value: "192 KB", tone: .neutral),
                                FactoryMetricItem(label: "CDP エラー", value: "0 件", tone: .success),
                            ],
                            summary: "自動プレイ: 生存 14.6 秒 / スコア更新＆リトライ確認済み",
                            bullets: [],
                            imagePath: nil,
                            threadId: 13,
                            threadLabel: "1. 実装スレッドを表示"
                        ),
                        FactoryGatePanel(
                            id: "gate2",
                            title: "4. 独立レビュー（隔離）",
                            statusText: "審査中…",
                            tone: .accent,
                            metrics: [],
                            summary: "3. 自動検査を通過したため、実装履歴のない別セッションで採点しています。",
                            bullets: [],
                            imagePath: nil,
                            threadId: 14,
                            threadLabel: "4. レビュースレッドを表示"
                        ),
                    ]
                ),
            ],
            localPreviewURL: nil,
            stagingPreviewURL: nil,
            productionURL: nil,
            logs: [
                "[15:02:11] 第 1 周: Gate 1 合格（ビルド 1.4 秒 / WASM 184 KB / CDP エラー 0 件）",
                "[15:02:19] 第 1 周: 独立レビュー差し戻し（62 点）→ 第 2 周の再実装を開始",
                "[15:02:37] 第 2 周: Gate 1 合格 → 独立レビュー（隔離セッション）を実行中…",
            ],
            errorMessage: nil
        )
        let runningVC = FactoryViewController()
        _ = runningVC.view
        runningVC.update(palette: .kasugai)
        runningVC.display(run: sampleRunning)
        if let path = renderOffscreen(
            view: runningVC.view,
            size: factorySize,
            appearance: darkApp,
            to: outDir.appendingPathComponent("factory-running-dark.png")
        ) {
            written.append(path)
        }

        var sampleReady = sampleRunning
        sampleReady.id = "snap-ready"
        sampleReady.status = .previewReady
        sampleReady.currentStageId = "preview"
        sampleReady.iterations[1].outcome = "passed"
        sampleReady.iterations[1].badgeText = "88 点"
        sampleReady.iterations[1].panels[1] = FactoryGatePanel(
            id: "gate2",
            title: "4. 独立レビュー（隔離）",
            statusText: "88 点",
            tone: .success,
            metrics: [],
            summary: "1 ボタン操作の気持ちよさと結果画面の切れ味が両立できています。",
            bullets: [],
            imagePath: nil,
            threadId: 14,
            threadLabel: "4. レビュースレッドを表示"
        )
        sampleReady.localPreviewURL = "http://127.0.0.1:41234/"
        sampleReady.stagingPreviewURL = "https://preview.example.com/demo-game/"
        let readyVC = FactoryViewController()
        _ = readyVC.view
        readyVC.update(palette: .kasugai)
        readyVC.display(run: sampleReady)
        if let path = renderOffscreen(
            view: readyVC.view,
            size: factorySize,
            appearance: darkApp,
            to: outDir.appendingPathComponent("factory-preview-dark.png")
        ) {
            written.append(path)
        }

        for path in written {
            print(path)
        }
        return written.isEmpty ? EXIT_FAILURE : EXIT_SUCCESS
    }

    private static func renderOffscreen(
        view: NSView,
        size: NSSize,
        appearance: NSAppearance?,
        to url: URL
    ) -> String? {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = appearance
        view.appearance = appearance
        view.frame = NSRect(origin: .zero, size: size)
        window.contentView = view
        window.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()

        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return nil
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        do {
            try png.write(to: url, options: .atomic)
            return url.path
        } catch {
            return nil
        }
    }
}
