import AppKit
import Foundation

private final class ApprovalBannerView: NSView {
    var onApprove: (() -> Void)?
    var onDeny: (() -> Void)?

    private let surface = KasugaiSurfaceView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(wrappingLabelWithString: "")
    private let approveButton = KasugaiFlatButton()
    private let denyButton = KasugaiFlatButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        surface.cornerRadius = 12
        surface.strokeWidth = 1
        surface.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        summaryLabel.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        summaryLabel.maximumNumberOfLines = 3
        summaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let textStack = NSStackView(views: [titleLabel, summaryLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        denyButton.buttonStyle = .pill
        denyButton.horizontalPadding = 10
        denyButton.title = "拒否"
        denyButton.target = self
        denyButton.action = #selector(handleDeny)

        approveButton.buttonStyle = .circlePrimary
        approveButton.horizontalPadding = 12
        approveButton.title = "許可"
        approveButton.keyEquivalent = "\r"
        approveButton.target = self
        approveButton.action = #selector(handleApprove)

        let row = NSStackView(views: [textStack, denyButton, approveButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        surface.addSubview(row)
        addSubview(surface)

        let widthCap = surface.widthAnchor.constraint(lessThanOrEqualToConstant: 760)
        let idealWidth = surface.widthAnchor.constraint(equalToConstant: 760)
        idealWidth.priority = NSLayoutConstraint.Priority(240)

        NSLayoutConstraint.activate([
            surface.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            surface.centerXAnchor.constraint(equalTo: centerXAnchor),
            surface.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            surface.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
            widthCap,
            idealWidth,

            row.topAnchor.constraint(equalTo: surface.topAnchor, constant: 10),
            row.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -14),
            row.bottomAnchor.constraint(equalTo: surface.bottomAnchor, constant: -10),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func apply(theme: KasugaiThemeTokens) {
        layer?.backgroundColor = theme.canvasBg.cgColor
        surface.fillColor = theme.warning.withAlphaComponent(0.11)
        surface.strokeColor = theme.warning.withAlphaComponent(0.32)
        titleLabel.textColor = theme.warning
        summaryLabel.textColor = theme.textPrimary
        denyButton.apply(theme: theme)
        approveButton.apply(theme: theme)
    }

    func update(approval: KasugaiPendingApproval?) {
        guard let approval, approval.active else {
            isHidden = true
            return
        }
        let wasHidden = isHidden
        isHidden = false
        titleLabel.stringValue = "ツール実行の承認待ち: \(approval.toolName)"
        summaryLabel.stringValue = approval.summary
        if wasHidden {
            KasugaiInteractiveMotion.animateDirectionalEnter(
                view: surface,
                direction: .fromBottom,
                distance: 10,
                duration: 0.18
            )
        }
    }

    @objc private func handleApprove() {
        onApprove?()
    }

    @objc private func handleDeny() {
        onDeny?()
    }
}

private struct ExternalEditorOption {
    let label: String
    let openTitle: String
    let appPath: String?
}

private enum ExternalEditorCatalog {
    private static let preferredKey = "kasugai.preferredEditorPath"

    private static let candidates: [(name: String, appPath: String)] = [
        ("Antigravity IDE", "/Applications/Antigravity IDE.app"),
        ("Antigravity", "/Applications/Antigravity.app"),
        ("Cursor", "/Applications/Cursor.app"),
        ("VS Code", "/Applications/Visual Studio Code.app"),
        ("Zed", "/Applications/Zed.app"),
        ("Ghostty", "/Applications/Ghostty.app"),
        ("ターミナル", "/System/Applications/Utilities/Terminal.app"),
    ]

    static func installedEditors() -> [ExternalEditorOption] {
        let fm = FileManager.default
        var list: [ExternalEditorOption] = []
        for item in candidates where fm.fileExists(atPath: item.appPath) {
            list.append(
                ExternalEditorOption(
                    label: item.name,
                    openTitle: "\(item.name) で開く",
                    appPath: item.appPath
                )
            )
        }
        list.append(
            ExternalEditorOption(
                label: "Finder",
                openTitle: "Finder で開く",
                appPath: nil
            )
        )
        return list
    }

    static func preferredEditor() -> ExternalEditorOption {
        let list = installedEditors()
        if let saved = UserDefaults.standard.string(forKey: preferredKey) {
            if saved == "finder", let finder = list.first(where: { $0.appPath == nil }) {
                return finder
            }
            if let matched = list.first(where: { $0.appPath == saved }) {
                return matched
            }
        }
        return list.first
            ?? ExternalEditorOption(label: "Finder", openTitle: "Finder で開く", appPath: nil)
    }

    static func savePreferred(appPath: String?) {
        UserDefaults.standard.set(appPath ?? "finder", forKey: preferredKey)
    }
}

private final class DetailsCardRowControl: NSControl {
    private let surface = KasugaiSurfaceView()
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let addLabel = NSTextField(labelWithString: "")
    private let delLabel = NSTextField(labelWithString: "")
    private let fallbackLabel = NSTextField(labelWithString: "")
    private let chevronView = NSImageView()
    private var theme = KasugaiThemeTokens.resolve(palette: .kasugai, isLight: false)
    private var isAccented = false
    private var isMutedTitle = false
    private var isHovered = false
    private var isPressed = false
    private var trackingAreaRef: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultLow, for: .horizontal)

        surface.cornerRadius = 8
        surface.translatesAutoresizingMaskIntoConstraints = false

        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleField.font = .systemFont(ofSize: 12.5, weight: .medium)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        addLabel.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        addLabel.isHidden = true
        addLabel.setContentHuggingPriority(.required, for: .horizontal)
        addLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        delLabel.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        delLabel.isHidden = true
        delLabel.setContentHuggingPriority(.required, for: .horizontal)
        delLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        fallbackLabel.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        fallbackLabel.isHidden = true
        fallbackLabel.setContentHuggingPriority(.required, for: .horizontal)
        fallbackLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let chevCfg = NSImage.SymbolConfiguration(pointSize: 9.5, weight: .semibold)
        chevronView.image = NSImage(
            systemSymbolName: "chevron.down",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(chevCfg)
        chevronView.imageScaling = .scaleProportionallyDown
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        chevronView.setContentHuggingPriority(.required, for: .horizontal)
        chevronView.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [
            iconView,
            titleField,
            spacer,
            addLabel,
            delLabel,
            fallbackLabel,
            chevronView,
        ])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.setCustomSpacing(5, after: addLabel)
        row.translatesAutoresizingMaskIntoConstraints = false

        surface.addSubview(row)
        addSubview(surface)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),

            iconView.widthAnchor.constraint(equalToConstant: 15),
            iconView.heightAnchor.constraint(equalToConstant: 15),

            chevronView.widthAnchor.constraint(equalToConstant: 11),
            chevronView.heightAnchor.constraint(equalToConstant: 11),

            row.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -10),
            row.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(
        symbol: String,
        title: String,
        monospaced: Bool = false,
        accented: Bool = false,
        muted: Bool = false,
        showChevron: Bool = true,
        theme: KasugaiThemeTokens
    ) {
        self.isAccented = accented
        self.isMutedTitle = muted
        self.theme = theme
        let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(cfg)
        titleField.stringValue = title
        titleField.font =
            monospaced
            ? .monospacedSystemFont(ofSize: 12, weight: .medium)
            : .systemFont(ofSize: 12.5, weight: .medium)
        chevronView.isHidden = !showChevron
        addLabel.isHidden = true
        delLabel.isHidden = true
        fallbackLabel.isHidden = true
        refreshStyle()
    }

    func configureDiffStats(
        files: Int64,
        insertions: Int64,
        deletions: Int64,
        theme: KasugaiThemeTokens
    ) {
        let hasChanges = files > 0 || insertions > 0 || deletions > 0
        configure(
            symbol: "plusminus",
            title: hasChanges ? "変更差分" : "変更なし",
            monospaced: false,
            accented: false,
            muted: !hasChanges,
            showChevron: false,
            theme: theme
        )
        if hasChanges {
            addLabel.stringValue = "+\(insertions)"
            addLabel.isHidden = insertions <= 0
            delLabel.stringValue = "-\(deletions)"
            delLabel.isHidden = deletions <= 0
            fallbackLabel.stringValue = "\(files) 件"
            fallbackLabel.isHidden = insertions > 0 || deletions > 0
            toolTip = "変更差分を開く（\(files) ファイル）"
        } else {
            toolTip = "変更はありません"
        }
        refreshStyle()
    }

    private func refreshStyle() {
        surface.fillColor = isHovered ? theme.surfaceSelected : .clear
        if isAccented {
            iconView.contentTintColor = theme.accent
            titleField.textColor = theme.textPrimary
            chevronView.contentTintColor = theme.accent
        } else if isMutedTitle {
            iconView.contentTintColor = theme.textMuted
            titleField.textColor = theme.textMuted
            chevronView.contentTintColor = theme.textMuted
        } else {
            iconView.contentTintColor = isHovered ? theme.textPrimary : theme.textMuted
            titleField.textColor = theme.textPrimary.withAlphaComponent(isHovered ? 1.0 : 0.86)
            chevronView.contentTintColor = isHovered ? theme.textPrimary : theme.textMuted
        }
        addLabel.textColor = theme.success
        delLabel.textColor = theme.danger
        fallbackLabel.textColor = theme.textSecondary
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
        isPressed = false
        refreshStyle()
        KasugaiInteractiveMotion.applyScale(to: self, scale: 1.0)
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        KasugaiInteractiveMotion.applyScale(to: self, scale: 0.985)
    }

    override func mouseUp(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let shouldFire = isPressed && bounds.contains(local)
        isPressed = false
        KasugaiInteractiveMotion.applyScale(to: self, scale: 1.0)
        if shouldFire {
            sendAction(action, to: target)
        }
    }
}

private final class DetailsCardSplitRowControl: NSView {
    var onPrimaryTap: (() -> Void)?
    var onMenuTap: ((NSView) -> Void)?

    private let surface = KasugaiSurfaceView()
    private let leftSurface = KasugaiSurfaceView()
    private let rightSurface = KasugaiSurfaceView()
    private let splitDivider = KasugaiSurfaceView()
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let chevronView = NSImageView()
    private var theme = KasugaiThemeTokens.resolve(palette: .kasugai, isLight: false)
    private var isHovered = false
    private var hoveredRight = false
    private var pressedRight: Bool?
    private var trackingAreaRef: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultLow, for: .horizontal)

        surface.cornerRadius = 8
        surface.translatesAutoresizingMaskIntoConstraints = false

        leftSurface.cornerRadius = 8
        leftSurface.translatesAutoresizingMaskIntoConstraints = false

        rightSurface.cornerRadius = 8
        rightSurface.translatesAutoresizingMaskIntoConstraints = false

        splitDivider.translatesAutoresizingMaskIntoConstraints = false
        splitDivider.isHidden = true

        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleField.font = .systemFont(ofSize: 12.5, weight: .medium)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let chevCfg = NSImage.SymbolConfiguration(pointSize: 9.5, weight: .semibold)
        chevronView.image = NSImage(
            systemSymbolName: "chevron.down",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(chevCfg)
        chevronView.imageScaling = .scaleProportionallyDown
        chevronView.translatesAutoresizingMaskIntoConstraints = false

        let leftRow = NSStackView(views: [iconView, titleField])
        leftRow.orientation = .horizontal
        leftRow.alignment = .centerY
        leftRow.spacing = 8
        leftRow.translatesAutoresizingMaskIntoConstraints = false

        leftSurface.addSubview(leftRow)
        rightSurface.addSubview(chevronView)
        surface.addSubview(leftSurface)
        surface.addSubview(splitDivider)
        surface.addSubview(rightSurface)
        addSubview(surface)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),

            leftSurface.topAnchor.constraint(equalTo: surface.topAnchor),
            leftSurface.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
            leftSurface.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            leftSurface.trailingAnchor.constraint(equalTo: splitDivider.leadingAnchor),

            splitDivider.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
            splitDivider.heightAnchor.constraint(equalToConstant: 16),
            splitDivider.widthAnchor.constraint(equalToConstant: 1),
            splitDivider.trailingAnchor.constraint(equalTo: rightSurface.leadingAnchor),

            rightSurface.topAnchor.constraint(equalTo: surface.topAnchor),
            rightSurface.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
            rightSurface.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            rightSurface.widthAnchor.constraint(equalToConstant: 30),

            iconView.widthAnchor.constraint(equalToConstant: 15),
            iconView.heightAnchor.constraint(equalToConstant: 15),

            leftRow.leadingAnchor.constraint(equalTo: leftSurface.leadingAnchor, constant: 10),
            leftRow.trailingAnchor.constraint(
                lessThanOrEqualTo: leftSurface.trailingAnchor, constant: -6),
            leftRow.centerYAnchor.constraint(equalTo: leftSurface.centerYAnchor),

            chevronView.centerXAnchor.constraint(equalTo: rightSurface.centerXAnchor),
            chevronView.centerYAnchor.constraint(equalTo: rightSurface.centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 11),
            chevronView.heightAnchor.constraint(equalToConstant: 11),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(title: String, theme: KasugaiThemeTokens) {
        self.theme = theme
        let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        iconView.image = NSImage(
            systemSymbolName: "arrow.up.forward.app",
            accessibilityDescription: title
        )?.withSymbolConfiguration(cfg)
        titleField.stringValue = title
        refreshStyle()
    }

    private func refreshStyle() {
        let baseHover = theme.surfaceSelected.withAlphaComponent(theme.isLight ? 0.55 : 0.65)
        surface.fillColor = isHovered ? baseHover : .clear
        leftSurface.fillColor = (isHovered && !hoveredRight) ? theme.surfaceSelected : .clear
        rightSurface.fillColor = (isHovered && hoveredRight) ? theme.surfaceSelected : .clear
        splitDivider.fillColor = theme.borderStrong
        splitDivider.isHidden = !isHovered
        iconView.contentTintColor = isHovered ? theme.textPrimary : theme.textMuted
        titleField.textColor = theme.textPrimary.withAlphaComponent(isHovered ? 1.0 : 0.86)
        chevronView.contentTintColor = isHovered ? theme.textPrimary : theme.textMuted
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
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    private func isPointInRightHalf(_ point: NSPoint) -> Bool {
        point.x >= bounds.width - 30
    }

    override func mouseEntered(with event: NSEvent) {
        guard !KasugaiInteractiveMotion.isInteractionBlocked(for: self) else {
            return
        }
        let local = convert(event.locationInWindow, from: nil)
        isHovered = true
        hoveredRight = isPointInRightHalf(local)
        refreshStyle()
    }

    override func mouseMoved(with event: NSEvent) {
        guard !KasugaiInteractiveMotion.isInteractionBlocked(for: self) else {
            return
        }
        let local = convert(event.locationInWindow, from: nil)
        let nextRight = isPointInRightHalf(local)
        if nextRight != hoveredRight {
            hoveredRight = nextRight
            refreshStyle()
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        hoveredRight = false
        pressedRight = nil
        refreshStyle()
        KasugaiInteractiveMotion.applyScale(to: self, scale: 1.0)
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        pressedRight = isPointInRightHalf(local)
        KasugaiInteractiveMotion.applyScale(to: self, scale: 0.985)
    }

    override func mouseUp(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let startedRight = pressedRight
        pressedRight = nil
        KasugaiInteractiveMotion.applyScale(to: self, scale: 1.0)
        guard let startedRight, bounds.contains(local) else {
            return
        }
        if startedRight && isPointInRightHalf(local) {
            onMenuTap?(self)
        } else if !startedRight && !isPointInRightHalf(local) {
            onPrimaryTap?()
        }
    }
}

private final class ThreadDetailsCardView: NSView {
    static let cardWidth: CGFloat = 252

    var onWorkspaceRowTap: ((NSView) -> Void)?
    var onOpenInPrimaryTap: (() -> Void)?
    var onOpenInMenuTap: ((NSView) -> Void)?
    var onBranchRowTap: ((NSView) -> Void)?
    var onChangesRowTap: (() -> Void)?

    private let isFloating: Bool
    private let surface = KasugaiSurfaceView()
    private let workspaceRow = DetailsCardRowControl()
    private let openInRow = DetailsCardSplitRowControl()
    private let sectionDivider = KasugaiSurfaceView()
    private let branchRow = DetailsCardRowControl()
    private let changesRow = DetailsCardRowControl()

    init(isFloating: Bool) {
        self.isFloating = isFloating
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        setup()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func setup() {
        surface.cornerRadius = isFloating ? 16 : 0
        surface.strokeWidth = isFloating ? 1 : 0
        surface.translatesAutoresizingMaskIntoConstraints = false

        workspaceRow.target = self
        workspaceRow.action = #selector(handleWorkspaceTap)

        openInRow.onPrimaryTap = { [weak self] in
            self?.onOpenInPrimaryTap?()
        }
        openInRow.onMenuTap = { [weak self] anchor in
            self?.onOpenInMenuTap?(anchor)
        }

        branchRow.target = self
        branchRow.action = #selector(handleBranchTap)

        changesRow.target = self
        changesRow.action = #selector(handleChangesTap)

        let workspaceSection = NSStackView(views: [workspaceRow, openInRow])
        workspaceSection.orientation = .vertical
        workspaceSection.alignment = .width
        workspaceSection.spacing = 2
        workspaceSection.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        workspaceSection.translatesAutoresizingMaskIntoConstraints = false

        sectionDivider.translatesAutoresizingMaskIntoConstraints = false

        let vcsSection = NSStackView(views: [branchRow, changesRow])
        vcsSection.orientation = .vertical
        vcsSection.alignment = .width
        vcsSection.spacing = 2
        vcsSection.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        vcsSection.translatesAutoresizingMaskIntoConstraints = false

        let outerStack = NSStackView(views: [workspaceSection, sectionDivider, vcsSection])
        outerStack.orientation = .vertical
        outerStack.alignment = .width
        outerStack.spacing = 0
        outerStack.translatesAutoresizingMaskIntoConstraints = false

        surface.addSubview(outerStack)
        addSubview(surface)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.cardWidth),

            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),

            sectionDivider.heightAnchor.constraint(equalToConstant: 1),

            outerStack.topAnchor.constraint(equalTo: surface.topAnchor),
            outerStack.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
            outerStack.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            outerStack.trailingAnchor.constraint(equalTo: surface.trailingAnchor),

            workspaceRow.widthAnchor.constraint(
                equalTo: workspaceSection.widthAnchor, constant: -16),
            openInRow.widthAnchor.constraint(equalTo: workspaceSection.widthAnchor, constant: -16),
            branchRow.widthAnchor.constraint(equalTo: vcsSection.widthAnchor, constant: -16),
            changesRow.widthAnchor.constraint(equalTo: vcsSection.widthAnchor, constant: -16),
        ])
    }

    func update(
        workspace: KasugaiWorkspaceSnapshot?,
        diffReport: GitDiffReport?,
        theme: KasugaiThemeTokens
    ) {
        surface.fillColor =
            isFloating
            ? theme.surfaceBg.withAlphaComponent(theme.isLight ? 0.96 : 0.94)
            : theme.surfaceBg
        surface.strokeColor = isFloating ? theme.borderStrong : .clear
        sectionDivider.fillColor = theme.borderSubtle

        if isFloating {
            shadow = NSShadow()
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = theme.isLight ? 0.12 : 0.36
            layer?.shadowRadius = 14
            layer?.shadowOffset = CGSize(width: 0, height: -4)
            layer?.masksToBounds = false
        }

        guard let ws = workspace else {
            return
        }
        let isWorktree = ws.mode == "git_worktree"
        workspaceRow.configure(
            symbol: isWorktree ? "arrow.triangle.branch" : "laptopcomputer",
            title: isWorktree ? "Worktree" : "ローカル",
            monospaced: false,
            accented: isWorktree,
            showChevron: true,
            theme: theme
        )
        workspaceRow.toolTip = ws.effectiveCwd

        let preferred = ExternalEditorCatalog.preferredEditor()
        openInRow.configure(title: preferred.openTitle, theme: theme)
        openInRow.toolTip = "\(preferred.openTitle)（\(ws.effectiveCwd)）"

        let dirName = URL(fileURLWithPath: ws.effectiveCwd).lastPathComponent
        let reportBranch =
            (diffReport?.directory == ws.effectiveCwd) ? (diffReport?.branch ?? "") : ""
        let resolvedBranch = !ws.branch.isEmpty ? ws.branch : reportBranch
        let branchTitle =
            !resolvedBranch.isEmpty ? resolvedBranch : (dirName.isEmpty ? ws.effectiveCwd : dirName)
        let branchSymbol = !resolvedBranch.isEmpty ? "arrow.triangle.branch" : "folder"
        branchRow.configure(
            symbol: branchSymbol,
            title: branchTitle,
            monospaced: !resolvedBranch.isEmpty,
            accented: false,
            showChevron: true,
            theme: theme
        )
        branchRow.toolTip = ws.effectiveCwd

        let matchesReport = diffReport?.directory == ws.effectiveCwd
        let files = matchesReport ? (diffReport?.filesChanged ?? 0) : ws.diffFilesChanged
        let ins = matchesReport ? (diffReport?.insertions ?? 0) : ws.diffInsertions
        let del = matchesReport ? (diffReport?.deletions ?? 0) : ws.diffDeletions
        changesRow.configureDiffStats(
            files: files,
            insertions: ins,
            deletions: del,
            theme: theme
        )
    }

    @objc private func handleWorkspaceTap() {
        onWorkspaceRowTap?(workspaceRow)
    }

    @objc private func handleBranchTap() {
        onBranchRowTap?(branchRow)
    }

    @objc private func handleChangesTap() {
        onChangesRowTap?()
    }
}

private final class ThreadDetailsPopoverViewController: NSViewController {
    let cardView = ThreadDetailsCardView(isFloating: false)

    override func loadView() {
        let host = NSView(
            frame: NSRect(x: 0, y: 0, width: ThreadDetailsCardView.cardWidth, height: 168))
        host.addSubview(cardView)
        NSLayoutConstraint.activate([
            cardView.topAnchor.constraint(equalTo: host.topAnchor),
            cardView.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            cardView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])
        self.view = host
        host.layoutSubtreeIfNeeded()
        preferredContentSize = NSSize(
            width: ThreadDetailsCardView.cardWidth,
            height: max(164, ceil(cardView.fittingSize.height))
        )
    }
}

private final class ChatAreaViewController: NSViewController, NSPopoverDelegate {
    let chatWebView = SandboxedChatWebView(frame: .zero, mode: .chat)
    let approvalBanner = ApprovalBannerView(frame: .zero)
    let composerView = ComposerView(frame: .zero)

    var onToggleSidebar: (() -> Void)?
    var onToggleRightPane: (() -> Void)?
    var onOpenDiffFile: ((String?) -> Void)?
    var onOpenFilesTab: (() -> Void)?
    var onOpenFileLink: ((FileLinkTarget) -> Void)?
    var onOpenThread: ((Int64) -> Void)?
    var onToggleTerminal: (() -> Void)?
    var onRequestCreateWorktree: (() -> Void)?
    var onResetWorktree: (() -> Void)?
    var onApproveTool: (() -> Void)?
    var onDenyTool: (() -> Void)?
    var onDetailsCardOpenChanged: ((Bool) -> Void)?
    var onToggleActiveThreadSettled: (() -> Void)?

    private let rootSurface = KasugaiSurfaceView()
    let headerBar = NSStackView()
    let headerDivider = KasugaiSurfaceView()
    let detailsCard = ThreadDetailsCardView(isFloating: true)
    private var detailsCardPopover: NSPopover?
    private weak var popoverCardView: ThreadDetailsCardView?
    private var headerLeadingConstraint: NSLayoutConstraint?
    private let sidebarButton = KasugaiFlatButton()
    private let titleLabel = NSTextField(labelWithString: "Kasugai")
    let settleThreadButton = KasugaiFlatButton()
    let detailsCardButton = KasugaiFlatButton()
    let rightPaneButton = KasugaiFlatButton()
    let terminalButton = KasugaiFlatButton()

    private var palette: KasugaiPalette = .kasugai
    private var leftSidebarCollapsed = false
    private var rightPaneOpen = false
    private var terminalPaneOpen = false
    private var activeThreadSettled = false
    private var activeThreadCanSettle = false
    private var detailsCardUserOpen = true
    private var detailsCardTransitionToken: Int = 0
    private var currentWorkspace: KasugaiWorkspaceSnapshot?
    private var latestDiffReport: GitDiffReport?
    private static let inlineDetailsMinChatWidth: CGFloat = 660

    override func loadView() {
        rootSurface.frame = NSRect(x: 0, y: 0, width: 720, height: 520)

        sidebarButton.buttonStyle = .ghost
        sidebarButton.customHeight = 22
        sidebarButton.horizontalPadding = 5
        sidebarButton.configureSymbol("sidebar.left", pointSize: 12.5, weight: .medium)
        sidebarButton.toolTip = "左サイドバーを切り替え"
        sidebarButton.target = self
        sidebarButton.action = #selector(handleToggleSidebar)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        settleThreadButton.buttonStyle = .ghost
        settleThreadButton.customHeight = 22
        settleThreadButton.horizontalPadding = 5
        settleThreadButton.configureSymbol("checkmark.circle", pointSize: 12.5, weight: .medium)
        settleThreadButton.toolTip = "スレッドを完了にする"
        settleThreadButton.target = self
        settleThreadButton.action = #selector(handleToggleActiveThreadSettled)

        detailsCardButton.buttonStyle = .ghost
        detailsCardButton.customHeight = 22
        detailsCardButton.horizontalPadding = 5
        detailsCardButton.configureSymbol("doc.text", pointSize: 12, weight: .medium)
        detailsCardButton.toolTip = "ワークスペース情報を表示／非表示"
        detailsCardButton.target = self
        detailsCardButton.action = #selector(handleToggleDetailsCard)

        rightPaneButton.buttonStyle = .ghost
        rightPaneButton.customHeight = 22
        rightPaneButton.horizontalPadding = 5
        rightPaneButton.font = .monospacedSystemFont(ofSize: 11.5, weight: .medium)
        rightPaneButton.configureSymbol("sidebar.right", pointSize: 12.5, weight: .medium)
        rightPaneButton.toolTip = "右ペインを切り替え（⌘D）"
        rightPaneButton.target = self
        rightPaneButton.action = #selector(handleToggleRightPane)

        terminalButton.buttonStyle = .ghost
        terminalButton.customHeight = 22
        terminalButton.horizontalPadding = 5
        terminalButton.configureSymbol("terminal", pointSize: 12, weight: .medium)
        terminalButton.toolTip = "ターミナルを切り替え（⌘J）"
        terminalButton.target = self
        terminalButton.action = #selector(handleToggleTerminal)

        for view in [
            sidebarButton,
            titleLabel,
            spacer,
            settleThreadButton,
            detailsCardButton,
            terminalButton,
            rightPaneButton,
        ] {
            headerBar.addArrangedSubview(view)
        }
        headerBar.orientation = .horizontal
        headerBar.alignment = .centerY
        headerBar.spacing = 6
        headerBar.translatesAutoresizingMaskIntoConstraints = false

        headerDivider.translatesAutoresizingMaskIntoConstraints = false

        bindDetailsCardActions(detailsCard)
        detailsCard.isHidden = true

        approvalBanner.isHidden = true
        approvalBanner.onApprove = { [weak self] in
            self?.onApproveTool?()
        }
        approvalBanner.onDeny = { [weak self] in
            self?.onDenyTool?()
        }

        let bottomStack = NSStackView(views: [approvalBanner, composerView])
        bottomStack.orientation = .vertical
        bottomStack.alignment = .width
        bottomStack.spacing = 0
        bottomStack.translatesAutoresizingMaskIntoConstraints = false

        chatWebView.translatesAutoresizingMaskIntoConstraints = false
        chatWebView.onOpenFileLink = { [weak self] target in
            self?.onOpenFileLink?(target)
        }
        chatWebView.onOpenThread = { [weak self] threadId in
            self?.onOpenThread?(threadId)
        }
        composerView.translatesAutoresizingMaskIntoConstraints = false

        rootSurface.addSubview(headerBar)
        rootSurface.addSubview(headerDivider)
        rootSurface.addSubview(chatWebView)
        rootSurface.addSubview(bottomStack)
        rootSurface.addSubview(detailsCard)

        let leadingConstraint = headerBar.leadingAnchor.constraint(
            equalTo: rootSurface.leadingAnchor,
            constant: leftSidebarCollapsed ? KasugaiChromeMetrics.trafficLightLeadingInset : 12
        )
        headerLeadingConstraint = leadingConstraint

        NSLayoutConstraint.activate([
            headerBar.topAnchor.constraint(equalTo: rootSurface.topAnchor),
            leadingConstraint,
            headerBar.trailingAnchor.constraint(equalTo: rootSurface.trailingAnchor, constant: -12),
            headerBar.heightAnchor.constraint(
                equalToConstant: KasugaiChromeMetrics.headerBarHeight),

            headerDivider.topAnchor.constraint(
                equalTo: rootSurface.topAnchor, constant: KasugaiChromeMetrics.headerHeight),
            headerDivider.leadingAnchor.constraint(equalTo: rootSurface.leadingAnchor),
            headerDivider.trailingAnchor.constraint(equalTo: rootSurface.trailingAnchor),
            headerDivider.heightAnchor.constraint(equalToConstant: 1),

            chatWebView.topAnchor.constraint(equalTo: headerDivider.bottomAnchor),
            chatWebView.leadingAnchor.constraint(equalTo: rootSurface.leadingAnchor),
            chatWebView.trailingAnchor.constraint(equalTo: rootSurface.trailingAnchor),
            chatWebView.bottomAnchor.constraint(equalTo: bottomStack.topAnchor),

            detailsCard.topAnchor.constraint(equalTo: headerDivider.bottomAnchor, constant: 12),
            detailsCard.trailingAnchor.constraint(
                equalTo: rootSurface.trailingAnchor, constant: -12),

            bottomStack.leadingAnchor.constraint(equalTo: rootSurface.leadingAnchor),
            bottomStack.trailingAnchor.constraint(equalTo: rootSurface.trailingAnchor),
            bottomStack.bottomAnchor.constraint(equalTo: rootSurface.bottomAnchor),
        ])

        self.view = rootSurface
        rootSurface.onAppearanceChanged = { [weak self] in
            self?.applyTheme()
        }
        applyTheme()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        syncDetailsCardPresentation()
    }

    private func bindDetailsCardActions(_ card: ThreadDetailsCardView) {
        card.onWorkspaceRowTap = { [weak self] anchor in
            self?.showWorkspaceMenu(from: anchor)
        }
        card.onOpenInPrimaryTap = { [weak self] in
            self?.openWorkspaceInPreferredEditor()
        }
        card.onOpenInMenuTap = { [weak self] anchor in
            self?.showOpenInMenu(from: anchor)
        }
        card.onBranchRowTap = { [weak self] anchor in
            self?.showWorkspaceMenu(from: anchor)
        }
        card.onChangesRowTap = { [weak self] in
            self?.detailsCardPopover?.performClose(nil)
            self?.onOpenDiffFile?(nil)
        }
    }

    func update(palette: KasugaiPalette) {
        self.palette = palette
        chatWebView.update(palette: palette)
        composerView.update(palette: palette)
        applyTheme()
    }

    func update(approvalPolicy: KasugaiToolApprovalPolicy) {
        composerView.update(approvalPolicy: approvalPolicy)
    }

    func applyTheme() {
        let theme = KasugaiThemeTokens.resolve(
            palette: palette, appearance: view.effectiveAppearance)
        rootSurface.fillColor = theme.canvasBg
        headerDivider.fillColor = theme.borderSubtle
        titleLabel.textColor = theme.textPrimary
        sidebarButton.apply(theme: theme)
        syncSettleButtonStyle(theme: theme)
        syncDetailsCardContent(theme: theme)
        syncDetailsCardPresentation()
        detailsCardButton.apply(theme: theme)
        rightPaneButton.isSelectedPill = rightPaneOpen
        rightPaneButton.apply(theme: theme)
        terminalButton.isSelectedPill = terminalPaneOpen
        terminalButton.apply(theme: theme)
        approvalBanner.apply(theme: theme)
        composerView.applyTheme()
    }

    func update(diffReport: GitDiffReport?) {
        latestDiffReport = diffReport
        let theme = KasugaiThemeTokens.resolve(
            palette: palette, appearance: view.effectiveAppearance)
        syncDetailsCardContent(theme: theme)
    }

    var isDetailsCardUserOpen: Bool {
        detailsCardUserOpen
    }

    func setDetailsCardUserOpen(_ open: Bool) {
        detailsCardUserOpen = open
        syncDetailsCardPresentation()
    }

    func setActiveThreadSettleState(settled: Bool, visible: Bool) {
        activeThreadSettled = settled
        activeThreadCanSettle = visible
        let theme = KasugaiThemeTokens.resolve(
            palette: palette, appearance: view.effectiveAppearance)
        syncSettleButtonStyle(theme: theme)
    }

    private func syncSettleButtonStyle(theme: KasugaiThemeTokens) {
        settleThreadButton.isHidden = !activeThreadCanSettle
        settleThreadButton.configureSymbol(
            activeThreadSettled ? "checkmark.circle.fill" : "checkmark.circle",
            pointSize: 12.5,
            weight: .medium
        )
        settleThreadButton.customTintColor = activeThreadSettled ? theme.success : nil
        settleThreadButton.isSelectedPill = activeThreadSettled
        settleThreadButton.toolTip = activeThreadSettled ? "アクティブに戻す" : "スレッドを完了にする"
        settleThreadButton.apply(theme: theme)
    }

    @objc private func handleToggleActiveThreadSettled() {
        onToggleActiveThreadSettled?()
    }

    func setPaneStates(
        leftSidebarCollapsed: Bool,
        rightPaneOpen: Bool,
        terminalOpen: Bool
    ) {
        let changed =
            self.leftSidebarCollapsed != leftSidebarCollapsed
            || self.rightPaneOpen != rightPaneOpen
            || self.terminalPaneOpen != terminalOpen
        guard changed else {
            return
        }
        self.leftSidebarCollapsed = leftSidebarCollapsed
        self.rightPaneOpen = rightPaneOpen
        self.terminalPaneOpen = terminalOpen
        headerLeadingConstraint?.constant =
            leftSidebarCollapsed ? KasugaiChromeMetrics.trafficLightLeadingInset : 12
        rightPaneButton.isHidden = rightPaneOpen
        applyTheme()
    }

    func update(
        snapshot: KasugaiCoreSnapshot,
        threadTransition: KasugaiSlideDirection? = nil
    ) {
        let thread = snapshot.activeThread
        let nextTitle = thread?.displayTitle ?? "Kasugai"
        if let threadTransition, titleLabel.stringValue != nextTitle {
            KasugaiInteractiveMotion.animateDirectionalSwap(
                view: titleLabel,
                direction: threadTransition,
                distance: 8
            ) { [weak self] in
                self?.titleLabel.stringValue = nextTitle
            }
        } else {
            titleLabel.stringValue = nextTitle
        }
        currentWorkspace = thread?.workspace
        let theme = KasugaiThemeTokens.resolve(
            palette: palette, appearance: view.effectiveAppearance)
        syncDetailsCardContent(theme: theme)
        syncDetailsCardPresentation()
        let projectNames = Dictionary(
            uniqueKeysWithValues: snapshot.projects.map { ($0.id, $0.name) }
        )
        var threadIndex: [String: KasugaiThreadLinkInfo] = [:]
        for item in snapshot.threads {
            threadIndex[String(item.id)] = KasugaiThreadLinkInfo(
                id: item.id,
                title: item.displayTitle,
                projectName: projectNames[item.projectId] ?? "",
                status: item.status
            )
        }
        chatWebView.update(
            thread: thread,
            threadIndex: threadIndex,
            transition: threadTransition
        )
        approvalBanner.update(approval: thread?.pendingApproval)
        composerView.update(snapshot: snapshot)
    }

    private var canShowInlineDetailsCard: Bool {
        currentWorkspace != nil && view.bounds.width >= Self.inlineDetailsMinChatWidth
    }

    private func syncDetailsCardContent(theme: KasugaiThemeTokens) {
        detailsCard.update(
            workspace: currentWorkspace,
            diffReport: latestDiffReport,
            theme: theme
        )
        popoverCardView?.update(
            workspace: currentWorkspace,
            diffReport: latestDiffReport,
            theme: theme
        )
    }

    private func syncDetailsCardPresentation() {
        let hasWorkspace = currentWorkspace != nil
        detailsCardButton.isHidden = !hasWorkspace
        if canShowInlineDetailsCard {
            if let pop = detailsCardPopover, pop.isShown {
                pop.performClose(nil)
            }
            detailsCard.isHidden = !detailsCardUserOpen
            detailsCardButton.isSelectedPill = detailsCardUserOpen
        } else {
            detailsCard.isHidden = true
            detailsCardButton.isSelectedPill = detailsCardPopover?.isShown == true
        }
        let theme = KasugaiThemeTokens.resolve(
            palette: palette, appearance: view.effectiveAppearance)
        detailsCardButton.apply(theme: theme)
    }

    func popoverDidClose(_ notification: Notification) {
        syncDetailsCardPresentation()
    }

    @objc private func handleToggleDetailsCard() {
        guard currentWorkspace != nil else {
            return
        }
        if canShowInlineDetailsCard {
            detailsCardUserOpen.toggle()
            onDetailsCardOpenChanged?(detailsCardUserOpen)
            detailsCardTransitionToken &+= 1
            let token = detailsCardTransitionToken
            if detailsCardUserOpen {
                syncDetailsCardPresentation()
                KasugaiInteractiveMotion.animateDirectionalEnter(
                    view: detailsCard,
                    direction: .fromTop,
                    distance: 10,
                    duration: 0.18
                )
            } else {
                detailsCardButton.isSelectedPill = false
                let theme = KasugaiThemeTokens.resolve(
                    palette: palette, appearance: view.effectiveAppearance)
                detailsCardButton.apply(theme: theme)
                KasugaiInteractiveMotion.animateDirectionalExit(
                    view: detailsCard,
                    to: .fromTop,
                    distance: 8,
                    duration: 0.13
                ) { [weak self] in
                    guard let self, self.detailsCardTransitionToken == token,
                        !self.detailsCardUserOpen
                    else {
                        return
                    }
                    self.detailsCard.isHidden = true
                    self.detailsCard.layer?.opacity = 1
                    self.detailsCard.layer?.transform = CATransform3DIdentity
                }
            }
            return
        }
        if let existing = detailsCardPopover, existing.isShown {
            existing.performClose(nil)
            syncDetailsCardPresentation()
            return
        }
        let vc = ThreadDetailsPopoverViewController()
        _ = vc.view
        bindDetailsCardActions(vc.cardView)
        let theme = KasugaiThemeTokens.resolve(
            palette: palette, appearance: view.effectiveAppearance)
        vc.cardView.update(
            workspace: currentWorkspace,
            diffReport: latestDiffReport,
            theme: theme
        )
        popoverCardView = vc.cardView

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.appearance = view.effectiveAppearance
        popover.contentViewController = vc
        popover.contentSize = vc.preferredContentSize
        detailsCardPopover = popover
        popover.show(
            relativeTo: detailsCardButton.bounds,
            of: detailsCardButton,
            preferredEdge: .minY
        )
        syncDetailsCardPresentation()
    }

    private func openWorkspaceInPreferredEditor() {
        guard let cwd = currentWorkspace?.effectiveCwd, !cwd.isEmpty else {
            return
        }
        let preferred = ExternalEditorCatalog.preferredEditor()
        if let appPath = preferred.appPath {
            openWorkspace(cwd, withAppPath: appPath)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: cwd, isDirectory: true))
        }
    }

    private func openWorkspace(_ cwd: String, withAppPath appPath: String) {
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open(
            [URL(fileURLWithPath: cwd, isDirectory: true)],
            withApplicationAt: URL(fileURLWithPath: appPath),
            configuration: config
        )
    }

    private func showOpenInMenu(from anchor: NSView) {
        guard let path = currentWorkspace?.effectiveCwd, !path.isEmpty else {
            return
        }
        let menu = NSMenu()
        let preferred = ExternalEditorCatalog.preferredEditor()
        let editors = ExternalEditorCatalog.installedEditors()
        for option in editors {
            let item = NSMenuItem(
                title: option.openTitle,
                action: #selector(handlePickExternalEditor(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = option.appPath ?? ""
            item.state = option.appPath == preferred.appPath ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let copyItem = NSMenuItem(
            title: "パスをコピー",
            action: #selector(handleCopyWorkspacePath),
            keyEquivalent: ""
        )
        copyItem.target = self
        menu.addItem(copyItem)

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: -4),
            in: anchor
        )
    }

    @objc private func handlePickExternalEditor(_ sender: NSMenuItem) {
        guard let cwd = currentWorkspace?.effectiveCwd, !cwd.isEmpty else {
            return
        }
        let raw = sender.representedObject as? String ?? ""
        let appPath: String? = raw.isEmpty ? nil : raw
        ExternalEditorCatalog.savePreferred(appPath: appPath)
        let theme = KasugaiThemeTokens.resolve(
            palette: palette, appearance: view.effectiveAppearance)
        syncDetailsCardContent(theme: theme)
        if let appPath {
            openWorkspace(cwd, withAppPath: appPath)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: cwd, isDirectory: true))
        }
    }

    private func showWorkspaceMenu(from anchor: NSView) {
        guard let ws = currentWorkspace else {
            return
        }
        let menu = NSMenu()
        let pathItem = NSMenuItem(title: ws.effectiveCwd, action: nil, keyEquivalent: "")
        pathItem.isEnabled = false
        menu.addItem(pathItem)
        menu.addItem(.separator())

        let createItem = NSMenuItem(
            title: "Worktree を作成…",
            action: #selector(handleMenuCreateWorktree),
            keyEquivalent: ""
        )
        createItem.target = self
        menu.addItem(createItem)

        if ws.mode == "git_worktree" {
            let resetItem = NSMenuItem(
                title: "ルートに戻す",
                action: #selector(handleMenuResetWorktree),
                keyEquivalent: ""
            )
            resetItem.target = self
            menu.addItem(resetItem)
        }

        menu.addItem(.separator())

        let diffItem = NSMenuItem(
            title: "変更差分を開く",
            action: #selector(handleOpenDiffFromCard),
            keyEquivalent: ""
        )
        diffItem.target = self
        menu.addItem(diffItem)

        let filesItem = NSMenuItem(
            title: "ファイル一覧を開く",
            action: #selector(handleOpenFilesFromCard),
            keyEquivalent: ""
        )
        filesItem.target = self
        menu.addItem(filesItem)

        let finderItem = NSMenuItem(
            title: "Finder で開く",
            action: #selector(handleRevealWorkspaceInFinder),
            keyEquivalent: ""
        )
        finderItem.target = self
        menu.addItem(finderItem)

        let copyItem = NSMenuItem(
            title: "パスをコピー",
            action: #selector(handleCopyWorkspacePath),
            keyEquivalent: ""
        )
        copyItem.target = self
        menu.addItem(copyItem)

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: -4),
            in: anchor
        )
    }

    @objc private func handleOpenFilesFromCard() {
        detailsCardPopover?.performClose(nil)
        onOpenFilesTab?()
    }

    @objc private func handleMenuCreateWorktree() {
        detailsCardPopover?.performClose(nil)
        onRequestCreateWorktree?()
    }

    @objc private func handleMenuResetWorktree() {
        detailsCardPopover?.performClose(nil)
        onResetWorktree?()
    }

    @objc private func handleOpenDiffFromCard() {
        detailsCardPopover?.performClose(nil)
        onOpenDiffFile?(nil)
    }

    @objc private func handleRevealWorkspaceInFinder() {
        guard let path = currentWorkspace?.effectiveCwd, !path.isEmpty else {
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }

    @objc private func handleCopyWorkspacePath() {
        guard let path = currentWorkspace?.effectiveCwd, !path.isEmpty else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)
    }

    @objc private func handleToggleSidebar() {
        onToggleSidebar?()
    }

    @objc private func handleToggleRightPane() {
        onToggleRightPane?()
    }

    @objc private func handleToggleTerminal() {
        onToggleTerminal?()
    }
}

private final class VerticalSplitViewController: NSSplitViewController {
    let innerSplitView = KasugaiSplitView()

    override func loadView() {
        innerSplitView.frame = NSRect(x: 0, y: 0, width: 720, height: 820)
        innerSplitView.isVertical = false
        innerSplitView.dividerStyle = .thin
        self.splitView = innerSplitView
        super.loadView()
    }
}

final class MainSplitViewController: NSSplitViewController, KasugaiBrowserAutomationHost {
    var onLayoutStateChanged: (() -> Void)?

    private let core: KasugaiCore
    private var settings: KasugaiAppSettings
    private let storePath: String
    private let sidebarController = SidebarViewController()
    private let chatAreaController = ChatAreaViewController()
    private let factoryViewController = FactoryViewController()
    private let factoryStore: FactoryRunStore
    private let settingsViewController: SettingsViewController
    private let rateLimitsViewController = RateLimitsViewController()
    private let diffController = DiffViewerController()
    private let terminalController = TerminalPaneViewController()
    private let centerVerticalSplit = VerticalSplitViewController()
    private let outerSplitView = KasugaiSplitView()

    private var sidebarItem: NSSplitViewItem?
    private var diffItem: NSSplitViewItem?
    private var terminalItem: NSSplitViewItem?
    private var activeFactoryRunId: String?
    private var rightPaneWasOpenBeforeFactory = false
    private var isShowingSettings = false
    private var isShowingRateLimits = false
    private var settingsTransitionToken: Int = 0
    private var rateLimitsTransitionToken: Int = 0
    private var lastPresentedThreadId: Int64 = 0
    private var pinnedVisibleThreadId: Int64 = 0
    private var lastPresentedThreadRowIndex: Int?
    private var rateLimitObserverToken: UUID?
    private var wakeupSources: [Int32: DispatchSourceRead] = [:]
    private var orchestratorServer: LocalOrchestratorServer?
    private var browserBridgeServer: LocalBrowserBridgeServer?
    private var remoteOrchestratorSocketPath: String = ""
    private var syncLoopState: SyncLoopState = .idleClean
    private var syncLoopThreadId: Int64 = 0
    private var autoApprovingThreadIds: Set<Int64> = []
    private let draftStorePath: String
    private var draftStore: KasugaiDraftStore
    private var activeDraftThreadId: Int64 = 0
    private var pendingDraftSaveWorkItem: DispatchWorkItem?
    private let rightPaneTabsStorePath: String
    private var initialRightPaneTabsStore: KasugaiRightPaneTabStore
    private var pendingRightPaneTabsSaveWorkItem: DispatchWorkItem?

    var activeOrchestratorSocketPath: String {
        core.isRemoteDaemon ? remoteOrchestratorSocketPath : (orchestratorServer?.socketPath ?? "")
    }

    init(
        core: KasugaiCore,
        settings: KasugaiAppSettings,
        storePath: String,
        draftStorePath: String = KasugaiDraftStore.defaultPath(),
        rightPaneTabsStorePath: String = KasugaiRightPaneTabStore.defaultPath(),
        factoryRootDirectory: URL = KasugaiRuntimePaths.dataDirectory().appendingPathComponent(
            "factory",
            isDirectory: true
        )
    ) {
        self.core = core
        self.settings = settings
        self.storePath = storePath
        self.factoryStore = FactoryRunStore(rootDirectory: factoryRootDirectory)
        self.draftStorePath = draftStorePath
        self.draftStore = KasugaiDraftStore.load(from: draftStorePath)
        self.rightPaneTabsStorePath = rightPaneTabsStorePath
        self.initialRightPaneTabsStore = KasugaiRightPaneTabStore.load(
            from: rightPaneTabsStorePath
        )
        self.settingsViewController = SettingsViewController(
            settings: settings,
            storePath: storePath,
            socketPath: ""
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let token = rateLimitObserverToken {
            RateLimitService.shared.removeObserver(token)
        }
        stopOrchestratorBridge()
        factoryStore.detachForUIReload()
        browserBridgeServer?.stop()
        browserBridgeServer = nil
        for (_, source) in wakeupSources {
            source.cancel()
        }
        wakeupSources.removeAll()
    }

    override func loadView() {
        outerSplitView.frame = NSRect(x: 0, y: 0, width: 1280, height: 820)
        outerSplitView.isVertical = true
        outerSplitView.dividerStyle = .thin
        self.splitView = outerSplitView
        super.loadView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let chatItem = NSSplitViewItem(viewController: chatAreaController)
        chatItem.minimumThickness = 280
        let bottomTerminalItem = NSSplitViewItem(viewController: terminalController)
        bottomTerminalItem.canCollapse = true
        bottomTerminalItem.isCollapsed = true
        bottomTerminalItem.minimumThickness = 150
        centerVerticalSplit.addSplitViewItem(chatItem)
        centerVerticalSplit.addSplitViewItem(bottomTerminalItem)
        terminalItem = bottomTerminalItem

        let leftItem = NSSplitViewItem(viewController: sidebarController)
        leftItem.minimumThickness = 200
        leftItem.maximumThickness = 340
        leftItem.holdingPriority = NSLayoutConstraint.Priority(260)
        leftItem.canCollapse = true
        sidebarItem = leftItem

        let centerItem = NSSplitViewItem(viewController: centerVerticalSplit)
        centerItem.minimumThickness = 280
        centerItem.holdingPriority = NSLayoutConstraint.Priority(240)

        let rightItem = NSSplitViewItem(viewController: diffController)
        rightItem.minimumThickness = 240
        rightItem.maximumThickness = 960
        rightItem.holdingPriority = NSLayoutConstraint.Priority(255)
        rightItem.canCollapse = true
        rightItem.isCollapsed = true
        diffItem = rightItem

        addSplitViewItem(leftItem)
        addSplitViewItem(centerItem)
        addSplitViewItem(rightItem)

        installOverlays()
        wireActions()
        diffController.loadPersistedStore(initialRightPaneTabsStore)
        if core.isRemoteDaemon {
            core.onRemoteChanged = { [weak self] in
                self?.handleRemoteCoreChanged()
            }
            core.onRemoteReconnected = { [weak self] in
                self?.handleRemoteDaemonReconnected()
            }
        }
        applySettings(settings)
        factoryViewController.update(blueprints: factoryStore.allBlueprints)
        sidebarController.update(
            factoryRuns: factoryStore.allRuns,
            selectedFactoryRunId: activeFactoryRunId
        )
        refreshFromCore()
        rateLimitObserverToken = RateLimitService.shared.addObserver { [weak self] snap in
            self?.sidebarController.update(rateLimits: snap)
            self?.rateLimitsViewController.update(snapshot: snap)
        }
        if ProcessInfo.processInfo.environment["KASUGAI_SELF_TEST"] != "1"
            && CommandLine.arguments.dropFirst().first != "ui-snapshot"
        {
            let browserBridge = LocalBrowserBridgeServer(host: self)
            if browserBridge.start() {
                browserBridgeServer = browserBridge
            }
            ProviderModelCatalog.shared.refreshInBackgroundIfNeeded(
                suppressTelemetry: settings.suppressTelemetry
            ) { [weak self] in
                self?.refreshFromCore()
            }
            RateLimitService.shared.refreshIfNeeded(
                suppressTelemetry: settings.suppressTelemetry,
                force: true
            )
        }
    }

    private func installOverlays() {
        chatAreaController.addChild(factoryViewController)
        factoryViewController.view.translatesAutoresizingMaskIntoConstraints = false
        factoryViewController.view.isHidden = true

        chatAreaController.addChild(settingsViewController)
        settingsViewController.view.translatesAutoresizingMaskIntoConstraints = false
        settingsViewController.view.isHidden = true

        chatAreaController.addChild(rateLimitsViewController)
        rateLimitsViewController.view.translatesAutoresizingMaskIntoConstraints = false
        rateLimitsViewController.view.isHidden = true
    }

    private func setOverlayMounted(
        _ overlayView: NSView,
        in container: NSView,
        visible: Bool
    ) {
        if visible {
            if overlayView.superview !== container {
                container.addSubview(overlayView, positioned: .above, relativeTo: nil)
                NSLayoutConstraint.activate([
                    overlayView.topAnchor.constraint(equalTo: container.topAnchor),
                    overlayView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    overlayView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                    overlayView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                ])
            } else {
                container.addSubview(overlayView, positioned: .above, relativeTo: nil)
            }
            overlayView.isHidden = false
        } else {
            overlayView.isHidden = true
            if overlayView.superview != nil {
                overlayView.removeFromSuperview()
            }
        }
    }

    private func syncModalBlockingState() {
        let activeBackdrop: NSView?
        if isShowingSettings {
            activeBackdrop = settingsViewController.view
        } else if isShowingRateLimits {
            activeBackdrop = rateLimitsViewController.view
        } else {
            activeBackdrop = nil
        }
        let blocked = activeBackdrop != nil
        outerSplitView.isInteractionBlocked = blocked
        KasugaiInteractiveMotion.activeModalBackdrop = activeBackdrop
        if let window = view.window {
            window.invalidateCursorRects(for: outerSplitView)
            if let activeBackdrop {
                window.invalidateCursorRects(for: activeBackdrop)
            }
        }
    }

    private func anchorPointInRoot(for anchorView: NSView) -> NSPoint? {
        if sidebarItem?.isCollapsed == true {
            return nil
        }
        guard anchorView.window != nil,
            !anchorView.isHiddenOrHasHiddenAncestor,
            anchorView.bounds.width > 0,
            anchorView.bounds.height > 0
        else {
            return nil
        }
        let center = NSPoint(x: anchorView.bounds.midX, y: anchorView.bounds.midY)
        return view.convert(center, from: anchorView)
    }

    func showSettingsScreen(_ show: Bool) {
        if show && isShowingRateLimits {
            showRateLimitsScreen(false)
        }
        guard isShowingSettings != show || show else {
            return
        }
        isShowingSettings = show
        settingsTransitionToken &+= 1
        let token = settingsTransitionToken
        let origin = anchorPointInRoot(for: sidebarController.settingsAnchorView)
        sidebarController.setSettingsOpen(show)
        if show {
            setOverlayMounted(settingsViewController.view, in: view, visible: true)
            syncModalBlockingState()
            settingsViewController.update(
                settings: settings,
                storePath: storePath,
                socketPath: activeOrchestratorSocketPath
            )
            refreshMobileBridgeStatusAsync(refreshTailscale: settings.enableMobileBridge)
            view.layoutSubtreeIfNeeded()
            KasugaiInteractiveMotion.animateModalPresent(
                backdrop: settingsViewController.view,
                card: settingsViewController.modalSurface,
                fromOriginInBackdrop: origin
            )
            view.window?.makeFirstResponder(settingsViewController)
        } else {
            syncModalBlockingState()
            KasugaiInteractiveMotion.animateModalDismiss(
                backdrop: settingsViewController.view,
                card: settingsViewController.modalSurface,
                toOriginInBackdrop: origin
            ) { [weak self] in
                guard let self, self.settingsTransitionToken == token, !self.isShowingSettings
                else {
                    return
                }
                self.setOverlayMounted(
                    self.settingsViewController.view, in: self.view, visible: false)
                self.settingsViewController.view.layer?.opacity = 1
                self.settingsViewController.modalSurface.layer?.opacity = 1
                self.settingsViewController.modalSurface.layer?.transform = CATransform3DIdentity
                self.syncModalBlockingState()
            }
            if !isShowingRateLimits {
                focusComposer()
            }
        }
    }

    func toggleSettingsScreen() {
        showSettingsScreen(!isShowingSettings)
    }

    func showRateLimitsScreen(_ show: Bool) {
        if show && isShowingSettings {
            showSettingsScreen(false)
        }
        guard isShowingRateLimits != show || show else {
            return
        }
        isShowingRateLimits = show
        rateLimitsTransitionToken &+= 1
        let token = rateLimitsTransitionToken
        let origin = anchorPointInRoot(for: sidebarController.rateLimitsAnchorView)
        sidebarController.setRateLimitsOpen(show)
        if show {
            setOverlayMounted(rateLimitsViewController.view, in: view, visible: true)
            syncModalBlockingState()
            rateLimitsViewController.update(snapshot: RateLimitService.shared.snapshot)
            RateLimitService.shared.refreshIfNeeded(
                suppressTelemetry: settings.suppressTelemetry
            )
            view.layoutSubtreeIfNeeded()
            KasugaiInteractiveMotion.animateModalPresent(
                backdrop: rateLimitsViewController.view,
                card: rateLimitsViewController.modalSurface,
                fromOriginInBackdrop: origin
            )
            view.window?.makeFirstResponder(rateLimitsViewController)
        } else {
            syncModalBlockingState()
            KasugaiInteractiveMotion.animateModalDismiss(
                backdrop: rateLimitsViewController.view,
                card: rateLimitsViewController.modalSurface,
                toOriginInBackdrop: origin
            ) { [weak self] in
                guard let self, self.rateLimitsTransitionToken == token, !self.isShowingRateLimits
                else {
                    return
                }
                self.setOverlayMounted(
                    self.rateLimitsViewController.view, in: self.view, visible: false)
                self.rateLimitsViewController.view.layer?.opacity = 1
                self.rateLimitsViewController.modalSurface.layer?.opacity = 1
                self.rateLimitsViewController.modalSurface.layer?.transform = CATransform3DIdentity
                self.syncModalBlockingState()
            }
            if !isShowingSettings {
                focusComposer()
            }
        }
    }

    func toggleRateLimitsScreen() {
        showRateLimitsScreen(!isShowingRateLimits)
    }

    func toggleAppearanceQuick() {
        let currentTheme = KasugaiThemeTokens.resolve(
            palette: settings.palette,
            appearance: view.effectiveAppearance
        )
        var updated = settings
        updated.appearance = currentTheme.isLight ? .dark : .light
        _ = updated.save()
        applySettings(updated)
    }

    func applySettings(_ updated: KasugaiAppSettings) {
        settings = updated
        NSApp.appearance = updated.appearance.nsAppearance
        _ = core.setTelemetrySuppression(updated.suppressTelemetry)
        _ = core.setAutoApproveTools(updated.toolApprovalPolicy == .alwaysAllow)

        let theme = KasugaiThemeTokens.resolve(
            palette: updated.palette,
            appearance: view.effectiveAppearance
        )
        view.window?.backgroundColor = theme.canvasBg
        outerSplitView.themedBackgroundColor = theme.canvasBg
        outerSplitView.themedDividerColor = theme.borderSubtle
        centerVerticalSplit.innerSplitView.themedBackgroundColor = theme.canvasBg
        centerVerticalSplit.innerSplitView.themedDividerColor = theme.borderSubtle

        sidebarController.update(palette: updated.palette)
        chatAreaController.update(palette: updated.palette)
        factoryViewController.update(palette: updated.palette)
        chatAreaController.update(approvalPolicy: updated.toolApprovalPolicy)
        rateLimitsViewController.update(palette: updated.palette)
        diffController.update(palette: updated.palette)
        diffController.update(browserPolicy: updated.browserPolicy)
        terminalController.update(palette: updated.palette)
        syncOrchestratorBridge(enabled: updated.enableAgentOrchestration)
        if ProcessInfo.processInfo.environment["KASUGAI_SELF_TEST"] != "1"
            && updated.enableMobileBridge
        {
            configureMobileBridgeAsync(enabled: true, manageTailscale: true)
        }
        settingsViewController.update(
            settings: updated,
            storePath: storePath,
            socketPath: activeOrchestratorSocketPath
        )
        refreshFromCore()
    }

    func savePersistentUIStateNow() {
        flushActiveComposerDraft()
        saveRightPaneTabsNow()
    }

    func prepareForTerminate() {
        savePersistentUIStateNow()
        factoryStore.detachForUIReload()
        browserBridgeServer?.stop()
        browserBridgeServer = nil
        if core.isRemoteDaemon {
            core.disconnectClient()
        } else {
            stopOrchestratorBridge()
        }
    }

    private func scheduleRightPaneTabsSave() {
        pendingRightPaneTabsSaveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.saveRightPaneTabsNow()
        }
        pendingRightPaneTabsSaveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(180), execute: item)
    }

    private func saveRightPaneTabsNow() {
        pendingRightPaneTabsSaveWorkItem?.cancel()
        pendingRightPaneTabsSaveWorkItem = nil
        let snapshot = diffController.capturePersistedStore()
        _ = snapshot.save(to: rightPaneTabsStorePath)
    }

    private func scheduleDraftSave() {
        pendingDraftSaveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.saveDraftStoreNow()
        }
        pendingDraftSaveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250), execute: item)
    }

    private func saveDraftStoreNow() {
        pendingDraftSaveWorkItem?.cancel()
        pendingDraftSaveWorkItem = nil
        _ = draftStore.save(to: draftStorePath)
    }

    private func flushActiveComposerDraft() {
        if activeDraftThreadId > 0 {
            draftStore.setDraft(
                chatAreaController.composerView.currentDraft,
                for: activeDraftThreadId
            )
        }
        saveDraftStoreNow()
    }

    private func syncComposerDraft(forThreadId nextThreadId: Int64) {
        guard nextThreadId != activeDraftThreadId else {
            return
        }
        if activeDraftThreadId > 0 {
            draftStore.setDraft(
                chatAreaController.composerView.currentDraft,
                for: activeDraftThreadId
            )
            saveDraftStoreNow()
        }
        activeDraftThreadId = nextThreadId
        if nextThreadId > 0 {
            chatAreaController.composerView.restoreDraft(draftStore.draft(for: nextThreadId))
        } else {
            chatAreaController.composerView.restoreDraft(nil)
        }
    }

    func stopOrchestratorBridge() {
        guard !core.isRemoteDaemon else {
            return
        }
        orchestratorServer?.stop()
        orchestratorServer = nil
        _ = core.setOrchestratorBridge(socketPath: "", ctlBin: "")
    }

    private func syncOrchestratorBridge(enabled: Bool) {
        if core.isRemoteDaemon {
            let ctlBin = Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
            remoteOrchestratorSocketPath = core.setRemoteOrchestratorEnabled(
                enabled,
                ctlBin: ctlBin
            )
            return
        }
        if enabled {
            if orchestratorServer == nil {
                let server = LocalOrchestratorServer(core: core) { [weak self] in
                    self?.refreshFromCore()
                }
                if server.start() {
                    orchestratorServer = server
                    let ctlBin = Bundle.main.executableURL?.path ?? CommandLine.arguments[0]
                    _ = core.setOrchestratorBridge(socketPath: server.socketPath, ctlBin: ctlBin)
                }
            }
        } else {
            stopOrchestratorBridge()
        }
    }

    func focusComposer() {
        chatAreaController.composerView.focusInput()
    }

    func createNewThread(inProject projectIdOverride: Int64? = nil) {
        guard let snap = core.snapshot() else {
            return
        }
        let targetProjectId = projectIdOverride ?? snap.activeProjectId
        let active = snap.activeThread
        let inheritedProvider = active?.provider ?? settings.defaultProvider
        let provider =
            inheritedProvider == "local_echo" && settings.defaultProvider != "local_echo"
            ? settings.defaultProvider
            : inheritedProvider
        let model: String
        if provider == active?.provider,
            let activeModel = active?.model,
            !activeModel.isEmpty,
            activeModel != "default"
        {
            model = activeModel
        } else {
            model = ProviderModelCatalog.shared.defaultModelId(for: provider)
        }
        let effort = active?.effort ?? settings.defaultEffort
        if let createdId = core.createThread(
            projectId: targetProjectId,
            title: "",
            provider: provider,
            model: model,
            effort: effort
        ) {
            pinnedVisibleThreadId = createdId
        }
        refreshFromCore()
        focusComposer()
    }

    func selectThreadByUser(_ threadId: Int64) {
        guard threadId > 0 else {
            return
        }
        if isShowingSettings {
            showSettingsScreen(false)
        }
        if isShowingRateLimits {
            showRateLimitsScreen(false)
        }
        pinnedVisibleThreadId = threadId
        _ = core.selectThread(threadId)
        selectFactoryRun(nil)
        refreshFromCore()
        focusComposer()
    }

    func addProjectInteractive() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "選択"
        panel.message = "プロジェクトのフォルダを選択してください。"
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        openProject(at: url)
    }

    func openProject(at url: URL) {
        var isDir: ObjCBool = false
        let targetURL: URL
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            targetURL = url
        } else {
            targetURL = url.deletingLastPathComponent()
        }
        let canonical = GitWorkspace.canonicalPath(targetURL.path)
        if let snap = core.snapshot(),
            let existing = snap.projects.first(where: {
                GitWorkspace.canonicalPath($0.rootPath) == canonical
            })
        {
            _ = core.selectProject(existing.id)
            let deletedSet = Set(settings.deletedThreadIds)
            if let firstThread = snap.threads(forProject: existing.id).first(where: {
                !deletedSet.contains($0.id)
            }) {
                pinnedVisibleThreadId = firstThread.id
                _ = core.selectThread(firstThread.id)
            } else if let createdId = core.createThread(
                projectId: existing.id,
                title: "",
                provider: settings.defaultProvider,
                model: "",
                effort: settings.defaultEffort
            ) {
                pinnedVisibleThreadId = createdId
            }
            selectFactoryRun(nil)
            refreshFromCore()
            return
        }
        let name = targetURL.lastPathComponent.isEmpty ? "Project" : targetURL.lastPathComponent
        if let projectId = core.addProject(name: name, rootPath: canonical) {
            if let createdId = core.createThread(
                projectId: projectId,
                title: "",
                provider: settings.defaultProvider,
                model: "",
                effort: settings.defaultEffort
            ) {
                pinnedVisibleThreadId = createdId
            }
            selectFactoryRun(nil)
            refreshFromCore()
        }
    }

    func toggleLeftSidebar() {
        guard let sidebarItem else {
            return
        }
        let nextCollapsed = !sidebarItem.isCollapsed
        KasugaiInteractiveMotion.animateSplitCollapse(sidebarItem, collapsed: nextCollapsed)
        syncHeaderPaneStates(
            leftCollapsed: nextCollapsed,
            rightOpen: !(diffItem?.isCollapsed ?? true),
            terminalOpen: !(terminalItem?.isCollapsed ?? true)
        )
    }

    func focusThreadSearch() {
        if sidebarItem?.isCollapsed == true {
            sidebarItem?.isCollapsed = false
            syncHeaderPaneStates(
                leftCollapsed: false,
                rightOpen: !(diffItem?.isCollapsed ?? true),
                terminalOpen: !(terminalItem?.isCollapsed ?? true)
            )
        }
        sidebarController.setSearchOpen(true, focus: true)
    }

    private func ensureComfortableRightPaneWidth() {
        outerSplitView.adjustSubviews()
        outerSplitView.layoutSubtreeIfNeeded()
        let totalWidth = outerSplitView.bounds.width
        guard totalWidth >= 1040 else {
            return
        }
        let divider = outerSplitView.dividerThickness
        let leftWidth: CGFloat =
            (sidebarItem?.isCollapsed == true) ? 0 : sidebarController.view.frame.width
        let maxAllowed = totalWidth - leftWidth - divider * 2 - 280
        let desired = min(CGFloat(580), max(CGFloat(520), floor(totalWidth * 0.44)))
        let targetRight = min(desired, maxAllowed)
        guard targetRight >= 500 else {
            return
        }
        let dividerPos = totalWidth - divider - targetRight
        outerSplitView.setPosition(dividerPos, ofDividerAt: 1)
        outerSplitView.layoutSubtreeIfNeeded()
    }

    func toggleDiffPane() {
        guard let diffItem else {
            return
        }
        let nextCollapsed = !diffItem.isCollapsed
        if !nextCollapsed {
            diffController.ensureDefaultTabIfEmpty()
        }
        KasugaiInteractiveMotion.animateSplitCollapse(diffItem, collapsed: nextCollapsed) {
            [weak self] in
            if !nextCollapsed {
                self?.ensureComfortableRightPaneWidth()
            }
        }
        syncHeaderPaneStates(
            rightOpen: !nextCollapsed,
            terminalOpen: !(terminalItem?.isCollapsed ?? true)
        )
        if !nextCollapsed && diffController.activeTabKind == .diff {
            diffController.reloadDiffAsync()
        }
    }

    func openDiffTab(focusFile: String? = nil) {
        guard let diffItem else {
            return
        }
        let wasCollapsed = diffItem.isCollapsed
        diffController.openDiff(focusFile: focusFile)
        if wasCollapsed {
            KasugaiInteractiveMotion.animateSplitCollapse(diffItem, collapsed: false) {
                [weak self] in
                self?.ensureComfortableRightPaneWidth()
            }
        }
        syncHeaderPaneStates(
            rightOpen: true,
            terminalOpen: !(terminalItem?.isCollapsed ?? true)
        )
    }

    func openFilesTab(at directoryPath: String? = nil) {
        guard let diffItem else {
            return
        }
        let wasCollapsed = diffItem.isCollapsed
        diffController.openFiles(at: directoryPath)
        if wasCollapsed {
            KasugaiInteractiveMotion.animateSplitCollapse(diffItem, collapsed: false) {
                [weak self] in
                self?.ensureComfortableRightPaneWidth()
            }
        }
        syncHeaderPaneStates(
            rightOpen: true,
            terminalOpen: !(terminalItem?.isCollapsed ?? true)
        )
    }

    func browserTabsSummary(threadId: Int64? = nil) -> [BrowserTabInfo] {
        diffController.browserTabsSummary(threadId: threadId)
    }

    func browserEnsureTab(
        threadId: Int64? = nil,
        tabId: String?,
        openNew: Bool
    ) -> (tabId: String, view: LocalPreviewBrowserView)? {
        if diffController.isCurrentThread(threadId), let diffItem, diffItem.isCollapsed {
            diffItem.isCollapsed = false
            ensureComfortableRightPaneWidth()
            syncHeaderPaneStates(
                rightOpen: true,
                terminalOpen: !(terminalItem?.isCollapsed ?? true)
            )
        }
        return diffController.ensureBrowserTab(threadId: threadId, id: tabId, openNew: openNew)
    }

    func browserSelectTab(threadId: Int64? = nil, tabId: String) -> Bool {
        if diffController.isCurrentThread(threadId), let diffItem, diffItem.isCollapsed {
            diffItem.isCollapsed = false
            ensureComfortableRightPaneWidth()
            syncHeaderPaneStates(
                rightOpen: true,
                terminalOpen: !(terminalItem?.isCollapsed ?? true)
            )
        }
        return diffController.selectBrowserTab(threadId: threadId, id: tabId)
    }

    func browserCloseTab(threadId: Int64? = nil, tabId: String) -> Bool {
        diffController.closeBrowserTab(threadId: threadId, id: tabId)
    }

    func scrollSettingsToBottomForSnapshot() {
        settingsViewController.scrollToBottomForSnapshot()
    }

    func updateDiffPreviewForSnapshot(_ report: GitDiffReport) {
        chatAreaController.update(diffReport: report)
    }

    func openPreviewTab(path: String, lineRange: ClosedRange<Int>? = nil) {
        guard let diffItem else {
            return
        }
        let wasCollapsed = diffItem.isCollapsed
        diffController.showFilePreview(path: path, lineRange: lineRange)
        if wasCollapsed {
            KasugaiInteractiveMotion.animateSplitCollapse(diffItem, collapsed: false) {
                [weak self] in
                self?.ensureComfortableRightPaneWidth()
            }
        }
        syncHeaderPaneStates(
            rightOpen: true,
            terminalOpen: !(terminalItem?.isCollapsed ?? true)
        )
    }

    func openFileLink(_ target: FileLinkTarget) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir) else {
            return
        }
        if isDir.boolValue {
            openFilesTab(at: target.path)
            return
        }
        openPreviewTab(path: target.path, lineRange: target.lineRange)
    }

    private func selectFactoryRun(_ runId: String?) {
        let wasVisible = activeFactoryRunId != nil
        activeFactoryRunId = runId
        sidebarController.update(
            factoryRuns: factoryStore.allRuns,
            selectedFactoryRunId: activeFactoryRunId
        )
        if let runId, let run = factoryStore.run(withId: runId) {
            if !wasVisible {
                rightPaneWasOpenBeforeFactory = !(diffItem?.isCollapsed ?? true)
            }
            setOverlayMounted(
                factoryViewController.view,
                in: chatAreaController.view,
                visible: true
            )
            factoryViewController.display(run: run, childRuns: resolveChildRuns(for: run))
            if !wasVisible {
                KasugaiInteractiveMotion.animateDirectionalEnter(
                    view: factoryViewController.view,
                    direction: .fromLeft,
                    distance: 14,
                    duration: 0.16
                )
            }
            diffController.switchToFactoryRun(
                id: run.id,
                runDirectory: factoryStore.runDirectory(for: run.id).path
            )
            if let localURL = run.localPreviewURL, !localURL.isEmpty {
                openFactoryPreviewInRightPane(for: run)
            } else if let diffItem {
                let shouldCollapse = diffController.tabCount == 0
                if diffItem.isCollapsed != shouldCollapse {
                    diffItem.isCollapsed = shouldCollapse
                    if !shouldCollapse {
                        ensureComfortableRightPaneWidth()
                    }
                    syncHeaderPaneStates(
                        rightOpen: !shouldCollapse,
                        terminalOpen: !(terminalItem?.isCollapsed ?? true)
                    )
                }
            }
        } else {
            setOverlayMounted(
                factoryViewController.view,
                in: chatAreaController.view,
                visible: false
            )
            factoryViewController.display(run: nil)
            if wasVisible, let diffItem {
                if let activeThread = core.snapshot()?.activeThread {
                    diffController.update(thread: activeThread, forceRefresh: false)
                }
                let shouldCollapse = !rightPaneWasOpenBeforeFactory
                if diffItem.isCollapsed != shouldCollapse {
                    diffItem.isCollapsed = shouldCollapse
                    if !shouldCollapse {
                        ensureComfortableRightPaneWidth()
                    }
                    syncHeaderPaneStates(
                        rightOpen: !shouldCollapse,
                        terminalOpen: !(terminalItem?.isCollapsed ?? true)
                    )
                }
            }
        }
    }

    private func resolveChildRuns(for run: FactoryRunRecord) -> [String: FactoryRunRecord] {
        guard let map = run.childRunIds else {
            return [:]
        }
        var out: [String: FactoryRunRecord] = [:]
        for (stageId, childId) in map {
            if let child = factoryStore.run(withId: childId) {
                out[stageId] = child
            }
        }
        return out
    }

    private func openFactoryPreviewInRightPane(for run: FactoryRunRecord) {
        guard let localURL = run.localPreviewURL, !localURL.isEmpty else {
            return
        }
        if activeFactoryRunId == run.id {
            diffController.switchToFactoryRun(
                id: run.id,
                runDirectory: factoryStore.runDirectory(for: run.id).path
            )
            if let tab = browserEnsureTab(threadId: nil, tabId: nil, openNew: false) {
                tab.view.navigate(input: localURL)
            }
        }
    }

    func toggleTerminalPane() {
        guard let terminalItem else {
            return
        }
        let nextCollapsed = !terminalItem.isCollapsed
        KasugaiInteractiveMotion.animateSplitCollapse(terminalItem, collapsed: nextCollapsed)
        syncHeaderPaneStates(
            rightOpen: !(diffItem?.isCollapsed ?? true),
            terminalOpen: !nextCollapsed
        )
        if !nextCollapsed {
            terminalController.ensureStartedAndFocus()
        }
    }

    private func syncHeaderPaneStates(
        leftCollapsed: Bool? = nil,
        rightOpen: Bool,
        terminalOpen: Bool
    ) {
        let isLeftCollapsed = leftCollapsed ?? (sidebarItem?.isCollapsed ?? false)
        chatAreaController.setPaneStates(
            leftSidebarCollapsed: isLeftCollapsed,
            rightPaneOpen: rightOpen,
            terminalOpen: terminalOpen
        )
        factoryViewController.updatePaneStates(
            leftSidebarCollapsed: isLeftCollapsed,
            rightPaneOpen: rightOpen,
            terminalPaneOpen: terminalOpen
        )
        settingsViewController.setLeftSidebarCollapsed(isLeftCollapsed)
        rateLimitsViewController.setLeftSidebarCollapsed(isLeftCollapsed)
    }

    func capturePaneLayout() -> (
        sidebarCollapsed: Bool,
        sidebarWidth: Double,
        rightPaneCollapsed: Bool,
        rightPaneWidth: Double,
        terminalCollapsed: Bool,
        terminalHeight: Double,
        detailsCardOpen: Bool
    ) {
        let sidebarCollapsed = sidebarItem?.isCollapsed ?? false
        let sidebarWidth = Double(
            sidebarCollapsed ? 256 : max(200, min(340, sidebarController.view.frame.width))
        )
        let rightPaneCollapsed = diffItem?.isCollapsed ?? true
        let rightPaneWidth = Double(
            rightPaneCollapsed ? 540 : max(240, min(960, diffController.view.frame.width))
        )
        let terminalCollapsed = terminalItem?.isCollapsed ?? true
        let terminalHeight = Double(
            terminalCollapsed ? 220 : max(150, terminalController.view.frame.height)
        )
        return (
            sidebarCollapsed,
            sidebarWidth,
            rightPaneCollapsed,
            rightPaneWidth,
            terminalCollapsed,
            terminalHeight,
            chatAreaController.isDetailsCardUserOpen
        )
    }

    func restorePaneLayout(from state: KasugaiWindowState) {
        chatAreaController.setDetailsCardUserOpen(state.detailsCardOpen)
        sidebarItem?.isCollapsed = state.sidebarCollapsed
        if !state.rightPaneCollapsed {
            diffController.ensureDefaultTabIfEmpty()
        }
        diffItem?.isCollapsed = state.rightPaneCollapsed
        terminalItem?.isCollapsed = state.terminalCollapsed

        outerSplitView.adjustSubviews()
        outerSplitView.layoutSubtreeIfNeeded()
        let divider = outerSplitView.dividerThickness
        let totalWidth = outerSplitView.bounds.width
        if !state.sidebarCollapsed {
            let sideW = max(200, min(340, CGFloat(state.sidebarWidth)))
            outerSplitView.setPosition(sideW, ofDividerAt: 0)
        }
        if !state.rightPaneCollapsed && totalWidth > 600 {
            let leftW: CGFloat = state.sidebarCollapsed ? 0 : sidebarController.view.frame.width
            let maxRight = max(240, totalWidth - leftW - divider * 2 - 280)
            let rightW = max(240, min(CGFloat(state.rightPaneWidth), min(960, maxRight)))
            outerSplitView.setPosition(totalWidth - divider - rightW, ofDividerAt: 1)
        }
        if !state.terminalCollapsed {
            centerVerticalSplit.innerSplitView.adjustSubviews()
            centerVerticalSplit.innerSplitView.layoutSubtreeIfNeeded()
            let vTotal = centerVerticalSplit.innerSplitView.bounds.height
            let vDiv = centerVerticalSplit.innerSplitView.dividerThickness
            if vTotal > 320 {
                let termH = max(150, min(CGFloat(state.terminalHeight), vTotal - 160))
                centerVerticalSplit.innerSplitView.setPosition(
                    vTotal - vDiv - termH, ofDividerAt: 0)
            }
            terminalController.ensureStartedAndFocus()
        }
        syncHeaderPaneStates(
            leftCollapsed: state.sidebarCollapsed,
            rightOpen: !state.rightPaneCollapsed,
            terminalOpen: !state.terminalCollapsed
        )
        if !state.rightPaneCollapsed && diffController.activeTabKind == .diff {
            diffController.reloadDiffAsync()
        }
    }

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        guard diffItem != nil else {
            return
        }
        syncHeaderPaneStates(
            leftCollapsed: sidebarItem?.isCollapsed ?? false,
            rightOpen: !(diffItem?.isCollapsed ?? true),
            terminalOpen: !(terminalItem?.isCollapsed ?? true)
        )
        onLayoutStateChanged?()
    }

    func processQueuedTurns() {
        guard let threadId = core.snapshot()?.activeThreadId else {
            return
        }
        _ = core.processNextQueued(threadId: threadId)
        refreshFromCore()
    }

    private func wireActions() {
        sidebarController.onSelectProject = { [weak self] projectId in
            guard let self else {
                return
            }
            if self.isShowingSettings {
                self.showSettingsScreen(false)
            }
            if self.isShowingRateLimits {
                self.showRateLimitsScreen(false)
            }
            _ = self.core.selectProject(projectId)
            if let activeId = self.core.snapshot()?.activeThreadId, activeId > 0 {
                self.pinnedVisibleThreadId = activeId
            }
            self.selectFactoryRun(nil)
            self.refreshFromCore()
        }
        sidebarController.onSelectThread = { [weak self] threadId in
            self?.selectThreadByUser(threadId)
        }
        sidebarController.onCreateFactoryRun = { [weak self] in
            guard let self else {
                return
            }
            if self.isShowingSettings {
                self.showSettingsScreen(false)
            }
            if self.isShowingRateLimits {
                self.showRateLimitsScreen(false)
            }
            let created = self.factoryStore.createDraft()
            self.selectFactoryRun(created.id)
        }
        sidebarController.onSelectFactoryRun = { [weak self] runId in
            guard let self else {
                return
            }
            if self.isShowingSettings {
                self.showSettingsScreen(false)
            }
            if self.isShowingRateLimits {
                self.showRateLimitsScreen(false)
            }
            self.selectFactoryRun(runId)
        }
        sidebarController.onDeleteFactoryRun = { [weak self] runId in
            guard let self else {
                return
            }
            self.factoryStore.deleteRun(id: runId)
            if self.activeFactoryRunId == runId {
                self.selectFactoryRun(self.factoryStore.allRuns.first?.id)
            }
        }
        sidebarController.onAddProject = { [weak self] in
            self?.addProjectInteractive()
        }
        sidebarController.onCreateThread = { [weak self] projectId in
            if self?.isShowingSettings == true {
                self?.showSettingsScreen(false)
            }
            if self?.isShowingRateLimits == true {
                self?.showRateLimitsScreen(false)
            }
            self?.selectFactoryRun(nil)
            self?.createNewThread(inProject: projectId)
        }
        sidebarController.onTogglePinThread = { [weak self] threadId in
            self?.togglePinThread(threadId)
        }
        sidebarController.onToggleSettledThread = { [weak self] threadId in
            self?.toggleSettledThread(threadId)
        }
        sidebarController.onDeleteThread = { [weak self] threadId in
            self?.deleteThread(threadId)
        }
        sidebarController.onRenameThread = { [weak self] threadId, newTitle in
            guard let self else {
                return
            }
            _ = self.core.renameThread(threadId, title: newTitle)
            self.refreshFromCore()
        }
        sidebarController.onOpenRateLimits = { [weak self] in
            self?.toggleRateLimitsScreen()
        }
        sidebarController.onOpenSettings = { [weak self] in
            self?.toggleSettingsScreen()
        }
        sidebarController.onToggleAppearance = { [weak self] in
            self?.toggleAppearanceQuick()
        }

        settingsViewController.onSettingsChanged = { [weak self] updated in
            self?.applySettings(updated)
        }
        settingsViewController.onClearExternalBrowserData = {
            LocalPreviewBrowserView.clearExternalBrowserData()
        }
        settingsViewController.onClose = { [weak self] in
            self?.showSettingsScreen(false)
        }
        settingsViewController.onToggleMobileBridge = { [weak self] enabled in
            self?.configureMobileBridgeAsync(enabled: enabled, manageTailscale: true)
        }
        settingsViewController.onGenerateMobilePairing = { [weak self] in
            self?.generateMobilePairingAsync()
        }
        settingsViewController.onRevokeMobileDevice = { [weak self] deviceId in
            self?.revokeMobileDeviceAsync(deviceId: deviceId)
        }
        settingsViewController.onRefreshMobileBridgeStatus = { [weak self] in
            self?.refreshMobileBridgeStatusAsync(refreshTailscale: true)
        }
        rateLimitsViewController.onRefreshRequested = { [weak self] in
            guard let self else {
                return
            }
            RateLimitService.shared.refreshIfNeeded(
                suppressTelemetry: self.settings.suppressTelemetry,
                force: true
            )
        }
        rateLimitsViewController.onClose = { [weak self] in
            self?.showRateLimitsScreen(false)
        }

        factoryViewController.onToggleSidebar = { [weak self] in
            self?.toggleLeftSidebar()
        }
        factoryViewController.onToggleRightPane = { [weak self] in
            self?.toggleDiffPane()
        }
        factoryViewController.onToggleTerminal = { [weak self] in
            self?.toggleTerminalPane()
        }
        factoryViewController.onStartRun = {
            [weak self]
            runId, blueprintId, prompt, worker, workerModel, critic, criticModel, maxIter, minScore,
            rules, demoMode in
            guard let self else {
                return
            }
            let factoryProjectRoot =
                ProcessInfo.processInfo.environment["KASUGAI_FACTORY_PROJECT_ROOT"]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var factoryProjectId: Int64?
            if !factoryProjectRoot.isEmpty, let snap = self.core.snapshot() {
                if let existing = snap.projects.first(where: { $0.rootPath == factoryProjectRoot })
                {
                    factoryProjectId = existing.id
                } else if FileManager.default.fileExists(atPath: factoryProjectRoot) {
                    let name = URL(fileURLWithPath: factoryProjectRoot).lastPathComponent
                    factoryProjectId = self.core.addProject(
                        name: name.isEmpty ? "factory" : name,
                        rootPath: factoryProjectRoot
                    )
                }
            }
            self.factoryStore.startRun(
                id: runId,
                blueprintId: blueprintId,
                prompt: prompt,
                workerProvider: worker,
                workerModel: workerModel,
                criticProvider: critic,
                criticModel: criticModel,
                maxIterations: maxIter,
                minReviewScore: minScore,
                harnessRules: rules,
                ctlSocketPath: self.activeOrchestratorSocketPath,
                factoryProjectId: factoryProjectId,
                demoMode: demoMode
            )
        }
        factoryViewController.onSaveBlueprint = { [weak self] blueprint in
            self?.factoryStore.saveBlueprint(blueprint)
        }
        factoryViewController.onDuplicateBlueprint = { [weak self] sourceId, newName in
            self?.factoryStore.duplicateBlueprint(from: sourceId, newName: newName)
        }
        factoryViewController.onOpenBlueprintFile = { [weak self] blueprintId in
            guard let self else {
                return
            }
            let path = self.factoryStore.blueprintFileURL(for: blueprintId).path
            self.openPreviewTab(path: path)
        }
        factoryViewController.onStopRun = { [weak self] runId in
            self?.factoryStore.stopRun(id: runId)
        }
        factoryViewController.onOpenLocalPreview = { [weak self] run in
            self?.openFactoryPreviewInRightPane(for: run)
        }
        factoryViewController.onOpenExternalURL = { rawURL in
            if let url = URL(string: rawURL) {
                NSWorkspace.shared.open(url)
            }
        }
        factoryViewController.onPublishRun = { [weak self] runId in
            guard let self else {
                return
            }
            self.factoryStore.publishRun(
                id: runId,
                ctlSocketPath: self.activeOrchestratorSocketPath
            )
        }
        factoryViewController.onDiscardRun = { [weak self] runId in
            self?.factoryStore.discardRun(id: runId)
        }
        factoryViewController.onSelectThread = { [weak self] threadId in
            self?.selectThreadByUser(threadId)
        }
        factoryViewController.onSelectRun = { [weak self] runId in
            self?.selectFactoryRun(runId)
        }

        factoryStore.onBlueprintsChanged = { [weak self] blueprints in
            self?.factoryViewController.update(blueprints: blueprints)
        }
        factoryStore.onChanged = { [weak self] runs in
            guard let self else {
                return
            }
            self.sidebarController.update(
                factoryRuns: runs,
                selectedFactoryRunId: self.activeFactoryRunId
            )
            if let activeId = self.activeFactoryRunId,
                let activeRun = self.factoryStore.run(withId: activeId)
            {
                self.factoryViewController.display(
                    run: activeRun,
                    childRuns: self.resolveChildRuns(for: activeRun)
                )
            }
        }
        factoryStore.onPreviewReady = { [weak self] run in
            guard let self, self.activeFactoryRunId == run.id else {
                return
            }
            self.openFactoryPreviewInRightPane(for: run)
        }

        chatAreaController.onToggleSidebar = { [weak self] in
            self?.toggleLeftSidebar()
        }
        chatAreaController.onToggleRightPane = { [weak self] in
            self?.toggleDiffPane()
        }
        chatAreaController.onOpenDiffFile = { [weak self] filePath in
            self?.openDiffTab(focusFile: filePath)
        }
        chatAreaController.onOpenFilesTab = { [weak self] in
            self?.openFilesTab()
        }
        chatAreaController.onOpenFileLink = { [weak self] target in
            self?.openFileLink(target)
        }
        chatAreaController.onOpenThread = { [weak self] threadId in
            self?.selectThreadByUser(threadId)
        }
        chatAreaController.onDetailsCardOpenChanged = { [weak self] _ in
            self?.onLayoutStateChanged?()
        }
        chatAreaController.onToggleActiveThreadSettled = { [weak self] in
            guard let self, let activeId = self.core.snapshot()?.activeThreadId, activeId > 0 else {
                return
            }
            self.toggleSettledThread(activeId)
        }
        chatAreaController.onToggleTerminal = { [weak self] in
            self?.toggleTerminalPane()
        }
        chatAreaController.onRequestCreateWorktree = { [weak self] in
            self?.diffController.promptCreateWorktree()
        }
        chatAreaController.onResetWorktree = { [weak self] in
            guard let self, let threadId = self.core.snapshot()?.activeThreadId else {
                return
            }
            _ = self.core.resetWorktree(threadId: threadId)
            self.refreshFromCore(forceDiffRefresh: true)
        }
        chatAreaController.onApproveTool = { [weak self] in
            self?.resolveActiveApproval(approve: true)
        }
        chatAreaController.onDenyTool = { [weak self] in
            self?.resolveActiveApproval(approve: false)
        }

        chatAreaController.composerView.onSend = { [weak self] text, attachments in
            guard let self, let snap = self.core.snapshot(), let thread = snap.activeThread else {
                return false
            }
            self.unsettleThreadIfNeeded(thread.id)
            if thread.isDefaultTitle {
                let derived = KasugaiThread.deriveTitle(from: text)
                if !derived.isEmpty {
                    _ = self.core.renameThread(thread.id, title: derived)
                }
            }
            guard
                self.core.sendMessage(threadId: thread.id, text: text, attachments: attachments)
                    != nil
            else {
                return false
            }
            self.refreshFromCore()
            return true
        }
        chatAreaController.composerView.onEnqueue = { [weak self] text, attachments in
            guard let self, let snap = self.core.snapshot(), let thread = snap.activeThread else {
                return false
            }
            self.unsettleThreadIfNeeded(thread.id)
            if thread.isDefaultTitle {
                let derived = KasugaiThread.deriveTitle(from: text)
                if !derived.isEmpty {
                    _ = self.core.renameThread(thread.id, title: derived)
                }
            }
            guard
                self.core.enqueueMessage(threadId: thread.id, text: text, attachments: attachments)
                    != nil
            else {
                return false
            }
            self.refreshFromCore()
            return true
        }
        chatAreaController.composerView.onProcessQueue = { [weak self] in
            self?.processQueuedTurns()
        }
        chatAreaController.composerView.onCancelTurn = { [weak self] in
            guard let self, let threadId = self.core.snapshot()?.activeThreadId else {
                return
            }
            _ = self.core.cancelActiveTurn(threadId: threadId)
            self.refreshFromCore()
        }
        chatAreaController.composerView.onProviderChanged = { [weak self] provider, model, effort in
            guard let self, let threadId = self.core.snapshot()?.activeThreadId else {
                return
            }
            _ = self.core.setThreadProvider(
                threadId,
                provider: provider,
                model: model,
                effort: effort
            )
            self.refreshFromCore()
        }
        chatAreaController.composerView.onApprovalPolicyChanged = { [weak self] policy in
            guard let self else {
                return
            }
            var updated = self.settings
            updated.toolApprovalPolicy = policy
            _ = updated.save()
            self.applySettings(updated)
        }
        chatAreaController.composerView.onDraftChanged = { [weak self] draft in
            guard let self, self.activeDraftThreadId > 0 else {
                return
            }
            self.draftStore.setDraft(draft, for: self.activeDraftThreadId)
            if draft.isEmpty {
                self.saveDraftStoreNow()
            } else {
                self.scheduleDraftSave()
            }
        }

        diffController.onCreateWorktree = { [weak self] branch, baseRef in
            self?.createWorktreeForActiveThread(branch: branch, baseRef: baseRef)
        }
        diffController.onToggleRightPane = { [weak self] in
            self?.toggleDiffPane()
        }
        diffController.onTabsStateChanged = { [weak self] in
            self?.scheduleRightPaneTabsSave()
        }
        diffController.onAllTabsClosed = { [weak self] in
            guard let self, let diffItem = self.diffItem, !diffItem.isCollapsed else {
                return
            }
            KasugaiInteractiveMotion.animateSplitCollapse(diffItem, collapsed: true)
            self.syncHeaderPaneStates(
                rightOpen: false,
                terminalOpen: !(self.terminalItem?.isCollapsed ?? true)
            )
        }
        diffController.onResetWorktree = { [weak self] in
            guard let self, let threadId = self.core.snapshot()?.activeThreadId else {
                return
            }
            _ = self.core.resetWorktree(threadId: threadId)
            self.refreshFromCore(forceDiffRefresh: true)
        }
        diffController.onAttachPreviewedFile = { [weak self] path in
            self?.chatAreaController.composerView.appendExternalAttachments([path])
        }
        diffController.onOpenFileLink = { [weak self] target in
            self?.openFileLink(target)
        }
        diffController.onDiffStatsComputed = { [weak self] threadId, files, ins, del in
            guard let self else {
                return
            }
            let existing = self.core.snapshot()?.threads.first(where: { $0.id == threadId })
            let statsChanged =
                existing == nil
                || existing?.workspace.diffFilesChanged != files
                || existing?.workspace.diffInsertions != ins
                || existing?.workspace.diffDeletions != del
            let step = SyncLoopMachine.advance(
                self.syncLoopState,
                statsChanged ? .diffComputedChanged : .diffComputedUnchanged
            )
            self.syncLoopState = step.state
            guard step.outcome == .emitStatsChanged else {
                return
            }
            _ = self.core.updateDiffStats(
                threadId: threadId,
                filesChanged: files,
                insertions: ins,
                deletions: del
            )
            if let snap = self.core.snapshot() {
                self.chatAreaController.update(snapshot: snap)
            }
        }
        diffController.onDiffReportComputed = { [weak self] threadId, report in
            guard let self, self.core.snapshot()?.activeThreadId == threadId else {
                return
            }
            self.chatAreaController.update(diffReport: report)
        }
    }

    private func resolveActiveApproval(approve: Bool) {
        guard let threadId = core.snapshot()?.activeThreadId else {
            return
        }
        _ = core.resolveApproval(threadId: threadId, approve: approve)
        refreshFromCore()
    }

    private func createWorktreeForActiveThread(branch: String, baseRef: String) {
        guard let thread = core.snapshot()?.activeThread else {
            return
        }
        switch GitWorkspace.createWorktree(
            in: thread.workspace.rootPath,
            branch: branch,
            baseRef: baseRef
        ) {
        case .success(let entry):
            _ = core.bindWorktree(
                threadId: thread.id,
                branch: entry.branch,
                baseRef: baseRef,
                worktreePath: entry.path
            )
            refreshFromCore(forceDiffRefresh: true)
        case .failure(let error):
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Worktree を作成できませんでした"
            alert.informativeText = error.message
            alert.addButton(withTitle: "閉じる")
            alert.runModal()
        }
    }

    private func syncProviderWakeupSources() {
        guard !core.isRemoteDaemon else {
            return
        }
        let activeFDs = Set(core.providerWakeupFDs().map(\.fd))
        let existingFDs = Set(wakeupSources.keys)

        for obsolete in existingFDs.subtracting(activeFDs) {
            wakeupSources[obsolete]?.cancel()
            wakeupSources.removeValue(forKey: obsolete)
        }

        for fd in activeFDs.subtracting(existingFDs) where fd >= 0 {
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
            source.setEventHandler { [weak self] in
                self?.pollProvidersAndRefresh()
            }
            source.resume()
            wakeupSources[fd] = source
        }
    }

    private func advanceSyncLoopAndRefresh() {
        guard let initialSnapshot = core.snapshot() else {
            return
        }
        let activeThread = initialSnapshot.activeThread
        let activeId = activeThread?.id ?? 0
        if syncLoopThreadId != activeId {
            syncLoopThreadId = activeId
            syncLoopState = .idleClean
        }
        let activeStatus = activeThread?.status ?? ""
        let isBusyNow = activeStatus == "running" || activeStatus == "awaiting_approval"
        let diffVisible = activeFactoryRunId == nil && !(diffItem?.isCollapsed ?? true)
        let event: SyncLoopEvent
        if isBusyNow {
            event = diffVisible ? .remoteChangedBusyDiffOpen : .remoteChangedBusy
        } else {
            event = .remoteChangedIdle
        }
        let wasBusy = syncLoopState == .busyClean || syncLoopState == .busyDiffPending
        let step = SyncLoopMachine.advance(syncLoopState, event)
        syncLoopState = step.state
        let shouldRefreshDiff = step.outcome == .startDiff
        refreshFromCore(
            forceDiffRefresh: shouldRefreshDiff,
            preloadedSnapshot: initialSnapshot
        )
        if wasBusy && !isBusyNow {
            RateLimitService.shared.refreshIfNeeded(
                suppressTelemetry: settings.suppressTelemetry,
                minIntervalSeconds: 45
            )
        }
    }

    func reloadViewAndReconnect() {
        if core.isRemoteDaemon {
            _ = core.ensureRemoteDaemonAlive()
            handleRemoteDaemonReconnected()
        }
        chatAreaController.chatWebView.reloadRendererAssets()
        diffController.reloadRendererAssets()
        refreshFromCore(forceDiffRefresh: true)
    }

    func restartDaemonIfIdle() {
        guard core.isRemoteDaemon else {
            reloadViewAndReconnect()
            return
        }
        if let hello = core.remoteHello(), hello.activeTurnCount > 0 {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "コアデーモンを再起動できません"
            alert.informativeText =
                "実行中のターンが \(hello.activeTurnCount) 件あります。完了後に再実行してください。"
            alert.addButton(withTitle: "閉じる")
            alert.runModal()
            return
        }
        if core.restartRemoteDaemonIfIdle() {
            handleRemoteDaemonReconnected()
            chatAreaController.chatWebView.reloadRendererAssets()
            diffController.reloadRendererAssets()
        }
    }

    private func handleRemoteDaemonReconnected() {
        _ = core.setTelemetrySuppression(settings.suppressTelemetry)
        _ = core.setAutoApproveTools(settings.toolApprovalPolicy == .alwaysAllow)
        syncOrchestratorBridge(enabled: settings.enableAgentOrchestration)
        if settings.enableMobileBridge {
            configureMobileBridgeAsync(enabled: true, manageTailscale: true)
        }
        settingsViewController.update(
            settings: settings,
            storePath: storePath,
            socketPath: activeOrchestratorSocketPath
        )
        refreshFromCore(forceDiffRefresh: true)
    }

    private func configureMobileBridgeAsync(enabled: Bool, manageTailscale: Bool) {
        let localPort = settings.mobileBridgeLocalPort
        let httpsPort = settings.mobileBridgeHttpsPort
        let coreRef = core
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let status =
                coreRef.configureMobileBridge(
                    enabled: enabled,
                    localPort: localPort,
                    httpsPort: httpsPort,
                    manageTailscale: manageTailscale
                ) ?? .disabled
            DispatchQueue.main.async {
                self?.settingsViewController.update(mobileBridgeStatus: status)
            }
        }
    }

    private func refreshMobileBridgeStatusAsync(refreshTailscale: Bool) {
        let coreRef = core
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let status =
                coreRef.mobileBridgeStatus(refreshTailscale: refreshTailscale) ?? .disabled
            DispatchQueue.main.async {
                self?.settingsViewController.update(mobileBridgeStatus: status)
            }
        }
    }

    private func generateMobilePairingAsync() {
        let coreRef = core
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let status = coreRef.generateMobilePairingCode() else {
                return
            }
            DispatchQueue.main.async {
                self?.settingsViewController.update(mobileBridgeStatus: status)
            }
        }
    }

    private func revokeMobileDeviceAsync(deviceId: String) {
        let coreRef = core
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let status = coreRef.revokeMobileDevice(id: deviceId) else {
                return
            }
            DispatchQueue.main.async {
                self?.settingsViewController.update(mobileBridgeStatus: status)
            }
        }
    }

    private func handleRemoteCoreChanged() {
        advanceSyncLoopAndRefresh()
    }

    private func pollProvidersAndRefresh() {
        let changed = core.pollProviders()
        syncProviderWakeupSources()
        if changed {
            advanceSyncLoopAndRefresh()
        }
    }

    private func togglePinThread(_ threadId: Int64) {
        var updated = settings
        if let idx = updated.pinnedThreadIds.firstIndex(of: threadId) {
            updated.pinnedThreadIds.remove(at: idx)
        } else {
            updated.pinnedThreadIds.append(threadId)
        }
        settings = updated
        _ = updated.save()
        refreshFromCore()
    }

    private func nextVisibleThreadId(
        excluding excludedId: Int64,
        in snapshot: KasugaiCoreSnapshot,
        preferActive: Bool
    ) -> Int64? {
        let deletedSet = Set(settings.deletedThreadIds)
        let settledSet = Set(settings.settledThreadIds)
        let candidates = snapshot.threads
            .filter { $0.id != excludedId && !deletedSet.contains($0.id) }
            .sorted { lhs, rhs in
                if lhs.updatedAtMs != rhs.updatedAtMs {
                    return lhs.updatedAtMs > rhs.updatedAtMs
                }
                return lhs.id > rhs.id
            }
        if preferActive, let active = candidates.first(where: { !settledSet.contains($0.id) }) {
            return active.id
        }
        return candidates.first?.id
    }

    private func toggleSettledThread(_ threadId: Int64) {
        var updated = settings
        let becameSettled: Bool
        if let idx = updated.settledThreadIds.firstIndex(of: threadId) {
            updated.settledThreadIds.remove(at: idx)
            becameSettled = false
        } else {
            updated.settledThreadIds.append(threadId)
            if let pinIdx = updated.pinnedThreadIds.firstIndex(of: threadId) {
                updated.pinnedThreadIds.remove(at: pinIdx)
            }
            becameSettled = true
        }
        settings = updated
        _ = updated.save()
        if becameSettled,
            let snap = core.snapshot(),
            threadId == pinnedVisibleThreadId || threadId == snap.activeThreadId
        {
            let settledSet = Set(settings.settledThreadIds)
            let deletedSet = Set(settings.deletedThreadIds)
            if let nextActive = snap.threads
                .filter({
                    $0.id != threadId && !deletedSet.contains($0.id) && !settledSet.contains($0.id)
                })
                .sorted(by: { lhs, rhs in
                    if lhs.updatedAtMs != rhs.updatedAtMs {
                        return lhs.updatedAtMs > rhs.updatedAtMs
                    }
                    return lhs.id > rhs.id
                })
                .first
            {
                pinnedVisibleThreadId = nextActive.id
                _ = core.selectThread(nextActive.id)
            }
        }
        refreshFromCore()
    }

    func deleteThread(_ threadId: Int64) {
        guard threadId > 0 else {
            return
        }
        let snap = core.snapshot()
        if let target = snap?.threads.first(where: { $0.id == threadId }),
            target.status == "running"
        {
            _ = core.cancelActiveTurn(threadId: threadId)
        }
        var updated = settings
        if !updated.deletedThreadIds.contains(threadId) {
            updated.deletedThreadIds.append(threadId)
        }
        updated.pinnedThreadIds.removeAll { $0 == threadId }
        updated.settledThreadIds.removeAll { $0 == threadId }
        settings = updated
        _ = updated.save()

        if activeDraftThreadId == threadId {
            activeDraftThreadId = 0
            chatAreaController.composerView.restoreDraft(nil)
        }
        draftStore.setDraft(KasugaiComposerDraft(text: "", attachments: []), for: threadId)
        saveDraftStoreNow()
        diffController.removeThreadState(for: threadId)
        saveRightPaneTabsNow()

        let wasActive =
            pinnedVisibleThreadId == threadId || (snap?.activeThreadId == threadId)
        if wasActive {
            if let snap,
                let nextId = nextVisibleThreadId(
                    excluding: threadId,
                    in: snap,
                    preferActive: true
                )
            {
                pinnedVisibleThreadId = nextId
                _ = core.selectThread(nextId)
                refreshFromCore()
            } else {
                pinnedVisibleThreadId = 0
                createNewThread()
            }
        } else {
            refreshFromCore()
        }
    }

    private func unsettleThreadIfNeeded(_ threadId: Int64) {
        guard let idx = settings.settledThreadIds.firstIndex(of: threadId) else {
            return
        }
        var updated = settings
        updated.settledThreadIds.remove(at: idx)
        settings = updated
        _ = updated.save()
    }

    private func autoApprovePendingIfNeeded(in snapshot: KasugaiCoreSnapshot) -> Bool {
        var resolvedAny = false
        for thread in snapshot.threads where thread.pendingApproval.active {
            let isFactoryThread =
                thread.title.hasPrefix("[工場]") || thread.title.hasPrefix("[BGM工場]")
            guard settings.toolApprovalPolicy == .alwaysAllow || isFactoryThread else {
                continue
            }
            guard !autoApprovingThreadIds.contains(thread.id) else {
                continue
            }
            autoApprovingThreadIds.insert(thread.id)
            let ok = core.resolveApproval(threadId: thread.id, approve: true)
            autoApprovingThreadIds.remove(thread.id)
            if ok {
                resolvedAny = true
            }
        }
        return resolvedAny
    }

    private func refreshFromCore(
        forceDiffRefresh: Bool = false,
        preloadedSnapshot: KasugaiCoreSnapshot? = nil
    ) {
        guard var snapshot = preloadedSnapshot ?? core.snapshot() else {
            return
        }
        if autoApprovePendingIfNeeded(in: snapshot), let updated = core.snapshot() {
            snapshot = updated
        }
        let deletedSet = Set(settings.deletedThreadIds)
        if pinnedVisibleThreadId == 0 {
            if snapshot.activeThreadId > 0 && !deletedSet.contains(snapshot.activeThreadId) {
                pinnedVisibleThreadId = snapshot.activeThreadId
            } else if let fallbackId = nextVisibleThreadId(
                excluding: 0,
                in: snapshot,
                preferActive: true
            ) {
                pinnedVisibleThreadId = fallbackId
                _ = core.selectThread(fallbackId)
                if let restored = core.snapshot() {
                    snapshot = restored
                }
            }
        } else if deletedSet.contains(pinnedVisibleThreadId) {
            if let fallbackId = nextVisibleThreadId(
                excluding: pinnedVisibleThreadId,
                in: snapshot,
                preferActive: true
            ) {
                pinnedVisibleThreadId = fallbackId
                _ = core.selectThread(fallbackId)
                if let restored = core.snapshot() {
                    snapshot = restored
                }
            } else {
                pinnedVisibleThreadId = 0
            }
        } else if snapshot.activeThreadId != pinnedVisibleThreadId {
            if snapshot.threads.contains(where: { $0.id == pinnedVisibleThreadId }) {
                _ = core.selectThread(pinnedVisibleThreadId)
                if let restored = core.snapshot() {
                    snapshot = restored
                }
            } else {
                pinnedVisibleThreadId = snapshot.activeThreadId
            }
        }
        let previousThreadId = lastPresentedThreadId
        let previousRowIndex = lastPresentedThreadRowIndex
        syncComposerDraft(forThreadId: snapshot.activeThreadId)
        sidebarController.update(
            snapshot: snapshot,
            pinnedThreadIds: settings.pinnedThreadIds,
            settledThreadIds: settings.settledThreadIds,
            deletedThreadIds: settings.deletedThreadIds
        )
        let nextThreadId = snapshot.activeThreadId
        let nextRowIndex = sidebarController.rowIndex(forThreadId: nextThreadId)
        var threadTransition: KasugaiSlideDirection?
        if previousThreadId != 0 && nextThreadId != 0 && previousThreadId != nextThreadId {
            if let prevIdx = previousRowIndex, let nextIdx = nextRowIndex, prevIdx != nextIdx {
                threadTransition = nextIdx > prevIdx ? .fromBottom : .fromTop
            } else {
                threadTransition = .fromLeft
            }
        }
        lastPresentedThreadId = nextThreadId
        lastPresentedThreadRowIndex = nextRowIndex
        let activeThread = snapshot.activeThread
        let isActiveSettled =
            activeThread.map { settings.settledThreadIds.contains($0.id) } ?? false
        let canSettleActive = activeThread != nil && activeThread?.status != "running"
        chatAreaController.setActiveThreadSettleState(
            settled: isActiveSettled,
            visible: canSettleActive
        )
        chatAreaController.update(snapshot: snapshot, threadTransition: threadTransition)
        if activeFactoryRunId == nil {
            diffController.update(thread: snapshot.activeThread, forceRefresh: forceDiffRefresh)
        }
        terminalController.update(
            thread: snapshot.activeThread,
            isPaneVisible: !(terminalItem?.isCollapsed ?? true)
        )
        syncProviderWakeupSources()
    }

    static func runSelfTests() -> Bool {
        _ = NSApplication.shared
        guard let core = KasugaiCore(projectName: "Kasugai", projectPath: "/tmp") else {
            return false
        }
        let draftTestFile = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kasugai-split-drafts-\(UUID().uuidString).json"
        )
        defer { try? FileManager.default.removeItem(at: draftTestFile) }
        let rightPaneTabsTestFile = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kasugai-split-right-pane-tabs-\(UUID().uuidString).json"
        )
        defer { try? FileManager.default.removeItem(at: rightPaneTabsTestFile) }
        let factoryTestDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kasugai-split-factory-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: factoryTestDir) }
        var settings = KasugaiAppSettings.defaultValue
        settings.enableAgentOrchestration = false
        let controller = MainSplitViewController(
            core: core,
            settings: settings,
            storePath: "/tmp/events.jsonl",
            draftStorePath: draftTestFile.path,
            rightPaneTabsStorePath: rightPaneTabsTestFile.path,
            factoryRootDirectory: factoryTestDir
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 720, height: 480)
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 1280, height: 820))
        window.layoutIfNeeded()
        defer {
            controller.stopOrchestratorBridge()
            window.close()
        }

        guard controller.splitView.superview === controller.view,
            controller.splitViewItems.count == 3,
            window.styleMask.contains(.resizable),
            let contentSize = window.contentView?.frame.size,
            abs(contentSize.width - 1280) <= 2,
            abs(contentSize.height - 820) <= 2,
            controller.splitView.frame.width >= 1270,
            controller.splitView.frame.height >= 810
        else {
            return false
        }

        window.setContentSize(NSSize(width: 760, height: 500))
        window.layoutIfNeeded()
        guard let shrunk = window.contentView?.frame.size,
            shrunk.width <= 762,
            shrunk.height <= 502
        else {
            return false
        }
        window.setContentSize(NSSize(width: 1420, height: 880))
        window.layoutIfNeeded()
        guard let grown = window.contentView?.frame.size,
            grown.width >= 1418,
            grown.height >= 878
        else {
            return false
        }
        window.setContentSize(NSSize(width: 1280, height: 820))
        window.layoutIfNeeded()

        controller.showSettingsScreen(true)
        window.layoutIfNeeded()
        controller.settingsViewController.view.layoutSubtreeIfNeeded()
        let backdropFrame = controller.settingsViewController.view.convert(
            controller.settingsViewController.view.bounds,
            to: nil
        )
        let modalFrame = controller.settingsViewController.modalSurface.convert(
            controller.settingsViewController.modalSurface.bounds,
            to: nil
        )
        let titleFrame = controller.settingsViewController.headerTitleLabel.convert(
            controller.settingsViewController.headerTitleLabel.bounds,
            to: nil
        )
        let closeFrame = controller.settingsViewController.closeButton.convert(
            controller.settingsViewController.closeButton.bounds,
            to: nil
        )
        let telemetryFrame = controller.settingsViewController.telemetryCheck.convert(
            controller.settingsViewController.telemetryCheck.bounds,
            to: nil
        )
        let headingsLeftAligned = controller.settingsViewController.sectionLabels.allSatisfy {
            let f = $0.convert($0.bounds, to: nil)
            return abs(f.minX - (modalFrame.minX + 20)) <= 6
        }
        let cardsFullWidth = controller.settingsViewController.cardSurfaces.allSatisfy {
            let f = $0.convert($0.bounds, to: nil)
            return abs(f.minX - (modalFrame.minX + 20)) <= 6
                && abs(f.width - (modalFrame.width - 40)) <= 6
        }
        let settingsBackdropHit = controller.view.hitTest(NSPoint(x: 40, y: 120))
        let blockedSplitHit = controller.outerSplitView.hitTest(NSPoint(x: 40, y: 120))
        guard controller.isShowingSettings,
            !controller.settingsViewController.view.isHidden,
            controller.outerSplitView.isInteractionBlocked,
            blockedSplitHit == nil,
            settingsBackdropHit === controller.settingsViewController.view,
            abs(backdropFrame.width - 1280) <= 2,
            modalFrame.width >= 880,
            abs(modalFrame.midX - 640) <= 2,
            closeFrame.minX > titleFrame.maxX,
            abs(modalFrame.maxX - closeFrame.maxX) <= 20,
            abs(telemetryFrame.minX - (modalFrame.minX + 34)) <= 12,
            headingsLeftAligned,
            cardsFullWidth
        else {
            fputs(
                "MainSplitViewController self-test: settings layout mismatch backdrop=\(backdropFrame) modal=\(modalFrame) close=\(closeFrame) title=\(titleFrame) telemetry=\(telemetryFrame) headingsLeft=\(headingsLeftAligned) cardsFullWidth=\(cardsFullWidth) blockedSplitHit=\(String(describing: blockedSplitHit))\n",
                stderr
            )
            return false
        }
        for palette in [KasugaiPalette.forest, .rose, .twilight] {
            var next = settings
            next.appearance = .light
            next.palette = palette
            controller.applySettings(next)
            next.appearance = .dark
            controller.applySettings(next)
        }
        window.layoutIfNeeded()
        controller.showSettingsScreen(false)
        guard !controller.outerSplitView.isInteractionBlocked,
            controller.outerSplitView.hitTest(NSPoint(x: 40, y: 120)) != nil
        else {
            return false
        }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        guard
            KasugaiBrandIcons.relativeTimeLabel(
                fromMillis: Int64((now.timeIntervalSince1970 - 10) * 1000),
                now: now
            ) == "今",
            KasugaiBrandIcons.relativeTimeLabel(
                fromMillis: Int64((now.timeIntervalSince1970 - 300) * 1000),
                now: now
            ) == "5 分",
            KasugaiBrandIcons.relativeTimeLabel(
                fromMillis: Int64((now.timeIntervalSince1970 - 7200) * 1000),
                now: now
            ) == "2 時間",
            KasugaiBrandIcons.relativeTimeLabel(
                fromMillis: Int64((now.timeIntervalSince1970 - 172_800) * 1000),
                now: now
            ) == "2 日",
            KasugaiThread.deriveTitle(from: "\n  リファクタリングの相談  \n詳細")
                == "リファクタリングの相談",
            KasugaiBrandIcons.providerIcon(for: "claude_code").size
                == NSSize(width: 12, height: 12),
            KasugaiBrandIcons.projectBadge(name: "Kasugai", statusColor: nil, isLight: false).size
                == NSSize(width: 18, height: 18)
        else {
            return false
        }

        if let initialThread = core.snapshot()?.activeThread {
            guard initialThread.isDefaultTitle,
                initialThread.displayTitle == "新規スレッド",
                initialThread.updatedAtMs > 0
            else {
                return false
            }
            guard core.renameThread(initialThread.id, title: "サイドバー改修"),
                let renamed = core.snapshot()?.activeThread,
                !renamed.isDefaultTitle,
                renamed.displayTitle == "サイドバー改修"
            else {
                return false
            }
            controller.togglePinThread(initialThread.id)
            guard controller.settings.pinnedThreadIds.contains(initialThread.id) else {
                return false
            }
            controller.togglePinThread(initialThread.id)
            guard !controller.settings.pinnedThreadIds.contains(initialThread.id) else {
                return false
            }
            controller.toggleSettledThread(initialThread.id)
            guard controller.settings.settledThreadIds.contains(initialThread.id) else {
                return false
            }
            controller.unsettleThreadIfNeeded(initialThread.id)
            guard !controller.settings.settledThreadIds.contains(initialThread.id) else {
                return false
            }
            controller.sidebarController.setSearchQueryForTest("サイドバー改修")
            guard controller.sidebarController.visibleThreadCount == 1 else {
                return false
            }
            controller.sidebarController.setSearchQueryForTest("存在しない検索文字列xyz")
            guard controller.sidebarController.visibleThreadCount == 0 else {
                return false
            }
            controller.sidebarController.setSearchOpen(false, focus: false)
            guard controller.sidebarController.visibleThreadCount >= 1 else {
                return false
            }
        }

        let sampleSnap = KasugaiRateLimitSnapshot(
            claude: KasugaiProviderRateLimit(
                providerId: "claude_code",
                displayName: "Claude Code",
                plan: "Max",
                windows: [
                    KasugaiRateLimitWindow(
                        id: "seven_day",
                        label: "週間",
                        usedPercent: 59,
                        resetsAt: now.addingTimeInterval(3 * 86400),
                        windowDurationMins: 7 * 24 * 60
                    ),
                    KasugaiRateLimitWindow(
                        id: "scoped_fable",
                        label: "Fable",
                        usedPercent: 16,
                        resetsAt: now.addingTimeInterval(3 * 86400),
                        windowDurationMins: 7 * 24 * 60
                    ),
                ],
                resetCreditsAvailable: nil,
                status: .available,
                checkedAt: now
            ),
            codex: KasugaiProviderRateLimit(
                providerId: "codex",
                displayName: "Codex",
                plan: "Plus",
                windows: [
                    KasugaiRateLimitWindow(
                        id: "primary",
                        label: "5 時間",
                        usedPercent: 8,
                        resetsAt: now.addingTimeInterval(5000),
                        windowDurationMins: 300
                    ),
                    KasugaiRateLimitWindow(
                        id: "secondary",
                        label: "週間",
                        usedPercent: 13,
                        resetsAt: now.addingTimeInterval(4 * 86400),
                        windowDurationMins: 7 * 24 * 60
                    ),
                ],
                resetCreditsAvailable: 3,
                status: .available,
                checkedAt: now
            ),
            antigravity: KasugaiProviderRateLimit(
                providerId: "antigravity_acp",
                displayName: "Antigravity（Gemini）",
                plan: nil,
                windows: [
                    KasugaiRateLimitWindow(
                        id: "gemini-5h",
                        label: "Gemini 5 時間",
                        usedPercent: 6,
                        resetsAt: now.addingTimeInterval(3 * 3600 + 50 * 60),
                        windowDurationMins: 300
                    ),
                    KasugaiRateLimitWindow(
                        id: "gemini-weekly",
                        label: "Gemini 週間",
                        usedPercent: 30,
                        resetsAt: now.addingTimeInterval(5 * 86400 + 16 * 3600),
                        windowDurationMins: 7 * 24 * 60
                    ),
                    KasugaiRateLimitWindow(
                        id: "3p-5h",
                        label: "他モデル 5 時間",
                        usedPercent: 0,
                        resetsAt: nil,
                        windowDurationMins: 300
                    ),
                    KasugaiRateLimitWindow(
                        id: "3p-weekly",
                        label: "他モデル 週間",
                        usedPercent: 0,
                        resetsAt: nil,
                        windowDurationMins: 7 * 24 * 60
                    ),
                ],
                resetCreditsAvailable: nil,
                status: .available,
                checkedAt: now
            ),
            opencodeInstalled: true,
            opencodeUsage: KasugaiOpencodeUsage(
                today: KasugaiOpencodeWindowStats(
                    sessions: 7,
                    prompts: 7,
                    totalTokens: 1_877_476,
                    cost: 0
                ),
                sevenDay: KasugaiOpencodeWindowStats(
                    sessions: 9,
                    prompts: 12,
                    totalTokens: 3_520_000,
                    cost: 0
                )
            ),
            isRefreshing: false,
            lastUpdated: now
        )
        controller.sidebarController.update(rateLimits: sampleSnap)
        controller.rateLimitsViewController.update(snapshot: sampleSnap)
        controller.showRateLimitsScreen(true)
        window.setContentSize(NSSize(width: 860, height: 560))
        window.layoutIfNeeded()
        controller.rateLimitsViewController.view.layoutSubtreeIfNeeded()
        func containsScrollView(_ view: NSView) -> Bool {
            if view is NSScrollView {
                return true
            }
            return view.subviews.contains(where: containsScrollView)
        }
        let rlBackdrop = controller.rateLimitsViewController.view.convert(
            controller.rateLimitsViewController.view.bounds,
            to: nil
        )
        let rlModal = controller.rateLimitsViewController.modalSurface.convert(
            controller.rateLimitsViewController.modalSurface.bounds,
            to: nil
        )
        let rlClose = controller.rateLimitsViewController.closeButton.convert(
            controller.rateLimitsViewController.closeButton.bounds,
            to: nil
        )
        let rlTitle = controller.rateLimitsViewController.titleLabel.convert(
            controller.rateLimitsViewController.titleLabel.bounds,
            to: nil
        )
        let clampedOrigin = KasugaiInteractiveMotion.clampedOriginOffset(
            from: NSPoint(x: 24, y: 20),
            to: NSRect(x: 300, y: 100, width: 680, height: 600)
        )
        guard controller.isShowingRateLimits,
            !controller.rateLimitsViewController.view.isHidden,
            !controller.isShowingSettings,
            controller.outerSplitView.isInteractionBlocked,
            controller.outerSplitView.hitTest(NSPoint(x: 20, y: 20)) == nil,
            !containsScrollView(controller.rateLimitsViewController.view),
            controller.rateLimitsViewController.view.fittingSize.height <= 560,
            abs(rlBackdrop.width - 860) <= 2,
            rlModal.width >= 780,
            abs(rlModal.midX - 430) <= 2,
            rlClose.minX > rlTitle.maxX,
            clampedOrigin.x < 0,
            clampedOrigin.y < 0,
            abs(clampedOrigin.x) <= 132.5,
            abs(clampedOrigin.y) <= 92.5
        else {
            fputs(
                "MainSplitViewController self-test: rateLimits layout mismatch backdrop=\(rlBackdrop) modal=\(rlModal) close=\(rlClose) title=\(rlTitle) fit=\(controller.rateLimitsViewController.view.fittingSize)\n",
                stderr
            )
            return false
        }
        controller.showRateLimitsScreen(false)
        guard !controller.outerSplitView.isInteractionBlocked else {
            return false
        }

        let filesTabId = controller.diffController.openTab(.files)
        let browserTab1 = controller.diffController.openTab(.browser)
        let browserTab2 = controller.diffController.openTab(.browser)
        guard browserTab1 != browserTab2,
            controller.diffController.tabCount == 4,
            controller.diffController.activeTabKind == .browser
        else {
            return false
        }
        controller.diffItem?.isCollapsed = false
        window.layoutIfNeeded()
        controller.diffController.view.layoutSubtreeIfNeeded()
        if let closeBtn = controller.diffController.activeTabCloseButtonForTest() {
            let btnRectInWindow = closeBtn.convert(closeBtn.bounds, to: nil)
            let hitPt = NSPoint(x: btnRectInWindow.midX, y: btnRectInWindow.midY)
            let hitView = window.contentView?.hitTest(hitPt)
            guard hitView === closeBtn, !closeBtn.mouseDownCanMoveWindow else {
                fputs(
                    "MainSplitViewController self-test: close button hitTest mismatch hit=\(String(describing: hitView)) btnRect=\(btnRectInWindow)\n",
                    stderr
                )
                return false
            }
            closeBtn.performClick(nil)
            guard controller.diffController.tabCount == 3 else {
                fputs(
                    "MainSplitViewController self-test: close button click did not close tab\n",
                    stderr
                )
                return false
            }
        } else {
            return false
        }
        controller.diffController.closeTab(id: browserTab1)
        controller.diffController.closeTab(id: filesTabId)
        controller.diffItem?.isCollapsed = true
        guard controller.diffController.tabCount == 1,
            controller.diffController.activeTabKind == .diff
        else {
            return false
        }

        if let thread1Id = core.snapshot()?.activeThreadId, thread1Id > 0,
            let projectId = core.snapshot()?.activeProjectId, projectId > 0,
            let thread2Id = core.createThread(
                projectId: projectId,
                title: "スレッド別タブ確認",
                provider: "local_echo",
                model: "default",
                effort: "medium"
            )
        {
            controller.refreshFromCore()
            guard core.snapshot()?.activeThreadId == thread1Id else {
                fputs(
                    "MainSplitViewController self-test: background thread creation hijacked active thread\n",
                    stderr
                )
                return false
            }
            controller.selectThreadByUser(thread2Id)
            _ = controller.diffController.openTab(.browser)
            guard controller.diffController.tabCount == 2,
                controller.diffController.activeTabKind == .browser
            else {
                return false
            }
            controller.selectThreadByUser(thread1Id)
            guard controller.diffController.tabCount == 1,
                controller.diffController.activeTabKind == .diff
            else {
                return false
            }
            controller.selectThreadByUser(thread2Id)
            guard controller.diffController.tabCount == 2,
                controller.diffController.activeTabKind == .browser
            else {
                return false
            }
            controller.selectThreadByUser(thread1Id)
            controller.diffItem?.isCollapsed = true
            let bgTarget = controller.browserEnsureTab(
                threadId: thread2Id,
                tabId: nil,
                openNew: true
            )
            bgTarget?.view.navigate(input: "http://localhost:4321/preview")
            let bgTabs = controller.browserTabsSummary(threadId: thread2Id)
            let fgTabs = controller.browserTabsSummary(threadId: thread1Id)
            guard let bgView = bgTarget?.view,
                bgView.window != nil,
                bgView.frame.width >= 640,
                bgView.frame.height >= 480,
                controller.diffItem?.isCollapsed == true,
                controller.diffController.tabCount == 1,
                controller.diffController.activeTabKind == .diff,
                fgTabs.isEmpty,
                bgTabs.contains(where: { $0.url == "http://localhost:4321/preview" })
            else {
                fputs(
                    "MainSplitViewController self-test: background browser leaked to foreground thread\n",
                    stderr
                )
                return false
            }
            controller.selectThreadByUser(thread2Id)
            guard controller.diffController.activeTabKind == .browser,
                controller.browserTabsSummary().contains(where: {
                    $0.url == "http://localhost:4321/preview"
                }),
                !controller.chatAreaController.settleThreadButton.isHidden
            else {
                return false
            }
            controller.chatAreaController.settleThreadButton.performClick(nil)
            guard controller.settings.settledThreadIds.contains(thread2Id),
                core.snapshot()?.activeThreadId == thread1Id
            else {
                fputs(
                    "MainSplitViewController self-test: header settle button did not settle and switch away\n",
                    stderr
                )
                return false
            }
            controller.deleteThread(thread2Id)
            guard controller.settings.deletedThreadIds.contains(thread2Id),
                !controller.settings.settledThreadIds.contains(thread2Id),
                controller.sidebarController.rowIndex(forThreadId: thread2Id) == nil
            else {
                fputs(
                    "MainSplitViewController self-test: deleteThread did not hide thread\n",
                    stderr
                )
                return false
            }
            if let thread3Id = core.createThread(
                projectId: projectId,
                title: "削除切替テスト",
                provider: "local_echo",
                model: "default",
                effort: "medium"
            ) {
                controller.selectThreadByUser(thread3Id)
                controller.deleteThread(thread3Id)
                guard core.snapshot()?.activeThreadId == thread1Id,
                    controller.sidebarController.rowIndex(forThreadId: thread3Id) == nil
                else {
                    fputs(
                        "MainSplitViewController self-test: deleting active thread did not switch to remaining thread\n",
                        stderr
                    )
                    return false
                }
            }
            controller.selectThreadByUser(thread1Id)
        }

        let sampleDiffReport = GitDiffReport(
            directory: "/tmp",
            branch: "main",
            isGitRepo: true,
            filesChanged: 2,
            insertions: 18,
            deletions: 4,
            statusLines: [" M app/Sources/ComposerView.swift", "?? app/Sources/NewFile.swift"],
            unifiedDiff: "",
            files: [
                GitDiffFileEntry(
                    path: "app/Sources/ComposerView.swift",
                    status: "M",
                    insertions: 12,
                    deletions: 4,
                    patch: "@@ -1,2 +1,3 @@\n line1\n+line2"
                ),
                GitDiffFileEntry(
                    path: "app/Sources/NewFile.swift",
                    status: "?",
                    insertions: 6,
                    deletions: 0,
                    patch: "@@ -0,0 +1,2 @@\n+hello"
                ),
            ]
        )
        controller.chatAreaController.update(diffReport: sampleDiffReport)
        window.setContentSize(NSSize(width: 760, height: 500))
        window.layoutIfNeeded()
        guard let shrunkWithDiffCard = window.contentView?.frame.size,
            shrunkWithDiffCard.width <= 762,
            shrunkWithDiffCard.height <= 502
        else {
            return false
        }
        window.setContentSize(NSSize(width: 1280, height: 820))
        window.layoutIfNeeded()
        let closedRightBtnFrame = controller.chatAreaController.rightPaneButton.convert(
            controller.chatAreaController.rightPaneButton.bounds,
            to: nil
        )
        let closedTermBtnFrame = controller.chatAreaController.terminalButton.convert(
            controller.chatAreaController.terminalButton.bounds,
            to: nil
        )
        let wideDetailsCardFrame = controller.chatAreaController.detailsCard.convert(
            controller.chatAreaController.detailsCard.bounds,
            to: nil
        )
        guard !controller.chatAreaController.rightPaneButton.isHidden,
            !controller.chatAreaController.detailsCard.isHidden,
            abs(wideDetailsCardFrame.width - ThreadDetailsCardView.cardWidth) <= 1,
            abs((1280 - wideDetailsCardFrame.maxX) - 12) <= 2,
            closedRightBtnFrame.minX > closedTermBtnFrame.maxX,
            abs((1280 - closedRightBtnFrame.maxX) - 12) <= 2
        else {
            fputs(
                "MainSplitViewController self-test: detailsCard hidden=\(controller.chatAreaController.detailsCard.isHidden) frame=\(wideDetailsCardFrame)\n",
                stderr
            )
            return false
        }
        controller.chatAreaController.detailsCardButton.performClick(nil)
        guard controller.chatAreaController.detailsCard.isHidden else {
            return false
        }
        controller.chatAreaController.detailsCardButton.performClick(nil)
        guard !controller.chatAreaController.detailsCard.isHidden else {
            return false
        }
        controller.openFileLink(FileLinkTarget(path: "/tmp", lineStart: nil, lineEnd: nil))
        guard controller.diffController.activeTabKind == .files else {
            return false
        }
        controller.openDiffTab(focusFile: "app/Sources/ComposerView.swift")
        window.layoutIfNeeded()
        let openRightToggleFrame = controller.diffController.rightPaneToggleButton.convert(
            controller.diffController.rightPaneToggleButton.bounds,
            to: nil
        )
        guard controller.diffController.view.frame.width >= 500,
            controller.chatAreaController.rightPaneButton.isHidden,
            !controller.diffController.rightPaneToggleButton.isHidden,
            abs((1280 - openRightToggleFrame.maxX) - 12) <= 2,
            abs(openRightToggleFrame.maxX - closedRightBtnFrame.maxX) <= 2
        else {
            fputs(
                "MainSplitViewController self-test: diff width \(controller.diffController.view.frame.width), outer \(controller.outerSplitView.bounds.width), closedRight=\(closedRightBtnFrame.maxX), openRight=\(openRightToggleFrame.maxX)\n",
                stderr
            )
            return false
        }
        let leftDivY = controller.sidebarController.topDivider.convert(
            controller.sidebarController.topDivider.bounds,
            to: nil
        ).minY
        let centerDivY = controller.chatAreaController.headerDivider.convert(
            controller.chatAreaController.headerDivider.bounds,
            to: nil
        ).minY
        let rightDivY = controller.diffController.headerDivider.convert(
            controller.diffController.headerDivider.bounds,
            to: nil
        ).minY
        guard abs(leftDivY - centerDivY) <= 0.5, abs(rightDivY - centerDivY) <= 0.5 else {
            fputs(
                "MainSplitViewController self-test: divider Y mismatch left=\(leftDivY) center=\(centerDivY) right=\(rightDivY)\n",
                stderr
            )
            return false
        }
        if let closeBtn = window.standardWindowButton(.closeButton) {
            let closeMidY = closeBtn.convert(closeBtn.bounds, to: nil).midY
            let headerMidY = controller.chatAreaController.headerBar.convert(
                controller.chatAreaController.headerBar.bounds,
                to: nil
            ).midY
            guard abs(closeMidY - headerMidY) <= 1.5 else {
                fputs(
                    "MainSplitViewController self-test: traffic light alignment mismatch closeMidY=\(closeMidY) headerMidY=\(headerMidY)\n",
                    stderr
                )
                return false
            }
        }
        guard !controller.chatAreaController.detailsCardButton.isHidden,
            controller.chatAreaController.detailsCard.isHidden
        else {
            return false
        }
        let wideBrowserTab = controller.diffController.openTab(.browser)
        controller.outerSplitView.setPosition(680, ofDividerAt: 1)
        window.layoutIfNeeded()
        controller.outerSplitView.layoutSubtreeIfNeeded()
        let browserPaneWidth = controller.diffController.view.frame.width
        controller.diffController.closeTab(id: wideBrowserTab)
        guard browserPaneWidth >= 580 else {
            fputs(
                "MainSplitViewController self-test: browser pane snapped back width=\(browserPaneWidth)\n",
                stderr
            )
            return false
        }

        window.setContentSize(NSSize(width: 760, height: 500))
        window.layoutIfNeeded()
        guard let shrunkWithDiffOpen = window.contentView?.frame.size,
            shrunkWithDiffOpen.width <= 762,
            shrunkWithDiffOpen.height <= 502
        else {
            fputs(
                "MainSplitViewController self-test: shrunkWithDiffOpen \(String(describing: window.contentView?.frame.size))\n",
                stderr
            )
            return false
        }
        controller.chatAreaController.update(diffReport: nil)
        window.layoutIfNeeded()

        if let activeId = core.snapshot()?.activeThreadId, activeId > 0 {
            let typedDraft = KasugaiComposerDraft(text: "relaunch で残すテキスト", attachments: [])
            controller.chatAreaController.composerView.restoreDraft(typedDraft)
            if let ensured = controller.browserEnsureTab(tabId: nil, openNew: true) {
                ensured.view.navigate(input: "http://localhost:5173/dashboard")
            }
            controller.prepareForTerminate()
            let persisted = KasugaiDraftStore.load(from: draftTestFile.path)
            let persistedTabs = KasugaiRightPaneTabStore.load(from: rightPaneTabsTestFile.path)
            let restoredController = MainSplitViewController(
                core: core,
                settings: settings,
                storePath: "/tmp/events.jsonl",
                draftStorePath: draftTestFile.path,
                rightPaneTabsStorePath: rightPaneTabsTestFile.path,
                factoryRootDirectory: factoryTestDir
            )
            _ = restoredController.view
            let restoredBrowsers = restoredController.browserTabsSummary()
            restoredController.stopOrchestratorBridge()
            guard persisted.draft(for: activeId) == typedDraft,
                let savedPane = persistedTabs.pane(for: activeId),
                savedPane.tabs.contains(where: {
                    $0.kind == .browser && $0.url == "http://localhost:5173/dashboard"
                }),
                restoredController.diffController.activeTabKind == .browser,
                restoredBrowsers.contains(where: { $0.url == "http://localhost:5173/dashboard" })
            else {
                return false
            }

            let factoryDraft = controller.factoryStore.createDraft()
            controller.selectFactoryRun(factoryDraft.id)
            window.layoutIfNeeded()
            guard controller.activeFactoryRunId == factoryDraft.id,
                controller.diffItem?.isCollapsed == true,
                controller.diffController.tabCount == 0
            else {
                fputs(
                    "MainSplitViewController self-test: factory view leaked previous thread right pane\n",
                    stderr
                )
                return false
            }
            controller.refreshFromCore()
            guard controller.diffItem?.isCollapsed == true,
                controller.diffController.tabCount == 0
            else {
                fputs(
                    "MainSplitViewController self-test: refreshFromCore overwrote factory right pane\n",
                    stderr
                )
                return false
            }
            controller.selectFactoryRun(nil)
            controller.refreshFromCore()
            window.layoutIfNeeded()
            guard controller.activeFactoryRunId == nil,
                controller.diffItem?.isCollapsed == false,
                controller.diffController.activeTabKind == .browser,
                controller.browserTabsSummary().contains(where: {
                    $0.url == "http://localhost:5173/dashboard"
                })
            else {
                fputs(
                    "MainSplitViewController self-test: leaving factory did not restore thread right pane\n",
                    stderr
                )
                return false
            }
        }

        return !controller.isShowingSettings && controller.settingsViewController.view.isHidden
            && !controller.isShowingRateLimits && controller.rateLimitsViewController.view.isHidden
    }
}
