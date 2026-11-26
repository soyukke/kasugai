import AppKit
import Foundation
import WebKit

struct RegisteredMedia: Codable {
    let url: String
    let kind: String
    let name: String
}

struct DiffImagePair: Codable {
    let beforeUrl: String?
    let afterUrl: String?
    let beforeSize: String?
    let afterSize: String?

    enum CodingKeys: String, CodingKey {
        case beforeUrl = "before_url"
        case afterUrl = "after_url"
        case beforeSize = "before_size"
        case afterSize = "after_size"
    }
}

struct FileLinkTarget: Equatable {
    let path: String
    let lineStart: Int?
    let lineEnd: Int?

    var lineRange: ClosedRange<Int>? {
        guard let start = lineStart, start > 0 else {
            return nil
        }
        let end = max(start, lineEnd ?? start)
        return start...end
    }

    static func parse(_ url: URL) -> FileLinkTarget? {
        guard url.scheme?.lowercased() == "file" else {
            return nil
        }
        let path = url.path
        guard !path.isEmpty else {
            return nil
        }
        let (lineStart, lineEnd) = parseLineFragment(url.fragment)
        return FileLinkTarget(path: path, lineStart: lineStart, lineEnd: lineEnd)
    }

    static func parse(href: String) -> FileLinkTarget? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        if let url = URL(string: trimmed), let parsed = parse(url) {
            return parsed
        }
        let stripped: String
        if trimmed.hasPrefix("file://") {
            stripped = String(trimmed.dropFirst("file://".count))
        } else if trimmed.hasPrefix("/") {
            stripped = trimmed
        } else {
            return nil
        }
        let parts = stripped.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let rawPath = String(parts[0])
        let decodedPath = rawPath.removingPercentEncoding ?? rawPath
        guard decodedPath.hasPrefix("/") else {
            return nil
        }
        let fragment = parts.count == 2 ? String(parts[1]) : nil
        let (lineStart, lineEnd) = parseLineFragment(fragment)
        return FileLinkTarget(path: decodedPath, lineStart: lineStart, lineEnd: lineEnd)
    }

    private static func parseLineFragment(_ fragment: String?) -> (Int?, Int?) {
        guard let raw = fragment?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty
        else {
            return (nil, nil)
        }
        let parts = raw.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        func parseNumber(_ sub: Substring) -> Int? {
            let trimmed = sub.hasPrefix("L") || sub.hasPrefix("l") ? sub.dropFirst() : sub
            guard !trimmed.isEmpty, let value = Int(trimmed), value > 0 else {
                return nil
            }
            return value
        }
        guard let start = parseNumber(parts[0]) else {
            return (nil, nil)
        }
        if parts.count == 2, let end = parseNumber(parts[1]) {
            return (start, max(start, end))
        }
        return (start, start)
    }
}

struct FilePreviewPayload: Codable {
    let path: String
    let name: String
    let kind: String
    let sizeLabel: String
    let text: String?
    let mediaUrl: String?
    let highlightLineStart: Int?
    let highlightLineEnd: Int?

    enum CodingKeys: String, CodingKey {
        case path
        case name
        case kind
        case sizeLabel = "size_label"
        case text
        case mediaUrl = "media_url"
        case highlightLineStart = "highlight_line_start"
        case highlightLineEnd = "highlight_line_end"
    }
}

extension Notification.Name {
    static let kasugaiViewRendererDidChange = Notification.Name("KasugaiViewRendererDidChange")
}

enum KasugaiViewRenderer {
    static let scheme = "kasugai-view"
    static let host = "app"
    static let allowedAssets = ["index.html", "kasugai-view.css", "kasugai-view.js"]

    static func resolveFolder(
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        if let override = env["KASUGAI_VIEW_RENDERER_DIR"], !override.isEmpty {
            let candidate = URL(fileURLWithPath: override, isDirectory: true)
                .resolvingSymlinksInPath()
                .standardizedFileURL
            if FileManager.default.fileExists(
                atPath: candidate.appendingPathComponent("index.html").path
            ) {
                return candidate
            }
        }
        let executableDir = Bundle.main.executableURL?.deletingLastPathComponent()
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent("ViewRenderer", isDirectory: true),
            executableDir?.appendingPathComponent("ViewRenderer", isDirectory: true),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
                .appendingPathComponent("view-renderer", isDirectory: true),
        ]
        return candidates.compactMap { $0 }.first {
            FileManager.default.fileExists(atPath: $0.appendingPathComponent("index.html").path)
        }
    }

    static let folder: URL? = resolveFolder()

    static func isLiveReloadEnabled(
        env: [String: String] = ProcessInfo.processInfo.environment,
        resolvedFolder: URL? = folder
    ) -> Bool {
        guard env["KASUGAI_SELF_TEST"] != "1",
            let override = env["KASUGAI_VIEW_RENDERER_DIR"],
            !override.isEmpty,
            let resolvedFolder
        else {
            return false
        }
        let expected = URL(fileURLWithPath: override, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        return resolvedFolder.resolvingSymlinksInPath().standardizedFileURL.path == expected.path
    }

    static var isLiveReloadEnabled: Bool {
        isLiveReloadEnabled()
    }

    static func isAllowedAsset(_ parts: [String]) -> Bool {
        parts.count == 1 && allowedAssets.contains(parts[0])
    }

    static func mediaKind(forExtension ext: String) -> String? {
        switch ext.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "svg", "avif", "bmp", "ico", "heic":
            return "image"
        case "mp3", "m4a", "wav", "ogg", "aac", "flac", "opus", "aiff", "aif":
            return "audio"
        case "mp4", "mov", "webm", "m4v", "ogv":
            return "video"
        default:
            return nil
        }
    }

    static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "html":
            return "text/html; charset=utf-8"
        case "css":
            return "text/css; charset=utf-8"
        case "js":
            return "text/javascript; charset=utf-8"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "svg":
            return "image/svg+xml"
        case "avif":
            return "image/avif"
        case "bmp":
            return "image/bmp"
        case "ico":
            return "image/x-icon"
        case "heic":
            return "image/heic"
        case "mp3":
            return "audio/mpeg"
        case "m4a":
            return "audio/mp4"
        case "wav":
            return "audio/wav"
        case "ogg":
            return "audio/ogg"
        case "aac":
            return "audio/aac"
        case "flac":
            return "audio/flac"
        case "opus":
            return "audio/opus"
        case "aiff", "aif":
            return "audio/aiff"
        case "mp4":
            return "video/mp4"
        case "mov":
            return "video/quicktime"
        case "webm":
            return "video/webm"
        case "m4v":
            return "video/x-m4v"
        case "ogv":
            return "video/ogg"
        default:
            return "application/octet-stream"
        }
    }

    static func mimeType(_ file: URL) -> String {
        mimeType(forExtension: file.pathExtension)
    }

    static func parseByteRange(_ header: String?, totalLength: Int) -> Range<Int>? {
        guard let header, totalLength > 0, header.hasPrefix("bytes=") else {
            return nil
        }
        let spec =
            String(header.dropFirst("bytes=".count))
            .split(separator: ",")
            .first
            .map(String.init) ?? ""
        let parts = spec.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else {
            return nil
        }
        if parts[0].isEmpty {
            guard let suffix = Int(parts[1]), suffix > 0 else {
                return nil
            }
            let start = max(0, totalLength - suffix)
            return start..<totalLength
        }
        guard let start = Int(parts[0]), start >= 0, start < totalLength else {
            return nil
        }
        let end: Int
        if parts[1].isEmpty {
            end = totalLength - 1
        } else if let parsedEnd = Int(parts[1]) {
            end = min(parsedEnd, totalLength - 1)
        } else {
            return nil
        }
        guard start <= end else {
            return nil
        }
        return start..<(end + 1)
    }

    static func confined(_ parts: [String], in folder: URL) -> URL? {
        guard !parts.isEmpty,
            !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
        else {
            return nil
        }
        let base = folder.resolvingSymlinksInPath().standardizedFileURL
        let file = parts.reduce(base) { $0.appendingPathComponent($1) }
            .resolvingSymlinksInPath().standardizedFileURL
        guard file.path.hasPrefix(base.path + "/") else {
            return nil
        }
        return file
    }

    static func compileContentRules(_ completion: @escaping (WKContentRuleList?) -> Void) {
        if let cached = compiledRules {
            completion(cached)
            return
        }
        let source = """
            [{"trigger":{"url-filter":".*"},"action":{"type":"block"}},
             {"trigger":{"url-filter":"^\(scheme):"},"action":{"type":"ignore-previous-rules"}}]
            """
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "kasugai-view-only",
            encodedContentRuleList: source
        ) { rules, _ in
            compiledRules = rules
            completion(rules)
        }
    }

    private static var compiledRules: WKContentRuleList?
}

final class ViewRendererHotReloader {
    static let shared = ViewRendererHotReloader()

    private let queue = DispatchQueue(label: "dev.soyukke.kasugai.view-renderer-watch")
    private var watchedFolder: URL?
    private var directorySource: DispatchSourceFileSystemObject?
    private var assetSources: [DispatchSourceFileSystemObject] = []
    private var pendingWorkItem: DispatchWorkItem?
    private var lastSignature: String = ""

    func startIfNeeded(folder: URL) {
        let normalized = folder.resolvingSymlinksInPath().standardizedFileURL
        queue.async { [weak self] in
            guard let self else {
                return
            }
            if self.watchedFolder?.path == normalized.path {
                return
            }
            self.stopLocked()
            self.watchedFolder = normalized
            self.lastSignature = Self.computeSignature(in: normalized)
            self.armWatchersLocked(in: normalized)
        }
    }

    static func computeSignature(in folder: URL) -> String {
        let fm = FileManager.default
        return KasugaiViewRenderer.allowedAssets.map { name in
            let path = folder.appendingPathComponent(name).path
            guard let attrs = try? fm.attributesOfItem(atPath: path) else {
                return "\(name):missing"
            }
            let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            let inode = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
            return "\(name):\(mtime):\(size):\(inode)"
        }.joined(separator: "|")
    }

    private func stopLocked() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        directorySource?.cancel()
        directorySource = nil
        for source in assetSources {
            source.cancel()
        }
        assetSources.removeAll()
        watchedFolder = nil
    }

    private func armWatchersLocked(in folder: URL) {
        if directorySource == nil {
            directorySource = makeSource(path: folder.path)
        }
        rearmAssetSourcesLocked(in: folder)
    }

    private func rearmAssetSourcesLocked(in folder: URL) {
        for source in assetSources {
            source.cancel()
        }
        assetSources.removeAll()
        for name in KasugaiViewRenderer.allowedAssets {
            let path = folder.appendingPathComponent(name).path
            if let source = makeSource(path: path) {
                assetSources.append(source)
            }
        }
    }

    private func makeSource(path: String) -> DispatchSourceFileSystemObject? {
        let fd = Darwin.open(path, O_EVTONLY)
        guard fd >= 0 else {
            return nil
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete, .attrib],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            self?.scheduleCheckLocked()
        }
        source.setCancelHandler {
            Darwin.close(fd)
        }
        source.resume()
        return source
    }

    private func scheduleCheckLocked() {
        pendingWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.evaluateChangeLocked()
        }
        pendingWorkItem = item
        queue.asyncAfter(deadline: .now() + .milliseconds(80), execute: item)
    }

    private func evaluateChangeLocked() {
        guard let folder = watchedFolder else {
            return
        }
        let nextSignature = Self.computeSignature(in: folder)
        rearmAssetSourcesLocked(in: folder)
        guard nextSignature != lastSignature else {
            return
        }
        lastSignature = nextSignature
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .kasugaiViewRendererDidChange,
                object: nil
            )
        }
    }
}

final class KasugaiViewSchemeHandler: NSObject, WKURLSchemeHandler {
    private struct MemoryAsset {
        let data: Data
        let mimeType: String
    }

    let rendererFolder: URL
    private var attachmentsByToken: [String: URL] = [:]
    private var tokenByPath: [String: String] = [:]
    private var memoryAssetsByToken: [String: MemoryAsset] = [:]
    private var memoryTokenByKey: [String: String] = [:]

    init(rendererFolder: URL) {
        self.rendererFolder = rendererFolder
    }

    func registerMediaAttachment(path: String) -> RegisteredMedia? {
        let candidate = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        guard let kind = KasugaiViewRenderer.mediaKind(forExtension: candidate.pathExtension) else {
            return nil
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
            !isDirectory.boolValue
        else {
            return nil
        }
        let token: String
        if let existing = tokenByPath[candidate.path] {
            token = existing
        } else {
            token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            attachmentsByToken[token] = candidate
            tokenByPath[candidate.path] = token
        }
        return RegisteredMedia(
            url: "\(KasugaiViewRenderer.scheme)://\(KasugaiViewRenderer.host)/attachment/\(token)",
            kind: kind,
            name: candidate.lastPathComponent
        )
    }

    func registerMemoryMedia(
        cacheKey: String,
        data: Data,
        fileExtension: String,
        name: String
    ) -> RegisteredMedia? {
        guard !data.isEmpty,
            let kind = KasugaiViewRenderer.mediaKind(forExtension: fileExtension)
        else {
            return nil
        }
        let token: String
        if let existing = memoryTokenByKey[cacheKey] {
            token = existing
        } else {
            token = "mem-" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            memoryTokenByKey[cacheKey] = token
        }
        memoryAssetsByToken[token] = MemoryAsset(
            data: data,
            mimeType: KasugaiViewRenderer.mimeType(forExtension: fileExtension)
        )
        return RegisteredMedia(
            url: "\(KasugaiViewRenderer.scheme)://\(KasugaiViewRenderer.host)/attachment/\(token)",
            kind: kind,
            name: name
        )
    }

    func file(for url: URL) -> URL? {
        guard url.scheme == KasugaiViewRenderer.scheme,
            url.host == KasugaiViewRenderer.host
        else {
            return nil
        }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: false)
            .dropFirst()
            .map(String.init)
        if parts.count == 2 && parts[0] == "attachment" {
            return attachmentsByToken[parts[1]]
        }
        guard KasugaiViewRenderer.isAllowedAsset(parts) else {
            return nil
        }
        return KasugaiViewRenderer.confined(parts, in: rendererFolder)
    }

    private func memoryAsset(for url: URL) -> MemoryAsset? {
        guard url.scheme == KasugaiViewRenderer.scheme,
            url.host == KasugaiViewRenderer.host
        else {
            return nil
        }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: false)
            .dropFirst()
            .map(String.init)
        guard parts.count == 2 && parts[0] == "attachment" else {
            return nil
        }
        return memoryAssetsByToken[parts[1]]
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else {
            task.didFailWithError(URLError(.badURL))
            return
        }
        let resolvedData: Data?
        let resolvedMime: String?
        if let mem = memoryAsset(for: url) {
            resolvedData = mem.data
            resolvedMime = mem.mimeType
        } else if let target = file(for: url), let diskData = try? Data(contentsOf: target) {
            resolvedData = diskData
            resolvedMime = KasugaiViewRenderer.mimeType(target)
        } else {
            resolvedData = nil
            resolvedMime = nil
        }
        var headers = ["Cache-Control": "no-store", "Accept-Ranges": "bytes"]
        var statusCode = 404
        var body = Data()

        if let fullData = resolvedData, let mime = resolvedMime {
            headers["Content-Type"] = mime
            let rangeHeader = task.request.value(forHTTPHeaderField: "Range")
            if let slice = KasugaiViewRenderer.parseByteRange(
                rangeHeader,
                totalLength: fullData.count
            ) {
                statusCode = 206
                body = fullData.subdata(in: slice)
                headers["Content-Range"] =
                    "bytes \(slice.lowerBound)-\(slice.upperBound - 1)/\(fullData.count)"
                headers["Content-Length"] = "\(body.count)"
            } else {
                statusCode = 200
                body = fullData
                headers["Content-Length"] = "\(body.count)"
            }
        }
        guard
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )
        else {
            task.didFailWithError(URLError(.cannotParseResponse))
            return
        }
        task.didReceive(response)
        task.didReceive(body)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: SandboxedChatWebView?

    init(target: SandboxedChatWebView) {
        self.target = target
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        target?.handleScriptMessage(name: message.name, body: message.body)
    }
}

struct KasugaiThreadLinkInfo: Encodable, Equatable {
    let id: Int64
    let title: String
    let projectName: String
    let status: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case projectName = "project_name"
        case status
    }
}

final class SandboxedChatWebView: NSView, WKNavigationDelegate {
    enum RenderMode {
        case chat
        case diff
        case filePreview
    }

    var onOpenFileLink: ((FileLinkTarget) -> Void)?
    var onOpenThread: ((Int64) -> Void)?

    private var renderMode: RenderMode
    private var webView: WKWebView?
    private var schemeHandler: KasugaiViewSchemeHandler?
    private var compiledContentRules: WKContentRuleList?
    private var renderGeneration: UInt64 = 0
    private var syncState: WebViewSyncState = .compilingRulesEmpty
    private var latestPayloadJSON: String = "null"
    private var latestMediaMapJSON: String = "{}"
    private var latestThreadIndexJSON: String = "{}"
    private var latestDiffMediaMapJSON: String = "{}"
    private var pendingThread: KasugaiThread?
    private var pendingDiffReport: GitDiffReport?
    private var pendingPreviewPath: String?
    private var pendingPreviewLineRange: ClosedRange<Int>?
    private var pendingDiffFocusPath: String?
    private var currentPalette: KasugaiPalette = .kasugai
    private let rendererFolder: URL?
    private var hotReloadObserver: NSObjectProtocol?
    private var lastRequestedChatKey: String = ""
    private var pendingThreadTransition: String = ""

    override convenience init(frame frameRect: NSRect) {
        self.init(frame: frameRect, mode: .chat)
    }

    init(frame frameRect: NSRect, mode: RenderMode) {
        self.renderMode = mode
        self.rendererFolder = KasugaiViewRenderer.folder
        super.init(frame: frameRect)
        wantsLayer = true
        guard let rendererFolder else {
            applyTransition(.rulesFailed, rules: nil)
            return
        }
        if KasugaiViewRenderer.isLiveReloadEnabled {
            ViewRendererHotReloader.shared.startIfNeeded(folder: rendererFolder)
            hotReloadObserver = NotificationCenter.default.addObserver(
                forName: .kasugaiViewRendererDidChange,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.reloadRendererAssets()
            }
        }
        KasugaiViewRenderer.compileContentRules { [weak self] rules in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                if let rules {
                    self.compiledContentRules = rules
                    self.installWebView(rendererFolder: rendererFolder, rules: rules)
                    self.applyTransition(.rulesCompiled, rules: rules)
                } else {
                    self.applyTransition(.rulesFailed, rules: nil)
                }
            }
        }
    }

    deinit {
        teardownWebView()
        if let hotReloadObserver {
            NotificationCenter.default.removeObserver(hotReloadObserver)
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    func reloadRendererAssets() {
        lastRequestedChatKey = ""
        if let rendererFolder, let compiledContentRules, syncState != .blocked {
            installWebView(rendererFolder: rendererFolder, rules: compiledContentRules)
        }
        applyTransition(.processTerminated, rules: nil)
    }

    func update(palette: KasugaiPalette) {
        currentPalette = palette
        let theme = KasugaiThemeTokens.resolve(
            palette: palette, appearance: effectiveAppearance)
        layer?.backgroundColor = theme.canvasBg.cgColor
        syncAppearance()
    }

    private struct ChatRenderFingerprint: Encodable {
        let id: Int64
        let status: String
        let provider: String
        let providerName: String
        let model: String
        let activeTurnId: Int64
        let streamingText: String
        let lastError: String
        let pendingApproval: KasugaiPendingApproval
        let activities: [KasugaiActivity]
        let messages: [KasugaiMessage]
        let queue: [KasugaiQueuedTurn]
        let mediaMapJSON: String
        let threadIndexJSON: String
    }

    private func makeChatRenderKey(thread: KasugaiThread?) -> String {
        guard let thread else {
            return "null"
        }
        let fp = ChatRenderFingerprint(
            id: thread.id,
            status: thread.status,
            provider: thread.provider,
            providerName: thread.providerName,
            model: thread.model,
            activeTurnId: thread.activeTurnId,
            streamingText: thread.streamingText,
            lastError: thread.lastError,
            pendingApproval: thread.pendingApproval,
            activities: thread.activities,
            messages: thread.messages,
            queue: thread.queue,
            mediaMapJSON: latestMediaMapJSON,
            threadIndexJSON: latestThreadIndexJSON
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(fp), let key = String(data: data, encoding: .utf8) {
            return key
        }
        return latestPayloadJSON + "|" + latestMediaMapJSON + "|" + latestThreadIndexJSON
    }

    func update(
        thread: KasugaiThread?,
        threadIndex: [String: KasugaiThreadLinkInfo]? = nil,
        transition: KasugaiSlideDirection? = nil
    ) {
        let wasChat = renderMode == .chat
        renderMode = .chat
        pendingThread = thread
        pendingPreviewPath = nil
        if let transition {
            pendingThreadTransition =
                KasugaiInteractiveMotion.shouldAnimate ? transition.rawValue : "none"
        }
        if let thread,
            let data = try? JSONEncoder().encode(thread),
            let encoded = String(data: data, encoding: .utf8)
        {
            latestPayloadJSON = encoded
        } else {
            latestPayloadJSON = "null"
        }
        if let threadIndex {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            if let data = try? encoder.encode(threadIndex),
                let encoded = String(data: data, encoding: .utf8)
            {
                latestThreadIndexJSON = encoded
            } else {
                latestThreadIndexJSON = "{}"
            }
        }
        refreshMediaMap()
        let nextKey = makeChatRenderKey(thread: thread)
        if wasChat && nextKey == lastRequestedChatKey && !lastRequestedChatKey.isEmpty
            && syncState != .compilingRulesEmpty && syncState != .blocked
        {
            return
        }
        lastRequestedChatKey = nextKey
        applyTransition(.snapshotRequested, rules: nil)
    }

    func update(diffReport: GitDiffReport?, focusFile: String? = nil) {
        renderMode = .diff
        lastRequestedChatKey = ""
        pendingThread = nil
        pendingDiffReport = diffReport
        pendingPreviewPath = nil
        pendingDiffFocusPath = focusFile
        if let diffReport,
            let data = try? JSONEncoder().encode(diffReport),
            let encoded = String(data: data, encoding: .utf8)
        {
            latestPayloadJSON = encoded
        } else {
            latestPayloadJSON = "null"
        }
        refreshDiffMediaMap()
        applyTransition(.snapshotRequested, rules: nil)
    }

    func update(filePreviewPath: String?, lineRange: ClosedRange<Int>? = nil) {
        renderMode = .filePreview
        lastRequestedChatKey = ""
        pendingThread = nil
        pendingPreviewPath = filePreviewPath
        pendingPreviewLineRange = lineRange
        rebuildFilePreviewPayload()
        applyTransition(.snapshotRequested, rules: nil)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        let theme = KasugaiThemeTokens.resolve(
            palette: currentPalette, appearance: effectiveAppearance)
        layer?.backgroundColor = theme.canvasBg.cgColor
        syncAppearance()
    }

    private func rebuildFilePreviewPayload() {
        guard let path = pendingPreviewPath, !path.isEmpty else {
            latestPayloadJSON = "null"
            return
        }
        let payload = buildFilePreviewPayload(path: path, lineRange: pendingPreviewLineRange)
        if let data = try? JSONEncoder().encode(payload),
            let encoded = String(data: data, encoding: .utf8)
        {
            latestPayloadJSON = encoded
        } else {
            latestPayloadJSON = "null"
        }
    }

    private func buildFilePreviewPayload(
        path: String,
        lineRange: ClosedRange<Int>?
    ) -> FilePreviewPayload {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let byteSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let sizeLabel = ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)

        if let media = schemeHandler?.registerMediaAttachment(path: path) {
            return FilePreviewPayload(
                path: path,
                name: name,
                kind: media.kind,
                sizeLabel: sizeLabel,
                text: nil,
                mediaUrl: media.url,
                highlightLineStart: nil,
                highlightLineEnd: nil
            )
        }

        let maxBytes = 262_144
        if let handle = FileHandle(forReadingAtPath: path) {
            defer { try? handle.close() }
            let data = handle.readData(ofLength: maxBytes)
            if !data.contains(0), let text = String(data: data, encoding: .utf8) {
                let ext = url.pathExtension.lowercased()
                let isMarkdown = ext == "md" || ext == "markdown"
                let suffix = byteSize > Int64(maxBytes) ? "\n…（先頭 256 KB のみ表示）" : ""
                return FilePreviewPayload(
                    path: path,
                    name: name,
                    kind: isMarkdown ? "markdown" : "text",
                    sizeLabel: sizeLabel,
                    text: text + suffix,
                    mediaUrl: nil,
                    highlightLineStart: lineRange?.lowerBound,
                    highlightLineEnd: lineRange?.upperBound
                )
            }
        }

        return FilePreviewPayload(
            path: path,
            name: name,
            kind: "binary",
            sizeLabel: sizeLabel,
            text: nil,
            mediaUrl: nil,
            highlightLineStart: nil,
            highlightLineEnd: nil
        )
    }

    private static func extractMarkdownMediaTargets(from text: String) -> [String] {
        var targets: [String] = []
        if let linkRegex = try? NSRegularExpression(
            pattern: "!?\\[[^\\]]*\\]\\(([^)\\s]+)\\)",
            options: []
        ) {
            let range = NSRange(location: 0, length: (text as NSString).length)
            for match in linkRegex.matches(in: text, options: [], range: range)
            where match.numberOfRanges >= 2 {
                let r = match.range(at: 1)
                if r.location != NSNotFound {
                    targets.append((text as NSString).substring(with: r))
                }
            }
        }
        if let compareRegex = try? NSRegularExpression(
            pattern: "(?m)^\\s*(?:before|after|変更前|変更後)\\s*:\\s*(\\S+)",
            options: [.caseInsensitive]
        ) {
            let range = NSRange(location: 0, length: (text as NSString).length)
            for match in compareRegex.matches(in: text, options: [], range: range)
            where match.numberOfRanges >= 2 {
                let r = match.range(at: 1)
                if r.location != NSNotFound {
                    targets.append((text as NSString).substring(with: r))
                }
            }
        }
        return targets
    }

    private static func resolveLocalMediaPath(
        rawTarget: String,
        workspaceCwd: String
    ) -> String? {
        let trimmed = rawTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://")
            || lower.hasPrefix("mailto:") || lower.hasPrefix("data:")
            || lower.hasPrefix("kasugai-view:")
        {
            return nil
        }
        if lower.hasPrefix("file://") {
            if let url = URL(string: trimmed), url.isFileURL {
                return url.path
            }
            let stripped = String(trimmed.dropFirst("file://".count))
            let base = stripped.split(separator: "#", maxSplits: 1).first.map(String.init) ?? ""
            let decoded = base.removingPercentEncoding ?? base
            return decoded.hasPrefix("/") ? decoded : nil
        }
        let withoutFragment =
            trimmed.split(separator: "#", maxSplits: 1).first.map(String.init) ?? trimmed
        let decoded = withoutFragment.removingPercentEncoding ?? withoutFragment
        if decoded.hasPrefix("/") {
            return decoded
        }
        if decoded.hasPrefix("~/") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return home + "/" + String(decoded.dropFirst(2))
        }
        guard !workspaceCwd.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: workspaceCwd, isDirectory: true)
            .appendingPathComponent(decoded)
            .standardizedFileURL
            .path
    }

    private func refreshMediaMap() {
        guard let handler = schemeHandler, let thread = pendingThread else {
            latestMediaMapJSON = "{}"
            return
        }
        let cwd = thread.workspace.effectiveCwd
        var mapped: [String: RegisteredMedia] = [:]

        func registerRawTarget(_ target: String) {
            guard mapped[target] == nil,
                let resolved = Self.resolveLocalMediaPath(rawTarget: target, workspaceCwd: cwd),
                let entry = handler.registerMediaAttachment(path: resolved)
            else {
                return
            }
            mapped[target] = entry
            if mapped[resolved] == nil {
                mapped[resolved] = entry
            }
        }

        for message in thread.messages {
            for path in message.attachments {
                registerRawTarget(path)
            }
            for target in Self.extractMarkdownMediaTargets(from: message.text) {
                registerRawTarget(target)
            }
        }
        for queued in thread.queue {
            for path in queued.attachments {
                registerRawTarget(path)
            }
            for target in Self.extractMarkdownMediaTargets(from: queued.text) {
                registerRawTarget(target)
            }
        }
        if !thread.streamingText.isEmpty {
            for target in Self.extractMarkdownMediaTargets(from: thread.streamingText) {
                registerRawTarget(target)
            }
        }
        if let data = try? JSONEncoder().encode(mapped),
            let encoded = String(data: data, encoding: .utf8)
        {
            latestMediaMapJSON = encoded
        } else {
            latestMediaMapJSON = "{}"
        }
    }

    private func refreshDiffMediaMap() {
        guard let handler = schemeHandler, let report = pendingDiffReport, report.isGitRepo else {
            latestDiffMediaMapJSON = "{}"
            return
        }
        let baseURL = URL(fileURLWithPath: report.directory, isDirectory: true)
        var pairs: [String: DiffImagePair] = [:]
        for entry in report.files {
            let fileURL = baseURL.appendingPathComponent(entry.path)
            let ext = fileURL.pathExtension
            guard KasugaiViewRenderer.mediaKind(forExtension: ext) == "image" else {
                continue
            }
            var beforeUrl: String?
            var beforeSize: String?
            if entry.status != "?" && entry.status != "A" {
                if let headData = GitWorkspace.gitObjectData(
                    in: report.directory,
                    ref: "HEAD",
                    relativePath: entry.path
                ),
                    let registered = handler.registerMemoryMedia(
                        cacheKey: "HEAD:\(report.directory):\(entry.path):\(headData.count)",
                        data: headData,
                        fileExtension: ext,
                        name: "HEAD · \(fileURL.lastPathComponent)"
                    )
                {
                    beforeUrl = registered.url
                    beforeSize = ByteCountFormatter.string(
                        fromByteCount: Int64(headData.count),
                        countStyle: .file
                    )
                }
            }
            var afterUrl: String?
            var afterSize: String?
            if entry.status != "D",
                let registered = handler.registerMediaAttachment(path: fileURL.path)
            {
                afterUrl = registered.url
                if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                    let bytes = (attrs[.size] as? NSNumber)?.int64Value
                {
                    afterSize = ByteCountFormatter.string(
                        fromByteCount: bytes,
                        countStyle: .file
                    )
                }
            }
            if beforeUrl != nil || afterUrl != nil {
                pairs[entry.path] = DiffImagePair(
                    beforeUrl: beforeUrl,
                    afterUrl: afterUrl,
                    beforeSize: beforeSize,
                    afterSize: afterSize
                )
            }
        }
        if let data = try? JSONEncoder().encode(pairs),
            let encoded = String(data: data, encoding: .utf8)
        {
            latestDiffMediaMapJSON = encoded
        } else {
            latestDiffMediaMapJSON = "{}"
        }
    }

    private func teardownWebView() {
        renderGeneration &+= 1
        guard let existing = webView else {
            return
        }
        existing.stopLoading()
        existing.navigationDelegate = nil
        existing.configuration.userContentController.removeScriptMessageHandler(
            forName: "kasugaiLink"
        )
        existing.removeFromSuperview()
        webView = nil
        schemeHandler = nil
    }

    private func installWebView(rendererFolder: URL, rules: WKContentRuleList) {
        teardownWebView()
        let handler = KasugaiViewSchemeHandler(rendererFolder: rendererFolder)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(handler, forURLScheme: KasugaiViewRenderer.scheme)
        config.userContentController.add(rules)
        config.userContentController.add(
            WeakScriptMessageHandler(target: self),
            name: "kasugaiLink"
        )
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.suppressesIncrementalRendering = true

        let view = WKWebView(frame: bounds, configuration: config)
        view.autoresizingMask = [.width, .height]
        view.navigationDelegate = self
        view.allowsMagnification = false
        view.allowsBackForwardNavigationGestures = false
        addSubview(view)
        self.schemeHandler = handler
        self.webView = view
        refreshMediaMap()
        if renderMode == .diff {
            refreshDiffMediaMap()
        } else if renderMode == .filePreview {
            rebuildFilePreviewPayload()
        }
    }

    private func applyTransition(_ event: WebViewSyncEvent, rules: WKContentRuleList?) {
        _ = rules
        let step = WebViewSyncMachine.advance(syncState, event)
        syncState = step.state

        switch step.outcome {
        case .noop, .bufferSnapshot, .renderComplete:
            break
        case .pageReady:
            syncAppearance()
        case .blockFailClosed:
            teardownWebView()
        case .loadPage, .reloadPage:
            loadRendererPage()
        case .renderNow:
            dispatchRenderToWebView()
        }
    }

    private func loadRendererPage() {
        guard let webView,
            let url = URL(
                string: "\(KasugaiViewRenderer.scheme)://\(KasugaiViewRenderer.host)/index.html"
            )
        else {
            return
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        webView.load(request)
    }

    private func currentThemeName() -> String {
        let match = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        return match == .aqua ? "light" : "dark"
    }

    private func syncAppearance() {
        guard
            syncState == .readyIdle || syncState == .renderingClean || syncState == .renderingStale
        else {
            return
        }
        let theme = currentThemeName()
        let palette = currentPalette.rawValue
        webView?.callAsyncJavaScript(
            "window.kasugaiView && window.kasugaiView.setAppearance(theme, palette)",
            arguments: ["theme": theme, "palette": palette],
            in: nil,
            in: .page
        ) { _ in }
    }

    private func dispatchRenderToWebView() {
        guard let webView else {
            return
        }
        renderGeneration &+= 1
        let expectedGeneration = renderGeneration
        let targetWebView = webView
        let theme = currentThemeName()
        let palette = currentPalette.rawValue
        let completeRender: () -> Void = { [weak self] in
            DispatchQueue.main.async {
                guard let self,
                    self.webView === targetWebView,
                    self.renderGeneration == expectedGeneration
                else {
                    return
                }
                self.applyTransition(.renderCompleted, rules: nil)
            }
        }
        switch renderMode {
        case .chat:
            refreshMediaMap()
            let payload = latestPayloadJSON
            let mediaMap = latestMediaMapJSON
            let threadIndex = latestThreadIndexJSON
            let transitionDir =
                KasugaiInteractiveMotion.shouldAnimate ? pendingThreadTransition : "none"
            pendingThreadTransition = ""
            webView.callAsyncJavaScript(
                """
                if (window.kasugaiView) {
                    window.kasugaiView.setAppearance(theme, palette);
                    window.kasugaiView.renderThread(payload, media, transitionDir, threadIndex);
                }
                """,
                arguments: [
                    "theme": theme,
                    "palette": palette,
                    "payload": payload,
                    "media": mediaMap,
                    "transitionDir": transitionDir,
                    "threadIndex": threadIndex,
                ],
                in: nil,
                in: .page
            ) { _ in
                completeRender()
            }
        case .diff:
            refreshDiffMediaMap()
            let payload = latestPayloadJSON
            let focusPath = pendingDiffFocusPath ?? ""
            let diffMedia = latestDiffMediaMapJSON
            pendingDiffFocusPath = nil
            webView.callAsyncJavaScript(
                """
                if (window.kasugaiView) {
                    window.kasugaiView.setAppearance(theme, palette);
                    window.kasugaiView.renderDiff(payload, focusPath, diffMedia);
                }
                """,
                arguments: [
                    "theme": theme,
                    "palette": palette,
                    "payload": payload,
                    "focusPath": focusPath,
                    "diffMedia": diffMedia,
                ],
                in: nil,
                in: .page
            ) { _ in
                completeRender()
            }
        case .filePreview:
            rebuildFilePreviewPayload()
            let payload = latestPayloadJSON
            webView.callAsyncJavaScript(
                """
                if (window.kasugaiView) {
                    window.kasugaiView.setAppearance(theme, palette);
                    window.kasugaiView.renderFilePreview(payload);
                }
                """,
                arguments: [
                    "theme": theme,
                    "palette": palette,
                    "payload": payload,
                ],
                in: nil,
                in: .page
            ) { _ in
                completeRender()
            }
        }
    }

    static func parseThreadLinkId(_ raw: String) -> Int64? {
        let prefix = "kasugai-thread://"
        guard raw.lowercased().hasPrefix(prefix) else {
            return nil
        }
        let rest =
            String(raw.dropFirst(prefix.count))
            .split(separator: "/", maxSplits: 1)
            .first
            .map(String.init) ?? ""
        guard let id = Int64(rest), id > 0 else {
            return nil
        }
        return id
    }

    fileprivate func handleScriptMessage(name: String, body: Any) {
        guard name == "kasugaiLink", let href = body as? String else {
            return
        }
        if let threadId = Self.parseThreadLinkId(href) {
            onOpenThread?(threadId)
            return
        }
        guard let target = FileLinkTarget.parse(href: href) else {
            return
        }
        onOpenFileLink?(target)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        guard webView === self.webView else {
            return
        }
        applyTransition(.pageFinished, rules: nil)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === self.webView else {
            return
        }
        applyTransition(.processTerminated, rules: nil)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let clicked = navigationAction.navigationType == .linkActivated
        if clicked, let url = navigationAction.request.url {
            if let threadId = Self.parseThreadLinkId(url.absoluteString) {
                onOpenThread?(threadId)
                decisionHandler(.cancel)
                return
            }
            if let target = FileLinkTarget.parse(url) {
                onOpenFileLink?(target)
                decisionHandler(.cancel)
                return
            }
        }
        let decision = Self.navigationPolicy(
            for: navigationAction.request.url,
            mainFrame: navigationAction.targetFrame?.isMainFrame ?? false,
            clicked: clicked
        )
        decisionHandler(decision)
    }

    static func navigationPolicy(for url: URL?, mainFrame: Bool, clicked: Bool)
        -> WKNavigationActionPolicy
    {
        guard let url else {
            return .cancel
        }
        if clicked {
            if ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(url)
            }
            return .cancel
        }
        let isBundledIndex =
            url.scheme == KasugaiViewRenderer.scheme
            && url.host == KasugaiViewRenderer.host
            && url.path == "/index.html"
        return mainFrame && isBundledIndex ? .allow : .cancel
    }

    static func runSelfTests() -> Bool {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(
            "kasugai-view-test-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fm.removeItem(at: root) }
        let renderer = root.appendingPathComponent("renderer", isDirectory: true)
        let outside = root.appendingPathComponent("secret.txt")
        let sampleImage = root.appendingPathComponent("sample.png")
        let sampleAudio = root.appendingPathComponent("clip.mp3")
        let sampleVideo = root.appendingPathComponent("demo.mp4")
        do {
            try fm.createDirectory(at: renderer, withIntermediateDirectories: true)
            try Data("<!doctype html>".utf8)
                .write(to: renderer.appendingPathComponent("index.html"))
            try Data("body{}".utf8)
                .write(to: renderer.appendingPathComponent("kasugai-view.css"))
            try Data("secret".utf8).write(to: outside)
            try Data([0x89, 0x50, 0x4E, 0x47]).write(to: sampleImage)
            try Data([0x49, 0x44, 0x33, 0x03]).write(to: sampleAudio)
            try Data([0x00, 0x00, 0x00, 0x18]).write(to: sampleVideo)
            try fm.createSymbolicLink(
                at: renderer.appendingPathComponent("kasugai-view.js"),
                withDestinationURL: outside
            )
        } catch {
            return false
        }

        let handler = KasugaiViewSchemeHandler(rendererFolder: renderer)
        let allowed = URL(string: "kasugai-view://app/index.html").flatMap(handler.file(for:))
        let symlinkEscape =
            URL(string: "kasugai-view://app/kasugai-view.js").flatMap(handler.file(for:))
        let traversal =
            URL(string: "kasugai-view://app/../secret.txt").flatMap(handler.file(for:))
        let wrongHost =
            URL(string: "kasugai-view://evil/index.html").flatMap(handler.file(for:))
        let httpBlocked =
            URL(string: "https://example.com/index.html").flatMap(handler.file(for:))

        let unregisteredAttachment =
            URL(string: "kasugai-view://app/attachment/unknown").flatMap(handler.file(for:))
        let rejectedTextAttach = handler.registerMediaAttachment(path: outside.path)
        let registeredImage = handler.registerMediaAttachment(path: sampleImage.path)
        let registeredAudio = handler.registerMediaAttachment(path: sampleAudio.path)
        let registeredVideo = handler.registerMediaAttachment(path: sampleVideo.path)
        let resolvedImage = registeredImage.flatMap { URL(string: $0.url) }.flatMap(
            handler.file(for:))
        let resolvedAudio = registeredAudio.flatMap { URL(string: $0.url) }.flatMap(
            handler.file(for:))
        let resolvedVideo = registeredVideo.flatMap { URL(string: $0.url) }.flatMap(
            handler.file(for:))

        let rangeOk = KasugaiViewRenderer.parseByteRange("bytes=0-3", totalLength: 10) == 0..<4
        let suffixRangeOk =
            KasugaiViewRenderer.parseByteRange("bytes=-2", totalLength: 10) == 8..<10

        let indexURL = URL(string: "kasugai-view://app/index.html")
        let externalURL = URL(string: "https://example.com")
        let fileURL = URL(string: "file:///etc/hosts")

        let resolvedOverride = KasugaiViewRenderer.resolveFolder(
            env: ["KASUGAI_VIEW_RENDERER_DIR": renderer.path]
        )
        let normalizedRenderer = renderer.resolvingSymlinksInPath().standardizedFileURL
        let liveReloadActive = KasugaiViewRenderer.isLiveReloadEnabled(
            env: ["KASUGAI_VIEW_RENDERER_DIR": renderer.path],
            resolvedFolder: resolvedOverride
        )
        let liveReloadOffInTest = !KasugaiViewRenderer.isLiveReloadEnabled(
            env: [
                "KASUGAI_VIEW_RENDERER_DIR": renderer.path,
                "KASUGAI_SELF_TEST": "1",
            ],
            resolvedFolder: resolvedOverride
        )
        let signatureBefore = ViewRendererHotReloader.computeSignature(in: renderer)
        try? Data("body{color:red}".utf8)
            .write(to: renderer.appendingPathComponent("kasugai-view.css"))
        let signatureAfter = ViewRendererHotReloader.computeSignature(in: renderer)

        let parsedFileRange =
            URL(string: "file:///tmp/my%20file.swift#L12-L24").flatMap(FileLinkTarget.parse)
        let parsedSingleLine =
            URL(string: "file:///tmp/justfile#L7").flatMap(FileLinkTarget.parse)
        let parsedPlainFile =
            URL(string: "file:///tmp/justfile").flatMap(FileLinkTarget.parse)
        let parsedExternal = externalURL.flatMap(FileLinkTarget.parse)

        guard allowed != nil,
            symlinkEscape == nil,
            traversal == nil,
            wrongHost == nil,
            httpBlocked == nil,
            unregisteredAttachment == nil,
            rejectedTextAttach == nil,
            registeredImage?.kind == "image",
            registeredAudio?.kind == "audio",
            registeredVideo?.kind == "video",
            resolvedImage != nil,
            resolvedAudio != nil,
            resolvedVideo != nil,
            rangeOk,
            suffixRangeOk,
            resolvedOverride?.path == normalizedRenderer.path,
            liveReloadActive,
            liveReloadOffInTest,
            signatureBefore != signatureAfter,
            parsedFileRange
                == FileLinkTarget(path: "/tmp/my file.swift", lineStart: 12, lineEnd: 24),
            parsedSingleLine == FileLinkTarget(path: "/tmp/justfile", lineStart: 7, lineEnd: 7),
            parsedPlainFile == FileLinkTarget(path: "/tmp/justfile", lineStart: nil, lineEnd: nil),
            parsedExternal == nil,
            navigationPolicy(for: indexURL, mainFrame: true, clicked: false) == .allow,
            navigationPolicy(for: indexURL, mainFrame: false, clicked: false) == .cancel,
            navigationPolicy(for: externalURL, mainFrame: true, clicked: false) == .cancel,
            navigationPolicy(for: fileURL, mainFrame: true, clicked: false) == .cancel,
            navigationPolicy(for: fileURL, mainFrame: true, clicked: true) == .cancel
        else {
            return false
        }

        return verifyLiveWebViewRender()
    }

    private static func verifyLiveWebViewRender() -> Bool {
        _ = NSApplication.shared
        guard KasugaiViewRenderer.folder != nil else {
            return false
        }
        let view = SandboxedChatWebView(
            frame: NSRect(x: 0, y: 0, width: 640, height: 420),
            mode: .chat
        )
        let fillerLines = (1...32).map { "- 項目 \($0): スクロール維持検証テキスト" }.joined(
            separator: "\n")
        let tableMarkdown = """
            疎通確認メッセージ [justfile](file:///tmp/justfile#L10-L20)

            1. 第一項目
               - 子項目 A
               - 子項目 B
            2. 第二項目
               - 子項目 C

            | 項目 | 値 | 備考 |
            |---|---:|---|
            | A | 10 | ok |
            | B | 20 | ok |

            3. 第三項目

            \(fillerLines)
            """
        let sampleThread = KasugaiThread(
            id: 1,
            projectId: 1,
            title: "テスト",
            updatedAtMs: 0,
            status: "idle",
            sessionState: "ready",
            provider: "claude_code",
            providerName: "Claude Code",
            model: "default",
            effort: "medium",
            activeTurnId: 0,
            streamingText: "",
            lastError: "",
            availableModels: [],
            activities: [
                KasugaiActivity(
                    turnId: 1,
                    callId: "thought-1",
                    kind: "thought",
                    title: "思考中",
                    status: "completed",
                    detail: ""
                )
            ],
            pendingApproval: KasugaiPendingApproval(active: false, toolName: "", summary: ""),
            workspace: KasugaiWorkspaceSnapshot(
                mode: "root",
                rootPath: "/tmp",
                worktreePath: "",
                effectiveCwd: "/tmp",
                branch: "main",
                baseRef: "",
                diffFilesChanged: 0,
                diffInsertions: 0,
                diffDeletions: 0
            ),
            messages: [
                KasugaiMessage(
                    id: 1,
                    turnId: 1,
                    role: "assistant",
                    text: tableMarkdown,
                    provider: "claude_code",
                    model: "default",
                    attachments: []
                )
            ],
            queue: []
        )
        view.update(thread: sampleThread)
        let deadline = Date().addingTimeInterval(4.0)
        while view.syncState != .readyIdle && Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.02, false)
        }
        guard view.syncState == .readyIdle, let webView = view.webView else {
            return false
        }

        func evalString(_ script: String) -> String {
            var out = ""
            var done = false
            webView.evaluateJavaScript(script) { val, _ in
                if let s = val as? String {
                    out = s
                } else if let n = val as? NSNumber {
                    out = n.stringValue
                }
                done = true
            }
            let jsDeadline = Date().addingTimeInterval(2.0)
            while !done && Date() < jsDeadline {
                CFRunLoopRunInMode(.defaultMode, 0.02, false)
            }
            return out
        }

        let initialText = evalString("document.getElementById('app')?.textContent || ''")
        let fileLinkHref = evalString(
            "document.querySelector('a.file-link')?.getAttribute('href') || ''")
        let fileLinkText = evalString("document.querySelector('a.file-link')?.textContent || ''")
        var clickedFileTarget: FileLinkTarget?
        view.onOpenFileLink = { target in
            clickedFileTarget = target
        }
        _ = evalString("document.querySelector('a.file-link')?.click(); ''")
        let linkClickDeadline = Date().addingTimeInterval(1.0)
        while clickedFileTarget == nil && Date() < linkClickDeadline {
            CFRunLoopRunInMode(.defaultMode, 0.01, false)
        }
        let firstOlDirectItems = evalString(
            "document.querySelectorAll('.message-body > ol:first-of-type > li').length")
        let secondOlStart = evalString(
            "document.querySelectorAll('.message-body > ol')[1]?.getAttribute('start') || ''")
        let tableHeaders = evalString("document.querySelectorAll('table.md-table thead th').length")
        let tableRows = evalString("document.querySelectorAll('table.md-table tbody tr').length")
        let count1 = evalString("document.getElementById('app')?.dataset.renderCount || '0'")
        _ = evalString(
            "window.__firstArticle = document.querySelector('article.message'); window.scrollTo(0, 24); String(window.scrollY)"
        )
        let scrolledBefore = Double(evalString("window.scrollY")) ?? -1

        let diffOnlyThread = KasugaiThread(
            id: 1,
            projectId: 1,
            title: "テスト",
            updatedAtMs: 99,
            status: "idle",
            sessionState: "ready",
            provider: "claude_code",
            providerName: "Claude Code",
            model: "default",
            effort: "medium",
            activeTurnId: 0,
            streamingText: "",
            lastError: "",
            availableModels: [],
            activities: sampleThread.activities,
            pendingApproval: sampleThread.pendingApproval,
            workspace: KasugaiWorkspaceSnapshot(
                mode: "root",
                rootPath: "/tmp",
                worktreePath: "",
                effectiveCwd: "/tmp",
                branch: "main",
                baseRef: "",
                diffFilesChanged: 5,
                diffInsertions: 42,
                diffDeletions: 7
            ),
            messages: sampleThread.messages,
            queue: []
        )
        view.update(thread: diffOnlyThread)
        let dedupeDeadline = Date().addingTimeInterval(0.15)
        while Date() < dedupeDeadline {
            CFRunLoopRunInMode(.defaultMode, 0.01, false)
        }
        let count2 = evalString("document.getElementById('app')?.dataset.renderCount || '0'")

        let thinkingThread = KasugaiThread(
            id: 1,
            projectId: 1,
            title: "テスト",
            updatedAtMs: 115,
            status: "running",
            sessionState: "prompting",
            provider: "claude_code",
            providerName: "Claude Code",
            model: "default",
            effort: "medium",
            activeTurnId: 2,
            streamingText: "",
            lastError: "",
            availableModels: [],
            activities: sampleThread.activities + [
                KasugaiActivity(
                    turnId: 2,
                    callId: "thought-2",
                    kind: "thought",
                    title: "思考中",
                    status: "running",
                    detail: "計画を立てています"
                )
            ],
            pendingApproval: sampleThread.pendingApproval,
            workspace: diffOnlyThread.workspace,
            messages: sampleThread.messages,
            queue: []
        )
        view.update(thread: thinkingThread)
        let thinkDeadline = Date().addingTimeInterval(2.0)
        while view.syncState != .readyIdle && Date() < thinkDeadline {
            CFRunLoopRunInMode(.defaultMode, 0.02, false)
        }
        let thinkingBusyCount = evalString("document.querySelectorAll('.busy-indicator').length")
        let thinkingBusyText = evalString(
            "document.querySelector('.busy-indicator')?.textContent || ''")
        let thinkingLivePanelCount = evalString(
            "document.querySelectorAll('.activity-live').length")

        let busyThread = KasugaiThread(
            id: 1,
            projectId: 1,
            title: "テスト",
            updatedAtMs: 120,
            status: "running",
            sessionState: "prompting",
            provider: "claude_code",
            providerName: "Claude Code",
            model: "default",
            effort: "medium",
            activeTurnId: 2,
            streamingText: "",
            lastError: "",
            availableModels: [],
            activities: thinkingThread.activities
                + (1...6).map { idx in
                    KasugaiActivity(
                        turnId: 2,
                        callId: "call-\(idx)",
                        kind: "tool",
                        title: "File Sample\(idx).swift",
                        status: idx == 6 ? "running" : "completed",
                        detail: ""
                    )
                },
            pendingApproval: sampleThread.pendingApproval,
            workspace: diffOnlyThread.workspace,
            messages: sampleThread.messages,
            queue: [
                KasugaiQueuedTurn(
                    turnId: 3,
                    text: "次の指示メッセージ",
                    attachments: []
                )
            ]
        )
        view.update(thread: busyThread)
        let busyDeadline = Date().addingTimeInterval(2.0)
        while view.syncState != .readyIdle && Date() < busyDeadline {
            CFRunLoopRunInMode(.defaultMode, 0.02, false)
        }
        let sameDomNode = evalString(
            "document.querySelector('article.message') === window.__firstArticle ? '1' : '0'")
        let scrolledAfter = Double(evalString("window.scrollY")) ?? -1
        let jumpBtnVisibleWhenScrolledUp = evalString(
            "document.querySelector('.scroll-to-bottom-btn.is-visible.is-live') ? '1' : '0'"
        )
        let hasBusyIndicatorWithPanel = evalString(
            "document.querySelector('.busy-indicator') ? '1' : '0'")
        let foldedLiveRows = evalString(
            "document.querySelectorAll('.activity-live .activity-row').length")
        let expandBtnText = evalString(
            "document.querySelector('.activity-live .activity-expand-btn')?.textContent || ''")
        let queuedBubbleCount = evalString(
            "document.querySelectorAll('.message.role-user.role-queued').length")
        let queuedBubbleText = evalString(
            "document.querySelector('.message.role-user.role-queued .message-body')?.textContent || ''"
        )
        let queuedMetaText = evalString(
            "document.querySelector('.message.role-user.role-queued .message-queue-meta')?.textContent || ''"
        )
        _ = evalString("document.querySelector('.activity-live .activity-expand-btn')?.click(); ''")
        let expandedLiveRows = evalString(
            "document.querySelectorAll('.activity-live .activity-row').length")

        let stoppedThread = KasugaiThread(
            id: 1,
            projectId: 1,
            title: "テスト",
            updatedAtMs: 140,
            status: "idle",
            sessionState: "ready",
            provider: "claude_code",
            providerName: "Claude Code",
            model: "default",
            effort: "medium",
            activeTurnId: 0,
            streamingText: "",
            lastError: "ターンを停止しました",
            availableModels: [],
            activities: sampleThread.activities,
            pendingApproval: sampleThread.pendingApproval,
            workspace: diffOnlyThread.workspace,
            messages: sampleThread.messages,
            queue: []
        )
        view.update(thread: stoppedThread)
        let stopDeadline = Date().addingTimeInterval(2.0)
        while view.syncState != .readyIdle && Date() < stopDeadline {
            CFRunLoopRunInMode(.defaultMode, 0.02, false)
        }
        let hasNoticeBanner = evalString("document.querySelector('.banner.notice') ? '1' : '0'")
        let hasErrorBanner = evalString("document.querySelector('.banner.error') ? '1' : '0'")

        let partialStreamingThread = KasugaiThread(
            id: 1,
            projectId: 1,
            title: "テスト",
            updatedAtMs: 160,
            status: "running",
            sessionState: "prompting",
            provider: "claude_code",
            providerName: "Claude Code",
            model: "default",
            effort: "medium",
            activeTurnId: 4,
            streamingText: "途中テキスト\n\n---\n\n### ",
            lastError: "",
            availableModels: [],
            activities: sampleThread.activities,
            pendingApproval: sampleThread.pendingApproval,
            workspace: diffOnlyThread.workspace,
            messages: sampleThread.messages,
            queue: []
        )
        view.update(thread: partialStreamingThread)
        let partialDeadline = Date().addingTimeInterval(2.0)
        while view.syncState != .readyIdle && Date() < partialDeadline {
            CFRunLoopRunInMode(.defaultMode, 0.02, false)
        }
        let partialRendered = view.syncState == .readyIdle
        let partialStreamText = evalString(
            "document.querySelector('.message.role-streaming .message-body')?.textContent || ''"
        )

        let secondThread = KasugaiThread(
            id: 2,
            projectId: 1,
            title: "切替先スレッド",
            updatedAtMs: 180,
            status: "idle",
            sessionState: "ready",
            provider: "claude_code",
            providerName: "Claude Code",
            model: "default",
            effort: "medium",
            activeTurnId: 0,
            streamingText: "",
            lastError: "",
            availableModels: [],
            activities: [],
            pendingApproval: sampleThread.pendingApproval,
            workspace: diffOnlyThread.workspace,
            messages: [
                KasugaiMessage(
                    id: 20,
                    turnId: 5,
                    role: "assistant",
                    text: "別セッション表示確認",
                    provider: "claude_code",
                    model: "default",
                    attachments: []
                )
            ],
            queue: []
        )
        view.update(thread: secondThread)
        let switchDeadline = Date().addingTimeInterval(2.0)
        while view.syncState != .readyIdle && Date() < switchDeadline {
            CFRunLoopRunInMode(.defaultMode, 0.02, false)
        }
        let switchedText = evalString("document.getElementById('app')?.textContent || ''")

        let mediaRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kasugai-media-live-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: mediaRoot) }
        var mediaAndCompareOk = false
        if (try? FileManager.default.createDirectory(
            at: mediaRoot,
            withIntermediateDirectories: true
        )) != nil {
            let pngBytes = Data([
                0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
                0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
                0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
                0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
                0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
                0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
                0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D,
                0xB0, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
                0x44, 0xAE, 0x42, 0x60, 0x82,
            ])
            let beforeURL = mediaRoot.appendingPathComponent("before.png")
            let afterURL = mediaRoot.appendingPathComponent("after.png")
            let audioURL = mediaRoot.appendingPathComponent("track.mp3")
            let videoURL = mediaRoot.appendingPathComponent("clip.mp4")
            try? pngBytes.write(to: beforeURL)
            try? pngBytes.write(to: afterURL)
            try? Data([0x49, 0x44, 0x33, 0x03]).write(to: audioURL)
            try? Data([0x00, 0x00, 0x00, 0x18]).write(to: videoURL)

            let mediaMarkdown = """
                変更前 [before.png](file://\(beforeURL.path))
                変更後 [after.png](after.png)
                音声 [track.mp3](file://\(audioURL.path))
                動画 [clip.mp4](file://\(videoURL.path))
                """
            let mediaThread = KasugaiThread(
                id: 3,
                projectId: 1,
                title: "メディア検証",
                updatedAtMs: 200,
                status: "idle",
                sessionState: "ready",
                provider: "claude_code",
                providerName: "Claude Code",
                model: "default",
                effort: "medium",
                activeTurnId: 0,
                streamingText: "",
                lastError: "",
                availableModels: [],
                activities: [],
                pendingApproval: sampleThread.pendingApproval,
                workspace: KasugaiWorkspaceSnapshot(
                    mode: "root",
                    rootPath: mediaRoot.path,
                    worktreePath: "",
                    effectiveCwd: mediaRoot.path,
                    branch: "main",
                    baseRef: "",
                    diffFilesChanged: 0,
                    diffInsertions: 0,
                    diffDeletions: 0
                ),
                messages: [
                    KasugaiMessage(
                        id: 30,
                        turnId: 6,
                        role: "assistant",
                        text: mediaMarkdown,
                        provider: "claude_code",
                        model: "default",
                        attachments: []
                    )
                ],
                queue: []
            )
            view.update(thread: mediaThread)
            let mediaDeadline = Date().addingTimeInterval(2.5)
            while view.syncState != .readyIdle && Date() < mediaDeadline {
                CFRunLoopRunInMode(.defaultMode, 0.02, false)
            }
            let imgCount = evalString(
                "document.querySelectorAll('.inline-media img.attachment-thumb').length")
            let audioCount = evalString(
                "document.querySelectorAll('.inline-media audio.attachment-audio').length")
            let videoCount = evalString(
                "document.querySelectorAll('.inline-media video.attachment-video').length")
            let compareStageCount = evalString(
                "document.querySelectorAll('.img-compare-stage').length")
            let compareBeforeCount = evalString(
                "document.querySelectorAll('.img-compare-before').length")
            let compareAfterCount = evalString(
                "document.querySelectorAll('.img-compare-after').length")

            let gitInit = Process()
            gitInit.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            gitInit.arguments = [
                "sh", "-c",
                "git -C \"$1\" init -q && git -C \"$1\" config user.email test@kasugai.local && git -C \"$1\" config user.name test && git -C \"$1\" add before.png && git -C \"$1\" commit -qm init",
                "_", mediaRoot.path,
            ]
            try? gitInit.run()
            gitInit.waitUntilExit()
            var modifiedPng = pngBytes
            modifiedPng.append(0x00)
            try? modifiedPng.write(to: beforeURL)
            let diffReport = GitWorkspace.computeDiff(in: mediaRoot.path)
            let diffView = SandboxedChatWebView(
                frame: NSRect(x: 0, y: 0, width: 640, height: 420),
                mode: .diff
            )
            diffView.update(diffReport: diffReport, focusFile: "before.png")
            let diffDeadline = Date().addingTimeInterval(4.0)
            while diffView.syncState != .readyIdle && Date() < diffDeadline {
                CFRunLoopRunInMode(.defaultMode, 0.02, false)
            }
            var diffCompareCount = "0"
            if let diffWeb = diffView.webView {
                var done = false
                diffWeb.evaluateJavaScript(
                    "String(document.querySelectorAll('.diff-image-wrap .img-compare-stage').length)"
                ) {
                    val, _ in
                    if let s = val as? String {
                        diffCompareCount = s
                    }
                    done = true
                }
                let jsDeadline = Date().addingTimeInterval(2.0)
                while !done && Date() < jsDeadline {
                    CFRunLoopRunInMode(.defaultMode, 0.02, false)
                }
            }
            mediaAndCompareOk =
                imgCount == "2"
                && audioCount == "1"
                && videoCount == "1"
                && compareStageCount == "1"
                && compareBeforeCount == "1"
                && compareAfterCount == "1"
                && diffCompareCount == "1"
        }

        var clickedThreadId: Int64?
        view.onOpenThread = { tid in
            clickedThreadId = tid
        }
        let handoffThread = KasugaiThread(
            id: 7,
            projectId: 1,
            title: "Kasugai",
            updatedAtMs: 0,
            status: "idle",
            sessionState: "disconnected",
            provider: "antigravity_acp",
            providerName: "Antigravity",
            model: "default",
            effort: "high",
            activeTurnId: 0,
            streamingText: "",
            lastError: "",
            availableModels: [],
            activities: [
                KasugaiActivity(
                    turnId: 8,
                    callId: "call-handoff",
                    kind: "tool",
                    title: "\"$KASUGAI_CTL_BIN\" ctl send --thread 10 --prompt \"ゲーム更新するか。\"",
                    status: "completed",
                    detail: ""
                )
            ],
            pendingApproval: sampleThread.pendingApproval,
            workspace: sampleThread.workspace,
            messages: [
                KasugaiMessage(
                    id: 40,
                    turnId: 8,
                    role: "assistant",
                    text: "[SampleApp](kasugai-thread://10) に転送しました。",
                    provider: "antigravity_acp",
                    model: "default",
                    attachments: []
                )
            ],
            queue: []
        )
        view.update(
            thread: handoffThread,
            threadIndex: [
                "10": KasugaiThreadLinkInfo(
                    id: 10,
                    title: "sample-app、ビルド完了した。",
                    projectName: "sample-app",
                    status: "running"
                )
            ]
        )
        let handoffDeadline = Date().addingTimeInterval(2.5)
        while view.syncState != .readyIdle && Date() < handoffDeadline {
            CFRunLoopRunInMode(.defaultMode, 0.02, false)
        }
        let handoffCardCount = evalString(
            "document.querySelectorAll('.session-handoff-card').length")
        let handoffTargetText = evalString(
            "document.querySelector('.session-handoff-target')?.textContent || ''")
        let handoffPromptText = evalString(
            "document.querySelector('.session-handoff-prompt')?.textContent || ''")
        _ = evalString(
            "(() => { const b = document.querySelector('.session-handoff-link'); if (b) { b.click(); return '1'; } return '0'; })()"
        )
        let handoffClickDeadline = Date().addingTimeInterval(1.0)
        while clickedThreadId == nil && Date() < handoffClickDeadline {
            CFRunLoopRunInMode(.defaultMode, 0.02, false)
        }
        let handoffOk =
            handoffCardCount == "1"
            && handoffTargetText.contains("sample-app")
            && handoffPromptText == "ゲーム更新するか。"
            && clickedThreadId == 10

        let prevWebView = view.webView
        view.reloadRendererAssets()
        let reloadDeadline = Date().addingTimeInterval(4.0)
        while view.syncState != .readyIdle && Date() < reloadDeadline {
            CFRunLoopRunInMode(.defaultMode, 0.02, false)
        }
        let reloadedFreshWebView = view.webView != nil && view.webView !== prevWebView
        let reloadedText: String = {
            guard let fresh = view.webView else {
                return ""
            }
            var out = ""
            var done = false
            fresh.evaluateJavaScript("document.getElementById('app')?.textContent || ''") {
                val, _ in
                if let s = val as? String {
                    out = s
                }
                done = true
            }
            let jsDeadline = Date().addingTimeInterval(2.0)
            while !done && Date() < jsDeadline {
                CFRunLoopRunInMode(.defaultMode, 0.02, false)
            }
            return out
        }()

        return initialText.contains("疎通確認メッセージ")
            && !initialText.contains("件の操作")
            && fileLinkHref == "file:///tmp/justfile#L10-L20"
            && fileLinkText == "justfile"
            && clickedFileTarget
                == FileLinkTarget(path: "/tmp/justfile", lineStart: 10, lineEnd: 20)
            && firstOlDirectItems == "2"
            && secondOlStart == "3"
            && tableHeaders == "3"
            && tableRows == "2"
            && count1 == "1"
            && count2 == "1"
            && scrolledBefore >= 18
            && abs(scrolledAfter - scrolledBefore) <= 2
            && sameDomNode == "1"
            && jumpBtnVisibleWhenScrolledUp == "1"
            && thinkingBusyCount == "1"
            && thinkingBusyText == "思考中…"
            && thinkingLivePanelCount == "0"
            && hasBusyIndicatorWithPanel == "0"
            && foldedLiveRows == "3"
            && expandBtnText == "前の 3 件を表示"
            && expandedLiveRows == "6"
            && queuedBubbleCount == "1"
            && queuedBubbleText.contains("次の指示メッセージ")
            && queuedMetaText == "待機中"
            && hasNoticeBanner == "1"
            && hasErrorBanner == "0"
            && partialRendered
            && partialStreamText.contains("途中テキスト")
            && switchedText.contains("別セッション表示確認")
            && mediaAndCompareOk
            && handoffOk
            && reloadedFreshWebView
            && reloadedText.contains("転送しました")
    }
}
