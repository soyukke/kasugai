import Darwin
import Foundation

struct KasugaiTerminalRun: Codable {
    let text: String
    let fg: String
    let bg: String
    let bold: Bool
    let italic: Bool

    enum CodingKeys: String, CodingKey {
        case text = "t"
        case fg
        case bg
        case bold = "b"
        case italic = "i"
    }
}

struct KasugaiTerminalSnapshot: Codable {
    let cols: Int64
    let rows: Int64
    let exited: Bool
    let alternate: Bool
    let cursorVisible: Bool
    let cursorX: Int64
    let cursorY: Int64
    let scrollTotal: Int64
    let scrollOffset: Int64
    let scrollLen: Int64
    let cwd: String
    let background: String
    let foreground: String
    let lines: [[KasugaiTerminalRun]]

    enum CodingKeys: String, CodingKey {
        case cols
        case rows
        case exited
        case alternate
        case cursorVisible = "cursor_visible"
        case cursorX = "cursor_x"
        case cursorY = "cursor_y"
        case scrollTotal = "scroll_total"
        case scrollOffset = "scroll_offset"
        case scrollLen = "scroll_len"
        case cwd
        case background
        case foreground
        case lines
    }

    func plainText() -> String {
        lines.map { row in
            row.map(\.text).joined()
                .replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        }
        .joined(separator: "\n")
    }
}

final class KasugaiTerminal {
    private let handle: UnsafeMutableRawPointer

    init?(cwd: String, cols: UInt16 = 80, rows: UInt16 = 24) {
        let created = cwd.withCString { cwdPtr in
            kasugaiTermCreate(cwdPtr, cols, rows)
        }
        guard let created else {
            return nil
        }
        self.handle = created
    }

    init?(cwd: String, command: String, cols: UInt16 = 80, rows: UInt16 = 24) {
        let created = cwd.withCString { cwdPtr in
            command.withCString { cmdPtr in
                kasugaiTermCreateCommand(cwdPtr, cmdPtr, cols, rows)
            }
        }
        guard let created else {
            return nil
        }
        self.handle = created
    }

    deinit {
        kasugaiTermDestroy(handle)
    }

    var wakeupFD: Int32 {
        kasugaiTermWakeupFd(handle)
    }

    var exited: Bool {
        kasugaiTermExited(handle) != 0
    }

    @discardableResult
    func drain() -> Bool {
        kasugaiTermDrain(handle) != 0
    }

    @discardableResult
    func write(_ string: String) -> Bool {
        write(Data(string.utf8))
    }

    @discardableResult
    func write(_ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else {
                return true
            }
            return kasugaiTermWrite(handle, base, data.count) != 0
        }
    }

    @discardableResult
    func resize(cols: UInt16, rows: UInt16) -> Bool {
        kasugaiTermResize(handle, cols, rows) != 0
    }

    @discardableResult
    func scroll(deltaLines: Int64) -> Bool {
        kasugaiTermScroll(handle, deltaLines) != 0
    }

    func snapshot() -> KasugaiTerminalSnapshot? {
        guard let pointer = kasugaiTermSnapshotJson(handle) else {
            return nil
        }
        defer { kasugaiStringFree(pointer) }
        let json = String(cString: pointer)
        return try? JSONDecoder().decode(KasugaiTerminalSnapshot.self, from: Data(json.utf8))
    }

    static func runSelfTests() -> Bool {
        guard
            let term = KasugaiTerminal(
                cwd: "/tmp",
                command: "printf 'swift-term-ok\\n'",
                cols: 80,
                rows: 12
            ),
            term.wakeupFD >= 0
        else {
            return false
        }
        for _ in 0..<100 {
            _ = term.drain()
            if let snap = term.snapshot(), snap.plainText().contains("swift-term-ok") {
                return term.resize(cols: 100, rows: 20)
            }
            usleep(5000)
        }
        return false
    }
}
