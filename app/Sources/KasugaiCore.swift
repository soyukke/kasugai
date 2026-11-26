import Darwin
import Foundation

struct KasugaiProviderSpec: Codable {
    let id: String
    let displayName: String
    let transport: String
    let defaultModel: String
    let ready: Bool
    let launchSpec: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case transport
        case defaultModel = "default_model"
        case ready
        case launchSpec = "launch_spec"
    }
}

struct KasugaiProject: Codable {
    let id: Int64
    let name: String
    let rootPath: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case rootPath = "root_path"
    }
}

struct KasugaiPendingApproval: Codable {
    let active: Bool
    let toolName: String
    let summary: String

    enum CodingKeys: String, CodingKey {
        case active
        case toolName = "tool_name"
        case summary
    }
}

struct KasugaiWorkspaceSnapshot: Codable {
    let mode: String
    let rootPath: String
    let worktreePath: String
    let effectiveCwd: String
    let branch: String
    let baseRef: String
    let diffFilesChanged: Int64
    let diffInsertions: Int64
    let diffDeletions: Int64

    enum CodingKeys: String, CodingKey {
        case mode
        case rootPath = "root_path"
        case worktreePath = "worktree_path"
        case effectiveCwd = "effective_cwd"
        case branch
        case baseRef = "base_ref"
        case diffFilesChanged = "diff_files_changed"
        case diffInsertions = "diff_insertions"
        case diffDeletions = "diff_deletions"
    }
}

struct KasugaiMessage: Codable {
    let id: Int64
    let turnId: Int64
    let role: String
    let text: String
    let provider: String
    let model: String
    let attachments: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case turnId = "turn_id"
        case role
        case text
        case provider
        case model
        case attachments
    }
}

struct KasugaiQueuedTurn: Codable {
    let turnId: Int64
    let text: String
    let attachments: [String]

    enum CodingKeys: String, CodingKey {
        case turnId = "turn_id"
        case text
        case attachments
    }
}

struct KasugaiActivity: Codable {
    let turnId: Int64
    let callId: String
    let kind: String
    let title: String
    let status: String
    let detail: String

    enum CodingKeys: String, CodingKey {
        case turnId = "turn_id"
        case callId = "call_id"
        case kind
        case title
        case status
        case detail
    }
}

struct KasugaiThread: Codable {
    let id: Int64
    let projectId: Int64
    let title: String
    let updatedAtMs: Int64
    let status: String
    let sessionState: String
    let provider: String
    let providerName: String
    let model: String
    let effort: String
    let activeTurnId: Int64
    let streamingText: String
    let lastError: String
    let availableModels: [String]
    let activities: [KasugaiActivity]
    let pendingApproval: KasugaiPendingApproval
    let workspace: KasugaiWorkspaceSnapshot
    let messages: [KasugaiMessage]
    let queue: [KasugaiQueuedTurn]

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case title
        case updatedAtMs = "updated_at_ms"
        case status
        case sessionState = "session_state"
        case provider
        case providerName = "provider_name"
        case model
        case effort
        case activeTurnId = "active_turn_id"
        case streamingText = "streaming_text"
        case lastError = "last_error"
        case availableModels = "available_models"
        case activities
        case pendingApproval = "pending_approval"
        case workspace
        case messages
        case queue
    }

    var isDefaultTitle: Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return true
        }
        guard trimmed.hasPrefix("スレッド ") else {
            return false
        }
        let suffix = trimmed.dropFirst("スレッド ".count)
        return !suffix.isEmpty && suffix.allSatisfy(\.isNumber)
    }

    var displayTitle: String {
        if !isDefaultTitle {
            return title
        }
        if let firstUser = messages.first(where: { $0.role == "user" }) {
            let derived = Self.deriveTitle(from: firstUser.text)
            if !derived.isEmpty {
                return derived
            }
        }
        return "新規スレッド"
    }

    static func deriveTitle(from prompt: String) -> String {
        let firstLine =
            prompt
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
        if firstLine.count <= 28 {
            return firstLine
        }
        return String(firstLine.prefix(27)) + "…"
    }
}

struct KasugaiWakeupFD: Codable, Equatable {
    let threadId: Int64
    let fd: Int32

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case fd
    }
}

struct KasugaiCoreSnapshot: Codable {
    let schemaVersion: Int64
    let activeProjectId: Int64
    let activeThreadId: Int64
    let suppressTelemetry: Bool
    let autoApproveTools: Bool
    let eventCount: Int64
    let providers: [KasugaiProviderSpec]
    let projects: [KasugaiProject]
    let threads: [KasugaiThread]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case activeProjectId = "active_project_id"
        case activeThreadId = "active_thread_id"
        case suppressTelemetry = "suppress_telemetry"
        case autoApproveTools = "auto_approve_tools"
        case eventCount = "event_count"
        case providers
        case projects
        case threads
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int64.self, forKey: .schemaVersion)
        activeProjectId = try c.decode(Int64.self, forKey: .activeProjectId)
        activeThreadId = try c.decode(Int64.self, forKey: .activeThreadId)
        suppressTelemetry = try c.decode(Bool.self, forKey: .suppressTelemetry)
        autoApproveTools = try c.decodeIfPresent(Bool.self, forKey: .autoApproveTools) ?? false
        eventCount = try c.decode(Int64.self, forKey: .eventCount)
        providers = try c.decode([KasugaiProviderSpec].self, forKey: .providers)
        projects = try c.decode([KasugaiProject].self, forKey: .projects)
        threads = try c.decode([KasugaiThread].self, forKey: .threads)
    }

    var activeThread: KasugaiThread? {
        threads.first { $0.id == activeThreadId }
    }

    func threads(forProject projectId: Int64) -> [KasugaiThread] {
        threads.filter { $0.projectId == projectId }
    }
}

final class KasugaiCore {
    private enum Backend {
        case direct(UnsafeMutableRawPointer)
        case remote(KasugaiDaemonClient)
    }

    private var backend: Backend?
    private var directMobileBridge: MobileBridgeServer?

    var isRemoteDaemon: Bool {
        if case .remote = backend {
            return true
        }
        return false
    }

    var daemonSocketPath: String? {
        if case .remote(let client) = backend {
            return client.socketPath
        }
        return nil
    }

    var onRemoteChanged: (() -> Void)? {
        get {
            if case .remote(let client) = backend {
                return client.onChanged
            }
            return nil
        }
        set {
            if case .remote(let client) = backend {
                client.onChanged = newValue
            }
        }
    }

    var onRemoteReconnected: (() -> Void)? {
        get {
            if case .remote(let client) = backend {
                return client.onReconnected
            }
            return nil
        }
        set {
            if case .remote(let client) = backend {
                client.onReconnected = newValue
            }
        }
    }

    static func defaultStorePath() -> String {
        if let override = ProcessInfo.processInfo.environment["KASUGAI_STORE_PATH"],
            !override.isEmpty
        {
            return override
        }
        return KasugaiRuntimePaths.dataDirectory()
            .appendingPathComponent("events.jsonl")
            .path
    }

    init?(projectName: String, projectPath: String, storePath: String? = nil) {
        let created: UnsafeMutableRawPointer?
        if let storePath, !storePath.isEmpty {
            created = projectName.withCString { namePtr in
                projectPath.withCString { pathPtr in
                    storePath.withCString { storePtr in
                        kasugaiCoreCreateWithStore(namePtr, pathPtr, storePtr)
                    }
                }
            }
        } else {
            created = projectName.withCString { namePtr in
                projectPath.withCString { pathPtr in
                    kasugaiCoreCreate(namePtr, pathPtr)
                }
            }
        }
        guard let created else {
            return nil
        }
        self.backend = .direct(created)
    }

    private init(remoteClient: KasugaiDaemonClient) {
        self.backend = .remote(remoteClient)
    }

    static func connectToDaemon(
        projectName: String,
        projectPath: String,
        storePath: String = defaultStorePath(),
        socketPath: String = KasugaiDaemonPaths.defaultSocketPath(),
        daemonExecutable: String = KasugaiDaemonPaths.daemonExecutablePath()
    ) -> KasugaiCore? {
        guard
            let client = KasugaiDaemonClient.ensureRunningAndConnect(
                socketPath: socketPath,
                storePath: storePath,
                projectName: projectName,
                projectPath: projectPath,
                daemonExecutable: daemonExecutable
            )
        else {
            return nil
        }
        return KasugaiCore(remoteClient: client)
    }

    deinit {
        close()
    }

    func close() {
        guard let current = backend else {
            return
        }
        backend = nil
        directMobileBridge?.stop(disableTailscaleServe: false)
        directMobileBridge = nil
        switch current {
        case .direct(let handle):
            kasugaiCoreDestroy(handle)
        case .remote(let client):
            client.stopSubscription()
        }
    }

    func disconnectClient() {
        if case .remote(let client) = backend {
            client.stopSubscription()
        }
    }

    func remoteHello() -> DaemonHello? {
        if case .remote(let client) = backend {
            return client.hello()
        }
        return nil
    }

    @discardableResult
    func ensureRemoteDaemonAlive() -> Bool {
        if case .remote(let client) = backend {
            return client.ensureAlive()
        }
        return true
    }

    @discardableResult
    func restartRemoteDaemonIfIdle() -> Bool {
        if case .remote(let client) = backend {
            return client.restartDaemon()
        }
        return true
    }

    func snapshotJSON() -> String? {
        guard let backend else {
            return nil
        }
        switch backend {
        case .direct(let handle):
            return copyAndFree(kasugaiCoreSnapshotJson(handle))
        case .remote(let client):
            guard let res = client.call(DaemonRequest(method: "snapshot")), res.ok else {
                return nil
            }
            return res.stringValue
        }
    }

    func snapshot() -> KasugaiCoreSnapshot? {
        guard let json = snapshotJSON() else {
            return nil
        }
        return try? JSONDecoder().decode(KasugaiCoreSnapshot.self, from: Data(json.utf8))
    }

    func eventsJsonl(threadId: Int64 = 0) -> String? {
        guard let backend else {
            return nil
        }
        switch backend {
        case .direct(let handle):
            return copyAndFree(kasugaiCoreEventsJsonl(handle, threadId))
        case .remote(let client):
            var req = DaemonRequest(method: "events_jsonl")
            req.threadId = threadId
            guard let res = client.call(req), res.ok else {
                return nil
            }
            return res.stringValue
        }
    }

    @discardableResult
    func pollProviders() -> Bool {
        guard let backend else {
            return false
        }
        switch backend {
        case .direct(let handle):
            return kasugaiCorePollProviders(handle) != 0
        case .remote(let client):
            let res = client.call(DaemonRequest(method: "poll_providers"))
            return res?.boolValue ?? false
        }
    }

    func providerWakeupFDs() -> [KasugaiWakeupFD] {
        guard let backend else {
            return []
        }
        switch backend {
        case .direct(let handle):
            guard let json = copyAndFree(kasugaiCoreProviderWakeupFds(handle)),
                let decoded = try? JSONDecoder().decode(
                    [KasugaiWakeupFD].self, from: Data(json.utf8))
            else {
                return []
            }
            return decoded
        case .remote:
            return []
        }
    }

    @discardableResult
    func addProject(name: String, rootPath: String) -> Int64? {
        guard let backend else {
            return nil
        }
        switch backend {
        case .direct(let handle):
            let id = name.withCString { namePtr in
                rootPath.withCString { pathPtr in
                    kasugaiCoreAddProject(handle, namePtr, pathPtr)
                }
            }
            return id > 0 ? id : nil
        case .remote(let client):
            var req = DaemonRequest(method: "add_project")
            req.name = name
            req.rootPath = rootPath
            guard let res = client.call(req), res.ok, let id = res.intValue, id > 0 else {
                return nil
            }
            return id
        }
    }

    @discardableResult
    func selectProject(_ projectId: Int64) -> Bool {
        guard let backend else {
            return false
        }
        switch backend {
        case .direct(let handle):
            return kasugaiCoreSelectProject(handle, projectId) != 0
        case .remote(let client):
            var req = DaemonRequest(method: "select_project")
            req.projectId = projectId
            return client.call(req)?.ok ?? false
        }
    }

    @discardableResult
    func createThread(
        projectId: Int64,
        title: String = "",
        provider: String = "local_echo",
        model: String = "",
        effort: String = "medium"
    ) -> Int64? {
        guard let backend else {
            return nil
        }
        switch backend {
        case .direct(let handle):
            let id = title.withCString { titlePtr in
                provider.withCString { providerPtr in
                    model.withCString { modelPtr in
                        effort.withCString { effortPtr in
                            kasugaiCoreCreateThread(
                                handle,
                                projectId,
                                titlePtr,
                                providerPtr,
                                modelPtr,
                                effortPtr
                            )
                        }
                    }
                }
            }
            return id > 0 ? id : nil
        case .remote(let client):
            var req = DaemonRequest(method: "create_thread")
            req.projectId = projectId
            req.title = title
            req.provider = provider
            req.model = model
            req.effort = effort
            guard let res = client.call(req), res.ok, let id = res.intValue, id > 0 else {
                return nil
            }
            return id
        }
    }

    @discardableResult
    func selectThread(_ threadId: Int64) -> Bool {
        guard let backend else {
            return false
        }
        switch backend {
        case .direct(let handle):
            return kasugaiCoreSelectThread(handle, threadId) != 0
        case .remote(let client):
            var req = DaemonRequest(method: "select_thread")
            req.threadId = threadId
            return client.call(req)?.ok ?? false
        }
    }

    @discardableResult
    func renameThread(_ threadId: Int64, title: String) -> Bool {
        guard let backend else {
            return false
        }
        switch backend {
        case .direct(let handle):
            return title.withCString { titlePtr in
                kasugaiCoreRenameThread(handle, threadId, titlePtr) != 0
            }
        case .remote(let client):
            var req = DaemonRequest(method: "rename_thread")
            req.threadId = threadId
            req.title = title
            return client.call(req)?.ok ?? false
        }
    }

    @discardableResult
    func setThreadProvider(
        _ threadId: Int64,
        provider: String,
        model: String,
        effort: String
    ) -> Bool {
        guard let backend else {
            return false
        }
        switch backend {
        case .direct(let handle):
            return provider.withCString { providerPtr in
                model.withCString { modelPtr in
                    effort.withCString { effortPtr in
                        kasugaiCoreSetThreadProvider(
                            handle, threadId, providerPtr, modelPtr, effortPtr
                        ) != 0
                    }
                }
            }
        case .remote(let client):
            var req = DaemonRequest(method: "set_thread_provider")
            req.threadId = threadId
            req.provider = provider
            req.model = model
            req.effort = effort
            return client.call(req)?.ok ?? false
        }
    }

    @discardableResult
    func sendMessage(threadId: Int64, text: String, attachments: [String] = []) -> Int64? {
        guard let backend else {
            return nil
        }
        switch backend {
        case .direct(let handle):
            let joined = attachments.joined(separator: "\n")
            let turnId = text.withCString { textPtr in
                joined.withCString { attPtr in
                    kasugaiCoreSendMessage(handle, threadId, textPtr, attPtr)
                }
            }
            return turnId > 0 ? turnId : nil
        case .remote(let client):
            var req = DaemonRequest(method: "send_message")
            req.threadId = threadId
            req.text = text
            req.attachments = attachments
            guard let res = client.call(req), res.ok, let turnId = res.intValue, turnId > 0 else {
                return nil
            }
            return turnId
        }
    }

    @discardableResult
    func enqueueMessage(threadId: Int64, text: String, attachments: [String] = []) -> Int64? {
        guard let backend else {
            return nil
        }
        switch backend {
        case .direct(let handle):
            let joined = attachments.joined(separator: "\n")
            let turnId = text.withCString { textPtr in
                joined.withCString { attPtr in
                    kasugaiCoreEnqueueMessage(handle, threadId, textPtr, attPtr)
                }
            }
            return turnId > 0 ? turnId : nil
        case .remote(let client):
            var req = DaemonRequest(method: "enqueue_message")
            req.threadId = threadId
            req.text = text
            req.attachments = attachments
            guard let res = client.call(req), res.ok, let turnId = res.intValue, turnId > 0 else {
                return nil
            }
            return turnId
        }
    }

    @discardableResult
    func processNextQueued(threadId: Int64) -> Bool {
        guard let backend else {
            return false
        }
        switch backend {
        case .direct(let handle):
            return kasugaiCoreProcessNextQueued(handle, threadId) != 0
        case .remote(let client):
            var req = DaemonRequest(method: "process_next_queued")
            req.threadId = threadId
            return client.call(req)?.ok ?? false
        }
    }

    @discardableResult
    func cancelQueuedTurn(threadId: Int64, turnId: Int64) -> Bool {
        guard let backend else {
            return false
        }
        switch backend {
        case .direct(let handle):
            return kasugaiCoreCancelQueuedTurn(handle, threadId, turnId) != 0
        case .remote(let client):
            var req = DaemonRequest(method: "cancel_queued_turn")
            req.threadId = threadId
            req.turnId = turnId
            return client.call(req)?.ok ?? false
        }
    }

    @discardableResult
    func resolveApproval(threadId: Int64, approve: Bool) -> Bool {
        guard let backend else {
            return false
        }
        switch backend {
        case .direct(let handle):
            return kasugaiCoreResolveApproval(handle, threadId, approve ? 1 : 0) != 0
        case .remote(let client):
            var req = DaemonRequest(method: "resolve_approval")
            req.threadId = threadId
            req.approve = approve
            return client.call(req)?.ok ?? false
        }
    }

    @discardableResult
    func cancelActiveTurn(threadId: Int64) -> Bool {
        guard let backend else {
            return false
        }
        switch backend {
        case .direct(let handle):
            return kasugaiCoreCancelActiveTurn(handle, threadId) != 0
        case .remote(let client):
            var req = DaemonRequest(method: "cancel_active_turn")
            req.threadId = threadId
            return client.call(req)?.ok ?? false
        }
    }

    @discardableResult
    func setTelemetrySuppression(_ enabled: Bool) -> Bool {
        guard let backend else {
            return false
        }
        switch backend {
        case .direct(let handle):
            return kasugaiCoreSetTelemetrySuppression(handle, enabled ? 1 : 0) != 0
        case .remote(let client):
            var req = DaemonRequest(method: "set_telemetry_suppression")
            req.enabled = enabled
            return client.call(req)?.ok ?? false
        }
    }

    @discardableResult
    func setAutoApproveTools(_ enabled: Bool) -> Bool {
        guard let backend else {
            return false
        }
        switch backend {
        case .direct(let handle):
            return kasugaiCoreSetAutoApproveTools(handle, enabled ? 1 : 0) != 0
        case .remote(let client):
            var req = DaemonRequest(method: "set_auto_approve_tools")
            req.enabled = enabled
            return client.call(req)?.ok ?? false
        }
    }

    @discardableResult
    func setOrchestratorBridge(socketPath: String, ctlBin: String) -> Bool {
        guard let backend else {
            return false
        }
        switch backend {
        case .direct(let handle):
            return socketPath.withCString { sockPtr in
                ctlBin.withCString { binPtr in
                    kasugaiCoreSetOrchestratorBridge(handle, sockPtr, binPtr) != 0
                }
            }
        case .remote(let client):
            var req = DaemonRequest(method: "set_orchestrator_bridge")
            req.socketPath = socketPath
            req.ctlBin = ctlBin
            return client.call(req)?.ok ?? false
        }
    }

    func setRemoteOrchestratorEnabled(_ enabled: Bool, ctlBin: String) -> String {
        guard case .remote(let client) = backend else {
            return ""
        }
        var req = DaemonRequest(method: "set_orchestrator_enabled")
        req.enabled = enabled
        req.ctlBin = ctlBin
        return client.call(req)?.stringValue ?? ""
    }

    private func ensureDirectMobileBridge() -> MobileBridgeServer {
        if let existing = directMobileBridge {
            return existing
        }
        let created = MobileBridgeServer(
            fetchSnapshotJSONOnMain: { [weak self] in
                self?.snapshotJSON()
            },
            fetchThreadWorkspaceOnMain: { [weak self] tid in
                self?.snapshot()?.threads.first(where: { $0.id == tid })
            },
            executeActionOnMain: { [weak self] req in
                self?.executeDirectMobileAction(req) ?? .failure("core unavailable")
            }
        )
        directMobileBridge = created
        return created
    }

    private func executeDirectMobileAction(_ req: DaemonRequest) -> DaemonResponse {
        switch req.method {
        case "select_project":
            let ok = selectProject(req.projectId ?? 0)
            return DaemonResponse(
                ok: ok, error: ok ? nil : "select_project failed", intValue: nil, boolValue: ok,
                stringValue: nil, hello: nil)
        case "select_thread":
            let ok = selectThread(req.threadId ?? 0)
            return DaemonResponse(
                ok: ok, error: ok ? nil : "select_thread failed", intValue: nil, boolValue: ok,
                stringValue: nil, hello: nil)
        case "create_thread":
            let id =
                createThread(
                    projectId: req.projectId ?? 0,
                    title: req.title ?? "",
                    provider: req.provider ?? "local_echo",
                    model: req.model ?? "",
                    effort: req.effort ?? "medium"
                ) ?? 0
            return DaemonResponse(
                ok: id > 0, error: id > 0 ? nil : "create_thread failed", intValue: id,
                boolValue: nil, stringValue: nil, hello: nil)
        case "rename_thread":
            let ok = renameThread(req.threadId ?? 0, title: req.title ?? "")
            return DaemonResponse(
                ok: ok, error: ok ? nil : "rename_thread failed", intValue: nil, boolValue: ok,
                stringValue: nil, hello: nil)
        case "set_thread_provider":
            let ok = setThreadProvider(
                req.threadId ?? 0,
                provider: req.provider ?? "local_echo",
                model: req.model ?? "",
                effort: req.effort ?? "medium"
            )
            return DaemonResponse(
                ok: ok, error: ok ? nil : "set_thread_provider failed", intValue: nil,
                boolValue: ok, stringValue: nil, hello: nil)
        case "send_message":
            let id =
                sendMessage(
                    threadId: req.threadId ?? 0,
                    text: req.text ?? "",
                    attachments: req.attachments ?? []
                ) ?? 0
            return DaemonResponse(
                ok: id > 0, error: id > 0 ? nil : "send_message failed", intValue: id,
                boolValue: nil, stringValue: nil, hello: nil)
        case "enqueue_message":
            let id =
                enqueueMessage(
                    threadId: req.threadId ?? 0,
                    text: req.text ?? "",
                    attachments: req.attachments ?? []
                ) ?? 0
            return DaemonResponse(
                ok: id > 0, error: id > 0 ? nil : "enqueue_message failed", intValue: id,
                boolValue: nil, stringValue: nil, hello: nil)
        case "process_next_queued":
            let ok = processNextQueued(threadId: req.threadId ?? 0)
            return DaemonResponse(
                ok: ok, error: ok ? nil : "process_next_queued failed", intValue: nil,
                boolValue: ok, stringValue: nil, hello: nil)
        case "cancel_queued_turn":
            let ok = cancelQueuedTurn(threadId: req.threadId ?? 0, turnId: req.turnId ?? 0)
            return DaemonResponse(
                ok: ok, error: ok ? nil : "cancel_queued_turn failed", intValue: nil,
                boolValue: ok, stringValue: nil, hello: nil)
        case "cancel_active_turn":
            let ok = cancelActiveTurn(threadId: req.threadId ?? 0)
            return DaemonResponse(
                ok: ok, error: ok ? nil : "cancel_active_turn failed", intValue: nil,
                boolValue: ok, stringValue: nil, hello: nil)
        case "resolve_approval":
            let ok = resolveApproval(threadId: req.threadId ?? 0, approve: req.approve ?? false)
            return DaemonResponse(
                ok: ok, error: ok ? nil : "resolve_approval failed", intValue: nil,
                boolValue: ok, stringValue: nil, hello: nil)
        case "set_auto_approve_tools":
            let ok = setAutoApproveTools(req.enabled ?? false)
            return DaemonResponse(
                ok: ok, error: ok ? nil : "set_auto_approve_tools failed", intValue: nil,
                boolValue: ok, stringValue: nil, hello: nil)
        case "reset_worktree":
            let ok = resetWorktree(threadId: req.threadId ?? 0)
            return DaemonResponse(
                ok: ok, error: ok ? nil : "reset_worktree failed", intValue: nil,
                boolValue: ok, stringValue: nil, hello: nil)
        default:
            return .failure("unsupported method")
        }
    }

    func configureMobileBridge(
        enabled: Bool,
        localPort: UInt16,
        httpsPort: UInt16,
        manageTailscale: Bool
    ) -> MobileBridgeStatusSnapshot? {
        guard let backend else {
            return nil
        }
        switch backend {
        case .direct:
            return ensureDirectMobileBridge().configure(
                enabled: enabled,
                localPort: localPort,
                httpsPort: httpsPort,
                manageTailscaleServe: manageTailscale
            )
        case .remote(let client):
            var req = DaemonRequest(method: "configure_mobile_bridge")
            req.enabled = enabled
            req.localPort = localPort
            req.httpsPort = httpsPort
            req.manageTailscale = manageTailscale
            guard let raw = client.call(req, timeoutSeconds: 15)?.stringValue else {
                return nil
            }
            return try? JSONDecoder().decode(MobileBridgeStatusSnapshot.self, from: Data(raw.utf8))
        }
    }

    func mobileBridgeStatus(refreshTailscale: Bool = true) -> MobileBridgeStatusSnapshot? {
        guard let backend else {
            return nil
        }
        switch backend {
        case .direct:
            return directMobileBridge?.statusSnapshot(refreshTailscale: refreshTailscale)
                ?? .disabled
        case .remote(let client):
            var req = DaemonRequest(method: "mobile_bridge_status")
            req.manageTailscale = refreshTailscale
            guard let raw = client.call(req, timeoutSeconds: 10)?.stringValue else {
                return nil
            }
            return try? JSONDecoder().decode(MobileBridgeStatusSnapshot.self, from: Data(raw.utf8))
        }
    }

    func generateMobilePairingCode() -> MobileBridgeStatusSnapshot? {
        guard let backend else {
            return nil
        }
        switch backend {
        case .direct:
            return ensureDirectMobileBridge().generatePairingCode()
        case .remote(let client):
            let req = DaemonRequest(method: "mobile_bridge_generate_pairing")
            guard let raw = client.call(req, timeoutSeconds: 10)?.stringValue else {
                return nil
            }
            return try? JSONDecoder().decode(MobileBridgeStatusSnapshot.self, from: Data(raw.utf8))
        }
    }

    func revokeMobileDevice(id: String) -> MobileBridgeStatusSnapshot? {
        guard let backend else {
            return nil
        }
        switch backend {
        case .direct:
            let bridge = ensureDirectMobileBridge()
            return id.isEmpty ? bridge.revokeAllDevices() : bridge.revokeDevice(id: id)
        case .remote(let client):
            var req = DaemonRequest(method: "mobile_bridge_revoke_device")
            req.deviceId = id
            guard let raw = client.call(req, timeoutSeconds: 10)?.stringValue else {
                return nil
            }
            return try? JSONDecoder().decode(MobileBridgeStatusSnapshot.self, from: Data(raw.utf8))
        }
    }

    @discardableResult
    func setProviderCommandOverride(
        provider: String,
        executable: String,
        arguments: [String]
    ) -> Bool {
        guard let backend else {
            return false
        }
        switch backend {
        case .direct(let handle):
            let joined = arguments.joined(separator: "\u{1F}")
            return provider.withCString { provPtr in
                executable.withCString { execPtr in
                    joined.withCString { argsPtr in
                        kasugaiCoreSetProviderCommandOverride(handle, provPtr, execPtr, argsPtr)
                            != 0
                    }
                }
            }
        case .remote(let client):
            var req = DaemonRequest(method: "set_provider_command_override")
            req.provider = provider
            req.executable = executable
            req.arguments = arguments
            return client.call(req)?.ok ?? false
        }
    }

    @discardableResult
    func bindWorktree(
        threadId: Int64,
        branch: String,
        baseRef: String,
        worktreePath: String
    ) -> Bool {
        guard let backend else {
            return false
        }
        switch backend {
        case .direct(let handle):
            return branch.withCString { branchPtr in
                baseRef.withCString { basePtr in
                    worktreePath.withCString { pathPtr in
                        kasugaiCoreBindWorktree(handle, threadId, branchPtr, basePtr, pathPtr) != 0
                    }
                }
            }
        case .remote(let client):
            var req = DaemonRequest(method: "bind_worktree")
            req.threadId = threadId
            req.branch = branch
            req.baseRef = baseRef
            req.worktreePath = worktreePath
            return client.call(req)?.ok ?? false
        }
    }

    @discardableResult
    func resetWorktree(threadId: Int64) -> Bool {
        guard let backend else {
            return false
        }
        switch backend {
        case .direct(let handle):
            return kasugaiCoreResetWorktree(handle, threadId) != 0
        case .remote(let client):
            var req = DaemonRequest(method: "reset_worktree")
            req.threadId = threadId
            return client.call(req)?.ok ?? false
        }
    }

    @discardableResult
    func updateDiffStats(
        threadId: Int64,
        filesChanged: Int64,
        insertions: Int64,
        deletions: Int64
    ) -> Bool {
        guard let backend else {
            return false
        }
        switch backend {
        case .direct(let handle):
            return kasugaiCoreUpdateDiffStats(
                handle, threadId, filesChanged, insertions, deletions
            ) != 0
        case .remote(let client):
            var req = DaemonRequest(method: "update_diff_stats")
            req.threadId = threadId
            req.filesChanged = filesChanged
            req.insertions = insertions
            req.deletions = deletions
            return client.call(req)?.ok ?? false
        }
    }

    private func copyAndFree(_ pointer: UnsafeMutablePointer<CChar>?) -> String? {
        guard let pointer else {
            return nil
        }
        defer {
            kasugaiStringFree(pointer)
        }
        return String(cString: pointer)
    }

    static func runSelfTests() -> Bool {
        let storeURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kasugai-swift-core-\(UUID().uuidString).jsonl"
        )
        defer { try? FileManager.default.removeItem(at: storeURL) }

        do {
            guard
                let core = KasugaiCore(
                    projectName: "Kasugai",
                    projectPath: "/tmp",
                    storePath: storeURL.path
                )
            else {
                return false
            }
            guard let initial = core.snapshot(),
                initial.suppressTelemetry,
                initial.projects.count == 1,
                initial.threads.count == 1,
                initial.providers.count == 5,
                initial.providers.allSatisfy({ $0.ready })
            else {
                return false
            }
            guard let localTurn = core.sendMessage(threadId: 1, text: "ローカル確認"),
                localTurn > 0,
                let afterLocal = core.snapshot(),
                afterLocal.activeThread?.messages.count == 2
            else {
                return false
            }

            let mockAcpScript = """
                import json, sys
                for raw in sys.stdin:
                    msg = json.loads(raw)
                    m = msg.get("method")
                    if m == "initialize":
                        print(json.dumps({"jsonrpc":"2.0","id":msg["id"],"result":{"protocolVersion":1}}), flush=True)
                    elif m == "session/new":
                        print(json.dumps({"jsonrpc":"2.0","id":msg["id"],"result":{"sessionId":"s1","configOptions":[{"id":"model","category":"model","currentValue":"acp/v1","options":[{"value":"acp/v1"},{"value":"acp/v2"}]}]}}), flush=True)
                    elif m == "session/prompt":
                        pid = msg["id"]
                        print(json.dumps({"jsonrpc":"2.0","id":77,"method":"session/request_permission","params":{"toolCall":{"kind":"shell","title":"echo ok"},"options":[{"optionId":"allow","kind":"allow_once"}]}}), flush=True)
                        _ = sys.stdin.readline()
                        print(json.dumps({"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"ACP live ok"}}}}), flush=True)
                        print(json.dumps({"jsonrpc":"2.0","id":pid,"result":{"stopReason":"end_turn"}}), flush=True)
                """
            guard
                core.setProviderCommandOverride(
                    provider: "opencode_acp",
                    executable: "/usr/bin/python3",
                    arguments: ["-u", "-c", mockAcpScript]
                ),
                let thread2 = core.createThread(
                    projectId: 1,
                    title: "ACP テスト",
                    provider: "opencode_acp",
                    model: "default",
                    effort: "high"
                ),
                core.sendMessage(threadId: thread2, text: "テスト実行") != nil
            else {
                return false
            }

            var approved = false
            var completed = false
            for _ in 0..<150 {
                _ = core.pollProviders()
                if let snap = core.snapshot(),
                    let active = snap.threads.first(where: { $0.id == thread2 })
                {
                    if !approved && active.pendingApproval.active {
                        approved = core.resolveApproval(threadId: thread2, approve: true)
                    }
                    if active.status == "idle" && active.messages.count == 2
                        && active.availableModels.count == 2
                    {
                        completed = true
                        break
                    }
                }
                usleep(5000)
            }
            guard approved, completed, !core.providerWakeupFDs().isEmpty else {
                return false
            }
        }

        guard
            let reloaded = KasugaiCore(
                projectName: "Kasugai",
                projectPath: "/tmp",
                storePath: storeURL.path
            ),
            let restored = reloaded.snapshot(),
            restored.threads.count == 2,
            restored.threads[1].messages.count == 2
        else {
            return false
        }
        return true
    }
}
