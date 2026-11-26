import Darwin
import Foundation

struct KasugaiModelOption: Equatable {
    let id: String
    let label: String
}

final class ProviderModelCatalog {
    static let shared = ProviderModelCatalog()

    private let lock = NSLock()
    private var liveByProvider: [String: [KasugaiModelOption]] = [:]
    private var hasStartedRefresh = false

    func options(for providerId: String, discovered: [String] = []) -> [KasugaiModelOption] {
        lock.lock()
        let live = liveByProvider[providerId] ?? []
        lock.unlock()

        var merged: [KasugaiModelOption] = []
        var seen: Set<String> = []

        for raw in discovered {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && trimmed != "default" && seen.insert(trimmed).inserted {
                merged.append(KasugaiModelOption(id: trimmed, label: formatModelLabel(trimmed)))
            }
        }
        for item in live where item.id != "default" && seen.insert(item.id).inserted {
            merged.append(item)
        }
        for item in Self.curatedPresets(for: providerId)
        where item.id != "default" && seen.insert(item.id).inserted {
            merged.append(item)
        }
        return merged
    }

    func resolveConcreteModelId(providerId: String, model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if providerId == "claude_code" {
            switch trimmed {
            case "", "default", "opus":
                return "claude-opus-5-5"
            case "sonnet":
                return "claude-sonnet-5-5"
            case "fable":
                return "claude-fable-5-2"
            case "haiku":
                return "claude-haiku-5-5"
            default:
                return trimmed
            }
        }
        if trimmed.isEmpty || trimmed == "default" {
            return defaultModelId(for: providerId)
        }
        return trimmed
    }

    func effortOptions(for providerId: String) -> [(id: String, label: String)] {
        if providerId == "claude_code" {
            return [
                ("low", "Low"),
                ("medium", "Medium"),
                ("high", "High"),
                ("xhigh", "Max"),
            ]
        }
        return [
            ("low", "Low"),
            ("medium", "Medium"),
            ("high", "High"),
            ("xhigh", "XHigh"),
        ]
    }

    func effortLabel(for providerId: String, effort: String) -> String {
        effortOptions(for: providerId).first(where: { $0.id == effort })?.label ?? "Medium"
    }

    func modelEmbedsEffort(_ modelId: String) -> Bool {
        let lower = modelId.lowercased()
        return lower.hasSuffix("-low")
            || lower.hasSuffix("-medium")
            || lower.hasSuffix("-high")
            || lower.hasSuffix("-xhigh")
            || lower.hasSuffix("-max")
            || lower.contains("(low)")
            || lower.contains("(medium)")
            || lower.contains("(high)")
            || lower.contains("(xhigh)")
            || lower.contains("(max)")
    }

    func pillTitle(
        providerId: String,
        providerName: String,
        model: String,
        effort: String? = nil
    ) -> String {
        let shortProvider: String
        switch providerId {
        case "claude_code":
            shortProvider = "Claude"
        case "codex":
            shortProvider = "Codex"
        case "opencode_acp":
            shortProvider = "OpenCode"
        case "antigravity_acp":
            shortProvider = "Antigravity"
        default:
            shortProvider = providerName
        }

        let resolved = resolveConcreteModelId(providerId: providerId, model: model)
        let all = options(for: providerId)
        let modelLabel =
            all.first(where: { $0.id == resolved })?.label ?? formatModelLabel(resolved)
        if let effort, !effort.isEmpty,
            providerId != "local_echo",
            !modelEmbedsEffort(resolved),
            !modelEmbedsEffort(modelLabel)
        {
            let effLabel = effortLabel(for: providerId, effort: effort)
            return "\(shortProvider) · \(modelLabel) · \(effLabel)"
        }
        return "\(shortProvider) · \(modelLabel)"
    }

    func defaultModelId(for providerId: String) -> String {
        let all = options(for: providerId)
        if let first = all.first {
            return first.id
        }
        return "claude-opus-5-5"
    }

    func refreshInBackgroundIfNeeded(suppressTelemetry: Bool, onUpdated: @escaping () -> Void) {
        lock.lock()
        if hasStartedRefresh {
            lock.unlock()
            return
        }
        hasStartedRefresh = true
        lock.unlock()

        let group = DispatchGroup()
        var didUpdate = false
        let updateLock = NSLock()

        func runProbe(_ providerId: String, _ work: @escaping () -> [KasugaiModelOption]) {
            group.enter()
            DispatchQueue.global(qos: .utility).async { [weak self] in
                defer { group.leave() }
                guard let self else {
                    return
                }
                let models = work()
                guard !models.isEmpty else {
                    return
                }
                self.lock.lock()
                self.liveByProvider[providerId] = models
                self.lock.unlock()
                updateLock.lock()
                didUpdate = true
                updateLock.unlock()
                DispatchQueue.main.async {
                    onUpdated()
                }
            }
        }

        runProbe("opencode_acp") {
            Self.probeOpenCodeModels(suppressTelemetry: suppressTelemetry)
        }
        runProbe("claude_code") {
            Self.probeClaudeModels(suppressTelemetry: suppressTelemetry)
        }
        runProbe("codex") {
            Self.probeCodexModels(suppressTelemetry: suppressTelemetry)
        }

        group.notify(queue: .main) {
            if didUpdate {
                onUpdated()
            }
        }
    }

    private func formatModelLabel(_ modelId: String) -> String {
        if modelId.hasPrefix("opencode-go/") {
            let tail = String(modelId.dropFirst("opencode-go/".count))
            if !tail.isEmpty {
                return "\(tail) (go)"
            }
        }
        if let slash = modelId.lastIndex(of: "/") {
            let tail = String(modelId[modelId.index(after: slash)...])
            if !tail.isEmpty {
                return tail
            }
        }
        return modelId
    }

    private static func curatedPresets(for providerId: String) -> [KasugaiModelOption] {
        switch providerId {
        case "claude_code":
            return [
                KasugaiModelOption(id: "claude-opus-5-5", label: "Opus 5.5"),
                KasugaiModelOption(id: "claude-sonnet-5-5", label: "Sonnet 5.5"),
                KasugaiModelOption(id: "claude-fable-5-2", label: "Fable 5.2"),
                KasugaiModelOption(id: "claude-haiku-5-5", label: "Haiku 5.5"),
                KasugaiModelOption(id: "claude-opus-4-6", label: "Opus 4.6"),
                KasugaiModelOption(id: "claude-sonnet-4-6", label: "Sonnet 4.6"),
            ]
        case "codex":
            return [
                KasugaiModelOption(id: "gpt-6.2-sol", label: "GPT-6.2-Sol"),
                KasugaiModelOption(id: "gpt-6.2-astra", label: "GPT-6.2-Astra"),
                KasugaiModelOption(id: "gpt-6.1-terra", label: "GPT-6.1 Terra"),
                KasugaiModelOption(id: "gpt-6.1-sol", label: "GPT-6.1-Sol"),
                KasugaiModelOption(id: "gpt-6-astra", label: "GPT-6-Astra"),
                KasugaiModelOption(id: "gpt-6-sol", label: "GPT-6-Sol"),
                KasugaiModelOption(id: "gpt-6-luna", label: "GPT-6-Luna"),
            ]
        case "opencode_acp":
            return [
                KasugaiModelOption(id: "opencode-go/glm-5.3", label: "glm-5.3 (go)"),
                KasugaiModelOption(id: "opencode-go/glm-5.3-flash", label: "glm-5.3-flash (go)"),
                KasugaiModelOption(id: "opencode-go/gpt-6-luna", label: "gpt-6-luna (go)"),
                KasugaiModelOption(id: "opencode-go/gemini-4-argon", label: "gemini-4-argon (go)"),
                KasugaiModelOption(
                    id: "opencode-go/claude-haiku-5-5", label: "claude-haiku-5-5 (go)"),
                KasugaiModelOption(
                    id: "opencode-go/deepseek-v4-pro", label: "deepseek-v4-pro (go)"),
                KasugaiModelOption(id: "opencode-go/kimi-k3.1-pro", label: "kimi-k3.1-pro (go)"),
                KasugaiModelOption(id: "opencode-go/qwen4-max", label: "qwen4-max (go)"),
                KasugaiModelOption(
                    id: "opencode-go/minimax-m3.1-flash", label: "minimax-m3.1-flash (go)"),
            ]
        case "antigravity_acp":
            return [
                KasugaiModelOption(id: "gemini-4-neon", label: "Gemini 4 Neon"),
                KasugaiModelOption(id: "gemini-4-argon", label: "Gemini 4 Argon"),
                KasugaiModelOption(id: "gemini-4-carbon", label: "Gemini 4 Carbon"),
                KasugaiModelOption(id: "gemini-3.8-flash", label: "Gemini 3.8 Flash"),
            ]
        default:
            return []
        }
    }

    static func enrichedEnvironment(suppressTelemetry: Bool) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let existing = env["PATH"] ?? ""
        var parts = existing.split(separator: ":").map(String.init)
        let extras = [
            "\(home)/.local/bin",
            "\(home)/.opencode/bin",
            "\(home)/.local/share/kugi/bin",
            "\(home)/.cargo/bin",
            "\(home)/.nix-profile/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ]
        for dir in extras where !parts.contains(dir) {
            parts.append(dir)
        }
        env["PATH"] = parts.joined(separator: ":")
        if suppressTelemetry {
            env["CODEX_DISABLE_TELEMETRY"] = "1"
            env["OPENCODE_DISABLE_TELEMETRY"] = "1"
            env["AGY_DISABLE_TELEMETRY"] = "1"
            env["DISABLE_TELEMETRY"] = "1"
            env["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
        }
        return env
    }

    static func findExecutable(_ name: String, env: [String: String]) -> String? {
        let fm = FileManager.default
        let pathStr = env["PATH"] ?? ""
        for dir in pathStr.split(separator: ":") {
            let candidate = "\(dir)/\(name)"
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func probeClaudeModels(suppressTelemetry: Bool) -> [KasugaiModelOption] {
        let env = enrichedEnvironment(suppressTelemetry: suppressTelemetry)
        guard let bin = findExecutable("claude", env: env) else {
            return []
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
            return []
        }
        defer {
            if proc.isRunning {
                proc.terminate()
            }
        }

        let initReq =
            "{\"type\":\"control_request\",\"request_id\":\"init-1\",\"request\":{\"subtype\":\"initialize\"}}\n"
        inPipe.fileHandleForWriting.write(Data(initReq.utf8))
        try? inPipe.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(3.5)
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
                    if let parsed = parseClaudeInitLine(String(line)), !parsed.isEmpty {
                        return parsed
                    }
                }
            }
        }
        return []
    }

    private static func parseClaudeInitLine(_ line: String) -> [KasugaiModelOption]? {
        guard
            let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
            (obj["type"] as? String) == "control_response",
            let outer = obj["response"] as? [String: Any],
            let inner = outer["response"] as? [String: Any],
            let models = inner["models"] as? [[String: Any]]
        else {
            return nil
        }
        var out: [KasugaiModelOption] = []
        var seen: Set<String> = []
        for entry in models {
            guard let rawValue = entry["value"] as? String,
                !rawValue.isEmpty,
                rawValue != "default"
            else {
                continue
            }
            let desc = (entry["description"] as? String) ?? ""
            let versionPrefix =
                desc.components(separatedBy: " · ").first?.trimmingCharacters(
                    in: .whitespacesAndNewlines) ?? ""
            let displayName = (entry["displayName"] as? String) ?? rawValue
            let concreteLabel = versionPrefix.isEmpty ? displayName : versionPrefix
            let concreteId = resolveClaudeModelId(rawValue: rawValue, versionLabel: concreteLabel)
            if seen.insert(concreteId).inserted {
                out.append(KasugaiModelOption(id: concreteId, label: concreteLabel))
            }
        }
        return out
    }

    private static func resolveClaudeModelId(rawValue: String, versionLabel: String) -> String {
        if rawValue.hasPrefix("claude-") {
            return rawValue
        }
        let parts = versionLabel.lowercased().split(separator: " ").map(String.init)
        if parts.count >= 2 {
            let family = parts[0]
            let version = parts[1].replacingOccurrences(of: ".", with: "-")
            if ["opus", "sonnet", "haiku", "fable"].contains(family) {
                return "claude-\(family)-\(version)"
            }
        }
        return rawValue
    }

    private static func probeCodexModels(suppressTelemetry: Bool) -> [KasugaiModelOption] {
        let env = enrichedEnvironment(suppressTelemetry: suppressTelemetry)
        guard let bin = findExecutable("codex", env: env) else {
            return []
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = ["app-server", "--stdio"]
        proc.environment = env
        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            return []
        }
        defer {
            if proc.isRunning {
                proc.terminate()
            }
        }

        let initReq =
            "{\"id\":1,\"method\":\"initialize\",\"params\":{\"clientInfo\":{\"name\":\"kasugai\",\"version\":\"0.1.0\"}}}\n"
        let listReq = "{\"id\":2,\"method\":\"model/list\",\"params\":{}}\n"
        inPipe.fileHandleForWriting.write(Data((initReq + listReq).utf8))
        try? inPipe.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(3.0)
        var collected = Data()
        let readFD = outPipe.fileHandleForReading.fileDescriptor
        var pfd = pollfd(fd: readFD, events: Int16(POLLIN), revents: 0)
        var chunk = [UInt8](repeating: 0, count: 8192)
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
                    if let parsed = parseCodexModelListLine(String(line)), !parsed.isEmpty {
                        return parsed
                    }
                }
            }
        }
        return []
    }

    private static func parseCodexModelListLine(_ line: String) -> [KasugaiModelOption]? {
        guard
            let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
            (obj["id"] as? NSNumber)?.intValue == 2,
            let result = obj["result"] as? [String: Any],
            let data = result["data"] as? [[String: Any]]
        else {
            return nil
        }
        var out: [KasugaiModelOption] = []
        for entry in data.prefix(24) {
            guard let id = entry["id"] as? String, !id.isEmpty else {
                continue
            }
            let name = (entry["displayName"] as? String) ?? id
            out.append(KasugaiModelOption(id: id, label: name))
        }
        return out
    }

    private static func probeOpenCodeModels(suppressTelemetry: Bool) -> [KasugaiModelOption] {
        let env = enrichedEnvironment(suppressTelemetry: suppressTelemetry)
        guard let bin = findExecutable("opencode", env: env) else {
            return []
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = ["models"]
        proc.environment = env
        let outPipe = Pipe()
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
        } catch {
            return []
        }
        let deadline = Date().addingTimeInterval(12.0)
        while proc.isRunning && Date() < deadline {
            usleep(20_000)
        }
        if proc.isRunning {
            proc.terminate()
            return []
        }
        let raw = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: raw, encoding: .utf8) else {
            return []
        }
        var out: [KasugaiModelOption] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.contains(" ") || !trimmed.contains("/") {
                continue
            }
            let shortName = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
            let label = trimmed.hasPrefix("opencode-go/") ? "\(shortName) (go)" : shortName
            out.append(KasugaiModelOption(id: trimmed, label: label))
        }
        return out
    }
}
