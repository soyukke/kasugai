import AppKit
import Foundation

final class KasugaiMiniRingBadgeView: NSView {
    struct Entry {
        let color: NSColor
        let remainingPercent: Double
    }

    var entries: [Entry] = [] {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }
    var trackColor: NSColor = NSColor(white: 1.0, alpha: 0.14) {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize {
        let count = max(1, entries.count)
        let width = CGFloat(count) * 14 + CGFloat(max(0, count - 1)) * 4
        return NSSize(width: width, height: 14)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let diameter: CGFloat = 14
        let gap: CGFloat = 4
        for (idx, entry) in entries.enumerated() {
            let x = CGFloat(idx) * (diameter + gap)
            let rect = NSRect(x: x + 1.5, y: 1.5, width: diameter - 3, height: diameter - 3)
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius = rect.width / 2.0

            let track = NSBezierPath()
            track.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 0,
                endAngle: 360,
                clockwise: false
            )
            track.lineWidth = 2.0
            trackColor.setStroke()
            track.stroke()

            let frac = max(0, min(1, entry.remainingPercent / 100.0))
            if frac > 0.005 {
                let startAngle: CGFloat = 90
                let endAngle: CGFloat = 90 - CGFloat(frac) * 360.0
                let arc = NSBezierPath()
                arc.appendArc(
                    withCenter: center,
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: true
                )
                arc.lineWidth = 2.0
                arc.lineCapStyle = .round
                entry.color.setStroke()
                arc.stroke()
            }
        }
    }
}

private final class KasugaiCircularGaugeView: NSView {
    private let preferredDiameter: CGFloat
    private let windowData: KasugaiRateLimitWindow
    private let accentColor: NSColor
    private let theme: KasugaiThemeTokens

    init(
        window: KasugaiRateLimitWindow,
        accentColor: NSColor,
        theme: KasugaiThemeTokens,
        diameter: CGFloat
    ) {
        self.windowData = window
        self.accentColor = accentColor
        self.theme = theme
        self.preferredDiameter = diameter
        super.init(frame: .zero)
        wantsLayer = true
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        let remInt = Int(round(window.remainingPercent))
        let usedInt = Int(round(window.usedPercent))
        let resetText = RateLimitService.formatResetTimestamp(window.resetsAt)
        if resetText.isEmpty {
            toolTip = "\(window.label): 残り \(remInt)%（使用済み \(usedInt)%）"
        } else {
            toolTip = "\(window.label): 残り \(remInt)%（使用済み \(usedInt)%） · リセット \(resetText)"
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: max(preferredDiameter + 16, 86), height: preferredDiameter + 42)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let labelBandHeight: CGFloat = 38
        let maxRingW = max(36, bounds.width - 10)
        let maxRingH = max(36, bounds.height - labelBandHeight - 4)
        let diameter = min(preferredDiameter, maxRingW, maxRingH)
        let ringWidth: CGFloat = diameter >= 84 ? 7.0 : (diameter >= 64 ? 6.0 : 5.0)
        let ringTop = bounds.height - 2
        let center = NSPoint(x: bounds.midX, y: ringTop - diameter / 2.0)
        let radius = max(12, (diameter - ringWidth) / 2.0)

        let track = NSBezierPath()
        track.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 0,
            endAngle: 360,
            clockwise: false
        )
        track.lineWidth = ringWidth
        theme.textPrimary.withAlphaComponent(theme.isLight ? 0.08 : 0.11).setStroke()
        track.stroke()

        let remaining = windowData.remainingPercent
        let progressColor: NSColor
        if remaining <= 10 {
            progressColor = theme.danger
        } else if remaining <= 25 {
            progressColor = theme.warning
        } else {
            progressColor = accentColor
        }

        let frac = max(0, min(1, remaining / 100.0))
        if frac > 0.005 {
            let startAngle: CGFloat = 90
            let endAngle: CGFloat = 90 - CGFloat(frac) * 360.0
            let arc = NSBezierPath()
            arc.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: startAngle,
                endAngle: endAngle,
                clockwise: true
            )
            arc.lineWidth = ringWidth
            arc.lineCapStyle = .round
            progressColor.setStroke()
            arc.stroke()
        }

        let pctFontSize: CGFloat = diameter >= 80 ? 18 : (diameter >= 62 ? 15 : 13)
        let pctString = "\(Int(round(remaining)))%"
        let pctAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: pctFontSize, weight: .semibold),
            .foregroundColor: theme.textPrimary,
        ]
        let pctSize = (pctString as NSString).size(withAttributes: pctAttrs)
        let pctY = center.y - pctSize.height / 2.0
        (pctString as NSString).draw(
            at: NSPoint(x: center.x - pctSize.width / 2.0, y: pctY),
            withAttributes: pctAttrs
        )

        let centerParagraph = NSMutableParagraphStyle()
        centerParagraph.alignment = .center
        centerParagraph.lineBreakMode = .byTruncatingTail

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: diameter >= 72 ? 12 : 11, weight: .semibold),
            .foregroundColor: theme.textPrimary,
            .paragraphStyle: centerParagraph,
        ]
        let titleHeight: CGFloat = 16
        let titleY = max(16, ringTop - diameter - titleHeight - 5)
        let titleRect = NSRect(
            x: 2, y: titleY, width: max(0, bounds.width - 4), height: titleHeight)
        (windowData.label as NSString).draw(
            with: titleRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: titleAttrs
        )

        let resetStr: String
        if let resetsAt = windowData.resetsAt {
            resetStr = RateLimitService.formatResetCountdown(resetsAt)
        } else if remaining >= 99.5 {
            resetStr = "未使用"
        } else {
            resetStr = "リセットなし"
        }
        let resetAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: theme.textMuted,
            .paragraphStyle: centerParagraph,
        ]
        let resetHeight: CGFloat = 14
        let resetY = max(1, titleY - resetHeight - 1)
        let resetRect = NSRect(
            x: 2, y: resetY, width: max(0, bounds.width - 4), height: resetHeight)
        (resetStr as NSString).draw(
            with: resetRect,
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: resetAttrs
        )
    }
}

final class RateLimitsViewController: NSViewController {
    var onRefreshRequested: (() -> Void)?
    var onClose: (() -> Void)?

    private var palette: KasugaiPalette = .kasugai
    private var theme: KasugaiThemeTokens = KasugaiThemeTokens.resolve(
        palette: .kasugai, isLight: false)
    private var snapshot: KasugaiRateLimitSnapshot = .initial()

    private let rootSurface = KasugaiModalBackdropView()
    let modalSurface = KasugaiSurfaceView()
    let titleLabel = NSTextField(labelWithString: "レートリミット")
    private let updatedLabel = NSTextField(labelWithString: "取得中…")
    private let refreshButton = KasugaiFlatButton()
    let closeButton = KasugaiFlatButton()
    private let headerDivider = KasugaiSurfaceView()

    private let cardsRow = NSStackView()
    private let claudeCard = KasugaiSurfaceView()
    private let codexCard = KasugaiSurfaceView()
    private let antigravityCard = KasugaiSurfaceView()
    private var equalHeightConstraint: NSLayoutConstraint?
    private var stackedWidthConstraints: [NSLayoutConstraint] = []
    private var isStackedLayout = false
    private let bottomStack = NSStackView()
    private let footerNoteLabel = NSTextField(
        labelWithString: "ローカル CLI 経由（外部通信なし）"
    )

    override func cancelOperation(_ sender: Any?) {
        onClose?()
    }

    override func loadView() {
        rootSurface.frame = NSRect(x: 0, y: 0, width: 760, height: 560)
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

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.alignment = .left
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        updatedLabel.font = .monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)
        updatedLabel.lineBreakMode = .byTruncatingTail
        updatedLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        refreshButton.buttonStyle = .pill
        refreshButton.customHeight = 24
        refreshButton.horizontalPadding = 10
        refreshButton.font = .systemFont(ofSize: 11.5, weight: .medium)
        refreshButton.configureSymbol(
            "arrow.clockwise", title: "更新", pointSize: 11, weight: .medium)
        refreshButton.target = self
        refreshButton.action = #selector(handleRefresh)

        closeButton.buttonStyle = .ghost
        closeButton.customHeight = 26
        closeButton.horizontalPadding = 6
        closeButton.configureSymbol("xmark", pointSize: 11.5, weight: .semibold)
        closeButton.toolTip = "閉じる（Esc）"
        closeButton.target = self
        closeButton.action = #selector(handleClose)

        let titleStack = NSStackView(views: [titleLabel, updatedLabel])
        titleStack.orientation = .horizontal
        titleStack.alignment = .firstBaseline
        titleStack.spacing = 10

        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.init(1), for: .horizontal)

        let headerBar = NSStackView(views: [
            titleStack,
            headerSpacer,
            refreshButton,
            closeButton,
        ])
        headerBar.orientation = .horizontal
        headerBar.alignment = .centerY
        headerBar.spacing = 8
        headerBar.translatesAutoresizingMaskIntoConstraints = false

        headerDivider.translatesAutoresizingMaskIntoConstraints = false

        claudeCard.cornerRadius = 12
        claudeCard.strokeWidth = 1
        claudeCard.translatesAutoresizingMaskIntoConstraints = false

        codexCard.cornerRadius = 12
        codexCard.strokeWidth = 1
        codexCard.translatesAutoresizingMaskIntoConstraints = false

        antigravityCard.cornerRadius = 12
        antigravityCard.strokeWidth = 1
        antigravityCard.translatesAutoresizingMaskIntoConstraints = false

        cardsRow.orientation = .horizontal
        cardsRow.alignment = .top
        cardsRow.distribution = .fillEqually
        cardsRow.spacing = 12
        cardsRow.translatesAutoresizingMaskIntoConstraints = false
        cardsRow.addArrangedSubview(claudeCard)
        cardsRow.addArrangedSubview(codexCard)

        bottomStack.orientation = .horizontal
        bottomStack.alignment = .centerY
        bottomStack.spacing = 10
        bottomStack.translatesAutoresizingMaskIntoConstraints = false

        footerNoteLabel.font = .systemFont(ofSize: 10.5, weight: .regular)
        footerNoteLabel.lineBreakMode = .byTruncatingTail
        footerNoteLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        footerNoteLabel.translatesAutoresizingMaskIntoConstraints = false

        modalSurface.addSubview(headerBar)
        modalSurface.addSubview(headerDivider)
        modalSurface.addSubview(cardsRow)
        modalSurface.addSubview(antigravityCard)
        modalSurface.addSubview(bottomStack)
        rootSurface.addSubview(modalSurface)

        let eqHeight = claudeCard.heightAnchor.constraint(equalTo: codexCard.heightAnchor)
        equalHeightConstraint = eqHeight
        stackedWidthConstraints = [
            claudeCard.leadingAnchor.constraint(equalTo: cardsRow.leadingAnchor),
            claudeCard.trailingAnchor.constraint(equalTo: cardsRow.trailingAnchor),
            codexCard.leadingAnchor.constraint(equalTo: cardsRow.leadingAnchor),
            codexCard.trailingAnchor.constraint(equalTo: cardsRow.trailingAnchor),
        ]

        let idealWidth = modalSurface.widthAnchor.constraint(equalToConstant: 920)
        idealWidth.priority = NSLayoutConstraint.Priority(480)

        NSLayoutConstraint.activate([
            modalSurface.centerXAnchor.constraint(equalTo: rootSurface.centerXAnchor),
            modalSurface.centerYAnchor.constraint(equalTo: rootSurface.centerYAnchor),
            modalSurface.leadingAnchor.constraint(
                greaterThanOrEqualTo: rootSurface.leadingAnchor, constant: 28),
            modalSurface.trailingAnchor.constraint(
                lessThanOrEqualTo: rootSurface.trailingAnchor, constant: -28),
            modalSurface.topAnchor.constraint(
                greaterThanOrEqualTo: rootSurface.topAnchor, constant: 24),
            modalSurface.bottomAnchor.constraint(
                lessThanOrEqualTo: rootSurface.bottomAnchor, constant: -24),
            modalSurface.widthAnchor.constraint(lessThanOrEqualToConstant: 920),
            idealWidth,

            headerBar.topAnchor.constraint(equalTo: modalSurface.topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: modalSurface.leadingAnchor, constant: 18),
            headerBar.trailingAnchor.constraint(
                equalTo: modalSurface.trailingAnchor, constant: -12),
            headerBar.heightAnchor.constraint(equalToConstant: 44),

            headerDivider.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            headerDivider.leadingAnchor.constraint(equalTo: modalSurface.leadingAnchor),
            headerDivider.trailingAnchor.constraint(equalTo: modalSurface.trailingAnchor),
            headerDivider.heightAnchor.constraint(equalToConstant: 1),

            cardsRow.topAnchor.constraint(equalTo: headerDivider.bottomAnchor, constant: 14),
            cardsRow.leadingAnchor.constraint(equalTo: modalSurface.leadingAnchor, constant: 18),
            cardsRow.trailingAnchor.constraint(equalTo: modalSurface.trailingAnchor, constant: -18),
            eqHeight,

            antigravityCard.topAnchor.constraint(equalTo: cardsRow.bottomAnchor, constant: 10),
            antigravityCard.leadingAnchor.constraint(
                equalTo: modalSurface.leadingAnchor, constant: 18),
            antigravityCard.trailingAnchor.constraint(
                equalTo: modalSurface.trailingAnchor, constant: -18),

            bottomStack.topAnchor.constraint(equalTo: antigravityCard.bottomAnchor, constant: 10),
            bottomStack.leadingAnchor.constraint(equalTo: modalSurface.leadingAnchor, constant: 20),
            bottomStack.trailingAnchor.constraint(
                equalTo: modalSurface.trailingAnchor, constant: -20),
            bottomStack.bottomAnchor.constraint(
                equalTo: modalSurface.bottomAnchor, constant: -14),
        ])

        self.view = rootSurface
        applyTheme()
        renderSnapshot()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        syncResponsiveLayout()
    }

    private func syncResponsiveLayout() {
        let cardW = modalSurface.bounds.width > 0 ? modalSurface.bounds.width : view.bounds.width
        let shouldStack = cardW > 0 && cardW < 580
        if shouldStack != isStackedLayout {
            isStackedLayout = shouldStack
            equalHeightConstraint?.isActive = !shouldStack
            cardsRow.orientation = shouldStack ? .vertical : .horizontal
            cardsRow.alignment = shouldStack ? .leading : .top
            cardsRow.distribution = shouldStack ? .fill : .fillEqually
            cardsRow.spacing = shouldStack ? 10 : 12
            for constraint in stackedWidthConstraints {
                constraint.isActive = shouldStack
            }
            renderSnapshot()
        }
    }

    func update(palette: KasugaiPalette) {
        self.palette = palette
        applyTheme()
    }

    func setLeftSidebarCollapsed(_ collapsed: Bool) {
        _ = collapsed
    }

    func update(snapshot: KasugaiRateLimitSnapshot) {
        self.snapshot = snapshot
        renderSnapshot()
    }

    private func applyTheme() {
        theme = KasugaiThemeTokens.resolve(
            palette: palette,
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
        titleLabel.textColor = theme.textPrimary
        updatedLabel.textColor = theme.textMuted
        refreshButton.apply(theme: theme)
        closeButton.apply(theme: theme)
        claudeCard.fillColor = theme.surfaceBg
        claudeCard.strokeColor = theme.borderSubtle
        codexCard.fillColor = theme.surfaceBg
        codexCard.strokeColor = theme.borderSubtle
        antigravityCard.fillColor = theme.surfaceBg
        antigravityCard.strokeColor = theme.borderSubtle
        footerNoteLabel.textColor = theme.textMuted
        renderSnapshot()
    }

    private func renderSnapshot() {
        if snapshot.isRefreshing {
            updatedLabel.stringValue = "取得中…"
            refreshButton.isEnabled = false
        } else if let updated = snapshot.lastUpdated {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.dateFormat = "HH:mm"
            updatedLabel.stringValue = "最終更新 \(formatter.string(from: updated))"
            refreshButton.isEnabled = true
        } else {
            updatedLabel.stringValue = "未取得"
            refreshButton.isEnabled = true
        }

        populateCard(
            claudeCard,
            report: snapshot.claude,
            brandColor: KasugaiThemeTokens.hex(0xD97757),
            isFullWidthRow: false
        )
        populateCard(
            codexCard,
            report: snapshot.codex,
            brandColor: KasugaiThemeTokens.hex(0x10A37F),
            isFullWidthRow: false
        )
        populateCard(
            antigravityCard,
            report: snapshot.antigravity,
            brandColor: KasugaiThemeTokens.hex(0x7C8CFF),
            isFullWidthRow: true
        )
        populateBottomStrip()
    }

    private func populateCard(
        _ card: KasugaiSurfaceView,
        report: KasugaiProviderRateLimit,
        brandColor: NSColor,
        isFullWidthRow: Bool
    ) {
        for sub in card.subviews {
            sub.removeFromSuperview()
        }

        let iconView = NSImageView()
        iconView.image = KasugaiBrandIcons.providerIcon(for: report.providerId)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = NSTextField(labelWithString: report.displayName)
        nameLabel.font = .systemFont(ofSize: 13.5, weight: .semibold)
        nameLabel.textColor = theme.textPrimary
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        var headerViews: [NSView] = [iconView, nameLabel]
        if let plan = report.plan {
            let pill = KasugaiSurfaceView()
            pill.fillColor = brandColor.withAlphaComponent(theme.isLight ? 0.14 : 0.20)
            pill.cornerRadius = 5
            pill.translatesAutoresizingMaskIntoConstraints = false
            let planLabel = NSTextField(labelWithString: plan)
            planLabel.font = .systemFont(ofSize: 10.5, weight: .semibold)
            planLabel.textColor = brandColor
            planLabel.translatesAutoresizingMaskIntoConstraints = false
            pill.addSubview(planLabel)
            NSLayoutConstraint.activate([
                planLabel.topAnchor.constraint(equalTo: pill.topAnchor, constant: 2),
                planLabel.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -2),
                planLabel.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 6),
                planLabel.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -6),
            ])
            headerViews.append(pill)
        }
        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        headerViews.append(headerSpacer)

        if let credits = report.resetCreditsAvailable, credits > 0 {
            let creditLabel = NSTextField(labelWithString: "リセット枠 \(credits) 回")
            creditLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            creditLabel.textColor = theme.textMuted
            creditLabel.lineBreakMode = .byTruncatingTail
            creditLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            headerViews.append(creditLabel)
        }

        let cardHeader = NSStackView(views: headerViews)
        cardHeader.orientation = .horizontal
        cardHeader.alignment = .centerY
        cardHeader.spacing = 7
        cardHeader.translatesAutoresizingMaskIntoConstraints = false

        let bodyContainer = NSView()
        bodyContainer.translatesAutoresizingMaskIntoConstraints = false

        switch report.status {
        case .available:
            let count = report.windows.count
            let baseDiameter: CGFloat
            if isStackedLayout {
                baseDiameter = count <= 2 ? 62 : 52
            } else if isFullWidthRow {
                baseDiameter = count <= 2 ? 82 : 76
            } else {
                baseDiameter = count <= 2 ? 82 : (count == 3 ? 68 : 58)
            }
            let gaugesRow = NSStackView()
            gaugesRow.orientation = .horizontal
            gaugesRow.alignment = .centerY
            gaugesRow.distribution = .fillEqually
            gaugesRow.spacing = count <= 2 ? 12 : 6
            gaugesRow.translatesAutoresizingMaskIntoConstraints = false

            for item in report.windows.prefix(4) {
                let gauge = KasugaiCircularGaugeView(
                    window: item,
                    accentColor: brandColor,
                    theme: theme,
                    diameter: baseDiameter
                )
                gaugesRow.addArrangedSubview(gauge)
            }
            bodyContainer.addSubview(gaugesRow)
            NSLayoutConstraint.activate([
                gaugesRow.topAnchor.constraint(equalTo: bodyContainer.topAnchor, constant: 2),
                gaugesRow.bottomAnchor.constraint(
                    equalTo: bodyContainer.bottomAnchor, constant: -2),
                gaugesRow.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
                gaugesRow.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            ])

        case .loading:
            let label = NSTextField(labelWithString: "ローカル CLI から取得中…")
            label.font = .systemFont(ofSize: 12.5, weight: .regular)
            label.textColor = theme.textMuted
            label.translatesAutoresizingMaskIntoConstraints = false
            bodyContainer.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: bodyContainer.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: bodyContainer.centerYAnchor),
                bodyContainer.heightAnchor.constraint(
                    greaterThanOrEqualToConstant: isStackedLayout ? 84 : 114),
            ])

        case .notInstalled:
            let label = NSTextField(labelWithString: "CLI が未インストールです")
            label.font = .systemFont(ofSize: 12.5, weight: .regular)
            label.textColor = theme.textMuted
            label.translatesAutoresizingMaskIntoConstraints = false
            bodyContainer.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: bodyContainer.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: bodyContainer.centerYAnchor),
                bodyContainer.heightAnchor.constraint(
                    greaterThanOrEqualToConstant: isStackedLayout ? 84 : 114),
            ])

        case .unavailable(let reason):
            let label = NSTextField(labelWithString: reason)
            label.font = .systemFont(ofSize: 12.5, weight: .regular)
            label.textColor = theme.textMuted
            label.translatesAutoresizingMaskIntoConstraints = false
            bodyContainer.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: bodyContainer.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: bodyContainer.centerYAnchor),
                bodyContainer.heightAnchor.constraint(
                    greaterThanOrEqualToConstant: isStackedLayout ? 84 : 114),
            ])
        }

        card.addSubview(cardHeader)
        card.addSubview(bodyContainer)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 15),
            iconView.heightAnchor.constraint(equalToConstant: 15),

            cardHeader.topAnchor.constraint(
                equalTo: card.topAnchor, constant: isStackedLayout ? 9 : 11),
            cardHeader.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            cardHeader.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),

            bodyContainer.topAnchor.constraint(
                equalTo: cardHeader.bottomAnchor, constant: isStackedLayout ? 4 : 6),
            bodyContainer.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            bodyContainer.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            bodyContainer.bottomAnchor.constraint(
                equalTo: card.bottomAnchor, constant: isStackedLayout ? -8 : -10),
        ])
    }

    private func populateBottomStrip() {
        for sub in bottomStack.arrangedSubviews {
            bottomStack.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }

        let opencodeSummary = makeOpencodeSummary()
        bottomStack.addArrangedSubview(
            makeCliStatusPill(
                providerId: "opencode_acp",
                text: opencodeSummary.text,
                active: snapshot.opencodeInstalled,
                detailTip: opencodeSummary.tip
            )
        )

        if snapshot.opencodeInstalled {
            let consoleButton = KasugaiFlatButton()
            consoleButton.buttonStyle = .pill
            consoleButton.customHeight = 20
            consoleButton.horizontalPadding = 8
            consoleButton.font = .systemFont(ofSize: 10.5, weight: .medium)
            consoleButton.title = "Console ↗"
            consoleButton.toolTip = "OpenCode Console でサブスク残枠を確認（外部ブラウザで開きます）"
            consoleButton.target = self
            consoleButton.action = #selector(handleOpenOpencodeConsole)
            consoleButton.apply(theme: theme)
            bottomStack.addArrangedSubview(consoleButton)
        }

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bottomStack.addArrangedSubview(spacer)
        bottomStack.addArrangedSubview(footerNoteLabel)
    }

    private func makeOpencodeSummary() -> (text: String, tip: String) {
        guard snapshot.opencodeInstalled else {
            return (
                "OpenCode · 未導入",
                "OpenCode CLI がインストールされていません。"
            )
        }
        if let usage = snapshot.opencodeUsage {
            var parts: [String] = []
            var tipLines: [String] = []
            if let today = usage.today {
                let tok = RateLimitService.formatCompactTokens(today.totalTokens)
                parts.append("今日 \(tok) tok")
                tipLines.append(
                    "今日: \(today.sessions) セッション / \(today.prompts) プロンプト / \(tok) tok"
                )
            }
            if let week = usage.sevenDay {
                let tok = RateLimitService.formatCompactTokens(week.totalTokens)
                if week.cost >= 0.01 {
                    let costStr = String(format: "$%.2f", week.cost)
                    parts.append("7 日 \(tok) tok（\(costStr)）")
                } else {
                    parts.append("7 日 \(tok) tok")
                }
                tipLines.append(
                    "過去 7 日: \(week.sessions) セッション / \(week.prompts) プロンプト / \(tok) tok"
                )
            }
            tipLines.append("サブスク残枠（%）は OpenCode Console で確認できます。")
            let summary = parts.isEmpty ? "導入済み" : parts.joined(separator: " · ")
            return ("OpenCode · \(summary)", tipLines.joined(separator: "\n"))
        }
        if snapshot.isRefreshing {
            return (
                "OpenCode · ローカル集計を取得中…",
                "opencode stats からローカル使用量を集計しています。"
            )
        }
        return (
            "OpenCode · 導入済み",
            "OpenCode CLI はサブスク残枠 API を提供していません。Console から確認できます。"
        )
    }

    private func makeCliStatusPill(
        providerId: String,
        text: String,
        active: Bool,
        detailTip: String
    ) -> NSView {
        let icon = NSImageView()
        icon.image = KasugaiBrandIcons.providerIcon(for: providerId)
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 13),
            icon.heightAnchor.constraint(equalToConstant: 13),
        ])

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = active ? theme.textSecondary : theme.textMuted
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.toolTip = detailTip
        return stack
    }

    @objc private func handleOpenOpencodeConsole() {
        guard let url = URL(string: "https://opencode.ai/console") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func handleRefresh() {
        onRefreshRequested?()
    }

    @objc private func handleClose() {
        onClose?()
    }
}
