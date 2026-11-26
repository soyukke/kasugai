import CryptoKit
import Darwin
import Foundation
import Security

private struct StoredPairedMobileDevice: Codable, Equatable {
    let id: String
    let name: String
    let tokenHash: String
    let createdAtMs: Int64
    var lastSeenAtMs: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case tokenHash = "token_hash"
        case createdAtMs = "created_at_ms"
        case lastSeenAtMs = "last_seen_at_ms"
    }

    var publicInfo: PairedMobileDeviceInfo {
        PairedMobileDeviceInfo(
            id: id,
            name: name,
            createdAtMs: createdAtMs,
            lastSeenAtMs: lastSeenAtMs
        )
    }
}

private struct StoredMobileBridgeAuth: Codable {
    var devices: [StoredPairedMobileDevice]

    static let empty = StoredMobileBridgeAuth(devices: [])
}

enum MobileBridgeDefaults {
    static var defaultLocalPort: UInt16 {
        KasugaiRuntimePaths.isDevBundle ? 17922 : 17921
    }

    static var defaultTailscaleHttpsPort: UInt16 {
        KasugaiRuntimePaths.isDevBundle ? 9444 : 9443
    }

    static func defaultAuthStorePath(
        env: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        if let override = env["KASUGAI_MOBILE_AUTH_PATH"], !override.isEmpty {
            return override
        }
        if env["KASUGAI_SELF_TEST"] == "1" {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("kasugai-self-test-mobile-auth.json")
                .path
        }
        return KasugaiRuntimePaths.dataDirectory(env: env)
            .appendingPathComponent("mobile-bridge.json")
            .path
    }
}

struct TailscaleBridgeInfo: Equatable {
    let available: Bool
    let running: Bool
    let serveActive: Bool
    let dnsName: String
    let hostName: String
    let lastError: String

    static let unavailable = TailscaleBridgeInfo(
        available: false,
        running: false,
        serveActive: false,
        dnsName: "",
        hostName: "",
        lastError: ""
    )
}

enum TailscaleServeBridge {
    private struct CommandResult {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    static func findExecutable() -> String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        var candidates: [String] = []
        for dir in envPath.split(separator: ":") where !dir.isEmpty {
            candidates.append("\(dir)/tailscale")
        }
        candidates.append(contentsOf: [
            "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
            "\(home)/.nix-profile/bin/tailscale",
            "/opt/homebrew/bin/tailscale",
            "/usr/local/bin/tailscale",
            "/usr/bin/tailscale",
        ])
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    static func probeStatus(localPort: UInt16, httpsPort: UInt16) -> TailscaleBridgeInfo {
        guard let bin = findExecutable() else {
            return .unavailable
        }
        guard let statusOut = run(bin, arguments: ["status", "--json"]),
            statusOut.status == 0,
            let data = statusOut.stdout.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return TailscaleBridgeInfo(
                available: true,
                running: false,
                serveActive: false,
                dnsName: "",
                hostName: "",
                lastError: "Tailscale の状態を取得できませんでした"
            )
        }
        let backendState = obj["BackendState"] as? String ?? ""
        let isRunning = backendState == "Running"
        let selfNode = obj["Self"] as? [String: Any] ?? [:]
        var dnsName = (selfNode["DNSName"] as? String ?? "").trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        while dnsName.hasSuffix(".") {
            dnsName.removeLast()
        }
        let hostName = (selfNode["HostName"] as? String ?? "").trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        var serveActive = false
        if isRunning, !dnsName.isEmpty,
            let serveOut = run(bin, arguments: ["serve", "status", "--json"]),
            serveOut.status == 0,
            let serveData = serveOut.stdout.data(using: .utf8),
            let serveObj = try? JSONSerialization.jsonObject(with: serveData) as? [String: Any],
            let web = serveObj["Web"] as? [String: Any]
        {
            let targetKey = "\(dnsName):\(httpsPort)"
            if let entry = web[targetKey] as? [String: Any],
                let handlers = entry["Handlers"] as? [String: Any],
                let rootHandler = handlers["/"] as? [String: Any],
                let proxy = rootHandler["Proxy"] as? String
            {
                serveActive = proxy.contains("127.0.0.1:\(localPort)")
            }
        }

        return TailscaleBridgeInfo(
            available: true,
            running: isRunning,
            serveActive: serveActive,
            dnsName: dnsName,
            hostName: hostName,
            lastError: ""
        )
    }

    @discardableResult
    static func enableServe(localPort: UInt16, httpsPort: UInt16) -> (ok: Bool, error: String) {
        guard let bin = findExecutable() else {
            return (false, "tailscale コマンドが見つかりません")
        }
        guard
            let result = run(
                bin,
                arguments: [
                    "serve",
                    "--bg",
                    "--https=\(httpsPort)",
                    "http://127.0.0.1:\(localPort)",
                ]
            )
        else {
            return (false, "tailscale serve を起動できませんでした")
        }
        if result.status == 0 {
            return (true, "")
        }
        let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return (false, detail.isEmpty ? "tailscale serve の設定に失敗しました" : detail)
    }

    @discardableResult
    static func disableServe(httpsPort: UInt16) -> (ok: Bool, error: String) {
        guard let bin = findExecutable() else {
            return (true, "")
        }
        guard
            let result = run(
                bin,
                arguments: ["serve", "--https=\(httpsPort)", "off"]
            )
        else {
            return (false, "tailscale serve の停止に失敗しました")
        }
        if result.status == 0 {
            return (true, "")
        }
        let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return (false, detail.isEmpty ? "tailscale serve の停止に失敗しました" : detail)
    }

    static func publicURL(dnsName: String, httpsPort: UInt16) -> String {
        guard !dnsName.isEmpty else {
            return ""
        }
        if httpsPort == 443 {
            return "https://\(dnsName)"
        }
        return "https://\(dnsName):\(httpsPort)"
    }

    private static func run(_ executable: String, arguments: [String]) -> CommandResult? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = arguments
        proc.standardInput = FileHandle.nullDevice
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        do {
            try proc.run()
        } catch {
            return nil
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return CommandResult(
            status: proc.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }
}

private final class MobileTerminalSessionPool {
    private struct Entry {
        let cwd: String
        let terminal: KasugaiTerminal
        var lastAccess: Date
    }

    private let queue = DispatchQueue(label: "dev.soyukke.kasugai.mobile.terminals")
    private var sessions: [Int64: Entry] = [:]

    func open(threadId: Int64, cwd: String, cols: UInt16, rows: UInt16) -> KasugaiTerminalSnapshot?
    {
        queue.sync {
            let clampedCols = max(24, min(240, cols))
            let clampedRows = max(8, min(100, rows))
            if var existing = sessions[threadId],
                !existing.terminal.exited,
                existing.cwd == cwd
            {
                existing.lastAccess = Date()
                _ = existing.terminal.resize(cols: clampedCols, rows: clampedRows)
                _ = existing.terminal.drain()
                sessions[threadId] = existing
                return existing.terminal.snapshot()
            }
            sessions.removeValue(forKey: threadId)
            let effectiveDir =
                FileManager.default.fileExists(atPath: cwd)
                ? cwd : FileManager.default.homeDirectoryForCurrentUser.path
            guard
                let term = KasugaiTerminal(
                    cwd: effectiveDir,
                    cols: clampedCols,
                    rows: clampedRows
                )
            else {
                return nil
            }
            usleep(30_000)
            _ = term.drain()
            sessions[threadId] = Entry(cwd: cwd, terminal: term, lastAccess: Date())
            return term.snapshot()
        }
    }

    func snapshot(threadId: Int64) -> KasugaiTerminalSnapshot? {
        queue.sync {
            guard var entry = sessions[threadId] else {
                return nil
            }
            entry.lastAccess = Date()
            _ = entry.terminal.drain()
            sessions[threadId] = entry
            return entry.terminal.snapshot()
        }
    }

    func write(threadId: Int64, text: String) -> KasugaiTerminalSnapshot? {
        queue.sync {
            guard var entry = sessions[threadId] else {
                return nil
            }
            entry.lastAccess = Date()
            _ = entry.terminal.write(text)
            usleep(25_000)
            _ = entry.terminal.drain()
            sessions[threadId] = entry
            return entry.terminal.snapshot()
        }
    }

    func resize(threadId: Int64, cols: UInt16, rows: UInt16) -> KasugaiTerminalSnapshot? {
        queue.sync {
            guard var entry = sessions[threadId] else {
                return nil
            }
            entry.lastAccess = Date()
            let clampedCols = max(24, min(240, cols))
            let clampedRows = max(8, min(100, rows))
            _ = entry.terminal.resize(cols: clampedCols, rows: clampedRows)
            _ = entry.terminal.drain()
            sessions[threadId] = entry
            return entry.terminal.snapshot()
        }
    }

    func close(threadId: Int64) {
        queue.sync {
            _ = sessions.removeValue(forKey: threadId)
        }
    }

    func closeAll() {
        queue.sync {
            sessions.removeAll()
        }
    }
}

private struct ParsedHTTPRequest {
    let method: String
    let path: String
    let queryItems: [String: String]
    let headers: [String: String]
    let body: Data
}

final class MobileBridgeServer {
    private struct ActivePairing {
        let code: String
        let expiresAtMs: Int64
        var failedAttempts: Int
    }

    private struct StreamClient {
        let fd: Int32
        let deviceId: String
        let source: DispatchSourceRead
    }

    private let authStorePath: String
    private let executeActionOnMain: (DaemonRequest) -> DaemonResponse
    private let fetchSnapshotJSONOnMain: () -> String?
    private let fetchThreadWorkspaceOnMain: (Int64) -> KasugaiThread?

    private let stateLock = NSLock()
    private let acceptQueue = DispatchQueue(label: "dev.soyukke.kasugai.mobile.accept")
    private let streamQueue = DispatchQueue(label: "dev.soyukke.kasugai.mobile.streams")
    private let terminalPool = MobileTerminalSessionPool()

    private var authData: StoredMobileBridgeAuth
    private var activePairing: ActivePairing?
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var heartbeatTimer: DispatchSourceTimer?
    private var streamClients: [Int32: StreamClient] = [:]

    private var isEnabledFlag: Bool = false
    private var boundPort: UInt16 = MobileBridgeDefaults.defaultLocalPort
    private var configuredHttpsPort: UInt16 = MobileBridgeDefaults.defaultTailscaleHttpsPort
    private var lastBridgeError: String = ""
    private var cachedTailscale: TailscaleBridgeInfo = .unavailable
    private var managedTailscaleServe: Bool = false

    init(
        authStorePath: String = MobileBridgeDefaults.defaultAuthStorePath(),
        fetchSnapshotJSONOnMain: @escaping () -> String?,
        fetchThreadWorkspaceOnMain: @escaping (Int64) -> KasugaiThread?,
        executeActionOnMain: @escaping (DaemonRequest) -> DaemonResponse
    ) {
        self.authStorePath = authStorePath
        self.fetchSnapshotJSONOnMain = fetchSnapshotJSONOnMain
        self.fetchThreadWorkspaceOnMain = fetchThreadWorkspaceOnMain
        self.executeActionOnMain = executeActionOnMain
        self.authData = Self.loadAuth(from: authStorePath)
    }

    deinit {
        stop(disableTailscaleServe: false)
    }

    var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return listenFD >= 0
    }

    var listeningPort: UInt16 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return boundPort
    }

    var connectedStreamCount: Int {
        streamQueue.sync {
            streamClients.count
        }
    }

    @discardableResult
    func configure(
        enabled: Bool,
        localPort: UInt16,
        httpsPort: UInt16,
        manageTailscaleServe: Bool
    ) -> MobileBridgeStatusSnapshot {
        let targetLocalPort = localPort == 0 ? 0 : localPort
        let targetHttpsPort =
            httpsPort == 0 ? MobileBridgeDefaults.defaultTailscaleHttpsPort : httpsPort

        stateLock.lock()
        let wasRunning = listenFD >= 0
        let samePorts = boundPort == targetLocalPort && configuredHttpsPort == targetHttpsPort
        configuredHttpsPort = targetHttpsPort
        isEnabledFlag = enabled
        lastBridgeError = ""
        stateLock.unlock()

        if !enabled {
            stop(disableTailscaleServe: manageTailscaleServe)
            return statusSnapshot(refreshTailscale: false)
        }

        if !wasRunning || !samePorts {
            stopTransportOnly()
            if !startLoopbackListener(port: targetLocalPort) {
                stateLock.lock()
                lastBridgeError = "ローカルポート \(targetLocalPort) の待ち受けに失敗しました"
                stateLock.unlock()
                return statusSnapshot(refreshTailscale: false)
            }
        }

        if manageTailscaleServe {
            let activeLocal = listeningPort
            let res = TailscaleServeBridge.enableServe(
                localPort: activeLocal,
                httpsPort: targetHttpsPort
            )
            stateLock.lock()
            managedTailscaleServe = res.ok
            if !res.ok {
                lastBridgeError = res.error
            }
            stateLock.unlock()
        }

        return statusSnapshot(refreshTailscale: manageTailscaleServe)
    }

    func generatePairingCode(ttlSeconds: Int64 = 300) -> MobileBridgeStatusSnapshot {
        let code = Self.randomPairingCode()
        let nowMs = Self.nowMillis()
        stateLock.lock()
        activePairing = ActivePairing(
            code: code,
            expiresAtMs: nowMs + ttlSeconds * 1000,
            failedAttempts: 0
        )
        stateLock.unlock()
        return statusSnapshot(refreshTailscale: false)
    }

    func revokeDevice(id: String) -> MobileBridgeStatusSnapshot {
        stateLock.lock()
        authData.devices.removeAll { $0.id == id }
        let snapshotToSave = authData
        stateLock.unlock()
        Self.saveAuth(snapshotToSave, to: authStorePath)
        closeStreams(forDeviceId: id)
        return statusSnapshot(refreshTailscale: false)
    }

    func revokeAllDevices() -> MobileBridgeStatusSnapshot {
        stateLock.lock()
        authData.devices.removeAll()
        activePairing = nil
        let snapshotToSave = authData
        stateLock.unlock()
        Self.saveAuth(snapshotToSave, to: authStorePath)
        closeAllStreams()
        return statusSnapshot(refreshTailscale: false)
    }

    func statusSnapshot(refreshTailscale: Bool = true) -> MobileBridgeStatusSnapshot {
        stateLock.lock()
        let enabled = isEnabledFlag
        let running = listenFD >= 0
        let localPort = boundPort
        let httpsPort = configuredHttpsPort
        let err = lastBridgeError
        let nowMs = Self.nowMillis()
        if let pairing = activePairing, pairing.expiresAtMs <= nowMs {
            activePairing = nil
        }
        let code = activePairing?.code ?? ""
        let expiresAt = activePairing?.expiresAtMs ?? 0
        let devices = authData.devices.map(\.publicInfo)
        stateLock.unlock()

        if refreshTailscale && enabled {
            let probed = TailscaleServeBridge.probeStatus(
                localPort: localPort,
                httpsPort: httpsPort
            )
            stateLock.lock()
            cachedTailscale = probed
            stateLock.unlock()
        }

        stateLock.lock()
        let ts = cachedTailscale
        stateLock.unlock()

        let publicURL =
            !ts.dnsName.isEmpty
            ? TailscaleServeBridge.publicURL(dnsName: ts.dnsName, httpsPort: httpsPort)
            : (running ? "http://127.0.0.1:\(localPort)" : "")
        let serverName =
            !ts.hostName.isEmpty
            ? ts.hostName
            : (Host.current().localizedName ?? ProcessInfo.processInfo.hostName)
        let combinedError = !err.isEmpty ? err : ts.lastError

        return MobileBridgeStatusSnapshot(
            enabled: enabled,
            running: running,
            bindHost: "127.0.0.1",
            localPort: localPort,
            tailscaleAvailable: ts.available,
            tailscaleRunning: ts.running,
            tailscaleServeActive: ts.serveActive,
            tailscaleDnsName: ts.dnsName,
            tailscaleHttpsPort: httpsPort,
            publicBaseURL: publicURL,
            serverName: serverName,
            activePairingCode: code,
            pairingExpiresAtMs: expiresAt,
            pairedDevices: devices,
            connectedStreamCount: connectedStreamCount,
            lastError: combinedError
        )
    }

    func notifyChanged() {
        let payload = Data("event: changed\ndata: {}\n\n".utf8)
        streamQueue.async { [weak self] in
            self?.broadcastStreamPayloadLocked(payload)
        }
    }

    func stop(disableTailscaleServe: Bool = false) {
        stateLock.lock()
        let httpsPort = configuredHttpsPort
        let shouldDisableServe = disableTailscaleServe && managedTailscaleServe
        managedTailscaleServe = false
        isEnabledFlag = false
        stateLock.unlock()

        stopTransportOnly()
        terminalPool.closeAll()

        if shouldDisableServe {
            _ = TailscaleServeBridge.disableServe(httpsPort: httpsPort)
        }
    }

    private func stopTransportOnly() {
        stateLock.lock()
        let fdToClose = listenFD
        listenFD = -1
        let sourceToCancel = acceptSource
        acceptSource = nil
        stateLock.unlock()

        sourceToCancel?.cancel()
        if fdToClose >= 0 {
            Darwin.close(fdToClose)
        }
        closeAllStreams()
    }

    private func startLoopbackListener(port: UInt16) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            return false
        }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)

        let bound = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            Darwin.close(fd)
            return false
        }

        var actualAddr = sockaddr_in()
        var actualLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let actualPort: UInt16
        if withUnsafeMutablePointer(
            to: &actualAddr,
            { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    getsockname(fd, sockPtr, &actualLen) == 0
                }
            })
        {
            actualPort = UInt16(bigEndian: actualAddr.sin_port)
        } else {
            actualPort = port
        }

        guard listen(fd, 64) == 0 else {
            Darwin.close(fd)
            return false
        }
        let flags = fcntl(fd, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: acceptQueue)
        source.setEventHandler { [weak self] in
            self?.acceptPendingConnections()
        }
        source.resume()

        stateLock.lock()
        listenFD = fd
        boundPort = actualPort
        acceptSource = source
        stateLock.unlock()

        startHeartbeatTimer()
        return true
    }

    private func startHeartbeatTimer() {
        streamQueue.async { [weak self] in
            guard let self else {
                return
            }
            self.heartbeatTimer?.cancel()
            let timer = DispatchSource.makeTimerSource(queue: self.streamQueue)
            timer.schedule(deadline: .now() + 20, repeating: 20)
            timer.setEventHandler { [weak self] in
                self?.broadcastStreamPayloadLocked(Data(": ping\n\n".utf8))
            }
            timer.resume()
            self.heartbeatTimer = timer
        }
    }

    private func acceptPendingConnections() {
        while true {
            stateLock.lock()
            let currentListenFD = listenFD
            stateLock.unlock()
            guard currentListenFD >= 0 else {
                break
            }
            let clientFD = accept(currentListenFD, nil, nil)
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
            var timeout = timeval(tv_sec: 15, tv_usec: 0)
            setsockopt(
                clientFD,
                SOL_SOCKET,
                SO_RCVTIMEO,
                &timeout,
                socklen_t(MemoryLayout<timeval>.size)
            )
            setsockopt(
                clientFD,
                SOL_SOCKET,
                SO_SNDTIMEO,
                &timeout,
                socklen_t(MemoryLayout<timeval>.size)
            )
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.handleConnection(fd: clientFD)
            }
        }
    }

    private func handleConnection(fd: Int32) {
        guard let req = Self.readHTTPRequest(fd: fd) else {
            Darwin.close(fd)
            return
        }

        if req.method == "GET" && req.path == "/api/v1/health" {
            stateLock.lock()
            let count = authData.devices.count
            let tsHost = cachedTailscale.hostName
            stateLock.unlock()
            let serverName =
                !tsHost.isEmpty
                ? tsHost : (Host.current().localizedName ?? ProcessInfo.processInfo.hostName)
            let payload = MobileBridgeHealthResponse(
                ok: true,
                protocol: 1,
                serverName: serverName,
                pairedDevices: count
            )
            Self.sendJSON(fd: fd, status: 200, reason: "OK", payload: payload)
            Darwin.close(fd)
            return
        }

        if req.method == "POST" && req.path == "/api/v1/pair" {
            handlePairRequest(fd: fd, body: req.body)
            Darwin.close(fd)
            return
        }

        guard let deviceId = authenticateBearer(headers: req.headers) else {
            Self.sendJSON(
                fd: fd,
                status: 401,
                reason: "Unauthorized",
                payload: MobileErrorResponse(ok: false, error: "認証トークンが無効または失効しています")
            )
            Darwin.close(fd)
            return
        }

        if req.method == "GET" && req.path == "/api/v1/events" {
            upgradeToSSE(fd: fd, deviceId: deviceId)
            return
        }

        defer { Darwin.close(fd) }

        if req.method == "POST" && req.path == "/api/v1/unpair" {
            _ = revokeDevice(id: deviceId)
            Self.sendJSON(
                fd: fd,
                status: 200,
                reason: "OK",
                payload: MobileActionResponse(
                    ok: true,
                    error: nil,
                    intValue: nil,
                    boolValue: true,
                    stringValue: nil
                )
            )
            return
        }

        if req.method == "GET" && req.path == "/api/v1/snapshot" {
            let rawJSON: String? = DispatchQueue.main.sync {
                fetchSnapshotJSONOnMain()
            }
            guard let rawJSON else {
                Self.sendJSON(
                    fd: fd,
                    status: 503,
                    reason: "Service Unavailable",
                    payload: MobileErrorResponse(ok: false, error: "スナップショットを取得できませんでした")
                )
                return
            }
            Self.sendRawResponse(
                fd: fd,
                status: 200,
                reason: "OK",
                contentType: "application/json; charset=utf-8",
                body: Data(rawJSON.utf8)
            )
            return
        }

        if req.method == "POST" && req.path == "/api/v1/action" {
            handleActionRequest(fd: fd, body: req.body)
            return
        }

        if req.method == "POST" && req.path == "/api/v1/attachments" {
            handleAttachmentUpload(fd: fd, body: req.body)
            return
        }

        if let threadRoute = parseThreadRoute(path: req.path) {
            handleThreadRoute(
                fd: fd,
                method: req.method,
                threadId: threadRoute.threadId,
                subpath: threadRoute.subpath,
                query: req.queryItems,
                body: req.body
            )
            return
        }

        Self.sendJSON(
            fd: fd,
            status: 404,
            reason: "Not Found",
            payload: MobileErrorResponse(ok: false, error: "エンドポイントが見つかりません")
        )
    }

    private func handlePairRequest(fd: Int32, body: Data) {
        guard let pairReq = try? JSONDecoder().decode(MobilePairRequest.self, from: body) else {
            Self.sendJSON(
                fd: fd,
                status: 400,
                reason: "Bad Request",
                payload: MobileErrorResponse(ok: false, error: "ペアリングリクエストの形式が不正です")
            )
            return
        }

        let candidateCode = MobilePairingPayload.normalizePairingCode(pairReq.code)
        let nowMs = Self.nowMillis()

        stateLock.lock()
        guard var pairing = activePairing else {
            stateLock.unlock()
            Self.sendJSON(
                fd: fd,
                status: 401,
                reason: "Unauthorized",
                payload: MobileErrorResponse(ok: false, error: "有効なペアリングコードがありません")
            )
            return
        }
        if pairing.expiresAtMs <= nowMs {
            activePairing = nil
            stateLock.unlock()
            Self.sendJSON(
                fd: fd,
                status: 401,
                reason: "Unauthorized",
                payload: MobileErrorResponse(ok: false, error: "ペアリングコードの有効期限が切れました")
            )
            return
        }
        guard Self.constantTimeEquals(candidateCode, pairing.code) else {
            pairing.failedAttempts += 1
            if pairing.failedAttempts >= 8 {
                activePairing = nil
            } else {
                activePairing = pairing
            }
            stateLock.unlock()
            Self.sendJSON(
                fd: fd,
                status: 401,
                reason: "Unauthorized",
                payload: MobileErrorResponse(ok: false, error: "ペアリングコードが一致しません")
            )
            return
        }

        activePairing = nil
        let rawToken = Self.randomToken()
        let tokenHash = Self.sha256Hex(rawToken)
        let deviceId = UUID().uuidString.lowercased()
        let trimmedName = pairReq.deviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let deviceName = trimmedName.isEmpty ? "iPhone" : String(trimmedName.prefix(48))
        let device = StoredPairedMobileDevice(
            id: deviceId,
            name: deviceName,
            tokenHash: tokenHash,
            createdAtMs: nowMs,
            lastSeenAtMs: nowMs
        )
        authData.devices.append(device)
        let snapshotToSave = authData
        let tsHost = cachedTailscale.hostName
        stateLock.unlock()

        Self.saveAuth(snapshotToSave, to: authStorePath)
        let serverName =
            !tsHost.isEmpty
            ? tsHost : (Host.current().localizedName ?? ProcessInfo.processInfo.hostName)
        Self.sendJSON(
            fd: fd,
            status: 200,
            reason: "OK",
            payload: MobilePairResponse(
                ok: true,
                deviceId: deviceId,
                token: rawToken,
                serverName: serverName
            )
        )
    }

    private func authenticateBearer(headers: [String: String]) -> String? {
        guard let authHeader = headers["authorization"] else {
            return nil
        }
        let prefix = "bearer "
        guard authHeader.lowercased().hasPrefix(prefix) else {
            return nil
        }
        let token = String(authHeader.dropFirst(prefix.count)).trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard token.count >= 24 else {
            return nil
        }
        let hash = Self.sha256Hex(token)
        let nowMs = Self.nowMillis()

        stateLock.lock()
        var matchedId: String?
        var shouldSave = false
        for idx in authData.devices.indices {
            if Self.constantTimeEquals(authData.devices[idx].tokenHash, hash) {
                matchedId = authData.devices[idx].id
                if nowMs - authData.devices[idx].lastSeenAtMs > 60_000 {
                    authData.devices[idx].lastSeenAtMs = nowMs
                    shouldSave = true
                }
                break
            }
        }
        let snapshotToSave = shouldSave ? authData : nil
        stateLock.unlock()

        if let snapshotToSave {
            Self.saveAuth(snapshotToSave, to: authStorePath)
        }
        return matchedId
    }

    private func upgradeToSSE(fd: Int32, deviceId: String) {
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
        let header =
            "HTTP/1.1 200 OK\r\n"
            + "Content-Type: text/event-stream; charset=utf-8\r\n"
            + "Cache-Control: no-cache, no-store\r\n"
            + "Connection: keep-alive\r\n"
            + "X-Accel-Buffering: no\r\n\r\n"
            + ": ready\n\n"
        guard Self.writeAll(fd: fd, data: Data(header.utf8)) else {
            Darwin.close(fd)
            return
        }
        streamQueue.async { [weak self] in
            guard let self else {
                Darwin.close(fd)
                return
            }
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: self.streamQueue)
            source.setEventHandler { [weak self] in
                var buf = [UInt8](repeating: 0, count: 64)
                let n = Darwin.read(fd, &buf, buf.count)
                if n <= 0 && errno != EAGAIN && errno != EWOULDBLOCK {
                    self?.removeStreamClientLocked(fd: fd)
                }
            }
            source.resume()
            self.streamClients[fd] = StreamClient(fd: fd, deviceId: deviceId, source: source)
        }
    }

    private func broadcastStreamPayloadLocked(_ data: Data) {
        var dead: [Int32] = []
        for fd in streamClients.keys {
            if !Self.writeAll(fd: fd, data: data) {
                dead.append(fd)
            }
        }
        for fd in dead {
            removeStreamClientLocked(fd: fd)
        }
    }

    private func removeStreamClientLocked(fd: Int32) {
        if let entry = streamClients.removeValue(forKey: fd) {
            entry.source.cancel()
        }
        Darwin.close(fd)
    }

    private func closeStreams(forDeviceId deviceId: String) {
        streamQueue.sync {
            let matching = streamClients.values.filter { $0.deviceId == deviceId }.map(\.fd)
            for fd in matching {
                removeStreamClientLocked(fd: fd)
            }
        }
    }

    private func closeAllStreams() {
        streamQueue.sync {
            heartbeatTimer?.cancel()
            heartbeatTimer = nil
            let allFDs = Array(streamClients.keys)
            for fd in allFDs {
                removeStreamClientLocked(fd: fd)
            }
        }
    }

    private func handleActionRequest(fd: Int32, body: Data) {
        guard let action = try? JSONDecoder().decode(MobileActionRequest.self, from: body) else {
            Self.sendJSON(
                fd: fd,
                status: 400,
                reason: "Bad Request",
                payload: MobileErrorResponse(ok: false, error: "アクションの JSON 形式が不正です")
            )
            return
        }
        let allowedMethods: Set<String> = [
            "select_project",
            "select_thread",
            "create_thread",
            "rename_thread",
            "set_thread_provider",
            "send_message",
            "enqueue_message",
            "process_next_queued",
            "cancel_queued_turn",
            "cancel_active_turn",
            "resolve_approval",
            "set_auto_approve_tools",
            "reset_worktree",
        ]
        guard allowedMethods.contains(action.method) else {
            Self.sendJSON(
                fd: fd,
                status: 403,
                reason: "Forbidden",
                payload: MobileErrorResponse(ok: false, error: "許可されていない操作です")
            )
            return
        }

        var daemonReq = DaemonRequest(method: action.method)
        daemonReq.projectId = action.projectId
        daemonReq.threadId = action.threadId
        daemonReq.turnId = action.turnId
        daemonReq.title = action.title
        daemonReq.provider = action.provider
        daemonReq.model = action.model
        daemonReq.effort = action.effort
        daemonReq.text = action.text
        daemonReq.attachments = action.attachments
        daemonReq.approve = action.approve
        daemonReq.enabled = action.enabled

        let daemonResp: DaemonResponse = DispatchQueue.main.sync {
            executeActionOnMain(daemonReq)
        }
        Self.sendJSON(
            fd: fd,
            status: daemonResp.ok ? 200 : 400,
            reason: daemonResp.ok ? "OK" : "Bad Request",
            payload: MobileActionResponse(
                ok: daemonResp.ok,
                error: daemonResp.error,
                intValue: daemonResp.intValue,
                boolValue: daemonResp.boolValue,
                stringValue: daemonResp.stringValue
            )
        )
    }

    private func handleAttachmentUpload(fd: Int32, body: Data) {
        guard let req = try? JSONDecoder().decode(MobileAttachmentUploadRequest.self, from: body),
            let decoded = Data(base64Encoded: req.dataBase64),
            !decoded.isEmpty,
            decoded.count <= 10 * 1024 * 1024
        else {
            Self.sendJSON(
                fd: fd,
                status: 400,
                reason: "Bad Request",
                payload: MobileErrorResponse(ok: false, error: "添付データの形式またはサイズが不正です")
            )
            return
        }
        let rawExt = URL(fileURLWithPath: req.filename).pathExtension.lowercased()
        let allowedExts: Set<String> = [
            "png", "jpg", "jpeg", "webp", "gif", "heic", "txt", "md", "pdf",
        ]
        let ext = allowedExts.contains(rawExt) ? rawExt : "png"
        let dir = KasugaiRuntimePaths.dataDirectory()
            .appendingPathComponent("attachments", isDirectory: true)
        let fm = FileManager.default
        let shortId = String(UUID().uuidString.prefix(8)).lowercased()
        let fileName = "mobile-\(shortId).\(ext)"
        let target = dir.appendingPathComponent(fileName)
        do {
            try fm.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try decoded.write(to: target, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            Self.sendJSON(
                fd: fd,
                status: 200,
                reason: "OK",
                payload: MobileAttachmentUploadResponse(
                    ok: true,
                    path: target.path,
                    name: fileName
                )
            )
        } catch {
            Self.sendJSON(
                fd: fd,
                status: 500,
                reason: "Internal Server Error",
                payload: MobileErrorResponse(ok: false, error: "添付ファイルを保存できませんでした")
            )
        }
    }

    private func parseThreadRoute(path: String) -> (threadId: Int64, subpath: String)? {
        let prefix = "/api/v1/threads/"
        guard path.hasPrefix(prefix) else {
            return nil
        }
        let remainder = String(path.dropFirst(prefix.count))
        guard let slash = remainder.firstIndex(of: "/") else {
            return nil
        }
        let idStr = String(remainder[..<slash])
        guard let threadId = Int64(idStr), threadId > 0 else {
            return nil
        }
        let subpath = String(remainder[slash...])
        return (threadId, subpath)
    }

    private func handleThreadRoute(
        fd: Int32,
        method: String,
        threadId: Int64,
        subpath: String,
        query: [String: String],
        body: Data
    ) {
        let thread: KasugaiThread? = DispatchQueue.main.sync {
            fetchThreadWorkspaceOnMain(threadId)
        }
        guard let thread else {
            Self.sendJSON(
                fd: fd,
                status: 404,
                reason: "Not Found",
                payload: MobileErrorResponse(ok: false, error: "スレッドが見つかりません")
            )
            return
        }
        let workspaceRoot = thread.workspace.effectiveCwd

        if method == "GET" && subpath == "/diff" {
            let report = GitWorkspace.computeDiff(in: workspaceRoot)
            Self.sendJSON(fd: fd, status: 200, reason: "OK", payload: report)
            return
        }

        if method == "GET" && subpath == "/files" {
            let relPath = query["path"] ?? ""
            guard let listing = listWorkspaceDirectory(root: workspaceRoot, relativePath: relPath)
            else {
                Self.sendJSON(
                    fd: fd,
                    status: 403,
                    reason: "Forbidden",
                    payload: MobileErrorResponse(ok: false, error: "指定されたフォルダにアクセスできません")
                )
                return
            }
            Self.sendJSON(fd: fd, status: 200, reason: "OK", payload: listing)
            return
        }

        if method == "GET" && subpath == "/file-preview" {
            let requestedPath = query["path"] ?? ""
            let lineStart = query["line_start"].flatMap(Int.init)
            let lineEnd = query["line_end"].flatMap(Int.init)
            guard
                let resolved = resolveAllowedPath(
                    requestedPath,
                    workspaceRoot: workspaceRoot,
                    thread: thread
                )
            else {
                Self.sendJSON(
                    fd: fd,
                    status: 403,
                    reason: "Forbidden",
                    payload: MobileErrorResponse(ok: false, error: "指定されたファイルにアクセスできません")
                )
                return
            }
            let payload = buildMobileFilePreview(
                path: resolved,
                lineStart: lineStart,
                lineEnd: lineEnd
            )
            Self.sendJSON(fd: fd, status: 200, reason: "OK", payload: payload)
            return
        }

        if method == "GET" && subpath == "/media" {
            let requestedPath = query["path"] ?? ""
            guard
                let resolved = resolveAllowedPath(
                    requestedPath,
                    workspaceRoot: workspaceRoot,
                    thread: thread
                ),
                KasugaiViewRenderer.mediaKind(
                    forExtension: URL(fileURLWithPath: resolved).pathExtension
                ) != nil,
                let data = try? Data(contentsOf: URL(fileURLWithPath: resolved)),
                data.count <= 25 * 1024 * 1024
            else {
                Self.sendJSON(
                    fd: fd,
                    status: 404,
                    reason: "Not Found",
                    payload: MobileErrorResponse(ok: false, error: "メディアファイルが見つかりません")
                )
                return
            }
            let mime = KasugaiViewRenderer.mimeType(URL(fileURLWithPath: resolved))
            Self.sendRawResponse(fd: fd, status: 200, reason: "OK", contentType: mime, body: data)
            return
        }

        if method == "POST" && subpath == "/terminal/open" {
            let req =
                (try? JSONDecoder().decode(MobileTerminalOpenRequest.self, from: body))
                ?? MobileTerminalOpenRequest(cols: 80, rows: 24)
            guard
                let snap = terminalPool.open(
                    threadId: threadId,
                    cwd: workspaceRoot,
                    cols: req.cols,
                    rows: req.rows
                )
            else {
                Self.sendJSON(
                    fd: fd,
                    status: 500,
                    reason: "Internal Server Error",
                    payload: MobileErrorResponse(ok: false, error: "ターミナルを起動できませんでした")
                )
                return
            }
            Self.sendJSON(fd: fd, status: 200, reason: "OK", payload: snap)
            return
        }

        if method == "GET" && subpath == "/terminal/snapshot" {
            let snap =
                terminalPool.snapshot(threadId: threadId)
                ?? terminalPool.open(threadId: threadId, cwd: workspaceRoot, cols: 80, rows: 24)
            guard let snap else {
                Self.sendJSON(
                    fd: fd,
                    status: 500,
                    reason: "Internal Server Error",
                    payload: MobileErrorResponse(ok: false, error: "ターミナル状態を取得できませんでした")
                )
                return
            }
            Self.sendJSON(fd: fd, status: 200, reason: "OK", payload: snap)
            return
        }

        if method == "POST" && subpath == "/terminal/input" {
            guard let req = try? JSONDecoder().decode(MobileTerminalInputRequest.self, from: body)
            else {
                Self.sendJSON(
                    fd: fd,
                    status: 400,
                    reason: "Bad Request",
                    payload: MobileErrorResponse(ok: false, error: "ターミナル入力の形式が不正です")
                )
                return
            }
            if terminalPool.snapshot(threadId: threadId) == nil {
                _ = terminalPool.open(threadId: threadId, cwd: workspaceRoot, cols: 80, rows: 24)
            }
            guard let snap = terminalPool.write(threadId: threadId, text: req.text) else {
                Self.sendJSON(
                    fd: fd,
                    status: 500,
                    reason: "Internal Server Error",
                    payload: MobileErrorResponse(ok: false, error: "ターミナルへ書き込めませんでした")
                )
                return
            }
            Self.sendJSON(fd: fd, status: 200, reason: "OK", payload: snap)
            return
        }

        if method == "POST" && subpath == "/terminal/resize" {
            guard let req = try? JSONDecoder().decode(MobileTerminalResizeRequest.self, from: body)
            else {
                Self.sendJSON(
                    fd: fd,
                    status: 400,
                    reason: "Bad Request",
                    payload: MobileErrorResponse(ok: false, error: "サイズ指定が不正です")
                )
                return
            }
            let snap =
                terminalPool.resize(threadId: threadId, cols: req.cols, rows: req.rows)
                ?? terminalPool.open(
                    threadId: threadId,
                    cwd: workspaceRoot,
                    cols: req.cols,
                    rows: req.rows
                )
            guard let snap else {
                Self.sendJSON(
                    fd: fd,
                    status: 500,
                    reason: "Internal Server Error",
                    payload: MobileErrorResponse(ok: false, error: "ターミナルサイズを変更できませんでした")
                )
                return
            }
            Self.sendJSON(fd: fd, status: 200, reason: "OK", payload: snap)
            return
        }

        if method == "POST" && subpath == "/terminal/close" {
            terminalPool.close(threadId: threadId)
            Self.sendJSON(
                fd: fd,
                status: 200,
                reason: "OK",
                payload: MobileActionResponse(
                    ok: true,
                    error: nil,
                    intValue: nil,
                    boolValue: true,
                    stringValue: nil
                )
            )
            return
        }

        Self.sendJSON(
            fd: fd,
            status: 404,
            reason: "Not Found",
            payload: MobileErrorResponse(ok: false, error: "スレッド API が見つかりません")
        )
    }

    private func resolveAllowedPath(
        _ requested: String,
        workspaceRoot: String,
        thread: KasugaiThread
    ) -> String? {
        let trimmed = requested.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let baseURL = URL(fileURLWithPath: workspaceRoot, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let candidateURL: URL
        if trimmed.hasPrefix("/") {
            candidateURL =
                URL(fileURLWithPath: trimmed)
                .resolvingSymlinksInPath()
                .standardizedFileURL
        } else {
            candidateURL =
                baseURL.appendingPathComponent(trimmed)
                .resolvingSymlinksInPath()
                .standardizedFileURL
        }
        let resolvedPath = candidateURL.path
        let basePath = baseURL.path
        if resolvedPath == basePath || resolvedPath.hasPrefix(basePath + "/") {
            return FileManager.default.fileExists(atPath: resolvedPath) ? resolvedPath : nil
        }

        var threadAttachments: Set<String> = []
        for msg in thread.messages {
            for att in msg.attachments {
                threadAttachments.insert(
                    URL(fileURLWithPath: att).resolvingSymlinksInPath().standardizedFileURL.path
                )
            }
        }
        for queued in thread.queue {
            for att in queued.attachments {
                threadAttachments.insert(
                    URL(fileURLWithPath: att).resolvingSymlinksInPath().standardizedFileURL.path
                )
            }
        }
        if threadAttachments.contains(resolvedPath),
            FileManager.default.fileExists(atPath: resolvedPath)
        {
            return resolvedPath
        }
        return nil
    }

    private func listWorkspaceDirectory(
        root: String,
        relativePath: String
    ) -> MobileDirectoryListing? {
        let baseURL = URL(fileURLWithPath: root, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let cleanedRel = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        let targetURL =
            cleanedRel.isEmpty
            ? baseURL
            : baseURL.appendingPathComponent(cleanedRel, isDirectory: true)
                .resolvingSymlinksInPath()
                .standardizedFileURL
        let basePath = baseURL.path
        let targetPath = targetURL.path
        guard targetPath == basePath || targetPath.hasPrefix(basePath + "/") else {
            return nil
        }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: targetPath, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        guard
            let urls = try? fm.contentsOfDirectory(
                at: targetURL,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return nil
        }
        var entries: [MobileFileEntry] = []
        for item in urls {
            let name = item.lastPathComponent
            if name == ".git" || name == "node_modules" || name == ".build" {
                continue
            }
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let itemIsDir = values?.isDirectory ?? false
            let size = Int64(values?.fileSize ?? 0)
            let rel = cleanedRel.isEmpty ? name : "\(cleanedRel)/\(name)"
            entries.append(
                MobileFileEntry(
                    name: name,
                    relativePath: rel,
                    fullPath: item.path,
                    isDirectory: itemIsDir,
                    sizeBytes: size
                )
            )
        }
        entries.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return MobileDirectoryListing(
            rootPath: basePath,
            relativePath: cleanedRel,
            entries: Array(entries.prefix(500))
        )
    }

    private func buildMobileFilePreview(
        path: String,
        lineStart: Int?,
        lineEnd: Int?
    ) -> MobileFilePreviewPayload {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        let byteSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        let sizeLabel = ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)

        if let mediaKind = KasugaiViewRenderer.mediaKind(forExtension: url.pathExtension) {
            return MobileFilePreviewPayload(
                path: path,
                name: name,
                kind: mediaKind,
                sizeLabel: sizeLabel,
                text: nil,
                mediaUrl: path,
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
                return MobileFilePreviewPayload(
                    path: path,
                    name: name,
                    kind: isMarkdown ? "markdown" : "text",
                    sizeLabel: sizeLabel,
                    text: text + suffix,
                    mediaUrl: nil,
                    highlightLineStart: lineStart,
                    highlightLineEnd: lineEnd ?? lineStart
                )
            }
        }

        return MobileFilePreviewPayload(
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

    private static func readHTTPRequest(fd: Int32) -> ParsedHTTPRequest? {
        let maxHeaderBytes = 64 * 1024
        let maxBodyBytes = 12 * 1024 * 1024
        let delimiter = Data([13, 10, 13, 10])
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        var headerEnd: Data.Index?

        while headerEnd == nil && buffer.count < maxHeaderBytes {
            let n = Darwin.read(fd, &chunk, chunk.count)
            if n < 0 {
                if errno == EINTR {
                    continue
                }
                return nil
            }
            if n == 0 {
                break
            }
            buffer.append(contentsOf: chunk[0..<n])
            if let range = buffer.range(of: delimiter) {
                headerEnd = range.upperBound
            }
        }

        guard let headerEnd,
            let headerText = String(data: buffer.subdata(in: 0..<headerEnd), encoding: .utf8)
        else {
            return nil
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return nil
        }
        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else {
            return nil
        }
        let method = parts[0].uppercased()
        let rawTarget = parts[1]

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            if let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(
                    in: .whitespaces
                )
                headers[key] = value
            }
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        guard contentLength >= 0 && contentLength <= maxBodyBytes else {
            return nil
        }

        var body = Data(buffer.subdata(in: headerEnd..<buffer.count))
        while body.count < contentLength {
            let remaining = min(chunk.count, contentLength - body.count)
            let n = Darwin.read(fd, &chunk, remaining)
            if n < 0 {
                if errno == EINTR {
                    continue
                }
                return nil
            }
            if n == 0 {
                break
            }
            body.append(contentsOf: chunk[0..<n])
        }
        if body.count > contentLength {
            body = body.subdata(in: 0..<contentLength)
        }

        let components = URLComponents(string: "http://localhost" + rawTarget)
        let path = components?.path ?? rawTarget
        var queryItems: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            queryItems[item.name] = item.value ?? ""
        }
        return ParsedHTTPRequest(
            method: method,
            path: path,
            queryItems: queryItems,
            headers: headers,
            body: body
        )
    }

    private static func sendJSON<T: Encodable>(
        fd: Int32,
        status: Int,
        reason: String,
        payload: T
    ) {
        let body = (try? JSONEncoder().encode(payload)) ?? Data("{}".utf8)
        sendRawResponse(
            fd: fd,
            status: status,
            reason: reason,
            contentType: "application/json; charset=utf-8",
            body: body
        )
    }

    private static func sendRawResponse(
        fd: Int32,
        status: Int,
        reason: String,
        contentType: String,
        body: Data
    ) {
        let head =
            "HTTP/1.1 \(status) \(reason)\r\n"
            + "Content-Type: \(contentType)\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Cache-Control: no-store\r\n"
            + "X-Content-Type-Options: nosniff\r\n"
            + "Connection: close\r\n\r\n"
        var framed = Data(head.utf8)
        framed.append(body)
        _ = writeAll(fd: fd, data: framed)
    }

    @discardableResult
    private static func writeAll(fd: Int32, data: Data) -> Bool {
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

    private static func nowMillis() -> Int64 {
        Int64((Date().timeIntervalSince1970 * 1000.0).rounded())
    }

    private static func randomBytes(_ count: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        let rc = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        if rc != errSecSuccess {
            var rng = SystemRandomNumberGenerator()
            for idx in 0..<count {
                bytes[idx] = UInt8.random(in: 0...255, using: &rng)
            }
        }
        return bytes
    }

    private static func randomPairingCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let bytes = randomBytes(8)
        let chars = bytes.map { alphabet[Int($0) % alphabet.count] }
        return String(chars.prefix(4)) + "-" + String(chars.suffix(4))
    }

    private static func randomToken() -> String {
        Data(randomBytes(32))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func sha256Hex(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8)
        let b = Array(rhs.utf8)
        guard a.count == b.count else {
            return false
        }
        var diff: UInt8 = 0
        for idx in 0..<a.count {
            diff |= a[idx] ^ b[idx]
        }
        return diff == 0
    }

    private static func loadAuth(from path: String) -> StoredMobileBridgeAuth {
        guard let data = FileManager.default.contents(atPath: path),
            let decoded = try? JSONDecoder().decode(StoredMobileBridgeAuth.self, from: data)
        else {
            return .empty
        }
        return decoded
    }

    private static func saveAuth(_ auth: StoredMobileBridgeAuth, to path: String) {
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
            let data = try encoder.encode(auth)
            try data.write(to: url, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {}
    }

    static func runSelfTests() -> Bool {
        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent(
            "kasugai-mobile-bridge-test-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fm.removeItem(at: workDir) }
        do {
            try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
            try Data("hello kasugai mobile\nsecond line\n".utf8).write(
                to: workDir.appendingPathComponent("sample.txt")
            )
        } catch {
            return false
        }

        let storeFile = workDir.appendingPathComponent("events.jsonl").path
        let authFile = workDir.appendingPathComponent("mobile-bridge.json").path
        guard
            let core = KasugaiCore(
                projectName: "MobileTest", projectPath: workDir.path, storePath: storeFile)
        else {
            return false
        }
        defer { core.close() }

        let server = MobileBridgeServer(
            authStorePath: authFile,
            fetchSnapshotJSONOnMain: { core.snapshotJSON() },
            fetchThreadWorkspaceOnMain: { tid in
                core.snapshot()?.threads.first(where: { $0.id == tid })
            },
            executeActionOnMain: { req in
                if req.method == "send_message" {
                    let id =
                        core.sendMessage(
                            threadId: req.threadId ?? 0,
                            text: req.text ?? "",
                            attachments: req.attachments ?? []
                        ) ?? 0
                    return DaemonResponse(
                        ok: id > 0,
                        error: nil,
                        intValue: id,
                        boolValue: nil,
                        stringValue: nil,
                        hello: nil
                    )
                }
                return .failure("unsupported")
            }
        )
        defer { server.stop(disableTailscaleServe: false) }

        let started = server.configure(
            enabled: true,
            localPort: 0,
            httpsPort: 9443,
            manageTailscaleServe: false
        )
        guard started.running, started.localPort > 0 else {
            return false
        }
        let port = started.localPort
        let baseURL = "http://127.0.0.1:\(port)"

        func httpCall(
            method: String,
            path: String,
            token: String? = nil,
            body: Data? = nil
        ) -> (status: Int, data: Data)? {
            guard let url = URL(string: baseURL + path) else {
                return nil
            }
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.httpBody = body
            if body != nil {
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            if let token {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            var outStatus = 0
            var outData = Data()
            var succeeded = false
            var done = false
            let task = URLSession.shared.dataTask(with: req) { data, resp, _ in
                if let http = resp as? HTTPURLResponse {
                    outStatus = http.statusCode
                    outData = data ?? Data()
                    succeeded = true
                }
                done = true
            }
            task.resume()
            let deadline = Date().addingTimeInterval(5.0)
            while !done && Date() < deadline {
                CFRunLoopRunInMode(.defaultMode, 0.01, false)
            }
            return succeeded ? (outStatus, outData) : nil
        }

        let healthResp = httpCall(method: "GET", path: "/api/v1/health")
        let unauthSnap = httpCall(method: "GET", path: "/api/v1/snapshot")
        guard healthResp?.status == 200, unauthSnap?.status == 401 else {
            return false
        }

        let pairedStatus = server.generatePairingCode()
        let code = pairedStatus.activePairingCode
        guard !code.isEmpty else {
            return false
        }
        let uriPayload = MobilePairingPayload(hostURL: baseURL, code: code)
        guard MobilePairingPayload.parse(uriPayload.uriString) == uriPayload else {
            return false
        }

        let wrongPairBody = try? JSONEncoder().encode(
            MobilePairRequest(code: "ZZZZ-9999", deviceName: "Test")
        )
        let wrongPair = httpCall(method: "POST", path: "/api/v1/pair", body: wrongPairBody)
        guard wrongPair?.status == 401 else {
            return false
        }

        let goodPairBody = try? JSONEncoder().encode(
            MobilePairRequest(code: code, deviceName: "iPhone テスト")
        )
        guard let goodPair = httpCall(method: "POST", path: "/api/v1/pair", body: goodPairBody),
            goodPair.status == 200,
            let pairResp = try? JSONDecoder().decode(MobilePairResponse.self, from: goodPair.data),
            pairResp.ok,
            !pairResp.token.isEmpty
        else {
            return false
        }

        let replayPair = httpCall(method: "POST", path: "/api/v1/pair", body: goodPairBody)
        guard replayPair?.status == 401 else {
            return false
        }

        guard
            let authSnap = httpCall(method: "GET", path: "/api/v1/snapshot", token: pairResp.token),
            authSnap.status == 200,
            let decodedSnap = try? JSONDecoder().decode(
                KasugaiCoreSnapshot.self, from: authSnap.data),
            let activeThreadId = decodedSnap.activeThread?.id
        else {
            return false
        }

        guard
            let filesResp = httpCall(
                method: "GET",
                path: "/api/v1/threads/\(activeThreadId)/files",
                token: pairResp.token
            ),
            filesResp.status == 200,
            let listing = try? JSONDecoder().decode(
                MobileDirectoryListing.self, from: filesResp.data),
            listing.entries.contains(where: { $0.name == "sample.txt" })
        else {
            return false
        }

        let escapeResp = httpCall(
            method: "GET",
            path: "/api/v1/threads/\(activeThreadId)/file-preview?path=/etc/hosts",
            token: pairResp.token
        )
        guard escapeResp?.status == 403 else {
            return false
        }

        guard
            let previewResp = httpCall(
                method: "GET",
                path: "/api/v1/threads/\(activeThreadId)/file-preview?path=sample.txt&line_start=2",
                token: pairResp.token
            ),
            previewResp.status == 200,
            let preview = try? JSONDecoder().decode(
                MobileFilePreviewPayload.self,
                from: previewResp.data
            ),
            preview.kind == "text",
            preview.highlightLineStart == 2,
            preview.text?.contains("hello kasugai mobile") == true
        else {
            return false
        }

        let sendBody = try? JSONEncoder().encode(
            MobileActionRequest(
                method: "send_message",
                threadId: activeThreadId,
                text: "スマホから送信テスト"
            )
        )
        let sendResp = httpCall(
            method: "POST",
            path: "/api/v1/action",
            token: pairResp.token,
            body: sendBody
        )
        guard sendResp?.status == 200 else {
            return false
        }

        let openTermBody = try? JSONEncoder().encode(MobileTerminalOpenRequest(cols: 80, rows: 16))
        let termOpenResp = httpCall(
            method: "POST",
            path: "/api/v1/threads/\(activeThreadId)/terminal/open",
            token: pairResp.token,
            body: openTermBody
        )
        let termCloseResp = httpCall(
            method: "POST",
            path: "/api/v1/threads/\(activeThreadId)/terminal/close",
            token: pairResp.token
        )
        guard termOpenResp?.status == 200, termCloseResp?.status == 200 else {
            return false
        }

        _ = server.revokeDevice(id: pairResp.deviceId)
        let revokedSnap = httpCall(method: "GET", path: "/api/v1/snapshot", token: pairResp.token)
        return revokedSnap?.status == 401
    }
}
