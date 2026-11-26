import Darwin
import Foundation

enum FactoryTone: String, Codable, Equatable {
    case neutral
    case accent
    case success
    case warning
    case danger
}

enum FactoryRunStatus: String, Codable, Equatable {
    case draft
    case running
    case previewReady = "preview_ready"
    case published
    case discarded
    case failed

    var label: String {
        switch self {
        case .draft:
            return "入力待ち"
        case .running:
            return "製造中…"
        case .previewReady:
            return "確認待ち"
        case .published:
            return "公開済み"
        case .discarded:
            return "破棄済み"
        case .failed:
            return "失敗"
        }
    }
}

struct FactoryStageBlueprint: Codable, Equatable {
    var id: String
    var title: String
    var subtitle: String
    var symbol: String
    var subBlueprintId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case symbol
        case subBlueprintId = "sub_blueprint_id"
    }
}

struct FactoryLoopBlueprint: Codable, Equatable {
    var id: String
    var fromStageId: String
    var toStageId: String
    var label: String
    var activeLabel: String

    enum CodingKeys: String, CodingKey {
        case id
        case fromStageId = "from_stage_id"
        case toStageId = "to_stage_id"
        case label
        case activeLabel = "active_label"
    }
}

struct FactoryBlueprint: Codable, Equatable {
    var id: String
    var name: String
    var summary: String
    var runnerScript: String
    var stages: [FactoryStageBlueprint]
    var loops: [FactoryLoopBlueprint]
    var defaultWorkerProvider: String
    var defaultWorkerModel: String
    var defaultCriticProvider: String
    var defaultCriticModel: String
    var maxIterations: Int
    var minReviewScore: Int
    var harnessRules: [String]
    var publishTargetLabel: String
    var placeholderPrompt: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case summary
        case runnerScript = "runner_script"
        case stages
        case loops
        case defaultWorkerProvider = "default_worker_provider"
        case defaultWorkerModel = "default_worker_model"
        case defaultCriticProvider = "default_critic_provider"
        case defaultCriticModel = "default_critic_model"
        case maxIterations = "max_iterations"
        case minReviewScore = "min_review_score"
        case harnessRules = "harness_rules"
        case publishTargetLabel = "publish_target_label"
        case placeholderPrompt = "placeholder_prompt"
    }

    static func builtInDefaults() -> [FactoryBlueprint] {
        [
            FactoryBlueprint(
                id: "meta-factory",
                name: "工場を作る工場（Meta）",
                summary:
                    "短いお題 1 発から専用工場（Blueprint JSON + 0 トークン lint）を自動設計し、実作品 A のポン出し品質を Chrome CDP と隔離レビューで検証します。",
                runnerScript: "",
                stages: [
                    FactoryStageBlueprint(
                        id: "ideate",
                        title: "工場設計",
                        subtitle: "工場コンセプト＆品質契約",
                        symbol: "lightbulb",
                        subBlueprintId: nil
                    ),
                    FactoryStageBlueprint(
                        id: "manufacture",
                        title: "工場＆作品製造",
                        subtitle: "専用 lint ＆ 作品 A を製造",
                        symbol: "wrench.and.screwdriver",
                        subBlueprintId: nil
                    ),
                    FactoryStageBlueprint(
                        id: "verify",
                        title: "自動検査",
                        subtitle: "lint ＆ 実 Chrome CDP",
                        symbol: "checkmark.shield",
                        subBlueprintId: nil
                    ),
                    FactoryStageBlueprint(
                        id: "review",
                        title: "独立レビュー",
                        subtitle: "実スクショ隔離審査",
                        symbol: "eye",
                        subBlueprintId: nil
                    ),
                    FactoryStageBlueprint(
                        id: "preview",
                        title: "採用プレビュー",
                        subtitle: "実作品＆採用ボタン配信",
                        symbol: "play.rectangle",
                        subBlueprintId: nil
                    ),
                ],
                loops: [
                    FactoryLoopBlueprint(
                        id: "verify_retry",
                        fromStageId: "verify",
                        toStageId: "manufacture",
                        label: "不合格時 差し戻し（0 トークン）",
                        activeLabel: "自動検査 差し戻し（0 トークン）"
                    ),
                    FactoryLoopBlueprint(
                        id: "review_retry",
                        fromStageId: "review",
                        toStageId: "manufacture",
                        label: "独立レビュー差し戻し → 工場改善ループ",
                        activeLabel: "実スクショ審査差し戻し → 工場を改善して再製造"
                    ),
                ],
                defaultWorkerProvider: "opencode_acp",
                defaultWorkerModel: "opencode-go/glm-5.3",
                defaultCriticProvider: "opencode_acp",
                defaultCriticModel: "opencode-go/glm-5.3",
                maxIterations: 2,
                minReviewScore: 82,
                harnessRules: [
                    "工場の設計（blueprint.json / spec.json / 0 トークン lint.mjs）と実作品 A の製造を分離する",
                    "生成物は外部 CDN や外部通信を一切使わない単一完結 HTML/CSS/JS にする",
                    "Gate 1（0 トークン）で lint.mjs --self-test・専用 lint・実 Chrome CDP 検証を強制する",
                ],
                publishTargetLabel: "Kasugai 工場一覧",
                placeholderPrompt:
                    "例: 100字のお題から「触って鳴らせる幾何学オルゴール装置」をポン出しで高品質に出荷する専用工場を作って。"
            ),
            FactoryBlueprint(
                id: "factory-optimizer",
                name: "工場改善工場（Optimizer）",
                summary:
                    "指定した工場を固定お題でベンチマーク計測し、品質・1 発合格・稼働時間・トークン量の総合指標が上がる仮説パッチだけを KEEP / REVERT で自動進化させます。",
                runnerScript: "",
                stages: [
                    FactoryStageBlueprint(
                        id: "baseline",
                        title: "v0 計測",
                        subtitle: "現行 v0 を固定お題で計測",
                        symbol: "flag",
                        subBlueprintId: nil
                    ),
                    FactoryStageBlueprint(
                        id: "mutate",
                        title: "工場を改変",
                        subtitle: "仮説パッチ生成",
                        symbol: "wand.and.stars",
                        subBlueprintId: nil
                    ),
                    FactoryStageBlueprint(
                        id: "evaluate",
                        title: "再計測",
                        subtitle: "ゼロから再ポン出し＆CDP",
                        symbol: "checkmark.shield",
                        subBlueprintId: nil
                    ),
                    FactoryStageBlueprint(
                        id: "judge",
                        title: "進化判定",
                        subtitle: "KEEP / REVERT 判定",
                        symbol: "chart.line.uptrend.xyaxis",
                        subBlueprintId: nil
                    ),
                    FactoryStageBlueprint(
                        id: "report",
                        title: "比較レポート",
                        subtitle: "世代比較ボード配信",
                        symbol: "play.rectangle",
                        subBlueprintId: nil
                    ),
                ],
                loops: [
                    FactoryLoopBlueprint(
                        id: "evolve_loop",
                        fromStageId: "judge",
                        toStageId: "mutate",
                        label: "KEEP / REVERT 判定 → 次世代の進化ループ",
                        activeLabel: "仮説検証ループ → 次世代の工場パッチ生成"
                    )
                ],
                defaultWorkerProvider: "opencode_acp",
                defaultWorkerModel: "opencode-go/glm-5.3",
                defaultCriticProvider: "opencode_acp",
                defaultCriticModel: "opencode-go/glm-5.3",
                maxIterations: 3,
                minReviewScore: 85,
                harnessRules: [
                    "対象工場を固定お題でゼロからポン出し計測し、総合指標（Fitness）で定量評価する",
                    "過去ベストを上回った仮説だけ KEEP（正本更新）、横ばい・悪化は自動 REVERT する",
                ],
                publishTargetLabel: "対象工場の正本へ反映済み",
                placeholderPrompt:
                    "対象工場: （工場名または ID、省略で直近の工場）\n重視指標: ポン出しの見た目品質を最優先しつつ、稼働時間とトークン量も削る。"
            ),
            FactoryBlueprint(
                id: "web-game",
                name: "ゲーム工場",
                summary:
                    "1 発のお題からゲームを実装し、子工場（音楽工場）で OP/BGM/ED を合成、自動検査と隔離レビューを経て配信します。",
                runnerScript: "",
                stages: [
                    FactoryStageBlueprint(
                        id: "implement",
                        title: "実装",
                        subtitle: "雛形生成 · 実装",
                        symbol: "hammer",
                        subBlueprintId: nil
                    ),
                    FactoryStageBlueprint(
                        id: "bgm_factory",
                        title: "BGM 工場",
                        subtitle: "OP/BGM/ED 合成",
                        symbol: "music.note",
                        subBlueprintId: "mv-music"
                    ),
                    FactoryStageBlueprint(
                        id: "verify",
                        title: "自動検査",
                        subtitle: "ビルド · CDP · Bot",
                        symbol: "checkmark.shield",
                        subBlueprintId: nil
                    ),
                    FactoryStageBlueprint(
                        id: "review",
                        title: "独立レビュー",
                        subtitle: "隔離セッション",
                        symbol: "eye",
                        subBlueprintId: nil
                    ),
                    FactoryStageBlueprint(
                        id: "preview",
                        title: "プレビュー",
                        subtitle: "ローカル配信",
                        symbol: "play.rectangle",
                        subBlueprintId: nil
                    ),
                ],
                loops: [
                    FactoryLoopBlueprint(
                        id: "verify_retry",
                        fromStageId: "verify",
                        toStageId: "implement",
                        label: "不合格時 差し戻し（0 トークン）",
                        activeLabel: "自動検査 差し戻し（0 トークン）"
                    ),
                    FactoryLoopBlueprint(
                        id: "review_retry",
                        fromStageId: "review",
                        toStageId: "implement",
                        label: "独立レビュー差し戻し → 改善ループ",
                        activeLabel: "独立レビュー差し戻し → 再実装"
                    ),
                ],
                defaultWorkerProvider: "opencode_acp",
                defaultWorkerModel: "opencode-go/glm-5.3",
                defaultCriticProvider: "opencode_acp",
                defaultCriticModel: "opencode-go/glm-5.3",
                maxIterations: 3,
                minReviewScore: 80,
                harnessRules: [
                    "操作は 1〜2 ボタンに絞り、1 画面 1 行の短い表現にする",
                    "CDP エラー 0 件・モバイル 390×844 崩れ 0 を必須とする",
                    "自動プレイ Bot で状態変化・得点・ゲームオーバー到達を確認する",
                ],
                publishTargetLabel: "本番公開先",
                placeholderPrompt:
                    "例: 終電を逃した会社員が 1 ボタンで障害物を跳び越える即死アクションゲーム。8bit 調の合成効果音と 1 画面 1 行の短い演出。"
            ),
            FactoryBlueprint(
                id: "mv-music",
                name: "音楽・OP/ED 工場",
                summary:
                    "OP/BGM/ED と効果音を Python 合成し、音響数値 lint と独立レビューを経て納品します。",
                runnerScript: "",
                stages: [
                    FactoryStageBlueprint(
                        id: "compose",
                        title: "作曲・合成",
                        subtitle: "Python 合成 WAV",
                        symbol: "music.note",
                        subBlueprintId: nil
                    ),
                    FactoryStageBlueprint(
                        id: "audio_lint",
                        title: "音響 lint",
                        subtitle: "音圧・単調さ・無音",
                        symbol: "waveform.path.ecg",
                        subBlueprintId: nil
                    ),
                    FactoryStageBlueprint(
                        id: "review",
                        title: "独立レビュー",
                        subtitle: "隔離セッション",
                        symbol: "eye",
                        subBlueprintId: nil
                    ),
                    FactoryStageBlueprint(
                        id: "render",
                        title: "納品",
                        subtitle: "WAV＆manifest",
                        symbol: "checkmark.circle",
                        subBlueprintId: nil
                    ),
                ],
                loops: [
                    FactoryLoopBlueprint(
                        id: "audio_retry",
                        fromStageId: "audio_lint",
                        toStageId: "compose",
                        label: "音響 lint 不合格 → 再合成（0 トークン）",
                        activeLabel: "音響 lint 差し戻し（0 トークン）"
                    ),
                    FactoryLoopBlueprint(
                        id: "review_retry",
                        fromStageId: "review",
                        toStageId: "compose",
                        label: "独立レビュー差し戻し → 改善ループ",
                        activeLabel: "独立レビュー差し戻し → 再作曲"
                    ),
                ],
                defaultWorkerProvider: "opencode_acp",
                defaultWorkerModel: "opencode-go/glm-5.3",
                defaultCriticProvider: "opencode_acp",
                defaultCriticModel: "opencode-go/glm-5.3",
                maxIterations: 3,
                minReviewScore: 80,
                harnessRules: [
                    "無音区間・クリッピング・過度な反復（単調さ）を数値 lint で禁止する",
                    "BPM に対するリズムずれを許容幅以内に収める",
                ],
                publishTargetLabel: "書き出し先",
                placeholderPrompt:
                    "例: 深夜のドライブに合う 30 秒のシンセウェーブ。BPM 118、後半 15 秒でリードメロディが展開する構成。"
            ),
        ]
    }
}

struct FactoryMetricItem: Codable, Equatable {
    var label: String
    var value: String
    var tone: FactoryTone
}

struct FactoryGatePanel: Codable, Equatable {
    var id: String
    var title: String
    var statusText: String
    var tone: FactoryTone
    var metrics: [FactoryMetricItem]
    var summary: String?
    var bullets: [String]
    var imagePath: String?
    var threadId: Int64?
    var threadLabel: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case statusText = "status_text"
        case tone
        case metrics
        case summary
        case bullets
        case imagePath = "image_path"
        case threadId = "thread_id"
        case threadLabel = "thread_label"
    }
}

struct FactoryIterationRecord: Codable, Equatable {
    var index: Int
    var durationSeconds: Double?
    var outcome: String
    var badgeText: String?
    var activeLoopIds: [String]
    var loopNote: String?
    var stuckDetected: Bool
    var panels: [FactoryGatePanel]

    enum CodingKeys: String, CodingKey {
        case index
        case durationSeconds = "duration_seconds"
        case outcome
        case badgeText = "badge_text"
        case activeLoopIds = "active_loop_ids"
        case loopNote = "loop_note"
        case stuckDetected = "stuck_detected"
        case panels
    }
}

struct FactoryRunRecord: Codable, Equatable {
    var id: String
    var parentRunId: String?
    var childRunIds: [String: String]?
    var blueprintId: String
    var blueprintName: String
    var title: String
    var prompt: String
    var slug: String
    var status: FactoryRunStatus
    var currentStageId: String
    var stages: [FactoryStageBlueprint]
    var loops: [FactoryLoopBlueprint]
    var workerProvider: String
    var workerModel: String
    var criticProvider: String
    var criticModel: String
    var maxIterations: Int
    var minReviewScore: Int
    var harnessRules: [String]
    var publishTargetLabel: String
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var startedAtMs: Int64? = nil
    var finishedAtMs: Int64? = nil
    var inputTokens: Int? = nil
    var outputTokens: Int? = nil
    var tokensEstimated: Bool? = nil
    var iterations: [FactoryIterationRecord]
    var localPreviewURL: String?
    var stagingPreviewURL: String?
    var productionURL: String?
    var logs: [String]
    var errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case id
        case parentRunId = "parent_run_id"
        case childRunIds = "child_run_ids"
        case blueprintId = "blueprint_id"
        case blueprintName = "blueprint_name"
        case title
        case prompt
        case slug
        case status
        case currentStageId = "current_stage_id"
        case stages
        case loops
        case workerProvider = "worker_provider"
        case workerModel = "worker_model"
        case criticProvider = "critic_provider"
        case criticModel = "critic_model"
        case maxIterations = "max_iterations"
        case minReviewScore = "min_review_score"
        case harnessRules = "harness_rules"
        case publishTargetLabel = "publish_target_label"
        case createdAtMs = "created_at_ms"
        case updatedAtMs = "updated_at_ms"
        case startedAtMs = "started_at_ms"
        case finishedAtMs = "finished_at_ms"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case tokensEstimated = "tokens_estimated"
        case iterations
        case localPreviewURL = "local_preview_url"
        case stagingPreviewURL = "staging_preview_url"
        case productionURL = "production_url"
        case logs
        case errorMessage = "error_message"
    }

    var totalTokens: Int {
        max(0, (inputTokens ?? 0) + (outputTokens ?? 0))
    }

    func elapsedSeconds(nowMs: Int64 = FactoryRunStore.nowMillis()) -> Double {
        let start = startedAtMs ?? createdAtMs
        let end: Int64
        if let finishedAtMs {
            end = finishedAtMs
        } else if status == .running {
            end = nowMs
        } else {
            end = updatedAtMs
        }
        return max(0, Double(end - start) / 1000.0)
    }

    func formattedElapsed(nowMs: Int64 = FactoryRunStore.nowMillis()) -> String {
        let secs = Int(elapsedSeconds(nowMs: nowMs).rounded(.down))
        let hours = secs / 3600
        let mins = (secs % 3600) / 60
        let rem = secs % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, rem)
        }
        return String(format: "%02d:%02d", mins, rem)
    }

    static func formatTokenCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        }
        if count >= 1_000 {
            return String(format: "%.1fk", Double(count) / 1_000.0)
        }
        return "\(count)"
    }

    var formattedTokens: String {
        let total = totalTokens
        if total == 0 {
            return "0"
        }
        let prefix = (tokensEstimated ?? false) ? "約 " : ""
        return "\(prefix)\(Self.formatTokenCount(total))"
    }

    var tokenBreakdownTooltip: String {
        let inp = inputTokens ?? 0
        let out = outputTokens ?? 0
        let suffix = (tokensEstimated ?? false) ? "（推定）" : ""
        return "入力 \(Self.formatTokenCount(inp)) · 出力 \(Self.formatTokenCount(out))\(suffix)"
    }

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty {
            return "新規製造"
        }
        let firstLine = p.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? p
        if firstLine.count <= 22 {
            return firstLine
        }
        return String(firstLine.prefix(22)) + "…"
    }

    var currentStageTitle: String {
        stages.first(where: { $0.id == currentStageId })?.title ?? currentStageId
    }
}

final class FactoryRunStore {
    var onChanged: (([FactoryRunRecord]) -> Void)?
    var onBlueprintsChanged: (([FactoryBlueprint]) -> Void)?
    var onPreviewReady: ((FactoryRunRecord) -> Void)?

    private let baseDirectory: URL
    private let blueprintsDirectory: URL
    private var blueprints: [FactoryBlueprint] = []
    private var runs: [FactoryRunRecord] = []
    private var runningProcesses: [String: Process] = [:]
    private var previewServers: [String: Process] = [:]
    private var demoWorkItems: [String: [DispatchWorkItem]] = [:]
    private var machineStates: [String: FactoryMachineState] = [:]
    private var pollTimer: Timer?
    private var notifiedPreviewRunIds: Set<String> = []

    var isPollingActive: Bool {
        pollTimer != nil
    }

    init(
        rootDirectory: URL = KasugaiRuntimePaths.dataDirectory().appendingPathComponent(
            "factory",
            isDirectory: true
        )
    ) {
        self.baseDirectory = rootDirectory.appendingPathComponent("runs", isDirectory: true)
        self.blueprintsDirectory = rootDirectory.appendingPathComponent(
            "blueprints", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            at: blueprintsDirectory,
            withIntermediateDirectories: true
        )
        seedDefaultBlueprintsIfNeeded()
        reloadBlueprints(notify: false)
        reloadFromDisk(notify: false)
    }

    deinit {
        detachForUIReload()
    }

    private func currentMachineState(for record: FactoryRunRecord) -> FactoryMachineState {
        if let existing = machineStates[record.id] {
            return existing
        }
        switch record.status {
        case .draft:
            return .draft
        case .running:
            return runningProcesses[record.id] != nil ? .runningAttached : .runningDetached
        case .previewReady:
            return .previewReady
        case .published:
            return .published
        case .discarded:
            return .discarded
        case .failed:
            return .failed
        }
    }

    func detachForUIReload() {
        pollTimer?.invalidate()
        pollTimer = nil
        for (_, items) in demoWorkItems {
            for item in items {
                item.cancel()
            }
        }
        demoWorkItems.removeAll()
        for (id, state) in machineStates {
            let step = FactoryRunMachine.advance(state, .uiReloaded)
            machineStates[id] = step.state
        }
        for (_, proc) in previewServers {
            if proc.isRunning {
                proc.terminate()
            }
        }
        previewServers.removeAll()
    }

    var allRuns: [FactoryRunRecord] {
        runs
    }

    var allBlueprints: [FactoryBlueprint] {
        blueprints
    }

    func blueprint(withId id: String) -> FactoryBlueprint {
        blueprints.first(where: { $0.id == id })
            ?? blueprints.first
            ?? FactoryBlueprint.builtInDefaults()[0]
    }

    func blueprintFileURL(for id: String) -> URL {
        blueprintsDirectory.appendingPathComponent("\(id).json")
    }

    func saveBlueprint(_ bp: FactoryBlueprint) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(bp) {
            try? data.write(to: blueprintFileURL(for: bp.id), options: .atomic)
        }
        reloadBlueprints(notify: true)
    }

    @discardableResult
    func duplicateBlueprint(from id: String, newName: String) -> FactoryBlueprint {
        var copy = blueprint(withId: id)
        let suffix = Int.random(in: 100...999)
        copy.id = "\(copy.id)-\(suffix)"
        copy.name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if copy.name.isEmpty {
            copy.name = "カスタム工場 \(suffix)"
        }
        saveBlueprint(copy)
        return copy
    }

    func run(withId id: String) -> FactoryRunRecord? {
        runs.first { $0.id == id }
    }

    func runDirectory(for id: String) -> URL {
        baseDirectory.appendingPathComponent(id, isDirectory: true)
    }

    func traceFileURL(for id: String) -> URL {
        runDirectory(for: id).appendingPathComponent("trace.json")
    }

    func stopAllProcesses() {
        pollTimer?.invalidate()
        pollTimer = nil
        for (_, items) in demoWorkItems {
            for item in items {
                item.cancel()
            }
        }
        demoWorkItems.removeAll()
        for (_, proc) in runningProcesses {
            if proc.isRunning {
                proc.terminate()
            }
        }
        runningProcesses.removeAll()
        for (_, proc) in previewServers {
            if proc.isRunning {
                proc.terminate()
            }
        }
        previewServers.removeAll()
    }

    @discardableResult
    func createDraft(blueprintId: String? = nil) -> FactoryRunRecord {
        reloadBlueprints(notify: true)
        let bp =
            blueprintId.map { blueprint(withId: $0) }
            ?? blueprints.first
            ?? blueprint(withId: "web-game")
        let now = Self.nowMillis()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let id = "run-\(formatter.string(from: Date()))-\(Int.random(in: 100...999))"
        let record = FactoryRunRecord(
            id: id,
            parentRunId: nil,
            childRunIds: nil,
            blueprintId: bp.id,
            blueprintName: bp.name,
            title: "",
            prompt: "",
            slug: "",
            status: .draft,
            currentStageId: bp.stages.first?.id ?? "implement",
            stages: bp.stages,
            loops: bp.loops,
            workerProvider: bp.defaultWorkerProvider,
            workerModel: bp.defaultWorkerModel,
            criticProvider: bp.defaultCriticProvider,
            criticModel: bp.defaultCriticModel,
            maxIterations: bp.maxIterations,
            minReviewScore: bp.minReviewScore,
            harnessRules: bp.harnessRules,
            publishTargetLabel: bp.publishTargetLabel,
            createdAtMs: now,
            updatedAtMs: now,
            iterations: [],
            localPreviewURL: nil,
            stagingPreviewURL: nil,
            productionURL: nil,
            logs: [],
            errorMessage: nil
        )
        upsert(record)
        return record
    }

    func startRun(
        id: String,
        blueprintId: String,
        prompt: String,
        workerProvider: String,
        workerModel: String,
        criticProvider: String,
        criticModel: String,
        maxIterations: Int,
        minReviewScore: Int,
        harnessRules: [String],
        ctlSocketPath: String,
        factoryProjectId: Int64? = nil,
        demoMode: Bool
    ) {
        guard var record = run(withId: id) else {
            return
        }
        let cleaned = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return
        }
        let startStep = FactoryRunMachine.advance(currentMachineState(for: record), .startRequested)
        guard startStep.outcome == .launchRunnerAndPoll else {
            return
        }
        machineStates[id] = startStep.state
        let bp = blueprint(withId: blueprintId)
        let firstLine =
            cleaned.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? cleaned
        record.blueprintId = bp.id
        record.blueprintName = bp.name
        record.stages = bp.stages
        record.loops = bp.loops
        record.publishTargetLabel = bp.publishTargetLabel
        record.title = firstLine.count <= 20 ? firstLine : String(firstLine.prefix(20)) + "…"
        record.prompt = cleaned
        record.slug = Self.makeSlug(from: id)
        record.workerProvider = workerProvider
        record.workerModel = workerModel
        record.criticProvider = criticProvider
        record.criticModel = criticModel
        record.maxIterations = maxIterations
        record.minReviewScore = minReviewScore
        record.harnessRules = harnessRules
        record.status = .running
        record.currentStageId = bp.stages.first?.id ?? "implement"
        let startedNow = Self.nowMillis()
        record.startedAtMs = startedNow
        record.finishedAtMs = nil
        record.inputTokens = 0
        record.outputTokens = 0
        record.tokensEstimated = true
        record.updatedAtMs = startedNow
        record.iterations = []
        record.localPreviewURL = nil
        record.stagingPreviewURL = nil
        record.productionURL = nil
        record.errorMessage = nil
        record.logs = [
            "[\(Self.clockStamp())] \(bp.name) を開始しました（実装: \(workerModel) / レビュー: \(criticModel)）"
        ]
        notifiedPreviewRunIds.remove(id)
        upsert(record)

        if demoMode {
            runDemoPipeline(for: record)
            return
        }

        let runnerPath =
            ProcessInfo.processInfo.environment["KASUGAI_FACTORY_RUNNER"] ?? bp.runnerScript
        if FileManager.default.isExecutableFile(atPath: runnerPath)
            || FileManager.default.fileExists(atPath: runnerPath)
        {
            launchExternalRunner(
                for: record,
                runnerPath: runnerPath,
                action: "run",
                ctlSocketPath: ctlSocketPath,
                factoryProjectId: factoryProjectId
            )
            ensurePollTimer()
            return
        }

        let missingStep = FactoryRunMachine.advance(
            currentMachineState(for: record), .runnerMissing
        )
        machineStates[id] = missingStep.state
        record.status = .failed
        record.updatedAtMs = Self.nowMillis()
        record.errorMessage =
            "ランナースクリプトが見つかりません（\(runnerPath)）。「デモで表示」で画面を確認するか、ランナーを配置してください。"
        record.logs.append("[\(Self.clockStamp())] ランナー未配置のため停止しました")
        upsert(record)
    }

    func stopRun(id: String) {
        if let items = demoWorkItems.removeValue(forKey: id) {
            for item in items {
                item.cancel()
            }
        }
        if let proc = runningProcesses.removeValue(forKey: id), proc.isRunning {
            proc.terminate()
        }
        guard var record = run(withId: id) else {
            return
        }
        let stopStep = FactoryRunMachine.advance(currentMachineState(for: record), .stopRequested)
        guard stopStep.outcome == .stopAndMarkFailed else {
            return
        }
        machineStates[id] = stopStep.state
        record.status = .failed
        record.errorMessage = "ユーザーにより停止されました。"
        let stopNow = Self.nowMillis()
        record.finishedAtMs = stopNow
        record.updatedAtMs = stopNow
        record.logs.append("[\(Self.clockStamp())] 製造を停止しました")
        upsert(record)
    }

    func publishRun(id: String, ctlSocketPath: String) {
        guard var record = run(withId: id) else {
            return
        }
        let pubStep = FactoryRunMachine.advance(currentMachineState(for: record), .publishRequested)
        guard pubStep.outcome == .launchPublishAndPoll else {
            return
        }
        machineStates[id] = pubStep.state
        let bp = blueprint(withId: record.blueprintId)
        let runnerPath =
            ProcessInfo.processInfo.environment["KASUGAI_FACTORY_RUNNER"] ?? bp.runnerScript
        if FileManager.default.fileExists(atPath: runnerPath)
            && !(record.stagingPreviewURL?.contains("demo-preview") ?? false)
        {
            record.logs.append("[\(Self.clockStamp())] \(record.publishTargetLabel) へ本番配信を開始しました…")
            record.updatedAtMs = Self.nowMillis()
            upsert(record)
            launchExternalRunner(
                for: record,
                runnerPath: runnerPath,
                action: "publish",
                ctlSocketPath: ctlSocketPath
            )
            ensurePollTimer()
            return
        }
        let doneStep = FactoryRunMachine.advance(pubStep.state, .diskReloadPublished)
        machineStates[id] = doneStep.state
        record.status = .published
        record.productionURL = record.localPreviewURL ?? "http://127.0.0.1/\(record.slug)/"
        record.updatedAtMs = Self.nowMillis()
        record.logs.append("[\(Self.clockStamp())] 本番公開が完了しました: \(record.productionURL ?? "")")
        upsert(record)
    }

    func discardRun(id: String) {
        guard var record = run(withId: id) else {
            return
        }
        let discardStep = FactoryRunMachine.advance(
            currentMachineState(for: record), .discardRequested
        )
        guard discardStep.outcome == .stopAndMarkDiscarded else {
            return
        }
        if let items = demoWorkItems.removeValue(forKey: id) {
            for item in items {
                item.cancel()
            }
        }
        if let proc = runningProcesses.removeValue(forKey: id), proc.isRunning {
            proc.terminate()
        }
        if let server = previewServers.removeValue(forKey: id), server.isRunning {
            server.terminate()
        }
        machineStates[id] = discardStep.state
        record.status = .discarded
        record.updatedAtMs = Self.nowMillis()
        record.logs.append("[\(Self.clockStamp())] 成果物を破棄しました（工場設定を微調整して再製造できます）")
        upsert(record)
    }

    func deleteRun(id: String) {
        if let items = demoWorkItems.removeValue(forKey: id) {
            for item in items {
                item.cancel()
            }
        }
        if let proc = runningProcesses.removeValue(forKey: id), proc.isRunning {
            proc.terminate()
        }
        if let server = previewServers.removeValue(forKey: id), server.isRunning {
            server.terminate()
        }
        try? FileManager.default.removeItem(at: runDirectory(for: id))
        runs.removeAll { $0.id == id }
        onChanged?(runs)
    }

    func reloadBlueprints(notify: Bool = true) {
        var loaded: [FactoryBlueprint] = []
        if let entries = try? FileManager.default.contentsOfDirectory(
            at: blueprintsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            let decoder = JSONDecoder()
            for url in entries where url.pathExtension == "json" {
                if let data = try? Data(contentsOf: url),
                    let bp = try? decoder.decode(FactoryBlueprint.self, from: data)
                {
                    loaded.append(bp)
                }
            }
        }
        if loaded.isEmpty {
            loaded = FactoryBlueprint.builtInDefaults()
        }
        loaded.sort { lhs, rhs in
            let order: (String) -> Int = { id in
                switch id {
                case "meta-factory":
                    return 0
                case "web-game":
                    return 1
                case "mv-music":
                    return 2
                default:
                    return 3
                }
            }
            let lo = order(lhs.id)
            let ro = order(rhs.id)
            if lo != ro {
                return lo < ro
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        let changed = loaded != blueprints
        blueprints = loaded
        if notify && changed {
            onBlueprintsChanged?(blueprints)
        }
    }

    func reloadFromDisk(notify: Bool = true) {
        reloadBlueprints(notify: notify)
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: baseDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        else {
            return
        }
        var loaded: [FactoryRunRecord] = []
        let decoder = JSONDecoder()
        for entry in entries {
            let traceURL = entry.appendingPathComponent("trace.json")
            guard let data = try? Data(contentsOf: traceURL),
                let record = try? decoder.decode(FactoryRunRecord.self, from: data)
            else {
                continue
            }
            loaded.append(record)
        }
        loaded.sort { lhs, rhs in
            if lhs.updatedAtMs != rhs.updatedAtMs {
                return lhs.updatedAtMs > rhs.updatedAtMs
            }
            return lhs.id > rhs.id
        }
        let changed = loaded != runs
        runs = loaded
        var shouldPoll = !runningProcesses.isEmpty
        for record in runs {
            let currentState = machineStates[record.id] ?? .draft
            let reloadEvent: FactoryMachineEvent?
            switch record.status {
            case .running:
                reloadEvent = .diskReloadRunning
            case .previewReady:
                reloadEvent = .diskReloadPreviewReady
            case .published:
                reloadEvent = .diskReloadPublished
            case .failed:
                reloadEvent = .diskReloadFailed
            case .draft, .discarded:
                reloadEvent = nil
            }
            if let reloadEvent {
                let step = FactoryRunMachine.advance(currentState, reloadEvent)
                machineStates[record.id] = step.state
                if step.outcome == .resumePoll || step.state == .runningAttached
                    || step.state == .runningDetached || step.state == .publishing
                {
                    shouldPoll = true
                }
            } else {
                machineStates[record.id] = record.status == .discarded ? .discarded : .draft
            }
            if record.status == .previewReady,
                let localURL = record.localPreviewURL,
                !localURL.isEmpty,
                !notifiedPreviewRunIds.contains(record.id)
            {
                notifiedPreviewRunIds.insert(record.id)
                onPreviewReady?(record)
            }
        }
        let loadedIds = Set(runs.map(\.id))
        machineStates = machineStates.filter { loadedIds.contains($0.key) }
        if notify && changed {
            onChanged?(runs)
        }
        if shouldPoll {
            ensurePollTimer()
        } else {
            pollTimer?.invalidate()
            pollTimer = nil
        }
    }

    private func seedDefaultBlueprintsIfNeeded() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let decoder = JSONDecoder()
        for bp in FactoryBlueprint.builtInDefaults() {
            let url = blueprintFileURL(for: bp.id)
            var shouldWrite = !FileManager.default.fileExists(atPath: url.path)
            if !shouldWrite,
                bp.id == "web-game",
                let data = try? Data(contentsOf: url),
                let existing = try? decoder.decode(FactoryBlueprint.self, from: data),
                !existing.stages.contains(where: { $0.subBlueprintId != nil })
            {
                shouldWrite = true
            }
            if !shouldWrite,
                bp.id == "mv-music",
                let data = try? Data(contentsOf: url),
                let existing = try? decoder.decode(FactoryBlueprint.self, from: data),
                existing.runnerScript.contains("mv-factory")
            {
                shouldWrite = true
            }
            if shouldWrite, let data = try? encoder.encode(bp) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func upsert(_ record: FactoryRunRecord) {
        let dir = runDirectory(for: record.id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(record) {
            try? data.write(to: traceFileURL(for: record.id), options: .atomic)
        }
        if let idx = runs.firstIndex(where: { $0.id == record.id }) {
            runs[idx] = record
        } else {
            runs.insert(record, at: 0)
        }
        runs.sort { lhs, rhs in
            if lhs.updatedAtMs != rhs.updatedAtMs {
                return lhs.updatedAtMs > rhs.updatedAtMs
            }
            return lhs.id > rhs.id
        }
        onChanged?(runs)
    }

    private func ensurePollTimer() {
        guard pollTimer == nil else {
            return
        }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.reloadFromDisk(notify: true)
        }
    }

    private func launchExternalRunner(
        for record: FactoryRunRecord,
        runnerPath: String,
        action: String,
        ctlSocketPath: String,
        factoryProjectId: Int64? = nil
    ) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [
            "node",
            runnerPath,
            action,
            "--run-dir",
            runDirectory(for: record.id).path,
            "--trace",
            traceFileURL(for: record.id).path,
            "--blueprint",
            blueprintFileURL(for: record.blueprintId).path,
        ]
        var env = ProcessInfo.processInfo.environment
        if !ctlSocketPath.isEmpty {
            env["KASUGAI_CTL_SOCKET"] = ctlSocketPath
        }
        if let factoryProjectId {
            env["KASUGAI_FACTORY_PROJECT_ID"] = String(factoryProjectId)
        }
        env["KASUGAI_APP_BINARY"] = Bundle.main.executablePath ?? CommandLine.arguments.first ?? ""
        proc.environment = env
        let logURL = runDirectory(for: record.id).appendingPathComponent("runner.log")
        try? FileManager.default.createDirectory(
            at: runDirectory(for: record.id),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        let logHandle = try? FileHandle(forWritingTo: logURL)
        _ = try? logHandle?.seekToEnd()
        proc.standardOutput = logHandle ?? FileHandle.nullDevice
        proc.standardError = logHandle ?? FileHandle.nullDevice
        proc.terminationHandler = { [weak self] finished in
            try? logHandle?.close()
            DispatchQueue.main.async {
                guard let self else {
                    return
                }
                self.runningProcesses.removeValue(forKey: record.id)
                self.reloadFromDisk(notify: true)
                if finished.terminationStatus != 0,
                    var current = self.run(withId: record.id)
                {
                    let failStep = FactoryRunMachine.advance(
                        self.currentMachineState(for: current),
                        .runnerExitedNonZero
                    )
                    if failStep.outcome == .markFailed {
                        self.machineStates[record.id] = failStep.state
                        current.status = .failed
                        current.updatedAtMs = Self.nowMillis()
                        current.errorMessage = "ランナーが終了コード \(finished.terminationStatus) で停止しました。"
                        self.upsert(current)
                    }
                }
            }
        }
        do {
            try proc.run()
            runningProcesses[record.id] = proc
        } catch {
            var failed = record
            failed.status = .failed
            failed.updatedAtMs = Self.nowMillis()
            failed.errorMessage = "ランナーの起動に失敗しました: \(error.localizedDescription)"
            upsert(failed)
        }
    }

    private func runDemoPipeline(for initial: FactoryRunRecord) {
        let runId = initial.id
        let stages = initial.stages
        let s0 = stages.first?.id ?? "implement"
        let s1 =
            stages.first(where: { $0.id == "verify" || $0.id == "audio_lint" })?.id
            ?? (stages.indices.contains(1) ? stages[1].id : "verify")
        let s2 =
            stages.first(where: { $0.id == "review" })?.id
            ?? (stages.indices.contains(2) ? stages[2].id : "review")
        let s3 = stages.last?.id ?? "preview"
        let reviewLoopId = initial.loops.last?.id ?? "review_retry"
        let isMusic = initial.blueprintId == "mv-music"

        func makeGate1Panel(
            passed: Bool,
            buildSec: String,
            secondVal: String,
            thirdVal: String,
            summary: String
        ) -> FactoryGatePanel {
            FactoryGatePanel(
                id: "gate1",
                title: isMusic ? "2. 音響 lint（0 トークン）" : "3. 自動検査（0 トークン）",
                statusText: passed ? "合格" : "不合格",
                tone: passed ? .success : .danger,
                metrics: isMusic
                    ? [
                        FactoryMetricItem(label: "音圧", value: buildSec, tone: .neutral),
                        FactoryMetricItem(label: "単調さ", value: secondVal, tone: .success),
                        FactoryMetricItem(label: "リズムずれ", value: thirdVal, tone: .success),
                    ]
                    : [
                        FactoryMetricItem(label: "ビルド", value: buildSec, tone: .neutral),
                        FactoryMetricItem(label: "WASM", value: secondVal, tone: .neutral),
                        FactoryMetricItem(label: "CDP エラー", value: thirdVal, tone: .success),
                    ],
                summary: summary,
                bullets: [],
                imagePath: nil,
                threadId: nil,
                threadLabel: "1. 実装スレッドを表示"
            )
        }

        var items: [DispatchWorkItem] = []
        func schedule(_ delay: TimeInterval, _ block: @escaping () -> Void) {
            let item = DispatchWorkItem(block: block)
            items.append(item)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        }

        schedule(0.6) { [weak self] in
            guard let self, var rec = self.run(withId: runId), rec.status == .running else {
                return
            }
            rec.currentStageId = s1
            rec.updatedAtMs = Self.nowMillis()
            rec.iterations = [
                FactoryIterationRecord(
                    index: 1,
                    durationSeconds: 14.2,
                    outcome: "running",
                    badgeText: nil,
                    activeLoopIds: [],
                    loopNote: nil,
                    stuckDetected: false,
                    panels: [
                        FactoryGatePanel(
                            id: "gate1",
                            title: isMusic ? "Gate 1 · 音響 lint" : "Gate 1 · 自動検査",
                            statusText: "実行中…",
                            tone: .accent,
                            metrics: [],
                            summary: "自動検査を実行しています…",
                            bullets: [],
                            imagePath: nil,
                            threadId: nil,
                            threadLabel: nil
                        ),
                        FactoryGatePanel(
                            id: "gate2",
                            title: isMusic ? "3. 独立レビュー（隔離）" : "4. 独立レビュー（隔離）",
                            statusText: "待機",
                            tone: .neutral,
                            metrics: [],
                            summary: "Gate 1 通過後に隔離セッションで採点します。",
                            bullets: [],
                            imagePath: nil,
                            threadId: nil,
                            threadLabel: nil
                        ),
                    ]
                )
            ]
            rec.logs.append("[\(Self.clockStamp())] 第 1 周: 実装完了 → Gate 1 を実行中…")
            self.upsert(rec)
        }

        schedule(1.4) { [weak self] in
            guard let self, var rec = self.run(withId: runId), rec.status == .running else {
                return
            }
            rec.currentStageId = s2
            rec.updatedAtMs = Self.nowMillis()
            rec.iterations = [
                FactoryIterationRecord(
                    index: 1,
                    durationSeconds: 19.6,
                    outcome: "running",
                    badgeText: nil,
                    activeLoopIds: [],
                    loopNote: nil,
                    stuckDetected: false,
                    panels: [
                        makeGate1Panel(
                            passed: true,
                            buildSec: isMusic ? "-14.2 LUFS" : "1.4 秒",
                            secondVal: isMusic ? "OK" : "184 KB",
                            thirdVal: "0 件",
                            summary: isMusic
                                ? "波形・クリッピング・リズム検査をすべて通過しました。"
                                : "自動プレイ: 生存 8.2 秒 / ゲームオーバー到達"
                        ),
                        FactoryGatePanel(
                            id: "gate2",
                            title: isMusic ? "3. 独立レビュー（隔離）" : "4. 独立レビュー（隔離）",
                            statusText: "審査中…",
                            tone: .accent,
                            metrics: [],
                            summary: "実装履歴を持たない隔離セッションで採点しています…",
                            bullets: [],
                            imagePath: nil,
                            threadId: nil,
                            threadLabel: nil
                        ),
                    ]
                )
            ]
            rec.logs.append("[\(Self.clockStamp())] 第 1 周: Gate 1 合格 → 独立レビューを実行中…")
            self.upsert(rec)
        }

        schedule(2.4) { [weak self] in
            guard let self, var rec = self.run(withId: runId), rec.status == .running else {
                return
            }
            rec.currentStageId = s0
            rec.updatedAtMs = Self.nowMillis()
            rec.iterations = [
                FactoryIterationRecord(
                    index: 1,
                    durationSeconds: 26.8,
                    outcome: "retry",
                    badgeText: "62 点",
                    activeLoopIds: [reviewLoopId],
                    loopNote: "第 1 周 レビュー差し戻し（62 点）→ 再実装",
                    stuckDetected: false,
                    panels: [
                        makeGate1Panel(
                            passed: true,
                            buildSec: isMusic ? "-14.2 LUFS" : "1.4 秒",
                            secondVal: isMusic ? "OK" : "184 KB",
                            thirdVal: "0 件",
                            summary: isMusic
                                ? "波形・クリッピング・リズム検査をすべて通過しました。"
                                : "自動プレイ: 生存 8.2 秒 / ゲームオーバー到達"
                        ),
                        FactoryGatePanel(
                            id: "gate2",
                            title: isMusic ? "3. 独立レビュー（隔離）" : "4. 独立レビュー（隔離）",
                            statusText: "62 点",
                            tone: .warning,
                            metrics: [],
                            summary: "動作は安定していますが、視認性と手応えが基準（\(rec.minReviewScore) 点）に届きませんでした。",
                            bullets: [
                                "背景と主要要素のコントラストが弱く初見で識別しにくい",
                                "アクション時の演出と効果音のメリハリを追加してください",
                            ],
                            imagePath: nil,
                            threadId: nil,
                            threadLabel: nil
                        ),
                    ]
                ),
                FactoryIterationRecord(
                    index: 2,
                    durationSeconds: nil,
                    outcome: "running",
                    badgeText: nil,
                    activeLoopIds: [],
                    loopNote: nil,
                    stuckDetected: false,
                    panels: [
                        FactoryGatePanel(
                            id: "gate1",
                            title: isMusic ? "Gate 1 · 音響 lint" : "Gate 1 · 自動検査",
                            statusText: "待機",
                            tone: .neutral,
                            metrics: [],
                            summary: "第 2 周の修正完了後に再検査します。",
                            bullets: [],
                            imagePath: nil,
                            threadId: nil,
                            threadLabel: nil
                        ),
                        FactoryGatePanel(
                            id: "gate2",
                            title: isMusic ? "3. 独立レビュー（隔離）" : "4. 独立レビュー（隔離）",
                            statusText: "待機",
                            tone: .neutral,
                            metrics: [],
                            summary: "Gate 1 通過後に隔離セッションで再採点します。",
                            bullets: [],
                            imagePath: nil,
                            threadId: nil,
                            threadLabel: nil
                        ),
                    ]
                ),
            ]
            rec.logs.append("[\(Self.clockStamp())] 第 1 周: 独立レビュー差し戻し（62 点）→ 第 2 周の再実装を開始")
            self.upsert(rec)
        }

        schedule(3.5) { [weak self] in
            guard let self, var rec = self.run(withId: runId), rec.status == .running else {
                return
            }
            rec.currentStageId = s3
            rec.updatedAtMs = Self.nowMillis()
            if rec.iterations.count >= 2 {
                rec.iterations[1] = FactoryIterationRecord(
                    index: 2,
                    durationSeconds: 21.3,
                    outcome: "passed",
                    badgeText: "88 点",
                    activeLoopIds: [],
                    loopNote: nil,
                    stuckDetected: false,
                    panels: [
                        makeGate1Panel(
                            passed: true,
                            buildSec: isMusic ? "-13.9 LUFS" : "1.2 秒",
                            secondVal: isMusic ? "OK" : "192 KB",
                            thirdVal: "0 件",
                            summary: isMusic
                                ? "展開の変化量と音圧バランスが目標範囲に収まりました。"
                                : "自動プレイ: 生存 14.6 秒 / スコア更新＆リトライ確認済み"
                        ),
                        FactoryGatePanel(
                            id: "gate2",
                            title: isMusic ? "3. 独立レビュー（隔離）" : "4. 独立レビュー（隔離）",
                            statusText: "88 点",
                            tone: .success,
                            metrics: [],
                            summary: "操作の手応えとコントラストが改善され、基準（\(rec.minReviewScore) 点）をクリアしました。",
                            bullets: [],
                            imagePath: nil,
                            threadId: nil,
                            threadLabel: nil
                        ),
                    ]
                )
            }
            rec.logs.append("[\(Self.clockStamp())] 第 2 周: Gate 1・Gate 2 合格（88 点）→ プレビューを配信中…")
            self.upsert(rec)
        }

        schedule(4.2) { [weak self] in
            guard let self, var rec = self.run(withId: runId), rec.status == .running else {
                return
            }
            let localURL = self.startDemoPreviewServer(for: rec)
            rec.status = .previewReady
            rec.currentStageId = s3
            rec.localPreviewURL = localURL
            rec.stagingPreviewURL = "https://preview.example.com/\(rec.slug)/"
            rec.updatedAtMs = Self.nowMillis()
            rec.logs.append("[\(Self.clockStamp())] プレビュー配信完了（右ペインで即プレイ可能）")
            self.upsert(rec)
            self.notifiedPreviewRunIds.insert(rec.id)
            self.onPreviewReady?(rec)
            self.demoWorkItems.removeValue(forKey: runId)
        }

        demoWorkItems[runId] = items
    }

    private func startDemoPreviewServer(for record: FactoryRunRecord) -> String? {
        let previewDir = runDirectory(for: record.id).appendingPathComponent(
            "preview",
            isDirectory: true
        )
        try? FileManager.default.createDirectory(at: previewDir, withIntermediateDirectories: true)
        let html = Self.makeDemoGameHTML(title: record.displayTitle, prompt: record.prompt)
        let indexURL = previewDir.appendingPathComponent("index.html")
        try? Data(html.utf8).write(to: indexURL, options: .atomic)

        guard let port = Self.findFreeLoopbackPort() else {
            return nil
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        proc.arguments = [
            "-m",
            "http.server",
            String(port),
            "--bind",
            "127.0.0.1",
            "--directory",
            previewDir.path,
        ]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
            previewServers[record.id] = proc
            return "http://127.0.0.1:\(port)/"
        } catch {
            return nil
        }
    }

    private static func findFreeLoopbackPort() -> UInt16? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            return nil
        }
        defer { close(fd) }
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
        guard bound == 0 else {
            return nil
        }
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let got = withUnsafeMutablePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                getsockname(fd, sockPtr, &len)
            }
        }
        guard got == 0 else {
            return nil
        }
        return UInt16(bigEndian: addr.sin_port)
    }

    private static func makeDemoGameHTML(title: String, prompt: String) -> String {
        let escapedTitle =
            title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let escapedPrompt =
            prompt
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
            <!doctype html>
            <html lang="ja">
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width,initial-scale=1">
            <title>\(escapedTitle)</title>
            <style>
            *{box-sizing:border-box;margin:0;padding:0;user-select:none}
            body{background:#0f172a;color:#f8fafc;font-family:-apple-system,BlinkMacSystemFont,sans-serif;display:flex;flex-direction:column;align-items:center;justify-content:center;min-height:100vh;padding:16px;gap:12px}
            .hud{width:min(520px,100%);display:flex;justify-content:space-between;align-items:center;font-size:13px;color:#94a3b8}
            .badge{background:#1e293b;border:1px solid #334155;border-radius:999px;padding:4px 10px;color:#38bdf8;font-weight:600}
            canvas{width:min(520px,100%);aspect-ratio:16/10;background:#111827;border-radius:14px;border:1px solid #334155;display:block;cursor:pointer;touch-action:manipulation}
            .hint{width:min(520px,100%);font-size:12px;color:#94a3b8;text-align:center}
            </style>
            </head>
            <body>
            <div class="hud">
            <span class="badge">FACTORY PREVIEW</span>
            <span id="score">SCORE 0 / BEST 0</span>
            </div>
            <canvas id="c" width="640" height="400"></canvas>
            <div class="hint">Space / クリックでジャンプ — \(escapedPrompt)</div>
            <script>
            const c=document.getElementById('c'),x=c.getContext('2d'),sc=document.getElementById('score');
            let st='title',y=300,vy=0,obs=[],t=0,score=0,best=0,sp=5.2,ac=null;
            function beep(f,d){try{if(!ac)ac=new(window.AudioContext||window.webkitAudioContext)();const o=ac.createOscillator(),g=ac.createGain();o.type='square';o.frequency.value=f;g.gain.value=0.06;o.connect(g);g.connect(ac.destination);o.start();g.gain.exponentialRampToValueAtTime(0.001,ac.currentTime+d);o.stop(ac.currentTime+d);}catch(e){}}
            function reset(){st='play';y=300;vy=0;obs=[];t=0;score=0;sp=5.4;beep(520,0.08);}
            function act(){if(st!=='play'){reset();return;}if(y>=298){vy=-12.8;beep(680,0.09);}}
            window.addEventListener('keydown',e=>{if(e.code==='Space'||e.code==='ArrowUp'){e.preventDefault();act();}});
            c.addEventListener('pointerdown',e=>{e.preventDefault();act();});
            function loop(){
              t++;
              x.fillStyle='#0b1220';x.fillRect(0,0,640,400);
              x.fillStyle='#1e293b';x.fillRect(0,336,640,64);
              x.fillStyle='#38bdf8';x.fillRect(0,336,640,3);
              if(st==='play'){
                score++;if(score>best)best=score;
                sp=5.4+Math.min(5,score/600);
                vy+=0.68;y+=vy;if(y>300){y=300;vy=0;}
                if(t%Math.max(42,88-Math.floor(score/180))===0){
                  const h=28+Math.floor(Math.random()*36);
                  obs.push({x:660,w:26+Math.floor(Math.random()*16),h});
                }
                for(const o of obs){o.x-=sp;}
                obs=obs.filter(o=>o.x+o.w>-20);
                for(const o of obs){
                  if(120+28>o.x+4&&120<o.x+o.w-4&&y+36>336-o.h+4){
                    st='over';beep(180,0.22);
                  }
                }
              }
              for(const o of obs){
                x.fillStyle='#f97316';x.fillRect(o.x,336-o.h,o.w,o.h);
                x.fillStyle='#fed7aa';x.fillRect(o.x+3,336-o.h+3,o.w-6,5);
              }
              x.fillStyle=st==='over'?'#ef4444':'#38bdf8';
              x.fillRect(120,y,32,36);
              x.fillStyle='#f8fafc';x.fillRect(138,y+8,8,8);
              sc.textContent='SCORE '+Math.floor(score/6)+' / BEST '+Math.floor(best/6);
              if(st==='title'){
                x.fillStyle='rgba(15,23,42,0.72)';x.fillRect(120,120,400,130);
                x.fillStyle='#f8fafc';x.font='700 22px -apple-system,sans-serif';x.textAlign='center';
                x.fillText('\(escapedTitle)',320,175);
                x.fillStyle='#38bdf8';x.font='600 14px -apple-system,sans-serif';
                x.fillText('Space またはクリックでスタート',320,214);
              }else if(st==='over'){
                x.fillStyle='rgba(15,23,42,0.78)';x.fillRect(140,124,360,126);
                x.fillStyle='#f87171';x.font='700 24px -apple-system,sans-serif';x.textAlign='center';
                x.fillText('GAME OVER',320,174);
                x.fillStyle='#e2e8f0';x.font='600 14px -apple-system,sans-serif';
                x.fillText('Space またはクリックでもう一回',320,212);
              }
              requestAnimationFrame(loop);
            }
            loop();
            </script>
            </body>
            </html>
            """
    }

    private static func makeSlug(from id: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        let cleaned = id.lowercased().unicodeScalars.map {
            allowed.contains($0) ? Character($0) : "-"
        }
        return String(cleaned)
    }

    static func nowMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000.0)
    }

    private static func clockStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    static func runSelfTests() -> Bool {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(
            "kasugai-factory-store-test-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? fm.removeItem(at: root) }

        let store1 = FactoryRunStore(rootDirectory: root)
        var draft = store1.createDraft(blueprintId: "web-game")
        draft.title = "テスト工場"
        draft.prompt = "テストプロンプト"
        draft.status = .running
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(draft) else {
            return false
        }
        try? data.write(to: store1.traceFileURL(for: draft.id), options: .atomic)
        store1.detachForUIReload()

        let store2 = FactoryRunStore(rootDirectory: root)
        defer { store2.stopAllProcesses() }
        guard store2.isPollingActive,
            store2.run(withId: draft.id)?.status == .running
        else {
            return false
        }

        var ready = draft
        ready.status = .previewReady
        ready.stagingPreviewURL = "https://demo-preview.local/test"
        if let readyData = try? encoder.encode(ready) {
            try? readyData.write(to: store2.traceFileURL(for: draft.id), options: .atomic)
        }
        store2.reloadFromDisk(notify: false)
        guard !store2.isPollingActive,
            store2.run(withId: draft.id)?.status == .previewReady
        else {
            return false
        }

        store2.publishRun(id: draft.id, ctlSocketPath: "")
        guard store2.run(withId: draft.id)?.status == .published else {
            return false
        }
        store2.discardRun(id: draft.id)
        guard store2.run(withId: draft.id)?.status == .published else {
            return false
        }
        return true
    }
}
