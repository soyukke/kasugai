import Darwin
import Foundation

struct OrchestratorRequest: Codable {
    let action: String
    let projectId: Int64?
    let threadId: Int64?
    let title: String?
    let provider: String?
    let model: String?
    let effort: String?
    let prompt: String?
    let worktreeBranch: String?
    let timeoutMs: Int64?
    var cwd: String? = nil
    var autoApprove: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case action
        case projectId = "project_id"
        case threadId = "thread_id"
        case title
        case provider
        case model
        case effort
        case prompt
        case worktreeBranch = "worktree_branch"
        case timeoutMs = "timeout_ms"
        case cwd
        case autoApprove = "auto_approve"
    }
}

struct OrchestratorThreadSummary: Codable {
    let id: Int64
    let projectId: Int64
    let title: String
    let status: String
    let provider: String
    let model: String
    let effort: String
    let effectiveCwd: String
    let messageCount: Int
    let queueCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case title
        case status
        case provider
        case model
        case effort
        case effectiveCwd = "effective_cwd"
        case messageCount = "message_count"
        case queueCount = "queue_count"
    }
}

struct OrchestratorResponse: Codable {
    let ok: Bool
    let error: String?
    let threadId: Int64?
    let turnId: Int64?
    let status: String?
    let threads: [OrchestratorThreadSummary]?
    let thread: KasugaiThread?

    enum CodingKeys: String, CodingKey {
        case ok
        case error
        case threadId = "thread_id"
        case turnId = "turn_id"
        case status
        case threads
        case thread
    }
}

final class LocalOrchestratorServer {
    let socketPath: String
    private let core: KasugaiCore
    private let onMutated: () -> Void
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "dev.soyukke.kasugai.orchestrator")

    static func defaultSocketPath() -> String {
        let dir = KasugaiRuntimePaths.dataDirectory()
            .appendingPathComponent("run", isDirectory: true)
        return dir.appendingPathComponent("ctl-\(getpid()).sock").path
    }

    init(
        socketPath: String = defaultSocketPath(), core: KasugaiCore, onMutated: @escaping () -> Void
    ) {
        self.socketPath = socketPath
        self.core = core
        self.onMutated = onMutated
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
            var recvTimeout = timeval(tv_sec: 15, tv_usec: 0)
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
        let response: OrchestratorResponse
        if let req = try? JSONDecoder().decode(OrchestratorRequest.self, from: Data(line.utf8)) {
            response = execute(request: req)
        } else {
            response = OrchestratorResponse(
                ok: false,
                error: "invalid request JSON",
                threadId: nil,
                turnId: nil,
                status: nil,
                threads: nil,
                thread: nil
            )
        }
        if let encoded = try? JSONEncoder().encode(response) {
            var framed = encoded
            framed.append(0x0A)
            Self.writeAll(fd: fd, data: framed)
        }
    }

    private func execute(request: OrchestratorRequest) -> OrchestratorResponse {
        switch request.action {
        case "list":
            return runOnCore { core in
                guard let snap = core.snapshot() else {
                    return Self.failure("snapshot unavailable")
                }
                let items = snap.threads.map { th in
                    OrchestratorThreadSummary(
                        id: th.id,
                        projectId: th.projectId,
                        title: th.title,
                        status: th.status,
                        provider: th.provider,
                        model: th.model,
                        effort: th.effort,
                        effectiveCwd: th.workspace.effectiveCwd,
                        messageCount: th.messages.count,
                        queueCount: th.queue.count
                    )
                }
                return OrchestratorResponse(
                    ok: true,
                    error: nil,
                    threadId: snap.activeThreadId,
                    turnId: nil,
                    status: nil,
                    threads: items,
                    thread: nil
                )
            }

        case "read":
            return runOnCoreDynamic { core in
                let polled = core.pollProviders()
                guard let snap = core.snapshot() else {
                    return (Self.failure("snapshot unavailable"), polled)
                }
                let targetId = request.threadId ?? snap.activeThreadId
                guard let thread = snap.threads.first(where: { $0.id == targetId }) else {
                    return (Self.failure("thread not found: \(targetId)"), polled)
                }
                return (
                    OrchestratorResponse(
                        ok: true,
                        error: nil,
                        threadId: thread.id,
                        turnId: nil,
                        status: thread.status,
                        threads: nil,
                        thread: thread
                    ),
                    polled
                )
            }

        case "launch":
            return runOnCore(mutates: true) { core in
                guard let snap = core.snapshot() else {
                    return Self.failure("snapshot unavailable")
                }
                let previousProjectId = snap.activeProjectId
                let previousThreadId = snap.activeThreadId
                var projectId = request.projectId ?? snap.activeProjectId
                if let rawCwd = request.cwd?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !rawCwd.isEmpty
                {
                    if let existing = snap.projects.first(where: { $0.rootPath == rawCwd }) {
                        projectId = existing.id
                    } else {
                        let name = URL(fileURLWithPath: rawCwd).lastPathComponent
                        if let createdProjectId = core.addProject(
                            name: name.isEmpty ? rawCwd : name,
                            rootPath: rawCwd
                        ) {
                            projectId = createdProjectId
                        }
                    }
                }
                let active = snap.activeThread
                let provider = request.provider ?? active?.provider ?? "local_echo"
                let model = request.model ?? ""
                let effort = request.effort ?? active?.effort ?? "medium"
                let title = request.title ?? ""
                guard
                    let newId = core.createThread(
                        projectId: projectId,
                        title: title,
                        provider: provider,
                        model: model,
                        effort: effort
                    )
                else {
                    if previousThreadId > 0 {
                        _ = core.selectThread(previousThreadId)
                    } else if previousProjectId > 0 {
                        _ = core.selectProject(previousProjectId)
                    }
                    return Self.failure("failed to create thread")
                }
                if let branch = request.worktreeBranch, !branch.isEmpty,
                    let proj = snap.projects.first(where: { $0.id == projectId })
                {
                    if case .success(let entry) = GitWorkspace.createWorktree(
                        in: proj.rootPath,
                        branch: branch
                    ) {
                        _ = core.bindWorktree(
                            threadId: newId,
                            branch: entry.branch,
                            baseRef: "HEAD",
                            worktreePath: entry.path
                        )
                    }
                }
                var turnId: Int64?
                if let prompt = request.prompt,
                    !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    turnId = core.sendMessage(threadId: newId, text: prompt)
                }
                if previousThreadId > 0 {
                    _ = core.selectThread(previousThreadId)
                } else if previousProjectId > 0 {
                    _ = core.selectProject(previousProjectId)
                }
                let created = core.snapshot()?.threads.first { $0.id == newId }
                return OrchestratorResponse(
                    ok: true,
                    error: nil,
                    threadId: newId,
                    turnId: turnId,
                    status: created?.status,
                    threads: nil,
                    thread: created
                )
            }

        case "send":
            guard let prompt = request.prompt,
                !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return Self.failure("prompt is required")
            }
            return runOnCore(mutates: true) { core in
                guard let snap = core.snapshot() else {
                    return Self.failure("snapshot unavailable")
                }
                let previousThreadId = snap.activeThreadId
                let targetId = request.threadId ?? snap.activeThreadId
                guard let turnId = core.sendMessage(threadId: targetId, text: prompt) else {
                    return Self.failure("failed to send message to thread \(targetId)")
                }
                if previousThreadId > 0, core.snapshot()?.activeThreadId != previousThreadId {
                    _ = core.selectThread(previousThreadId)
                }
                let updated = core.snapshot()?.threads.first { $0.id == targetId }
                return OrchestratorResponse(
                    ok: true,
                    error: nil,
                    threadId: targetId,
                    turnId: turnId,
                    status: updated?.status,
                    threads: nil,
                    thread: updated
                )
            }

        case "wait":
            let timeout = max(100, min(request.timeoutMs ?? 15000, 120000))
            let deadline = Date().addingTimeInterval(Double(timeout) / 1000.0)
            let autoApprove = request.autoApprove == true
            var firstCheck = true
            var lastSnapshotAt = Date.distantPast
            var lastResponse: OrchestratorResponse?
            while true {
                let now = Date()
                let shouldSnapshot = firstCheck || now.timeIntervalSince(lastSnapshotAt) >= 0.35
                if let res = runOnCoreWaitCheck(
                    shouldSnapshotIfUnchanged: shouldSnapshot,
                    targetThreadId: request.threadId,
                    autoApprove: autoApprove
                ) {
                    firstCheck = false
                    lastSnapshotAt = now
                    lastResponse = res
                    let stillActive =
                        res.status == "running"
                        || (autoApprove && res.status == "awaiting_approval")
                    if !res.ok || !stillActive || now >= deadline {
                        return res
                    }
                } else if now >= deadline {
                    if let finalRes = runOnCoreWaitCheck(
                        shouldSnapshotIfUnchanged: true,
                        targetThreadId: request.threadId,
                        autoApprove: autoApprove
                    ) {
                        return finalRes
                    }
                    return lastResponse ?? Self.failure("snapshot unavailable")
                }
                usleep(100_000)
            }

        default:
            return Self.failure("unknown action: \(request.action)")
        }
    }

    private func runOnCore(
        mutates: Bool = false,
        _ block: (KasugaiCore) -> OrchestratorResponse
    ) -> OrchestratorResponse {
        runOnCoreDynamic { core in
            (block(core), mutates)
        }
    }

    private func runOnCoreDynamic(
        _ block: (KasugaiCore) -> (OrchestratorResponse, Bool)
    ) -> OrchestratorResponse {
        if Thread.isMainThread {
            let (result, mutated) = block(core)
            if mutated {
                onMutated()
            }
            return result
        }
        var output = Self.failure("dispatch error")
        DispatchQueue.main.sync {
            let (result, mutated) = block(self.core)
            output = result
            if mutated {
                self.onMutated()
            }
        }
        return output
    }

    private func runOnCoreWaitCheck(
        shouldSnapshotIfUnchanged: Bool,
        targetThreadId: Int64?,
        autoApprove: Bool
    ) -> OrchestratorResponse? {
        let perform: () -> OrchestratorResponse? = {
            let polled = self.core.pollProviders()
            guard polled || shouldSnapshotIfUnchanged else {
                return nil
            }
            guard let snap = self.core.snapshot() else {
                if polled {
                    self.onMutated()
                }
                return Self.failure("snapshot unavailable")
            }
            let resolvedId = targetThreadId ?? snap.activeThreadId
            guard let thread = snap.threads.first(where: { $0.id == resolvedId }) else {
                if polled {
                    self.onMutated()
                }
                return Self.failure("thread not found: \(resolvedId)")
            }
            var approved = false
            if autoApprove && thread.status == "awaiting_approval" {
                approved = self.core.resolveApproval(threadId: resolvedId, approve: true)
            }
            if polled || approved {
                self.onMutated()
            }
            return OrchestratorResponse(
                ok: true,
                error: nil,
                threadId: thread.id,
                turnId: nil,
                status: thread.status,
                threads: nil,
                thread: thread
            )
        }
        if Thread.isMainThread {
            return perform()
        }
        var output: OrchestratorResponse?
        DispatchQueue.main.sync {
            output = perform()
        }
        return output
    }

    private static func failure(_ message: String) -> OrchestratorResponse {
        OrchestratorResponse(
            ok: false,
            error: message,
            threadId: nil,
            turnId: nil,
            status: nil,
            threads: nil,
            thread: nil
        )
    }

    fileprivate static func readLine(fd: Int32) -> String? {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while buffer.count < 1_048_576 {
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

enum LocalOrchestratorClient {
    static func send(request: OrchestratorRequest, socketPath: String) -> OrchestratorResponse? {
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
        LocalOrchestratorServer.writeAll(fd: fd, data: encoded)
        guard let line = LocalOrchestratorServer.readLine(fd: fd),
            let response = try? JSONDecoder().decode(
                OrchestratorResponse.self, from: Data(line.utf8))
        else {
            return nil
        }
        return response
    }

    static func runCLI(arguments: [String]) -> Int32 {
        if arguments.first == "browser" {
            return LocalBrowserBridgeClient.runCLI(arguments: Array(arguments.dropFirst()))
        }
        guard let socketPath = ProcessInfo.processInfo.environment["KASUGAI_CTL_SOCKET"],
            !socketPath.isEmpty
        else {
            fputs("KASUGAI_CTL_SOCKET is not set\n", stderr)
            return 2
        }
        guard let subcommand = arguments.first else {
            fputs("usage: Kasugai ctl <list|launch|read|send|wait|browser> [options]\n", stderr)
            return 2
        }
        let rest = Array(arguments.dropFirst())
        let req = buildCLIRequest(action: subcommand, args: rest)
        guard let response = send(request: req, socketPath: socketPath),
            let data = try? JSONEncoder().encode(response),
            let text = String(data: data, encoding: .utf8)
        else {
            fputs("failed to communicate with Kasugai control socket\n", stderr)
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

    private static func buildCLIRequest(action: String, args: [String]) -> OrchestratorRequest {
        OrchestratorRequest(
            action: action,
            projectId: optionValue("--project", in: args).flatMap(Int64.init),
            threadId: optionValue("--thread", in: args).flatMap(Int64.init),
            title: optionValue("--title", in: args),
            provider: optionValue("--provider", in: args),
            model: optionValue("--model", in: args),
            effort: optionValue("--effort", in: args),
            prompt: optionValue("--prompt", in: args),
            worktreeBranch: optionValue("--worktree", in: args),
            timeoutMs: optionValue("--timeout-ms", in: args).flatMap(Int64.init),
            cwd: optionValue("--cwd", in: args),
            autoApprove: args.contains("--auto-approve") ? true : nil
        )
    }

    static func handleMCPLine(_ line: String, socketPath: String) -> String? {
        guard
            let jsonObj = try? JSONSerialization.jsonObject(with: Data(line.utf8))
                as? [String: Any],
            let method = jsonObj["method"] as? String
        else {
            return nil
        }
        let idValue = jsonObj["id"]
        if method == "notifications/initialized" {
            return nil
        }
        if method == "initialize" {
            let reply: [String: Any] = [
                "jsonrpc": "2.0",
                "id": idValue ?? 0,
                "result": [
                    "protocolVersion": "2024-11-05",
                    "capabilities": ["tools": [:]],
                    "serverInfo": ["name": "kasugai-local-orchestrator", "version": "0.1.0"],
                ],
            ]
            return serializeJSON(reply)
        }
        if method == "tools/list" {
            var tools: [[String: Any]] = [
                mcpToolDef(
                    name: "kasugai_list_threads",
                    description: "List all Kasugai threads and their statuses.",
                    properties: [:]
                ),
                mcpToolDef(
                    name: "kasugai_launch_thread",
                    description:
                        "Create a new Kasugai thread and optionally send an initial prompt.",
                    properties: [
                        "title": ["type": "string"],
                        "provider": ["type": "string"],
                        "model": ["type": "string"],
                        "effort": ["type": "string"],
                        "prompt": ["type": "string"],
                        "worktree_branch": ["type": "string"],
                    ]
                ),
                mcpToolDef(
                    name: "kasugai_read_thread",
                    description: "Read messages, activities, and status of a Kasugai thread.",
                    properties: ["thread_id": ["type": "integer"]]
                ),
                mcpToolDef(
                    name: "kasugai_send_thread",
                    description: "Send or enqueue a prompt to an existing Kasugai thread.",
                    properties: [
                        "thread_id": ["type": "integer"],
                        "prompt": ["type": "string"],
                    ]
                ),
                mcpToolDef(
                    name: "kasugai_wait_thread",
                    description: "Wait until a Kasugai thread finishes running its active turn.",
                    properties: [
                        "thread_id": ["type": "integer"],
                        "timeout_ms": ["type": "integer"],
                    ]
                ),
            ]
            tools.append(contentsOf: LocalBrowserBridgeClient.mcpToolDefinitions())
            let reply: [String: Any] = [
                "jsonrpc": "2.0",
                "id": idValue ?? 0,
                "result": ["tools": tools],
            ]
            return serializeJSON(reply)
        }
        if method == "tools/call",
            let params = jsonObj["params"] as? [String: Any],
            let name = params["name"] as? String
        {
            let args = params["arguments"] as? [String: Any] ?? [:]
            if let browserResult = LocalBrowserBridgeClient.handleMCPToolCall(
                name: name,
                arguments: args
            ) {
                let reply: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": idValue ?? 0,
                    "result": [
                        "content": [["type": "text", "text": browserResult.text]],
                        "isError": !browserResult.ok,
                    ],
                ]
                return serializeJSON(reply)
            }
            guard !socketPath.isEmpty else {
                let reply: [String: Any] = [
                    "jsonrpc": "2.0",
                    "id": idValue ?? 0,
                    "result": [
                        "content": [
                            [
                                "type": "text",
                                "text":
                                    "{\"ok\":false,\"error\":\"KASUGAI_CTL_SOCKET is not set\"}",
                            ]
                        ],
                        "isError": true,
                    ],
                ]
                return serializeJSON(reply)
            }
            let action: String
            switch name {
            case "kasugai_list_threads":
                action = "list"
            case "kasugai_launch_thread":
                action = "launch"
            case "kasugai_read_thread":
                action = "read"
            case "kasugai_send_thread":
                action = "send"
            case "kasugai_wait_thread":
                action = "wait"
            default:
                action = ""
            }
            let req = OrchestratorRequest(
                action: action,
                projectId: (args["project_id"] as? NSNumber)?.int64Value,
                threadId: (args["thread_id"] as? NSNumber)?.int64Value,
                title: args["title"] as? String,
                provider: args["provider"] as? String,
                model: args["model"] as? String,
                effort: args["effort"] as? String,
                prompt: args["prompt"] as? String,
                worktreeBranch: args["worktree_branch"] as? String,
                timeoutMs: (args["timeout_ms"] as? NSNumber)?.int64Value
            )
            let res = send(request: req, socketPath: socketPath)
            let resText: String
            if let res, let data = try? JSONEncoder().encode(res),
                let str = String(data: data, encoding: .utf8)
            {
                resText = str
            } else {
                resText = "{\"ok\":false,\"error\":\"bridge unavailable\"}"
            }
            let reply: [String: Any] = [
                "jsonrpc": "2.0",
                "id": idValue ?? 0,
                "result": [
                    "content": [["type": "text", "text": resText]],
                    "isError": !(res?.ok ?? false),
                ],
            ]
            return serializeJSON(reply)
        }
        return nil
    }

    static func runMCPStdio() -> Int32 {
        let socketPath = ProcessInfo.processInfo.environment["KASUGAI_CTL_SOCKET"] ?? ""
        while let line = Swift.readLine(strippingNewline: true) {
            if let reply = handleMCPLine(line, socketPath: socketPath) {
                print(reply)
                fflush(stdout)
            }
        }
        return 0
    }

    private static func mcpToolDef(
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

    private static func serializeJSON(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func runSelfTests() -> Bool {
        guard let core = KasugaiCore(projectName: "Kasugai", projectPath: "/tmp") else {
            return false
        }
        let sockPath = "/tmp/kasugai-ctl-test-\(getpid())-\(UUID().uuidString.prefix(6)).sock"
        var mutatedCount = 0
        let server = LocalOrchestratorServer(socketPath: sockPath, core: core) {
            mutatedCount += 1
        }
        guard server.start() else {
            return false
        }
        defer { server.stop() }

        let group = DispatchGroup()
        var passed = false
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { group.leave() }
            let launchReq = OrchestratorRequest(
                action: "launch",
                projectId: nil,
                threadId: nil,
                title: "子セッション",
                provider: "local_echo",
                model: "local-echo",
                effort: "medium",
                prompt: "別スレッド確認",
                worktreeBranch: nil,
                timeoutMs: nil
            )
            guard let launched = send(request: launchReq, socketPath: sockPath),
                launched.ok,
                let childId = launched.threadId,
                childId == 2
            else {
                return
            }
            let sendReq = OrchestratorRequest(
                action: "send",
                projectId: nil,
                threadId: childId,
                title: nil,
                provider: nil,
                model: nil,
                effort: nil,
                prompt: "追加指示",
                worktreeBranch: nil,
                timeoutMs: nil
            )
            guard let sent = send(request: sendReq, socketPath: sockPath),
                sent.ok
            else {
                return
            }
            let waitReq = OrchestratorRequest(
                action: "wait",
                projectId: nil,
                threadId: childId,
                title: nil,
                provider: nil,
                model: nil,
                effort: nil,
                prompt: nil,
                worktreeBranch: nil,
                timeoutMs: 1000
            )
            guard let waited = send(request: waitReq, socketPath: sockPath),
                waited.ok,
                waited.status == "idle"
            else {
                return
            }
            let readReq = OrchestratorRequest(
                action: "read",
                projectId: nil,
                threadId: childId,
                title: nil,
                provider: nil,
                model: nil,
                effort: nil,
                prompt: nil,
                worktreeBranch: nil,
                timeoutMs: nil
            )
            guard let readRes = send(request: readReq, socketPath: sockPath),
                readRes.ok,
                readRes.thread?.messages.count == 4
            else {
                return
            }
            let listReq = OrchestratorRequest(
                action: "list",
                projectId: nil,
                threadId: nil,
                title: nil,
                provider: nil,
                model: nil,
                effort: nil,
                prompt: nil,
                worktreeBranch: nil,
                timeoutMs: nil
            )
            guard let listRes = send(request: listReq, socketPath: sockPath),
                listRes.ok,
                listRes.threadId == 1,
                listRes.threads?.count == 2
            else {
                return
            }
            let mcpCall =
                "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"kasugai_list_threads\",\"arguments\":{}}}"
            guard let mcpReply = handleMCPLine(mcpCall, socketPath: sockPath),
                mcpReply.contains("子セッション")
            else {
                return
            }
            passed = true
        }
        while group.wait(timeout: .now() + 0.01) == .timedOut {
            CFRunLoopRunInMode(.defaultMode, 0.01, false)
        }
        return passed && mutatedCount == 2
    }
}
