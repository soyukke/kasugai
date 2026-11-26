import AppKit
import Foundation

enum KasugaiRightPaneTabKind: Equatable {
    case diff
    case files
    case preview(String)
    case browser

    var symbolName: String {
        switch self {
        case .diff:
            return "doc.text.magnifyingglass"
        case .files:
            return "folder"
        case .preview:
            return "doc.text"
        case .browser:
            return "globe"
        }
    }

    var defaultTitle: String {
        switch self {
        case .diff:
            return "変更差分"
        case .files:
            return "ファイル"
        case .preview(let path):
            let name = URL(fileURLWithPath: path).lastPathComponent
            return name.isEmpty ? "プレビュー" : name
        case .browser:
            return "ブラウザ"
        }
    }
}

private final class WorkspaceFileNode {
    let url: URL
    let name: String
    let isDirectory: Bool
    private var loadedChildren: [WorkspaceFileNode]?

    private static let hiddenDefaults: Set<String> = [
        ".git",
        ".build",
        "node_modules",
        ".DS_Store",
    ]

    init(url: URL, isDirectory: Bool) {
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = isDirectory
    }

    var children: [WorkspaceFileNode] {
        if let loadedChildren {
            return loadedChildren
        }
        guard isDirectory else {
            loadedChildren = []
            return []
        }
        let fm = FileManager.default
        let items =
            (try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )) ?? []
        let built: [WorkspaceFileNode] = items.compactMap { item in
            let itemName = item.lastPathComponent
            if Self.hiddenDefaults.contains(itemName) {
                return nil
            }
            let values = try? item.resourceValues(forKeys: [.isDirectoryKey])
            return WorkspaceFileNode(url: item, isDirectory: values?.isDirectory ?? false)
        }.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
        loadedChildren = built
        return built
    }
}

private final class NonDraggableTabDocumentView: NSView {
    override var mouseDownCanMoveWindow: Bool {
        false
    }
}

private final class RightPaneTabCloseButton: NSButton {
    var onTap: (() -> Void)?

    private var theme = KasugaiThemeTokens.resolve(palette: .kasugai, isLight: false)
    private var isHovered = false
    private var isPressed = false
    private var trackingAreaRef: NSTrackingArea?

    override var isFlipped: Bool {
        true
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        title = ""
        image = nil
        focusRingType = .none
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        target = self
        action = #selector(handleButtonClick)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 18),
            heightAnchor.constraint(equalToConstant: 18),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 18, height: 18)
    }

    @objc private func handleButtonClick() {
        onTap?()
    }

    func apply(theme: KasugaiThemeTokens) {
        self.theme = theme
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func resetCursorRects() {
        if !KasugaiInteractiveMotion.isInteractionBlocked(for: self) {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard !KasugaiInteractiveMotion.isInteractionBlocked(for: self) else {
            return
        }
        isHovered = true
        needsDisplay = true
        KasugaiInteractiveMotion.applyScale(to: self, scale: 1.1)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
        needsDisplay = true
        KasugaiInteractiveMotion.applyScale(to: self, scale: 1.0)
    }

    override func mouseDown(with event: NSEvent) {
        guard !KasugaiInteractiveMotion.isInteractionBlocked(for: self) else {
            return
        }
        isPressed = true
        needsDisplay = true
        KasugaiInteractiveMotion.applyScale(to: self, scale: 0.9)
        super.mouseDown(with: event)
        isPressed = false
        needsDisplay = true
        KasugaiInteractiveMotion.applyScale(to: self, scale: isHovered ? 1.1 : 1.0)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isPressed || isHovered {
            let bg =
                isPressed
                ? theme.borderStrong
                : theme.surfaceSelected
            let oval = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
            bg.setFill()
            oval.fill()
        }
        let cx = bounds.midX
        let cy = bounds.midY
        let arm: CGFloat = 3.2
        let path = NSBezierPath()
        path.move(to: NSPoint(x: cx - arm, y: cy - arm))
        path.line(to: NSPoint(x: cx + arm, y: cy + arm))
        path.move(to: NSPoint(x: cx + arm, y: cy - arm))
        path.line(to: NSPoint(x: cx - arm, y: cy + arm))
        path.lineWidth = 1.45
        path.lineCapStyle = .round
        let strokeColor = (isHovered || isPressed) ? theme.textPrimary : theme.textMuted
        strokeColor.setStroke()
        path.stroke()
    }
}

private final class RightPaneTabChipView: NSView {
    let tabId: UUID
    var onSelect: (() -> Void)?
    var onClose: (() -> Void)?
    var onCloseOthers: (() -> Void)?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    let closeButton = RightPaneTabCloseButton()

    private var isSelectedTab = false
    private var isHovered = false
    private var showTrailingSeparator = false
    private var hasOtherTabs = false
    private var theme = KasugaiThemeTokens.resolve(palette: .kasugai, isLight: false)
    private var trackingAreaRef: NSTrackingArea?

    override var isFlipped: Bool {
        true
    }

    init(tabId: UUID, symbol: String, title: String, toolTip: String) {
        self.tabId = tabId
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        self.toolTip = toolTip

        let iconCfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(iconCfg)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        closeButton.toolTip = "タブを閉じる"
        closeButton.onTap = { [weak self] in
            self?.handleCloseTap()
        }

        let row = NSStackView(views: [iconView, titleLabel, closeButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 5
        row.translatesAutoresizingMaskIntoConstraints = false

        addSubview(row)

        let minWidth = widthAnchor.constraint(greaterThanOrEqualToConstant: 74)
        let maxWidth = widthAnchor.constraint(lessThanOrEqualToConstant: 156)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 25),
            minWidth,
            maxWidth,

            iconView.widthAnchor.constraint(equalToConstant: 12),
            iconView.heightAnchor.constraint(equalToConstant: 12),

            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            row.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -0.5),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(
        title: String,
        isSelected: Bool,
        showTrailingSeparator: Bool,
        hasOtherTabs: Bool,
        theme: KasugaiThemeTokens
    ) {
        self.isSelectedTab = isSelected
        self.showTrailingSeparator = showTrailingSeparator
        self.hasOtherTabs = hasOtherTabs
        self.theme = theme
        titleLabel.stringValue = title
        refreshStyle()
    }

    private func refreshStyle() {
        if isSelectedTab {
            iconView.contentTintColor = theme.textPrimary
            titleLabel.textColor = theme.textPrimary
            titleLabel.font = .systemFont(ofSize: 11.5, weight: .semibold)
        } else if isHovered {
            iconView.contentTintColor = theme.textSecondary
            titleLabel.textColor = theme.textSecondary
            titleLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        } else {
            iconView.contentTintColor = theme.textMuted
            titleLabel.textColor = theme.textMuted
            titleLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        }
        closeButton.isHidden = !(isSelectedTab || isHovered)
        closeButton.apply(theme: theme)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width
        let h = bounds.height
        guard w > 4, h > 4 else {
            return
        }
        if isSelectedTab {
            let r: CGFloat = 7.0
            let fillPath = NSBezierPath()
            fillPath.move(to: NSPoint(x: 0, y: h))
            fillPath.line(to: NSPoint(x: 0, y: r))
            fillPath.appendArc(from: NSPoint(x: 0, y: 0), to: NSPoint(x: r, y: 0), radius: r)
            fillPath.line(to: NSPoint(x: w - r, y: 0))
            fillPath.appendArc(from: NSPoint(x: w, y: 0), to: NSPoint(x: w, y: r), radius: r)
            fillPath.line(to: NSPoint(x: w, y: h))
            fillPath.close()
            theme.canvasBg.setFill()
            fillPath.fill()

            let sr: CGFloat = 6.5
            let strokePath = NSBezierPath()
            strokePath.move(to: NSPoint(x: 0.5, y: h))
            strokePath.line(to: NSPoint(x: 0.5, y: 0.5 + sr))
            strokePath.appendArc(
                from: NSPoint(x: 0.5, y: 0.5),
                to: NSPoint(x: 0.5 + sr, y: 0.5),
                radius: sr
            )
            strokePath.line(to: NSPoint(x: w - 0.5 - sr, y: 0.5))
            strokePath.appendArc(
                from: NSPoint(x: w - 0.5, y: 0.5),
                to: NSPoint(x: w - 0.5, y: 0.5 + sr),
                radius: sr
            )
            strokePath.line(to: NSPoint(x: w - 0.5, y: h))
            strokePath.lineWidth = 1.0
            theme.borderSubtle.setStroke()
            strokePath.stroke()
        } else {
            if isHovered {
                let hoverRect = NSRect(x: 2, y: 2, width: w - 4, height: h - 5)
                let hoverPath = NSBezierPath(roundedRect: hoverRect, xRadius: 6, yRadius: 6)
                theme.surfaceSelected.setFill()
                hoverPath.fill()
            } else if showTrailingSeparator {
                let sep = NSBezierPath()
                sep.move(to: NSPoint(x: w - 0.5, y: 8))
                sep.line(to: NSPoint(x: w - 0.5, y: h - 9))
                sep.lineWidth = 1.0
                theme.borderSubtle.setStroke()
                sep.stroke()
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func resetCursorRects() {
        if !KasugaiInteractiveMotion.isInteractionBlocked(for: self) {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard !KasugaiInteractiveMotion.isInteractionBlocked(for: self) else {
            return
        }
        isHovered = true
        refreshStyle()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        refreshStyle()
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, !KasugaiInteractiveMotion.isInteractionBlocked(for: self) else {
            return nil
        }
        let local = convert(point, from: superview)
        guard bounds.contains(local) else {
            return nil
        }
        if !closeButton.isHidden {
            let closeRect = convert(closeButton.bounds, from: closeButton).insetBy(dx: -3, dy: -3)
            if closeRect.contains(local) {
                return closeButton
            }
        }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        onSelect?()
    }

    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 {
            onClose?()
            return
        }
        super.otherMouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let closeItem = NSMenuItem(
            title: "タブを閉じる",
            action: #selector(handleCloseTap),
            keyEquivalent: ""
        )
        closeItem.target = self
        menu.addItem(closeItem)
        if hasOtherTabs {
            let closeOthersItem = NSMenuItem(
                title: "他のタブをすべて閉じる",
                action: #selector(handleCloseOthersTap),
                keyEquivalent: ""
            )
            closeOthersItem.target = self
            menu.addItem(closeOthersItem)
        }
        return menu
    }

    @objc private func handleCloseTap() {
        onClose?()
    }

    @objc private func handleCloseOthersTap() {
        onCloseOthers?()
    }
}

private final class RightPaneTabEntry {
    let id = UUID()
    let kind: KasugaiRightPaneTabKind
    var title: String
    var toolTip: String
    let contentView: NSView
    weak var browserView: LocalPreviewBrowserView?
    weak var previewWebView: SandboxedChatWebView?

    init(
        kind: KasugaiRightPaneTabKind,
        title: String,
        toolTip: String,
        contentView: NSView,
        browserView: LocalPreviewBrowserView? = nil,
        previewWebView: SandboxedChatWebView? = nil
    ) {
        self.kind = kind
        self.title = title
        self.toolTip = toolTip
        self.contentView = contentView
        self.browserView = browserView
        self.previewWebView = previewWebView
    }
}

private final class ThreadRightPaneState {
    var tabs: [RightPaneTabEntry] = []
    var activeTabId: UUID?
    var fileRootPath: String = ""
}

final class DiffViewerController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate,
    NSMenuDelegate
{
    var onCreateWorktree: ((String, String) -> Void)?
    var onResetWorktree: (() -> Void)?
    var onAttachPreviewedFile: ((String) -> Void)?
    var onOpenFileLink: ((FileLinkTarget) -> Void)?
    var onDiffStatsComputed: ((Int64, Int64, Int64, Int64) -> Void)?
    var onDiffReportComputed: ((Int64, GitDiffReport) -> Void)?
    var onAllTabsClosed: (() -> Void)?
    var onToggleRightPane: (() -> Void)?
    var onTabsStateChanged: (() -> Void)?

    var tabCount: Int {
        tabs.count
    }

    var activeTabKind: KasugaiRightPaneTabKind? {
        activeTab?.kind
    }

    func activeTabCloseButtonForTest() -> NSButton? {
        guard let activeTabId,
            let chip = tabChips.first(where: { $0.tabId == activeTabId })
        else {
            return nil
        }
        return chip.closeButton
    }

    private let rootSurface = KasugaiSurfaceView()
    private let headerWell = KasugaiSurfaceView()
    let headerDivider = KasugaiSurfaceView()
    private let subBarContainer = NSView()
    private let subDivider = KasugaiSurfaceView()
    private let tabScrollView = NSScrollView()
    private let tabStack = NSStackView()
    private let addTabButton = KasugaiFlatButton()
    private let refreshButton = KasugaiFlatButton()
    let rightPaneToggleButton = KasugaiFlatButton()

    private let subRow = NSStackView()
    private let pathLabel = NSTextField(labelWithString: "")
    private let createWorktreeButton = KasugaiFlatButton()
    private let resetWorktreeButton = KasugaiFlatButton()
    private let attachFileButton = KasugaiFlatButton()

    private let bodyContainer = NSView()
    private var bodyTopBelowHeader: NSLayoutConstraint?
    private var bodyTopBelowSubBar: NSLayoutConstraint?
    private let diffWebView = SandboxedChatWebView(frame: .zero, mode: .diff)
    private let outlineView = NSOutlineView()
    private let fileScrollView = NSScrollView()

    private var paneStatesByThreadId: [Int64: ThreadRightPaneState] = [:]
    private var factoryPaneKeysByRunId: [String: Int64] = [:]
    private var nextFactoryPaneKey: Int64 = -1
    private var pendingPersistedPanes: [Int64: KasugaiPersistedThreadRightPane] = [:]
    private var isRestoringPaneState = false
    private var backgroundBrowserHostWindow: NSWindow?
    private var tabChips: [RightPaneTabChipView] = []

    private var currentThreadId: Int64 = 0
    private var currentCwd: String = ""
    private var isCurrentWorktree: Bool = false
    private var currentBranch: String = ""
    private var fileRootNode: WorkspaceFileNode?
    private var lastDiffReport: GitDiffReport?
    private var pendingFocusFile: String?
    private var refreshGeneration: Int = 0
    private var palette: KasugaiPalette = .kasugai
    private var browserPolicy: KasugaiBrowserPolicy = .loopbackOnly
    private var theme: KasugaiThemeTokens = KasugaiThemeTokens.resolve(
        palette: .kasugai, isLight: false)

    private var activePaneState: ThreadRightPaneState {
        if let existing = paneStatesByThreadId[currentThreadId] {
            return existing
        }
        let created = ThreadRightPaneState()
        paneStatesByThreadId[currentThreadId] = created
        return created
    }

    private var tabs: [RightPaneTabEntry] {
        get { activePaneState.tabs }
        set { activePaneState.tabs = newValue }
    }

    private var activeTabId: UUID? {
        get { activePaneState.activeTabId }
        set { activePaneState.activeTabId = newValue }
    }

    private var fileRootPath: String {
        get { activePaneState.fileRootPath }
        set { activePaneState.fileRootPath = newValue }
    }

    private var allTabsAcrossThreads: [RightPaneTabEntry] {
        paneStatesByThreadId.values.flatMap(\.tabs)
    }

    private var activeTab: RightPaneTabEntry? {
        tabs.first(where: { $0.id == activeTabId })
    }

    override func loadView() {
        rootSurface.frame = NSRect(x: 0, y: 0, width: 560, height: 640)

        headerWell.translatesAutoresizingMaskIntoConstraints = false

        tabStack.orientation = .horizontal
        tabStack.alignment = .bottom
        tabStack.spacing = 0
        tabStack.translatesAutoresizingMaskIntoConstraints = false

        let tabDocView = NonDraggableTabDocumentView()
        tabDocView.translatesAutoresizingMaskIntoConstraints = false
        tabDocView.addSubview(tabStack)
        NSLayoutConstraint.activate([
            tabStack.topAnchor.constraint(equalTo: tabDocView.topAnchor),
            tabStack.bottomAnchor.constraint(equalTo: tabDocView.bottomAnchor),
            tabStack.leadingAnchor.constraint(equalTo: tabDocView.leadingAnchor),
            tabStack.trailingAnchor.constraint(equalTo: tabDocView.trailingAnchor),
            tabStack.heightAnchor.constraint(
                equalToConstant: KasugaiChromeMetrics.headerHeight + 1),
        ])

        tabScrollView.automaticallyAdjustsContentInsets = false
        tabScrollView.contentInsets = NSEdgeInsetsZero
        tabScrollView.scrollerInsets = NSEdgeInsetsZero
        tabScrollView.documentView = tabDocView
        NSLayoutConstraint.activate([
            tabDocView.topAnchor.constraint(equalTo: tabScrollView.contentView.topAnchor),
            tabDocView.bottomAnchor.constraint(equalTo: tabScrollView.contentView.bottomAnchor),
        ])
        tabScrollView.hasHorizontalScroller = false
        tabScrollView.hasVerticalScroller = false
        tabScrollView.drawsBackground = false
        tabScrollView.borderType = .noBorder
        tabScrollView.setContentHuggingPriority(.init(240), for: .horizontal)
        tabScrollView.setContentCompressionResistancePriority(.init(100), for: .horizontal)
        tabScrollView.translatesAutoresizingMaskIntoConstraints = false

        addTabButton.buttonStyle = .ghost
        addTabButton.customHeight = 22
        addTabButton.horizontalPadding = 5
        addTabButton.configureSymbol("plus", pointSize: 11.5, weight: .medium)
        addTabButton.toolTip = "タブを追加"
        addTabButton.target = self
        addTabButton.action = #selector(handleAddTabMenu)

        let tabFlexSpacer = NSView()
        tabFlexSpacer.setContentHuggingPriority(.init(1), for: .horizontal)
        tabFlexSpacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        createWorktreeButton.buttonStyle = .ghost
        createWorktreeButton.customHeight = 22
        createWorktreeButton.horizontalPadding = 5
        createWorktreeButton.configureSymbol(
            "arrow.triangle.branch", pointSize: 11, weight: .medium)
        createWorktreeButton.toolTip = "Worktree を作成…"
        createWorktreeButton.target = self
        createWorktreeButton.action = #selector(handleCreateWorktree)

        resetWorktreeButton.buttonStyle = .ghost
        resetWorktreeButton.customHeight = 22
        resetWorktreeButton.horizontalPadding = 5
        resetWorktreeButton.configureSymbol(
            "arrow.uturn.backward", pointSize: 11, weight: .medium)
        resetWorktreeButton.toolTip = "ルートに戻す"
        resetWorktreeButton.target = self
        resetWorktreeButton.action = #selector(handleResetWorktree)
        resetWorktreeButton.isHidden = true

        refreshButton.buttonStyle = .ghost
        refreshButton.customHeight = 22
        refreshButton.horizontalPadding = 5
        refreshButton.configureSymbol("arrow.clockwise", pointSize: 11, weight: .medium)
        refreshButton.toolTip = "更新"
        refreshButton.target = self
        refreshButton.action = #selector(handleRefresh)

        rightPaneToggleButton.buttonStyle = .ghost
        rightPaneToggleButton.customHeight = 22
        rightPaneToggleButton.horizontalPadding = 5
        rightPaneToggleButton.configureSymbol("sidebar.right", pointSize: 12.5, weight: .medium)
        rightPaneToggleButton.toolTip = "右ペインを切り替え（⌘D）"
        rightPaneToggleButton.isSelectedPill = true
        rightPaneToggleButton.target = self
        rightPaneToggleButton.action = #selector(handleToggleRightPane)

        let titleRow = NSStackView(views: [
            tabScrollView,
            addTabButton,
            tabFlexSpacer,
            createWorktreeButton,
            resetWorktreeButton,
            refreshButton,
            rightPaneToggleButton,
        ])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 4
        titleRow.setHuggingPriority(.init(1), for: .horizontal)
        titleRow.translatesAutoresizingMaskIntoConstraints = false

        headerDivider.translatesAutoresizingMaskIntoConstraints = false

        pathLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.setContentHuggingPriority(.init(1), for: .horizontal)
        pathLabel.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        attachFileButton.buttonStyle = .ghost
        attachFileButton.horizontalPadding = 6
        attachFileButton.configureSymbol("paperclip", pointSize: 12, weight: .medium)
        attachFileButton.toolTip = "入力欄に添付"
        attachFileButton.target = self
        attachFileButton.action = #selector(handleAttachFile)
        attachFileButton.isHidden = true

        subRow.addArrangedSubview(pathLabel)
        subRow.addArrangedSubview(attachFileButton)
        subRow.orientation = .horizontal
        subRow.alignment = .centerY
        subRow.spacing = 5
        subRow.translatesAutoresizingMaskIntoConstraints = false

        subDivider.translatesAutoresizingMaskIntoConstraints = false
        subBarContainer.translatesAutoresizingMaskIntoConstraints = false
        subBarContainer.addSubview(subRow)
        subBarContainer.addSubview(subDivider)

        let fileCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("workspaceFileTree"))
        fileCol.resizingMask = .autoresizingMask
        outlineView.addTableColumn(fileCol)
        outlineView.outlineTableColumn = fileCol
        outlineView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outlineView.headerView = nil
        outlineView.style = .plain
        outlineView.backgroundColor = .clear
        outlineView.rowSizeStyle = .small
        outlineView.dataSource = self
        outlineView.delegate = self

        let fileMenu = NSMenu()
        fileMenu.delegate = self
        outlineView.menu = fileMenu

        fileScrollView.documentView = outlineView
        fileScrollView.hasHorizontalScroller = false
        fileScrollView.hasVerticalScroller = true
        fileScrollView.autohidesScrollers = true
        fileScrollView.drawsBackground = false
        fileScrollView.borderType = .noBorder

        bodyContainer.translatesAutoresizingMaskIntoConstraints = false

        rootSurface.addSubview(headerWell)
        rootSurface.addSubview(headerDivider)
        rootSurface.addSubview(titleRow)
        rootSurface.addSubview(subBarContainer)
        rootSurface.addSubview(bodyContainer)

        let topBelowHeader = bodyContainer.topAnchor.constraint(
            equalTo: headerDivider.bottomAnchor)
        let topBelowSubBar = bodyContainer.topAnchor.constraint(
            equalTo: subBarContainer.bottomAnchor)
        bodyTopBelowHeader = topBelowHeader
        bodyTopBelowSubBar = topBelowSubBar

        let fitTabScrollWidth = tabScrollView.widthAnchor.constraint(equalTo: tabStack.widthAnchor)
        fitTabScrollWidth.priority = NSLayoutConstraint.Priority(240)

        NSLayoutConstraint.activate([
            headerWell.topAnchor.constraint(equalTo: rootSurface.topAnchor),
            headerWell.leadingAnchor.constraint(equalTo: rootSurface.leadingAnchor),
            headerWell.trailingAnchor.constraint(equalTo: rootSurface.trailingAnchor),
            headerWell.heightAnchor.constraint(equalToConstant: KasugaiChromeMetrics.headerHeight),

            headerDivider.topAnchor.constraint(equalTo: headerWell.bottomAnchor),
            headerDivider.leadingAnchor.constraint(equalTo: rootSurface.leadingAnchor),
            headerDivider.trailingAnchor.constraint(equalTo: rootSurface.trailingAnchor),
            headerDivider.heightAnchor.constraint(equalToConstant: 1),

            titleRow.topAnchor.constraint(equalTo: rootSurface.topAnchor),
            titleRow.leadingAnchor.constraint(equalTo: rootSurface.leadingAnchor, constant: 6),
            titleRow.trailingAnchor.constraint(equalTo: rootSurface.trailingAnchor, constant: -12),
            titleRow.bottomAnchor.constraint(equalTo: headerDivider.bottomAnchor),

            tabScrollView.heightAnchor.constraint(
                equalToConstant: KasugaiChromeMetrics.headerHeight + 1),
            fitTabScrollWidth,

            subBarContainer.topAnchor.constraint(equalTo: headerDivider.bottomAnchor),
            subBarContainer.leadingAnchor.constraint(equalTo: rootSurface.leadingAnchor),
            subBarContainer.trailingAnchor.constraint(equalTo: rootSurface.trailingAnchor),

            subRow.topAnchor.constraint(equalTo: subBarContainer.topAnchor, constant: 4),
            subRow.leadingAnchor.constraint(equalTo: subBarContainer.leadingAnchor, constant: 10),
            subRow.trailingAnchor.constraint(
                equalTo: subBarContainer.trailingAnchor, constant: -10),
            subRow.heightAnchor.constraint(equalToConstant: 24),

            subDivider.topAnchor.constraint(equalTo: subRow.bottomAnchor, constant: 4),
            subDivider.leadingAnchor.constraint(equalTo: subBarContainer.leadingAnchor),
            subDivider.trailingAnchor.constraint(equalTo: subBarContainer.trailingAnchor),
            subDivider.bottomAnchor.constraint(equalTo: subBarContainer.bottomAnchor),
            subDivider.heightAnchor.constraint(equalToConstant: 1),

            topBelowHeader,
            bodyContainer.leadingAnchor.constraint(equalTo: rootSurface.leadingAnchor),
            bodyContainer.trailingAnchor.constraint(equalTo: rootSurface.trailingAnchor),
            bodyContainer.bottomAnchor.constraint(equalTo: rootSurface.bottomAnchor),
        ])

        self.view = rootSurface
        rootSurface.onAppearanceChanged = { [weak self] in
            self?.applyTheme()
        }
        applyTheme()
        ensureDefaultTabIfEmpty()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        scrollActiveTabIntoView()
    }

    private func scrollActiveTabIntoView() {
        guard let activeTabId,
            let chip = tabChips.first(where: { $0.tabId == activeTabId }),
            let docView = tabScrollView.documentView
        else {
            return
        }
        tabScrollView.layoutSubtreeIfNeeded()
        docView.layoutSubtreeIfNeeded()
        let visibleW = tabScrollView.contentView.bounds.width
        let docW = docView.bounds.width
        guard visibleW > 0, docW > 0 else {
            return
        }
        let rectInDoc = docView.convert(chip.bounds, from: chip)
        let maxScrollX = max(0, docW - visibleW)
        let currentX = tabScrollView.contentView.bounds.origin.x
        var targetX = currentX
        if rectInDoc.maxX > currentX + visibleW {
            targetX = rectInDoc.maxX - visibleW
        } else if rectInDoc.minX < currentX {
            targetX = rectInDoc.minX
        }
        targetX = max(0, min(targetX, maxScrollX))
        if abs(targetX - currentX) > 0.5 {
            tabScrollView.contentView.scroll(to: NSPoint(x: targetX, y: 0))
            tabScrollView.reflectScrolledClipView(tabScrollView.contentView)
        }
    }

    func update(palette: KasugaiPalette) {
        self.palette = palette
        diffWebView.update(palette: palette)
        for tab in allTabsAcrossThreads {
            tab.browserView?.update(palette: palette)
            tab.previewWebView?.update(palette: palette)
        }
        applyTheme()
    }

    func update(browserPolicy: KasugaiBrowserPolicy) {
        self.browserPolicy = browserPolicy
        for tab in allTabsAcrossThreads {
            tab.browserView?.update(policy: browserPolicy)
        }
    }

    func applyTheme() {
        theme = KasugaiThemeTokens.resolve(
            palette: palette, appearance: view.effectiveAppearance)
        rootSurface.fillColor = theme.canvasBg
        headerWell.fillColor = theme.sidebarBg
        headerDivider.fillColor = theme.borderSubtle
        subDivider.fillColor = theme.borderSubtle
        addTabButton.apply(theme: theme)
        refreshButton.apply(theme: theme)
        rightPaneToggleButton.isSelectedPill = true
        rightPaneToggleButton.apply(theme: theme)
        pathLabel.textColor = theme.textMuted
        createWorktreeButton.apply(theme: theme)
        resetWorktreeButton.apply(theme: theme)
        attachFileButton.apply(theme: theme)
        outlineView.reloadData()
        syncTabChipsStyle()
    }

    deinit {
        backgroundBrowserHostWindow?.close()
        backgroundBrowserHostWindow = nil
    }

    private func ensureBackgroundBrowserHostContentView() -> NSView {
        let hostSize = NSSize(
            width: max(640, bodyContainer.bounds.width),
            height: max(480, bodyContainer.bounds.height)
        )
        if let existing = backgroundBrowserHostWindow {
            if existing.frame.size != hostSize {
                existing.setContentSize(hostSize)
            }
            if let content = existing.contentView {
                return content
            }
        }
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: hostSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(origin: .zero, size: hostSize))
        win.contentView = content
        backgroundBrowserHostWindow = win
        return content
    }

    private func parkBackgroundBrowserView(_ browser: LocalPreviewBrowserView) {
        let hostContent = ensureBackgroundBrowserHostContentView()
        if browser.superview !== hostContent {
            browser.removeFromSuperview()
            browser.translatesAutoresizingMaskIntoConstraints = true
            browser.frame = hostContent.bounds
            browser.autoresizingMask = [.width, .height]
            browser.isHidden = false
            hostContent.addSubview(browser)
        } else {
            browser.frame = hostContent.bounds
            browser.isHidden = false
        }
        browser.layoutSubtreeIfNeeded()
    }

    private func makeBrowserTabEntry(forThreadId targetThreadId: Int64) -> RightPaneTabEntry {
        let browser = LocalPreviewBrowserView(frame: .zero, policy: browserPolicy)
        browser.update(palette: palette)
        let created = RightPaneTabEntry(
            kind: .browser,
            title: KasugaiRightPaneTabKind.browser.defaultTitle,
            toolTip: browserPolicy.allowExternal ? "内蔵ブラウザ" : "ローカルブラウザ",
            contentView: browser,
            browserView: browser
        )
        browser.onDisplayTitleChanged = { [weak self, weak created] title in
            guard let self, let created else {
                return
            }
            let changed = created.title != title
            created.title = title
            created.toolTip = title
            if self.currentThreadId == targetThreadId {
                self.syncTabChipsStyle()
            }
            if changed {
                self.notifyTabsStateChanged(for: targetThreadId)
            }
        }
        browser.onURLChanged = { [weak self] _ in
            self?.notifyTabsStateChanged(for: targetThreadId)
        }
        return created
    }

    private func notifyTabsStateChanged(for threadId: Int64? = nil) {
        let targetId = threadId ?? currentThreadId
        guard !isRestoringPaneState, targetId > 0 else {
            return
        }
        onTabsStateChanged?()
    }

    private static func isExistingDirectory(_ path: String) -> Bool {
        guard !path.isEmpty else {
            return false
        }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    func loadPersistedStore(_ store: KasugaiRightPaneTabStore) {
        pendingPersistedPanes.removeAll()
        for (key, pane) in store.byThreadId {
            if let threadId = Int64(key), threadId > 0, !pane.tabs.isEmpty {
                pendingPersistedPanes[threadId] = pane
            }
        }
        if currentThreadId > 0,
            let saved = pendingPersistedPanes.removeValue(forKey: currentThreadId)
        {
            restorePersistedPane(saved, for: currentThreadId)
        }
    }

    func removeThreadState(for threadId: Int64) {
        pendingPersistedPanes.removeValue(forKey: threadId)
        if let removed = paneStatesByThreadId.removeValue(forKey: threadId) {
            for tab in removed.tabs {
                tab.contentView.isHidden = true
                if tab.kind != .diff && tab.kind != .files {
                    tab.contentView.removeFromSuperview()
                }
            }
        }
        if currentThreadId == threadId {
            currentThreadId = 0
            for chip in tabChips {
                tabStack.removeArrangedSubview(chip)
                chip.removeFromSuperview()
            }
            tabChips.removeAll()
        }
    }

    func capturePersistedStore() -> KasugaiRightPaneTabStore {
        var result = KasugaiRightPaneTabStore.empty
        for (threadId, pending) in pendingPersistedPanes
        where threadId > 0 && !pending.tabs.isEmpty {
            result.setPane(pending, for: threadId)
        }
        for (threadId, state) in paneStatesByThreadId where threadId > 0 {
            let persistedTabs: [KasugaiPersistedRightPaneTab] = state.tabs.map { entry in
                switch entry.kind {
                case .diff:
                    return KasugaiPersistedRightPaneTab(
                        kind: .diff,
                        path: nil,
                        url: nil,
                        title: nil
                    )
                case .files:
                    return KasugaiPersistedRightPaneTab(
                        kind: .files,
                        path: nil,
                        url: nil,
                        title: nil
                    )
                case .preview(let path):
                    return KasugaiPersistedRightPaneTab(
                        kind: .preview,
                        path: path,
                        url: nil,
                        title: nil
                    )
                case .browser:
                    let currentURL = entry.browserView?.currentURLString ?? ""
                    let cleanURL = currentURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleanTitle = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    return KasugaiPersistedRightPaneTab(
                        kind: .browser,
                        path: nil,
                        url: cleanURL.isEmpty ? nil : cleanURL,
                        title: cleanTitle.isEmpty ? nil : cleanTitle
                    )
                }
            }
            if persistedTabs.isEmpty {
                result.setPane(nil, for: threadId)
                continue
            }
            let activeIdx = state.tabs.firstIndex(where: { $0.id == state.activeTabId }) ?? 0
            let cleanFileRoot = state.fileRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
            result.setPane(
                KasugaiPersistedThreadRightPane(
                    tabs: persistedTabs,
                    activeIndex: activeIdx,
                    fileRootPath: cleanFileRoot.isEmpty ? nil : cleanFileRoot
                ),
                for: threadId
            )
        }
        return result
    }

    private func restorePersistedPane(
        _ saved: KasugaiPersistedThreadRightPane,
        for threadId: Int64
    ) {
        isRestoringPaneState = true
        defer { isRestoringPaneState = false }

        if let existing = paneStatesByThreadId[threadId] {
            for tab in existing.tabs {
                tab.contentView.isHidden = true
                if tab.kind != .diff && tab.kind != .files {
                    tab.contentView.removeFromSuperview()
                }
            }
        }
        let state = ThreadRightPaneState()
        if let savedRoot = saved.fileRootPath, Self.isExistingDirectory(savedRoot) {
            state.fileRootPath = savedRoot
        }
        paneStatesByThreadId[threadId] = state

        var restoredIds: [UUID?] = []
        for savedTab in saved.tabs {
            switch savedTab.kind {
            case .diff:
                restoredIds.append(openTab(.diff, animated: false))
            case .files:
                restoredIds.append(openTab(.files, animated: false))
            case .preview:
                if let path = savedTab.path, !path.isEmpty,
                    FileManager.default.fileExists(atPath: path)
                {
                    restoredIds.append(openTab(.preview(path), animated: false))
                } else {
                    restoredIds.append(nil)
                }
            case .browser:
                let tabId = openTab(.browser, animated: false)
                if let entry = tabs.first(where: { $0.id == tabId }) {
                    if let savedTitle = savedTab.title, !savedTitle.isEmpty {
                        entry.title = savedTitle
                        entry.toolTip = savedTitle
                    }
                    if let savedURL = savedTab.url, !savedURL.isEmpty {
                        entry.browserView?.restorePersistedURL(savedURL)
                    }
                }
                restoredIds.append(tabId)
            }
        }

        if tabs.isEmpty {
            _ = openTab(.diff, animated: false)
        } else {
            let targetId: UUID
            if saved.activeIndex >= 0,
                saved.activeIndex < restoredIds.count,
                let matchedId = restoredIds[saved.activeIndex]
            {
                targetId = matchedId
            } else {
                targetId = tabs[0].id
            }
            selectTab(id: targetId, animated: false)
        }
        syncTabChipsStyle()
    }

    func ensureDefaultTabIfEmpty() {
        if tabs.isEmpty {
            openTab(currentThreadId < 0 ? .files : .diff)
        }
    }

    @discardableResult
    func openTab(_ kind: KasugaiRightPaneTabKind, animated: Bool = true) -> UUID {
        switch kind {
        case .diff, .files, .preview:
            if let existing = tabs.first(where: { $0.kind == kind }) {
                selectTab(id: existing.id, animated: animated)
                return existing.id
            }
        case .browser:
            break
        }

        let entry: RightPaneTabEntry
        switch kind {
        case .diff:
            entry = RightPaneTabEntry(
                kind: .diff,
                title: kind.defaultTitle,
                toolTip: "変更差分",
                contentView: diffWebView
            )
            if let lastDiffReport {
                diffWebView.update(diffReport: lastDiffReport)
            } else {
                reloadDiffAsync()
            }
        case .files:
            entry = RightPaneTabEntry(
                kind: .files,
                title: kind.defaultTitle,
                toolTip: "ファイル",
                contentView: fileScrollView
            )
            let targetRoot = Self.isExistingDirectory(fileRootPath) ? fileRootPath : currentCwd
            if fileRootNode == nil && !targetRoot.isEmpty {
                reloadFileTree(rootPath: targetRoot)
            }
        case .preview(let path):
            let webView = SandboxedChatWebView(frame: .zero, mode: .diff)
            webView.update(palette: palette)
            webView.update(filePreviewPath: path)
            webView.onOpenFileLink = { [weak self] target in
                self?.onOpenFileLink?(target)
            }
            entry = RightPaneTabEntry(
                kind: .preview(path),
                title: kind.defaultTitle,
                toolTip: path,
                contentView: webView,
                previewWebView: webView
            )
        case .browser:
            entry = makeBrowserTabEntry(forThreadId: currentThreadId)
        }

        tabs.append(entry)
        mountContentViewIfNeeded(entry.contentView)
        rebuildTabBar()
        selectTab(id: entry.id, animated: animated)
        notifyTabsStateChanged()
        return entry.id
    }

    func selectTab(id: UUID, animated: Bool = true) {
        guard let nextIndex = tabs.firstIndex(where: { $0.id == id }) else {
            return
        }
        let previousId = activeTabId
        let previousIndex = tabs.firstIndex(where: { $0.id == previousId })
        activeTabId = id
        for tab in tabs {
            tab.contentView.isHidden = tab.id != id
        }
        syncTabChipsStyle()
        scrollActiveTabIntoView()
        syncSubBar()
        if animated, previousId != nil, previousId != id {
            let direction: KasugaiSlideDirection
            if let previousIndex {
                direction = nextIndex >= previousIndex ? .fromRight : .fromLeft
            } else {
                direction = .fromRight
            }
            KasugaiInteractiveMotion.animateDirectionalEnter(
                view: tabs[nextIndex].contentView,
                direction: direction,
                distance: 16,
                duration: 0.18
            )
        }
        if previousId != id {
            notifyTabsStateChanged()
        }
    }

    func closeTab(id: UUID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else {
            return
        }
        let removed = tabs.remove(at: idx)
        if removed.kind != .diff && removed.kind != .files {
            removed.contentView.removeFromSuperview()
        } else {
            removed.contentView.isHidden = true
        }
        if activeTabId == id {
            if tabs.isEmpty {
                activeTabId = nil
            } else {
                let nextIndex = min(idx, tabs.count - 1)
                activeTabId = tabs[nextIndex].id
            }
        }
        rebuildTabBar()
        if let activeTabId {
            selectTab(id: activeTabId)
        } else {
            syncSubBar()
            onAllTabsClosed?()
        }
        notifyTabsStateChanged()
    }

    func closeOtherTabs(keeping id: UUID) {
        let toRemove = tabs.filter { $0.id != id }.map(\.id)
        for tabId in toRemove {
            closeTab(id: tabId)
        }
    }

    func openDiff(focusFile: String? = nil) {
        _ = openTab(.diff)
        if let lastDiffReport {
            diffWebView.update(diffReport: lastDiffReport, focusFile: focusFile)
        } else {
            pendingFocusFile = focusFile
            reloadDiffAsync()
        }
    }

    func openFiles(at directoryPath: String? = nil) {
        if let dir = directoryPath, !dir.isEmpty {
            reloadFileTree(rootPath: dir)
            notifyTabsStateChanged()
        } else if fileRootPath.isEmpty && !currentCwd.isEmpty {
            reloadFileTree(rootPath: currentCwd)
        }
        _ = openTab(.files)
        syncSubBar()
    }

    func showFilePreview(path: String, lineRange: ClosedRange<Int>? = nil) {
        let existed = tabs.contains(where: { $0.kind == .preview(path) })
        _ = openTab(.preview(path))
        if existed || lineRange != nil {
            activeTab?.previewWebView?.update(filePreviewPath: path, lineRange: lineRange)
        }
    }

    func isCurrentThread(_ threadId: Int64?) -> Bool {
        guard let threadId, threadId > 0 else {
            return true
        }
        return threadId == currentThreadId
    }

    private func resolveBrowserThreadId(requestedThreadId: Int64?, tabId: String?) -> Int64 {
        if let requestedThreadId, requestedThreadId > 0 {
            return requestedThreadId
        }
        if let tabId, !tabId.isEmpty {
            for (tid, state) in paneStatesByThreadId {
                if state.tabs.contains(where: { $0.kind == .browser && $0.id.uuidString == tabId })
                {
                    return tid
                }
            }
        }
        return currentThreadId
    }

    private func materializeBackgroundPaneState(for threadId: Int64) -> ThreadRightPaneState {
        if let existing = paneStatesByThreadId[threadId] {
            return existing
        }
        let state = ThreadRightPaneState()
        paneStatesByThreadId[threadId] = state
        guard let saved = pendingPersistedPanes.removeValue(forKey: threadId) else {
            return state
        }
        isRestoringPaneState = true
        defer { isRestoringPaneState = false }
        if let savedRoot = saved.fileRootPath, Self.isExistingDirectory(savedRoot) {
            state.fileRootPath = savedRoot
        }
        var restoredIds: [UUID?] = []
        for savedTab in saved.tabs {
            switch savedTab.kind {
            case .diff:
                let entry = RightPaneTabEntry(
                    kind: .diff,
                    title: KasugaiRightPaneTabKind.diff.defaultTitle,
                    toolTip: "変更差分",
                    contentView: diffWebView
                )
                state.tabs.append(entry)
                restoredIds.append(entry.id)
            case .files:
                let entry = RightPaneTabEntry(
                    kind: .files,
                    title: KasugaiRightPaneTabKind.files.defaultTitle,
                    toolTip: "ファイル",
                    contentView: fileScrollView
                )
                state.tabs.append(entry)
                restoredIds.append(entry.id)
            case .preview:
                if let path = savedTab.path, !path.isEmpty,
                    FileManager.default.fileExists(atPath: path)
                {
                    let webView = SandboxedChatWebView(frame: .zero, mode: .diff)
                    webView.update(palette: palette)
                    webView.update(filePreviewPath: path)
                    webView.onOpenFileLink = { [weak self] target in
                        self?.onOpenFileLink?(target)
                    }
                    let entry = RightPaneTabEntry(
                        kind: .preview(path),
                        title: KasugaiRightPaneTabKind.preview(path).defaultTitle,
                        toolTip: path,
                        contentView: webView,
                        previewWebView: webView
                    )
                    state.tabs.append(entry)
                    restoredIds.append(entry.id)
                } else {
                    restoredIds.append(nil)
                }
            case .browser:
                let entry = makeBrowserTabEntry(forThreadId: threadId)
                if let savedTitle = savedTab.title, !savedTitle.isEmpty {
                    entry.title = savedTitle
                    entry.toolTip = savedTitle
                }
                if let browser = entry.browserView {
                    parkBackgroundBrowserView(browser)
                    if let savedURL = savedTab.url, !savedURL.isEmpty {
                        browser.restorePersistedURL(savedURL)
                    }
                }
                state.tabs.append(entry)
                restoredIds.append(entry.id)
            }
        }
        if saved.activeIndex >= 0,
            saved.activeIndex < restoredIds.count,
            let matched = restoredIds[saved.activeIndex]
        {
            state.activeTabId = matched
        } else {
            state.activeTabId = state.tabs.first?.id
        }
        return state
    }

    func browserTabsSummary(threadId: Int64? = nil) -> [BrowserTabInfo] {
        let targetId = resolveBrowserThreadId(requestedThreadId: threadId, tabId: nil)
        let state: ThreadRightPaneState
        if targetId == currentThreadId {
            state = activePaneState
        } else {
            state = materializeBackgroundPaneState(for: targetId)
        }
        return state.tabs.compactMap { entry in
            guard entry.kind == .browser, let browser = entry.browserView else {
                return nil
            }
            return BrowserTabInfo(
                tabId: entry.id.uuidString,
                title: entry.title,
                url: browser.currentURLString,
                active: entry.id == state.activeTabId
            )
        }
    }

    func ensureBrowserTab(
        threadId: Int64? = nil,
        id: String?,
        openNew: Bool
    ) -> (tabId: String, view: LocalPreviewBrowserView)? {
        let targetId = resolveBrowserThreadId(requestedThreadId: threadId, tabId: id)
        if targetId == currentThreadId {
            if !openNew {
                if let id,
                    let matched = tabs.first(where: {
                        $0.kind == .browser && $0.id.uuidString == id
                    }),
                    let browser = matched.browserView
                {
                    selectTab(id: matched.id)
                    return (matched.id.uuidString, browser)
                }
                if let active = activeTab, active.kind == .browser,
                    let browser = active.browserView
                {
                    return (active.id.uuidString, browser)
                }
                if let first = tabs.first(where: { $0.kind == .browser }),
                    let browser = first.browserView
                {
                    selectTab(id: first.id)
                    return (first.id.uuidString, browser)
                }
            }
            let createdId = openTab(.browser)
            guard let created = tabs.first(where: { $0.id == createdId }),
                let browser = created.browserView
            else {
                return nil
            }
            return (created.id.uuidString, browser)
        }

        let state = materializeBackgroundPaneState(for: targetId)
        if !openNew {
            if let id,
                let matched = state.tabs.first(where: {
                    $0.kind == .browser && $0.id.uuidString == id
                }),
                let browser = matched.browserView
            {
                state.activeTabId = matched.id
                parkBackgroundBrowserView(browser)
                notifyTabsStateChanged(for: targetId)
                return (matched.id.uuidString, browser)
            }
            if let activeId = state.activeTabId,
                let active = state.tabs.first(where: {
                    $0.id == activeId && $0.kind == .browser
                }),
                let browser = active.browserView
            {
                parkBackgroundBrowserView(browser)
                return (active.id.uuidString, browser)
            }
            if let first = state.tabs.first(where: { $0.kind == .browser }),
                let browser = first.browserView
            {
                state.activeTabId = first.id
                parkBackgroundBrowserView(browser)
                notifyTabsStateChanged(for: targetId)
                return (first.id.uuidString, browser)
            }
        }
        let created = makeBrowserTabEntry(forThreadId: targetId)
        guard let browser = created.browserView else {
            return nil
        }
        parkBackgroundBrowserView(browser)
        state.tabs.append(created)
        state.activeTabId = created.id
        notifyTabsStateChanged(for: targetId)
        return (created.id.uuidString, browser)
    }

    func selectBrowserTab(threadId: Int64? = nil, id: String) -> Bool {
        let targetId = resolveBrowserThreadId(requestedThreadId: threadId, tabId: id)
        if targetId == currentThreadId {
            guard
                let matched = tabs.first(where: { $0.kind == .browser && $0.id.uuidString == id })
            else {
                return false
            }
            selectTab(id: matched.id)
            return true
        }
        let state = materializeBackgroundPaneState(for: targetId)
        guard
            let matched = state.tabs.first(where: { $0.kind == .browser && $0.id.uuidString == id })
        else {
            return false
        }
        state.activeTabId = matched.id
        notifyTabsStateChanged(for: targetId)
        return true
    }

    func closeBrowserTab(threadId: Int64? = nil, id: String) -> Bool {
        let targetId = resolveBrowserThreadId(requestedThreadId: threadId, tabId: id)
        if targetId == currentThreadId {
            guard
                let matched = tabs.first(where: { $0.kind == .browser && $0.id.uuidString == id })
            else {
                return false
            }
            closeTab(id: matched.id)
            return true
        }
        let state = materializeBackgroundPaneState(for: targetId)
        guard
            let idx = state.tabs.firstIndex(where: {
                $0.kind == .browser && $0.id.uuidString == id
            })
        else {
            return false
        }
        let removed = state.tabs.remove(at: idx)
        removed.contentView.removeFromSuperview()
        if state.activeTabId == removed.id {
            if state.tabs.isEmpty {
                state.activeTabId = nil
            } else {
                state.activeTabId = state.tabs[min(idx, state.tabs.count - 1)].id
            }
        }
        notifyTabsStateChanged(for: targetId)
        return true
    }

    private func paneKey(forFactoryRunId runId: String) -> Int64 {
        if let existing = factoryPaneKeysByRunId[runId] {
            return existing
        }
        let assigned = nextFactoryPaneKey
        nextFactoryPaneKey -= 1
        factoryPaneKeysByRunId[runId] = assigned
        return assigned
    }

    private func parkOrHideCurrentPaneTabs() {
        guard let prevState = paneStatesByThreadId[currentThreadId] else {
            return
        }
        for tab in prevState.tabs {
            if let browser = tab.browserView {
                parkBackgroundBrowserView(browser)
            } else {
                tab.contentView.isHidden = true
                if tab.kind != .diff && tab.kind != .files {
                    tab.contentView.removeFromSuperview()
                }
            }
        }
    }

    func switchToFactoryRun(id runId: String, runDirectory: String) {
        let key = paneKey(forFactoryRunId: runId)
        if currentThreadId != key {
            parkOrHideCurrentPaneTabs()
            if currentThreadId == 0 {
                paneStatesByThreadId.removeValue(forKey: 0)
            }
            currentThreadId = key
            if tabs.isEmpty {
                rebuildTabBar()
                syncSubBar()
            } else {
                for tab in tabs {
                    mountContentViewIfNeeded(tab.contentView)
                }
                rebuildTabBar()
                if let targetId = activeTabId ?? tabs.first?.id {
                    selectTab(id: targetId, animated: false)
                } else {
                    syncSubBar()
                }
            }
        }
        isCurrentWorktree = false
        currentBranch = ""
        currentCwd = runDirectory
        if fileRootPath.isEmpty {
            fileRootPath = runDirectory
        }
        if !runDirectory.isEmpty && (fileRootNode == nil || fileRootNode?.url.path != fileRootPath)
        {
            reloadFileTree(rootPath: fileRootPath)
        }
        syncSubBar()
    }

    private func switchActivePaneState(to nextThreadId: Int64) {
        guard nextThreadId != currentThreadId else {
            return
        }
        let previousThreadId = currentThreadId
        if previousThreadId == 0 && nextThreadId > 0,
            paneStatesByThreadId[nextThreadId] == nil,
            pendingPersistedPanes[nextThreadId] == nil,
            let bootstrap = paneStatesByThreadId.removeValue(forKey: 0)
        {
            paneStatesByThreadId[nextThreadId] = bootstrap
            currentThreadId = nextThreadId
            return
        }
        parkOrHideCurrentPaneTabs()
        if previousThreadId == 0 {
            paneStatesByThreadId.removeValue(forKey: 0)
        }
        currentThreadId = nextThreadId
        if let saved = pendingPersistedPanes.removeValue(forKey: nextThreadId) {
            restorePersistedPane(saved, for: nextThreadId)
            return
        }
        if tabs.isEmpty {
            ensureDefaultTabIfEmpty()
        } else {
            for tab in tabs {
                mountContentViewIfNeeded(tab.contentView)
            }
            rebuildTabBar()
            if let targetId = activeTabId ?? tabs.first?.id {
                selectTab(id: targetId, animated: false)
            } else {
                syncSubBar()
            }
        }
    }

    func update(thread: KasugaiThread?, forceRefresh: Bool = false) {
        guard let thread else {
            switchActivePaneState(to: 0)
            currentCwd = ""
            isCurrentWorktree = false
            currentBranch = ""
            pathLabel.stringValue = ""
            resetWorktreeButton.isHidden = true
            reloadFileTree(rootPath: "")
            diffWebView.update(diffReport: nil)
            return
        }
        let workspace = thread.workspace
        isCurrentWorktree = workspace.mode == "git_worktree" && !workspace.branch.isEmpty
        currentBranch = workspace.branch

        let threadChanged = currentThreadId != thread.id
        let previousCwd = currentCwd
        let shouldReload =
            forceRefresh || threadChanged || currentCwd != workspace.effectiveCwd
        switchActivePaneState(to: thread.id)
        let cwdChanged = previousCwd != workspace.effectiveCwd
        currentCwd = workspace.effectiveCwd
        if !threadChanged && cwdChanged && (fileRootPath.isEmpty || fileRootPath == previousCwd) {
            fileRootPath = currentCwd
        }
        let effectiveFileRoot =
            Self.isExistingDirectory(fileRootPath) ? fileRootPath : currentCwd
        if threadChanged || cwdChanged || fileRootNode == nil
            || fileRootNode?.url.path != effectiveFileRoot
        {
            reloadFileTree(rootPath: effectiveFileRoot)
        }
        syncSubBar()
        if shouldReload {
            reloadDiffAsync()
        }
    }

    func reloadRendererAssets() {
        diffWebView.reloadRendererAssets()
        for tab in allTabsAcrossThreads {
            tab.previewWebView?.reloadRendererAssets()
        }
    }

    func reloadDiffAsync() {
        let cwd = currentCwd
        let threadId = currentThreadId
        guard !cwd.isEmpty, threadId > 0 else {
            return
        }
        refreshGeneration += 1
        let gen = refreshGeneration
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let report = GitWorkspace.computeDiff(in: cwd)
            DispatchQueue.main.async {
                guard let self, self.refreshGeneration == gen else {
                    return
                }
                self.lastDiffReport = report
                let focus = self.pendingFocusFile
                self.pendingFocusFile = nil
                self.diffWebView.update(diffReport: report, focusFile: focus)
                self.onDiffStatsComputed?(
                    threadId,
                    report.filesChanged,
                    report.insertions,
                    report.deletions
                )
                self.onDiffReportComputed?(threadId, report)
            }
        }
    }

    private func mountContentViewIfNeeded(_ view: NSView) {
        guard view.superview !== bodyContainer else {
            return
        }
        if view.superview != nil {
            view.removeFromSuperview()
        }
        view.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            view.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: bodyContainer.bottomAnchor),
        ])
    }

    private func rebuildTabBar() {
        for chip in tabChips {
            tabStack.removeArrangedSubview(chip)
            chip.removeFromSuperview()
        }
        tabChips.removeAll()

        for tab in tabs {
            let chip = RightPaneTabChipView(
                tabId: tab.id,
                symbol: tab.kind.symbolName,
                title: tab.title,
                toolTip: tab.toolTip
            )
            chip.onSelect = { [weak self] in
                self?.selectTab(id: tab.id)
            }
            chip.onClose = { [weak self] in
                self?.closeTab(id: tab.id)
            }
            chip.onCloseOthers = { [weak self] in
                self?.closeOtherTabs(keeping: tab.id)
            }
            tabChips.append(chip)
            tabStack.addArrangedSubview(chip)
        }
        syncTabChipsStyle()
    }

    private func syncTabChipsStyle() {
        let hasMultiple = tabs.count > 1
        for (idx, chip) in tabChips.enumerated() {
            guard let tab = tabs.first(where: { $0.id == chip.tabId }) else {
                continue
            }
            let isSelected = tab.id == activeTabId
            let nextIsSelected =
                idx + 1 < tabChips.count && tabChips[idx + 1].tabId == activeTabId
            let showSep = !isSelected && !nextIsSelected && idx + 1 < tabChips.count
            chip.toolTip = tab.toolTip
            chip.update(
                title: tab.title,
                isSelected: isSelected,
                showTrailingSeparator: showSep,
                hasOtherTabs: hasMultiple,
                theme: theme
            )
        }
    }

    private func setSubBarVisible(_ visible: Bool) {
        subBarContainer.isHidden = !visible
        bodyTopBelowHeader?.isActive = !visible
        bodyTopBelowSubBar?.isActive = visible
    }

    private func syncSubBar() {
        guard let activeTab else {
            createWorktreeButton.isHidden = true
            resetWorktreeButton.isHidden = true
            setSubBarVisible(false)
            return
        }
        switch activeTab.kind {
        case .diff:
            createWorktreeButton.isHidden = false
            resetWorktreeButton.isHidden = !isCurrentWorktree
            attachFileButton.isHidden = true
            setSubBarVisible(false)
        case .files:
            createWorktreeButton.isHidden = true
            resetWorktreeButton.isHidden = true
            attachFileButton.isHidden = false
            let activeRoot = fileRootPath.isEmpty ? currentCwd : fileRootPath
            if activeRoot == currentCwd {
                let dirName = URL(fileURLWithPath: activeRoot).lastPathComponent
                pathLabel.stringValue = dirName.isEmpty ? activeRoot : dirName
            } else {
                pathLabel.stringValue = activeRoot
            }
            pathLabel.toolTip = activeRoot
            setSubBarVisible(true)
        case .preview(let path):
            createWorktreeButton.isHidden = true
            resetWorktreeButton.isHidden = true
            attachFileButton.isHidden = false
            pathLabel.stringValue = path
            pathLabel.toolTip = path
            setSubBarVisible(true)
        case .browser:
            createWorktreeButton.isHidden = true
            resetWorktreeButton.isHidden = true
            attachFileButton.isHidden = true
            setSubBarVisible(false)
        }
    }

    private func reloadFileTree(rootPath: String) {
        fileRootPath = rootPath
        if rootPath.isEmpty {
            fileRootNode = nil
        } else {
            fileRootNode = WorkspaceFileNode(
                url: URL(fileURLWithPath: rootPath, isDirectory: true),
                isDirectory: true
            )
        }
        outlineView.reloadData()
    }

    @objc private func handleAddTabMenu() {
        let menu = NSMenu()

        let diffItem = NSMenuItem(
            title: "変更差分",
            action: #selector(handleAddDiffTab),
            keyEquivalent: ""
        )
        diffItem.target = self
        diffItem.image = NSImage(
            systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: nil)
        menu.addItem(diffItem)

        let filesItem = NSMenuItem(
            title: "ファイル",
            action: #selector(handleAddFilesTab),
            keyEquivalent: ""
        )
        filesItem.target = self
        filesItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        menu.addItem(filesItem)

        let browserItem = NSMenuItem(
            title: "ローカルブラウザ",
            action: #selector(handleAddBrowserTab),
            keyEquivalent: ""
        )
        browserItem.target = self
        browserItem.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        menu.addItem(browserItem)

        menu.addItem(.separator())

        let previewFileItem = NSMenuItem(
            title: "ファイルを開いてプレビュー…",
            action: #selector(handleOpenFilePreviewPanel),
            keyEquivalent: ""
        )
        previewFileItem.target = self
        previewFileItem.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        menu.addItem(previewFileItem)

        let point = NSPoint(x: 0, y: addTabButton.bounds.height + 4)
        menu.popUp(positioning: nil, at: point, in: addTabButton)
    }

    @objc private func handleAddDiffTab() {
        _ = openTab(.diff)
    }

    @objc private func handleAddFilesTab() {
        _ = openTab(.files)
    }

    @objc private func handleAddBrowserTab() {
        _ = openTab(.browser)
    }

    @objc private func handleOpenFilePreviewPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "開く"
        if !currentCwd.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: currentCwd, isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        showFilePreview(path: url.path)
    }

    @objc private func handleRefresh() {
        guard let activeTab else {
            return
        }
        switch activeTab.kind {
        case .diff:
            reloadDiffAsync()
        case .files:
            reloadFileTree(rootPath: fileRootPath.isEmpty ? currentCwd : fileRootPath)
        case .preview(let path):
            activeTab.previewWebView?.update(filePreviewPath: path)
        case .browser:
            activeTab.browserView?.reloadCurrentPage()
        }
    }

    @objc private func handleAttachFile() {
        guard let activeTab else {
            return
        }
        switch activeTab.kind {
        case .files:
            let row = outlineView.selectedRow
            if row >= 0, let node = outlineView.item(atRow: row) as? WorkspaceFileNode,
                !node.isDirectory
            {
                onAttachPreviewedFile?(node.url.path)
            }
        case .preview(let path):
            onAttachPreviewedFile?(path)
        case .diff, .browser:
            break
        }
    }

    func promptCreateWorktree() {
        handleCreateWorktree()
    }

    @objc private func handleCreateWorktree() {
        let alert = NSAlert()
        alert.messageText = "Worktree を作成"
        alert.informativeText = "新しいブランチ名とベース参照を入力してください。"
        alert.addButton(withTitle: "作成")
        alert.addButton(withTitle: "キャンセル")

        let branchField = NSTextField(frame: NSRect(x: 0, y: 30, width: 260, height: 24))
        branchField.placeholderString = "例: feat/task-name"
        let baseField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        baseField.stringValue = "HEAD"
        baseField.placeholderString = "ベース参照（例: HEAD）"

        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 58))
        accessory.addSubview(branchField)
        accessory.addSubview(baseField)
        alert.accessoryView = accessory
        alert.window.initialFirstResponder = branchField

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        let branch = branchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseRef = baseField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else {
            return
        }
        onCreateWorktree?(branch, baseRef.isEmpty ? "HEAD" : baseRef)
    }

    @objc private func handleResetWorktree() {
        onResetWorktree?()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? WorkspaceFileNode,
            !node.isDirectory
        else {
            return
        }
        let previewItem = NSMenuItem(
            title: "タブでプレビュー",
            action: #selector(handleContextPreviewFile(_:)),
            keyEquivalent: ""
        )
        previewItem.target = self
        previewItem.representedObject = node.url.path
        menu.addItem(previewItem)

        let attachItem = NSMenuItem(
            title: "入力欄に添付",
            action: #selector(handleContextAttachFile(_:)),
            keyEquivalent: ""
        )
        attachItem.target = self
        attachItem.representedObject = node.url.path
        menu.addItem(attachItem)
    }

    @objc private func handleContextPreviewFile(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else {
            return
        }
        showFilePreview(path: path)
    }

    @objc private func handleContextAttachFile(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else {
            return
        }
        onAttachPreviewedFile?(path)
    }

    @objc private func handleToggleRightPane() {
        onToggleRightPane?()
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return fileRootNode?.children.count ?? 0
        }
        return (item as? WorkspaceFileNode)?.children.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil, let root = fileRootNode {
            return root.children[index]
        }
        if let node = item as? WorkspaceFileNode {
            return node.children[index]
        }
        return WorkspaceFileNode(url: URL(fileURLWithPath: "/"), isDirectory: false)
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? WorkspaceFileNode)?.isDirectory ?? false
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        viewFor tableColumn: NSTableColumn?,
        item: Any
    ) -> NSView? {
        guard let node = item as? WorkspaceFileNode else {
            return nil
        }
        let cell = NSTableCellView()
        let iconView = NSImageView()
        iconView.image = NSWorkspace.shared.icon(forFile: node.url.path)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: node.name)
        label.font = .systemFont(ofSize: 12)
        label.textColor = theme.textPrimary
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(iconView)
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            iconView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 15),
            iconView.heightAnchor.constraint(equalToConstant: 15),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let row = outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? WorkspaceFileNode else {
            return
        }
        if !node.isDirectory {
            showFilePreview(path: node.url.path)
        }
    }
}
