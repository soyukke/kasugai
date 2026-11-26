import AppKit
import Foundation

private final class SidebarThreadCellView: NSTableCellView {
    var onTogglePin: (() -> Void)?
    var onToggleSettled: (() -> Void)?
    var onDelete: (() -> Void)?

    private let pillSurface = KasugaiSurfaceView()
    private let projectBadgeView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let settleButton = KasugaiFlatButton()
    private let pinButton = KasugaiFlatButton()
    private let deleteButton = KasugaiFlatButton()
    private let timeLabel = NSTextField(labelWithString: "")
    private let providerIconView = NSImageView()
    private let projectDirLabel = NSTextField(labelWithString: "")
    private let stateBadgeLabel = NSTextField(labelWithString: "")

    private var isSelectedRow = false
    private var isPinnedRow = false
    private var isSettledRow = false
    private var isWorkingRow = false
    private var isHovered = false
    private var theme = KasugaiThemeTokens.resolve(palette: .kasugai, isLight: false)
    private var trackingAreaRef: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func setup() {
        pillSurface.cornerRadius = 7
        pillSurface.translatesAutoresizingMaskIntoConstraints = false

        projectBadgeView.imageScaling = .scaleProportionallyDown
        projectBadgeView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        settleButton.buttonStyle = .ghost
        settleButton.horizontalPadding = 2
        settleButton.target = self
        settleButton.action = #selector(handleSettleTap)
        settleButton.translatesAutoresizingMaskIntoConstraints = false

        pinButton.buttonStyle = .ghost
        pinButton.horizontalPadding = 2
        pinButton.target = self
        pinButton.action = #selector(handlePinTap)
        pinButton.translatesAutoresizingMaskIntoConstraints = false

        deleteButton.buttonStyle = .ghost
        deleteButton.horizontalPadding = 2
        deleteButton.target = self
        deleteButton.action = #selector(handleDeleteTap)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let topRow = NSStackView(views: [
            titleLabel, settleButton, pinButton, deleteButton, timeLabel,
        ])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 2
        topRow.translatesAutoresizingMaskIntoConstraints = false

        providerIconView.imageScaling = .scaleProportionallyDown
        providerIconView.translatesAutoresizingMaskIntoConstraints = false

        projectDirLabel.font = .systemFont(ofSize: 10.5, weight: .regular)
        projectDirLabel.lineBreakMode = .byTruncatingMiddle
        projectDirLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let metaSpacer = NSView()
        metaSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        stateBadgeLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        stateBadgeLabel.lineBreakMode = .byTruncatingTail
        stateBadgeLabel.setContentHuggingPriority(.required, for: .horizontal)

        let bottomRow = NSStackView(views: [
            providerIconView,
            projectDirLabel,
            metaSpacer,
            stateBadgeLabel,
        ])
        bottomRow.orientation = .horizontal
        bottomRow.alignment = .centerY
        bottomRow.spacing = 5
        bottomRow.translatesAutoresizingMaskIntoConstraints = false

        pillSurface.addSubview(projectBadgeView)
        pillSurface.addSubview(topRow)
        pillSurface.addSubview(bottomRow)
        addSubview(pillSurface)

        NSLayoutConstraint.activate([
            pillSurface.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            pillSurface.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            pillSurface.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            pillSurface.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),

            projectBadgeView.leadingAnchor.constraint(
                equalTo: pillSurface.leadingAnchor, constant: 7),
            projectBadgeView.centerYAnchor.constraint(equalTo: pillSurface.centerYAnchor),
            projectBadgeView.widthAnchor.constraint(equalToConstant: 18),
            projectBadgeView.heightAnchor.constraint(equalToConstant: 18),

            topRow.topAnchor.constraint(equalTo: pillSurface.topAnchor, constant: 4),
            topRow.leadingAnchor.constraint(equalTo: projectBadgeView.trailingAnchor, constant: 7),
            topRow.trailingAnchor.constraint(equalTo: pillSurface.trailingAnchor, constant: -7),
            topRow.heightAnchor.constraint(equalToConstant: 16),

            settleButton.widthAnchor.constraint(equalToConstant: 16),
            settleButton.heightAnchor.constraint(equalToConstant: 16),

            pinButton.widthAnchor.constraint(equalToConstant: 16),
            pinButton.heightAnchor.constraint(equalToConstant: 16),

            deleteButton.widthAnchor.constraint(equalToConstant: 16),
            deleteButton.heightAnchor.constraint(equalToConstant: 16),

            providerIconView.widthAnchor.constraint(equalToConstant: 12),
            providerIconView.heightAnchor.constraint(equalToConstant: 12),

            bottomRow.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 1),
            bottomRow.leadingAnchor.constraint(
                equalTo: projectBadgeView.trailingAnchor, constant: 7),
            bottomRow.trailingAnchor.constraint(equalTo: pillSurface.trailingAnchor, constant: -7),
            bottomRow.heightAnchor.constraint(equalToConstant: 14),
        ])
    }

    func configure(
        thread: KasugaiThread,
        projectName: String,
        isSelected: Bool,
        isPinned: Bool,
        isSettled: Bool,
        theme: KasugaiThemeTokens
    ) {
        self.isSelectedRow = isSelected
        self.isPinnedRow = isPinned
        self.isSettledRow = isSettled
        self.isWorkingRow = thread.status == "running"
        self.theme = theme

        let dotColor: NSColor?
        let stateText: String
        let stateColor: NSColor
        if let running = thread.activities.last(where: { $0.status == "running" }) {
            dotColor = theme.accent
            stateText = running.title
            stateColor = theme.accent
        } else if thread.status == "running" {
            dotColor = theme.accent
            stateText = "作業中"
            stateColor = theme.accent
        } else if thread.status == "awaiting_approval" {
            dotColor = theme.warning
            stateText = "承認待ち"
            stateColor = theme.warning
        } else if thread.status == "failed" {
            dotColor = theme.danger
            stateText = "エラー"
            stateColor = theme.danger
        } else if !thread.queue.isEmpty {
            dotColor = nil
            stateText = "キュー \(thread.queue.count)"
            stateColor = theme.warning
        } else {
            dotColor = nil
            stateText = ""
            stateColor = theme.textMuted
        }

        let dirName =
            URL(fileURLWithPath: thread.workspace.effectiveCwd).lastPathComponent.isEmpty
            ? projectName
            : URL(fileURLWithPath: thread.workspace.effectiveCwd).lastPathComponent
        let labelBase = projectName.isEmpty ? dirName : projectName
        let dirDisplay: String
        if thread.workspace.mode == "git_worktree" && !thread.workspace.branch.isEmpty {
            dirDisplay = "\(labelBase) · \(thread.workspace.branch)"
        } else {
            dirDisplay = labelBase
        }

        projectBadgeView.image = KasugaiBrandIcons.projectBadge(
            name: labelBase,
            statusColor: dotColor,
            isLight: theme.isLight
        )
        projectBadgeView.alphaValue = isSettled && !isSelected ? 0.65 : 1.0
        projectBadgeView.toolTip = thread.workspace.effectiveCwd

        titleLabel.stringValue = thread.displayTitle
        titleLabel.font = .systemFont(ofSize: 12.5, weight: isSelected ? .semibold : .medium)
        if isSelected {
            titleLabel.textColor = theme.textPrimary
        } else if isSettled {
            titleLabel.textColor = theme.textMuted
        } else {
            titleLabel.textColor = theme.textSecondary
        }

        timeLabel.stringValue = KasugaiBrandIcons.relativeTimeLabel(fromMillis: thread.updatedAtMs)
        timeLabel.textColor = theme.textMuted

        providerIconView.image = KasugaiBrandIcons.providerIcon(for: thread.provider)
        providerIconView.alphaValue = isSettled && !isSelected ? 0.65 : 1.0
        providerIconView.toolTip = ProviderModelCatalog.shared.pillTitle(
            providerId: thread.provider,
            providerName: thread.providerName,
            model: thread.model
        )
        projectDirLabel.stringValue = dirDisplay
        projectDirLabel.textColor = theme.textMuted

        stateBadgeLabel.stringValue = stateText
        stateBadgeLabel.textColor = stateColor
        stateBadgeLabel.isHidden = stateText.isEmpty

        refreshHoverAndActionStyle()
    }

    private func refreshHoverAndActionStyle() {
        if isSelectedRow {
            pillSurface.fillColor = theme.surfaceSelected
        } else if isHovered {
            pillSurface.fillColor = theme.surfaceSelected.withAlphaComponent(
                theme.isLight ? 0.04 : 0.05
            )
        } else {
            pillSurface.fillColor = .clear
        }

        let showSettle = !isWorkingRow && (isSettledRow || isHovered)
        settleButton.isHidden = !showSettle
        settleButton.configureSymbol(
            isSettledRow ? "checkmark.circle.fill" : "checkmark.circle",
            pointSize: 11,
            weight: .medium
        )
        settleButton.customTintColor = isSettledRow ? theme.success : nil
        settleButton.apply(theme: theme)
        settleButton.toolTip = isSettledRow ? "アクティブに戻す" : "完了にする"

        let showPin = isPinnedRow || isHovered
        pinButton.isHidden = !showPin
        pinButton.configureSymbol(
            isPinnedRow ? "pin.fill" : "pin",
            pointSize: 9.5,
            weight: .medium
        )
        pinButton.customTintColor = isPinnedRow ? theme.accent : nil
        pinButton.apply(theme: theme)
        pinButton.toolTip = isPinnedRow ? "ピン留めを解除" : "ピン留め"

        deleteButton.isHidden = !isHovered
        deleteButton.configureSymbol("xmark", pointSize: 9.5, weight: .semibold)
        deleteButton.customTintColor = nil
        deleteButton.apply(theme: theme)
        deleteButton.toolTip = "スレッドを削除"
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
        refreshHoverAndActionStyle()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        refreshHoverAndActionStyle()
    }

    @objc private func handlePinTap() {
        onTogglePin?()
    }

    @objc private func handleSettleTap() {
        onToggleSettled?()
    }

    @objc private func handleDeleteTap() {
        onDelete?()
    }
}

private final class SidebarFactoryRunCellView: NSTableCellView {
    private let pillSurface = KasugaiSurfaceView()
    private let iconBadgeSurface = KasugaiSurfaceView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private let metaLabel = NSTextField(labelWithString: "")
    private let stateBadgeLabel = NSTextField(labelWithString: "")

    private var isSelectedRow = false
    private var isHovered = false
    private var theme = KasugaiThemeTokens.resolve(palette: .kasugai, isLight: false)
    private var trackingAreaRef: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func setup() {
        pillSurface.cornerRadius = 7
        pillSurface.translatesAutoresizingMaskIntoConstraints = false

        iconBadgeSurface.cornerRadius = 5
        iconBadgeSurface.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconBadgeSurface.addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        timeLabel.setContentHuggingPriority(.required, for: .horizontal)
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let topRow = NSStackView(views: [titleLabel, timeLabel])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 4
        topRow.translatesAutoresizingMaskIntoConstraints = false

        metaLabel.font = .systemFont(ofSize: 10.5, weight: .regular)
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let metaSpacer = NSView()
        metaSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        stateBadgeLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        stateBadgeLabel.lineBreakMode = .byTruncatingTail
        stateBadgeLabel.setContentHuggingPriority(.required, for: .horizontal)

        let bottomRow = NSStackView(views: [metaLabel, metaSpacer, stateBadgeLabel])
        bottomRow.orientation = .horizontal
        bottomRow.alignment = .centerY
        bottomRow.spacing = 5
        bottomRow.translatesAutoresizingMaskIntoConstraints = false

        pillSurface.addSubview(iconBadgeSurface)
        pillSurface.addSubview(topRow)
        pillSurface.addSubview(bottomRow)
        addSubview(pillSurface)

        NSLayoutConstraint.activate([
            pillSurface.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            pillSurface.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            pillSurface.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            pillSurface.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),

            iconBadgeSurface.leadingAnchor.constraint(
                equalTo: pillSurface.leadingAnchor, constant: 7),
            iconBadgeSurface.centerYAnchor.constraint(equalTo: pillSurface.centerYAnchor),
            iconBadgeSurface.widthAnchor.constraint(equalToConstant: 18),
            iconBadgeSurface.heightAnchor.constraint(equalToConstant: 18),

            iconView.centerXAnchor.constraint(equalTo: iconBadgeSurface.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBadgeSurface.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 11),
            iconView.heightAnchor.constraint(equalToConstant: 11),

            topRow.topAnchor.constraint(equalTo: pillSurface.topAnchor, constant: 4),
            topRow.leadingAnchor.constraint(
                equalTo: iconBadgeSurface.trailingAnchor, constant: 7),
            topRow.trailingAnchor.constraint(equalTo: pillSurface.trailingAnchor, constant: -7),
            topRow.heightAnchor.constraint(equalToConstant: 16),

            bottomRow.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 1),
            bottomRow.leadingAnchor.constraint(
                equalTo: iconBadgeSurface.trailingAnchor, constant: 7),
            bottomRow.trailingAnchor.constraint(equalTo: pillSurface.trailingAnchor, constant: -7),
            bottomRow.heightAnchor.constraint(equalToConstant: 14),
        ])
    }

    func configure(run: FactoryRunRecord, isSelected: Bool, theme: KasugaiThemeTokens) {
        self.isSelectedRow = isSelected
        self.theme = theme

        let stateColor: NSColor
        let symbolName: String
        switch run.status {
        case .draft:
            stateColor = theme.textMuted
            symbolName = "square.and.pencil"
        case .running:
            stateColor = theme.accent
            symbolName = "gearshape.2.fill"
        case .previewReady:
            stateColor = theme.warning
            symbolName = "play.fill"
        case .published:
            stateColor = theme.success
            symbolName = "checkmark.seal.fill"
        case .discarded:
            stateColor = theme.textMuted
            symbolName = "trash"
        case .failed:
            stateColor = theme.danger
            symbolName = "exclamationmark.triangle.fill"
        }

        iconBadgeSurface.fillColor = stateColor.withAlphaComponent(0.16)
        let cfg = NSImage.SymbolConfiguration(pointSize: 9.5, weight: .semibold)
        iconView.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: run.status.label
        )?.withSymbolConfiguration(cfg)
        iconView.contentTintColor = stateColor

        let prefix = run.parentRunId != nil ? "↳ " : ""
        titleLabel.stringValue = prefix + run.displayTitle
        titleLabel.font = .systemFont(ofSize: 12.5, weight: isSelected ? .semibold : .medium)
        titleLabel.textColor = isSelected ? theme.textPrimary : theme.textSecondary

        if run.status == .draft {
            timeLabel.stringValue = KasugaiBrandIcons.relativeTimeLabel(fromMillis: run.updatedAtMs)
            metaLabel.stringValue = run.blueprintName
        } else {
            timeLabel.stringValue = run.formattedElapsed()
            let iterText = run.iterations.isEmpty ? "開始" : "第 \(run.iterations.count) 周"
            let tokText = run.totalTokens > 0 ? " · \(run.formattedTokens)" : ""
            metaLabel.stringValue = "\(run.blueprintName) · \(iterText)\(tokText)"
        }
        timeLabel.textColor = theme.textMuted
        metaLabel.textColor = theme.textMuted

        stateBadgeLabel.stringValue = run.status.label
        stateBadgeLabel.textColor = stateColor
        refreshStyle()
    }

    private func refreshStyle() {
        if isSelectedRow {
            pillSurface.fillColor = theme.surfaceSelected
        } else if isHovered {
            pillSurface.fillColor = theme.surfaceSelected.withAlphaComponent(
                theme.isLight ? 0.04 : 0.05
            )
        } else {
            pillSurface.fillColor = .clear
        }
    }

    override func resetCursorRects() {
        if !KasugaiInteractiveMotion.isInteractionBlocked(for: self) {
            addCursorRect(bounds, cursor: .pointingHand)
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
}

private final class SidebarSectionHeaderCellView: NSTableCellView {
    var onToggle: (() -> Void)?
    var onTrailingAction: (() -> Void)?

    private let pillSurface = KasugaiSurfaceView()
    private let chevronView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let trailingActionButton = KasugaiFlatButton()
    private var isCollapsible = false
    private var isHovered = false
    private var isPressed = false
    private var baseAccentColor: NSColor?
    private var theme = KasugaiThemeTokens.resolve(palette: .kasugai, isLight: false)
    private var trackingAreaRef: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        pillSurface.cornerRadius = 6
        pillSurface.translatesAutoresizingMaskIntoConstraints = false

        chevronView.imageScaling = .scaleProportionallyDown
        chevronView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 10.5, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        trailingActionButton.buttonStyle = .ghost
        trailingActionButton.customHeight = 18
        trailingActionButton.horizontalPadding = 3
        trailingActionButton.isHidden = true
        trailingActionButton.target = self
        trailingActionButton.action = #selector(handleTrailingAction)
        trailingActionButton.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [
            chevronView, titleLabel, countLabel, spacer, trailingActionButton,
        ])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 4
        row.translatesAutoresizingMaskIntoConstraints = false

        pillSurface.addSubview(row)
        addSubview(pillSurface)
        NSLayoutConstraint.activate([
            pillSurface.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            pillSurface.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
            pillSurface.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 7),
            pillSurface.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),

            chevronView.widthAnchor.constraint(equalToConstant: 9),
            chevronView.heightAnchor.constraint(equalToConstant: 9),

            row.leadingAnchor.constraint(equalTo: pillSurface.leadingAnchor, constant: 6),
            row.trailingAnchor.constraint(equalTo: pillSurface.trailingAnchor, constant: -4),
            row.centerYAnchor.constraint(equalTo: pillSurface.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(
        title: String,
        count: Int?,
        collapsible: Bool,
        expanded: Bool,
        accentColor: NSColor?,
        trailingSymbol: String? = nil,
        trailingToolTip: String? = nil,
        theme: KasugaiThemeTokens
    ) {
        self.isCollapsible = collapsible
        self.baseAccentColor = accentColor
        self.theme = theme
        chevronView.isHidden = !collapsible
        if collapsible {
            let cfg = NSImage.SymbolConfiguration(pointSize: 8.5, weight: .semibold)
            chevronView.image = NSImage(
                systemSymbolName: expanded ? "chevron.down" : "chevron.right",
                accessibilityDescription: title
            )?.withSymbolConfiguration(cfg)
        }
        titleLabel.stringValue = title
        if let count {
            countLabel.stringValue = "\(count)"
            countLabel.isHidden = false
        } else {
            countLabel.isHidden = true
        }
        if let trailingSymbol {
            trailingActionButton.isHidden = false
            trailingActionButton.configureSymbol(trailingSymbol, pointSize: 10.5, weight: .semibold)
            trailingActionButton.toolTip = trailingToolTip
            trailingActionButton.apply(theme: theme)
        } else {
            trailingActionButton.isHidden = true
        }
        refreshHoverStyle()
        window?.invalidateCursorRects(for: self)
    }

    @objc private func handleTrailingAction() {
        onTrailingAction?()
    }

    private func refreshHoverStyle() {
        let activeHover = isCollapsible && isHovered
        if activeHover {
            pillSurface.fillColor = theme.surfaceSelected
            let hiColor = baseAccentColor ?? theme.textPrimary
            chevronView.contentTintColor = hiColor
            titleLabel.textColor = hiColor
            countLabel.textColor = theme.textSecondary
        } else {
            pillSurface.fillColor = .clear
            let normalColor = baseAccentColor ?? theme.textMuted
            chevronView.contentTintColor = normalColor
            titleLabel.textColor = normalColor
            countLabel.textColor = theme.textMuted
        }
    }

    override func resetCursorRects() {
        if isCollapsible && !KasugaiInteractiveMotion.isInteractionBlocked(for: self) {
            addCursorRect(bounds, cursor: .pointingHand)
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

    override func mouseEntered(with event: NSEvent) {
        guard !KasugaiInteractiveMotion.isInteractionBlocked(for: self) else {
            return
        }
        isHovered = true
        refreshHoverStyle()
        if isCollapsible {
            KasugaiInteractiveMotion.applyScale(to: pillSurface, scale: 1.02)
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
        refreshHoverStyle()
        KasugaiInteractiveMotion.applyScale(to: pillSurface, scale: 1.0)
    }

    override func mouseDown(with event: NSEvent) {
        if isCollapsible {
            isPressed = true
            KasugaiInteractiveMotion.applyScale(to: pillSurface, scale: 0.97)
        } else {
            super.mouseDown(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isCollapsible && isPressed {
            let local = convert(event.locationInWindow, from: nil)
            let inside = bounds.contains(local)
            isPressed = false
            KasugaiInteractiveMotion.applyScale(to: pillSurface, scale: inside ? 1.02 : 1.0)
            if inside {
                onToggle?()
            }
        } else {
            super.mouseUp(with: event)
        }
    }
}

private final class SidebarRateLimitFooterButton: NSControl {
    var isSelectedPill: Bool = false {
        didSet { applyColors() }
    }

    private let surface = KasugaiSurfaceView()
    private let fallbackIcon = NSImageView()
    private let miniRings = KasugaiMiniRingBadgeView()
    private var theme = KasugaiThemeTokens.resolve(palette: .kasugai, isLight: false)
    private var isHovered = false
    private var trackingAreaRef: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        surface.cornerRadius = 7
        surface.translatesAutoresizingMaskIntoConstraints = false

        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        fallbackIcon.image = NSImage(
            systemSymbolName: "gauge.with.dots.needle.67percent",
            accessibilityDescription: "レートリミット"
        )?.withSymbolConfiguration(cfg)
        fallbackIcon.imageScaling = .scaleProportionallyDown
        fallbackIcon.translatesAutoresizingMaskIntoConstraints = false

        miniRings.isHidden = true
        miniRings.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [fallbackIcon, miniRings])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 0
        row.translatesAutoresizingMaskIntoConstraints = false

        surface.addSubview(row)
        addSubview(surface)
        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),
            surface.heightAnchor.constraint(equalToConstant: 26),

            fallbackIcon.widthAnchor.constraint(equalToConstant: 15),
            fallbackIcon.heightAnchor.constraint(equalToConstant: 15),

            row.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 7),
            row.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -7),
            row.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
        ])
        toolTip = "レートリミット"
        applyColors()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func apply(theme: KasugaiThemeTokens) {
        self.theme = theme
        applyColors()
    }

    func update(snapshot: KasugaiRateLimitSnapshot) {
        var entries: [KasugaiMiniRingBadgeView.Entry] = []
        var tipParts: [String] = []
        if let claudeRem = snapshot.claude.tightestRemainingPercent {
            let color: NSColor =
                claudeRem <= 10
                ? theme.danger
                : (claudeRem <= 25 ? theme.warning : KasugaiThemeTokens.hex(0xD97757))
            entries.append(.init(color: color, remainingPercent: claudeRem))
            tipParts.append("Claude 残り \(Int(round(claudeRem)))%")
        }
        if let codexRem = snapshot.codex.tightestRemainingPercent {
            let color: NSColor =
                codexRem <= 10
                ? theme.danger
                : (codexRem <= 25 ? theme.warning : KasugaiThemeTokens.hex(0x10A37F))
            entries.append(.init(color: color, remainingPercent: codexRem))
            tipParts.append("Codex 残り \(Int(round(codexRem)))%")
        }
        if let agyRem = snapshot.antigravity.tightestRemainingPercent {
            let color: NSColor =
                agyRem <= 10
                ? theme.danger
                : (agyRem <= 25 ? theme.warning : KasugaiThemeTokens.hex(0x7C8CFF))
            entries.append(.init(color: color, remainingPercent: agyRem))
            tipParts.append("Antigravity 残り \(Int(round(agyRem)))%")
        }

        if entries.isEmpty {
            miniRings.isHidden = true
            fallbackIcon.isHidden = false
            toolTip = snapshot.isRefreshing ? "レートリミットを取得中…" : "レートリミット"
        } else {
            miniRings.entries = entries
            miniRings.isHidden = false
            fallbackIcon.isHidden = true
            toolTip = "レートリミット（\(tipParts.joined(separator: " · "))）"
        }
        applyColors()
    }

    private func applyColors() {
        let fg = isSelectedPill ? theme.textPrimary : theme.textSecondary
        surface.fillColor =
            isSelectedPill ? theme.surfaceSelected : (isHovered ? theme.surfaceSelected : .clear)
        fallbackIcon.contentTintColor = fg
        miniRings.trackColor = theme.borderSubtle.withAlphaComponent(theme.isLight ? 0.16 : 0.20)
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
        applyColors()
        KasugaiInteractiveMotion.applyScale(to: self, scale: 1.05)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        applyColors()
        KasugaiInteractiveMotion.applyScale(to: self, scale: 1.0)
    }

    override func mouseDown(with event: NSEvent) {
        KasugaiInteractiveMotion.applyScale(to: self, scale: 0.94)
    }

    override func mouseUp(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let inside = bounds.contains(local)
        KasugaiInteractiveMotion.applyScale(to: self, scale: inside ? 1.05 : 1.0)
        if inside {
            sendAction(action, to: target)
        }
    }
}

final class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate,
    NSMenuDelegate, NSTextFieldDelegate
{
    var onSelectProject: ((Int64) -> Void)?
    var onSelectThread: ((Int64) -> Void)?
    var onAddProject: (() -> Void)?
    var onCreateThread: ((Int64?) -> Void)?
    var onTogglePinThread: ((Int64) -> Void)?
    var onToggleSettledThread: ((Int64) -> Void)?
    var onDeleteThread: ((Int64) -> Void)?
    var onRenameThread: ((Int64, String) -> Void)?
    var onOpenRateLimits: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onToggleAppearance: (() -> Void)?
    var onCreateFactoryRun: (() -> Void)?
    var onSelectFactoryRun: ((String) -> Void)?
    var onDeleteFactoryRun: ((String) -> Void)?

    private enum ShelfKind {
        case factory
        case pinned
        case working
        case active
        case done
    }

    private enum SidebarRow {
        case section(title: String, count: Int?, kind: ShelfKind, expanded: Bool)
        case factoryRun(FactoryRunRecord)
        case thread(KasugaiThread, String)
    }

    private enum SidebarRowRenderKey: Equatable {
        case section(title: String, count: Int?, kind: ShelfKind, expanded: Bool)
        case factoryRun(
            id: String,
            parentRunId: String?,
            title: String,
            blueprintName: String,
            status: FactoryRunStatus,
            iterationCount: Int,
            relativeTime: String,
            isSelected: Bool
        )
        case thread(
            id: Int64,
            projectName: String,
            title: String,
            status: String,
            provider: String,
            model: String,
            cwd: String,
            workspaceMode: String,
            branch: String,
            queueCount: Int,
            relativeTime: String,
            isSelected: Bool,
            isPinned: Bool,
            isSettled: Bool
        )
    }

    private var rows: [SidebarRow] = []
    private var lastRenderedKeys: [SidebarRowRenderKey] = []
    private var lastSelectedRowIndex: Int?
    private var factoryRuns: [FactoryRunRecord] = []
    private var selectedFactoryRunId: String?
    private var isFactoryExpanded = true
    private var projects: [KasugaiProject] = []
    private var latestSnapshot: KasugaiCoreSnapshot?
    private var selectedProjectFilterId: Int64?
    private var pinnedIds: Set<Int64> = []
    private var settledIds: Set<Int64> = []
    private var deletedIds: Set<Int64> = []
    private var isWorkingExpanded = true
    private var isDoneExpanded = false
    private var activeThreadId: Int64 = 0
    private var activeProjectId: Int64 = 0
    private var isUpdatingSelection = false
    private var palette: KasugaiPalette = .kasugai
    private var theme: KasugaiThemeTokens = KasugaiThemeTokens.resolve(
        palette: .kasugai, isLight: false)
    private var latestRateLimits: KasugaiRateLimitSnapshot = .initial()
    private var timeRefreshTimer: Timer?

    private let rootSurface = KasugaiSurfaceView()
    let topDivider = KasugaiSurfaceView()
    private let bottomDivider = KasugaiSurfaceView()
    private let projectFilterButton = KasugaiFlatButton()
    private let searchToggleButton = KasugaiFlatButton()
    private let addProjectButton = KasugaiFlatButton()
    private let newThreadIconButton = KasugaiFlatButton()
    private let searchBarSurface = KasugaiSurfaceView()
    private let searchFieldIcon = NSImageView()
    private let searchField = NSTextField()
    private let searchClearButton = KasugaiFlatButton()
    private var scrollTopBelowDivider: NSLayoutConstraint?
    private var scrollTopBelowSearchBar: NSLayoutConstraint?
    private var isSearchOpen = false
    private var searchTransitionToken: Int = 0
    private var searchQuery = ""
    private let rateLimitButton = SidebarRateLimitFooterButton()
    private let appearanceButton = KasugaiFlatButton()
    private let settingsButton = KasugaiFlatButton()
    private var isSettingsOpen: Bool = false
    private var isRateLimitsOpen: Bool = false
    private let tableView = NSTableView()
    private let threadScrollView = NSScrollView()

    var settingsAnchorView: NSView {
        settingsButton
    }

    var rateLimitsAnchorView: NSView {
        rateLimitButton
    }

    func rowIndex(forThreadId threadId: Int64) -> Int? {
        rows.firstIndex { row in
            if case .thread(let thread, _) = row {
                return thread.id == threadId
            }
            return false
        }
    }

    deinit {
        timeRefreshTimer?.invalidate()
    }

    override func loadView() {
        rootSurface.frame = NSRect(x: 0, y: 0, width: 256, height: 640)

        projectFilterButton.buttonStyle = .ghost
        projectFilterButton.customHeight = 22
        projectFilterButton.horizontalPadding = 5
        projectFilterButton.configureSymbol(
            "line.3.horizontal.decrease", pointSize: 12, weight: .medium)
        projectFilterButton.toolTip = "プロジェクトで絞り込み"
        projectFilterButton.target = self
        projectFilterButton.action = #selector(handleProjectScopeClick)
        projectFilterButton.translatesAutoresizingMaskIntoConstraints = false

        searchToggleButton.buttonStyle = .ghost
        searchToggleButton.customHeight = 22
        searchToggleButton.horizontalPadding = 5
        searchToggleButton.configureSymbol("magnifyingglass", pointSize: 12, weight: .medium)
        searchToggleButton.toolTip = "スレッドを検索（⌘K）"
        searchToggleButton.target = self
        searchToggleButton.action = #selector(handleToggleSearch)
        searchToggleButton.translatesAutoresizingMaskIntoConstraints = false

        let topSpacer = NSView()
        topSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        var topBarViews: [NSView] = [
            projectFilterButton,
            searchToggleButton,
        ]
        if KasugaiRuntimePaths.isDevBundle {
            let devBadge = KasugaiSurfaceView()
            devBadge.cornerRadius = 5
            devBadge.fillColor = NSColor.systemOrange.withAlphaComponent(0.18)
            devBadge.strokeColor = NSColor.systemOrange.withAlphaComponent(0.45)
            devBadge.strokeWidth = 1
            devBadge.translatesAutoresizingMaskIntoConstraints = false

            let devLabel = NSTextField(labelWithString: "Dev")
            devLabel.font = .systemFont(ofSize: 10, weight: .semibold)
            devLabel.textColor = .systemOrange
            devLabel.translatesAutoresizingMaskIntoConstraints = false
            devBadge.addSubview(devLabel)
            NSLayoutConstraint.activate([
                devLabel.leadingAnchor.constraint(equalTo: devBadge.leadingAnchor, constant: 6),
                devLabel.trailingAnchor.constraint(equalTo: devBadge.trailingAnchor, constant: -6),
                devLabel.topAnchor.constraint(equalTo: devBadge.topAnchor, constant: 2),
                devLabel.bottomAnchor.constraint(equalTo: devBadge.bottomAnchor, constant: -2),
            ])
            devBadge.toolTip = "開発ビルド（データ保存先: Kasugai-Dev）"
            topBarViews.append(devBadge)
        }

        addProjectButton.buttonStyle = .ghost
        addProjectButton.customHeight = 22
        addProjectButton.horizontalPadding = 5
        addProjectButton.configureSymbol("folder.badge.plus", pointSize: 12, weight: .medium)
        addProjectButton.toolTip = "プロジェクトを追加…（⇧⌘O）"
        addProjectButton.target = self
        addProjectButton.action = #selector(handleAddProject)
        addProjectButton.translatesAutoresizingMaskIntoConstraints = false

        newThreadIconButton.buttonStyle = .ghost
        newThreadIconButton.customHeight = 22
        newThreadIconButton.horizontalPadding = 5
        newThreadIconButton.configureSymbol("square.and.pencil", pointSize: 12, weight: .medium)
        newThreadIconButton.toolTip = "新規スレッド（⌘N）"
        newThreadIconButton.target = self
        newThreadIconButton.action = #selector(handleCreateThreadActive)
        newThreadIconButton.translatesAutoresizingMaskIntoConstraints = false

        topBarViews.append(contentsOf: [
            topSpacer,
            addProjectButton,
            newThreadIconButton,
        ])
        let topBar = NSStackView(views: topBarViews)
        topBar.orientation = .horizontal
        topBar.alignment = .centerY
        topBar.spacing = 2
        topBar.translatesAutoresizingMaskIntoConstraints = false

        searchBarSurface.cornerRadius = 7
        searchBarSurface.strokeWidth = 1
        searchBarSurface.isHidden = true
        searchBarSurface.translatesAutoresizingMaskIntoConstraints = false

        let searchIconCfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        searchFieldIcon.image = NSImage(
            systemSymbolName: "magnifyingglass",
            accessibilityDescription: "検索"
        )?.withSymbolConfiguration(searchIconCfg)
        searchFieldIcon.imageScaling = .scaleProportionallyDown
        searchFieldIcon.translatesAutoresizingMaskIntoConstraints = false

        searchField.isBordered = false
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.font = .systemFont(ofSize: 12)
        searchField.placeholderString = "スレッドを検索…"
        searchField.lineBreakMode = .byTruncatingTail
        searchField.usesSingleLineMode = true
        searchField.delegate = self
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        searchField.translatesAutoresizingMaskIntoConstraints = false

        searchClearButton.buttonStyle = .ghost
        searchClearButton.horizontalPadding = 3
        searchClearButton.configureSymbol("xmark", pointSize: 9.5, weight: .semibold)
        searchClearButton.toolTip = "検索を閉じる"
        searchClearButton.target = self
        searchClearButton.action = #selector(handleCloseSearch)
        searchClearButton.translatesAutoresizingMaskIntoConstraints = false

        let searchRow = NSStackView(views: [searchFieldIcon, searchField, searchClearButton])
        searchRow.orientation = .horizontal
        searchRow.alignment = .centerY
        searchRow.spacing = 5
        searchRow.translatesAutoresizingMaskIntoConstraints = false
        searchBarSurface.addSubview(searchRow)

        topDivider.translatesAutoresizingMaskIntoConstraints = false

        let threadCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sidebar"))
        threadCol.resizingMask = .autoresizingMask
        tableView.addTableColumn(threadCol)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.rowSizeStyle = .custom
        tableView.dataSource = self
        tableView.delegate = self

        let contextMenu = NSMenu()
        contextMenu.delegate = self
        tableView.menu = contextMenu

        threadScrollView.documentView = tableView
        threadScrollView.hasVerticalScroller = true
        threadScrollView.autohidesScrollers = true
        threadScrollView.drawsBackground = false
        threadScrollView.borderType = .noBorder
        threadScrollView.translatesAutoresizingMaskIntoConstraints = false

        bottomDivider.translatesAutoresizingMaskIntoConstraints = false

        settingsButton.buttonStyle = .ghost
        settingsButton.horizontalPadding = 6
        settingsButton.configureSymbol("gearshape", pointSize: 13, weight: .medium)
        settingsButton.toolTip = "設定（⌘,）"
        settingsButton.target = self
        settingsButton.action = #selector(handleOpenSettings)

        rateLimitButton.target = self
        rateLimitButton.action = #selector(handleOpenRateLimits)
        rateLimitButton.translatesAutoresizingMaskIntoConstraints = false

        let footerSpacer = NSView()
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        appearanceButton.buttonStyle = .ghost
        appearanceButton.horizontalPadding = 6
        appearanceButton.configureSymbol("sun.max", pointSize: 13, weight: .medium)
        appearanceButton.toolTip = "ライト / ダークを切り替え"
        appearanceButton.target = self
        appearanceButton.action = #selector(handleToggleAppearance)

        let footerBar = NSStackView(views: [
            settingsButton,
            rateLimitButton,
            footerSpacer,
            appearanceButton,
        ])
        footerBar.orientation = .horizontal
        footerBar.alignment = .centerY
        footerBar.spacing = 4
        footerBar.translatesAutoresizingMaskIntoConstraints = false

        rootSurface.addSubview(topBar)
        rootSurface.addSubview(searchBarSurface)
        rootSurface.addSubview(topDivider)
        rootSurface.addSubview(threadScrollView)
        rootSurface.addSubview(bottomDivider)
        rootSurface.addSubview(footerBar)

        let scrollBelowDivider = threadScrollView.topAnchor.constraint(
            equalTo: topDivider.bottomAnchor, constant: 4)
        let scrollBelowSearch = threadScrollView.topAnchor.constraint(
            equalTo: searchBarSurface.bottomAnchor, constant: 4)
        scrollTopBelowDivider = scrollBelowDivider
        scrollTopBelowSearchBar = scrollBelowSearch

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: rootSurface.topAnchor),
            topBar.leadingAnchor.constraint(
                equalTo: rootSurface.leadingAnchor,
                constant: KasugaiChromeMetrics.trafficLightLeadingInset
            ),
            topBar.trailingAnchor.constraint(equalTo: rootSurface.trailingAnchor, constant: -8),
            topBar.heightAnchor.constraint(equalToConstant: KasugaiChromeMetrics.headerBarHeight),

            topDivider.topAnchor.constraint(
                equalTo: rootSurface.topAnchor, constant: KasugaiChromeMetrics.headerHeight),
            topDivider.leadingAnchor.constraint(equalTo: rootSurface.leadingAnchor),
            topDivider.trailingAnchor.constraint(equalTo: rootSurface.trailingAnchor),
            topDivider.heightAnchor.constraint(equalToConstant: 1),

            searchBarSurface.topAnchor.constraint(equalTo: topDivider.bottomAnchor, constant: 6),
            searchBarSurface.leadingAnchor.constraint(
                equalTo: rootSurface.leadingAnchor, constant: 8),
            searchBarSurface.trailingAnchor.constraint(
                equalTo: rootSurface.trailingAnchor, constant: -8),
            searchBarSurface.heightAnchor.constraint(equalToConstant: 26),

            searchFieldIcon.widthAnchor.constraint(equalToConstant: 12),
            searchFieldIcon.heightAnchor.constraint(equalToConstant: 12),
            searchRow.leadingAnchor.constraint(
                equalTo: searchBarSurface.leadingAnchor, constant: 8),
            searchRow.trailingAnchor.constraint(
                equalTo: searchBarSurface.trailingAnchor, constant: -4),
            searchRow.centerYAnchor.constraint(equalTo: searchBarSurface.centerYAnchor),

            scrollBelowDivider,
            threadScrollView.leadingAnchor.constraint(equalTo: rootSurface.leadingAnchor),
            threadScrollView.trailingAnchor.constraint(equalTo: rootSurface.trailingAnchor),
            threadScrollView.bottomAnchor.constraint(equalTo: bottomDivider.topAnchor),

            bottomDivider.leadingAnchor.constraint(equalTo: rootSurface.leadingAnchor),
            bottomDivider.trailingAnchor.constraint(equalTo: rootSurface.trailingAnchor),
            bottomDivider.bottomAnchor.constraint(equalTo: footerBar.topAnchor, constant: -5),
            bottomDivider.heightAnchor.constraint(equalToConstant: 1),

            footerBar.leadingAnchor.constraint(equalTo: rootSurface.leadingAnchor, constant: 8),
            footerBar.trailingAnchor.constraint(equalTo: rootSurface.trailingAnchor, constant: -8),
            footerBar.bottomAnchor.constraint(equalTo: rootSurface.bottomAnchor, constant: -7),
            footerBar.heightAnchor.constraint(equalToConstant: 28),
        ])

        self.view = rootSurface
        rootSurface.onAppearanceChanged = { [weak self] in
            self?.applyTheme()
        }
        applyTheme()

        if ProcessInfo.processInfo.environment["KASUGAI_SELF_TEST"] != "1" {
            timeRefreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) {
                [weak self] _ in
                self?.rebuildRows()
            }
        }
    }

    func update(palette: KasugaiPalette) {
        self.palette = palette
        applyTheme()
    }

    func update(rateLimits: KasugaiRateLimitSnapshot) {
        latestRateLimits = rateLimits
        rateLimitButton.update(snapshot: rateLimits)
    }

    func setSettingsOpen(_ open: Bool) {
        isSettingsOpen = open
        settingsButton.isSelectedPill = open
        settingsButton.apply(theme: theme)
    }

    func setRateLimitsOpen(_ open: Bool) {
        isRateLimitsOpen = open
        rateLimitButton.isSelectedPill = open
        rateLimitButton.apply(theme: theme)
    }

    func applyTheme() {
        theme = KasugaiThemeTokens.resolve(
            palette: palette,
            appearance: view.effectiveAppearance
        )
        rootSurface.fillColor = theme.sidebarBg
        topDivider.fillColor = theme.borderSubtle
        bottomDivider.fillColor = theme.borderSubtle
        searchBarSurface.fillColor = theme.surfaceBg
        searchBarSurface.strokeColor = theme.borderSubtle
        searchFieldIcon.contentTintColor = theme.textMuted
        searchField.textColor = theme.textPrimary
        searchClearButton.apply(theme: theme)
        searchToggleButton.isSelectedPill = isSearchOpen
        searchToggleButton.apply(theme: theme)
        addProjectButton.apply(theme: theme)
        newThreadIconButton.apply(theme: theme)
        rateLimitButton.isSelectedPill = isRateLimitsOpen
        rateLimitButton.apply(theme: theme)
        rateLimitButton.update(snapshot: latestRateLimits)
        appearanceButton.configureSymbol(
            theme.isLight ? "moon" : "sun.max",
            pointSize: 13,
            weight: .medium
        )
        appearanceButton.apply(theme: theme)
        settingsButton.isSelectedPill = isSettingsOpen
        settingsButton.apply(theme: theme)
        refreshProjectFilterButton()
        lastRenderedKeys.removeAll()
        lastSelectedRowIndex = nil
        rebuildRows()
    }

    func update(
        snapshot: KasugaiCoreSnapshot,
        pinnedThreadIds: [Int64]? = nil,
        settledThreadIds: [Int64]? = nil,
        deletedThreadIds: [Int64]? = nil
    ) {
        if let pinnedThreadIds {
            pinnedIds = Set(pinnedThreadIds)
        }
        if let settledThreadIds {
            settledIds = Set(settledThreadIds)
        }
        if let deletedThreadIds {
            deletedIds = Set(deletedThreadIds)
        }
        latestSnapshot = snapshot
        projects = snapshot.projects
        activeProjectId = snapshot.activeProjectId
        activeThreadId = snapshot.activeThreadId
        if let filter = selectedProjectFilterId,
            !projects.contains(where: { $0.id == filter })
        {
            selectedProjectFilterId = nil
        }

        refreshProjectFilterButton()
        rebuildRows()
    }

    func update(factoryRuns: [FactoryRunRecord], selectedFactoryRunId: String?) {
        self.factoryRuns = factoryRuns
        self.selectedFactoryRunId = selectedFactoryRunId
        rebuildRows()
    }

    func setSearchOpen(_ open: Bool, focus: Bool = true) {
        let wasOpen = isSearchOpen
        isSearchOpen = open
        searchTransitionToken &+= 1
        let token = searchTransitionToken
        searchToggleButton.isSelectedPill = isSearchOpen
        searchToggleButton.apply(theme: theme)

        if open {
            searchBarSurface.isHidden = false
            scrollTopBelowDivider?.isActive = false
            scrollTopBelowSearchBar?.isActive = true
            if !wasOpen {
                KasugaiInteractiveMotion.animateDirectionalEnter(
                    view: searchBarSurface,
                    direction: .fromTop,
                    distance: 10,
                    duration: 0.16
                )
            }
            if focus {
                view.window?.makeFirstResponder(searchField)
            }
        } else {
            searchQuery = ""
            searchField.stringValue = ""
            rebuildRows()
            if wasOpen {
                KasugaiInteractiveMotion.animateDirectionalExit(
                    view: searchBarSurface,
                    to: .fromTop,
                    distance: 8,
                    duration: 0.12
                ) { [weak self] in
                    guard let self, self.searchTransitionToken == token, !self.isSearchOpen else {
                        return
                    }
                    self.searchBarSurface.isHidden = true
                    self.searchBarSurface.layer?.opacity = 1
                    self.searchBarSurface.layer?.transform = CATransform3DIdentity
                    self.scrollTopBelowSearchBar?.isActive = false
                    self.scrollTopBelowDivider?.isActive = true
                }
            } else {
                searchBarSurface.isHidden = true
                scrollTopBelowSearchBar?.isActive = false
                scrollTopBelowDivider?.isActive = true
            }
        }
    }

    func setSearchQueryForTest(_ query: String) {
        if !isSearchOpen {
            setSearchOpen(true, focus: false)
        }
        searchField.stringValue = query
        searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        rebuildRows()
    }

    var visibleThreadCount: Int {
        rows.reduce(0) { acc, row in
            if case .thread = row {
                return acc + 1
            }
            return acc
        }
    }

    private func refreshProjectFilterButton() {
        if let filter = selectedProjectFilterId,
            let project = projects.first(where: { $0.id == filter })
        {
            projectFilterButton.isSelectedPill = true
            projectFilterButton.customTintColor = theme.accent
            projectFilterButton.toolTip = "プロジェクト絞り込み中: \(project.name)"
        } else {
            projectFilterButton.isSelectedPill = false
            projectFilterButton.customTintColor = nil
            projectFilterButton.toolTip = "プロジェクトで絞り込み"
        }
        projectFilterButton.apply(theme: theme)
    }

    private func rebuildRows() {
        guard let snapshot = latestSnapshot else {
            rows = []
            lastRenderedKeys.removeAll()
            lastSelectedRowIndex = nil
            tableView.reloadData()
            return
        }
        let projectNameById = Dictionary(
            uniqueKeysWithValues: snapshot.projects.map { ($0.id, $0.name) }
        )
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSearching = !trimmedQuery.isEmpty

        let filtered = snapshot.threads.filter { thread in
            if deletedIds.contains(thread.id) {
                return false
            }
            if let filter = selectedProjectFilterId, thread.projectId != filter {
                return false
            }
            if isSearching {
                let projectName = projectNameById[thread.projectId] ?? ""
                if thread.displayTitle.localizedCaseInsensitiveContains(trimmedQuery)
                    || projectName.localizedCaseInsensitiveContains(trimmedQuery)
                    || thread.workspace.effectiveCwd.localizedCaseInsensitiveContains(trimmedQuery)
                    || thread.workspace.branch.localizedCaseInsensitiveContains(trimmedQuery)
                    || thread.messages.contains(where: {
                        $0.text.localizedCaseInsensitiveContains(trimmedQuery)
                    })
                {
                    return true
                }
                return false
            }
            return true
        }
        let sorted = filtered.sorted { lhs, rhs in
            if lhs.updatedAtMs != rhs.updatedAtMs {
                return lhs.updatedAtMs > rhs.updatedAtMs
            }
            return lhs.id > rhs.id
        }

        var pinned: [KasugaiThread] = []
        var working: [KasugaiThread] = []
        var active: [KasugaiThread] = []
        var done: [KasugaiThread] = []

        for thread in sorted {
            if pinnedIds.contains(thread.id) {
                pinned.append(thread)
            } else if thread.status == "running" {
                working.append(thread)
            } else if settledIds.contains(thread.id) {
                done.append(thread)
            } else {
                active.append(thread)
            }
        }

        var built: [SidebarRow] = []
        let filteredFactoryRuns: [FactoryRunRecord]
        if isSearching {
            filteredFactoryRuns = factoryRuns.filter { run in
                run.displayTitle.localizedCaseInsensitiveContains(trimmedQuery)
                    || run.prompt.localizedCaseInsensitiveContains(trimmedQuery)
                    || run.status.label.localizedCaseInsensitiveContains(trimmedQuery)
            }
        } else {
            filteredFactoryRuns = factoryRuns
        }
        let showFactoryExpanded = isFactoryExpanded || isSearching
        if !isSearching || !filteredFactoryRuns.isEmpty {
            built.append(
                .section(
                    title: "工場",
                    count: filteredFactoryRuns.isEmpty ? nil : filteredFactoryRuns.count,
                    kind: .factory,
                    expanded: showFactoryExpanded
                )
            )
            if showFactoryExpanded {
                for run in filteredFactoryRuns {
                    built.append(.factoryRun(run))
                }
            } else if let selectedId = selectedFactoryRunId,
                let selectedRun = filteredFactoryRuns.first(where: { $0.id == selectedId })
            {
                built.append(.factoryRun(selectedRun))
            }
        }

        if !pinned.isEmpty {
            built.append(
                .section(title: "ピン留め", count: pinned.count, kind: .pinned, expanded: true))
            for thread in pinned {
                built.append(.thread(thread, projectNameById[thread.projectId] ?? ""))
            }
        }

        if !active.isEmpty {
            if !pinned.isEmpty || !built.isEmpty {
                built.append(
                    .section(title: "スレッド", count: active.count, kind: .active, expanded: true))
            }
            for thread in active {
                built.append(.thread(thread, projectNameById[thread.projectId] ?? ""))
            }
        }

        let showWorkingExpanded = isWorkingExpanded || isSearching
        if !working.isEmpty {
            built.append(
                .section(
                    title: "作業中",
                    count: working.count,
                    kind: .working,
                    expanded: showWorkingExpanded
                )
            )
            if showWorkingExpanded {
                for thread in working {
                    built.append(.thread(thread, projectNameById[thread.projectId] ?? ""))
                }
            } else if selectedFactoryRunId == nil,
                let selected = working.first(where: { $0.id == activeThreadId })
            {
                built.append(.thread(selected, projectNameById[selected.projectId] ?? ""))
            }
        }

        let showDoneExpanded = isDoneExpanded || isSearching
        if !done.isEmpty {
            built.append(
                .section(
                    title: "完了",
                    count: done.count,
                    kind: .done,
                    expanded: showDoneExpanded
                )
            )
            if showDoneExpanded {
                for thread in done {
                    built.append(.thread(thread, projectNameById[thread.projectId] ?? ""))
                }
            } else if selectedFactoryRunId == nil,
                let selected = done.first(where: { $0.id == activeThreadId })
            {
                built.append(.thread(selected, projectNameById[selected.projectId] ?? ""))
            }
        }

        rows = built

        let selectedIndex: Int?
        if let selectedRunId = selectedFactoryRunId {
            selectedIndex = rows.firstIndex(where: { row in
                if case .factoryRun(let run) = row {
                    return run.id == selectedRunId
                }
                return false
            })
        } else {
            selectedIndex = rows.firstIndex(where: { row in
                if case .thread(let thread, _) = row {
                    return thread.id == activeThreadId
                }
                return false
            })
        }

        let nextRenderKeys: [SidebarRowRenderKey] = rows.map { row in
            switch row {
            case .section(let title, let count, let kind, let expanded):
                return .section(title: title, count: count, kind: kind, expanded: expanded)
            case .factoryRun(let run):
                return .factoryRun(
                    id: run.id,
                    parentRunId: run.parentRunId,
                    title: run.displayTitle,
                    blueprintName: run.blueprintName,
                    status: run.status,
                    iterationCount: run.iterations.count,
                    relativeTime: KasugaiBrandIcons.relativeTimeLabel(fromMillis: run.updatedAtMs),
                    isSelected: run.id == selectedFactoryRunId
                )
            case .thread(let thread, let projectName):
                return .thread(
                    id: thread.id,
                    projectName: projectName,
                    title: thread.displayTitle,
                    status: thread.status,
                    provider: thread.provider,
                    model: thread.model,
                    cwd: thread.workspace.effectiveCwd,
                    workspaceMode: thread.workspace.mode,
                    branch: thread.workspace.branch,
                    queueCount: thread.queue.count,
                    relativeTime: KasugaiBrandIcons.relativeTimeLabel(
                        fromMillis: thread.updatedAtMs
                    ),
                    isSelected: selectedFactoryRunId == nil && thread.id == activeThreadId,
                    isPinned: pinnedIds.contains(thread.id),
                    isSettled: settledIds.contains(thread.id)
                )
            }
        }

        if nextRenderKeys == lastRenderedKeys && selectedIndex == lastSelectedRowIndex {
            return
        }
        lastRenderedKeys = nextRenderKeys
        lastSelectedRowIndex = selectedIndex

        isUpdatingSelection = true
        tableView.reloadData()
        if let selectedIndex {
            tableView.selectRowIndexes(
                IndexSet(integer: selectedIndex), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }
        isUpdatingSelection = false
    }

    @objc private func handleToggleSearch() {
        setSearchOpen(!isSearchOpen)
    }

    @objc private func handleCloseSearch() {
        setSearchOpen(false)
    }

    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSTextField) === searchField else {
            return
        }
        searchQuery = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        rebuildRows()
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        guard control === searchField else {
            return false
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            setSearchOpen(false)
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if let first = rows.first(where: {
                if case .thread = $0 {
                    return true
                }
                return false
            }), case .thread(let thread, _) = first {
                onSelectThread?(thread.id)
                return true
            }
        }
        return false
    }

    @objc private func handleProjectScopeClick() {
        let menu = NSMenu()
        let allItem = NSMenuItem(
            title: "すべてのプロジェクト",
            action: #selector(handleSelectAllProjects),
            keyEquivalent: ""
        )
        allItem.target = self
        allItem.state = selectedProjectFilterId == nil ? .on : .off
        menu.addItem(allItem)
        if !projects.isEmpty {
            menu.addItem(.separator())
        }
        for project in projects {
            let item = NSMenuItem(
                title: project.name,
                action: #selector(handleSelectProjectMenuItem(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = project.id
            item.toolTip = project.rootPath
            item.state = selectedProjectFilterId == project.id ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let addItem = NSMenuItem(
            title: "プロジェクトを追加…",
            action: #selector(handleAddProject),
            keyEquivalent: ""
        )
        addItem.target = self
        menu.addItem(addItem)

        let point = NSPoint(x: 0, y: projectFilterButton.bounds.height + 4)
        menu.popUp(positioning: nil, at: point, in: projectFilterButton)
    }

    @objc private func handleSelectAllProjects() {
        selectedProjectFilterId = nil
        refreshProjectFilterButton()
        rebuildRows()
    }

    @objc private func handleSelectProjectMenuItem(_ sender: NSMenuItem) {
        guard let projectId = sender.representedObject as? Int64 else {
            return
        }
        selectedProjectFilterId = projectId
        refreshProjectFilterButton()
        rebuildRows()
        onSelectProject?(projectId)
    }

    @objc private func handleAddProject() {
        onAddProject?()
    }

    @objc private func handleCreateThreadActive() {
        onCreateThread?(selectedProjectFilterId)
    }

    @objc private func handleOpenRateLimits() {
        onOpenRateLimits?()
    }

    @objc private func handleOpenSettings() {
        onOpenSettings?()
    }

    @objc private func handleToggleAppearance() {
        onToggleAppearance?()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = tableView.clickedRow
        guard row >= 0, row < rows.count else {
            return
        }
        if case .factoryRun(let run) = rows[row] {
            let deleteItem = NSMenuItem(
                title: "削除",
                action: #selector(handleContextDeleteFactoryRun(_:)),
                keyEquivalent: ""
            )
            deleteItem.target = self
            deleteItem.representedObject = run.id
            menu.addItem(deleteItem)
            return
        }
        guard case .thread(let thread, _) = rows[row] else {
            return
        }
        let isSettled = settledIds.contains(thread.id)
        if thread.status != "running" {
            let settleItem = NSMenuItem(
                title: isSettled ? "アクティブに戻す" : "完了にする",
                action: #selector(handleContextToggleSettled(_:)),
                keyEquivalent: ""
            )
            settleItem.target = self
            settleItem.representedObject = thread.id
            menu.addItem(settleItem)
        }

        let isPinned = pinnedIds.contains(thread.id)
        let pinItem = NSMenuItem(
            title: isPinned ? "ピン留めを解除" : "ピン留め",
            action: #selector(handleContextTogglePin(_:)),
            keyEquivalent: ""
        )
        pinItem.target = self
        pinItem.representedObject = thread.id
        menu.addItem(pinItem)

        menu.addItem(.separator())

        let renameItem = NSMenuItem(
            title: "名前を変更…",
            action: #selector(handleContextRename(_:)),
            keyEquivalent: ""
        )
        renameItem.target = self
        renameItem.representedObject = thread
        menu.addItem(renameItem)

        menu.addItem(.separator())

        let deleteItem = NSMenuItem(
            title: "削除",
            action: #selector(handleContextDeleteThread(_:)),
            keyEquivalent: ""
        )
        deleteItem.target = self
        deleteItem.representedObject = thread.id
        menu.addItem(deleteItem)
    }

    @objc private func handleContextDeleteThread(_ sender: NSMenuItem) {
        guard let threadId = sender.representedObject as? Int64 else {
            return
        }
        onDeleteThread?(threadId)
    }

    @objc private func handleContextDeleteFactoryRun(_ sender: NSMenuItem) {
        guard let runId = sender.representedObject as? String else {
            return
        }
        onDeleteFactoryRun?(runId)
    }

    @objc private func handleContextToggleSettled(_ sender: NSMenuItem) {
        guard let threadId = sender.representedObject as? Int64 else {
            return
        }
        onToggleSettledThread?(threadId)
    }

    @objc private func handleContextTogglePin(_ sender: NSMenuItem) {
        guard let threadId = sender.representedObject as? Int64 else {
            return
        }
        onTogglePinThread?(threadId)
    }

    @objc private func handleContextRename(_ sender: NSMenuItem) {
        guard let thread = sender.representedObject as? KasugaiThread else {
            return
        }
        let alert = NSAlert()
        alert.messageText = "スレッド名を変更"
        alert.informativeText = "新しいスレッド名を入力してください。"
        alert.addButton(withTitle: "変更")
        alert.addButton(withTitle: "キャンセル")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = thread.displayTitle
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        let nextTitle = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nextTitle.isEmpty else {
            return
        }
        onRenameThread?(thread.id, nextTitle)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        rows.count
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        if case .section = rows[row] {
            return false
        }
        return true
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        switch rows[row] {
        case .section:
            return 22
        case .factoryRun:
            return 40
        case .thread:
            return 40
        }
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int)
        -> NSView?
    {
        switch rows[row] {
        case .section(let title, let count, let kind, let expanded):
            let cell = SidebarSectionHeaderCellView()
            let collapsible = kind == .factory || kind == .working || kind == .done
            let accentColor: NSColor?
            if kind == .factory || kind == .working {
                accentColor = theme.accent
            } else {
                accentColor = nil
            }
            cell.configure(
                title: title,
                count: count,
                collapsible: collapsible,
                expanded: expanded,
                accentColor: accentColor,
                trailingSymbol: kind == .factory ? "plus" : nil,
                trailingToolTip: kind == .factory ? "新規製造" : nil,
                theme: theme
            )
            if kind == .factory {
                cell.onToggle = { [weak self] in
                    self?.isFactoryExpanded.toggle()
                    self?.rebuildRows()
                }
                cell.onTrailingAction = { [weak self] in
                    self?.onCreateFactoryRun?()
                }
            } else if kind == .working {
                cell.onToggle = { [weak self] in
                    self?.isWorkingExpanded.toggle()
                    self?.rebuildRows()
                }
            } else if kind == .done {
                cell.onToggle = { [weak self] in
                    self?.isDoneExpanded.toggle()
                    self?.rebuildRows()
                }
            }
            return cell

        case .factoryRun(let run):
            let cell = SidebarFactoryRunCellView()
            cell.configure(
                run: run,
                isSelected: run.id == selectedFactoryRunId,
                theme: theme
            )
            return cell

        case .thread(let thread, let projectName):
            let cell = SidebarThreadCellView()
            cell.configure(
                thread: thread,
                projectName: projectName,
                isSelected: selectedFactoryRunId == nil && thread.id == activeThreadId,
                isPinned: pinnedIds.contains(thread.id),
                isSettled: settledIds.contains(thread.id),
                theme: theme
            )
            cell.onTogglePin = { [weak self] in
                self?.onTogglePinThread?(thread.id)
            }
            cell.onToggleSettled = { [weak self] in
                self?.onToggleSettledThread?(thread.id)
            }
            cell.onDelete = { [weak self] in
                self?.onDeleteThread?(thread.id)
            }
            return cell
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isUpdatingSelection else {
            return
        }
        let row = tableView.selectedRow
        guard row >= 0, row < rows.count else {
            return
        }
        switch rows[row] {
        case .factoryRun(let run):
            onSelectFactoryRun?(run.id)
        case .thread(let thread, _):
            onSelectThread?(thread.id)
        case .section:
            break
        }
    }
}
