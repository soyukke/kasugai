import Darwin
import Foundation

struct GitWorktreeEntry: Equatable {
    let path: String
    let repository: String
    let branch: String
    let isMain: Bool
}

struct GitDiffFileEntry: Codable, Equatable {
    let path: String
    let status: String
    let insertions: Int64
    let deletions: Int64
    let patch: String
}

struct GitDiffReport: Codable {
    let directory: String
    let branch: String
    let isGitRepo: Bool
    let filesChanged: Int64
    let insertions: Int64
    let deletions: Int64
    let statusLines: [String]
    let unifiedDiff: String
    let files: [GitDiffFileEntry]

    enum CodingKeys: String, CodingKey {
        case directory
        case branch
        case isGitRepo = "is_git_repo"
        case filesChanged = "files_changed"
        case insertions
        case deletions
        case statusLines = "status_lines"
        case unifiedDiff = "unified_diff"
        case files
    }
}

struct GitWorkspaceError: Error {
    let message: String
}

enum GitWorkspace {
    private static let worktreeFolderSuffix = ".worktrees"

    private struct CommandOutput {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    static func canonicalPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else {
            return URL(fileURLWithPath: path).standardizedFileURL.path
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    static func worktreeLocation(repository: String, branch: String) -> String {
        let root = URL(fileURLWithPath: repository)
        return root.deletingLastPathComponent()
            .appendingPathComponent(
                root.lastPathComponent + worktreeFolderSuffix, isDirectory: true
            )
            .appendingPathComponent(branch.replacingOccurrences(of: "/", with: "-"))
            .path
    }

    static func repositoryRoot(of directory: String) -> String? {
        guard let output = runGit(["worktree", "list", "--porcelain"], in: directory),
            output.status == 0
        else {
            return nil
        }
        let first = output.stdout.components(separatedBy: "\n\n").first ?? ""
        let lines = first.split(separator: "\n").map(String.init)
        guard let line = lines.first, line.hasPrefix("worktree "), !lines.contains("bare") else {
            return nil
        }
        return String(line.dropFirst("worktree ".count))
    }

    static func currentBranch(in directory: String) -> String {
        guard let output = runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: directory),
            output.status == 0
        else {
            return ""
        }
        return output.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isValidBranchName(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("-"),
            let output = runGit(["check-ref-format", "--branch", name], in: "/")
        else {
            return false
        }
        return output.status == 0
    }

    static func createWorktree(
        in directory: String,
        branch: String,
        baseRef: String = "HEAD"
    ) -> Result<GitWorktreeEntry, GitWorkspaceError> {
        guard let repository = repositoryRoot(of: directory) else {
            return .failure(GitWorkspaceError(message: "このフォルダは Git リポジトリではありません。"))
        }
        let trimmed = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidBranchName(trimmed) else {
            return .failure(GitWorkspaceError(message: "ブランチ名「\(trimmed)」は無効です。"))
        }
        let targetPath = worktreeLocation(repository: repository, branch: trimmed)
        guard !FileManager.default.fileExists(atPath: targetPath) else {
            return .failure(GitWorkspaceError(message: "同じ名前の Worktree が既に存在します。"))
        }
        let existing = runGit(
            ["show-ref", "--verify", "--quiet", "refs/heads/\(trimmed)"],
            in: repository
        )
        let ref = baseRef.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = ref.isEmpty ? "HEAD" : ref
        let arguments =
            existing?.status == 0
            ? ["worktree", "add", targetPath, trimmed]
            : ["worktree", "add", "-b", trimmed, targetPath, base]
        guard let output = runGit(arguments, in: directory) else {
            return .failure(GitWorkspaceError(message: "git コマンドを実行できませんでした。"))
        }
        guard output.status == 0 else {
            let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(
                GitWorkspaceError(message: detail.isEmpty ? "Worktree を作成できませんでした。" : detail)
            )
        }
        return .success(
            GitWorktreeEntry(
                path: canonicalPath(targetPath),
                repository: canonicalPath(repository),
                branch: trimmed,
                isMain: false
            )
        )
    }

    static func removeWorktree(
        in directory: String,
        worktreePath: String
    ) -> Result<Void, GitWorkspaceError> {
        guard let repository = repositoryRoot(of: directory) else {
            return .failure(GitWorkspaceError(message: "このフォルダは Git リポジトリではありません。"))
        }
        guard let output = runGit(["worktree", "remove", "--force", worktreePath], in: repository)
        else {
            return .failure(GitWorkspaceError(message: "git コマンドを実行できませんでした。"))
        }
        guard output.status == 0 else {
            let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(
                GitWorkspaceError(message: detail.isEmpty ? "Worktree を削除できませんでした。" : detail)
            )
        }
        return .success(())
    }

    static func computeDiff(in directory: String) -> GitDiffReport {
        guard repositoryRoot(of: directory) != nil else {
            return GitDiffReport(
                directory: directory,
                branch: "",
                isGitRepo: false,
                filesChanged: 0,
                insertions: 0,
                deletions: 0,
                statusLines: [],
                unifiedDiff: "",
                files: []
            )
        }
        let branch = currentBranch(in: directory)
        let statusOut = runGit(["status", "--porcelain", "-uall"], in: directory)?.stdout ?? ""
        let statusLines = statusOut.split(separator: "\n").map(String.init).filter { !$0.isEmpty }

        let unstagedNum = runGit(["diff", "--numstat"], in: directory)?.stdout ?? ""
        let stagedNum = runGit(["diff", "--cached", "--numstat"], in: directory)?.stdout ?? ""
        let perFileStats = accumulatePerFileNumstat([stagedNum, unstagedNum])

        let unstagedDiff = runGit(["diff", "--no-color"], in: directory)?.stdout ?? ""
        let stagedDiff = runGit(["diff", "--cached", "--no-color"], in: directory)?.stdout ?? ""
        var sections: [String] = []
        if !stagedDiff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(stagedDiff)
        }
        if !unstagedDiff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(unstagedDiff)
        }
        let combined = sections.joined(separator: "\n")
        let patchesByPath = splitPatchesByFile(combined)

        var statusByPath: [String: String] = [:]
        var orderedPaths: [String] = []
        var seenPaths: Set<String> = []
        for raw in statusLines {
            guard raw.count >= 4 else {
                continue
            }
            let code = String(raw.prefix(2))
            var relPath = String(raw.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            if let arrowRange = relPath.range(of: " -> ") {
                relPath = String(relPath[arrowRange.upperBound...])
            }
            if relPath.hasPrefix("\"") && relPath.hasSuffix("\"") && relPath.count >= 2 {
                relPath = String(relPath.dropFirst().dropLast())
            }
            guard !relPath.isEmpty else {
                continue
            }
            statusByPath[relPath] = normalizeStatusCode(code)
            if seenPaths.insert(relPath).inserted {
                orderedPaths.append(relPath)
            }
        }
        for path in perFileStats.keys.sorted() where seenPaths.insert(path).inserted {
            orderedPaths.append(path)
        }
        for path in patchesByPath.keys.sorted() where seenPaths.insert(path).inserted {
            orderedPaths.append(path)
        }

        var fileEntries: [GitDiffFileEntry] = []
        var totalInsertions: Int64 = 0
        var totalDeletions: Int64 = 0
        for path in orderedPaths.sorted() {
            let status = statusByPath[path] ?? "M"
            var ins = perFileStats[path]?.insertions ?? 0
            let del = perFileStats[path]?.deletions ?? 0
            var patch = patchesByPath[path] ?? ""
            if patch.isEmpty && status == "?" {
                let synth = synthesizeUntrackedPatch(directory: directory, relativePath: path)
                patch = synth.patch
                if ins == 0 {
                    ins = synth.insertions
                }
            }
            totalInsertions += ins
            totalDeletions += del
            fileEntries.append(
                GitDiffFileEntry(
                    path: path,
                    status: status,
                    insertions: ins,
                    deletions: del,
                    patch: patch
                )
            )
        }

        return GitDiffReport(
            directory: directory,
            branch: branch,
            isGitRepo: true,
            filesChanged: Int64(fileEntries.count),
            insertions: totalInsertions,
            deletions: totalDeletions,
            statusLines: statusLines,
            unifiedDiff: combined,
            files: fileEntries
        )
    }

    private static func normalizeStatusCode(_ raw: String) -> String {
        if raw == "??" {
            return "?"
        }
        if raw.contains("R") {
            return "R"
        }
        if raw.contains("D") {
            return "D"
        }
        if raw.contains("A") {
            return "A"
        }
        return "M"
    }

    private static func accumulatePerFileNumstat(_ outputs: [String])
        -> [String: (insertions: Int64, deletions: Int64)]
    {
        var map: [String: (insertions: Int64, deletions: Int64)] = [:]
        for output in outputs {
            for line in output.split(separator: "\n") {
                let parts = line.split(separator: "\t")
                guard parts.count >= 3 else {
                    continue
                }
                let path = String(parts[2])
                let ins = Int64(parts[0]) ?? 0
                let del = Int64(parts[1]) ?? 0
                let prev = map[path] ?? (0, 0)
                map[path] = (prev.insertions + ins, prev.deletions + del)
            }
        }
        return map
    }

    private static func splitPatchesByFile(_ unified: String) -> [String: String] {
        guard !unified.isEmpty else {
            return [:]
        }
        var result: [String: String] = [:]
        let lines = unified.components(separatedBy: "\n")
        var currentPath: String?
        var buffer: [String] = []

        func flush() {
            guard let path = currentPath, !buffer.isEmpty else {
                return
            }
            let chunk = buffer.joined(separator: "\n")
            if let existing = result[path], !existing.isEmpty {
                result[path] = existing + "\n" + chunk
            } else {
                result[path] = chunk
            }
        }

        for line in lines {
            if line.hasPrefix("diff --git ") {
                flush()
                buffer = [line]
                currentPath = extractDiffHeaderPath(line)
            } else if currentPath != nil {
                buffer.append(line)
            }
        }
        flush()
        return result
    }

    private static func extractDiffHeaderPath(_ headerLine: String) -> String {
        if let range = headerLine.range(of: " b/", options: .backwards) {
            return String(headerLine[range.upperBound...])
        }
        return headerLine
    }

    private static func synthesizeUntrackedPatch(directory: String, relativePath: String)
        -> (patch: String, insertions: Int64)
    {
        let fullURL = URL(fileURLWithPath: directory).appendingPathComponent(relativePath)
        guard let handle = FileHandle(forReadingAtPath: fullURL.path) else {
            return ("", 0)
        }
        defer { try? handle.close() }
        let maxBytes = 24_576
        let data = handle.readData(ofLength: maxBytes)
        if data.contains(0) {
            return ("", 0)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return ("", 0)
        }
        let allLines = text.replacingOccurrences(of: "\r\n", with: "\n").components(
            separatedBy: "\n")
        let trimmedLines = allLines.last == "" ? Array(allLines.dropLast()) : allLines
        let capped = Array(trimmedLines.prefix(250))
        var out: [String] = [
            "diff --git a/\(relativePath) b/\(relativePath)",
            "--- /dev/null",
            "+++ b/\(relativePath)",
            "@@ -0,0 +1,\(capped.count) @@",
        ]
        for line in capped {
            out.append("+\(line)")
        }
        if trimmedLines.count > capped.count {
            out.append(" …（残り \(trimmedLines.count - capped.count) 行を省略）")
        }
        return (out.joined(separator: "\n"), Int64(trimmedLines.count))
    }

    private static func enrichedPath() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let existing = ProcessInfo.processInfo.environment["PATH"] ?? ""
        var parts = existing.split(separator: ":").map(String.init)
        let extras = [
            "\(home)/.local/bin",
            "\(home)/.local/share/kugi/bin",
            "\(home)/.nix-profile/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ]
        for dir in extras where !parts.contains(dir) {
            parts.append(dir)
        }
        return parts.joined(separator: ":")
    }

    static func gitObjectData(
        in directory: String,
        ref: String = "HEAD",
        relativePath: String
    ) -> Data? {
        guard !directory.isEmpty, !relativePath.isEmpty else {
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", directory, "show", "\(ref):\(relativePath)"]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = enrichedPath()
        process.environment = env
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        _ = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !outData.isEmpty else {
            return nil
        }
        return outData
    }

    private static func runGit(_ arguments: [String], in directory: String) -> CommandOutput? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", directory] + arguments
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = enrichedPath()
        process.environment = env
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandOutput(
            status: process.terminationStatus,
            stdout: String(decoding: outData, as: UTF8.self),
            stderr: String(decoding: errData, as: UTF8.self)
        )
    }

    static func runSelfTests() -> Bool {
        let fm = FileManager.default
        let tempRoot = fm.temporaryDirectory.appendingPathComponent(
            "kasugai-git-test-\(UUID().uuidString)",
            isDirectory: true
        )
        let repoDir = tempRoot.appendingPathComponent("demo", isDirectory: true)
        defer { try? fm.removeItem(at: tempRoot) }
        do {
            try fm.createDirectory(at: repoDir, withIntermediateDirectories: true)
            let fileURL = repoDir.appendingPathComponent("hello.txt")
            try Data("line1\n".utf8).write(to: fileURL)
        } catch {
            return false
        }
        guard runGit(["init", "-q"], in: repoDir.path)?.status == 0,
            runGit(["config", "user.email", "test@kasugai.local"], in: repoDir.path)?.status == 0,
            runGit(["config", "user.name", "Kasugai Test"], in: repoDir.path)?.status == 0,
            runGit(["add", "hello.txt"], in: repoDir.path)?.status == 0,
            runGit(["commit", "-q", "-m", "init"], in: repoDir.path)?.status == 0
        else {
            return false
        }
        guard case .success(let entry) = createWorktree(in: repoDir.path, branch: "feat/diff-check")
        else {
            return false
        }
        let wtFile = URL(fileURLWithPath: entry.path).appendingPathComponent("hello.txt")
        let untrackedFile = URL(fileURLWithPath: entry.path).appendingPathComponent("added.txt")
        do {
            try Data("line1\nline2\n".utf8).write(to: wtFile)
            try Data("new1\nnew2\n".utf8).write(to: untrackedFile)
        } catch {
            return false
        }
        let report = computeDiff(in: entry.path)
        guard report.isGitRepo,
            report.branch == "feat/diff-check",
            report.filesChanged == 2,
            report.insertions == 3,
            report.unifiedDiff.contains("+line2"),
            report.files.count == 2,
            let added = report.files.first(where: { $0.path == "added.txt" }),
            added.status == "?",
            added.insertions == 2,
            added.patch.contains("+new1")
        else {
            return false
        }
        guard case .success = removeWorktree(in: repoDir.path, worktreePath: entry.path) else {
            return false
        }
        return true
    }
}
