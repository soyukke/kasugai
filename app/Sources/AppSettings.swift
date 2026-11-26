import AppKit
import Foundation

enum KasugaiRuntimePaths {
    static let devBundleIdentifier = "dev.soyukke.kasugai.dev"

    static var isDevBundle: Bool {
        isDevBundle(bundleIdentifier: Bundle.main.bundleIdentifier)
    }

    static func isDevBundle(bundleIdentifier: String?) -> Bool {
        bundleIdentifier == devBundleIdentifier
    }

    static var appDisplayName: String {
        isDevBundle ? "Kasugai Dev" : "Kasugai"
    }

    static func dataDirectory(
        env: [String: String] = ProcessInfo.processInfo.environment,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> URL {
        if let override = env["KASUGAI_DATA_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
                "Library/Application Support",
                isDirectory: true
            )
        let folderName = isDevBundle(bundleIdentifier: bundleIdentifier) ? "Kasugai-Dev" : "Kasugai"
        return base.appendingPathComponent(folderName, isDirectory: true)
    }
}

enum KasugaiAppearance: String, Codable, CaseIterable {
    case system
    case light
    case dark

    var label: String {
        switch self {
        case .system:
            return "システム"
        case .light:
            return "ライト"
        case .dark:
            return "ダーク"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system:
            return nil
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        }
    }
}

enum KasugaiPalette: String, Codable, CaseIterable {
    case kasugai
    case slate
    case nord
    case warm
    case forest
    case rose
    case twilight
    case highContrast = "high_contrast"

    var label: String {
        switch self {
        case .kasugai:
            return "標準"
        case .slate:
            return "スレート"
        case .nord:
            return "ノード"
        case .warm:
            return "ウォーム"
        case .forest:
            return "フォレスト"
        case .rose:
            return "ローズ"
        case .twilight:
            return "トワイライト"
        case .highContrast:
            return "ハイコントラスト"
        }
    }

    func terminalColors(isLight: Bool) -> (background: NSColor, foreground: NSColor) {
        let theme = KasugaiThemeTokens.resolve(palette: self, isLight: isLight)
        return (theme.canvasBg, theme.textPrimary)
    }

    func swatchColors(isLight: Bool) -> (bg: NSColor, surface: NSColor, accent: NSColor) {
        let theme = KasugaiThemeTokens.resolve(palette: self, isLight: isLight)
        return (theme.canvasBg, theme.surfaceBg, theme.accent)
    }
}

enum KasugaiToolApprovalPolicy: String, Codable, CaseIterable {
    case alwaysAllow = "always_allow"
    case askEveryTime = "ask"

    var label: String {
        switch self {
        case .alwaysAllow:
            return "常に許可"
        case .askEveryTime:
            return "毎回確認"
        }
    }
}

struct KasugaiComposerDraft: Codable, Equatable {
    var text: String
    var attachments: [String]

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty
    }
}

struct KasugaiWindowState: Codable, Equatable {
    var frameX: Double
    var frameY: Double
    var frameWidth: Double
    var frameHeight: Double
    var isFullScreen: Bool
    var sidebarCollapsed: Bool
    var sidebarWidth: Double
    var rightPaneCollapsed: Bool
    var rightPaneWidth: Double
    var terminalCollapsed: Bool
    var terminalHeight: Double
    var detailsCardOpen: Bool

    init(
        frameX: Double,
        frameY: Double,
        frameWidth: Double,
        frameHeight: Double,
        isFullScreen: Bool,
        sidebarCollapsed: Bool,
        sidebarWidth: Double,
        rightPaneCollapsed: Bool,
        rightPaneWidth: Double,
        terminalCollapsed: Bool,
        terminalHeight: Double,
        detailsCardOpen: Bool = true
    ) {
        self.frameX = frameX
        self.frameY = frameY
        self.frameWidth = frameWidth
        self.frameHeight = frameHeight
        self.isFullScreen = isFullScreen
        self.sidebarCollapsed = sidebarCollapsed
        self.sidebarWidth = sidebarWidth
        self.rightPaneCollapsed = rightPaneCollapsed
        self.rightPaneWidth = rightPaneWidth
        self.terminalCollapsed = terminalCollapsed
        self.terminalHeight = terminalHeight
        self.detailsCardOpen = detailsCardOpen
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        frameX = try c.decode(Double.self, forKey: .frameX)
        frameY = try c.decode(Double.self, forKey: .frameY)
        frameWidth = try c.decode(Double.self, forKey: .frameWidth)
        frameHeight = try c.decode(Double.self, forKey: .frameHeight)
        isFullScreen = try c.decode(Bool.self, forKey: .isFullScreen)
        sidebarCollapsed = try c.decode(Bool.self, forKey: .sidebarCollapsed)
        sidebarWidth = try c.decode(Double.self, forKey: .sidebarWidth)
        rightPaneCollapsed = try c.decode(Bool.self, forKey: .rightPaneCollapsed)
        rightPaneWidth = try c.decode(Double.self, forKey: .rightPaneWidth)
        terminalCollapsed = try c.decode(Bool.self, forKey: .terminalCollapsed)
        terminalHeight = try c.decode(Double.self, forKey: .terminalHeight)
        detailsCardOpen = try c.decodeIfPresent(Bool.self, forKey: .detailsCardOpen) ?? true
    }

    static func defaultPath() -> String {
        if let override = ProcessInfo.processInfo.environment["KASUGAI_WINDOW_STATE_PATH"],
            !override.isEmpty
        {
            return override
        }
        if ProcessInfo.processInfo.environment["KASUGAI_SELF_TEST"] == "1" {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("kasugai-self-test-window-state.json")
                .path
        }
        return KasugaiRuntimePaths.dataDirectory()
            .appendingPathComponent("window-state.json")
            .path
    }

    static func load(from path: String = defaultPath()) -> KasugaiWindowState? {
        guard let data = FileManager.default.contents(atPath: path),
            let decoded = try? JSONDecoder().decode(KasugaiWindowState.self, from: data),
            decoded.frameWidth >= 720,
            decoded.frameHeight >= 480
        else {
            return nil
        }
        return decoded
    }

    @discardableResult
    func save(to path: String = defaultPath()) -> Bool {
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        let fm = FileManager.default
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try fm.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = try encoder.encode(self)
            try data.write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }

    func clampedFrame(in visibleFrames: [NSRect]) -> NSRect {
        let raw = NSRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight)
        guard !visibleFrames.isEmpty else {
            return raw
        }
        let targetScreen =
            visibleFrames.max { lhs, rhs in
                let a = lhs.intersection(raw)
                let b = rhs.intersection(raw)
                let areaA = a.isNull ? 0 : a.width * a.height
                let areaB = b.isNull ? 0 : b.width * b.height
                return areaA < areaB
            } ?? visibleFrames[0]
        let clampedW = max(720, min(raw.width, targetScreen.width))
        let clampedH = max(480, min(raw.height, targetScreen.height))
        let clampedX = min(max(raw.minX, targetScreen.minX), targetScreen.maxX - clampedW)
        let clampedY = min(max(raw.minY, targetScreen.minY), targetScreen.maxY - clampedH)
        return NSRect(x: clampedX, y: clampedY, width: clampedW, height: clampedH)
    }
}

struct KasugaiDraftStore: Codable, Equatable {
    var byThreadId: [String: KasugaiComposerDraft]

    static let empty = KasugaiDraftStore(byThreadId: [:])

    static func defaultPath() -> String {
        if let override = ProcessInfo.processInfo.environment["KASUGAI_DRAFTS_PATH"],
            !override.isEmpty
        {
            return override
        }
        if ProcessInfo.processInfo.environment["KASUGAI_SELF_TEST"] == "1" {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("kasugai-self-test-drafts.json")
                .path
        }
        return KasugaiRuntimePaths.dataDirectory()
            .appendingPathComponent("drafts.json")
            .path
    }

    static func load(from path: String = defaultPath()) -> KasugaiDraftStore {
        guard let data = FileManager.default.contents(atPath: path),
            let decoded = try? JSONDecoder().decode(KasugaiDraftStore.self, from: data)
        else {
            return .empty
        }
        return decoded
    }

    func draft(for threadId: Int64) -> KasugaiComposerDraft? {
        byThreadId[String(threadId)]
    }

    mutating func setDraft(_ draft: KasugaiComposerDraft, for threadId: Int64) {
        let key = String(threadId)
        if draft.isEmpty {
            byThreadId.removeValue(forKey: key)
        } else {
            byThreadId[key] = draft
        }
    }

    @discardableResult
    func save(to path: String = defaultPath()) -> Bool {
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        let fm = FileManager.default
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try fm.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = try encoder.encode(self)
            try data.write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }
}

enum KasugaiPersistedTabKind: String, Codable, Equatable {
    case diff
    case files
    case preview
    case browser
}

struct KasugaiPersistedRightPaneTab: Codable, Equatable {
    var kind: KasugaiPersistedTabKind
    var path: String?
    var url: String?
    var title: String?
}

struct KasugaiPersistedThreadRightPane: Codable, Equatable {
    var tabs: [KasugaiPersistedRightPaneTab]
    var activeIndex: Int
    var fileRootPath: String?
}

struct KasugaiRightPaneTabStore: Codable, Equatable {
    var byThreadId: [String: KasugaiPersistedThreadRightPane]

    static let empty = KasugaiRightPaneTabStore(byThreadId: [:])

    static func defaultPath() -> String {
        if let override = ProcessInfo.processInfo.environment["KASUGAI_RIGHT_PANE_TABS_PATH"],
            !override.isEmpty
        {
            return override
        }
        if ProcessInfo.processInfo.environment["KASUGAI_SELF_TEST"] == "1" {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("kasugai-self-test-right-pane-tabs.json")
                .path
        }
        return KasugaiRuntimePaths.dataDirectory()
            .appendingPathComponent("right-pane-tabs.json")
            .path
    }

    static func load(from path: String = defaultPath()) -> KasugaiRightPaneTabStore {
        guard let data = FileManager.default.contents(atPath: path),
            let decoded = try? JSONDecoder().decode(KasugaiRightPaneTabStore.self, from: data)
        else {
            return .empty
        }
        return decoded
    }

    func pane(for threadId: Int64) -> KasugaiPersistedThreadRightPane? {
        byThreadId[String(threadId)]
    }

    mutating func setPane(_ pane: KasugaiPersistedThreadRightPane?, for threadId: Int64) {
        let key = String(threadId)
        if let pane, !pane.tabs.isEmpty {
            byThreadId[key] = pane
        } else {
            byThreadId.removeValue(forKey: key)
        }
    }

    @discardableResult
    func save(to path: String = defaultPath()) -> Bool {
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        let fm = FileManager.default
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try fm.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = try encoder.encode(self)
            try data.write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }
}

enum KasugaiBrowserRuleAction: String, Codable, CaseIterable {
    case allow
    case block

    var label: String {
        switch self {
        case .allow:
            return "許可"
        case .block:
            return "ブロック"
        }
    }
}

struct KasugaiBrowserDomainRule: Codable, Equatable {
    var action: KasugaiBrowserRuleAction
    var domain: String
}

struct KasugaiBrowserPolicy: Equatable {
    var allowExternal: Bool
    var allowAllExternal: Bool
    var rules: [KasugaiBrowserDomainRule]

    static let loopbackOnly = KasugaiBrowserPolicy(
        allowExternal: false,
        allowAllExternal: false,
        rules: []
    )

    init(
        allowExternal: Bool,
        allowAllExternal: Bool,
        rules: [KasugaiBrowserDomainRule]
    ) {
        self.allowExternal = allowExternal
        self.allowAllExternal = allowAllExternal
        self.rules = rules
    }

    init(allowExternal: Bool, allowedDomains: [String]) {
        self.allowExternal = allowExternal
        self.allowAllExternal = allowedDomains.isEmpty
        self.rules = allowedDomains.compactMap { raw in
            guard let normalized = Self.normalizeDomain(raw) else {
                return nil
            }
            return KasugaiBrowserDomainRule(action: .allow, domain: normalized)
        }
    }

    static func normalizeDomain(_ raw: String) -> String? {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cleaned.hasPrefix("https://") {
            cleaned = String(cleaned.dropFirst("https://".count))
        } else if cleaned.hasPrefix("http://") {
            cleaned = String(cleaned.dropFirst("http://".count))
        }
        if let slash = cleaned.firstIndex(of: "/") {
            cleaned = String(cleaned[..<slash])
        }
        if let colon = cleaned.firstIndex(of: ":") {
            cleaned = String(cleaned[..<colon])
        }
        while cleaned.hasPrefix("*.") {
            cleaned = String(cleaned.dropFirst(2))
        }
        while cleaned.hasPrefix(".") {
            cleaned = String(cleaned.dropFirst())
        }
        return cleaned.isEmpty ? nil : cleaned
    }

    static func parseDomains(from raw: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",;\n\r\t ")
        var seen: Set<String> = []
        var result: [String] = []
        for piece in raw.components(separatedBy: separators) {
            guard let cleaned = normalizeDomain(piece), !seen.contains(cleaned) else {
                continue
            }
            seen.insert(cleaned)
            result.append(cleaned)
        }
        return result
    }

    static func isLoopbackHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        return lower == "localhost" || lower == "127.0.0.1" || lower == "::1"
    }

    private static func host(_ host: String, matchesDomain domain: String) -> Bool {
        guard let normalized = normalizeDomain(domain) else {
            return false
        }
        return host == normalized || host.hasSuffix(".\(normalized)")
    }

    func isAllowedURL(_ url: URL?) -> Bool {
        guard let url,
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = url.host?.lowercased(),
            !host.isEmpty
        else {
            return false
        }
        if Self.isLoopbackHost(host) {
            return true
        }
        guard allowExternal else {
            return false
        }
        for rule in rules where rule.action == .block {
            if Self.host(host, matchesDomain: rule.domain) {
                return false
            }
        }
        for rule in rules where rule.action == .allow {
            if Self.host(host, matchesDomain: rule.domain) {
                return true
            }
        }
        return allowAllExternal
    }

    func normalizeURL(_ raw: String) -> URL? {
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
        } else if trimmed.lowercased().hasPrefix("localhost")
            || trimmed.hasPrefix("127.0.0.1")
            || trimmed.hasPrefix("[::1]")
        {
            candidate = "http://\(trimmed)"
        } else {
            candidate = "https://\(trimmed)"
        }
        guard let url = URL(string: candidate), isAllowedURL(url) else {
            return nil
        }
        return url
    }
}

struct KasugaiAppSettings: Codable, Equatable {
    var appearance: KasugaiAppearance
    var palette: KasugaiPalette
    var suppressTelemetry: Bool
    var defaultProvider: String
    var defaultEffort: String
    var toolApprovalPolicy: KasugaiToolApprovalPolicy
    var enableAgentOrchestration: Bool
    var allowExternalBrowser: Bool
    var externalBrowserAllowAll: Bool
    var externalBrowserRules: [KasugaiBrowserDomainRule]
    var externalBrowserAllowedDomains: [String]
    var enableMobileBridge: Bool
    var mobileBridgeLocalPort: UInt16
    var mobileBridgeHttpsPort: UInt16
    var pinnedThreadIds: [Int64]
    var settledThreadIds: [Int64]
    var deletedThreadIds: [Int64]

    var browserPolicy: KasugaiBrowserPolicy {
        KasugaiBrowserPolicy(
            allowExternal: allowExternalBrowser,
            allowAllExternal: externalBrowserAllowAll,
            rules: externalBrowserRules
        )
    }

    static let defaultValue = KasugaiAppSettings(
        appearance: .system,
        palette: .kasugai,
        suppressTelemetry: true,
        defaultProvider: "local_echo",
        defaultEffort: "medium",
        toolApprovalPolicy: .alwaysAllow,
        enableAgentOrchestration: true,
        allowExternalBrowser: false,
        externalBrowserAllowAll: false,
        externalBrowserRules: [],
        externalBrowserAllowedDomains: [],
        enableMobileBridge: false,
        mobileBridgeLocalPort: MobileBridgeDefaults.defaultLocalPort,
        mobileBridgeHttpsPort: MobileBridgeDefaults.defaultTailscaleHttpsPort,
        pinnedThreadIds: [],
        settledThreadIds: [],
        deletedThreadIds: []
    )

    init(
        appearance: KasugaiAppearance,
        palette: KasugaiPalette,
        suppressTelemetry: Bool,
        defaultProvider: String,
        defaultEffort: String,
        toolApprovalPolicy: KasugaiToolApprovalPolicy = .alwaysAllow,
        enableAgentOrchestration: Bool,
        allowExternalBrowser: Bool = false,
        externalBrowserAllowAll: Bool? = nil,
        externalBrowserRules: [KasugaiBrowserDomainRule]? = nil,
        externalBrowserAllowedDomains: [String] = [],
        enableMobileBridge: Bool = false,
        mobileBridgeLocalPort: UInt16 = MobileBridgeDefaults.defaultLocalPort,
        mobileBridgeHttpsPort: UInt16 = MobileBridgeDefaults.defaultTailscaleHttpsPort,
        pinnedThreadIds: [Int64] = [],
        settledThreadIds: [Int64] = [],
        deletedThreadIds: [Int64] = []
    ) {
        self.appearance = appearance
        self.palette = palette
        self.suppressTelemetry = suppressTelemetry
        self.defaultProvider = defaultProvider
        self.defaultEffort = defaultEffort
        self.toolApprovalPolicy = toolApprovalPolicy
        self.enableAgentOrchestration = enableAgentOrchestration
        self.allowExternalBrowser = allowExternalBrowser
        let resolvedRules =
            externalBrowserRules
            ?? externalBrowserAllowedDomains.compactMap { raw in
                KasugaiBrowserPolicy.normalizeDomain(raw).map {
                    KasugaiBrowserDomainRule(action: .allow, domain: $0)
                }
            }
        self.externalBrowserRules = resolvedRules
        self.externalBrowserAllowAll =
            externalBrowserAllowAll ?? (allowExternalBrowser && resolvedRules.isEmpty)
        self.externalBrowserAllowedDomains =
            resolvedRules
            .filter { $0.action == .allow }
            .map(\.domain)
        self.enableMobileBridge = enableMobileBridge
        self.mobileBridgeLocalPort = mobileBridgeLocalPort
        self.mobileBridgeHttpsPort = mobileBridgeHttpsPort
        self.pinnedThreadIds = pinnedThreadIds
        self.settledThreadIds = settledThreadIds
        self.deletedThreadIds = deletedThreadIds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appearance = try c.decodeIfPresent(KasugaiAppearance.self, forKey: .appearance) ?? .system
        palette = try c.decodeIfPresent(KasugaiPalette.self, forKey: .palette) ?? .kasugai
        suppressTelemetry = try c.decodeIfPresent(Bool.self, forKey: .suppressTelemetry) ?? true
        defaultProvider =
            try c.decodeIfPresent(String.self, forKey: .defaultProvider) ?? "local_echo"
        defaultEffort = try c.decodeIfPresent(String.self, forKey: .defaultEffort) ?? "medium"
        toolApprovalPolicy =
            try c.decodeIfPresent(KasugaiToolApprovalPolicy.self, forKey: .toolApprovalPolicy)
            ?? .alwaysAllow
        enableAgentOrchestration =
            try c.decodeIfPresent(Bool.self, forKey: .enableAgentOrchestration) ?? true
        allowExternalBrowser =
            try c.decodeIfPresent(Bool.self, forKey: .allowExternalBrowser) ?? false
        let legacyAllowed =
            try c.decodeIfPresent([String].self, forKey: .externalBrowserAllowedDomains) ?? []
        let decodedRules = try c.decodeIfPresent(
            [KasugaiBrowserDomainRule].self,
            forKey: .externalBrowserRules
        )
        let resolvedRules =
            decodedRules
            ?? legacyAllowed.compactMap { raw in
                KasugaiBrowserPolicy.normalizeDomain(raw).map {
                    KasugaiBrowserDomainRule(action: .allow, domain: $0)
                }
            }
        externalBrowserRules = resolvedRules
        let decodedAllowAll = try c.decodeIfPresent(Bool.self, forKey: .externalBrowserAllowAll)
        externalBrowserAllowAll =
            decodedAllowAll ?? (allowExternalBrowser && resolvedRules.isEmpty)
        externalBrowserAllowedDomains =
            resolvedRules
            .filter { $0.action == .allow }
            .map(\.domain)
        enableMobileBridge =
            try c.decodeIfPresent(Bool.self, forKey: .enableMobileBridge) ?? false
        mobileBridgeLocalPort =
            try c.decodeIfPresent(UInt16.self, forKey: .mobileBridgeLocalPort)
            ?? MobileBridgeDefaults.defaultLocalPort
        mobileBridgeHttpsPort =
            try c.decodeIfPresent(UInt16.self, forKey: .mobileBridgeHttpsPort)
            ?? MobileBridgeDefaults.defaultTailscaleHttpsPort
        pinnedThreadIds = try c.decodeIfPresent([Int64].self, forKey: .pinnedThreadIds) ?? []
        settledThreadIds = try c.decodeIfPresent([Int64].self, forKey: .settledThreadIds) ?? []
        deletedThreadIds = try c.decodeIfPresent([Int64].self, forKey: .deletedThreadIds) ?? []
    }

    static func defaultPath() -> String {
        if let override = ProcessInfo.processInfo.environment["KASUGAI_SETTINGS_PATH"],
            !override.isEmpty
        {
            return override
        }
        if ProcessInfo.processInfo.environment["KASUGAI_SELF_TEST"] == "1" {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("kasugai-self-test-settings.json")
                .path
        }
        return KasugaiRuntimePaths.dataDirectory()
            .appendingPathComponent("settings.json")
            .path
    }

    static func load(from path: String = defaultPath()) -> KasugaiAppSettings {
        guard let data = FileManager.default.contents(atPath: path),
            let decoded = try? JSONDecoder().decode(KasugaiAppSettings.self, from: data)
        else {
            return .defaultValue
        }
        return decoded
    }

    @discardableResult
    func save(to path: String = defaultPath()) -> Bool {
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        let fm = FileManager.default
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try fm.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = try encoder.encode(self)
            try data.write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }

    static func runSelfTests() -> Bool {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent(
            "kasugai-settings-\(UUID().uuidString).json"
        )
        defer { try? fm.removeItem(at: temp) }

        let custom = KasugaiAppSettings(
            appearance: .dark,
            palette: .nord,
            suppressTelemetry: true,
            defaultProvider: "claude_code",
            defaultEffort: "high",
            toolApprovalPolicy: .askEveryTime,
            enableAgentOrchestration: true,
            allowExternalBrowser: true,
            externalBrowserAllowedDomains: ["steamgames.com", "steampowered.com"],
            pinnedThreadIds: [2, 5],
            settledThreadIds: [3, 8],
            deletedThreadIds: [9, 12]
        )
        guard custom.save(to: temp.path) else {
            return false
        }
        let reloaded = KasugaiAppSettings.load(from: temp.path)
        let restrictedPolicy = custom.browserPolicy
        let openWithBlockPolicy = KasugaiBrowserPolicy(
            allowExternal: true,
            allowAllExternal: true,
            rules: [
                KasugaiBrowserDomainRule(action: .block, domain: "ads.example.com"),
                KasugaiBrowserDomainRule(action: .allow, domain: "partner.steamgames.com"),
            ]
        )
        let allowListWithBlockOverride = KasugaiBrowserPolicy(
            allowExternal: true,
            allowAllExternal: false,
            rules: [
                KasugaiBrowserDomainRule(action: .allow, domain: "steamgames.com"),
                KasugaiBrowserDomainRule(action: .block, domain: "blocked.steamgames.com"),
            ]
        )
        let policyChecks =
            KasugaiBrowserPolicy.loopbackOnly.normalizeURL("https://partner.steamgames.com") == nil
            && restrictedPolicy.normalizeURL("https://partner.steamgames.com/apps") != nil
            && restrictedPolicy.normalizeURL("https://example.com") == nil
            && restrictedPolicy.normalizeURL("http://localhost:3000") != nil
            && openWithBlockPolicy.normalizeURL("partner.steamgames.com")?.absoluteString
                == "https://partner.steamgames.com"
            && openWithBlockPolicy.normalizeURL("https://example.com") != nil
            && openWithBlockPolicy.normalizeURL("https://ads.example.com/pixel") == nil
            && openWithBlockPolicy.normalizeURL("file:///etc/passwd") == nil
            && allowListWithBlockOverride.normalizeURL("https://partner.steamgames.com") != nil
            && allowListWithBlockOverride.normalizeURL("https://blocked.steamgames.com") == nil
            && allowListWithBlockOverride.normalizeURL("https://other.org") == nil
            && KasugaiBrowserPolicy.parseDomains(
                from: "https://partner.steamgames.com/foo, *.steampowered.com"
            ) == ["partner.steamgames.com", "steampowered.com"]
        let prodDir = KasugaiRuntimePaths.dataDirectory(
            env: [:],
            bundleIdentifier: "dev.soyukke.kasugai"
        )
        let devDir = KasugaiRuntimePaths.dataDirectory(
            env: [:],
            bundleIdentifier: KasugaiRuntimePaths.devBundleIdentifier
        )
        let customDir = KasugaiRuntimePaths.dataDirectory(
            env: ["KASUGAI_DATA_DIR": "/tmp/kasugai-custom-data"],
            bundleIdentifier: "dev.soyukke.kasugai"
        )
        let draftTemp = fm.temporaryDirectory.appendingPathComponent(
            "kasugai-drafts-\(UUID().uuidString).json"
        )
        defer { try? fm.removeItem(at: draftTemp) }
        var draftStore = KasugaiDraftStore.empty
        let sampleDraft = KasugaiComposerDraft(text: "書きかけのメッセージ", attachments: ["/tmp/a.png"])
        draftStore.setDraft(sampleDraft, for: 42)
        guard draftStore.save(to: draftTemp.path) else {
            return false
        }
        var reloadedDrafts = KasugaiDraftStore.load(from: draftTemp.path)
        let draftMatches = reloadedDrafts.draft(for: 42) == sampleDraft
        reloadedDrafts.setDraft(KasugaiComposerDraft(text: "   ", attachments: []), for: 42)
        let draftCleared = reloadedDrafts.draft(for: 42) == nil

        let winTemp = fm.temporaryDirectory.appendingPathComponent(
            "kasugai-window-state-\(UUID().uuidString).json"
        )
        defer { try? fm.removeItem(at: winTemp) }
        let sampleWin = KasugaiWindowState(
            frameX: 120,
            frameY: 80,
            frameWidth: 1680,
            frameHeight: 1020,
            isFullScreen: false,
            sidebarCollapsed: false,
            sidebarWidth: 268,
            rightPaneCollapsed: false,
            rightPaneWidth: 560,
            terminalCollapsed: true,
            terminalHeight: 220
        )
        let winSaved = sampleWin.save(to: winTemp.path)
        let winReloaded = KasugaiWindowState.load(from: winTemp.path)
        let clampedOffscreen = KasugaiWindowState(
            frameX: 5000,
            frameY: 3000,
            frameWidth: 1600,
            frameHeight: 1000,
            isFullScreen: false,
            sidebarCollapsed: false,
            sidebarWidth: 256,
            rightPaneCollapsed: true,
            rightPaneWidth: 540,
            terminalCollapsed: true,
            terminalHeight: 220
        ).clampedFrame(in: [NSRect(x: 0, y: 0, width: 1440, height: 900)])
        let winStateOk =
            winSaved
            && winReloaded == sampleWin
            && clampedOffscreen.width == 1440
            && clampedOffscreen.height == 900
            && clampedOffscreen.minX == 0
            && clampedOffscreen.minY == 0

        let tabsTemp = fm.temporaryDirectory.appendingPathComponent(
            "kasugai-right-pane-tabs-\(UUID().uuidString).json"
        )
        defer { try? fm.removeItem(at: tabsTemp) }
        var tabsStore = KasugaiRightPaneTabStore.empty
        let samplePane = KasugaiPersistedThreadRightPane(
            tabs: [
                KasugaiPersistedRightPaneTab(kind: .diff, path: nil, url: nil, title: nil),
                KasugaiPersistedRightPaneTab(
                    kind: .browser,
                    path: nil,
                    url: "http://localhost:3000/app",
                    title: "localhost:3000"
                ),
            ],
            activeIndex: 1,
            fileRootPath: "/tmp"
        )
        tabsStore.setPane(samplePane, for: 42)
        let tabsSaved = tabsStore.save(to: tabsTemp.path)
        var reloadedTabs = KasugaiRightPaneTabStore.load(from: tabsTemp.path)
        let tabsMatched = reloadedTabs.pane(for: 42) == samplePane
        reloadedTabs.setPane(nil, for: 42)
        let tabsCleared = reloadedTabs.pane(for: 42) == nil

        return reloaded == custom
            && policyChecks
            && !KasugaiAppSettings.defaultValue.allowExternalBrowser
            && KasugaiAppSettings.defaultValue.toolApprovalPolicy == .alwaysAllow
            && !KasugaiAppSettings.defaultValue.enableMobileBridge
            && draftMatches
            && draftCleared
            && winStateOk
            && tabsSaved
            && tabsMatched
            && tabsCleared
            && prodDir.lastPathComponent == "Kasugai"
            && devDir.lastPathComponent == "Kasugai-Dev"
            && customDir.path == "/tmp/kasugai-custom-data"
    }
}
