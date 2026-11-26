import Darwin
import Foundation

@_silgen_name("flock")
private func posixFlock(_ fd: Int32, _ operation: Int32) -> Int32

enum KasugaiDaemonPaths {
    static func defaultSocketPath(
        env: [String: String] = ProcessInfo.processInfo.environment,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> String {
        if let override = env["KASUGAI_DAEMON_SOCKET"], !override.isEmpty {
            return override
        }
        return KasugaiRuntimePaths.dataDirectory(
            env: env,
            bundleIdentifier: bundleIdentifier
        )
        .appendingPathComponent("run", isDirectory: true)
        .appendingPathComponent("daemon.sock")
        .path
    }

    static func daemonExecutablePath(
        for currentExecutablePath: String = Bundle.main.executableURL?.path
            ?? CommandLine.arguments[0],
        isDevBundle: Bool = KasugaiRuntimePaths.isDevBundle
    ) -> String {
        let currentURL = URL(fileURLWithPath: currentExecutablePath)
        let dir = currentURL.deletingLastPathComponent()
        let helperName = isDevBundle ? "kasugaid-dev" : "kasugaid"
        let helperURL = dir.appendingPathComponent(helperName)
        if FileManager.default.isExecutableFile(atPath: helperURL.path) {
            return helperURL.path
        }
        return currentExecutablePath
    }

    static func binaryStamp(atPath path: String) -> String {
        let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: resolvedPath) else {
            return "unknown"
        }
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let mtimeMs = Int64((mtime * 1000.0).rounded())
        return "\(size)-\(mtimeMs)"
    }
}

struct DaemonHello: Codable, Equatable {
    let pid: Int32
    let buildId: String
    let storePath: String
    let orchestratorSocket: String
    let activeTurnCount: Int
    let liveSessionCount: Int

    enum CodingKeys: String, CodingKey {
        case pid
        case buildId = "build_id"
        case storePath = "store_path"
        case orchestratorSocket = "orchestrator_socket"
        case activeTurnCount = "active_turn_count"
        case liveSessionCount = "live_session_count"
    }
}

struct DaemonRequest: Codable {
    let method: String
    var projectId: Int64?
    var threadId: Int64?
    var turnId: Int64?
    var name: String?
    var rootPath: String?
    var title: String?
    var provider: String?
    var model: String?
    var effort: String?
    var text: String?
    var attachments: [String]?
    var approve: Bool?
    var enabled: Bool?
    var socketPath: String?
    var ctlBin: String?
    var executable: String?
    var arguments: [String]?
    var branch: String?
    var baseRef: String?
    var worktreePath: String?
    var filesChanged: Int64?
    var insertions: Int64?
    var deletions: Int64?
    var localPort: UInt16?
    var httpsPort: UInt16?
    var deviceId: String?
    var manageTailscale: Bool?

    enum CodingKeys: String, CodingKey {
        case method
        case projectId = "project_id"
        case threadId = "thread_id"
        case turnId = "turn_id"
        case name
        case rootPath = "root_path"
        case title
        case provider
        case model
        case effort
        case text
        case attachments
        case approve
        case enabled
        case socketPath = "socket_path"
        case ctlBin = "ctl_bin"
        case executable
        case arguments
        case branch
        case baseRef = "base_ref"
        case worktreePath = "worktree_path"
        case filesChanged = "files_changed"
        case insertions
        case deletions
        case localPort = "local_port"
        case httpsPort = "https_port"
        case deviceId = "device_id"
        case manageTailscale = "manage_tailscale"
    }
}

struct DaemonResponse: Codable {
    let ok: Bool
    let error: String?
    let intValue: Int64?
    let boolValue: Bool?
    let stringValue: String?
    let hello: DaemonHello?

    enum CodingKeys: String, CodingKey {
        case ok
        case error
        case intValue = "int_value"
        case boolValue = "bool_value"
        case stringValue = "string_value"
        case hello
    }

    static func failure(_ message: String) -> DaemonResponse {
        DaemonResponse(
            ok: false,
            error: message,
            intValue: nil,
            boolValue: nil,
            stringValue: nil,
            hello: nil
        )
    }
}

private enum UnixSocketIO {
    static func connect(path: String, timeoutSeconds: Int) -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            return -1
        }
        var noSigPipe: Int32 = 1
        setsockopt(
            fd,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSigPipe,
            socklen_t(MemoryLayout<Int32>.size)
        )
        if timeoutSeconds > 0 {
            var tv = timeval(tv_sec: timeoutSeconds, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        }

        var addr = sockaddr_un()
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count < maxLen else {
            close(fd)
            return -1
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for idx in 0..<bytes.count {
                raw[idx] = bytes[idx]
            }
            raw[bytes.count] = 0
        }

        let rc = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else {
            close(fd)
            return -1
        }
        return fd
    }

    @discardableResult
    static func writeAll(fd: Int32, data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else {
                return true
            }
            var offset = 0
            while offset < data.count {
                let written = Darwin.write(fd, base.advanced(by: offset), data.count - offset)
                if written <= 0 {
                    if written < 0 && errno == EINTR {
                        continue
                    }
                    return false
                }
                offset += written
            }
            return true
        }
    }

    static func readLine(fd: Int32, maxBytes: Int = 32 * 1024 * 1024) -> String? {
        var collected = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while collected.count < maxBytes {
            let n = Darwin.read(fd, &buffer, buffer.count)
            if n < 0 {
                if errno == EINTR {
                    continue
                }
                return nil
            }
            if n == 0 {
                break
            }
            if let nl = buffer[0..<n].firstIndex(of: 0x0A) {
                collected.append(contentsOf: buffer[0..<nl])
                break
            }
            collected.append(contentsOf: buffer[0..<n])
        }
        guard !collected.isEmpty else {
            return nil
        }
        return String(data: collected, encoding: .utf8)
    }
}

final class KasugaiDaemonServer {
    private let socketPath: String
    private let lockPath: String
    private let storePath: String
    private let buildId: String
    private let idleTimeoutSeconds: TimeInterval
    private let warmIdleTimeoutSeconds: TimeInterval
    private let core: KasugaiCore
    private let acceptQueue = DispatchQueue(label: "dev.soyukke.kasugai.daemon.accept")
    private var lockFD: Int32
    private var listenFD: Int32 = -1
    private var boundSocketInode: UInt64 = 0
    private var acceptSource: DispatchSourceRead?
    private var watchdogTimer: DispatchSourceTimer?
    private var idleSince: Date?
    private var wakeupSources: [Int32: DispatchSourceRead] = [:]
    private var subscribers: [Int32: DispatchSourceRead] = [:]
    private var orchestratorServer: LocalOrchestratorServer?
    private var mobileBridge: MobileBridgeServer?
    private var signalSources: [DispatchSourceSignal] = []

    static func acquireExclusiveLock(lockPath: String) -> Int32 {
        let dir = URL(fileURLWithPath: lockPath).deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            return -1
        }
        let fd = Darwin.open(lockPath, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else {
            return -1
        }
        guard posixFlock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return -1
        }
        _ = ftruncate(fd, 0)
        let pidLine = Data("\(getpid())\n".utf8)
        _ = UnixSocketIO.writeAll(fd: fd, data: pidLine)
        return fd
    }

    init?(
        socketPath: String,
        lockPath: String,
        lockFD: Int32,
        storePath: String,
        projectName: String,
        projectPath: String,
        buildId: String,
        idleTimeoutSeconds: TimeInterval,
        warmIdleTimeoutSeconds: TimeInterval
    ) {
        guard
            let directCore = KasugaiCore(
                projectName: projectName,
                projectPath: projectPath,
                storePath: storePath
            )
        else {
            close(lockFD)
            return nil
        }
        self.socketPath = socketPath
        self.lockPath = lockPath
        self.lockFD = lockFD
        self.storePath = storePath
        self.buildId = buildId
        self.idleTimeoutSeconds = idleTimeoutSeconds
        self.warmIdleTimeoutSeconds = warmIdleTimeoutSeconds
        self.core = directCore
    }

    deinit {
        stop()
    }

    @discardableResult
    func start() -> Bool {
        stopTransportOnly()
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
        let bytes = Array(socketPath.utf8)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard bytes.count < maxLen else {
            close(fd)
            return false
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for idx in 0..<bytes.count {
                raw[idx] = bytes[idx]
            }
            raw[bytes.count] = 0
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
        boundSocketInode = Self.socketInode(atPath: socketPath)
        guard listen(fd, 32) == 0 else {
            close(fd)
            unlink(socketPath)
            boundSocketInode = 0
            return false
        }
        let flags = fcntl(fd, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }
        listenFD = fd

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: acceptQueue)
        source.setEventHandler { [weak self] in
            self?.acceptPendingClients()
        }
        source.resume()
        acceptSource = source
        startWatchdog()
        return true
    }

    private static func socketInode(atPath path: String) -> UInt64 {
        var st = stat()
        guard Darwin.lstat(path, &st) == 0 else {
            return 0
        }
        return st.st_ino
    }

    private func startWatchdog() {
        watchdogTimer?.cancel()
        let interval = max(0.05, min(5.0, idleTimeoutSeconds > 0 ? idleTimeoutSeconds / 2.0 : 5.0))
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.checkHealthOnMain()
        }
        timer.resume()
        watchdogTimer = timer
    }

    private func checkHealthOnMain() {
        let hello = buildHelloOnMain()
        if boundSocketInode != 0 && Self.socketInode(atPath: socketPath) != boundSocketInode {
            if hello.activeTurnCount == 0 {
                stop()
                exit(0)
            }
            return
        }
        if !subscribers.isEmpty || hello.activeTurnCount > 0 || (mobileBridge?.isRunning ?? false) {
            idleSince = nil
            return
        }
        guard idleTimeoutSeconds > 0 else {
            return
        }
        let now = Date()
        let started = idleSince ?? now
        idleSince = started
        let limit = hello.liveSessionCount > 0 ? warmIdleTimeoutSeconds : idleTimeoutSeconds
        if now.timeIntervalSince(started) >= limit {
            stop()
            exit(0)
        }
    }

    private func stopTransportOnly() {
        watchdogTimer?.cancel()
        watchdogTimer = nil
        acceptSource?.cancel()
        acceptSource = nil
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        for (_, source) in wakeupSources {
            source.cancel()
        }
        wakeupSources.removeAll()
        for (fd, source) in subscribers {
            source.cancel()
            close(fd)
        }
        subscribers.removeAll()
        orchestratorServer?.stop()
        orchestratorServer = nil
        mobileBridge?.stop(disableTailscaleServe: false)
        mobileBridge = nil
        if boundSocketInode != 0 && Self.socketInode(atPath: socketPath) == boundSocketInode {
            unlink(socketPath)
        }
        boundSocketInode = 0
    }

    func stop() {
        stopTransportOnly()
        core.close()
        if lockFD >= 0 {
            _ = posixFlock(lockFD, LOCK_UN)
            close(lockFD)
            lockFD = -1
        }
    }

    func installSignalHandlers() {
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT, SIG_IGN)
        for sig in [SIGTERM, SIGINT] {
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                self?.stop()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
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
        guard let line = UnixSocketIO.readLine(fd: fd), !line.isEmpty else {
            close(fd)
            return
        }
        guard let request = try? JSONDecoder().decode(DaemonRequest.self, from: Data(line.utf8))
        else {
            writeResponse(DaemonResponse.failure("invalid request JSON"), to: fd)
            close(fd)
            return
        }

        if request.method == "subscribe" {
            var zeroTimeout = timeval(tv_sec: 0, tv_usec: 0)
            setsockopt(
                fd,
                SOL_SOCKET,
                SO_RCVTIMEO,
                &zeroTimeout,
                socklen_t(MemoryLayout<timeval>.size)
            )
            let flags = fcntl(fd, F_GETFL, 0)
            if flags >= 0 {
                _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
            }
            let ready = Data("{\"event\":\"ready\"}\n".utf8)
            guard UnixSocketIO.writeAll(fd: fd, data: ready) else {
                close(fd)
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.addSubscriberOnMain(fd: fd)
            }
            return
        }

        if request.method == "configure_mobile_bridge"
            || request.method == "mobile_bridge_status"
            || request.method == "mobile_bridge_generate_pairing"
            || request.method == "mobile_bridge_revoke_device"
        {
            let response = executeMobileBridgeRequest(request)
            writeResponse(response, to: fd)
            close(fd)
            return
        }

        let shouldShutdown = request.method == "shutdown"
        let response: DaemonResponse = DispatchQueue.main.sync {
            executeOnMain(request)
        }
        writeResponse(response, to: fd)
        close(fd)

        if shouldShutdown && response.ok {
            DispatchQueue.main.async { [weak self] in
                self?.stop()
                exit(0)
            }
        }
    }

    private func writeResponse(_ response: DaemonResponse, to fd: Int32) {
        guard let encoded = try? JSONEncoder().encode(response) else {
            return
        }
        var framed = encoded
        framed.append(0x0A)
        _ = UnixSocketIO.writeAll(fd: fd, data: framed)
    }

    private func addSubscriberOnMain(fd: Int32) {
        idleSince = nil
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            var scratch = [UInt8](repeating: 0, count: 64)
            let n = Darwin.read(fd, &scratch, scratch.count)
            if n <= 0 && errno != EAGAIN && errno != EWOULDBLOCK {
                self?.removeSubscriberOnMain(fd: fd)
            }
        }
        source.resume()
        subscribers[fd] = source
    }

    private func removeSubscriberOnMain(fd: Int32) {
        if let source = subscribers.removeValue(forKey: fd) {
            source.cancel()
        }
        close(fd)
    }

    private func broadcastChangedOnMain() {
        let payload = Data("{\"event\":\"changed\"}\n".utf8)
        var deadFDs: [Int32] = []
        for fd in subscribers.keys {
            if !UnixSocketIO.writeAll(fd: fd, data: payload) {
                deadFDs.append(fd)
            }
        }
        for fd in deadFDs {
            removeSubscriberOnMain(fd: fd)
        }
        mobileBridge?.notifyChanged()
    }

    private func ensureMobileBridge() -> MobileBridgeServer {
        DispatchQueue.main.sync {
            if let existing = mobileBridge {
                return existing
            }
            let authPath = URL(fileURLWithPath: storePath)
                .deletingLastPathComponent()
                .appendingPathComponent("mobile-bridge.json")
                .path
            let created = MobileBridgeServer(
                authStorePath: authPath,
                fetchSnapshotJSONOnMain: { [weak self] in
                    self?.core.snapshotJSON()
                },
                fetchThreadWorkspaceOnMain: { [weak self] tid in
                    self?.core.snapshot()?.threads.first(where: { $0.id == tid })
                },
                executeActionOnMain: { [weak self] req in
                    guard let self else {
                        return .failure("daemon unavailable")
                    }
                    return self.executeOnMain(req)
                }
            )
            mobileBridge = created
            return created
        }
    }

    private func encodeMobileStatusResponse(_ status: MobileBridgeStatusSnapshot) -> DaemonResponse
    {
        guard let data = try? JSONEncoder().encode(status),
            let json = String(data: data, encoding: .utf8)
        else {
            return .failure("mobile status encode failed")
        }
        return DaemonResponse(
            ok: true,
            error: nil,
            intValue: nil,
            boolValue: status.running,
            stringValue: json,
            hello: nil
        )
    }

    private func executeMobileBridgeRequest(_ req: DaemonRequest) -> DaemonResponse {
        let bridge = ensureMobileBridge()
        switch req.method {
        case "configure_mobile_bridge":
            let enabled = req.enabled ?? false
            let localPort = req.localPort ?? MobileBridgeDefaults.defaultLocalPort
            let httpsPort = req.httpsPort ?? MobileBridgeDefaults.defaultTailscaleHttpsPort
            let manageTailscale = req.manageTailscale ?? true
            let status = bridge.configure(
                enabled: enabled,
                localPort: localPort,
                httpsPort: httpsPort,
                manageTailscaleServe: manageTailscale
            )
            return encodeMobileStatusResponse(status)
        case "mobile_bridge_status":
            let refreshTailscale = req.manageTailscale ?? true
            return encodeMobileStatusResponse(
                bridge.statusSnapshot(refreshTailscale: refreshTailscale))
        case "mobile_bridge_generate_pairing":
            return encodeMobileStatusResponse(bridge.generatePairingCode())
        case "mobile_bridge_revoke_device":
            let id = req.deviceId ?? ""
            let status =
                id.isEmpty ? bridge.revokeAllDevices() : bridge.revokeDevice(id: id)
            return encodeMobileStatusResponse(status)
        default:
            return .failure("unknown mobile bridge method")
        }
    }

    private func syncProviderWakeupSourcesOnMain() {
        let activeFDs = Set(core.providerWakeupFDs().map(\.fd))
        let existingFDs = Set(wakeupSources.keys)

        for obsolete in existingFDs.subtracting(activeFDs) {
            wakeupSources[obsolete]?.cancel()
            wakeupSources.removeValue(forKey: obsolete)
        }

        for fd in activeFDs.subtracting(existingFDs) where fd >= 0 {
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
            source.setEventHandler { [weak self] in
                self?.pollProvidersOnMain()
            }
            source.resume()
            wakeupSources[fd] = source
        }
    }

    private func pollProvidersOnMain() {
        let changed = core.pollProviders()
        syncProviderWakeupSourcesOnMain()
        if changed {
            broadcastChangedOnMain()
        }
    }

    private func buildHelloOnMain() -> DaemonHello {
        let snap = core.snapshot()
        let activeTurns =
            snap?.threads.filter { $0.status == "running" || $0.status == "awaiting_approval" }
            .count ?? 0
        let liveSessions = core.providerWakeupFDs().count
        return DaemonHello(
            pid: getpid(),
            buildId: buildId,
            storePath: storePath,
            orchestratorSocket: orchestratorServer?.socketPath ?? "",
            activeTurnCount: activeTurns,
            liveSessionCount: liveSessions
        )
    }

    private func executeOnMain(_ req: DaemonRequest) -> DaemonResponse {
        idleSince = nil
        var mutated = false
        let response: DaemonResponse

        switch req.method {
        case "hello":
            response = DaemonResponse(
                ok: true,
                error: nil,
                intValue: nil,
                boolValue: nil,
                stringValue: nil,
                hello: buildHelloOnMain()
            )
        case "shutdown":
            response = DaemonResponse(
                ok: true,
                error: nil,
                intValue: nil,
                boolValue: true,
                stringValue: nil,
                hello: nil
            )
        case "snapshot":
            if let raw = core.snapshotJSON() {
                response = DaemonResponse(
                    ok: true,
                    error: nil,
                    intValue: nil,
                    boolValue: nil,
                    stringValue: raw,
                    hello: nil
                )
            } else {
                response = .failure("snapshot unavailable")
            }
        case "events_jsonl":
            let raw = core.eventsJsonl(threadId: req.threadId ?? 0) ?? ""
            response = DaemonResponse(
                ok: true,
                error: nil,
                intValue: nil,
                boolValue: nil,
                stringValue: raw,
                hello: nil
            )
        case "poll_providers":
            let changed = core.pollProviders()
            syncProviderWakeupSourcesOnMain()
            if changed {
                broadcastChangedOnMain()
            }
            response = DaemonResponse(
                ok: true,
                error: nil,
                intValue: nil,
                boolValue: changed,
                stringValue: nil,
                hello: nil
            )
        case "add_project":
            let id = core.addProject(name: req.name ?? "", rootPath: req.rootPath ?? "") ?? 0
            mutated = id > 0
            response = DaemonResponse(
                ok: id > 0,
                error: id > 0 ? nil : "add_project failed",
                intValue: id,
                boolValue: nil,
                stringValue: nil,
                hello: nil
            )
        case "select_project":
            let ok = core.selectProject(req.projectId ?? 0)
            mutated = ok
            response = DaemonResponse(
                ok: ok,
                error: ok ? nil : "select_project failed",
                intValue: nil,
                boolValue: ok,
                stringValue: nil,
                hello: nil
            )
        case "create_thread":
            let id =
                core.createThread(
                    projectId: req.projectId ?? 0,
                    title: req.title ?? "",
                    provider: req.provider ?? "local_echo",
                    model: req.model ?? "",
                    effort: req.effort ?? "medium"
                ) ?? 0
            mutated = id > 0
            response = DaemonResponse(
                ok: id > 0,
                error: id > 0 ? nil : "create_thread failed",
                intValue: id,
                boolValue: nil,
                stringValue: nil,
                hello: nil
            )
        case "select_thread":
            let ok = core.selectThread(req.threadId ?? 0)
            mutated = ok
            response = DaemonResponse(
                ok: ok,
                error: ok ? nil : "select_thread failed",
                intValue: nil,
                boolValue: ok,
                stringValue: nil,
                hello: nil
            )
        case "rename_thread":
            let ok = core.renameThread(req.threadId ?? 0, title: req.title ?? "")
            mutated = ok
            response = DaemonResponse(
                ok: ok,
                error: ok ? nil : "rename_thread failed",
                intValue: nil,
                boolValue: ok,
                stringValue: nil,
                hello: nil
            )
        case "set_thread_provider":
            let ok = core.setThreadProvider(
                req.threadId ?? 0,
                provider: req.provider ?? "local_echo",
                model: req.model ?? "",
                effort: req.effort ?? "medium"
            )
            mutated = ok
            response = DaemonResponse(
                ok: ok,
                error: ok ? nil : "set_thread_provider failed",
                intValue: nil,
                boolValue: ok,
                stringValue: nil,
                hello: nil
            )
        case "send_message":
            let id =
                core.sendMessage(
                    threadId: req.threadId ?? 0,
                    text: req.text ?? "",
                    attachments: req.attachments ?? []
                ) ?? 0
            mutated = id > 0
            response = DaemonResponse(
                ok: id > 0,
                error: id > 0 ? nil : "send_message failed",
                intValue: id,
                boolValue: nil,
                stringValue: nil,
                hello: nil
            )
        case "enqueue_message":
            let id =
                core.enqueueMessage(
                    threadId: req.threadId ?? 0,
                    text: req.text ?? "",
                    attachments: req.attachments ?? []
                ) ?? 0
            mutated = id > 0
            response = DaemonResponse(
                ok: id > 0,
                error: id > 0 ? nil : "enqueue_message failed",
                intValue: id,
                boolValue: nil,
                stringValue: nil,
                hello: nil
            )
        case "process_next_queued":
            let ok = core.processNextQueued(threadId: req.threadId ?? 0)
            mutated = ok
            response = DaemonResponse(
                ok: ok,
                error: ok ? nil : "process_next_queued failed",
                intValue: nil,
                boolValue: ok,
                stringValue: nil,
                hello: nil
            )
        case "cancel_queued_turn":
            let ok = core.cancelQueuedTurn(
                threadId: req.threadId ?? 0,
                turnId: req.turnId ?? 0
            )
            mutated = ok
            response = DaemonResponse(
                ok: ok,
                error: ok ? nil : "cancel_queued_turn failed",
                intValue: nil,
                boolValue: ok,
                stringValue: nil,
                hello: nil
            )
        case "resolve_approval":
            let ok = core.resolveApproval(
                threadId: req.threadId ?? 0,
                approve: req.approve ?? false
            )
            mutated = ok
            response = DaemonResponse(
                ok: ok,
                error: ok ? nil : "resolve_approval failed",
                intValue: nil,
                boolValue: ok,
                stringValue: nil,
                hello: nil
            )
        case "cancel_active_turn":
            let ok = core.cancelActiveTurn(threadId: req.threadId ?? 0)
            mutated = ok
            response = DaemonResponse(
                ok: ok,
                error: ok ? nil : "cancel_active_turn failed",
                intValue: nil,
                boolValue: ok,
                stringValue: nil,
                hello: nil
            )
        case "set_telemetry_suppression":
            let ok = core.setTelemetrySuppression(req.enabled ?? true)
            response = DaemonResponse(
                ok: ok,
                error: ok ? nil : "set_telemetry_suppression failed",
                intValue: nil,
                boolValue: ok,
                stringValue: nil,
                hello: nil
            )
        case "set_auto_approve_tools":
            let ok = core.setAutoApproveTools(req.enabled ?? false)
            mutated = ok
            response = DaemonResponse(
                ok: ok,
                error: ok ? nil : "set_auto_approve_tools failed",
                intValue: nil,
                boolValue: ok,
                stringValue: nil,
                hello: nil
            )
        case "set_orchestrator_enabled":
            let enabled = req.enabled ?? false
            let ctlBin = req.ctlBin ?? CommandLine.arguments[0]
            if enabled {
                if orchestratorServer == nil {
                    let ctlSocket = URL(fileURLWithPath: socketPath)
                        .deletingLastPathComponent()
                        .appendingPathComponent("ctl-\(getpid()).sock")
                        .path
                    let server = LocalOrchestratorServer(socketPath: ctlSocket, core: core) {
                        [weak self] in
                        self?.syncProviderWakeupSourcesOnMain()
                        self?.broadcastChangedOnMain()
                    }
                    if server.start() {
                        orchestratorServer = server
                    }
                }
                if let server = orchestratorServer {
                    _ = core.setOrchestratorBridge(socketPath: server.socketPath, ctlBin: ctlBin)
                }
            } else {
                orchestratorServer?.stop()
                orchestratorServer = nil
                _ = core.setOrchestratorBridge(socketPath: "", ctlBin: "")
            }
            response = DaemonResponse(
                ok: true,
                error: nil,
                intValue: nil,
                boolValue: true,
                stringValue: orchestratorServer?.socketPath ?? "",
                hello: nil
            )
        case "set_orchestrator_bridge":
            let ok = core.setOrchestratorBridge(
                socketPath: req.socketPath ?? "",
                ctlBin: req.ctlBin ?? ""
            )
            response = DaemonResponse(
                ok: ok,
                error: ok ? nil : "set_orchestrator_bridge failed",
                intValue: nil,
                boolValue: ok,
                stringValue: nil,
                hello: nil
            )
        case "set_provider_command_override":
            let ok = core.setProviderCommandOverride(
                provider: req.provider ?? "",
                executable: req.executable ?? "",
                arguments: req.arguments ?? []
            )
            response = DaemonResponse(
                ok: ok,
                error: ok ? nil : "set_provider_command_override failed",
                intValue: nil,
                boolValue: ok,
                stringValue: nil,
                hello: nil
            )
        case "bind_worktree":
            let ok = core.bindWorktree(
                threadId: req.threadId ?? 0,
                branch: req.branch ?? "",
                baseRef: req.baseRef ?? "",
                worktreePath: req.worktreePath ?? ""
            )
            mutated = ok
            response = DaemonResponse(
                ok: ok,
                error: ok ? nil : "bind_worktree failed",
                intValue: nil,
                boolValue: ok,
                stringValue: nil,
                hello: nil
            )
        case "reset_worktree":
            let ok = core.resetWorktree(threadId: req.threadId ?? 0)
            mutated = ok
            response = DaemonResponse(
                ok: ok,
                error: ok ? nil : "reset_worktree failed",
                intValue: nil,
                boolValue: ok,
                stringValue: nil,
                hello: nil
            )
        case "update_diff_stats":
            let threadId = req.threadId ?? 0
            let filesChanged = req.filesChanged ?? 0
            let insertions = req.insertions ?? 0
            let deletions = req.deletions ?? 0
            let previousWorkspace =
                core.snapshot()?.threads.first(where: { $0.id == threadId })?.workspace
            let statsChanged =
                previousWorkspace == nil
                || previousWorkspace?.diffFilesChanged != filesChanged
                || previousWorkspace?.diffInsertions != insertions
                || previousWorkspace?.diffDeletions != deletions
            let ok = core.updateDiffStats(
                threadId: threadId,
                filesChanged: filesChanged,
                insertions: insertions,
                deletions: deletions
            )
            mutated = ok && statsChanged
            response = DaemonResponse(
                ok: ok,
                error: ok ? nil : "update_diff_stats failed",
                intValue: nil,
                boolValue: statsChanged,
                stringValue: nil,
                hello: nil
            )
        default:
            response = .failure("unknown method: \(req.method)")
        }

        if mutated {
            syncProviderWakeupSourcesOnMain()
            broadcastChangedOnMain()
        }
        return response
    }

    static func runCLI(arguments: [String]) -> Int32 {
        var socketPath = KasugaiDaemonPaths.defaultSocketPath()
        var storePath = KasugaiCore.defaultStorePath()
        var projectName = "Kasugai"
        var projectPath = FileManager.default.homeDirectoryForCurrentUser.path
        var buildId = KasugaiDaemonPaths.binaryStamp(atPath: CommandLine.arguments[0])
        var idleTimeoutSeconds: TimeInterval = 60
        var warmIdleTimeoutSeconds: TimeInterval = 600
        var foreground = false

        if let envIdle = ProcessInfo.processInfo.environment["KASUGAI_DAEMON_IDLE_TIMEOUT_SEC"],
            let parsed = Double(envIdle),
            parsed >= 0
        {
            idleTimeoutSeconds = parsed
            warmIdleTimeoutSeconds = max(parsed, 10.0 * parsed)
        }

        var idx = 0
        while idx < arguments.count {
            let arg = arguments[idx]
            switch arg {
            case "--socket" where idx + 1 < arguments.count:
                socketPath = arguments[idx + 1]
                idx += 2
            case "--store" where idx + 1 < arguments.count:
                storePath = arguments[idx + 1]
                idx += 2
            case "--project-name" where idx + 1 < arguments.count:
                projectName = arguments[idx + 1]
                idx += 2
            case "--project-path" where idx + 1 < arguments.count:
                projectPath = arguments[idx + 1]
                idx += 2
            case "--build-id" where idx + 1 < arguments.count:
                buildId = arguments[idx + 1]
                idx += 2
            case "--idle-timeout-sec" where idx + 1 < arguments.count:
                if let parsed = Double(arguments[idx + 1]), parsed >= 0 {
                    idleTimeoutSeconds = parsed
                    warmIdleTimeoutSeconds = max(parsed, parsed * 10.0)
                }
                idx += 2
            case "--foreground":
                foreground = true
                idx += 1
            default:
                idx += 1
            }
        }

        signal(SIGPIPE, SIG_IGN)
        if !foreground {
            _ = setsid()
            signal(SIGHUP, SIG_IGN)
            let devNull = Darwin.open("/dev/null", O_RDWR)
            if devNull >= 0 {
                dup2(devNull, STDIN_FILENO)
                dup2(devNull, STDOUT_FILENO)
                dup2(devNull, STDERR_FILENO)
                if devNull > STDERR_FILENO {
                    close(devNull)
                }
            }
        }

        let lockPath = socketPath + ".lock"
        let lockFD = acquireExclusiveLock(lockPath: lockPath)
        guard lockFD >= 0 else {
            return 0
        }

        guard
            let server = KasugaiDaemonServer(
                socketPath: socketPath,
                lockPath: lockPath,
                lockFD: lockFD,
                storePath: storePath,
                projectName: projectName,
                projectPath: projectPath,
                buildId: buildId,
                idleTimeoutSeconds: idleTimeoutSeconds,
                warmIdleTimeoutSeconds: warmIdleTimeoutSeconds
            ),
            server.start()
        else {
            _ = posixFlock(lockFD, LOCK_UN)
            close(lockFD)
            return 1
        }
        server.installSignalHandlers()
        dispatchMain()
    }
}

struct DaemonLaunchSpec {
    let storePath: String
    let projectName: String
    let projectPath: String
    let daemonExecutable: String
}

final class KasugaiDaemonClient {
    let socketPath: String
    var onChanged: (() -> Void)?
    var onReconnected: (() -> Void)?

    private let launchSpec: DaemonLaunchSpec?
    private let spawnLock = NSLock()
    private let subQueue = DispatchQueue(label: "dev.soyukke.kasugai.daemon.subscribe")
    private var subFD: Int32 = -1
    private var subSource: DispatchSourceRead?
    private var subBuffer = Data()
    private var isStopped = false
    private var hasConnectedOnce = false
    private var notifyInFlight = false
    private var notifyDirty = false

    init(socketPath: String, launchSpec: DaemonLaunchSpec? = nil) {
        self.socketPath = socketPath
        self.launchSpec = launchSpec
    }

    deinit {
        stopSubscription()
    }

    private func callOnce(_ request: DaemonRequest, timeoutSeconds: Int) -> DaemonResponse? {
        let fd = UnixSocketIO.connect(path: socketPath, timeoutSeconds: timeoutSeconds)
        guard fd >= 0 else {
            return nil
        }
        defer { close(fd) }
        guard let encoded = try? JSONEncoder().encode(request) else {
            return nil
        }
        var framed = encoded
        framed.append(0x0A)
        guard UnixSocketIO.writeAll(fd: fd, data: framed),
            let line = UnixSocketIO.readLine(fd: fd)
        else {
            return nil
        }
        return try? JSONDecoder().decode(DaemonResponse.self, from: Data(line.utf8))
    }

    @discardableResult
    private func spawnDaemonAndWait(maxAttempts: Int = 80) -> Bool {
        guard let spec = launchSpec else {
            return false
        }
        spawnLock.lock()
        defer { spawnLock.unlock() }
        if let existing = callOnce(DaemonRequest(method: "hello"), timeoutSeconds: 1),
            existing.ok
        {
            return true
        }
        let expectedBuild = KasugaiDaemonPaths.binaryStamp(atPath: spec.daemonExecutable)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: spec.daemonExecutable)
        proc.arguments = [
            "daemon",
            "--socket", socketPath,
            "--store", spec.storePath,
            "--project-name", spec.projectName,
            "--project-path", spec.projectPath,
            "--build-id", expectedBuild,
        ]
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            return false
        }
        for _ in 0..<maxAttempts {
            if let res = callOnce(DaemonRequest(method: "hello"), timeoutSeconds: 1), res.ok {
                return true
            }
            usleep(30_000)
        }
        return false
    }

    func call(_ request: DaemonRequest, timeoutSeconds: Int = 10) -> DaemonResponse? {
        if let first = callOnce(request, timeoutSeconds: timeoutSeconds) {
            return first
        }
        guard request.method != "hello",
            request.method != "shutdown",
            launchSpec != nil
        else {
            return nil
        }
        guard spawnDaemonAndWait() else {
            return nil
        }
        let reconnectCallback = onReconnected
        DispatchQueue.main.async {
            reconnectCallback?()
        }
        return callOnce(request, timeoutSeconds: timeoutSeconds)
    }

    func hello(timeoutSeconds: Int = 2) -> DaemonHello? {
        let response = callOnce(DaemonRequest(method: "hello"), timeoutSeconds: timeoutSeconds)
        guard let response, response.ok else {
            return nil
        }
        return response.hello
    }

    @discardableResult
    func ensureAlive() -> Bool {
        if hello(timeoutSeconds: 1) != nil {
            return true
        }
        guard spawnDaemonAndWait() else {
            return false
        }
        startSubscription()
        return true
    }

    @discardableResult
    func restartDaemon() -> Bool {
        if let existing = hello(timeoutSeconds: 2), existing.activeTurnCount > 0 {
            return false
        }
        if hello(timeoutSeconds: 1) != nil {
            _ = shutdown()
            for _ in 0..<60 {
                if hello(timeoutSeconds: 1) == nil {
                    break
                }
                usleep(30_000)
            }
        }
        guard spawnDaemonAndWait(maxAttempts: 100) else {
            return false
        }
        startSubscription()
        return true
    }

    @discardableResult
    func shutdown() -> Bool {
        let response = callOnce(DaemonRequest(method: "shutdown"), timeoutSeconds: 2)
        return response?.ok ?? false
    }

    func startSubscription() {
        subQueue.async { [weak self] in
            self?.isStopped = false
            self?.connectSubscriptionLocked()
        }
    }

    func stopSubscription() {
        subQueue.sync {
            isStopped = true
            notifyDirty = false
            disconnectSubscriptionLocked()
        }
    }

    private func disconnectSubscriptionLocked() {
        subSource?.cancel()
        subSource = nil
        if subFD >= 0 {
            close(subFD)
            subFD = -1
        }
        subBuffer.removeAll(keepingCapacity: false)
    }

    private func connectSubscriptionLocked() {
        guard !isStopped, subFD < 0 else {
            return
        }
        var fd = UnixSocketIO.connect(path: socketPath, timeoutSeconds: 2)
        if fd < 0 && launchSpec != nil {
            if spawnDaemonAndWait(maxAttempts: 50) {
                fd = UnixSocketIO.connect(path: socketPath, timeoutSeconds: 2)
            }
        }
        guard fd >= 0 else {
            scheduleReconnectLocked()
            return
        }
        var zeroTimeout = timeval(tv_sec: 0, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &zeroTimeout, socklen_t(MemoryLayout<timeval>.size))
        let subscribeLine = Data("{\"method\":\"subscribe\"}\n".utf8)
        guard UnixSocketIO.writeAll(fd: fd, data: subscribeLine) else {
            close(fd)
            scheduleReconnectLocked()
            return
        }
        let flags = fcntl(fd, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }
        subFD = fd
        subBuffer.removeAll(keepingCapacity: true)

        let wasReconnect = hasConnectedOnce
        hasConnectedOnce = true

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: subQueue)
        source.setEventHandler { [weak self] in
            self?.drainSubscriptionLocked()
        }
        source.resume()
        subSource = source

        if wasReconnect {
            let reconnectCallback = onReconnected
            DispatchQueue.main.async {
                reconnectCallback?()
            }
        }
    }

    private func scheduleReconnectLocked() {
        guard !isStopped else {
            return
        }
        subQueue.asyncAfter(deadline: .now() + .milliseconds(350)) { [weak self] in
            self?.connectSubscriptionLocked()
        }
    }

    private func drainSubscriptionLocked() {
        guard subFD >= 0 else {
            return
        }
        var chunk = [UInt8](repeating: 0, count: 1024)
        var sawChanged = false
        while true {
            let n = Darwin.read(subFD, &chunk, chunk.count)
            if n > 0 {
                subBuffer.append(contentsOf: chunk[0..<n])
                while let nl = subBuffer.firstIndex(of: 0x0A) {
                    let lineData = subBuffer.subdata(in: 0..<nl)
                    subBuffer.removeSubrange(0...nl)
                    if let line = String(data: lineData, encoding: .utf8),
                        line.contains("\"changed\"")
                    {
                        sawChanged = true
                    }
                }
            } else if n == 0 {
                disconnectSubscriptionLocked()
                scheduleReconnectLocked()
                break
            } else {
                if errno == EINTR {
                    continue
                }
                if errno != EAGAIN && errno != EWOULDBLOCK {
                    disconnectSubscriptionLocked()
                    scheduleReconnectLocked()
                }
                break
            }
        }
        if sawChanged {
            if notifyInFlight {
                notifyDirty = true
            } else {
                notifyInFlight = true
                scheduleNotifyLocked(delayMs: 25)
            }
        }
    }

    private func scheduleNotifyLocked(delayMs: Int) {
        subQueue.asyncAfter(deadline: .now() + .milliseconds(delayMs)) { [weak self] in
            guard let self else {
                return
            }
            guard !self.isStopped else {
                self.notifyInFlight = false
                self.notifyDirty = false
                return
            }
            self.notifyDirty = false
            let callback = self.onChanged
            DispatchQueue.main.async { [weak self] in
                callback?()
                self?.subQueue.async { [weak self] in
                    guard let self else {
                        return
                    }
                    if !self.isStopped && self.notifyDirty {
                        self.notifyDirty = false
                        self.scheduleNotifyLocked(delayMs: 80)
                    } else {
                        self.notifyInFlight = false
                    }
                }
            }
        }
    }

    static func ensureRunningAndConnect(
        socketPath: String,
        storePath: String,
        projectName: String,
        projectPath: String,
        daemonExecutable: String = KasugaiDaemonPaths.daemonExecutablePath()
    ) -> KasugaiDaemonClient? {
        let spec = DaemonLaunchSpec(
            storePath: storePath,
            projectName: projectName,
            projectPath: projectPath,
            daemonExecutable: daemonExecutable
        )
        let client = KasugaiDaemonClient(socketPath: socketPath, launchSpec: spec)
        let expectedBuild = KasugaiDaemonPaths.binaryStamp(atPath: daemonExecutable)

        if let existing = client.hello(timeoutSeconds: 1) {
            if existing.buildId == expectedBuild
                || existing.activeTurnCount > 0
                || existing.liveSessionCount > 0
            {
                client.startSubscription()
                return client
            }
            _ = client.shutdown()
            for _ in 0..<50 {
                if client.hello(timeoutSeconds: 1) == nil {
                    break
                }
                usleep(30_000)
            }
        }

        guard client.spawnDaemonAndWait(maxAttempts: 100) else {
            return nil
        }
        client.startSubscription()
        return client
    }

    static func runStatusCLI(arguments: [String]) -> Int32 {
        let socketPath = parseSocketArg(arguments) ?? KasugaiDaemonPaths.defaultSocketPath()
        let client = KasugaiDaemonClient(socketPath: socketPath)
        guard let hello = client.hello(timeoutSeconds: 2) else {
            print("daemon: stopped (\(socketPath))")
            return 1
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(hello), let text = String(data: data, encoding: .utf8) {
            print(text)
        }
        return 0
    }

    static func restartBlockReason(
        env: [String: String],
        targetSocketPath: String,
        activeTurnCount: Int,
        force: Bool
    ) -> String? {
        if let threadId = env["KASUGAI_THREAD_ID"], !threadId.isEmpty {
            let parentSocket =
                env["KASUGAI_DAEMON_SOCKET"]
                ?? KasugaiDaemonPaths.defaultSocketPath(env: env)
            let normalizedTarget = URL(fileURLWithPath: targetSocketPath).standardizedFileURL.path
            let normalizedParent = URL(fileURLWithPath: parentSocket).standardizedFileURL.path
            if normalizedTarget == normalizedParent {
                return
                    "refused: cannot restart parent kasugaid from inside a Kasugai agent turn; ask the user to run `just daemon-restart` after turns finish"
            }
        }
        if activeTurnCount > 0 && !force {
            return
                "daemon has \(activeTurnCount) active turn(s); pass --force to stop anyway"
        }
        return nil
    }

    static func runRestartCLI(arguments: [String]) -> Int32 {
        let env = ProcessInfo.processInfo.environment
        let socketPath =
            parseFlagArg("--socket", in: arguments) ?? KasugaiDaemonPaths.defaultSocketPath()
        let force = arguments.contains("--force")
        let stopOnly = arguments.contains("--stop-only")
        let daemonBin =
            parseFlagArg("--daemon-bin", in: arguments) ?? KasugaiDaemonPaths.daemonExecutablePath()
        let fallbackStore =
            parseFlagArg("--store", in: arguments) ?? KasugaiCore.defaultStorePath()
        let projectPath =
            parseFlagArg("--project-path", in: arguments)
            ?? FileManager.default.homeDirectoryForCurrentUser.path
        let projectName =
            parseFlagArg("--project-name", in: arguments)
            ?? URL(fileURLWithPath: projectPath).lastPathComponent

        if let blocked = restartBlockReason(
            env: env,
            targetSocketPath: socketPath,
            activeTurnCount: 0,
            force: force
        ) {
            fputs("\(blocked)\n", stderr)
            return 2
        }
        let client = KasugaiDaemonClient(socketPath: socketPath)
        var oldPid: Int32?
        var storePath = fallbackStore
        if let hello = client.hello(timeoutSeconds: 2) {
            if let blocked = restartBlockReason(
                env: env,
                targetSocketPath: socketPath,
                activeTurnCount: hello.activeTurnCount,
                force: force
            ) {
                fputs("\(blocked)\n", stderr)
                return 2
            }
            oldPid = hello.pid
            if !hello.storePath.isEmpty {
                storePath = hello.storePath
            }
            guard client.shutdown() else {
                fputs("failed to stop daemon\n", stderr)
                return 1
            }
            for _ in 0..<60 {
                if client.hello(timeoutSeconds: 1) == nil {
                    break
                }
                usleep(30_000)
            }
        }

        if stopOnly {
            if let oldPid {
                print("daemon: stopped (pid=\(oldPid))")
            } else {
                print("daemon: already stopped")
            }
            return 0
        }

        guard
            let restarted = ensureRunningAndConnect(
                socketPath: socketPath,
                storePath: storePath,
                projectName: projectName.isEmpty ? "Kasugai" : projectName,
                projectPath: projectPath,
                daemonExecutable: daemonBin
            ),
            let nextHello = restarted.hello(timeoutSeconds: 2)
        else {
            fputs("failed to start daemon\n", stderr)
            return 1
        }
        restarted.stopSubscription()
        if let oldPid {
            print("daemon: restarted (pid=\(oldPid) -> \(nextHello.pid))")
        } else {
            print("daemon: started (pid=\(nextHello.pid))")
        }
        return 0
    }

    private static func parseSocketArg(_ arguments: [String]) -> String? {
        parseFlagArg("--socket", in: arguments)
    }

    private static func parseFlagArg(_ flag: String, in arguments: [String]) -> String? {
        var idx = 0
        while idx < arguments.count {
            if arguments[idx] == flag, idx + 1 < arguments.count {
                return arguments[idx + 1]
            }
            idx += 1
        }
        return nil
    }

    static func runSelfTests() -> Bool {
        let shortId = String(UUID().uuidString.prefix(8)).lowercased()
        let socketPath = "/tmp/ksg-d-\(shortId).sock"
        let storePath = "/tmp/ksg-d-\(shortId).jsonl"
        let childPidPath = "/tmp/ksg-c-\(shortId).pid"
        let idleSocketPath = "/tmp/ksg-i-\(shortId).sock"
        let idleStorePath = "/tmp/ksg-i-\(shortId).jsonl"
        let fm = FileManager.default
        defer {
            try? fm.removeItem(atPath: socketPath)
            try? fm.removeItem(atPath: socketPath + ".lock")
            try? fm.removeItem(atPath: storePath)
            try? fm.removeItem(atPath: childPidPath)
            try? fm.removeItem(atPath: idleSocketPath)
            try? fm.removeItem(atPath: idleSocketPath + ".lock")
            try? fm.removeItem(atPath: idleStorePath)
        }

        let selfBin = CommandLine.arguments[0]
        guard
            let firstCore = KasugaiCore.connectToDaemon(
                projectName: "DaemonTest",
                projectPath: "/tmp",
                storePath: storePath,
                socketPath: socketPath,
                daemonExecutable: selfBin
            )
        else {
            return false
        }
        guard let hello1 = firstCore.remoteHello(), hello1.pid > 0 else {
            _ = KasugaiDaemonClient(socketPath: socketPath).shutdown()
            return false
        }

        let duplicateProc = Process()
        duplicateProc.executableURL = URL(fileURLWithPath: selfBin)
        duplicateProc.arguments = [
            "daemon",
            "--socket", socketPath,
            "--store", storePath,
            "--project-name", "DaemonTest",
            "--project-path", "/tmp",
            "--foreground",
        ]
        duplicateProc.standardInput = FileHandle.nullDevice
        duplicateProc.standardOutput = FileHandle.nullDevice
        duplicateProc.standardError = FileHandle.nullDevice
        do {
            try duplicateProc.run()
            duplicateProc.waitUntilExit()
        } catch {
            _ = KasugaiDaemonClient(socketPath: socketPath).shutdown()
            return false
        }
        guard duplicateProc.terminationStatus == 0,
            let afterDup = firstCore.remoteHello(),
            afterDup.pid == hello1.pid
        else {
            _ = KasugaiDaemonClient(socketPath: socketPath).shutdown()
            return false
        }

        let mockAcpScript = """
            import json, os, sys
            with open(\(String(reflecting: childPidPath)), "w") as f:
                f.write(str(os.getpid()))
            for raw in sys.stdin:
                msg = json.loads(raw)
                m = msg.get("method")
                if m == "initialize":
                    print(json.dumps({"jsonrpc":"2.0","id":msg["id"],"result":{"protocolVersion":1}}), flush=True)
                elif m == "session/new":
                    print(json.dumps({"jsonrpc":"2.0","id":msg["id"],"result":{"sessionId":"daemon-s1"}}), flush=True)
                elif m == "session/prompt":
                    pid = msg["id"]
                    print(json.dumps({"jsonrpc":"2.0","id":88,"method":"session/request_permission","params":{"toolCall":{"kind":"shell","title":"echo survive"},"options":[{"optionId":"allow","kind":"allow_once"}]}}), flush=True)
                    _ = sys.stdin.readline()
                    print(json.dumps({"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"daemon-s1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Daemon reattach ok"}}}}), flush=True)
                    print(json.dumps({"jsonrpc":"2.0","id":pid,"result":{"stopReason":"end_turn"}}), flush=True)
            """
        guard
            firstCore.setProviderCommandOverride(
                provider: "opencode_acp",
                executable: "/usr/bin/python3",
                arguments: ["-u", "-c", mockAcpScript]
            ),
            let threadId = firstCore.createThread(
                projectId: 1,
                title: "常駐テスト",
                provider: "opencode_acp",
                model: "default",
                effort: "medium"
            ),
            firstCore.sendMessage(threadId: threadId, text: "途中切断テスト") != nil
        else {
            _ = KasugaiDaemonClient(socketPath: socketPath).shutdown()
            return false
        }

        var reachedApproval = false
        for _ in 0..<150 {
            if let snap = firstCore.snapshot(),
                let th = snap.threads.first(where: { $0.id == threadId }),
                th.pendingApproval.active
            {
                reachedApproval = true
                break
            }
            usleep(10_000)
        }
        guard reachedApproval else {
            _ = KasugaiDaemonClient(socketPath: socketPath).shutdown()
            return false
        }

        firstCore.disconnectClient()
        usleep(80_000)

        guard
            let secondCore = KasugaiCore.connectToDaemon(
                projectName: "DaemonTest",
                projectPath: "/tmp",
                storePath: storePath,
                socketPath: socketPath,
                daemonExecutable: selfBin
            ),
            let hello2 = secondCore.remoteHello(),
            hello2.pid == hello1.pid,
            hello2.activeTurnCount == 1
        else {
            _ = KasugaiDaemonClient(socketPath: socketPath).shutdown()
            return false
        }

        var pushCount = 0
        secondCore.onRemoteChanged = {
            pushCount += 1
        }
        guard
            secondCore.updateDiffStats(
                threadId: threadId, filesChanged: 2, insertions: 9, deletions: 3)
        else {
            secondCore.disconnectClient()
            _ = KasugaiDaemonClient(socketPath: socketPath).shutdown()
            return false
        }
        let firstPushDeadline = Date().addingTimeInterval(0.6)
        while pushCount == 0 && Date() < firstPushDeadline {
            CFRunLoopRunInMode(.defaultMode, 0.01, false)
        }
        let gotInitialDiffPush = pushCount > 0
        pushCount = 0
        guard
            secondCore.updateDiffStats(
                threadId: threadId, filesChanged: 2, insertions: 9, deletions: 3)
        else {
            secondCore.disconnectClient()
            _ = KasugaiDaemonClient(socketPath: socketPath).shutdown()
            return false
        }
        let quietDeadline = Date().addingTimeInterval(0.18)
        while Date() < quietDeadline {
            CFRunLoopRunInMode(.defaultMode, 0.01, false)
        }
        let unchangedDiffWasSilent = pushCount == 0

        var sawPush = false
        secondCore.onRemoteChanged = {
            sawPush = true
        }

        guard secondCore.resolveApproval(threadId: threadId, approve: true) else {
            secondCore.disconnectClient()
            _ = KasugaiDaemonClient(socketPath: socketPath).shutdown()
            return false
        }

        var completed = false
        var replyText = ""
        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.02, false)
            if let snap = secondCore.snapshot(),
                let th = snap.threads.first(where: { $0.id == threadId }),
                th.status == "idle",
                let last = th.messages.last,
                last.role == "assistant"
            {
                completed = true
                replyText = last.text
                if sawPush {
                    break
                }
            }
        }

        let childPid =
            (try? String(contentsOfFile: childPidPath, encoding: .utf8))
            .flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0

        let restartExit = runRestartCLI(
            arguments: [
                "--socket", socketPath,
                "--store", storePath,
                "--daemon-bin", selfBin,
            ]
        )
        let restartedHello = secondCore.remoteHello()
        let restartedNewPid =
            restartExit == 0
            && restartedHello != nil
            && restartedHello?.pid != hello1.pid
        var childReaped = childPid <= 0
        if childPid > 0 {
            for _ in 0..<40 {
                if Darwin.kill(childPid, 0) != 0 && errno == ESRCH {
                    childReaped = true
                    break
                }
                usleep(25_000)
            }
        }

        let stopBeforeRespawn = KasugaiDaemonClient(socketPath: socketPath).shutdown()
        for _ in 0..<40 {
            if KasugaiDaemonClient(socketPath: socketPath).hello(timeoutSeconds: 1) == nil {
                break
            }
            usleep(25_000)
        }
        let autoRespawnTurn = secondCore.sendMessage(threadId: 1, text: "自動復帰送信テスト")
        let respawnedHello = secondCore.remoteHello()
        let autoRespawned =
            stopBeforeRespawn
            && autoRespawnTurn != nil
            && respawnedHello != nil
            && respawnedHello?.pid != restartedHello?.pid

        secondCore.disconnectClient()
        let stopped = KasugaiDaemonClient(socketPath: socketPath).shutdown()
        for _ in 0..<40 {
            if KasugaiDaemonClient(socketPath: socketPath).hello(timeoutSeconds: 1) == nil {
                break
            }
            usleep(25_000)
        }

        let idleProc = Process()
        idleProc.executableURL = URL(fileURLWithPath: selfBin)
        idleProc.arguments = [
            "daemon",
            "--socket", idleSocketPath,
            "--store", idleStorePath,
            "--project-name", "IdleTest",
            "--project-path", "/tmp",
            "--idle-timeout-sec", "0.25",
            "--foreground",
        ]
        idleProc.standardInput = FileHandle.nullDevice
        idleProc.standardOutput = FileHandle.nullDevice
        idleProc.standardError = FileHandle.nullDevice
        var idleExited = false
        do {
            try idleProc.run()
            let idleClient = KasugaiDaemonClient(socketPath: idleSocketPath)
            var idleUp = false
            for _ in 0..<60 {
                if idleClient.hello(timeoutSeconds: 1) != nil {
                    idleUp = true
                    break
                }
                usleep(20_000)
            }
            if idleUp {
                for _ in 0..<80 {
                    if !idleProc.isRunning {
                        idleExited = idleProc.terminationStatus == 0
                        break
                    }
                    usleep(25_000)
                }
            }
            if idleProc.isRunning {
                idleProc.terminate()
            }
        } catch {
            idleExited = false
        }

        let selfBlockReason = restartBlockReason(
            env: [
                "KASUGAI_THREAD_ID": "7",
                "KASUGAI_DAEMON_SOCKET": socketPath,
            ],
            targetSocketPath: socketPath,
            activeTurnCount: 1,
            force: true
        )
        let devRestartAllowed =
            restartBlockReason(
                env: [
                    "KASUGAI_THREAD_ID": "7",
                    "KASUGAI_DAEMON_SOCKET": socketPath,
                ],
                targetSocketPath: idleSocketPath,
                activeTurnCount: 0,
                force: false
            ) == nil
        let activeTurnBlocked =
            restartBlockReason(
                env: [:],
                targetSocketPath: socketPath,
                activeTurnCount: 1,
                force: false
            ) != nil

        return completed
            && replyText.contains("Daemon reattach ok")
            && gotInitialDiffPush
            && unchangedDiffWasSilent
            && sawPush
            && restartedNewPid
            && autoRespawned
            && stopped
            && childReaped
            && idleExited
            && selfBlockReason != nil
            && devRestartAllowed
            && activeTurnBlocked
    }
}
