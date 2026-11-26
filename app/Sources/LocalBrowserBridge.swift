import AppKit
import Darwin
import Foundation

struct BrowserTabInfo: Codable {
    let tabId: String
    let title: String
    let url: String
    let active: Bool

    enum CodingKeys: String, CodingKey {
        case tabId = "tab_id"
        case title
        case url
        case active
    }
}

struct BrowserBridgeRequest: Codable {
    let action: String
    let threadId: Int64?
    let tabId: String?
    let newTab: Bool?
    let url: String?
    let ref: String?
    let selector: String?
    let x: Double?
    let y: Double?
    let doubleClick: Bool?
    let text: String?
    let clear: Bool?
    let submit: Bool?
    let key: String?
    let modifiers: [String]?
    let fromRef: String?
    let fromSelector: String?
    let fromX: Double?
    let fromY: Double?
    let toRef: String?
    let toSelector: String?
    let toX: Double?
    let toY: Double?
    let steps: Int?
    let mode: String?
    let files: [String]?
    let deltaX: Double?
    let deltaY: Double?
    let expression: String?
    let outputPath: String?
    let maxElements: Int?
    let timeoutMs: Int64?

    enum CodingKeys: String, CodingKey {
        case action
        case threadId = "thread_id"
        case tabId = "tab_id"
        case newTab = "new_tab"
        case url
        case ref
        case selector
        case x
        case y
        case doubleClick = "double_click"
        case text
        case clear
        case submit
        case key
        case modifiers
        case fromRef = "from_ref"
        case fromSelector = "from_selector"
        case fromX = "from_x"
        case fromY = "from_y"
        case toRef = "to_ref"
        case toSelector = "to_selector"
        case toX = "to_x"
        case toY = "to_y"
        case steps
        case mode
        case files
        case deltaX = "delta_x"
        case deltaY = "delta_y"
        case expression
        case outputPath = "output_path"
        case maxElements = "max_elements"
        case timeoutMs = "timeout_ms"
    }

    init(
        action: String,
        threadId: Int64? = nil,
        tabId: String? = nil,
        newTab: Bool? = nil,
        url: String? = nil,
        ref: String? = nil,
        selector: String? = nil,
        x: Double? = nil,
        y: Double? = nil,
        doubleClick: Bool? = nil,
        text: String? = nil,
        clear: Bool? = nil,
        submit: Bool? = nil,
        key: String? = nil,
        modifiers: [String]? = nil,
        fromRef: String? = nil,
        fromSelector: String? = nil,
        fromX: Double? = nil,
        fromY: Double? = nil,
        toRef: String? = nil,
        toSelector: String? = nil,
        toX: Double? = nil,
        toY: Double? = nil,
        steps: Int? = nil,
        mode: String? = nil,
        files: [String]? = nil,
        deltaX: Double? = nil,
        deltaY: Double? = nil,
        expression: String? = nil,
        outputPath: String? = nil,
        maxElements: Int? = nil,
        timeoutMs: Int64? = nil
    ) {
        self.action = action
        self.threadId = threadId
        self.tabId = tabId
        self.newTab = newTab
        self.url = url
        self.ref = ref
        self.selector = selector
        self.x = x
        self.y = y
        self.doubleClick = doubleClick
        self.text = text
        self.clear = clear
        self.submit = submit
        self.key = key
        self.modifiers = modifiers
        self.fromRef = fromRef
        self.fromSelector = fromSelector
        self.fromX = fromX
        self.fromY = fromY
        self.toRef = toRef
        self.toSelector = toSelector
        self.toX = toX
        self.toY = toY
        self.steps = steps
        self.mode = mode
        self.files = files
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.expression = expression
        self.outputPath = outputPath
        self.maxElements = maxElements
        self.timeoutMs = timeoutMs
    }
}

struct BrowserBridgeResponse: Codable {
    let ok: Bool
    let error: String?
    let tabId: String?
    let detail: String?
    let tabs: [BrowserTabInfo]?
    let snapshot: BrowserSnapshotPayload?
    let screenshotPath: String?
    let width: Int?
    let height: Int?

    enum CodingKeys: String, CodingKey {
        case ok
        case error
        case tabId = "tab_id"
        case detail
        case tabs
        case snapshot
        case screenshotPath = "screenshot_path"
        case width
        case height
    }

    static func failure(_ message: String, tabId: String? = nil) -> BrowserBridgeResponse {
        BrowserBridgeResponse(
            ok: false,
            error: message,
            tabId: tabId,
            detail: nil,
            tabs: nil,
            snapshot: nil,
            screenshotPath: nil,
            width: nil,
            height: nil
        )
    }
}

protocol KasugaiBrowserAutomationHost: AnyObject {
    func browserTabsSummary(threadId: Int64?) -> [BrowserTabInfo]
    func browserEnsureTab(threadId: Int64?, tabId: String?, openNew: Bool) -> (
        tabId: String, view: LocalPreviewBrowserView
    )?
    func browserSelectTab(threadId: Int64?, tabId: String) -> Bool
    func browserCloseTab(threadId: Int64?, tabId: String) -> Bool
}

enum LocalBrowserBridgePaths {
    static func defaultSocketPath() -> String {
        if let override = ProcessInfo.processInfo.environment["KASUGAI_BROWSER_SOCKET"],
            !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return override
        }
        return KasugaiRuntimePaths.dataDirectory()
            .appendingPathComponent("run", isDirectory: true)
            .appendingPathComponent("browser.sock")
            .path
    }
}

final class LocalBrowserBridgeServer {
    let socketPath: String
    private weak var host: KasugaiBrowserAutomationHost?
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "dev.soyukke.kasugai.browser-bridge")

    init(
        socketPath: String = LocalBrowserBridgePaths.defaultSocketPath(),
        host: KasugaiBrowserAutomationHost
    ) {
        self.socketPath = socketPath
        self.host = host
    }

    deinit {
        stop()
    }

    @discardableResult
    func start() -> Bool {
        stop()
        let url = URL(fileURLWithPath: socketPath)
        let dir = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            return false
        }
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            return false
        }

        var addr = sockaddr_un()
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count < maxLen else {
            close(fd)
            return false
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for idx in 0..<pathBytes.count {
                raw[idx] = pathBytes[idx]
            }
            raw[pathBytes.count] = 0
        }

        let bound = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0 else {
            close(fd)
            return false
        }
        chmod(socketPath, 0o600)
        guard listen(fd, 16) == 0 else {
            close(fd)
            unlink(socketPath)
            return false
        }
        let listenFlags = fcntl(fd, F_GETFL, 0)
        if listenFlags >= 0 {
            _ = fcntl(fd, F_SETFL, listenFlags | O_NONBLOCK)
        }
        listenFD = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptPendingClients()
        }
        source.resume()
        acceptSource = source
        return true
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        unlink(socketPath)
    }

    private func acceptPendingClients() {
        while listenFD >= 0 {
            let clientFD = accept(listenFD, nil, nil)
            if clientFD < 0 {
                break
            }
            let flags = fcntl(clientFD, F_GETFL, 0)
            if flags >= 0 {
                _ = fcntl(clientFD, F_SETFL, flags & ~O_NONBLOCK)
            }
            var noSigPipe: Int32 = 1
            setsockopt(
                clientFD,
                SOL_SOCKET,
                SO_NOSIGPIPE,
                &noSigPipe,
                socklen_t(MemoryLayout<Int32>.size)
            )
            var recvTimeout = timeval(tv_sec: 30, tv_usec: 0)
            setsockopt(
                clientFD,
                SOL_SOCKET,
                SO_RCVTIMEO,
                &recvTimeout,
                socklen_t(MemoryLayout<timeval>.size)
            )
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handleClient(fd: clientFD)
            }
        }
    }

    private func handleClient(fd: Int32) {
        defer { close(fd) }
        guard let line = Self.readLine(fd: fd), !line.isEmpty else {
            return
        }
        let response: BrowserBridgeResponse
        if let req = try? JSONDecoder().decode(BrowserBridgeRequest.self, from: Data(line.utf8)) {
            response = execute(request: req)
        } else {
            response = .failure("invalid browser request JSON")
        }
        if let encoded = try? JSONEncoder().encode(response) {
            var framed = encoded
            framed.append(0x0A)
            Self.writeAll(fd: fd, data: framed)
        }
    }

    private func execute(request: BrowserBridgeRequest) -> BrowserBridgeResponse {
        let timeoutSec = Double(max(1000, min(request.timeoutMs ?? 15000, 35000))) / 1000.0
        let sem = DispatchSemaphore(value: 0)
        var result = BrowserBridgeResponse.failure("browser host unavailable")
        let finish: (BrowserBridgeResponse) -> Void = { response in
            result = response
            sem.signal()
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, let host = self.host else {
                finish(.failure("browser host unavailable"))
                return
            }
            self.dispatchOnMain(request: request, host: host, completion: finish)
        }

        if sem.wait(timeout: .now() + timeoutSec) == .timedOut {
            return .failure("browser action timed out")
        }
        return result
    }

    private func dispatchOnMain(
        request: BrowserBridgeRequest,
        host: KasugaiBrowserAutomationHost,
        completion: @escaping (BrowserBridgeResponse) -> Void
    ) {
        switch request.action {
        case "tabs":
            let tabs = host.browserTabsSummary(threadId: request.threadId)
            completion(
                BrowserBridgeResponse(
                    ok: true,
                    error: nil,
                    tabId: tabs.first(where: \.active)?.tabId,
                    detail: nil,
                    tabs: tabs,
                    snapshot: nil,
                    screenshotPath: nil,
                    width: nil,
                    height: nil
                )
            )
            return

        case "select_tab":
            guard let id = request.tabId, !id.isEmpty else {
                completion(.failure("tab_id is required"))
                return
            }
            let ok = host.browserSelectTab(threadId: request.threadId, tabId: id)
            completion(
                BrowserBridgeResponse(
                    ok: ok,
                    error: ok ? nil : "tab not found: \(id)",
                    tabId: ok ? id : nil,
                    detail: nil,
                    tabs: host.browserTabsSummary(threadId: request.threadId),
                    snapshot: nil,
                    screenshotPath: nil,
                    width: nil,
                    height: nil
                )
            )
            return

        case "close_tab":
            guard let id = request.tabId, !id.isEmpty else {
                completion(.failure("tab_id is required"))
                return
            }
            let ok = host.browserCloseTab(threadId: request.threadId, tabId: id)
            completion(
                BrowserBridgeResponse(
                    ok: ok,
                    error: ok ? nil : "tab not found: \(id)",
                    tabId: nil,
                    detail: nil,
                    tabs: host.browserTabsSummary(threadId: request.threadId),
                    snapshot: nil,
                    screenshotPath: nil,
                    width: nil,
                    height: nil
                )
            )
            return

        default:
            break
        }

        let openNew = request.action == "open" && (request.newTab ?? false)
        guard
            let target = host.browserEnsureTab(
                threadId: request.threadId,
                tabId: request.tabId,
                openNew: openNew
            )
        else {
            completion(.failure("failed to acquire browser tab"))
            return
        }
        let tabId = target.tabId
        let browser = target.view

        switch request.action {
        case "open":
            guard let url = request.url,
                !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                completion(.failure("url is required", tabId: tabId))
                return
            }
            browser.navigateAndWait(input: url, timeoutMs: request.timeoutMs ?? 10000) { res in
                completion(
                    BrowserBridgeResponse(
                        ok: res.ok,
                        error: res.error,
                        tabId: tabId,
                        detail: res.detail,
                        tabs: nil,
                        snapshot: nil,
                        screenshotPath: nil,
                        width: nil,
                        height: nil
                    )
                )
            }

        case "snapshot":
            browser.captureSnapshot(maxElements: request.maxElements ?? 120) { res in
                switch res {
                case .success(let payload):
                    completion(
                        BrowserBridgeResponse(
                            ok: true,
                            error: nil,
                            tabId: tabId,
                            detail: nil,
                            tabs: nil,
                            snapshot: payload,
                            screenshotPath: nil,
                            width: nil,
                            height: nil
                        )
                    )
                case .failure(let error):
                    completion(.failure(error.localizedDescription, tabId: tabId))
                }
            }

        case "screenshot":
            browser.captureScreenshot(outputPath: request.outputPath) { res in
                switch res {
                case .success(let info):
                    completion(
                        BrowserBridgeResponse(
                            ok: true,
                            error: nil,
                            tabId: tabId,
                            detail: info.path,
                            tabs: nil,
                            snapshot: nil,
                            screenshotPath: info.path,
                            width: info.width,
                            height: info.height
                        )
                    )
                case .failure(let error):
                    completion(.failure(error.localizedDescription, tabId: tabId))
                }
            }

        case "click":
            browser.performClick(
                ref: request.ref,
                selector: request.selector,
                x: request.x,
                y: request.y,
                doubleClick: request.doubleClick ?? false
            ) { res in
                completion(
                    BrowserBridgeResponse(
                        ok: res.ok,
                        error: res.error,
                        tabId: tabId,
                        detail: res.detail,
                        tabs: nil,
                        snapshot: nil,
                        screenshotPath: nil,
                        width: nil,
                        height: nil
                    )
                )
            }

        case "type":
            guard let text = request.text else {
                completion(.failure("text is required", tabId: tabId))
                return
            }
            browser.performType(
                ref: request.ref,
                selector: request.selector,
                text: text,
                clear: request.clear ?? false,
                submit: request.submit ?? false
            ) { res in
                completion(
                    BrowserBridgeResponse(
                        ok: res.ok,
                        error: res.error,
                        tabId: tabId,
                        detail: res.detail,
                        tabs: nil,
                        snapshot: nil,
                        screenshotPath: nil,
                        width: nil,
                        height: nil
                    )
                )
            }

        case "press":
            guard let key = request.key, !key.isEmpty else {
                completion(.failure("key is required", tabId: tabId))
                return
            }
            browser.performPress(key: key, modifiers: request.modifiers ?? []) { res in
                completion(
                    BrowserBridgeResponse(
                        ok: res.ok,
                        error: res.error,
                        tabId: tabId,
                        detail: res.detail,
                        tabs: nil,
                        snapshot: nil,
                        screenshotPath: nil,
                        width: nil,
                        height: nil
                    )
                )
            }

        case "drag":
            browser.performDrag(
                fromRef: request.fromRef,
                fromSelector: request.fromSelector,
                fromX: request.fromX,
                fromY: request.fromY,
                toRef: request.toRef,
                toSelector: request.toSelector,
                toX: request.toX,
                toY: request.toY,
                steps: request.steps ?? 12,
                mode: request.mode ?? "auto"
            ) { res in
                completion(
                    BrowserBridgeResponse(
                        ok: res.ok,
                        error: res.error,
                        tabId: tabId,
                        detail: res.detail,
                        tabs: nil,
                        snapshot: nil,
                        screenshotPath: nil,
                        width: nil,
                        height: nil
                    )
                )
            }

        case "drop_files":
            browser.performDropFiles(
                ref: request.ref,
                selector: request.selector,
                x: request.x,
                y: request.y,
                filePaths: request.files ?? []
            ) { res in
                completion(
                    BrowserBridgeResponse(
                        ok: res.ok,
                        error: res.error,
                        tabId: tabId,
                        detail: res.detail,
                        tabs: nil,
                        snapshot: nil,
                        screenshotPath: nil,
                        width: nil,
                        height: nil
                    )
                )
            }

        case "scroll":
            browser.performScroll(
                ref: request.ref,
                selector: request.selector,
                deltaX: request.deltaX ?? 0,
                deltaY: request.deltaY ?? 0
            ) { res in
                completion(
                    BrowserBridgeResponse(
                        ok: res.ok,
                        error: res.error,
                        tabId: tabId,
                        detail: res.detail,
                        tabs: nil,
                        snapshot: nil,
                        screenshotPath: nil,
                        width: nil,
                        height: nil
                    )
                )
            }

        case "eval":
            guard let expr = request.expression, !expr.isEmpty else {
                completion(.failure("expression is required", tabId: tabId))
                return
            }
            browser.evaluateExpression(expr) { res in
                completion(
                    BrowserBridgeResponse(
                        ok: res.ok,
                        error: res.error,
                        tabId: tabId,
                        detail: res.detail,
                        tabs: nil,
                        snapshot: nil,
                        screenshotPath: nil,
                        width: nil,
                        height: nil
                    )
                )
            }

        default:
            completion(.failure("unknown browser action: \(request.action)", tabId: tabId))
        }
    }

    fileprivate static func readLine(fd: Int32) -> String? {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while buffer.count < 4_194_304 {
            let count = read(fd, &chunk, chunk.count)
            if count > 0 {
                buffer.append(contentsOf: chunk[0..<count])
                if let nl = buffer.firstIndex(of: 0x0A) {
                    return String(decoding: buffer[0..<nl], as: UTF8.self)
                }
            } else if count == 0 {
                break
            } else if errno != EINTR {
                break
            }
        }
        return buffer.isEmpty ? nil : String(decoding: buffer, as: UTF8.self)
    }

    fileprivate static func writeAll(fd: Int32, data: Data) {
        data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else {
                return
            }
            var sent = 0
            while sent < data.count {
                let written = write(fd, base.advanced(by: sent), data.count - sent)
                if written > 0 {
                    sent += written
                } else if written < 0 && errno == EINTR {
                    continue
                } else {
                    break
                }
            }
        }
    }
}

enum LocalBrowserBridgeClient {
    static func send(
        request: BrowserBridgeRequest,
        socketPath: String = LocalBrowserBridgePaths.defaultSocketPath()
    ) -> BrowserBridgeResponse? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            return nil
        }
        defer { close(fd) }

        var noSigPipe: Int32 = 1
        setsockopt(
            fd,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSigPipe,
            socklen_t(MemoryLayout<Int32>.size)
        )

        var addr = sockaddr_un()
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count < maxLen else {
            return nil
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for idx in 0..<pathBytes.count {
                raw[idx] = pathBytes[idx]
            }
            raw[pathBytes.count] = 0
        }
        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            return nil
        }
        guard var encoded = try? JSONEncoder().encode(request) else {
            return nil
        }
        encoded.append(0x0A)
        LocalBrowserBridgeServer.writeAll(fd: fd, data: encoded)
        guard let line = LocalBrowserBridgeServer.readLine(fd: fd),
            let response = try? JSONDecoder().decode(
                BrowserBridgeResponse.self, from: Data(line.utf8))
        else {
            return nil
        }
        return response
    }

    static func runCLI(arguments: [String]) -> Int32 {
        guard let sub = arguments.first else {
            fputs(
                "usage: Kasugai ctl browser <open|tabs|snapshot|screenshot|click|type|press|drag|drop-files|scroll|eval> [options]\n",
                stderr
            )
            return 2
        }
        let rest = Array(arguments.dropFirst())
        let req = buildCLIRequest(subcommand: sub, args: rest)
        let sock = LocalBrowserBridgePaths.defaultSocketPath()
        guard let response = send(request: req, socketPath: sock),
            let data = try? JSONEncoder().encode(response),
            let text = String(data: data, encoding: .utf8)
        else {
            fputs("failed to communicate with Kasugai browser bridge (\(sock))\n", stderr)
            return 1
        }
        print(text)
        return response.ok ? 0 : 1
    }

    private static func optionValue(_ name: String, in args: [String]) -> String? {
        guard let idx = args.firstIndex(of: name), idx + 1 < args.count else {
            return nil
        }
        return args[idx + 1]
    }

    private static func optionValues(_ name: String, in args: [String]) -> [String] {
        var out: [String] = []
        var idx = 0
        while idx < args.count {
            if args[idx] == name, idx + 1 < args.count {
                out.append(args[idx + 1])
                idx += 2
            } else {
                idx += 1
            }
        }
        return out
    }

    private static func buildCLIRequest(subcommand: String, args: [String]) -> BrowserBridgeRequest
    {
        let normalizedAction: String
        switch subcommand {
        case "drop-files":
            normalizedAction = "drop_files"
        case "select-tab":
            normalizedAction = "select_tab"
        case "close-tab":
            normalizedAction = "close_tab"
        default:
            normalizedAction = subcommand
        }
        let positionalURL =
            (normalizedAction == "open" && args.first?.hasPrefix("-") == false) ? args.first : nil
        let positionalExpr =
            (normalizedAction == "eval" && args.first?.hasPrefix("-") == false) ? args.first : nil
        let envThreadId = ProcessInfo.processInfo.environment["KASUGAI_THREAD_ID"].flatMap(
            Int64.init
        )
        let resolvedThreadId = optionValue("--thread", in: args).flatMap(Int64.init) ?? envThreadId
        return BrowserBridgeRequest(
            action: normalizedAction,
            threadId: resolvedThreadId,
            tabId: optionValue("--tab", in: args),
            newTab: args.contains("--new-tab"),
            url: optionValue("--url", in: args) ?? positionalURL,
            ref: optionValue("--ref", in: args),
            selector: optionValue("--selector", in: args),
            x: optionValue("--x", in: args).flatMap(Double.init),
            y: optionValue("--y", in: args).flatMap(Double.init),
            doubleClick: args.contains("--double"),
            text: optionValue("--text", in: args),
            clear: args.contains("--clear"),
            submit: args.contains("--submit"),
            key: optionValue("--key", in: args),
            modifiers: optionValues("--mod", in: args),
            fromRef: optionValue("--from-ref", in: args),
            fromSelector: optionValue("--from-selector", in: args),
            fromX: optionValue("--from-x", in: args).flatMap(Double.init),
            fromY: optionValue("--from-y", in: args).flatMap(Double.init),
            toRef: optionValue("--to-ref", in: args),
            toSelector: optionValue("--to-selector", in: args),
            toX: optionValue("--to-x", in: args).flatMap(Double.init),
            toY: optionValue("--to-y", in: args).flatMap(Double.init),
            steps: optionValue("--steps", in: args).flatMap(Int.init),
            mode: optionValue("--mode", in: args),
            files: optionValues("--file", in: args),
            deltaX: optionValue("--dx", in: args).flatMap(Double.init),
            deltaY: optionValue("--dy", in: args).flatMap(Double.init),
            expression: optionValue("--expr", in: args) ?? positionalExpr,
            outputPath: optionValue("--out", in: args),
            maxElements: optionValue("--max-elements", in: args).flatMap(Int.init),
            timeoutMs: optionValue("--timeout-ms", in: args).flatMap(Int64.init)
        )
    }

    static func mcpToolDefinitions() -> [[String: Any]] {
        [
            mcpTool(
                name: "kasugai_browser_open",
                description:
                    "Open a URL in Kasugai's built-in right-pane browser (loopback by default, or external https/http when enabled in Settings).",
                properties: [
                    "url": ["type": "string"],
                    "tab_id": ["type": "string"],
                    "new_tab": ["type": "boolean"],
                    "timeout_ms": ["type": "integer"],
                ]
            ),
            mcpTool(
                name: "kasugai_browser_tabs",
                description: "List, select, or close tabs in Kasugai's built-in browser.",
                properties: [
                    "operation": ["type": "string", "enum": ["list", "select", "close"]],
                    "tab_id": ["type": "string"],
                ]
            ),
            mcpTool(
                name: "kasugai_browser_snapshot",
                description:
                    "Inspect the current page in Kasugai's browser: returns interactive elements with refs (e1, e2...), bounding rects, text summary, and console logs.",
                properties: [
                    "tab_id": ["type": "string"],
                    "max_elements": ["type": "integer"],
                ]
            ),
            mcpTool(
                name: "kasugai_browser_screenshot",
                description: "Capture a PNG screenshot of Kasugai's built-in browser view.",
                properties: [
                    "tab_id": ["type": "string"],
                    "output_path": ["type": "string"],
                ]
            ),
            mcpTool(
                name: "kasugai_browser_click",
                description:
                    "Click an element in Kasugai's browser by snapshot ref, CSS selector, or viewport coordinates.",
                properties: [
                    "tab_id": ["type": "string"],
                    "ref": ["type": "string"],
                    "selector": ["type": "string"],
                    "x": ["type": "number"],
                    "y": ["type": "number"],
                    "double_click": ["type": "boolean"],
                ]
            ),
            mcpTool(
                name: "kasugai_browser_type",
                description:
                    "Type text into an input, textarea, or contenteditable element in Kasugai's browser.",
                properties: [
                    "tab_id": ["type": "string"],
                    "ref": ["type": "string"],
                    "selector": ["type": "string"],
                    "text": ["type": "string"],
                    "clear": ["type": "boolean"],
                    "submit": ["type": "boolean"],
                ]
            ),
            mcpTool(
                name: "kasugai_browser_press",
                description:
                    "Send a keyboard key press to the focused element in Kasugai's browser.",
                properties: [
                    "tab_id": ["type": "string"],
                    "key": ["type": "string"],
                    "modifiers": ["type": "array", "items": ["type": "string"]],
                ]
            ),
            mcpTool(
                name: "kasugai_browser_drag",
                description:
                    "Drag and drop from a source element/coordinate to a target element/coordinate using stepped pointer + HTML5 DataTransfer events.",
                properties: [
                    "tab_id": ["type": "string"],
                    "from_ref": ["type": "string"],
                    "from_selector": ["type": "string"],
                    "from_x": ["type": "number"],
                    "from_y": ["type": "number"],
                    "to_ref": ["type": "string"],
                    "to_selector": ["type": "string"],
                    "to_x": ["type": "number"],
                    "to_y": ["type": "number"],
                    "steps": ["type": "integer"],
                    "mode": ["type": "string", "enum": ["auto", "pointer", "html5"]],
                ]
            ),
            mcpTool(
                name: "kasugai_browser_drop_files",
                description:
                    "Drop local files onto a dropzone or file input in Kasugai's browser.",
                properties: [
                    "tab_id": ["type": "string"],
                    "ref": ["type": "string"],
                    "selector": ["type": "string"],
                    "x": ["type": "number"],
                    "y": ["type": "number"],
                    "files": ["type": "array", "items": ["type": "string"]],
                ]
            ),
            mcpTool(
                name: "kasugai_browser_scroll",
                description: "Scroll the page or a scrollable container in Kasugai's browser.",
                properties: [
                    "tab_id": ["type": "string"],
                    "ref": ["type": "string"],
                    "selector": ["type": "string"],
                    "delta_x": ["type": "number"],
                    "delta_y": ["type": "number"],
                ]
            ),
            mcpTool(
                name: "kasugai_browser_eval",
                description:
                    "Evaluate a JavaScript expression in Kasugai's built-in browser and return its JSON result.",
                properties: [
                    "tab_id": ["type": "string"],
                    "expression": ["type": "string"],
                ]
            ),
        ]
    }

    static func handleMCPToolCall(
        name: String,
        arguments args: [String: Any],
        socketPath: String = LocalBrowserBridgePaths.defaultSocketPath()
    ) -> (text: String, ok: Bool)? {
        let action: String
        switch name {
        case "kasugai_browser_open":
            action = "open"
        case "kasugai_browser_tabs":
            let op = (args["operation"] as? String) ?? "list"
            if op == "select" {
                action = "select_tab"
            } else if op == "close" {
                action = "close_tab"
            } else {
                action = "tabs"
            }
        case "kasugai_browser_snapshot":
            action = "snapshot"
        case "kasugai_browser_screenshot":
            action = "screenshot"
        case "kasugai_browser_click":
            action = "click"
        case "kasugai_browser_type":
            action = "type"
        case "kasugai_browser_press":
            action = "press"
        case "kasugai_browser_drag":
            action = "drag"
        case "kasugai_browser_drop_files":
            action = "drop_files"
        case "kasugai_browser_scroll":
            action = "scroll"
        case "kasugai_browser_eval":
            action = "eval"
        default:
            return nil
        }

        let envThreadId = ProcessInfo.processInfo.environment["KASUGAI_THREAD_ID"].flatMap(
            Int64.init
        )
        let resolvedThreadId = (args["thread_id"] as? NSNumber)?.int64Value ?? envThreadId
        let req = BrowserBridgeRequest(
            action: action,
            threadId: resolvedThreadId,
            tabId: args["tab_id"] as? String,
            newTab: args["new_tab"] as? Bool,
            url: args["url"] as? String,
            ref: args["ref"] as? String,
            selector: args["selector"] as? String,
            x: (args["x"] as? NSNumber)?.doubleValue,
            y: (args["y"] as? NSNumber)?.doubleValue,
            doubleClick: args["double_click"] as? Bool,
            text: args["text"] as? String,
            clear: args["clear"] as? Bool,
            submit: args["submit"] as? Bool,
            key: args["key"] as? String,
            modifiers: args["modifiers"] as? [String],
            fromRef: args["from_ref"] as? String,
            fromSelector: args["from_selector"] as? String,
            fromX: (args["from_x"] as? NSNumber)?.doubleValue,
            fromY: (args["from_y"] as? NSNumber)?.doubleValue,
            toRef: args["to_ref"] as? String,
            toSelector: args["to_selector"] as? String,
            toX: (args["to_x"] as? NSNumber)?.doubleValue,
            toY: (args["to_y"] as? NSNumber)?.doubleValue,
            steps: (args["steps"] as? NSNumber)?.intValue,
            mode: args["mode"] as? String,
            files: args["files"] as? [String],
            deltaX: (args["delta_x"] as? NSNumber)?.doubleValue,
            deltaY: (args["delta_y"] as? NSNumber)?.doubleValue,
            expression: args["expression"] as? String,
            outputPath: args["output_path"] as? String,
            maxElements: (args["max_elements"] as? NSNumber)?.intValue,
            timeoutMs: (args["timeout_ms"] as? NSNumber)?.int64Value
        )

        guard let res = send(request: req, socketPath: socketPath),
            let data = try? JSONEncoder().encode(res),
            let str = String(data: data, encoding: .utf8)
        else {
            return ("{\"ok\":false,\"error\":\"browser bridge unavailable\"}", false)
        }
        return (str, res.ok)
    }

    private static func mcpTool(
        name: String,
        description: String,
        properties: [String: Any]
    ) -> [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": [
                "type": "object",
                "properties": properties,
            ],
        ]
    }
}

private final class SelfTestLoopbackHTTPServer {
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "dev.soyukke.kasugai.selftest-http")
    private let htmlBody: Data
    private(set) var port: UInt16 = 0

    init(html: String) {
        self.htmlBody = Data(html.utf8)
    }

    deinit {
        stop()
    }

    func start() -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            return false
        }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bound = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            close(fd)
            return false
        }
        var boundAddr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &boundAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                getsockname(fd, sockPtr, &len)
            }
        }
        guard named == 0 else {
            close(fd)
            return false
        }
        port = UInt16(bigEndian: boundAddr.sin_port)
        let flags = fcntl(fd, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }
        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptAll()
        }
        source.resume()
        acceptSource = source
        return true
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
    }

    private func acceptAll() {
        while listenFD >= 0 {
            let clientFD = accept(listenFD, nil, nil)
            if clientFD < 0 {
                break
            }
            var buf = [UInt8](repeating: 0, count: 1024)
            _ = read(clientFD, &buf, buf.count)
            let header =
                "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(htmlBody.count)\r\nConnection: close\r\n\r\n"
            var payload = Data(header.utf8)
            payload.append(htmlBody)
            LocalBrowserBridgeServer.writeAll(fd: clientFD, data: payload)
            close(clientFD)
        }
    }
}

private final class SelfTestBrowserHost: KasugaiBrowserAutomationHost {
    let tabId = UUID().uuidString
    let browserView: LocalPreviewBrowserView
    let window: NSWindow

    init() {
        _ = NSApplication.shared
        let frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        let win = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let view = LocalPreviewBrowserView(frame: frame)
        win.contentView = view
        win.layoutIfNeeded()
        self.window = win
        self.browserView = view
    }

    func browserTabsSummary(threadId: Int64?) -> [BrowserTabInfo] {
        [
            BrowserTabInfo(
                tabId: tabId,
                title: browserView.currentTitleString,
                url: browserView.currentURLString,
                active: true
            )
        ]
    }

    func browserEnsureTab(threadId: Int64?, tabId: String?, openNew: Bool) -> (
        tabId: String, view: LocalPreviewBrowserView
    )? {
        (self.tabId, browserView)
    }

    func browserSelectTab(threadId: Int64?, tabId: String) -> Bool {
        tabId == self.tabId
    }

    func browserCloseTab(threadId: Int64?, tabId: String) -> Bool {
        false
    }
}

extension LocalBrowserBridgeServer {
    static func runSelfTests() -> Bool {
        let html = """
            <!doctype html>
            <html>
            <head><meta charset="utf-8"><title>Kasugai Browser Test</title>
            <style>
              body { margin: 0; padding: 16px; font-family: sans-serif; }
              #card { width: 80px; height: 40px; background: #3b82f6; color: white; display: inline-block; }
              #dropzone { width: 120px; height: 60px; border: 2px dashed #888; margin-top: 12px; }
              #knob { position: absolute; left: 20px; top: 220px; width: 40px; height: 40px; background: #10b981; }
              #filezone { width: 140px; height: 50px; border: 1px solid #666; margin-top: 80px; }
            </style>
            </head>
            <body>
              <button id="inc">Count: 0</button>
              <input id="name" placeholder="Name" />
              <div id="card" draggable="true">Drag Me</div>
              <div id="dropzone" data-droppable="true">Drop Here</div>
              <div id="knob">Knob</div>
              <div id="filezone" data-droppable="true">Drop File</div>
              <input id="native-file" type="file" />
              <script>
                window.__state = { clicks: 0, html5Dropped: false, pointerMoves: 0, lastX: 0, fileNames: [], nativeFileNames: [] };
                const inc = document.getElementById('inc');
                inc.addEventListener('click', () => { window.__state.clicks += 1; inc.textContent = 'Count: ' + window.__state.clicks; });
                const card = document.getElementById('card');
                const dz = document.getElementById('dropzone');
                card.addEventListener('dragstart', (e) => { e.dataTransfer.setData('text/plain', 'card-1'); });
                dz.addEventListener('dragover', (e) => { e.preventDefault(); });
                dz.addEventListener('drop', (e) => { e.preventDefault(); window.__state.html5Dropped = e.dataTransfer.getData('text/plain') === 'card-1'; });
                const knob = document.getElementById('knob');
                let draggingKnob = false;
                knob.addEventListener('pointerdown', () => { draggingKnob = true; });
                window.addEventListener('pointermove', (e) => { if (draggingKnob) { window.__state.pointerMoves += 1; window.__state.lastX = Math.round(e.clientX); } });
                window.addEventListener('pointerup', () => { draggingKnob = false; });
                const fz = document.getElementById('filezone');
                fz.addEventListener('dragover', (e) => { e.preventDefault(); });
                fz.addEventListener('drop', (e) => { e.preventDefault(); window.__state.fileNames = Array.from(e.dataTransfer.files).map(f => f.name + ':' + f.size); });
                const nf = document.getElementById('native-file');
                nf.addEventListener('change', () => { window.__state.nativeFileNames = Array.from(nf.files).map(f => f.name + ':' + f.size); });
              </script>
            </body>
            </html>
            """
        let httpServer = SelfTestLoopbackHTTPServer(html: html)
        guard httpServer.start(), httpServer.port > 0 else {
            return false
        }
        defer { httpServer.stop() }

        let host = SelfTestBrowserHost()
        let sockPath = "/tmp/kasugai-browser-test-\(getpid())-\(UUID().uuidString.prefix(6)).sock"
        let server = LocalBrowserBridgeServer(socketPath: sockPath, host: host)
        guard server.start() else {
            return false
        }
        defer { server.stop() }

        let tempFile = "/tmp/kasugai-drop-test-\(UUID().uuidString.prefix(6)).txt"
        let screenshotFile = "/tmp/kasugai-shot-test-\(UUID().uuidString.prefix(6)).png"
        try? Data("hello-dnd".utf8).write(to: URL(fileURLWithPath: tempFile))
        defer {
            try? FileManager.default.removeItem(atPath: tempFile)
            try? FileManager.default.removeItem(atPath: screenshotFile)
        }

        let group = DispatchGroup()
        var passed = false
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { group.leave() }
            let url = "http://127.0.0.1:\(httpServer.port)/"
            guard
                let openRes = LocalBrowserBridgeClient.send(
                    request: BrowserBridgeRequest(action: "open", url: url),
                    socketPath: sockPath
                ),
                openRes.ok
            else {
                fputs("LocalBrowserBridge self-test: open failed\n", stderr)
                return
            }
            guard
                let blockedRes = LocalBrowserBridgeClient.send(
                    request: BrowserBridgeRequest(action: "open", url: "https://example.com"),
                    socketPath: sockPath
                ),
                !blockedRes.ok
            else {
                fputs("LocalBrowserBridge self-test: external URL was not blocked\n", stderr)
                return
            }
            guard
                let snapRes = LocalBrowserBridgeClient.send(
                    request: BrowserBridgeRequest(action: "snapshot"),
                    socketPath: sockPath
                ),
                snapRes.ok,
                let snap = snapRes.snapshot,
                snap.title == "Kasugai Browser Test",
                let incEl = snap.elements.first(where: { $0.text.contains("Count:") }),
                let inputEl = snap.elements.first(where: { $0.tag == "input" }),
                let cardEl = snap.elements.first(where: { $0.draggable })
            else {
                fputs("LocalBrowserBridge self-test: snapshot failed\n", stderr)
                return
            }
            guard
                let clickRes = LocalBrowserBridgeClient.send(
                    request: BrowserBridgeRequest(action: "click", ref: incEl.ref),
                    socketPath: sockPath
                ),
                clickRes.ok
            else {
                fputs("LocalBrowserBridge self-test: click failed\n", stderr)
                return
            }
            guard
                let typeRes = LocalBrowserBridgeClient.send(
                    request: BrowserBridgeRequest(
                        action: "type",
                        ref: inputEl.ref,
                        text: "Kasugai",
                        clear: true
                    ),
                    socketPath: sockPath
                ),
                typeRes.ok
            else {
                fputs("LocalBrowserBridge self-test: type failed\n", stderr)
                return
            }
            guard
                let html5DragRes = LocalBrowserBridgeClient.send(
                    request: BrowserBridgeRequest(
                        action: "drag",
                        fromRef: cardEl.ref,
                        toSelector: "#dropzone",
                        steps: 4,
                        mode: "auto"
                    ),
                    socketPath: sockPath
                ),
                html5DragRes.ok
            else {
                fputs("LocalBrowserBridge self-test: html5 drag failed\n", stderr)
                return
            }
            guard
                let ptrDragRes = LocalBrowserBridgeClient.send(
                    request: BrowserBridgeRequest(
                        action: "drag",
                        fromSelector: "#knob",
                        toX: 260,
                        toY: 240,
                        steps: 5,
                        mode: "pointer"
                    ),
                    socketPath: sockPath
                ),
                ptrDragRes.ok
            else {
                fputs("LocalBrowserBridge self-test: pointer drag failed\n", stderr)
                return
            }
            guard
                let dropRes = LocalBrowserBridgeClient.send(
                    request: BrowserBridgeRequest(
                        action: "drop_files",
                        selector: "#filezone",
                        files: [tempFile]
                    ),
                    socketPath: sockPath
                ),
                dropRes.ok
            else {
                fputs("LocalBrowserBridge self-test: drop_files failed\n", stderr)
                return
            }
            guard
                let nativeUploadRes = LocalBrowserBridgeClient.send(
                    request: BrowserBridgeRequest(
                        action: "drop_files",
                        selector: "#native-file",
                        files: [tempFile]
                    ),
                    socketPath: sockPath
                ),
                nativeUploadRes.ok
            else {
                fputs("LocalBrowserBridge self-test: native file input upload failed\n", stderr)
                return
            }
            guard
                let evalRes = LocalBrowserBridgeClient.send(
                    request: BrowserBridgeRequest(
                        action: "eval",
                        expression:
                            "({ clicks: window.__state.clicks, name: document.getElementById('name').value, html5: window.__state.html5Dropped, moves: window.__state.pointerMoves, lastX: window.__state.lastX, files: window.__state.fileNames, nativeFiles: window.__state.nativeFileNames })"
                    ),
                    socketPath: sockPath
                ),
                evalRes.ok,
                let detail = evalRes.detail,
                detail.contains("\"clicks\":1"),
                detail.contains("\"name\":\"Kasugai\""),
                detail.contains("\"html5\":true"),
                detail.contains("\"lastX\":260"),
                detail.contains("\"files\":[\""),
                detail.contains("\"nativeFiles\":[\""),
                detail.contains(":9")
            else {
                fputs("LocalBrowserBridge self-test: eval state mismatch\n", stderr)
                return
            }
            guard
                let shotRes = LocalBrowserBridgeClient.send(
                    request: BrowserBridgeRequest(action: "screenshot", outputPath: screenshotFile),
                    socketPath: sockPath
                ),
                shotRes.ok,
                let attrs = try? FileManager.default.attributesOfItem(atPath: screenshotFile),
                (attrs[.size] as? Int64 ?? 0) > 100
            else {
                fputs("LocalBrowserBridge self-test: screenshot failed\n", stderr)
                return
            }
            guard
                let mcpResult = LocalBrowserBridgeClient.handleMCPToolCall(
                    name: "kasugai_browser_tabs",
                    arguments: ["operation": "list"],
                    socketPath: sockPath
                ),
                mcpResult.ok,
                mcpResult.text.contains(host.tabId)
            else {
                fputs("LocalBrowserBridge self-test: mcp call failed\n", stderr)
                return
            }
            passed = true
        }
        let deadline = Date().addingTimeInterval(10.0)
        while group.wait(timeout: .now() + 0.01) == .timedOut && Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.01, false)
        }
        return passed
    }
}
