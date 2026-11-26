import AppKit
import CoreImage
import Foundation

private final class SettingsFlippedClipView: NSClipView {
    override var isFlipped: Bool {
        true
    }
}

private final class SettingsFlippedView: NSView {
    override var isFlipped: Bool {
        true
    }
}

private final class PaletteSwatchCard: NSControl {
    let palette: KasugaiPalette
    var isSelectedCard: Bool = false {
        didSet { needsDisplay = true }
    }
    var previewLight: Bool = false {
        didSet { needsDisplay = true }
    }
    var activeTheme: KasugaiThemeTokens = KasugaiThemeTokens.resolve(
        palette: .kasugai, isLight: false
    )
    {
        didSet { needsDisplay = true }
    }

    private var isHovered: Bool = false
    private var trackingAreaRef: NSTrackingArea?

    init(palette: KasugaiPalette) {
        self.palette = palette
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 148, height: 86)
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
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let sample = KasugaiThemeTokens.resolve(palette: palette, isLight: previewLight)
        let cardBounds = bounds.insetBy(dx: 1, dy: 1)
        let cardPath = NSBezierPath(roundedRect: cardBounds, xRadius: 10, yRadius: 10)
        activeTheme.surfaceBg.setFill()
        cardPath.fill()

        let strokeColor =
            isSelectedCard
            ? activeTheme.accent
            : (isHovered ? activeTheme.borderStrong : activeTheme.borderSubtle)
        strokeColor.setStroke()
        cardPath.lineWidth = isSelectedCard ? 1.8 : 1.0
        cardPath.stroke()

        let previewRect = NSRect(
            x: 8,
            y: 26,
            width: bounds.width - 16,
            height: bounds.height - 34
        )
        let previewPath = NSBezierPath(roundedRect: previewRect, xRadius: 6, yRadius: 6)
        NSGraphicsContext.saveGraphicsState()
        previewPath.addClip()

        sample.canvasBg.setFill()
        previewRect.fill()

        let sideWidth = floor(previewRect.width * 0.28)
        let sideRect = NSRect(
            x: previewRect.minX,
            y: previewRect.minY,
            width: sideWidth,
            height: previewRect.height
        )
        sample.sidebarBg.setFill()
        sideRect.fill()

        let divRect = NSRect(
            x: previewRect.minX + sideWidth,
            y: previewRect.minY,
            width: 1,
            height: previewRect.height
        )
        sample.borderSubtle.setFill()
        divRect.fill()

        let bubbleRect = NSRect(
            x: previewRect.minX + sideWidth + 10,
            y: previewRect.maxY - 16,
            width: previewRect.width - sideWidth - 20,
            height: 8
        )
        sample.surfaceBg.setFill()
        NSBezierPath(roundedRect: bubbleRect, xRadius: 3, yRadius: 3).fill()

        let lineRect = NSRect(
            x: previewRect.minX + sideWidth + 10,
            y: previewRect.maxY - 27,
            width: (previewRect.width - sideWidth - 20) * 0.72,
            height: 4
        )
        sample.textMuted.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: lineRect, xRadius: 2, yRadius: 2).fill()

        let composerRect = NSRect(
            x: previewRect.minX + sideWidth + 8,
            y: previewRect.minY + 6,
            width: previewRect.width - sideWidth - 16,
            height: 11
        )
        sample.surfaceBg.setFill()
        NSBezierPath(roundedRect: composerRect, xRadius: 4, yRadius: 4).fill()

        let dotRect = NSRect(
            x: composerRect.maxX - 9,
            y: composerRect.minY + 2.5,
            width: 6,
            height: 6
        )
        sample.accent.setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        NSGraphicsContext.restoreGraphicsState()

        sample.borderSubtle.setStroke()
        previewPath.lineWidth = 1
        previewPath.stroke()

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(
                ofSize: 11.5,
                weight: isSelectedCard ? .semibold : .medium
            ),
            .foregroundColor: isSelectedCard
                ? activeTheme.textPrimary : activeTheme.textSecondary,
        ]
        let labelStr = palette.label as NSString
        labelStr.draw(at: NSPoint(x: 10, y: 6), withAttributes: labelAttrs)

        if isSelectedCard {
            let badgeRect = NSRect(x: bounds.width - 18, y: 9, width: 8, height: 8)
            activeTheme.accent.setFill()
            NSBezierPath(ovalIn: badgeRect).fill()
        }
    }
}

final class SettingsViewController: NSViewController, NSTextFieldDelegate {
    var onSettingsChanged: ((KasugaiAppSettings) -> Void)?
    var onClose: (() -> Void)?
    var onToggleMobileBridge: ((Bool) -> Void)?
    var onGenerateMobilePairing: (() -> Void)?
    var onRevokeMobileDevice: ((String) -> Void)?
    var onRefreshMobileBridgeStatus: (() -> Void)?
    var onClearExternalBrowserData: (() -> Void)?

    private var settings: KasugaiAppSettings
    private var storePath: String
    private var socketPath: String
    private var mobileStatus: MobileBridgeStatusSnapshot = .disabled

    private let providers: [(id: String, label: String)] = [
        ("claude_code", "Claude Code"),
        ("codex", "Codex"),
        ("opencode_acp", "OpenCode (ACP)"),
        ("antigravity_acp", "Antigravity (ACP)"),
    ]
    private let efforts: [(id: String, label: String)] = [
        ("low", "Low"),
        ("medium", "Medium"),
        ("high", "High"),
        ("xhigh", "XHigh / Max"),
    ]

    private let rootSurface = KasugaiModalBackdropView()
    let modalSurface = KasugaiSurfaceView()
    private let headerDivider = KasugaiSurfaceView()
    let closeButton = KasugaiFlatButton()
    let headerTitleLabel = NSTextField(labelWithString: "設定")
    private let scrollView = NSScrollView()
    private let appearanceControl = KasugaiSegmentedPill(items: [
        ("システム", "circle.lefthalf.filled"),
        ("ライト", "sun.max"),
        ("ダーク", "moon"),
    ])
    private var swatchCards: [PaletteSwatchCard] = []
    private let providerPopup = NSPopUpButton()
    private let effortPopup = NSPopUpButton()
    private let approvalPolicyPopup = NSPopUpButton()
    let telemetryCheck = NSButton(
        checkboxWithTitle: "子プロセスのテレメトリを抑止する", target: nil, action: nil)
    private let orchestrationCheck = NSButton(
        checkboxWithTitle: "セッション間オーケストレーションを有効にする（ローカル Unix ソケット）",
        target: nil,
        action: nil
    )
    private let externalBrowserCheck = NSButton(
        checkboxWithTitle: "内蔵ブラウザの外部通信を許可する",
        target: nil,
        action: nil
    )
    private let externalBrowserAllowAllCheck = NSButton(
        checkboxWithTitle: "すべての外部サイトを許可する（下のブロック指定を除く）",
        target: nil,
        action: nil
    )
    private let externalBrowserDescLabel = NSTextField(
        wrappingLabelWithString:
            "既定オフ。オンにすると右ペインのブラウザで外部サイト表示・ログイン保持が可能になります（チャット描画の通信遮断は維持、ブロック指定は許可より優先されます）。"
    )
    private let externalRulesStack = NSStackView()
    private var externalRuleRowViews:
        [(
            actionPopup: NSPopUpButton,
            domainSurface: KasugaiSurfaceView,
            domainField: NSTextField,
            removeButton: KasugaiFlatButton
        )] = []
    private let externalNewRuleActionPopup = NSPopUpButton()
    private let externalDomainsSurface = KasugaiSurfaceView()
    private let externalDomainsField = NSTextField()
    private let externalAddRuleButton = KasugaiFlatButton()
    private let clearBrowserDataButton = KasugaiFlatButton()
    private let mobileBridgeCheck = NSButton(
        checkboxWithTitle: "モバイル接続を有効にする（Tailscale）",
        target: nil,
        action: nil
    )
    private let mobileDescLabel = NSTextField(
        wrappingLabelWithString: "127.0.0.1 のみで待ち受け、Tailscale Serve とペアリングトークンで保護します。"
    )
    private let mobileStatusLabel = NSTextField(wrappingLabelWithString: "")
    private let mobileGenerateButton = KasugaiFlatButton()
    private let mobileCopyButton = KasugaiFlatButton()
    private let mobileRefreshButton = KasugaiFlatButton()
    private let mobileRevokeAllButton = KasugaiFlatButton()
    private let mobileQrSurface = KasugaiSurfaceView()
    private let mobileQrImageView = NSImageView()
    private let mobileCodeLabel = NSTextField(wrappingLabelWithString: "")
    private let mobilePairingRow = NSStackView()
    private let mobileDevicesStack = NSStackView()
    private var mobileDeviceButtons: [KasugaiFlatButton] = []
    private(set) var sectionLabels: [NSTextField] = []
    private var rowLabels: [NSTextField] = []
    private(set) var cardSurfaces: [KasugaiSurfaceView] = []
    private var cardDividers: [KasugaiSurfaceView] = []
    private let infoLabel = NSTextField(wrappingLabelWithString: "")

    init(settings: KasugaiAppSettings, storePath: String, socketPath: String) {
        self.settings = settings
        self.storePath = storePath
        self.socketPath = socketPath
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func cancelOperation(_ sender: Any?) {
        onClose?()
    }

    override func loadView() {
        rootSurface.frame = NSRect(x: 0, y: 0, width: 760, height: 640)
        rootSurface.modalCardView = modalSurface
        rootSurface.onBackdropClick = { [weak self] in
            self?.onClose?()
        }
        rootSurface.onAppearanceChanged = { [weak self] in
            self?.applyTheme()
        }

        modalSurface.cornerRadius = 16
        modalSurface.strokeWidth = 1
        modalSurface.translatesAutoresizingMaskIntoConstraints = false

        headerTitleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        headerTitleLabel.alignment = .left

        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.init(1), for: .horizontal)

        closeButton.buttonStyle = .ghost
        closeButton.customHeight = 26
        closeButton.horizontalPadding = 6
        closeButton.configureSymbol("xmark", pointSize: 11.5, weight: .semibold)
        closeButton.toolTip = "閉じる（Esc）"
        closeButton.target = self
        closeButton.action = #selector(handleBack)

        let headerBar = NSStackView(views: [headerTitleLabel, headerSpacer, closeButton])
        headerBar.orientation = .horizontal
        headerBar.alignment = .centerY
        headerBar.spacing = 8
        headerBar.translatesAutoresizingMaskIntoConstraints = false

        headerDivider.translatesAutoresizingMaskIntoConstraints = false

        appearanceControl.onSelectionChanged = { [weak self] idx in
            guard let self, idx >= 0, idx < KasugaiAppearance.allCases.count else {
                return
            }
            self.settings.appearance = KasugaiAppearance.allCases[idx]
            self.commitSettings()
        }

        let topRowCards = NSStackView()
        topRowCards.orientation = .horizontal
        topRowCards.distribution = .fillEqually
        topRowCards.spacing = 10

        let bottomRowCards = NSStackView()
        bottomRowCards.orientation = .horizontal
        bottomRowCards.distribution = .fillEqually
        bottomRowCards.spacing = 10

        for (idx, item) in KasugaiPalette.allCases.enumerated() {
            let card = PaletteSwatchCard(palette: item)
            card.tag = idx
            card.target = self
            card.action = #selector(handlePaletteTap(_:))
            card.setContentHuggingPriority(.defaultLow, for: .horizontal)
            card.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            card.heightAnchor.constraint(equalToConstant: 86).isActive = true
            swatchCards.append(card)
            if idx < 4 {
                topRowCards.addArrangedSubview(card)
            } else {
                bottomRowCards.addArrangedSubview(card)
            }
        }

        let paletteGrid = NSStackView(views: [topRowCards, bottomRowCards])
        paletteGrid.orientation = .vertical
        paletteGrid.alignment = .leading
        paletteGrid.spacing = 10
        topRowCards.widthAnchor.constraint(equalTo: paletteGrid.widthAnchor).isActive = true
        bottomRowCards.widthAnchor.constraint(equalTo: paletteGrid.widthAnchor).isActive = true

        for item in providers {
            providerPopup.addItem(withTitle: item.label)
        }
        providerPopup.controlSize = .small
        providerPopup.target = self
        providerPopup.action = #selector(handleControlChanged)

        for item in efforts {
            effortPopup.addItem(withTitle: item.label)
        }
        effortPopup.controlSize = .small
        effortPopup.target = self
        effortPopup.action = #selector(handleControlChanged)

        for policy in KasugaiToolApprovalPolicy.allCases {
            approvalPolicyPopup.addItem(withTitle: policy.label)
        }
        approvalPolicyPopup.controlSize = .small
        approvalPolicyPopup.target = self
        approvalPolicyPopup.action = #selector(handleControlChanged)

        telemetryCheck.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        telemetryCheck.target = self
        telemetryCheck.action = #selector(handleControlChanged)

        orchestrationCheck.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        orchestrationCheck.target = self
        orchestrationCheck.action = #selector(handleControlChanged)

        externalBrowserCheck.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        externalBrowserCheck.target = self
        externalBrowserCheck.action = #selector(handleControlChanged)

        externalBrowserAllowAllCheck.setContentCompressionResistancePriority(
            .defaultLow, for: .horizontal)
        externalBrowserAllowAllCheck.target = self
        externalBrowserAllowAllCheck.action = #selector(handleControlChanged)

        externalBrowserDescLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        externalBrowserDescLabel.alignment = .left
        externalBrowserDescLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        externalBrowserDescLabel.setContentCompressionResistancePriority(
            .defaultLow, for: .horizontal)

        externalRulesStack.orientation = .vertical
        externalRulesStack.alignment = .leading
        externalRulesStack.spacing = 6

        for action in KasugaiBrowserRuleAction.allCases {
            externalNewRuleActionPopup.addItem(withTitle: action.label)
        }
        externalNewRuleActionPopup.controlSize = .small
        externalNewRuleActionPopup.setContentHuggingPriority(.required, for: .horizontal)
        externalNewRuleActionPopup.widthAnchor.constraint(equalToConstant: 88).isActive = true

        externalDomainsSurface.cornerRadius = 7
        externalDomainsSurface.strokeWidth = 1
        externalDomainsSurface.translatesAutoresizingMaskIntoConstraints = false
        externalDomainsSurface.setContentHuggingPriority(.defaultLow, for: .horizontal)
        externalDomainsSurface.setContentCompressionResistancePriority(
            .defaultLow, for: .horizontal)

        externalDomainsField.isBordered = false
        externalDomainsField.drawsBackground = false
        externalDomainsField.focusRingType = .none
        externalDomainsField.placeholderString =
            "ドメインを追加（例: partner.steamgames.com）"
        externalDomainsField.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        externalDomainsField.lineBreakMode = .byTruncatingTail
        externalDomainsField.delegate = self
        externalDomainsField.translatesAutoresizingMaskIntoConstraints = false
        externalDomainsField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        externalDomainsField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        externalDomainsSurface.addSubview(externalDomainsField)
        NSLayoutConstraint.activate([
            externalDomainsSurface.heightAnchor.constraint(equalToConstant: 28),
            externalDomainsField.leadingAnchor.constraint(
                equalTo: externalDomainsSurface.leadingAnchor, constant: 8),
            externalDomainsField.trailingAnchor.constraint(
                equalTo: externalDomainsSurface.trailingAnchor, constant: -8),
            externalDomainsField.centerYAnchor.constraint(
                equalTo: externalDomainsSurface.centerYAnchor),
        ])

        externalAddRuleButton.buttonStyle = .subtleFilled
        externalAddRuleButton.customHeight = 28
        externalAddRuleButton.horizontalPadding = 10
        externalAddRuleButton.configureSymbol("plus", title: "追加", pointSize: 11, weight: .semibold)
        externalAddRuleButton.target = self
        externalAddRuleButton.action = #selector(handleAddBrowserRule)

        clearBrowserDataButton.buttonStyle = .ghost
        clearBrowserDataButton.title = "ブラウザデータを消去"
        clearBrowserDataButton.target = self
        clearBrowserDataButton.action = #selector(handleClearExternalBrowserData)

        let allowAllSpacer = NSView()
        allowAllSpacer.setContentHuggingPriority(.init(1), for: .horizontal)
        allowAllSpacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        let allowAllRow = NSStackView(views: [
            externalBrowserAllowAllCheck,
            allowAllSpacer,
            clearBrowserDataButton,
        ])
        allowAllRow.orientation = .horizontal
        allowAllRow.alignment = .centerY
        allowAllRow.spacing = 8

        let addRuleRow = NSStackView(views: [
            externalNewRuleActionPopup,
            externalDomainsSurface,
            externalAddRuleButton,
        ])
        addRuleRow.orientation = .horizontal
        addRuleRow.alignment = .centerY
        addRuleRow.spacing = 8

        let externalBrowserGroup = NSStackView(views: [
            makeLeftAlignedRow(externalBrowserCheck),
            externalBrowserDescLabel,
            allowAllRow,
            externalRulesStack,
            addRuleRow,
        ])
        externalBrowserGroup.orientation = .vertical
        externalBrowserGroup.alignment = .leading
        externalBrowserGroup.spacing = 8
        for sub in externalBrowserGroup.arrangedSubviews {
            sub.widthAnchor.constraint(equalTo: externalBrowserGroup.widthAnchor).isActive = true
        }

        mobileBridgeCheck.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        mobileBridgeCheck.target = self
        mobileBridgeCheck.action = #selector(handleToggleMobileBridge)

        mobileDescLabel.font = .systemFont(ofSize: 11.5, weight: .regular)
        mobileDescLabel.alignment = .left
        mobileDescLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        mobileDescLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        mobileStatusLabel.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        mobileStatusLabel.alignment = .left
        mobileStatusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        mobileStatusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        mobileGenerateButton.buttonStyle = .subtleFilled
        mobileGenerateButton.title = "ペアリングコードを発行"
        mobileGenerateButton.target = self
        mobileGenerateButton.action = #selector(handleGenerateMobilePairing)

        mobileCopyButton.buttonStyle = .subtleFilled
        mobileCopyButton.title = "ペアリング情報をコピー"
        mobileCopyButton.target = self
        mobileCopyButton.action = #selector(handleCopyMobilePairing)

        mobileRefreshButton.buttonStyle = .ghost
        mobileRefreshButton.title = "状態を更新"
        mobileRefreshButton.target = self
        mobileRefreshButton.action = #selector(handleRefreshMobileBridge)

        mobileRevokeAllButton.buttonStyle = .ghost
        mobileRevokeAllButton.title = "すべて解除"
        mobileRevokeAllButton.target = self
        mobileRevokeAllButton.action = #selector(handleRevokeAllMobileDevices)

        let mobileActionSpacer = NSView()
        mobileActionSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let mobileActionRow = NSStackView(views: [
            mobileGenerateButton,
            mobileCopyButton,
            mobileRefreshButton,
            mobileActionSpacer,
            mobileRevokeAllButton,
        ])
        mobileActionRow.orientation = .horizontal
        mobileActionRow.alignment = .centerY
        mobileActionRow.spacing = 8

        mobileQrSurface.cornerRadius = 10
        mobileQrSurface.fillColor = .white
        mobileQrSurface.strokeWidth = 1
        mobileQrSurface.translatesAutoresizingMaskIntoConstraints = false
        mobileQrImageView.imageScaling = .scaleProportionallyUpOrDown
        mobileQrImageView.translatesAutoresizingMaskIntoConstraints = false
        mobileQrSurface.addSubview(mobileQrImageView)
        NSLayoutConstraint.activate([
            mobileQrSurface.widthAnchor.constraint(equalToConstant: 148),
            mobileQrSurface.heightAnchor.constraint(equalToConstant: 148),
            mobileQrImageView.topAnchor.constraint(
                equalTo: mobileQrSurface.topAnchor, constant: 10),
            mobileQrImageView.bottomAnchor.constraint(
                equalTo: mobileQrSurface.bottomAnchor, constant: -10),
            mobileQrImageView.leadingAnchor.constraint(
                equalTo: mobileQrSurface.leadingAnchor, constant: 10),
            mobileQrImageView.trailingAnchor.constraint(
                equalTo: mobileQrSurface.trailingAnchor, constant: -10),
        ])

        mobileCodeLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        mobileCodeLabel.isSelectable = true
        mobileCodeLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        mobilePairingRow.orientation = .horizontal
        mobilePairingRow.alignment = .centerY
        mobilePairingRow.spacing = 14
        mobilePairingRow.addArrangedSubview(mobileQrSurface)
        mobilePairingRow.addArrangedSubview(mobileCodeLabel)
        mobilePairingRow.isHidden = true

        mobileDevicesStack.orientation = .vertical
        mobileDevicesStack.alignment = .width
        mobileDevicesStack.spacing = 6

        infoLabel.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        infoLabel.alignment = .left
        infoLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        infoLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        updateInfoLabel()

        let appearanceCard = makeCard(rows: [
            makeKeyValueRow(title: "外観モード", control: appearanceControl)
        ])

        let agentCard = makeCard(rows: [
            makeKeyValueRow(title: "既定プロバイダ", control: providerPopup),
            makeKeyValueRow(title: "既定推論強度", control: effortPopup),
            makeKeyValueRow(title: "ツール実行の承認", control: approvalPolicyPopup),
        ])

        let privacyCard = makeCard(rows: [
            makeLeftAlignedRow(telemetryCheck),
            makeLeftAlignedRow(orchestrationCheck),
            externalBrowserGroup,
        ])

        let mobileBodyStack = NSStackView(views: [
            makeLeftAlignedRow(mobileBridgeCheck),
            mobileDescLabel,
            mobileStatusLabel,
            mobileActionRow,
            mobilePairingRow,
            mobileDevicesStack,
        ])
        mobileBodyStack.orientation = .vertical
        mobileBodyStack.alignment = .leading
        mobileBodyStack.spacing = 8
        for sub in mobileBodyStack.arrangedSubviews {
            sub.widthAnchor.constraint(equalTo: mobileBodyStack.widthAnchor).isActive = true
        }

        let mobileCard = makeCard(rows: [mobileBodyStack])

        let envCard = makeCard(rows: [infoLabel])

        let contentStack = NSStackView(views: [
            makeSectionHeading("外観"),
            appearanceCard,
            makeSectionHeading("カラーテーマ"),
            paletteGrid,
            makeSectionHeading("エージェント"),
            agentCard,
            makeSectionHeading("プライバシーと連携"),
            privacyCard,
            makeSectionHeading("モバイル接続（Tailscale）"),
            mobileCard,
            makeSectionHeading("環境情報"),
            envCard,
        ])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 10
        contentStack.setCustomSpacing(18, after: appearanceCard)
        contentStack.setCustomSpacing(18, after: paletteGrid)
        contentStack.setCustomSpacing(18, after: agentCard)
        contentStack.setCustomSpacing(18, after: privacyCard)
        contentStack.setCustomSpacing(18, after: mobileCard)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        for sub in contentStack.arrangedSubviews {
            sub.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        }

        let docView = SettingsFlippedView()
        docView.translatesAutoresizingMaskIntoConstraints = false
        docView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: docView.topAnchor, constant: 18),
            contentStack.bottomAnchor.constraint(equalTo: docView.bottomAnchor, constant: -24),
            contentStack.leadingAnchor.constraint(equalTo: docView.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: docView.trailingAnchor, constant: -20),
        ])

        let clipView = SettingsFlippedClipView()
        clipView.drawsBackground = false
        scrollView.contentView = clipView
        scrollView.documentView = docView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            docView.topAnchor.constraint(equalTo: clipView.topAnchor),
            docView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            docView.widthAnchor.constraint(equalTo: clipView.widthAnchor),
        ])

        modalSurface.addSubview(headerBar)
        modalSurface.addSubview(headerDivider)
        modalSurface.addSubview(scrollView)
        rootSurface.addSubview(modalSurface)

        let idealWidth = modalSurface.widthAnchor.constraint(equalToConstant: 900)
        idealWidth.priority = NSLayoutConstraint.Priority(480)
        let idealHeight = modalSurface.heightAnchor.constraint(equalToConstant: 760)
        idealHeight.priority = NSLayoutConstraint.Priority(480)

        NSLayoutConstraint.activate([
            modalSurface.centerXAnchor.constraint(equalTo: rootSurface.centerXAnchor),
            modalSurface.centerYAnchor.constraint(equalTo: rootSurface.centerYAnchor),
            modalSurface.leadingAnchor.constraint(
                greaterThanOrEqualTo: rootSurface.leadingAnchor, constant: 28),
            modalSurface.trailingAnchor.constraint(
                lessThanOrEqualTo: rootSurface.trailingAnchor, constant: -28),
            modalSurface.topAnchor.constraint(
                greaterThanOrEqualTo: rootSurface.topAnchor, constant: 28),
            modalSurface.bottomAnchor.constraint(
                lessThanOrEqualTo: rootSurface.bottomAnchor, constant: -28),
            modalSurface.widthAnchor.constraint(lessThanOrEqualToConstant: 900),
            modalSurface.heightAnchor.constraint(lessThanOrEqualToConstant: 780),
            idealWidth,
            idealHeight,

            headerBar.topAnchor.constraint(equalTo: modalSurface.topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: modalSurface.leadingAnchor, constant: 18),
            headerBar.trailingAnchor.constraint(
                equalTo: modalSurface.trailingAnchor, constant: -12),
            headerBar.heightAnchor.constraint(equalToConstant: 44),

            headerDivider.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            headerDivider.leadingAnchor.constraint(equalTo: modalSurface.leadingAnchor),
            headerDivider.trailingAnchor.constraint(equalTo: modalSurface.trailingAnchor),
            headerDivider.heightAnchor.constraint(equalToConstant: 1),

            scrollView.topAnchor.constraint(equalTo: headerDivider.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: modalSurface.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: modalSurface.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: modalSurface.bottomAnchor, constant: -8),
        ])

        self.view = rootSurface
        syncControls()
        applyTheme()
    }

    func scrollToBottomForSnapshot() {
        view.layoutSubtreeIfNeeded()
        if let doc = scrollView.documentView {
            let maxY = max(0, doc.bounds.height - scrollView.contentView.bounds.height)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: maxY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    func setLeftSidebarCollapsed(_ collapsed: Bool) {
        _ = collapsed
    }

    func update(settings: KasugaiAppSettings, storePath: String, socketPath: String) {
        self.settings = settings
        self.storePath = storePath
        self.socketPath = socketPath
        updateInfoLabel()
        syncControls()
        renderMobileBridgeSection()
        applyTheme()
    }

    func update(mobileBridgeStatus: MobileBridgeStatusSnapshot) {
        self.mobileStatus = mobileBridgeStatus
        renderMobileBridgeSection()
        applyTheme()
    }

    func applyTheme() {
        let theme = KasugaiThemeTokens.resolve(
            palette: settings.palette,
            appearance: view.effectiveAppearance
        )
        rootSurface.apply(theme: theme)
        modalSurface.fillColor = theme.canvasBg
        modalSurface.strokeColor = theme.borderStrong
        modalSurface.shadow = NSShadow()
        modalSurface.layer?.shadowColor = NSColor.black.cgColor
        modalSurface.layer?.shadowOpacity = theme.isLight ? 0.18 : 0.5
        modalSurface.layer?.shadowRadius = 24
        modalSurface.layer?.shadowOffset = CGSize(width: 0, height: -8)
        modalSurface.layer?.masksToBounds = false
        headerDivider.fillColor = theme.borderSubtle
        closeButton.apply(theme: theme)
        headerTitleLabel.textColor = theme.textPrimary
        appearanceControl.apply(theme: theme)
        externalDomainsSurface.fillColor = theme.canvasBg
        externalDomainsSurface.strokeColor = theme.borderSubtle
        externalDomainsField.textColor = theme.textPrimary
        externalAddRuleButton.apply(theme: theme)
        for row in externalRuleRowViews {
            row.domainSurface.fillColor = theme.canvasBg
            row.domainSurface.strokeColor = theme.borderSubtle
            row.domainField.textColor = theme.textPrimary
            row.removeButton.apply(theme: theme)
        }

        for label in sectionLabels {
            label.textColor = theme.textMuted
        }
        for label in rowLabels {
            label.textColor = theme.textPrimary
        }
        for card in cardSurfaces {
            card.fillColor = theme.surfaceBg
            card.strokeColor = theme.borderSubtle
        }
        for div in cardDividers {
            div.fillColor = theme.borderSubtle
        }
        for card in swatchCards {
            card.previewLight = theme.isLight
            card.activeTheme = theme
            card.isSelectedCard = card.palette == settings.palette
        }
        infoLabel.textColor = theme.textSecondary
        externalBrowserDescLabel.textColor = theme.textMuted
        clearBrowserDataButton.apply(theme: theme)
        mobileDescLabel.textColor = theme.textMuted
        mobileStatusLabel.textColor = theme.textSecondary
        mobileCodeLabel.textColor = theme.textPrimary
        mobileQrSurface.strokeColor = theme.borderSubtle
        mobileGenerateButton.apply(theme: theme)
        mobileCopyButton.apply(theme: theme)
        mobileRefreshButton.apply(theme: theme)
        mobileRevokeAllButton.apply(theme: theme)
        for btn in mobileDeviceButtons {
            btn.apply(theme: theme)
        }
    }

    private func makeLeftAlignedRow(_ control: NSView) -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        let row = NSStackView(views: [control, spacer])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 0
        return row
    }

    private func makeSectionHeading(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.alignment = .left
        sectionLabels.append(label)
        return makeLeftAlignedRow(label)
    }

    private func makeKeyValueRow(title: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .regular)
        rowLabels.append(label)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [label, spacer, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func makeCard(rows: [NSView]) -> KasugaiSurfaceView {
        let card = KasugaiSurfaceView()
        card.cornerRadius = 12
        card.strokeWidth = 1
        card.translatesAutoresizingMaskIntoConstraints = false
        cardSurfaces.append(card)

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        for (idx, row) in rows.enumerated() {
            if idx > 0 {
                let sep = KasugaiSurfaceView()
                sep.heightAnchor.constraint(equalToConstant: 1).isActive = true
                cardDividers.append(sep)
                stack.addArrangedSubview(sep)
                sep.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
        ])
        return card
    }

    private func updateInfoLabel() {
        let socketLine =
            socketPath.isEmpty
            ? "ローカル制御ソケット: 停止中"
            : "ローカル制御ソケット: \(socketPath)"
        let browserPolicyLine: String
        if !settings.allowExternalBrowser {
            browserPolicyLine = "内蔵ブラウザ: ローカル限定（localhost / 127.0.0.1 のみ）"
        } else {
            let allowCount = settings.externalBrowserRules.filter { $0.action == .allow }.count
            let blockCount = settings.externalBrowserRules.filter { $0.action == .block }.count
            if settings.externalBrowserAllowAll {
                browserPolicyLine =
                    blockCount > 0
                    ? "内蔵ブラウザ: すべての外部サイトを許可（ブロック \(blockCount) 件）"
                    : "内蔵ブラウザ: すべての外部サイトを許可"
            } else {
                browserPolicyLine =
                    "内蔵ブラウザ: ルール指定のみ（許可 \(allowCount) 件・ブロック \(blockCount) 件）"
            }
        }
        infoLabel.stringValue =
            "\(browserPolicyLine)\nEvent Store: \(storePath)\n\(socketLine)"
    }

    private func syncControls() {
        if let idx = KasugaiAppearance.allCases.firstIndex(of: settings.appearance) {
            appearanceControl.setSelectedIndex(idx)
        }
        if let idx = providers.firstIndex(where: { $0.id == settings.defaultProvider }) {
            providerPopup.selectItem(at: idx)
        }
        if let idx = efforts.firstIndex(where: { $0.id == settings.defaultEffort }) {
            effortPopup.selectItem(at: idx)
        }
        if let idx = KasugaiToolApprovalPolicy.allCases.firstIndex(of: settings.toolApprovalPolicy)
        {
            approvalPolicyPopup.selectItem(at: idx)
        }
        telemetryCheck.state = settings.suppressTelemetry ? .on : .off
        orchestrationCheck.state = settings.enableAgentOrchestration ? .on : .off
        externalBrowserCheck.state = settings.allowExternalBrowser ? .on : .off
        externalBrowserAllowAllCheck.state = settings.externalBrowserAllowAll ? .on : .off
        externalBrowserAllowAllCheck.isEnabled = settings.allowExternalBrowser
        externalNewRuleActionPopup.isEnabled = settings.allowExternalBrowser
        externalDomainsField.isEnabled = settings.allowExternalBrowser
        externalAddRuleButton.isEnabled = settings.allowExternalBrowser
        clearBrowserDataButton.isEnabled = settings.allowExternalBrowser
        rebuildExternalBrowserRuleRows()
        mobileBridgeCheck.state = settings.enableMobileBridge ? .on : .off
    }

    private func rebuildExternalBrowserRuleRows() {
        for sub in externalRulesStack.arrangedSubviews {
            externalRulesStack.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }
        externalRuleRowViews.removeAll()

        let theme = KasugaiThemeTokens.resolve(
            palette: settings.palette,
            appearance: view.effectiveAppearance
        )
        let enabled = settings.allowExternalBrowser
        for (idx, rule) in settings.externalBrowserRules.enumerated() {
            let popup = NSPopUpButton()
            for action in KasugaiBrowserRuleAction.allCases {
                popup.addItem(withTitle: action.label)
            }
            if let actionIdx = KasugaiBrowserRuleAction.allCases.firstIndex(of: rule.action) {
                popup.selectItem(at: actionIdx)
            }
            popup.controlSize = .small
            popup.tag = idx
            popup.isEnabled = enabled
            popup.target = self
            popup.action = #selector(handleBrowserRuleActionChanged(_:))
            popup.setContentHuggingPriority(.required, for: .horizontal)
            popup.widthAnchor.constraint(equalToConstant: 88).isActive = true

            let domainSurface = KasugaiSurfaceView()
            domainSurface.cornerRadius = 7
            domainSurface.strokeWidth = 1
            domainSurface.fillColor = theme.canvasBg
            domainSurface.strokeColor = theme.borderSubtle
            domainSurface.translatesAutoresizingMaskIntoConstraints = false
            domainSurface.setContentHuggingPriority(.defaultLow, for: .horizontal)
            domainSurface.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let domainField = NSTextField()
            domainField.isBordered = false
            domainField.drawsBackground = false
            domainField.focusRingType = .none
            domainField.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
            domainField.textColor = theme.textPrimary
            domainField.lineBreakMode = .byTruncatingTail
            domainField.stringValue = rule.domain
            domainField.tag = idx
            domainField.isEnabled = enabled
            domainField.delegate = self
            domainField.translatesAutoresizingMaskIntoConstraints = false
            domainField.setContentHuggingPriority(.defaultLow, for: .horizontal)
            domainField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            domainSurface.addSubview(domainField)
            NSLayoutConstraint.activate([
                domainSurface.heightAnchor.constraint(equalToConstant: 26),
                domainField.leadingAnchor.constraint(
                    equalTo: domainSurface.leadingAnchor, constant: 8),
                domainField.trailingAnchor.constraint(
                    equalTo: domainSurface.trailingAnchor, constant: -8),
                domainField.centerYAnchor.constraint(equalTo: domainSurface.centerYAnchor),
            ])

            let removeBtn = KasugaiFlatButton()
            removeBtn.buttonStyle = .ghost
            removeBtn.customHeight = 26
            removeBtn.horizontalPadding = 6
            removeBtn.configureSymbol("xmark", pointSize: 10.5, weight: .semibold)
            removeBtn.toolTip = "ルールを削除"
            removeBtn.tag = idx
            removeBtn.isEnabled = enabled
            removeBtn.target = self
            removeBtn.action = #selector(handleRemoveBrowserRule(_:))
            removeBtn.apply(theme: theme)

            let row = NSStackView(views: [popup, domainSurface, removeBtn])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            externalRulesStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: externalRulesStack.widthAnchor).isActive = true
            externalRuleRowViews.append((popup, domainSurface, domainField, removeBtn))
        }
        externalRulesStack.isHidden = settings.externalBrowserRules.isEmpty
    }

    private func renderMobileBridgeSection() {
        mobileBridgeCheck.state = settings.enableMobileBridge ? .on : .off
        let isActive = settings.enableMobileBridge && mobileStatus.running
        mobileGenerateButton.isEnabled = isActive
        let hasCode = isActive && !mobileStatus.activePairingCode.isEmpty
        mobileCopyButton.isEnabled = hasCode
        mobileRefreshButton.isEnabled = settings.enableMobileBridge
        mobileRevokeAllButton.isHidden = mobileStatus.pairedDevices.isEmpty

        var lines: [String] = []
        if !settings.enableMobileBridge {
            lines.append("状態: 停止中（既定オフ・TCP ポート未使用）")
        } else if !mobileStatus.running {
            lines.append("状態: 起動中…")
        } else if mobileStatus.tailscaleServeActive {
            lines.append("状態: 公開中（Tailscale Serve・HTTPS）")
        } else if mobileStatus.tailscaleRunning {
            lines.append("状態: ローカル待機中（Tailscale Serve 未設定）")
        } else if mobileStatus.tailscaleAvailable {
            lines.append("状態: ローカル待機中（Tailscale 未接続）")
        } else {
            lines.append("状態: ローカル待機中（Tailscale 未検出）")
        }
        if isActive {
            lines.append("ローカル待受: \(mobileStatus.bindHost):\(mobileStatus.localPort)")
            if !mobileStatus.publicBaseURL.isEmpty {
                lines.append("接続先 URL: \(mobileStatus.publicBaseURL)")
            }
            lines.append(
                "接続済み端末: \(mobileStatus.pairedDevices.count) 台（ライブ接続: \(mobileStatus.connectedStreamCount)）"
            )
        }
        if !mobileStatus.lastError.isEmpty {
            lines.append("エラー: \(mobileStatus.lastError)")
        }
        mobileStatusLabel.stringValue = lines.joined(separator: "\n")

        if hasCode {
            let payload = MobilePairingPayload(
                hostURL: mobileStatus.publicBaseURL,
                code: mobileStatus.activePairingCode
            )
            mobileQrImageView.image = Self.makeQRCodeImage(text: payload.uriString)
            mobileCodeLabel.stringValue =
                "ペアリングコード: \(mobileStatus.activePairingCode)\n有効期限: 5 分間（1 回限り）\nURL: \(mobileStatus.publicBaseURL)\n\niPhone の Kasugai アプリで QR コードを読み取るか、ペアリング情報をペーストしてください。"
            mobilePairingRow.isHidden = false
        } else {
            mobileQrImageView.image = nil
            mobileCodeLabel.stringValue = ""
            mobilePairingRow.isHidden = true
        }

        for child in mobileDevicesStack.arrangedSubviews {
            mobileDevicesStack.removeArrangedSubview(child)
            child.removeFromSuperview()
        }
        mobileDeviceButtons.removeAll()
        if !mobileStatus.pairedDevices.isEmpty {
            for device in mobileStatus.pairedDevices {
                let nameLabel = NSTextField(labelWithString: device.name)
                nameLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
                rowLabels.append(nameLabel)

                let seenText = KasugaiBrandIcons.relativeTimeLabel(
                    fromMillis: device.lastSeenAtMs
                )
                let seenLabel = NSTextField(labelWithString: "最終接続: \(seenText)")
                seenLabel.font = .systemFont(ofSize: 11, weight: .regular)
                sectionLabels.append(seenLabel)

                let spacer = NSView()
                spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

                let revokeBtn = KasugaiFlatButton()
                revokeBtn.buttonStyle = .ghost
                revokeBtn.title = "解除"
                revokeBtn.identifier = NSUserInterfaceItemIdentifier(device.id)
                revokeBtn.target = self
                revokeBtn.action = #selector(handleRevokeSingleMobileDevice(_:))
                mobileDeviceButtons.append(revokeBtn)

                let row = NSStackView(views: [nameLabel, seenLabel, spacer, revokeBtn])
                row.orientation = .horizontal
                row.alignment = .centerY
                row.spacing = 8
                mobileDevicesStack.addArrangedSubview(row)
            }
            mobileDevicesStack.isHidden = false
        } else {
            mobileDevicesStack.isHidden = true
        }
    }

    private static func makeQRCodeImage(text: String) -> NSImage? {
        guard let data = text.data(using: .utf8),
            let filter = CIFilter(name: "CIQRCodeGenerator")
        else {
            return nil
        }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else {
            return nil
        }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let rep = NSCIImageRep(ciImage: scaled)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }

    @objc private func handleToggleMobileBridge() {
        let enabled = mobileBridgeCheck.state == .on
        settings.enableMobileBridge = enabled
        _ = settings.save()
        renderMobileBridgeSection()
        onSettingsChanged?(settings)
        onToggleMobileBridge?(enabled)
    }

    @objc private func handleGenerateMobilePairing() {
        onGenerateMobilePairing?()
    }

    @objc private func handleCopyMobilePairing() {
        guard !mobileStatus.activePairingCode.isEmpty, !mobileStatus.publicBaseURL.isEmpty else {
            return
        }
        let payload = MobilePairingPayload(
            hostURL: mobileStatus.publicBaseURL,
            code: mobileStatus.activePairingCode
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload.uriString, forType: .string)
    }

    @objc private func handleRefreshMobileBridge() {
        onRefreshMobileBridgeStatus?()
    }

    @objc private func handleRevokeSingleMobileDevice(_ sender: NSControl) {
        guard let deviceId = sender.identifier?.rawValue, !deviceId.isEmpty else {
            return
        }
        onRevokeMobileDevice?(deviceId)
    }

    @objc private func handleRevokeAllMobileDevices() {
        onRevokeMobileDevice?("")
    }

    private func commitSettings() {
        _ = settings.save()
        applyTheme()
        onSettingsChanged?(settings)
    }

    @objc private func handleBack() {
        onClose?()
    }

    @objc private func handlePaletteTap(_ sender: NSControl) {
        let idx = sender.tag
        guard idx >= 0, idx < KasugaiPalette.allCases.count else {
            return
        }
        settings.palette = KasugaiPalette.allCases[idx]
        commitSettings()
    }

    @objc private func handleControlChanged() {
        let provIdx = providerPopup.indexOfSelectedItem
        if provIdx >= 0 && provIdx < providers.count {
            settings.defaultProvider = providers[provIdx].id
        }
        let effIdx = effortPopup.indexOfSelectedItem
        if effIdx >= 0 && effIdx < efforts.count {
            settings.defaultEffort = efforts[effIdx].id
        }
        let policyIdx = approvalPolicyPopup.indexOfSelectedItem
        if policyIdx >= 0 && policyIdx < KasugaiToolApprovalPolicy.allCases.count {
            settings.toolApprovalPolicy = KasugaiToolApprovalPolicy.allCases[policyIdx]
        }
        settings.suppressTelemetry = telemetryCheck.state == .on
        settings.enableAgentOrchestration = orchestrationCheck.state == .on
        settings.allowExternalBrowser = externalBrowserCheck.state == .on
        settings.externalBrowserAllowAll = externalBrowserAllowAllCheck.state == .on
        syncAllowedDomainsMirror()
        syncControls()
        updateInfoLabel()
        commitSettings()
    }

    private func syncAllowedDomainsMirror() {
        settings.externalBrowserAllowedDomains = settings.externalBrowserRules
            .filter { $0.action == .allow }
            .map(\.domain)
    }

    @objc private func handleAddBrowserRule() {
        let actionIdx = externalNewRuleActionPopup.indexOfSelectedItem
        let action =
            (actionIdx >= 0 && actionIdx < KasugaiBrowserRuleAction.allCases.count)
            ? KasugaiBrowserRuleAction.allCases[actionIdx]
            : .allow
        let parsed = KasugaiBrowserPolicy.parseDomains(from: externalDomainsField.stringValue)
        guard !parsed.isEmpty else {
            return
        }
        for domain in parsed {
            if let existingIdx = settings.externalBrowserRules.firstIndex(where: {
                $0.domain == domain
            }) {
                settings.externalBrowserRules[existingIdx].action = action
            } else {
                settings.externalBrowserRules.append(
                    KasugaiBrowserDomainRule(action: action, domain: domain)
                )
            }
        }
        externalDomainsField.stringValue = ""
        syncAllowedDomainsMirror()
        syncControls()
        updateInfoLabel()
        commitSettings()
    }

    @objc private func handleBrowserRuleActionChanged(_ sender: NSPopUpButton) {
        let rowIdx = sender.tag
        let actionIdx = sender.indexOfSelectedItem
        guard rowIdx >= 0, rowIdx < settings.externalBrowserRules.count,
            actionIdx >= 0, actionIdx < KasugaiBrowserRuleAction.allCases.count
        else {
            return
        }
        settings.externalBrowserRules[rowIdx].action = KasugaiBrowserRuleAction.allCases[actionIdx]
        syncAllowedDomainsMirror()
        updateInfoLabel()
        commitSettings()
    }

    @objc private func handleRemoveBrowserRule(_ sender: NSControl) {
        let rowIdx = sender.tag
        guard rowIdx >= 0, rowIdx < settings.externalBrowserRules.count else {
            return
        }
        settings.externalBrowserRules.remove(at: rowIdx)
        syncAllowedDomainsMirror()
        syncControls()
        updateInfoLabel()
        commitSettings()
    }

    @objc private func handleClearExternalBrowserData() {
        onClearExternalBrowserData?()
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        if control === externalDomainsField
            && commandSelector == #selector(NSResponder.insertNewline(_:))
        {
            handleAddBrowserRule()
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else {
            return
        }
        if field === externalDomainsField {
            if !field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                handleAddBrowserRule()
            }
            return
        }
        let rowIdx = field.tag
        guard rowIdx >= 0, rowIdx < settings.externalBrowserRules.count,
            externalRuleRowViews.indices.contains(rowIdx),
            externalRuleRowViews[rowIdx].domainField === field
        else {
            return
        }
        if let normalized = KasugaiBrowserPolicy.normalizeDomain(field.stringValue) {
            settings.externalBrowserRules[rowIdx].domain = normalized
            field.stringValue = normalized
        } else {
            settings.externalBrowserRules.remove(at: rowIdx)
        }
        syncAllowedDomainsMirror()
        syncControls()
        updateInfoLabel()
        commitSettings()
    }
}
