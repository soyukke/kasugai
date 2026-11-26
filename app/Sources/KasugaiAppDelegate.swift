import AppKit
import Foundation

final class KasugaiAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var splitController: MainSplitViewController?
    private var menuController: MainMenuController?
    private var currentSettings: KasugaiAppSettings = .load()
    private var storePath: String = KasugaiCore.defaultStorePath()
    private var pendingOpenURLs: [URL] = []
    private var lastNonFullScreenFrame: NSRect = NSRect(x: 0, y: 0, width: 1280, height: 820)
    private var pendingWindowStateSave: DispatchWorkItem?
    private var isRestoringWindowState = false
    private let launchExecutableStamp: String = KasugaiDaemonPaths.binaryStamp(
        atPath: Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        let initialDir = resolveInitialProjectDirectory()
        let defaultName = URL(fileURLWithPath: initialDir).lastPathComponent
        let projectName = defaultName.isEmpty || defaultName == "/" ? "Kasugai" : defaultName
        let settingsPath = KasugaiAppSettings.defaultPath()
        let hasSavedSettings = FileManager.default.fileExists(atPath: settingsPath)
        currentSettings = KasugaiAppSettings.load(from: settingsPath)
        if !hasSavedSettings || currentSettings.defaultProvider == "local_echo",
            let detected = detectPreferredProvider()
        {
            currentSettings.defaultProvider = detected
            _ = currentSettings.save(to: settingsPath)
        }
        storePath = KasugaiCore.defaultStorePath()
        NSApp.appearance = currentSettings.appearance.nsAppearance

        let useDirectCore =
            ProcessInfo.processInfo.environment["KASUGAI_DIRECT_CORE"] == "1"
            || ProcessInfo.processInfo.environment["KASUGAI_SELF_TEST"] == "1"
        let connectedCore: KasugaiCore?
        if useDirectCore {
            connectedCore = KasugaiCore(
                projectName: projectName,
                projectPath: initialDir,
                storePath: storePath
            )
        } else {
            connectedCore =
                KasugaiCore.connectToDaemon(
                    projectName: projectName,
                    projectPath: initialDir,
                    storePath: storePath
                )
                ?? KasugaiCore(
                    projectName: projectName,
                    projectPath: initialDir,
                    storePath: storePath
                )
        }
        guard let core = connectedCore else {
            presentFatalError(
                title: "コアを初期化できませんでした",
                message: "Kasugai コアの起動に失敗しました。アプリを再起動してください。"
            )
            return
        }

        if let initialSnap = core.snapshot(),
            let activeThread = initialSnap.activeThread,
            activeThread.status == "idle",
            activeThread.messages.isEmpty,
            activeThread.provider == "local_echo",
            currentSettings.defaultProvider != "local_echo"
        {
            let defaultModel = ProviderModelCatalog.shared.defaultModelId(
                for: currentSettings.defaultProvider
            )
            _ = core.setThreadProvider(
                activeThread.id,
                provider: currentSettings.defaultProvider,
                model: defaultModel,
                effort: currentSettings.defaultEffort
            )
        } else if let initialSnap = core.snapshot(),
            let activeThread = initialSnap.activeThread,
            activeThread.status == "idle",
            activeThread.provider != "local_echo"
        {
            let resolved = ProviderModelCatalog.shared.resolveConcreteModelId(
                providerId: activeThread.provider,
                model: activeThread.model
            )
            if resolved != activeThread.model {
                _ = core.setThreadProvider(
                    activeThread.id,
                    provider: activeThread.provider,
                    model: resolved,
                    effort: activeThread.effort
                )
            }
        }

        let controller = MainSplitViewController(
            core: core,
            settings: currentSettings,
            storePath: storePath
        )

        let savedWindowState = KasugaiWindowState.load()
        let contentRect = NSRect(x: 0, y: 0, width: 1280, height: 820)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = KasugaiRuntimePaths.appDisplayName
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 720, height: 480)
        window.delegate = self
        window.contentViewController = controller
        window.backgroundColor =
            KasugaiThemeTokens.resolve(
                palette: currentSettings.palette,
                appearance: window.effectiveAppearance
            ).canvasBg
        isRestoringWindowState = true
        if let savedWindowState {
            let visibleFrames = NSScreen.screens.map(\.visibleFrame)
            let restoredFrame = savedWindowState.clampedFrame(in: visibleFrames)
            window.setFrame(restoredFrame, display: false)
            lastNonFullScreenFrame = restoredFrame
            window.layoutIfNeeded()
            controller.restorePaneLayout(from: savedWindowState)
        } else {
            window.setContentSize(contentRect.size)
            window.center()
            lastNonFullScreenFrame = window.frame
        }
        window.isReleasedWhenClosed = false
        controller.onLayoutStateChanged = { [weak self] in
            self?.scheduleWindowStateSave()
        }

        let menu = MainMenuController { [weak self, weak controller] action in
            switch action {
            case .openSettings:
                controller?.toggleSettingsScreen()
            case .newThread:
                controller?.createNewThread()
            case .addProject:
                controller?.addProjectInteractive()
            case .toggleSidebar:
                controller?.toggleLeftSidebar()
            case .toggleDiff:
                controller?.toggleDiffPane()
            case .toggleTerminal:
                controller?.toggleTerminalPane()
            case .reloadUI:
                self?.handleReloadUI()
            case .restartDaemon:
                controller?.restartDaemonIfIdle()
            case .searchThreads:
                controller?.focusThreadSearch()
            case .processQueue:
                controller?.processQueuedTurns()
            }
        }
        menu.install(in: NSApp)

        self.window = window
        self.splitController = controller
        self.menuController = menu

        if !pendingOpenURLs.isEmpty {
            let queued = pendingOpenURLs
            pendingOpenURLs.removeAll()
            for url in queued {
                controller.openProject(at: url)
            }
        }

        let launchBackground =
            ProcessInfo.processInfo.environment["KASUGAI_LAUNCH_BACKGROUND"] == "1"
        if launchBackground {
            window.orderFront(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            if savedWindowState?.isFullScreen == true {
                DispatchQueue.main.async {
                    window.toggleFullScreen(nil)
                }
            }
            controller.focusComposer()
        }
        isRestoringWindowState = false
    }

    private func scheduleWindowStateSave() {
        guard !isRestoringWindowState else {
            return
        }
        pendingWindowStateSave?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.saveWindowStateNow()
        }
        pendingWindowStateSave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(160), execute: item)
    }

    private func saveWindowStateNow() {
        pendingWindowStateSave?.cancel()
        pendingWindowStateSave = nil
        guard let window, let splitController else {
            return
        }
        let isFullScreen = window.styleMask.contains(.fullScreen)
        if !isFullScreen && window.frame.width >= 720 && window.frame.height >= 480 {
            lastNonFullScreenFrame = window.frame
        }
        let frameToSave = isFullScreen ? lastNonFullScreenFrame : window.frame
        guard frameToSave.width >= 720, frameToSave.height >= 480 else {
            return
        }
        let panes = splitController.capturePaneLayout()
        let state = KasugaiWindowState(
            frameX: Double(frameToSave.origin.x),
            frameY: Double(frameToSave.origin.y),
            frameWidth: Double(frameToSave.size.width),
            frameHeight: Double(frameToSave.size.height),
            isFullScreen: isFullScreen,
            sidebarCollapsed: panes.sidebarCollapsed,
            sidebarWidth: panes.sidebarWidth,
            rightPaneCollapsed: panes.rightPaneCollapsed,
            rightPaneWidth: panes.rightPaneWidth,
            terminalCollapsed: panes.terminalCollapsed,
            terminalHeight: panes.terminalHeight,
            detailsCardOpen: panes.detailsCardOpen
        )
        _ = state.save()
    }

    func windowDidResize(_ notification: Notification) {
        scheduleWindowStateSave()
    }

    func windowDidMove(_ notification: Notification) {
        scheduleWindowStateSave()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        saveWindowStateNow()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        saveWindowStateNow()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        saveWindowStateNow()
    }

    func application(_ sender: NSApplication, open urls: [URL]) {
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else {
            return
        }
        guard let splitController else {
            pendingOpenURLs.append(contentsOf: fileURLs)
            return
        }
        for url in fileURLs {
            splitController.openProject(at: url)
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        if !flag {
            window?.deminiaturize(nil)
            window?.makeKeyAndOrderFront(nil)
        }
        return true
    }

    private func resolveInitialProjectDirectory() -> String {
        if let first = pendingOpenURLs.first {
            return directoryPath(for: first)
        }
        if let envDir = ProcessInfo.processInfo.environment["KASUGAI_INITIAL_DIR"],
            !envDir.isEmpty
        {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: envDir, isDirectory: &isDir), isDir.boolValue
            {
                return envDir
            }
        }
        let cwd = FileManager.default.currentDirectoryPath
        let bundlePath = Bundle.main.bundleURL.standardizedFileURL.path
        if cwd.isEmpty || cwd == "/" || cwd.hasPrefix(bundlePath) {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: cwd, isDirectory: &isDir), isDir.boolValue {
            return cwd
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    private func directoryPath(for url: URL) -> String {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            return url.path
        }
        return url.deletingLastPathComponent().path
    }

    private func detectPreferredProvider() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let searchDirs = [
            "\(home)/.local/bin",
            "\(home)/.local/share/kugi/bin",
            "\(home)/.opencode/bin",
            "\(home)/.cargo/bin",
            "\(home)/.nix-profile/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
        ]
        let candidates: [(provider: String, executable: String)] = [
            ("claude_code", "claude"),
            ("codex", "codex"),
            ("opencode_acp", "opencode"),
            ("antigravity_acp", "agy"),
        ]
        let fm = FileManager.default
        for item in candidates {
            for dir in searchDirs {
                let path = "\(dir)/\(item.executable)"
                if fm.isExecutableFile(atPath: path) {
                    return item.provider
                }
            }
        }
        return nil
    }

    private func handleReloadUI() {
        saveWindowStateNow()
        splitController?.savePersistentUIStateNow()
        let exePath = Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
        let onDiskStamp = KasugaiDaemonPaths.binaryStamp(atPath: exePath)
        let bundleURL = Bundle.main.bundleURL
        if onDiskStamp != "unknown",
            onDiskStamp != launchExecutableStamp,
            bundleURL.pathExtension == "app",
            FileManager.default.fileExists(atPath: bundleURL.path)
        {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            proc.arguments = ["-n", bundleURL.path]
            if (try? proc.run()) != nil {
                NSApp.terminate(nil)
                return
            }
        }
        splitController?.reloadViewAndReconnect()
    }

    func applicationWillTerminate(_ notification: Notification) {
        saveWindowStateNow()
        splitController?.prepareForTerminate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    private func presentFatalError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "終了")
        alert.runModal()
        NSApp.terminate(nil)
    }
}
