import AppKit
import Foundation

private struct TerminalGridPoint: Equatable, Comparable {
    let row: Int
    let col: Int

    static func < (lhs: TerminalGridPoint, rhs: TerminalGridPoint) -> Bool {
        if lhs.row != rhs.row {
            return lhs.row < rhs.row
        }
        return lhs.col < rhs.col
    }
}

private final class TerminalCanvasView: NSView, NSTextInputClient, NSUserInterfaceValidations {
    var onSendText: ((String) -> Void)?
    var onResizeGrid: ((UInt16, UInt16) -> Void)?
    var onScrollLines: ((Int64) -> Void)?

    private var snapshot: KasugaiTerminalSnapshot?
    private var palette: KasugaiPalette = .kasugai
    private var lastReportedCols: UInt16 = 0
    private var lastReportedRows: UInt16 = 0
    private var selectionAnchor: TerminalGridPoint?
    private var selectionHead: TerminalGridPoint?

    private var markedTextStorage = NSMutableAttributedString()
    private var markedRangeStorage = NSRange(location: NSNotFound, length: 0)
    private var selectedRangeStorage = NSRange(location: 0, length: 0)

    private let baseFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private let boldFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
    private let paddingX: CGFloat = 10
    private let paddingY: CGFloat = 8

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    private var cellSize: NSSize {
        let sample = NSAttributedString(string: "M", attributes: [.font: baseFont]).size()
        return NSSize(
            width: max(6, ceil(sample.width)),
            height: max(14, ceil(sample.height + 2))
        )
    }

    func update(snapshot: KasugaiTerminalSnapshot?) {
        self.snapshot = snapshot
        needsDisplay = true
    }

    func update(palette: KasugaiPalette) {
        self.palette = palette
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    func computeGridSize() -> (cols: UInt16, rows: UInt16) {
        let size = cellSize
        let usableWidth = max(16, bounds.width - paddingX * 2)
        let usableHeight = max(16, bounds.height - paddingY * 2)
        let cols = max(20, min(300, Int(floor(usableWidth / size.width))))
        let rows = max(4, min(120, Int(floor(usableHeight / size.height))))
        return (UInt16(cols), UInt16(rows))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        notifyGridSizeIfChanged()
    }

    override func layout() {
        super.layout()
        notifyGridSizeIfChanged()
    }

    private func notifyGridSizeIfChanged() {
        let grid = computeGridSize()
        if grid.cols != lastReportedCols || grid.rows != lastReportedRows {
            lastReportedCols = grid.cols
            lastReportedRows = grid.rows
            onResizeGrid?(grid.cols, grid.rows)
        }
    }

    private var normalizedSelection: (start: TerminalGridPoint, end: TerminalGridPoint)? {
        guard let anchor = selectionAnchor, let head = selectionHead, anchor != head else {
            return nil
        }
        return anchor < head ? (anchor, head) : (head, anchor)
    }

    private func gridPoint(for windowPoint: NSPoint) -> TerminalGridPoint {
        let local = convert(windowPoint, from: nil)
        let cell = cellSize
        let maxRow = max(0, (snapshot?.lines.count ?? 1) - 1)
        let maxCol = max(0, Int(snapshot?.cols ?? 80))
        let row = max(0, min(maxRow, Int(floor((local.y - paddingY) / cell.height))))
        let col = max(0, min(maxCol, Int(floor((local.x - paddingX) / cell.width))))
        return TerminalGridPoint(row: row, col: col)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let pt = gridPoint(for: event.locationInWindow)
        if event.clickCount >= 3 {
            let maxCol = Int(snapshot?.cols ?? 80)
            selectionAnchor = TerminalGridPoint(row: pt.row, col: 0)
            selectionHead = TerminalGridPoint(row: pt.row, col: maxCol)
            needsDisplay = true
            return
        }
        selectionAnchor = pt
        selectionHead = pt
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let pt = gridPoint(for: event.locationInWindow)
        if selectionAnchor == nil {
            selectionAnchor = pt
        }
        selectionHead = pt
        needsDisplay = true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        window?.makeFirstResponder(self)
        let menu = NSMenu()
        let copyItem = NSMenuItem(title: "コピー", action: #selector(copy(_:)), keyEquivalent: "")
        copyItem.target = self
        let pasteItem = NSMenuItem(title: "ペースト", action: #selector(paste(_:)), keyEquivalent: "")
        pasteItem.target = self
        let selectAllItem = NSMenuItem(
            title: "すべてを選択",
            action: #selector(selectAll(_:)),
            keyEquivalent: ""
        )
        selectAllItem.target = self
        menu.addItem(copyItem)
        menu.addItem(pasteItem)
        menu.addItem(.separator())
        menu.addItem(selectAllItem)
        return menu
    }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)), #selector(selectAll(_:)):
            return snapshot != nil
        case #selector(paste(_:)):
            return !(NSPasteboard.general.string(forType: .string) ?? "").isEmpty
        default:
            return false
        }
    }

    @objc func copy(_ sender: Any?) {
        _ = sender
        guard let snapshot else {
            return
        }
        let text: String
        if let sel = normalizedSelection {
            text = TerminalPaneViewController.extractSelectedText(
                lines: snapshot.lines,
                startRow: sel.start.row,
                startCol: sel.start.col,
                endRow: sel.end.row,
                endCol: sel.end.col
            )
        } else {
            text = snapshot.plainText()
        }
        guard !text.isEmpty else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc func paste(_ sender: Any?) {
        _ = sender
        guard let raw = NSPasteboard.general.string(forType: .string), !raw.isEmpty else {
            return
        }
        let normalized = TerminalPaneViewController.normalizePastedText(raw)
        selectionAnchor = nil
        selectionHead = nil
        needsDisplay = true
        onSendText?(normalized)
    }

    @objc override func selectAll(_ sender: Any?) {
        _ = sender
        guard let snapshot, !snapshot.lines.isEmpty else {
            return
        }
        selectionAnchor = TerminalGridPoint(row: 0, col: 0)
        selectionHead = TerminalGridPoint(
            row: snapshot.lines.count - 1,
            col: Int(snapshot.cols)
        )
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        let dy = event.scrollingDeltaY
        guard abs(dy) > 0.1 else {
            return
        }
        let step: Int64 =
            event.hasPreciseScrollingDeltas
            ? Int64((-dy / 8.0).rounded(.towardZero))
            : Int64(dy > 0 ? -3 : 3)
        if step != 0 {
            onScrollLines?(step)
        }
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            if let chars = event.charactersIgnoringModifiers?.lowercased() {
                if chars == "v" {
                    paste(nil)
                    return
                }
                if chars == "c" {
                    copy(nil)
                    return
                }
                if chars == "a" {
                    selectAll(nil)
                    return
                }
            }
            super.keyDown(with: event)
            return
        }

        if selectionAnchor != nil || selectionHead != nil {
            selectionAnchor = nil
            selectionHead = nil
            needsDisplay = true
        }

        if !hasMarkedText() {
            if flags.contains(.control),
                let scalar = event.charactersIgnoringModifiers?.lowercased().unicodeScalars.first
            {
                let value = scalar.value
                if value >= 97 && value <= 122, let ctrl = UnicodeScalar(value - 96) {
                    onSendText?(String(ctrl))
                    return
                }
                if value == 91 {
                    onSendText?("\u{1B}")
                    return
                }
            }

            if let sequence = specialKeySequence(for: event.keyCode) {
                onSendText?(sequence)
                return
            }
        }

        interpretKeyEvents([event])
    }

    private func specialKeySequence(for keyCode: UInt16) -> String? {
        switch keyCode {
        case 36, 76:
            return "\r"
        case 51:
            return "\u{7F}"
        case 117:
            return "\u{1B}[3~"
        case 48:
            return "\t"
        case 53:
            return "\u{1B}"
        case 126:
            return "\u{1B}[A"
        case 125:
            return "\u{1B}[B"
        case 124:
            return "\u{1B}[C"
        case 123:
            return "\u{1B}[D"
        case 115:
            return "\u{1B}[H"
        case 119:
            return "\u{1B}[F"
        case 116:
            return "\u{1B}[5~"
        case 121:
            return "\u{1B}[6~"
        default:
            return nil
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let isLight = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .aqua
        let themeColors = palette.terminalColors(isLight: isLight)
        let bgColor = themeColors.background
        bgColor.setFill()
        dirtyRect.fill()

        guard let snapshot else {
            return
        }

        let cell = cellSize
        let defaultFg = themeColors.foreground
        let theme = KasugaiThemeTokens.resolve(palette: palette, isLight: isLight)

        if let sel = normalizedSelection {
            let selColor = theme.accent.withAlphaComponent(isLight ? 0.24 : 0.32)
            selColor.setFill()
            let maxCols = max(1, Int(snapshot.cols))
            for row in sel.start.row...sel.end.row {
                let cStart = row == sel.start.row ? sel.start.col : 0
                let cEnd = row == sel.end.row ? sel.end.col : maxCols
                guard cEnd > cStart else {
                    continue
                }
                let rx = paddingX + CGFloat(cStart) * cell.width
                let ry = paddingY + CGFloat(row) * cell.height
                let rw = CGFloat(cEnd - cStart) * cell.width
                NSRect(x: rx, y: ry, width: rw, height: cell.height).fill()
            }
        }

        for (rowIndex, runs) in snapshot.lines.enumerated() {
            let y = paddingY + CGFloat(rowIndex) * cell.height
            var x = paddingX
            for run in runs {
                let runFont = fontForRun(bold: run.bold, italic: run.italic)
                let resolved = TerminalPaneViewController.resolveRunColors(
                    runFgHex: run.fg,
                    runBgHex: run.bg,
                    snapshotFgHex: snapshot.foreground,
                    snapshotBgHex: snapshot.background,
                    themeBg: bgColor,
                    themeFg: defaultFg,
                    isLight: isLight
                )
                var attrs: [NSAttributedString.Key: Any] = [
                    .font: runFont,
                    .foregroundColor: resolved.fg,
                ]
                let attributed = NSAttributedString(string: run.text, attributes: attrs)
                let width = ceil(attributed.size().width)
                if let runBg = resolved.bg {
                    attrs[.backgroundColor] = runBg
                    runBg.setFill()
                    NSRect(x: x, y: y, width: width, height: cell.height).fill()
                }
                attributed.draw(at: NSPoint(x: x, y: y))
                x += width
            }
        }

        if snapshot.cursorVisible {
            let cx = paddingX + CGFloat(snapshot.cursorX) * cell.width
            let cy = paddingY + CGFloat(snapshot.cursorY) * cell.height
            let cursorRect = NSRect(x: cx, y: cy, width: cell.width, height: cell.height)
            defaultFg.withAlphaComponent(0.45).setFill()
            cursorRect.fill()

            if hasMarkedText() {
                let markedAttrs: [NSAttributedString.Key: Any] = [
                    .font: baseFont,
                    .foregroundColor: defaultFg,
                    .backgroundColor: NSColor.selectedTextBackgroundColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ]
                NSAttributedString(string: markedTextStorage.string, attributes: markedAttrs)
                    .draw(at: NSPoint(x: cx, y: cy))
            }
        }
    }

    private func fontForRun(bold: Bool, italic: Bool) -> NSFont {
        let picked = bold ? boldFont : baseFont
        if italic {
            return NSFontManager.shared.convert(picked, toHaveTrait: .italicFontMask)
        }
        return picked
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        _ = replacementRange
        let text: String
        if let attr = string as? NSAttributedString {
            text = attr.string
        } else if let plain = string as? String {
            text = plain
        } else {
            return
        }
        unmarkText()
        if !text.isEmpty {
            onSendText?(text)
        }
    }

    func setMarkedText(
        _ string: Any,
        selectedRange: NSRange,
        replacementRange: NSRange
    ) {
        _ = replacementRange
        let text: String
        if let attr = string as? NSAttributedString {
            text = attr.string
        } else if let plain = string as? String {
            text = plain
        } else {
            text = ""
        }
        markedTextStorage = NSMutableAttributedString(string: text)
        markedRangeStorage =
            text.isEmpty
            ? NSRange(location: NSNotFound, length: 0)
            : NSRange(location: 0, length: (text as NSString).length)
        selectedRangeStorage = selectedRange
        needsDisplay = true
    }

    func unmarkText() {
        markedTextStorage = NSMutableAttributedString()
        markedRangeStorage = NSRange(location: NSNotFound, length: 0)
        selectedRangeStorage = NSRange(location: 0, length: 0)
        needsDisplay = true
    }

    func selectedRange() -> NSRange {
        selectedRangeStorage
    }

    func markedRange() -> NSRange {
        markedRangeStorage
    }

    func hasMarkedText() -> Bool {
        markedRangeStorage.location != NSNotFound && markedRangeStorage.length > 0
    }

    func attributedSubstring(
        forProposedRange range: NSRange,
        actualRange: NSRangePointer?
    ) -> NSAttributedString? {
        _ = range
        _ = actualRange
        return nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        []
    }

    func firstRect(
        forCharacterRange range: NSRange,
        actualRange: NSRangePointer?
    ) -> NSRect {
        _ = range
        _ = actualRange
        let cell = cellSize
        let cx = paddingX + CGFloat(snapshot?.cursorX ?? 0) * cell.width
        let cy = paddingY + CGFloat(snapshot?.cursorY ?? 0) * cell.height
        let localRect = NSRect(x: cx, y: cy, width: cell.width, height: cell.height)
        let inWindow = convert(localRect, to: nil)
        return window?.convertToScreen(inWindow) ?? .zero
    }

    func characterIndex(for point: NSPoint) -> Int {
        _ = point
        return 0
    }
}

final class TerminalPaneViewController: NSViewController {
    private let rootSurface = KasugaiSurfaceView()
    private let headerSurface = KasugaiSurfaceView()
    private let headerDivider = KasugaiSurfaceView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "ターミナル")
    private let cwdLabel = NSTextField(labelWithString: "")
    private let restartButton = KasugaiFlatButton()
    private let canvasView = TerminalCanvasView(frame: .zero)

    private var terminal: KasugaiTerminal?
    private var readSource: DispatchSourceRead?
    private var activeCwd: String = ""
    private var spawnedCwd: String = ""
    private var palette: KasugaiPalette = .kasugai

    deinit {
        stopTerminal()
    }

    override func loadView() {
        rootSurface.frame = NSRect(x: 0, y: 0, width: 700, height: 220)
        headerSurface.translatesAutoresizingMaskIntoConstraints = false
        headerDivider.translatesAutoresizingMaskIntoConstraints = false

        let cfg = NSImage.SymbolConfiguration(pointSize: 11.5, weight: .medium)
        iconView.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "ターミナル")?
            .withSymbolConfiguration(cfg)

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)

        cwdLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        cwdLabel.lineBreakMode = .byTruncatingMiddle

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        restartButton.buttonStyle = .ghost
        restartButton.horizontalPadding = 8
        restartButton.font = .systemFont(ofSize: 11.5, weight: .medium)
        restartButton.configureSymbol("arrow.clockwise", title: "再起動", pointSize: 11)
        restartButton.target = self
        restartButton.action = #selector(handleRestart)

        let header = NSStackView(views: [iconView, titleLabel, cwdLabel, spacer, restartButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 7
        header.translatesAutoresizingMaskIntoConstraints = false
        headerSurface.addSubview(header)

        canvasView.translatesAutoresizingMaskIntoConstraints = false
        canvasView.onSendText = { [weak self] text in
            guard let self else {
                return
            }
            if self.terminal == nil {
                self.startTerminalIfNeeded(forceRestart: true)
            }
            _ = self.terminal?.write(text)
            self.drainAndRender()
        }
        canvasView.onResizeGrid = { [weak self] cols, rows in
            guard let self, let terminal = self.terminal else {
                return
            }
            _ = terminal.resize(cols: cols, rows: rows)
            self.drainAndRender()
        }
        canvasView.onScrollLines = { [weak self] delta in
            guard let self, let terminal = self.terminal else {
                return
            }
            _ = terminal.scroll(deltaLines: delta)
            self.canvasView.update(snapshot: terminal.snapshot())
        }

        rootSurface.addSubview(headerSurface)
        rootSurface.addSubview(headerDivider)
        rootSurface.addSubview(canvasView)

        NSLayoutConstraint.activate([
            headerSurface.topAnchor.constraint(equalTo: rootSurface.topAnchor),
            headerSurface.leadingAnchor.constraint(equalTo: rootSurface.leadingAnchor),
            headerSurface.trailingAnchor.constraint(equalTo: rootSurface.trailingAnchor),
            headerSurface.heightAnchor.constraint(equalToConstant: 34),

            header.leadingAnchor.constraint(equalTo: headerSurface.leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: headerSurface.trailingAnchor, constant: -10),
            header.centerYAnchor.constraint(equalTo: headerSurface.centerYAnchor),

            headerDivider.topAnchor.constraint(equalTo: headerSurface.bottomAnchor),
            headerDivider.leadingAnchor.constraint(equalTo: rootSurface.leadingAnchor),
            headerDivider.trailingAnchor.constraint(equalTo: rootSurface.trailingAnchor),
            headerDivider.heightAnchor.constraint(equalToConstant: 1),

            canvasView.topAnchor.constraint(equalTo: headerDivider.bottomAnchor),
            canvasView.leadingAnchor.constraint(equalTo: rootSurface.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: rootSurface.trailingAnchor),
            canvasView.bottomAnchor.constraint(equalTo: rootSurface.bottomAnchor),
        ])

        self.view = rootSurface
        rootSurface.onAppearanceChanged = { [weak self] in
            self?.applyTheme()
        }
        applyTheme()
    }

    func update(palette: KasugaiPalette) {
        self.palette = palette
        canvasView.update(palette: palette)
        applyTheme()
    }

    func applyTheme() {
        let theme = KasugaiThemeTokens.resolve(
            palette: palette, appearance: view.effectiveAppearance)
        rootSurface.fillColor = theme.canvasBg
        headerSurface.fillColor = theme.sidebarBg
        headerDivider.fillColor = theme.borderSubtle
        iconView.contentTintColor = theme.textSecondary
        titleLabel.textColor = theme.textPrimary
        cwdLabel.textColor = theme.textMuted
        restartButton.apply(theme: theme)
    }

    func update(thread: KasugaiThread?, isPaneVisible: Bool) {
        let cwd = thread?.workspace.effectiveCwd ?? ""
        activeCwd = cwd
        if cwd.isEmpty {
            cwdLabel.stringValue = ""
        } else if cwd != spawnedCwd && terminal != nil {
            cwdLabel.stringValue = "作業フォルダ: \(cwd)（切替待ち）"
        } else {
            cwdLabel.stringValue = "作業フォルダ: \(cwd)"
        }
        if isPaneVisible {
            startTerminalIfNeeded(forceRestart: false)
        }
    }

    func ensureStartedAndFocus() {
        startTerminalIfNeeded(forceRestart: false)
        view.window?.makeFirstResponder(canvasView)
    }

    private func startTerminalIfNeeded(forceRestart: Bool) {
        let targetCwd =
            activeCwd.isEmpty ? FileManager.default.currentDirectoryPath : activeCwd
        if !forceRestart && terminal != nil && !(terminal?.exited ?? true) {
            return
        }
        stopTerminal()
        let grid = canvasView.computeGridSize()
        guard let created = KasugaiTerminal(cwd: targetCwd, cols: grid.cols, rows: grid.rows) else {
            return
        }
        terminal = created
        spawnedCwd = targetCwd
        cwdLabel.stringValue = "作業フォルダ: \(targetCwd)"
        let fd = created.wakeupFD
        if fd >= 0 {
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
            source.setEventHandler { [weak self] in
                self?.drainAndRender()
            }
            source.resume()
            readSource = source
        }
        drainAndRender()
    }

    private func stopTerminal() {
        readSource?.cancel()
        readSource = nil
        terminal = nil
    }

    private func drainAndRender() {
        guard let terminal else {
            return
        }
        _ = terminal.drain()
        let snap = terminal.snapshot()
        canvasView.update(snapshot: snap)
        if snap?.exited == true {
            cwdLabel.stringValue = "セッションが終了しました（再起動できます）"
        }
    }

    @objc private func handleRestart() {
        startTerminalIfNeeded(forceRestart: true)
        view.window?.makeFirstResponder(canvasView)
    }

    static func parseHexRGB(_ hex: String) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        guard hex.hasPrefix("#"), hex.count == 7 else {
            return nil
        }
        let body = String(hex.dropFirst())
        guard let value = UInt32(body, radix: 16) else {
            return nil
        }
        return (
            r: CGFloat((value >> 16) & 0xFF) / 255.0,
            g: CGFloat((value >> 8) & 0xFF) / 255.0,
            b: CGFloat(value & 0xFF) / 255.0
        )
    }

    static func relativeLuminance(r: CGFloat, g: CGFloat, b: CGFloat) -> CGFloat {
        0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    static func resolveRunColors(
        runFgHex: String,
        runBgHex: String,
        snapshotFgHex: String,
        snapshotBgHex: String,
        themeBg: NSColor,
        themeFg: NSColor,
        isLight: Bool
    ) -> (fg: NSColor, bg: NSColor?) {
        let normFg = runFgHex.lowercased()
        let normBg = runBgHex.lowercased()
        let normSnapFg = snapshotFgHex.lowercased()
        let normSnapBg = snapshotBgHex.lowercased()

        let resolvedBg: NSColor?
        if normBg.isEmpty {
            resolvedBg = nil
        } else if !normSnapFg.isEmpty && normBg == normSnapFg {
            resolvedBg = themeFg
        } else if !normSnapBg.isEmpty && normBg == normSnapBg {
            resolvedBg = nil
        } else if let rgb = parseHexRGB(normBg) {
            resolvedBg = NSColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1.0)
        } else {
            resolvedBg = nil
        }

        if normFg.isEmpty || (!normSnapFg.isEmpty && normFg == normSnapFg) {
            return (fg: themeFg, bg: resolvedBg)
        }
        if !normSnapBg.isEmpty && normFg == normSnapBg && resolvedBg != nil {
            return (fg: themeBg, bg: resolvedBg)
        }
        guard let rgb = parseHexRGB(normFg) else {
            return (fg: themeFg, bg: resolvedBg)
        }

        if isLight && resolvedBg == nil {
            let lum = relativeLuminance(r: rgb.r, g: rgb.g, b: rgb.b)
            if lum > 0.62 {
                let spread = max(rgb.r, max(rgb.g, rgb.b)) - min(rgb.r, min(rgb.g, rgb.b))
                if spread < 0.08 {
                    let darkLevel = max(0.12, (1.0 - lum) * 1.4)
                    return (
                        fg: NSColor(
                            srgbRed: darkLevel,
                            green: darkLevel,
                            blue: darkLevel,
                            alpha: 1.0
                        ),
                        bg: nil
                    )
                }
                let scale = 0.48 / lum
                return (
                    fg: NSColor(
                        srgbRed: min(1.0, rgb.r * scale),
                        green: min(1.0, rgb.g * scale),
                        blue: min(1.0, rgb.b * scale),
                        alpha: 1.0
                    ),
                    bg: nil
                )
            }
        }

        return (
            fg: NSColor(srgbRed: rgb.r, green: rgb.g, blue: rgb.b, alpha: 1.0),
            bg: resolvedBg
        )
    }

    static func normalizePastedText(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\r\n", with: "\r")
            .replacingOccurrences(of: "\n", with: "\r")
    }

    static func extractSelectedText(
        lines: [[KasugaiTerminalRun]],
        startRow: Int,
        startCol: Int,
        endRow: Int,
        endCol: Int
    ) -> String {
        guard !lines.isEmpty, startRow >= 0, endRow >= startRow else {
            return ""
        }
        let clampedEndRow = min(endRow, lines.count - 1)
        var out: [String] = []
        for row in startRow...clampedEndRow {
            let full = lines[row].map(\.text).joined()
            let chars = Array(full)
            let from = row == startRow ? max(0, min(startCol, chars.count)) : 0
            let to = row == endRow ? max(from, min(endCol, chars.count)) : chars.count
            var slice = String(chars[from..<to])
            if row < clampedEndRow || endCol >= chars.count {
                slice = slice.replacingOccurrences(
                    of: "\\s+$",
                    with: "",
                    options: .regularExpression
                )
            }
            out.append(slice)
        }
        return out.joined(separator: "\n")
    }

    static func runSelfTests() -> Bool {
        let lightColors = KasugaiPalette.kasugai.terminalColors(isLight: true)
        let darkColors = KasugaiPalette.kasugai.terminalColors(isLight: false)

        let defaultLight = resolveRunColors(
            runFgHex: "#eceef2",
            runBgHex: "",
            snapshotFgHex: "#eceef2",
            snapshotBgHex: "#16171b",
            themeBg: lightColors.background,
            themeFg: lightColors.foreground,
            isLight: true
        )
        let ansiWhiteOnLight = resolveRunColors(
            runFgHex: "#ffffff",
            runBgHex: "",
            snapshotFgHex: "#eceef2",
            snapshotBgHex: "#16171b",
            themeBg: lightColors.background,
            themeFg: lightColors.foreground,
            isLight: true
        )
        let inverseOnLight = resolveRunColors(
            runFgHex: "#16171b",
            runBgHex: "#eceef2",
            snapshotFgHex: "#eceef2",
            snapshotBgHex: "#16171b",
            themeBg: lightColors.background,
            themeFg: lightColors.foreground,
            isLight: true
        )
        let defaultDark = resolveRunColors(
            runFgHex: "#eceef2",
            runBgHex: "",
            snapshotFgHex: "#eceef2",
            snapshotBgHex: "#16171b",
            themeBg: darkColors.background,
            themeFg: darkColors.foreground,
            isLight: false
        )

        func lum(_ color: NSColor) -> CGFloat {
            let srgb = color.usingColorSpace(.sRGB) ?? color
            return relativeLuminance(
                r: srgb.redComponent,
                g: srgb.greenComponent,
                b: srgb.blueComponent
            )
        }

        let sampleRuns: [[KasugaiTerminalRun]] = [
            [
                KasugaiTerminalRun(
                    text: "hello world   ", fg: "", bg: "", bold: false, italic: false)
            ],
            [
                KasugaiTerminalRun(
                    text: "second line   ", fg: "", bg: "", bold: false, italic: false)
            ],
        ]
        let singleLineSelection = extractSelectedText(
            lines: sampleRuns,
            startRow: 0,
            startCol: 6,
            endRow: 0,
            endCol: 11
        )
        let multiLineSelection = extractSelectedText(
            lines: sampleRuns,
            startRow: 0,
            startCol: 6,
            endRow: 1,
            endCol: 6
        )
        let normalizedPaste = normalizePastedText("echo a\r\necho b\n")

        return lum(defaultLight.fg) < 0.25
            && defaultLight.bg == nil
            && lum(ansiWhiteOnLight.fg) < 0.4
            && lum(inverseOnLight.fg) > 0.8
            && inverseOnLight.bg.map(lum) ?? 1.0 < 0.25
            && lum(defaultDark.fg) > 0.75
            && singleLineSelection == "world"
            && multiLineSelection == "world\nsecond"
            && normalizedPaste == "echo a\recho b\r"
    }
}
