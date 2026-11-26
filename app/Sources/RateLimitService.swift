import Darwin
import Foundation

struct KasugaiRateLimitWindow: Equatable {
    let id: String
    let label: String
    let usedPercent: Double
    let resetsAt: Date?
    let windowDurationMins: Int?

    var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }

    func paceRemainingPercent(now: Date = Date()) -> Double? {
        guard let resetsAt, let mins = windowDurationMins, mins > 0 else {
            return nil
        }
        let durationSeconds = Double(mins) * 60.0
        let remainingSeconds = resetsAt.timeIntervalSince(now)
        if remainingSeconds <= 0 {
            return 0
        }
        if remainingSeconds >= durationSeconds {
            return 100
        }
        return max(0, min(100, (remainingSeconds / durationSeconds) * 100.0))
    }
}

struct KasugaiProviderRateLimit: Equatable {
    enum Status: Equatable {
        case loading
        case available
        case notInstalled
        case unavailable(String)
    }

    let providerId: String
    let displayName: String
    let plan: String?
    let windows: [KasugaiRateLimitWindow]
    let resetCreditsAvailable: Int?
    let status: Status
    let checkedAt: Date

    var tightestRemainingPercent: Double? {
        guard status == .available, !windows.isEmpty else {
            return nil
        }
        return windows.map(\.remainingPercent).min()
    }
}

struct KasugaiOpencodeWindowStats: Equatable {
    let sessions: Int
    let prompts: Int
    let totalTokens: Int64
    let cost: Double
}

struct KasugaiOpencodeUsage: Equatable {
    let today: KasugaiOpencodeWindowStats?
    let sevenDay: KasugaiOpencodeWindowStats?
}

struct KasugaiRateLimitSnapshot: Equatable {
    let claude: KasugaiProviderRateLimit
    let codex: KasugaiProviderRateLimit
    let antigravity: KasugaiProviderRateLimit
    let opencodeInstalled: Bool
    let opencodeUsage: KasugaiOpencodeUsage?
    let isRefreshing: Bool
    let lastUpdated: Date?

    init(
        claude: KasugaiProviderRateLimit,
        codex: KasugaiProviderRateLimit,
        antigravity: KasugaiProviderRateLimit,
        opencodeInstalled: Bool,
        opencodeUsage: KasugaiOpencodeUsage? = nil,
        isRefreshing: Bool,
        lastUpdated: Date?
    ) {
        self.claude = claude
        self.codex = codex
        self.antigravity = antigravity
        self.opencodeInstalled = opencodeInstalled
        self.opencodeUsage = opencodeUsage
        self.isRefreshing = isRefreshing
        self.lastUpdated = lastUpdated
    }

    static func initial(now: Date = Date()) -> KasugaiRateLimitSnapshot {
        KasugaiRateLimitSnapshot(
            claude: KasugaiProviderRateLimit(
                providerId: "claude_code",
                displayName: "Claude Code",
                plan: nil,
                windows: [],
                resetCreditsAvailable: nil,
                status: .loading,
                checkedAt: now
            ),
            codex: KasugaiProviderRateLimit(
                providerId: "codex",
                displayName: "Codex",
                plan: nil,
                windows: [],
                resetCreditsAvailable: nil,
                status: .loading,
                checkedAt: now
            ),
            antigravity: KasugaiProviderRateLimit(
                providerId: "antigravity_acp",
                displayName: "Antigravity（Gemini）",
                plan: nil,
                windows: [],
                resetCreditsAvailable: nil,
                status: .loading,
                checkedAt: now
            ),
            opencodeInstalled: false,
            isRefreshing: false,
            lastUpdated: nil
        )
    }
}

final class RateLimitService {
    static let shared = RateLimitService()

    private let lock = NSLock()
    private var currentSnapshot: KasugaiRateLimitSnapshot = .initial()
    private var refreshInFlight = false
    private var lastFetchCompletedAt: Date?
    private var observers: [UUID: (KasugaiRateLimitSnapshot) -> Void] = [:]

    var snapshot: KasugaiRateLimitSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return currentSnapshot
    }

    @discardableResult
    func addObserver(_ handler: @escaping (KasugaiRateLimitSnapshot) -> Void) -> UUID {
        let token = UUID()
        lock.lock()
        observers[token] = handler
        let snap = currentSnapshot
        lock.unlock()
        DispatchQueue.main.async {
            handler(snap)
        }
        return token
    }

    func removeObserver(_ token: UUID) {
        lock.lock()
        observers.removeValue(forKey: token)
        lock.unlock()
    }

    func refreshIfNeeded(
        suppressTelemetry: Bool,
        force: Bool = false,
        minIntervalSeconds: TimeInterval = 30
    ) {
        if ProcessInfo.processInfo.environment["KASUGAI_SELF_TEST"] == "1" {
            return
        }
        lock.lock()
        if refreshInFlight {
            lock.unlock()
            return
        }
        if !force, let last = lastFetchCompletedAt,
            Date().timeIntervalSince(last) < minIntervalSeconds
        {
            lock.unlock()
            return
        }
        refreshInFlight = true
        currentSnapshot = KasugaiRateLimitSnapshot(
            claude: currentSnapshot.claude,
            codex: currentSnapshot.codex,
            antigravity: currentSnapshot.antigravity,
            opencodeInstalled: currentSnapshot.opencodeInstalled,
            opencodeUsage: currentSnapshot.opencodeUsage,
            isRefreshing: true,
            lastUpdated: currentSnapshot.lastUpdated
        )
        let startedSnap = currentSnapshot
        lock.unlock()
        notifyObservers(startedSnap)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else {
                return
            }
            let env = ProviderModelCatalog.enrichedEnvironment(suppressTelemetry: suppressTelemetry)
            let opencodeInstalled = ProviderModelCatalog.findExecutable("opencode", env: env) != nil

            self.lock.lock()
            self.currentSnapshot = KasugaiRateLimitSnapshot(
                claude: self.currentSnapshot.claude,
                codex: self.currentSnapshot.codex,
                antigravity: self.currentSnapshot.antigravity,
                opencodeInstalled: opencodeInstalled,
                opencodeUsage: opencodeInstalled ? self.currentSnapshot.opencodeUsage : nil,
                isRefreshing: true,
                lastUpdated: self.currentSnapshot.lastUpdated
            )
            self.lock.unlock()

            let group = DispatchGroup()

            group.enter()
            DispatchQueue.global(qos: .utility).async {
                let result = Self.probeClaude(env: env)
                self.publishPartial(claude: result)
                group.leave()
            }

            group.enter()
            DispatchQueue.global(qos: .utility).async {
                let result = Self.probeCodex(env: env)
                self.publishPartial(codex: result)
                group.leave()
            }

            group.enter()
            DispatchQueue.global(qos: .utility).async {
                let result = Self.probeAntigravity(env: env)
                self.publishPartial(antigravity: result)
                group.leave()
            }

            if opencodeInstalled {
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    let result = Self.probeOpencodeUsage(env: env)
                    self.publishPartial(opencodeUsage: result)
                    group.leave()
                }
            }

            group.wait()
            let finishedAt = Date()
            self.lock.lock()
            self.refreshInFlight = false
            self.lastFetchCompletedAt = finishedAt
            let next = KasugaiRateLimitSnapshot(
                claude: self.currentSnapshot.claude,
                codex: self.currentSnapshot.codex,
                antigravity: self.currentSnapshot.antigravity,
                opencodeInstalled: opencodeInstalled,
                opencodeUsage: self.currentSnapshot.opencodeUsage,
                isRefreshing: false,
                lastUpdated: finishedAt
            )
            self.currentSnapshot = next
            self.lock.unlock()
            self.notifyObservers(next)
        }
    }

    private func publishPartial(
        claude: KasugaiProviderRateLimit? = nil,
        codex: KasugaiProviderRateLimit? = nil,
        antigravity: KasugaiProviderRateLimit? = nil,
        opencodeUsage: KasugaiOpencodeUsage? = nil
    ) {
        let now = Date()
        lock.lock()
        let next = KasugaiRateLimitSnapshot(
            claude: claude ?? currentSnapshot.claude,
            codex: codex ?? currentSnapshot.codex,
            antigravity: antigravity ?? currentSnapshot.antigravity,
            opencodeInstalled: currentSnapshot.opencodeInstalled,
            opencodeUsage: opencodeUsage ?? currentSnapshot.opencodeUsage,
            isRefreshing: refreshInFlight,
            lastUpdated: now
        )
        currentSnapshot = next
        lock.unlock()
        notifyObservers(next)
    }

    private func notifyObservers(_ snapshot: KasugaiRateLimitSnapshot) {
        lock.lock()
        let handlers = Array(observers.values)
        lock.unlock()
        DispatchQueue.main.async {
            for handler in handlers {
                handler(snapshot)
            }
        }
    }

    private static func probeClaude(env: [String: String]) -> KasugaiProviderRateLimit {
        let now = Date()
        guard let bin = ProviderModelCatalog.findExecutable("claude", env: env) else {
            return KasugaiProviderRateLimit(
                providerId: "claude_code",
                displayName: "Claude Code",
                plan: nil,
                windows: [],
                resetCreditsAvailable: nil,
                status: .notInstalled,
                checkedAt: now
            )
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = [
            "-p",
            "--verbose",
            "--input-format",
            "stream-json",
            "--output-format",
            "stream-json",
        ]
        proc.environment = env
        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            return KasugaiProviderRateLimit(
                providerId: "claude_code",
                displayName: "Claude Code",
                plan: nil,
                windows: [],
                resetCreditsAvailable: nil,
                status: .unavailable("起動できませんでした"),
                checkedAt: now
            )
        }
        defer {
            try? inPipe.fileHandleForWriting.close()
            if proc.isRunning {
                proc.terminate()
            }
        }

        let req =
            "{\"type\":\"control_request\",\"request_id\":\"usage-1\",\"request\":{\"subtype\":\"get_usage\"}}\n"
        inPipe.fileHandleForWriting.write(Data(req.utf8))

        let deadline = Date().addingTimeInterval(15.0)
        var collected = Data()
        let readFD = outPipe.fileHandleForReading.fileDescriptor
        var pfd = pollfd(fd: readFD, events: Int16(POLLIN), revents: 0)
        var chunk = [UInt8](repeating: 0, count: 16384)
        while Date() < deadline {
            let ready = poll(&pfd, 1, 100)
            if ready <= 0 {
                if !proc.isRunning {
                    break
                }
                continue
            }
            let n = read(readFD, &chunk, chunk.count)
            if n <= 0 {
                break
            }
            collected.append(contentsOf: chunk[0..<n])
            if let text = String(data: collected, encoding: .utf8) {
                for line in text.split(separator: "\n") {
                    if let parsed = parseClaudeUsageLine(String(line), checkedAt: Date()) {
                        return parsed
                    }
                }
            }
        }
        return KasugaiProviderRateLimit(
            providerId: "claude_code",
            displayName: "Claude Code",
            plan: nil,
            windows: [],
            resetCreditsAvailable: nil,
            status: .unavailable("応答がタイムアウトしました"),
            checkedAt: Date()
        )
    }

    private static func probeCodex(env: [String: String]) -> KasugaiProviderRateLimit {
        let now = Date()
        guard let bin = ProviderModelCatalog.findExecutable("codex", env: env) else {
            return KasugaiProviderRateLimit(
                providerId: "codex",
                displayName: "Codex",
                plan: nil,
                windows: [],
                resetCreditsAvailable: nil,
                status: .notInstalled,
                checkedAt: now
            )
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = ["app-server", "--listen", "stdio://"]
        proc.environment = env
        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            return KasugaiProviderRateLimit(
                providerId: "codex",
                displayName: "Codex",
                plan: nil,
                windows: [],
                resetCreditsAvailable: nil,
                status: .unavailable("起動できませんでした"),
                checkedAt: now
            )
        }
        defer {
            try? inPipe.fileHandleForWriting.close()
            if proc.isRunning {
                proc.terminate()
            }
        }

        let payload =
            "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"clientInfo\":{\"name\":\"kasugai\",\"version\":\"0.1.0\"}}}\n"
            + "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}\n"
            + "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"account/rateLimits/read\",\"params\":{}}\n"
        inPipe.fileHandleForWriting.write(Data(payload.utf8))

        let deadline = Date().addingTimeInterval(12.0)
        var collected = Data()
        let readFD = outPipe.fileHandleForReading.fileDescriptor
        var pfd = pollfd(fd: readFD, events: Int16(POLLIN), revents: 0)
        var chunk = [UInt8](repeating: 0, count: 16384)
        while Date() < deadline {
            let ready = poll(&pfd, 1, 100)
            if ready <= 0 {
                if !proc.isRunning {
                    break
                }
                continue
            }
            let n = read(readFD, &chunk, chunk.count)
            if n <= 0 {
                break
            }
            collected.append(contentsOf: chunk[0..<n])
            if let text = String(data: collected, encoding: .utf8) {
                for line in text.split(separator: "\n") {
                    if let parsed = parseCodexRateLimitLine(String(line), checkedAt: Date()) {
                        return parsed
                    }
                }
            }
        }
        return KasugaiProviderRateLimit(
            providerId: "codex",
            displayName: "Codex",
            plan: nil,
            windows: [],
            resetCreditsAvailable: nil,
            status: .unavailable("応答がタイムアウトしました"),
            checkedAt: Date()
        )
    }

    private static func probeAntigravity(env: [String: String]) -> KasugaiProviderRateLimit {
        let now = Date()
        guard let bin = ProviderModelCatalog.findExecutable("agy", env: env) else {
            return KasugaiProviderRateLimit(
                providerId: "antigravity_acp",
                displayName: "Antigravity（Gemini）",
                plan: nil,
                windows: [],
                resetCreditsAvailable: nil,
                status: .notInstalled,
                checkedAt: now
            )
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = [
            "-p",
            "/usage",
            "--output-format",
            "json",
            "--print-timeout",
            "15s",
        ]
        proc.environment = env
        let outPipe = Pipe()
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            return KasugaiProviderRateLimit(
                providerId: "antigravity_acp",
                displayName: "Antigravity（Gemini）",
                plan: nil,
                windows: [],
                resetCreditsAvailable: nil,
                status: .unavailable("起動できませんでした"),
                checkedAt: now
            )
        }
        defer {
            if proc.isRunning {
                proc.terminate()
            }
        }

        let deadline = Date().addingTimeInterval(16.0)
        var collected = Data()
        let readFD = outPipe.fileHandleForReading.fileDescriptor
        var pfd = pollfd(fd: readFD, events: Int16(POLLIN), revents: 0)
        var chunk = [UInt8](repeating: 0, count: 16384)
        while Date() < deadline {
            let ready = poll(&pfd, 1, 100)
            if ready <= 0 {
                if !proc.isRunning {
                    break
                }
                continue
            }
            let n = read(readFD, &chunk, chunk.count)
            if n <= 0 {
                break
            }
            collected.append(contentsOf: chunk[0..<n])
        }
        if let text = String(data: collected, encoding: .utf8),
            let parsed = parseAntigravityUsageOutput(text, checkedAt: Date())
        {
            return parsed
        }
        return KasugaiProviderRateLimit(
            providerId: "antigravity_acp",
            displayName: "Antigravity（Gemini）",
            plan: nil,
            windows: [],
            resetCreditsAvailable: nil,
            status: .unavailable("応答がタイムアウトしました"),
            checkedAt: Date()
        )
    }

    static func parseAntigravityUsageOutput(_ raw: String, checkedAt: Date = Date())
        -> KasugaiProviderRateLimit?
    {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
            let startIdx = trimmed.firstIndex(of: "{"),
            let endIdx = trimmed.lastIndex(of: "}")
        else {
            return nil
        }
        let jsonSlice = String(trimmed[startIdx...endIdx])
        guard
            let obj = try? JSONSerialization.jsonObject(with: Data(jsonSlice.utf8))
                as? [String: Any]
        else {
            return nil
        }
        if let status = obj["status"] as? String, status != "SUCCESS" {
            return KasugaiProviderRateLimit(
                providerId: "antigravity_acp",
                displayName: "Antigravity（Gemini）",
                plan: nil,
                windows: [],
                resetCreditsAvailable: nil,
                status: .unavailable("サインインが必要です"),
                checkedAt: checkedAt
            )
        }
        guard let command = obj["command"] as? [String: Any],
            (command["name"] as? String) == "usage",
            let data = command["data"] as? [String: Any],
            let groups = data["groups"] as? [[String: Any]]
        else {
            return nil
        }

        var windows: [KasugaiRateLimitWindow] = []
        for group in groups {
            let groupName = (group["name"] as? String) ?? ""
            guard let buckets = group["buckets"] as? [[String: Any]] else {
                continue
            }
            let orderedBuckets = buckets.sorted { lhs, rhs in
                let lWin = (lhs["window"] as? String) ?? ""
                let rWin = (rhs["window"] as? String) ?? ""
                let lRank = lWin == "5h" ? 0 : (lWin == "weekly" ? 1 : 2)
                let rRank = rWin == "5h" ? 0 : (rWin == "weekly" ? 1 : 2)
                return lRank < rRank
            }
            for bucket in orderedBuckets {
                guard let id = bucket["id"] as? String,
                    let remainingFraction = numberValue(bucket["remaining_fraction"])
                else {
                    continue
                }
                let windowType = (bucket["window"] as? String) ?? ""
                let durationMins: Int?
                let windowShort: String
                if windowType == "5h" {
                    durationMins = 5 * 60
                    windowShort = "5 時間"
                } else if windowType == "weekly" {
                    durationMins = 7 * 24 * 60
                    windowShort = "週間"
                } else {
                    durationMins = nil
                    windowShort = (bucket["name"] as? String) ?? "枠"
                }

                let familyLabel: String
                if id.hasPrefix("gemini-") || groupName.localizedCaseInsensitiveContains("gemini") {
                    familyLabel = "Gemini"
                } else if id.hasPrefix("3p-")
                    || groupName.localizedCaseInsensitiveContains("claude")
                {
                    familyLabel = "他モデル"
                } else {
                    familyLabel = groupName.isEmpty ? id : groupName
                }

                let clampedFrac = max(0, min(1, remainingFraction))
                let usedPct = clampPercent((1.0 - clampedFrac) * 100.0)
                let desc = (bucket["description"] as? String)?.trimmingCharacters(
                    in: .whitespacesAndNewlines)
                let parsedReset = parseISO8601(bucket["reset_time"] as? String)
                let isUntouchedFull = clampedFrac >= 0.9999 && (desc?.isEmpty ?? true)
                let resetsAt = isUntouchedFull ? nil : parsedReset

                windows.append(
                    KasugaiRateLimitWindow(
                        id: id,
                        label: "\(familyLabel) \(windowShort)",
                        usedPercent: usedPct,
                        resetsAt: resetsAt,
                        windowDurationMins: durationMins
                    )
                )
            }
        }

        if windows.isEmpty {
            return KasugaiProviderRateLimit(
                providerId: "antigravity_acp",
                displayName: "Antigravity（Gemini）",
                plan: nil,
                windows: [],
                resetCreditsAvailable: nil,
                status: .unavailable("表示できる枠がありません"),
                checkedAt: checkedAt
            )
        }

        return KasugaiProviderRateLimit(
            providerId: "antigravity_acp",
            displayName: "Antigravity（Gemini）",
            plan: nil,
            windows: windows,
            resetCreditsAvailable: nil,
            status: .available,
            checkedAt: checkedAt
        )
    }

    static func parseClaudeUsageLine(_ line: String, checkedAt: Date = Date())
        -> KasugaiProviderRateLimit?
    {
        guard
            let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
            (obj["type"] as? String) == "control_response",
            let outer = obj["response"] as? [String: Any],
            (outer["request_id"] as? String) == "usage-1"
        else {
            return nil
        }
        if (outer["subtype"] as? String) != "success" {
            return KasugaiProviderRateLimit(
                providerId: "claude_code",
                displayName: "Claude Code",
                plan: nil,
                windows: [],
                resetCreditsAvailable: nil,
                status: .unavailable("サインインが必要です"),
                checkedAt: checkedAt
            )
        }
        guard let inner = outer["response"] as? [String: Any] else {
            return nil
        }
        let planRaw = inner["subscription_type"] as? String
        let planLabel = formatPlanName(planRaw)
        let available = (inner["rate_limits_available"] as? Bool) ?? false
        guard available, let limits = inner["rate_limits"] as? [String: Any] else {
            return KasugaiProviderRateLimit(
                providerId: "claude_code",
                displayName: "Claude Code",
                plan: planLabel,
                windows: [],
                resetCreditsAvailable: nil,
                status: .unavailable("利用枠情報がありません"),
                checkedAt: checkedAt
            )
        }

        var windows: [KasugaiRateLimitWindow] = []
        if let fiveHour = limits["five_hour"] as? [String: Any],
            let util = numberValue(fiveHour["utilization"])
        {
            windows.append(
                KasugaiRateLimitWindow(
                    id: "five_hour",
                    label: "5 時間",
                    usedPercent: clampPercent(util),
                    resetsAt: parseISO8601(fiveHour["resets_at"] as? String),
                    windowDurationMins: 5 * 60
                )
            )
        }
        if let sevenDay = limits["seven_day"] as? [String: Any],
            let util = numberValue(sevenDay["utilization"])
        {
            windows.append(
                KasugaiRateLimitWindow(
                    id: "seven_day",
                    label: "週間",
                    usedPercent: clampPercent(util),
                    resetsAt: parseISO8601(sevenDay["resets_at"] as? String),
                    windowDurationMins: 7 * 24 * 60
                )
            )
        }
        if let scopedList = limits["model_scoped"] as? [[String: Any]] {
            for entry in scopedList {
                guard let name = entry["display_name"] as? String,
                    !name.isEmpty,
                    let util = numberValue(entry["utilization"])
                else {
                    continue
                }
                windows.append(
                    KasugaiRateLimitWindow(
                        id: "scoped_\(name.lowercased())",
                        label: name,
                        usedPercent: clampPercent(util),
                        resetsAt: parseISO8601(entry["resets_at"] as? String),
                        windowDurationMins: 7 * 24 * 60
                    )
                )
            }
        }
        if let extra = limits["extra_usage"] as? [String: Any],
            (extra["is_enabled"] as? Bool) == true
        {
            var pct: Double?
            if let used = numberValue(extra["used_credits"]),
                let limit = numberValue(extra["monthly_limit"]),
                limit > 0
            {
                pct = (used / limit) * 100.0
            } else if let util = numberValue(extra["utilization"]) {
                pct = util
            }
            if let pct {
                windows.append(
                    KasugaiRateLimitWindow(
                        id: "extra_usage",
                        label: "追加枠",
                        usedPercent: clampPercent(pct),
                        resetsAt: nil,
                        windowDurationMins: nil
                    )
                )
            }
        }

        if windows.isEmpty {
            return KasugaiProviderRateLimit(
                providerId: "claude_code",
                displayName: "Claude Code",
                plan: planLabel,
                windows: [],
                resetCreditsAvailable: nil,
                status: .unavailable("表示できる枠がありません"),
                checkedAt: checkedAt
            )
        }

        return KasugaiProviderRateLimit(
            providerId: "claude_code",
            displayName: "Claude Code",
            plan: planLabel,
            windows: windows,
            resetCreditsAvailable: nil,
            status: .available,
            checkedAt: checkedAt
        )
    }

    static func parseCodexRateLimitLine(_ line: String, checkedAt: Date = Date())
        -> KasugaiProviderRateLimit?
    {
        guard
            let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
            (obj["id"] as? NSNumber)?.intValue == 2
        else {
            return nil
        }
        if obj["error"] != nil {
            return KasugaiProviderRateLimit(
                providerId: "codex",
                displayName: "Codex",
                plan: nil,
                windows: [],
                resetCreditsAvailable: nil,
                status: .unavailable("サインインが必要です"),
                checkedAt: checkedAt
            )
        }
        guard let result = obj["result"] as? [String: Any] else {
            return nil
        }
        let byId = result["rateLimitsByLimitId"] as? [String: Any]
        let snapshot =
            (byId?["codex"] as? [String: Any])
            ?? (result["rateLimits"] as? [String: Any])
        guard let snapshot else {
            return KasugaiProviderRateLimit(
                providerId: "codex",
                displayName: "Codex",
                plan: nil,
                windows: [],
                resetCreditsAvailable: nil,
                status: .unavailable("利用枠情報がありません"),
                checkedAt: checkedAt
            )
        }

        let planRaw = snapshot["planType"] as? String
        let planLabel = formatPlanName(planRaw)
        let isMonthlyPlan = planRaw == "free" || planRaw == "go"
        var windows: [KasugaiRateLimitWindow] = []

        if let primary = snapshot["primary"] as? [String: Any],
            let used = numberValue(primary["usedPercent"])
        {
            let mins =
                (primary["windowDurationMins"] as? NSNumber)?.intValue
                ?? (isMonthlyPlan ? 30 * 24 * 60 : 5 * 60)
            windows.append(
                KasugaiRateLimitWindow(
                    id: "primary",
                    label: windowLabel(forMinutes: mins),
                    usedPercent: clampPercent(used),
                    resetsAt: epochDate(primary["resetsAt"]),
                    windowDurationMins: mins
                )
            )
        }
        if let secondary = snapshot["secondary"] as? [String: Any],
            let used = numberValue(secondary["usedPercent"])
        {
            let mins =
                (secondary["windowDurationMins"] as? NSNumber)?.intValue ?? (7 * 24 * 60)
            windows.append(
                KasugaiRateLimitWindow(
                    id: "secondary",
                    label: windowLabel(forMinutes: mins),
                    usedPercent: clampPercent(used),
                    resetsAt: epochDate(secondary["resetsAt"]),
                    windowDurationMins: mins
                )
            )
        }
        if let individual = snapshot["individualLimit"] as? [String: Any],
            let remaining = numberValue(individual["remainingPercent"])
        {
            windows.append(
                KasugaiRateLimitWindow(
                    id: "individual",
                    label: "月間クレジット",
                    usedPercent: clampPercent(100 - remaining),
                    resetsAt: epochDate(individual["resetsAt"]),
                    windowDurationMins: 30 * 24 * 60
                )
            )
        }

        let resetCredits =
            ((result["rateLimitResetCredits"] as? [String: Any])?["availableCount"] as? NSNumber)?
            .intValue

        if windows.isEmpty {
            return KasugaiProviderRateLimit(
                providerId: "codex",
                displayName: "Codex",
                plan: planLabel,
                windows: [],
                resetCreditsAvailable: resetCredits,
                status: .unavailable("表示できる枠がありません"),
                checkedAt: checkedAt
            )
        }

        return KasugaiProviderRateLimit(
            providerId: "codex",
            displayName: "Codex",
            plan: planLabel,
            windows: windows,
            resetCreditsAvailable: resetCredits,
            status: .available,
            checkedAt: checkedAt
        )
    }

    private static func probeOpencodeUsage(env: [String: String]) -> KasugaiOpencodeUsage? {
        guard let bin = ProviderModelCatalog.findExecutable("opencode", env: env) else {
            return nil
        }
        let today = runOpencodeStats(bin: bin, days: 0, env: env)
        let sevenDay = runOpencodeStats(bin: bin, days: 7, env: env)
        guard today != nil || sevenDay != nil else {
            return nil
        }
        return KasugaiOpencodeUsage(today: today, sevenDay: sevenDay)
    }

    private static func runOpencodeStats(
        bin: String,
        days: Int,
        env: [String: String]
    ) -> KasugaiOpencodeWindowStats? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = ["stats", "--days", String(days), "--cost", "--json"]
        proc.environment = env
        let outPipe = Pipe()
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            return nil
        }
        defer {
            if proc.isRunning {
                proc.terminate()
            }
        }
        let deadline = Date().addingTimeInterval(4.0)
        var collected = Data()
        let readFD = outPipe.fileHandleForReading.fileDescriptor
        var pfd = pollfd(fd: readFD, events: Int16(POLLIN), revents: 0)
        var chunk = [UInt8](repeating: 0, count: 16384)
        while Date() < deadline {
            let ready = poll(&pfd, 1, 100)
            if ready <= 0 {
                if !proc.isRunning {
                    break
                }
                continue
            }
            let n = read(readFD, &chunk, chunk.count)
            if n <= 0 {
                break
            }
            collected.append(contentsOf: chunk[0..<n])
        }
        return parseOpencodeStats(data: collected)
    }

    static func parseOpencodeStats(data: Data) -> KasugaiOpencodeWindowStats? {
        guard !data.isEmpty,
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        let sessions = (obj["sessions"] as? NSNumber)?.intValue ?? 0
        let prompts = (obj["prompts"] as? NSNumber)?.intValue ?? 0
        let cost = numberValue(obj["cost"]) ?? 0
        var totalTokens: Int64 = 0
        if let tokens = obj["tokens"] as? [String: Any] {
            let input = (tokens["input"] as? NSNumber)?.int64Value ?? 0
            let output = (tokens["output"] as? NSNumber)?.int64Value ?? 0
            let reasoning = (tokens["reasoning"] as? NSNumber)?.int64Value ?? 0
            totalTokens = max(0, input) + max(0, output) + max(0, reasoning)
        }
        return KasugaiOpencodeWindowStats(
            sessions: max(0, sessions),
            prompts: max(0, prompts),
            totalTokens: totalTokens,
            cost: max(0, cost)
        )
    }

    static func formatCompactTokens(_ count: Int64) -> String {
        let clamped = max(0, count)
        if clamped >= 1_000_000_000 {
            return String(format: "%.1fB", Double(clamped) / 1_000_000_000.0)
        }
        if clamped >= 1_000_000 {
            return String(format: "%.1fM", Double(clamped) / 1_000_000.0)
        }
        if clamped >= 100_000 {
            return "\(clamped / 1_000)K"
        }
        if clamped >= 1_000 {
            return String(format: "%.1fK", Double(clamped) / 1_000.0)
        }
        return "\(clamped)"
    }

    static func formatResetCountdown(_ date: Date?, now: Date = Date()) -> String {
        guard let date else {
            return "リセット時刻なし"
        }
        let delta = Int(date.timeIntervalSince(now))
        if delta <= 60 {
            return "まもなくリセット"
        }
        let totalMinutes = delta / 60
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let mins = totalMinutes % 60
        if days > 0 {
            return hours > 0 ? "あと \(days) 日 \(hours) 時間" : "あと \(days) 日"
        }
        if hours > 0 {
            return mins > 0 ? "あと \(hours) 時間 \(mins) 分" : "あと \(hours) 時間"
        }
        return "あと \(mins) 分"
    }

    static func formatResetTimestamp(_ date: Date?) -> String {
        guard let date else {
            return ""
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d HH:mm"
        return formatter.string(from: date)
    }

    private static func windowLabel(forMinutes mins: Int) -> String {
        if mins >= 28 * 24 * 60 {
            return "月間"
        }
        if mins >= 6 * 24 * 60 {
            return "週間"
        }
        if mins >= 60 {
            return "\(mins / 60) 時間"
        }
        return "\(mins) 分"
    }

    private static func formatPlanName(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed.prefix(1).uppercased() + trimmed.dropFirst().lowercased()
    }

    private static func clampPercent(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }
        return max(0, min(100, value))
    }

    private static func numberValue(_ raw: Any?) -> Double? {
        if let num = raw as? NSNumber {
            let val = num.doubleValue
            return val.isFinite ? val : nil
        }
        return nil
    }

    private static func epochDate(_ raw: Any?) -> Date? {
        guard let seconds = numberValue(raw), seconds > 0 else {
            return nil
        }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func parseISO8601(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else {
            return nil
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) {
            return date
        }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }

    static func runSelfTests() -> Bool {
        let now = Date(timeIntervalSince1970: 1_795_570_419)
        let claudeSample =
            "{\"type\":\"control_response\",\"response\":{\"subtype\":\"success\",\"request_id\":\"usage-1\",\"response\":{\"subscription_type\":\"max\",\"rate_limits_available\":true,\"rate_limits\":{\"five_hour\":null,\"seven_day\":{\"utilization\":59,\"resets_at\":\"2026-11-29T03:59:59.960675+00:00\"},\"model_scoped\":[{\"display_name\":\"Fable\",\"utilization\":16,\"resets_at\":\"2026-11-29T03:59:59.960908+00:00\"}]}}}}"
        guard let claude = parseClaudeUsageLine(claudeSample, checkedAt: now),
            claude.status == .available,
            claude.plan == "Max",
            claude.windows.count == 2,
            claude.windows[0].label == "週間",
            Int(claude.windows[0].remainingPercent) == 41,
            claude.windows[0].resetsAt != nil,
            claude.windows[1].label == "Fable",
            Int(claude.windows[1].remainingPercent) == 84,
            Int(claude.tightestRemainingPercent ?? -1) == 41
        else {
            return false
        }

        let codexSample =
            "{\"id\":2,\"result\":{\"rateLimits\":{\"limitId\":\"codex\",\"planType\":\"plus\",\"primary\":{\"usedPercent\":8,\"windowDurationMins\":300,\"resetsAt\":1795575419},\"secondary\":{\"usedPercent\":13,\"windowDurationMins\":10080,\"resetsAt\":1796000580}},\"rateLimitResetCredits\":{\"availableCount\":3}}}"
        guard let codex = parseCodexRateLimitLine(codexSample, checkedAt: now),
            codex.status == .available,
            codex.plan == "Plus",
            codex.windows.count == 2,
            codex.windows[0].label == "5 時間",
            Int(codex.windows[0].remainingPercent) == 92,
            codex.windows[1].label == "週間",
            Int(codex.windows[1].remainingPercent) == 87,
            codex.resetCreditsAvailable == 3,
            Int(codex.tightestRemainingPercent ?? -1) == 87
        else {
            return false
        }

        let countdown1 = formatResetCountdown(now.addingTimeInterval(5000), now: now)
        let countdown2 = formatResetCountdown(now.addingTimeInterval(3 * 86400 + 7200), now: now)
        let agySample =
            "{\"conversation_id\":\"\",\"status\":\"SUCCESS\",\"command\":{\"name\":\"usage\",\"data\":{\"groups\":[{\"name\":\"Gemini Models\",\"buckets\":[{\"id\":\"gemini-weekly\",\"window\":\"weekly\",\"remaining_fraction\":0.70,\"description\":\"used\",\"reset_time\":\"2026-11-30T20:11:16Z\"},{\"id\":\"gemini-5h\",\"window\":\"5h\",\"remaining_fraction\":0.94,\"description\":\"used\",\"reset_time\":\"2026-11-25T07:11:16Z\"}]},{\"name\":\"Claude and GPT models\",\"buckets\":[{\"id\":\"3p-weekly\",\"window\":\"weekly\",\"remaining_fraction\":1,\"reset_time\":\"2026-12-02T03:20:10Z\"},{\"id\":\"3p-5h\",\"window\":\"5h\",\"remaining_fraction\":1,\"reset_time\":\"2026-11-25T08:20:10Z\"}]}]}}}"
        let opencodeSample =
            "{\"sessions\":7,\"prompts\":7,\"tokens\":{\"input\":1252493,\"output\":187151,\"reasoning\":437832,\"cache\":{\"read\":128941440,\"write\":11636}},\"cost\":0}"
        guard countdown1 == "あと 1 時間 23 分",
            countdown2 == "あと 3 日 2 時間",
            let agy = parseAntigravityUsageOutput(agySample, checkedAt: now),
            agy.status == .available,
            agy.windows.count == 4,
            agy.windows[0].label == "Gemini 5 時間",
            Int(round(agy.windows[0].remainingPercent)) == 94,
            agy.windows[0].resetsAt != nil,
            agy.windows[1].label == "Gemini 週間",
            Int(round(agy.windows[1].remainingPercent)) == 70,
            agy.windows[2].label == "他モデル 5 時間",
            agy.windows[2].resetsAt == nil,
            Int(round(agy.tightestRemainingPercent ?? -1)) == 70,
            let opencode = parseOpencodeStats(data: Data(opencodeSample.utf8)),
            opencode.sessions == 7,
            opencode.prompts == 7,
            opencode.totalTokens == 1_877_476,
            opencode.cost == 0,
            formatCompactTokens(850) == "850",
            formatCompactTokens(12_340) == "12.3K",
            formatCompactTokens(420_000) == "420K",
            formatCompactTokens(1_877_476) == "1.9M"
        else {
            return false
        }
        return true
    }
}
