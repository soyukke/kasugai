import AppKit
import Foundation

private enum AttachmentStorage {
    private static let imagePasteboardTypes: [NSPasteboard.PasteboardType] = [
        .png,
        .tiff,
        NSPasteboard.PasteboardType("public.jpeg"),
        NSPasteboard.PasteboardType("public.heic"),
    ]

    static func hasAttachableContent(in pasteboard: NSPasteboard) -> Bool {
        if pasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) {
            return true
        }
        if pasteboard.availableType(from: imagePasteboardTypes) != nil {
            return true
        }
        return pasteboard.canReadObject(forClasses: [NSImage.self], options: nil)
    }

    static func isImagePath(_ path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return ["png", "jpg", "jpeg", "webp", "gif", "heic", "tiff", "bmp"].contains(ext)
    }

    static func savePNGData(_ pngData: Data) -> String? {
        let fm = FileManager.default
        let dir = KasugaiRuntimePaths.dataDirectory()
            .appendingPathComponent("attachments", isDirectory: true)
        do {
            try fm.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let shortId = String(UUID().uuidString.prefix(8)).lowercased()
            let fileURL = dir.appendingPathComponent("image-\(shortId).png")
            try pngData.write(to: fileURL, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return fileURL.path
        } catch {
            return nil
        }
    }

    static func saveClipboardImage(_ image: NSImage) -> String? {
        guard let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            return nil
        }
        return savePNGData(pngData)
    }

    static func extractPaths(from pasteboard: NSPasteboard) -> [String] {
        var paths: [String] = []
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] {
            for url in urls where url.isFileURL {
                paths.append(url.path)
            }
        }
        if !paths.isEmpty {
            return paths
        }
        if let pngData = pasteboard.data(forType: .png), !pngData.isEmpty,
            let saved = savePNGData(pngData)
        {
            return [saved]
        }
        if let tiffData = pasteboard.data(forType: .tiff), let image = NSImage(data: tiffData),
            let saved = saveClipboardImage(image)
        {
            return [saved]
        }
        for type in imagePasteboardTypes {
            if let data = pasteboard.data(forType: type), let image = NSImage(data: data),
                let saved = saveClipboardImage(image)
            {
                return [saved]
            }
        }
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)
            as? [NSImage],
            let first = images.first,
            let saved = saveClipboardImage(first)
        {
            return [saved]
        }
        return []
    }
}

private final class FlippedClipView: NSClipView {
    override var isFlipped: Bool {
        true
    }
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool {
        true
    }
}

private final class ModelPickerPillButton: NSControl {
    private let surface = KasugaiSurfaceView()
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "Claude Code")
    private let chevronView = NSImageView()
    private var theme = KasugaiThemeTokens.resolve(palette: .kasugai, isLight: false)
    private var currentProviderId = "claude_code"
    private var isHovered = false
    private var isPressed = false
    private var trackingAreaRef: NSTrackingArea?

    var displayTitle: String {
        titleField.stringValue
    }

    var hasProviderIcon: Bool {
        iconView.image != nil
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        surface.cornerRadius = 7
        surface.translatesAutoresizingMaskIntoConstraints = false

        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleField.font = .systemFont(ofSize: 12, weight: .medium)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let chevCfg = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        chevronView.image = NSImage(
            systemSymbolName: "chevron.down",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(chevCfg)
        chevronView.imageScaling = .scaleProportionallyDown
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        chevronView.setContentHuggingPriority(.required, for: .horizontal)
        chevronView.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [iconView, titleField, chevronView])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 5
        row.translatesAutoresizingMaskIntoConstraints = false

        surface.addSubview(row)
        addSubview(surface)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 28),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),

            iconView.widthAnchor.constraint(equalToConstant: 13),
            iconView.heightAnchor.constraint(equalToConstant: 13),

            chevronView.widthAnchor.constraint(equalToConstant: 10),
            chevronView.heightAnchor.constraint(equalToConstant: 10),

            row.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -7),
            row.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
        ])
        configure(providerId: currentProviderId, title: "Claude Code")
        apply(theme: theme)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func configure(providerId: String, title: String) {
        currentProviderId = providerId
        iconView.image = KasugaiBrandIcons.providerIcon(for: providerId, size: 13)
        titleField.stringValue = title
    }

    func apply(theme: KasugaiThemeTokens) {
        self.theme = theme
        refreshStyle()
    }

    private func refreshStyle() {
        surface.fillColor = isHovered ? theme.surfaceSelected : .clear
        titleField.textColor = isHovered ? theme.textPrimary : theme.textSecondary
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
        KasugaiInteractiveMotion.applyScale(to: self, scale: 1.025)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
        refreshStyle()
        KasugaiInteractiveMotion.applyScale(to: self, scale: 1.0)
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        KasugaiInteractiveMotion.applyScale(to: self, scale: 0.96)
    }

    override func mouseDragged(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let inside = bounds.contains(local)
        if inside != isPressed {
            isPressed = inside
            KasugaiInteractiveMotion.applyScale(to: self, scale: inside ? 0.96 : 1.0)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let shouldFire = isPressed && bounds.contains(local)
        isPressed = false
        KasugaiInteractiveMotion.applyScale(to: self, scale: bounds.contains(local) ? 1.025 : 1.0)
        if shouldFire {
            sendAction(action, to: target)
        }
    }
}

private final class ModelPickerProviderTabButton: NSControl {
    let providerId: String
    private let surface = KasugaiSurfaceView()
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let chevronView = NSImageView()
    private var isSelectedTab = false
    private var isHovered = false
    private var isPressed = false
    private var theme = KasugaiThemeTokens.resolve(palette: .kasugai, isLight: false)
    private var trackingAreaRef: NSTrackingArea?

    init(providerId: String, label: String, selected: Bool, theme: KasugaiThemeTokens) {
        self.providerId = providerId
        self.isSelectedTab = selected
        self.theme = theme
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultLow, for: .horizontal)

        surface.cornerRadius = 8
        surface.strokeWidth = 1
        surface.translatesAutoresizingMaskIntoConstraints = false

        iconView.image = KasugaiBrandIcons.providerIcon(for: providerId, size: 14)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleField.stringValue = label
        titleField.alignment = .left
        titleField.font = .systemFont(ofSize: 13, weight: selected ? .semibold : .regular)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)

        let chevCfg = NSImage.SymbolConfiguration(pointSize: 9.5, weight: .semibold)
        chevronView.image = NSImage(
            systemSymbolName: "chevron.right",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(chevCfg)
        chevronView.imageScaling = .scaleProportionallyDown
        chevronView.isHidden = !selected
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        chevronView.setContentHuggingPriority(.required, for: .horizontal)
        chevronView.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = NSStackView(views: [iconView, titleField, spacer, chevronView])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        surface.addSubview(row)
        addSubview(surface)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            surface.topAnchor.constraint(equalTo: topAnchor),
            surface.bottomAnchor.constraint(equalTo: bottomAnchor),
            surface.leadingAnchor.constraint(equalTo: leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: trailingAnchor),

            iconView.widthAnchor.constraint(equalToConstant: 14),
            iconView.heightAnchor.constraint(equalToConstant: 14),

            chevronView.widthAnchor.constraint(equalToConstant: 10),
            chevronView.heightAnchor.constraint(equalToConstant: 10),

            row.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -9),
            row.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
        ])
        refreshStyle()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func refreshStyle() {
        if isSelectedTab {
            surface.fillColor = theme.surfaceSelected
            surface.strokeColor = .clear
            titleField.textColor = theme.textPrimary
            chevronView.contentTintColor = theme.textMuted
        } else if isHovered {
            surface.fillColor = theme.surfaceElevated
            surface.strokeColor = .clear
            titleField.textColor = theme.textPrimary
            chevronView.contentTintColor = theme.textMuted
        } else {
            surface.fillColor = .clear
            surface.strokeColor = .clear
            titleField.textColor = theme.textSecondary
            chevronView.contentTintColor = theme.textMuted
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        refreshStyle()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
        refreshStyle()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        KasugaiInteractiveMotion.applyScale(to: self, scale: 0.97)
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

private final class EffortOptionRowButton: NSButton {
    let effortId: String
    let displayLabel: String
    private let titleField = NSTextField(labelWithString: "")
    private let checkView = NSImageView()
    private var isSelectedRow: Bool = false
    private var isHovered: Bool = false
    private var trackingAreaRef: NSTrackingArea?
    private var theme: KasugaiThemeTokens = KasugaiThemeTokens.resolve(
        palette: .kasugai, isLight: false)

    init(effortId: String, label: String, selected: Bool, theme: KasugaiThemeTokens) {
        self.effortId = effortId
        self.displayLabel = label
        self.isSelectedRow = selected
        self.theme = theme
        super.init(frame: .zero)
        isBordered = false
        title = ""
        wantsLayer = true
        layer?.cornerRadius = 8
        setContentHuggingPriority(.defaultLow, for: .horizontal)

        titleField.stringValue = label
        titleField.alignment = .left
        titleField.font = .systemFont(ofSize: 13, weight: selected ? .semibold : .regular)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        checkView.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
        checkView.isHidden = !selected

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)

        let row = NSStackView(views: [titleField, spacer, checkView])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            checkView.widthAnchor.constraint(equalToConstant: 12),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        refreshColors()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        refreshColors()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        refreshColors()
    }

    private func refreshColors() {
        if isHovered {
            layer?.backgroundColor = theme.surfaceElevated.cgColor
        } else if isSelectedRow {
            layer?.backgroundColor = theme.surfaceSelected.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
        titleField.textColor = isSelectedRow ? theme.textPrimary : theme.textSecondary
        checkView.contentTintColor = theme.accent
    }
}

final class ComposerTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onAttachPaths: (([String]) -> Void)?
    var onFocusChanged: ((Bool) -> Void)?
    var onContentHeightInvalidated: (() -> Void)?
    var placeholderText: String = "メッセージを入力…" {
        didSet { needsDisplay = true }
    }
    var placeholderColor: NSColor = .placeholderTextColor {
        didSet { needsDisplay = true }
    }

    var shouldDrawPlaceholder: Bool {
        string.isEmpty && !hasMarkedText()
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            onFocusChanged?(true)
        }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok {
            onFocusChanged?(false)
        }
        return ok
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
        onContentHeightInvalidated?()
    }

    override func setMarkedText(
        _ string: Any,
        selectedRange: NSRange,
        replacementRange: NSRange
    ) {
        super.setMarkedText(
            string, selectedRange: selectedRange, replacementRange: replacementRange)
        needsDisplay = true
        onContentHeightInvalidated?()
    }

    override func unmarkText() {
        super.unmarkText()
        needsDisplay = true
        onContentHeightInvalidated?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard shouldDrawPlaceholder else {
            return
        }
        let padding = textContainer?.lineFragmentPadding ?? 5
        let origin = NSPoint(
            x: textContainerOrigin.x + padding,
            y: textContainerOrigin.y
        )
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 14),
            .foregroundColor: placeholderColor,
        ]
        let rect = NSRect(
            x: origin.x,
            y: origin.y,
            width: max(0, bounds.width - origin.x - padding),
            height: max(20, bounds.height - origin.y)
        )
        (placeholderText as NSString).draw(in: rect, withAttributes: attrs)
    }

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn && !hasMarkedText() {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.shift) {
                super.keyDown(with: event)
                return
            }
            if flags.isEmpty || flags == .command {
                onSubmit?()
                return
            }
        }
        super.keyDown(with: event)
    }

    override var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        var types = super.readablePasteboardTypes
        let extra: [NSPasteboard.PasteboardType] = [
            .fileURL,
            .png,
            .tiff,
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.heic"),
        ]
        for t in extra where !types.contains(t) {
            types.append(t)
        }
        return types
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if (item.action == #selector(paste(_:)) || item.action == #selector(pasteAsPlainText(_:)))
            && AttachmentStorage.hasAttachableContent(in: .general)
        {
            return true
        }
        return super.validateUserInterfaceItem(item)
    }

    override func paste(_ sender: Any?) {
        let paths = AttachmentStorage.extractPaths(from: NSPasteboard.general)
        if !paths.isEmpty {
            onAttachPaths?(paths)
            return
        }
        super.paste(sender)
    }

    override func pasteAsPlainText(_ sender: Any?) {
        let paths = AttachmentStorage.extractPaths(from: NSPasteboard.general)
        if !paths.isEmpty {
            onAttachPaths?(paths)
            return
        }
        super.pasteAsPlainText(sender)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let types = sender.draggingPasteboard.types ?? []
        if types.contains(.fileURL) || types.contains(.png) || types.contains(.tiff) {
            return .copy
        }
        return super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let paths = AttachmentStorage.extractPaths(from: sender.draggingPasteboard)
        if !paths.isEmpty {
            onAttachPaths?(paths)
            return true
        }
        return super.performDragOperation(sender)
    }
}

private final class ModelOptionRowButton: NSButton {
    let providerId: String
    let modelId: String
    private let titleField = NSTextField(labelWithString: "")
    private let checkView = NSImageView()
    private var isSelectedRow: Bool = false
    private var isHovered: Bool = false
    private var trackingAreaRef: NSTrackingArea?
    private var theme: KasugaiThemeTokens = KasugaiThemeTokens.resolve(
        palette: .kasugai, isLight: false)

    init(
        providerId: String, modelId: String, label: String, selected: Bool,
        theme: KasugaiThemeTokens
    ) {
        self.providerId = providerId
        self.modelId = modelId
        self.isSelectedRow = selected
        self.theme = theme
        super.init(frame: .zero)
        isBordered = false
        title = ""
        wantsLayer = true
        layer?.cornerRadius = 8
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        toolTip = modelId

        titleField.stringValue = label
        titleField.alignment = .left
        titleField.font = .systemFont(ofSize: 13, weight: selected ? .semibold : .regular)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let cfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        checkView.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
        checkView.isHidden = !selected

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)

        let row = NSStackView(views: [titleField, spacer, checkView])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            checkView.widthAnchor.constraint(equalToConstant: 12),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        refreshColors()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        refreshColors()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        refreshColors()
    }

    private func refreshColors() {
        if isHovered {
            layer?.backgroundColor = theme.surfaceElevated.cgColor
        } else if isSelectedRow {
            layer?.backgroundColor = theme.surfaceSelected.cgColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
        }
        titleField.textColor = isSelectedRow ? theme.textPrimary : theme.textSecondary
        checkView.contentTintColor = theme.accent
    }
}

final class ModelPickerPopoverViewController: NSViewController {
    var onSelectModel: ((String, String, String) -> Void)?
    var onSelectEffort: ((String) -> Void)?
    var onRequestCustomModel: ((String) -> Void)?

    private let providers: [KasugaiProviderSpec]
    private var activeProviderId: String
    private var activeModelId: String
    private let discoveredModels: [String]
    private var selectedProviderId: String
    private var selectedEffort: String
    private let theme: KasugaiThemeTokens

    private let rootSurface = KasugaiSurfaceView()
    private let providerColumn = KasugaiSurfaceView()
    private let providerListStack = NSStackView()
    private let modelColumn = NSView()
    private let modelsScrollView = NSScrollView()
    private let modelsListStack = NSStackView()
    private let effortColumn = KasugaiSurfaceView()
    private let effortListStack = NSStackView()
    private let customModelButton = KasugaiFlatButton()
    private let dividerLeft = KasugaiSurfaceView()
    private let dividerRight = KasugaiSurfaceView()
    private let dividerCustom = KasugaiSurfaceView()

    private var providerTabButtons: [ModelPickerProviderTabButton] = []
    private var effortButtons: [EffortOptionRowButton] = []
    static let fixedPopoverSize = NSSize(width: 580, height: 312)

    init(
        providers: [KasugaiProviderSpec],
        activeProviderId: String,
        activeModelId: String,
        activeEffort: String,
        discoveredModels: [String],
        theme: KasugaiThemeTokens
    ) {
        let filtered = providers.filter { $0.id != "local_echo" }
        self.providers = filtered
        self.activeProviderId = activeProviderId
        self.activeModelId = activeModelId
        self.discoveredModels = discoveredModels
        self.selectedProviderId =
            filtered.contains(where: { $0.id == activeProviderId })
            ? activeProviderId : (filtered.first?.id ?? activeProviderId)
        self.selectedEffort = activeEffort
        self.theme = theme
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    var currentTabProviderId: String {
        selectedProviderId
    }

    var displayedModelCount: Int {
        modelsListStack.arrangedSubviews.count
    }

    var displayedEffortLabels: [String] {
        effortButtons.map(\.displayLabel)
    }

    var providerTabFrames: [NSRect] {
        providerTabButtons.map { $0.convert($0.bounds, to: view) }
    }

    var effortRowFrames: [NSRect] {
        effortButtons.map { $0.convert($0.bounds, to: view) }
    }

    func selectProviderTabForTest(_ providerId: String) {
        selectedProviderId = providerId
        rebuildProviderTabs()
        rebuildModelsList()
        rebuildEffortButtons()
        view.layoutSubtreeIfNeeded()
    }

    private func makeColumnHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11.5, weight: .semibold)
        label.textColor = theme.textMuted
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    override func loadView() {
        let size = Self.fixedPopoverSize
        rootSurface.frame = NSRect(origin: .zero, size: size)
        rootSurface.fillColor = theme.canvasBg
        preferredContentSize = size

        providerColumn.fillColor = theme.sidebarBg
        providerColumn.translatesAutoresizingMaskIntoConstraints = false

        let providerHeader = makeColumnHeader("プロバイダ")
        providerListStack.orientation = .vertical
        providerListStack.alignment = .width
        providerListStack.spacing = 3
        providerListStack.translatesAutoresizingMaskIntoConstraints = false

        providerColumn.addSubview(providerHeader)
        providerColumn.addSubview(providerListStack)
        NSLayoutConstraint.activate([
            providerHeader.topAnchor.constraint(equalTo: providerColumn.topAnchor, constant: 14),
            providerHeader.leadingAnchor.constraint(
                equalTo: providerColumn.leadingAnchor, constant: 18),
            providerHeader.trailingAnchor.constraint(
                equalTo: providerColumn.trailingAnchor, constant: -10),

            providerListStack.topAnchor.constraint(
                equalTo: providerHeader.bottomAnchor, constant: 8),
            providerListStack.leadingAnchor.constraint(
                equalTo: providerColumn.leadingAnchor, constant: 8),
            providerListStack.trailingAnchor.constraint(
                equalTo: providerColumn.trailingAnchor, constant: -8),
            providerListStack.bottomAnchor.constraint(
                lessThanOrEqualTo: providerColumn.bottomAnchor, constant: -10),
        ])

        modelColumn.translatesAutoresizingMaskIntoConstraints = false
        let modelHeader = makeColumnHeader("モデル")

        modelsListStack.orientation = .vertical
        modelsListStack.alignment = .width
        modelsListStack.spacing = 3
        modelsListStack.translatesAutoresizingMaskIntoConstraints = false

        let docView = FlippedDocumentView()
        docView.translatesAutoresizingMaskIntoConstraints = false
        docView.addSubview(modelsListStack)
        NSLayoutConstraint.activate([
            modelsListStack.topAnchor.constraint(equalTo: docView.topAnchor, constant: 2),
            modelsListStack.leadingAnchor.constraint(equalTo: docView.leadingAnchor, constant: 8),
            modelsListStack.trailingAnchor.constraint(
                equalTo: docView.trailingAnchor, constant: -8),
            modelsListStack.bottomAnchor.constraint(equalTo: docView.bottomAnchor, constant: -6),
        ])

        let clipView = FlippedClipView()
        clipView.drawsBackground = false
        modelsScrollView.contentView = clipView
        modelsScrollView.documentView = docView
        modelsScrollView.hasVerticalScroller = true
        modelsScrollView.autohidesScrollers = true
        modelsScrollView.drawsBackground = false
        modelsScrollView.borderType = .noBorder
        modelsScrollView.translatesAutoresizingMaskIntoConstraints = false
        docView.widthAnchor.constraint(equalTo: clipView.widthAnchor).isActive = true

        dividerCustom.fillColor = theme.borderSubtle
        dividerCustom.translatesAutoresizingMaskIntoConstraints = false

        customModelButton.buttonStyle = .ghost
        customModelButton.horizontalPadding = 10
        customModelButton.font = .systemFont(ofSize: 12, weight: .regular)
        customModelButton.configureSymbol("ellipsis.circle", title: "モデル名を指定…", pointSize: 11.5)
        customModelButton.apply(theme: theme)
        customModelButton.target = self
        customModelButton.action = #selector(handleCustomModelTap)
        customModelButton.translatesAutoresizingMaskIntoConstraints = false

        modelColumn.addSubview(modelHeader)
        modelColumn.addSubview(modelsScrollView)
        modelColumn.addSubview(dividerCustom)
        modelColumn.addSubview(customModelButton)
        NSLayoutConstraint.activate([
            modelHeader.topAnchor.constraint(equalTo: modelColumn.topAnchor, constant: 14),
            modelHeader.leadingAnchor.constraint(equalTo: modelColumn.leadingAnchor, constant: 18),
            modelHeader.trailingAnchor.constraint(
                equalTo: modelColumn.trailingAnchor, constant: -10),

            modelsScrollView.topAnchor.constraint(equalTo: modelHeader.bottomAnchor, constant: 8),
            modelsScrollView.leadingAnchor.constraint(equalTo: modelColumn.leadingAnchor),
            modelsScrollView.trailingAnchor.constraint(equalTo: modelColumn.trailingAnchor),
            modelsScrollView.bottomAnchor.constraint(
                equalTo: dividerCustom.topAnchor, constant: -6),

            dividerCustom.leadingAnchor.constraint(
                equalTo: modelColumn.leadingAnchor, constant: 10),
            dividerCustom.trailingAnchor.constraint(
                equalTo: modelColumn.trailingAnchor, constant: -10),
            dividerCustom.heightAnchor.constraint(equalToConstant: 1),
            dividerCustom.bottomAnchor.constraint(
                equalTo: customModelButton.topAnchor, constant: -6),

            customModelButton.leadingAnchor.constraint(
                equalTo: modelColumn.leadingAnchor, constant: 8),
            customModelButton.trailingAnchor.constraint(
                lessThanOrEqualTo: modelColumn.trailingAnchor, constant: -8),
            customModelButton.bottomAnchor.constraint(
                equalTo: modelColumn.bottomAnchor, constant: -8),
            customModelButton.heightAnchor.constraint(equalToConstant: 28),
        ])

        effortColumn.fillColor = theme.sidebarBg
        effortColumn.translatesAutoresizingMaskIntoConstraints = false

        let effortHeader = makeColumnHeader("Effort")
        effortListStack.orientation = .vertical
        effortListStack.alignment = .width
        effortListStack.spacing = 3
        effortListStack.translatesAutoresizingMaskIntoConstraints = false

        effortColumn.addSubview(effortHeader)
        effortColumn.addSubview(effortListStack)
        NSLayoutConstraint.activate([
            effortHeader.topAnchor.constraint(equalTo: effortColumn.topAnchor, constant: 14),
            effortHeader.leadingAnchor.constraint(
                equalTo: effortColumn.leadingAnchor, constant: 18),
            effortHeader.trailingAnchor.constraint(
                equalTo: effortColumn.trailingAnchor, constant: -10),

            effortListStack.topAnchor.constraint(equalTo: effortHeader.bottomAnchor, constant: 8),
            effortListStack.leadingAnchor.constraint(
                equalTo: effortColumn.leadingAnchor, constant: 8),
            effortListStack.trailingAnchor.constraint(
                equalTo: effortColumn.trailingAnchor, constant: -8),
            effortListStack.bottomAnchor.constraint(
                lessThanOrEqualTo: effortColumn.bottomAnchor, constant: -10),
        ])

        dividerLeft.fillColor = theme.borderSubtle
        dividerLeft.translatesAutoresizingMaskIntoConstraints = false
        dividerRight.fillColor = theme.borderSubtle
        dividerRight.translatesAutoresizingMaskIntoConstraints = false

        rootSurface.addSubview(providerColumn)
        rootSurface.addSubview(dividerLeft)
        rootSurface.addSubview(modelColumn)
        rootSurface.addSubview(dividerRight)
        rootSurface.addSubview(effortColumn)

        NSLayoutConstraint.activate([
            providerColumn.topAnchor.constraint(equalTo: rootSurface.topAnchor),
            providerColumn.bottomAnchor.constraint(equalTo: rootSurface.bottomAnchor),
            providerColumn.leadingAnchor.constraint(equalTo: rootSurface.leadingAnchor),
            providerColumn.widthAnchor.constraint(equalToConstant: 164),
            providerColumn.heightAnchor.constraint(equalToConstant: size.height),

            dividerLeft.topAnchor.constraint(equalTo: rootSurface.topAnchor),
            dividerLeft.bottomAnchor.constraint(equalTo: rootSurface.bottomAnchor),
            dividerLeft.leadingAnchor.constraint(equalTo: providerColumn.trailingAnchor),
            dividerLeft.widthAnchor.constraint(equalToConstant: 1),

            modelColumn.topAnchor.constraint(equalTo: rootSurface.topAnchor),
            modelColumn.bottomAnchor.constraint(equalTo: rootSurface.bottomAnchor),
            modelColumn.leadingAnchor.constraint(equalTo: dividerLeft.trailingAnchor),
            modelColumn.trailingAnchor.constraint(equalTo: dividerRight.leadingAnchor),
            modelColumn.widthAnchor.constraint(equalToConstant: 272),

            dividerRight.topAnchor.constraint(equalTo: rootSurface.topAnchor),
            dividerRight.bottomAnchor.constraint(equalTo: rootSurface.bottomAnchor),
            dividerRight.trailingAnchor.constraint(equalTo: effortColumn.leadingAnchor),
            dividerRight.widthAnchor.constraint(equalToConstant: 1),

            effortColumn.topAnchor.constraint(equalTo: rootSurface.topAnchor),
            effortColumn.bottomAnchor.constraint(equalTo: rootSurface.bottomAnchor),
            effortColumn.trailingAnchor.constraint(equalTo: rootSurface.trailingAnchor),
            effortColumn.widthAnchor.constraint(equalToConstant: 142),
        ])

        self.view = rootSurface
        rebuildProviderTabs()
        rebuildModelsList()
        rebuildEffortButtons()
        view.layoutSubtreeIfNeeded()
    }

    private func shortTabLabel(for spec: KasugaiProviderSpec) -> String {
        switch spec.id {
        case "claude_code":
            return "Claude"
        case "codex":
            return "Codex"
        case "opencode_acp":
            return "OpenCode"
        case "antigravity_acp":
            return "Antigravity"
        default:
            return spec.displayName
        }
    }

    private func rebuildProviderTabs() {
        for view in providerListStack.arrangedSubviews {
            providerListStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        providerTabButtons.removeAll()
        for (idx, spec) in providers.enumerated() {
            let btn = ModelPickerProviderTabButton(
                providerId: spec.id,
                label: shortTabLabel(for: spec),
                selected: spec.id == selectedProviderId,
                theme: theme
            )
            btn.tag = idx
            btn.target = self
            btn.action = #selector(handleProviderTabTap(_:))
            providerTabButtons.append(btn)
            providerListStack.addArrangedSubview(btn)
            btn.widthAnchor.constraint(equalTo: providerListStack.widthAnchor).isActive = true
        }
    }

    private func rebuildModelsList(resetScroll: Bool = true) {
        let savedOrigin = modelsScrollView.contentView.bounds.origin
        for view in modelsListStack.arrangedSubviews {
            modelsListStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let discovered = selectedProviderId == activeProviderId ? discoveredModels : []
        let options = ProviderModelCatalog.shared.options(
            for: selectedProviderId,
            discovered: discovered
        )
        let normalizedActive = ProviderModelCatalog.shared.resolveConcreteModelId(
            providerId: activeProviderId,
            model: activeModelId
        )
        for option in options {
            let isSelected = selectedProviderId == activeProviderId && option.id == normalizedActive
            let row = ModelOptionRowButton(
                providerId: selectedProviderId,
                modelId: option.id,
                label: option.label,
                selected: isSelected,
                theme: theme
            )
            row.target = self
            row.action = #selector(handleModelRowTap(_:))
            modelsListStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: modelsListStack.widthAnchor).isActive = true
        }
        modelsScrollView.contentView.scroll(to: resetScroll ? .zero : savedOrigin)
        modelsScrollView.reflectScrolledClipView(modelsScrollView.contentView)
    }

    private func rebuildEffortButtons() {
        for view in effortListStack.arrangedSubviews {
            effortListStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        effortButtons.removeAll()
        let choices = ProviderModelCatalog.shared.effortOptions(for: selectedProviderId)
        for (idx, choice) in choices.enumerated() {
            let btn = EffortOptionRowButton(
                effortId: choice.id,
                label: choice.label,
                selected: choice.id == selectedEffort,
                theme: theme
            )
            btn.tag = idx
            btn.target = self
            btn.action = #selector(handleEffortTap(_:))
            effortButtons.append(btn)
            effortListStack.addArrangedSubview(btn)
            btn.widthAnchor.constraint(equalTo: effortListStack.widthAnchor).isActive = true
        }
    }

    @objc private func handleProviderTabTap(_ sender: NSControl) {
        let idx = sender.tag
        guard idx >= 0, idx < providers.count else {
            return
        }
        selectedProviderId = providers[idx].id
        rebuildProviderTabs()
        rebuildModelsList()
        rebuildEffortButtons()
        view.layoutSubtreeIfNeeded()
    }

    @objc private func handleModelRowTap(_ sender: ModelOptionRowButton) {
        activeProviderId = sender.providerId
        activeModelId = sender.modelId
        rebuildModelsList(resetScroll: false)
        view.layoutSubtreeIfNeeded()
        onSelectModel?(sender.providerId, sender.modelId, selectedEffort)
    }

    @objc private func handleEffortTap(_ sender: NSButton) {
        let choices = ProviderModelCatalog.shared.effortOptions(for: selectedProviderId)
        let idx = sender.tag
        guard idx >= 0, idx < choices.count else {
            return
        }
        selectedEffort = choices[idx].id
        rebuildEffortButtons()
        if selectedProviderId == activeProviderId {
            view.layoutSubtreeIfNeeded()
            onSelectEffort?(selectedEffort)
        } else {
            let defaultModel = ProviderModelCatalog.shared.defaultModelId(for: selectedProviderId)
            activeProviderId = selectedProviderId
            activeModelId = defaultModel
            rebuildModelsList(resetScroll: false)
            view.layoutSubtreeIfNeeded()
            onSelectModel?(selectedProviderId, defaultModel, selectedEffort)
        }
    }

    @objc private func handleCustomModelTap() {
        onRequestCustomModel?(selectedProviderId)
    }
}

private final class ComposerActionButton: NSControl {
    enum Mode {
        case sendIdle
        case sendReady
        case stop
    }

    var mode: Mode = .sendIdle {
        didSet {
            if mode != oldValue {
                needsDisplay = true
            }
        }
    }

    private var theme: KasugaiThemeTokens = KasugaiThemeTokens.resolve(
        palette: .kasugai, isLight: false)
    private var isHovered: Bool = false
    private var isPressed: Bool = false
    private var trackingAreaRef: NSTrackingArea?

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 28),
            heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 28, height: 28)
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
        KasugaiInteractiveMotion.applyScale(to: self, scale: 1.07)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
        needsDisplay = true
        KasugaiInteractiveMotion.applyScale(to: self, scale: 1.0)
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        needsDisplay = true
        KasugaiInteractiveMotion.applyScale(to: self, scale: 0.92)
    }

    override func mouseDragged(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let inside = bounds.contains(local)
        if inside != isPressed {
            isPressed = inside
            needsDisplay = true
            KasugaiInteractiveMotion.applyScale(to: self, scale: inside ? 0.92 : 1.0)
        }
    }

    override func mouseUp(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let shouldFire = isPressed && bounds.contains(local)
        isPressed = false
        needsDisplay = true
        KasugaiInteractiveMotion.applyScale(to: self, scale: bounds.contains(local) ? 1.07 : 1.0)
        if shouldFire {
            sendAction(action, to: target)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let side = min(bounds.width, bounds.height)
        let circleRect = NSRect(
            x: (bounds.width - side) / 2.0 + 0.5,
            y: (bounds.height - side) / 2.0 + 0.5,
            width: side - 1.0,
            height: side - 1.0
        )
        let circle = NSBezierPath(ovalIn: circleRect)
        let cx = bounds.midX
        let cy = bounds.midY

        switch mode {
        case .sendReady:
            let alpha: CGFloat = isPressed ? 0.76 : (isHovered ? 0.88 : 1.0)
            theme.sendBg.withAlphaComponent(alpha).setFill()
            circle.fill()
            drawUpArrow(cx: cx, cy: cy, color: theme.sendFg)
        case .sendIdle:
            let bg =
                isPressed
                ? theme.borderStrong
                : (isHovered ? theme.surfaceSelected : theme.surfaceElevated)
            bg.setFill()
            circle.fill()
            theme.borderSubtle.setStroke()
            circle.lineWidth = 1.0
            circle.stroke()
            drawUpArrow(cx: cx, cy: cy, color: theme.textMuted)
        case .stop:
            let fillAlpha: CGFloat = isPressed ? 0.28 : (isHovered ? 0.21 : 0.13)
            let strokeAlpha: CGFloat = isPressed ? 0.75 : (isHovered ? 0.62 : 0.40)
            theme.danger.withAlphaComponent(fillAlpha).setFill()
            circle.fill()
            theme.danger.withAlphaComponent(strokeAlpha).setStroke()
            circle.lineWidth = 1.0
            circle.stroke()

            let sq: CGFloat = 9.0
            let sqRect = NSRect(x: cx - sq / 2.0, y: cy - sq / 2.0, width: sq, height: sq)
            let sqPath = NSBezierPath(roundedRect: sqRect, xRadius: 2.2, yRadius: 2.2)
            theme.danger.setFill()
            sqPath.fill()
        }
    }

    private func drawUpArrow(cx: CGFloat, cy: CGFloat, color: NSColor) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: cx, y: cy + 5.2))
        path.line(to: NSPoint(x: cx, y: cy - 5.0))
        path.move(to: NSPoint(x: cx - 4.1, y: cy - 1.1))
        path.line(to: NSPoint(x: cx, y: cy - 5.2))
        path.line(to: NSPoint(x: cx + 4.1, y: cy - 1.1))
        path.lineWidth = 1.85
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }
}

final class ComposerView: NSView, NSTextViewDelegate {
    var onSend: ((String, [String]) -> Bool)?
    var onEnqueue: ((String, [String]) -> Bool)?
    var onProcessQueue: (() -> Void)?
    var onCancelTurn: (() -> Void)?
    var onProviderChanged: ((String, String, String) -> Void)?
    var onApprovalPolicyChanged: ((KasugaiToolApprovalPolicy) -> Void)?
    var onDraftChanged: ((KasugaiComposerDraft) -> Void)?

    private let outerSurface = KasugaiSurfaceView()
    private let cardSurface = KasugaiSurfaceView()
    private let queueBar = KasugaiSurfaceView()
    private let queueStatusLabel = NSTextField(labelWithString: "")
    private let runQueueButton = KasugaiFlatButton()
    private let attachmentStrip = NSStackView()
    private let textScrollView = NSScrollView()
    private let textView = ComposerTextView()
    private var textHeightConstraint: NSLayoutConstraint?
    private var lastLayoutWidth: CGFloat = 0
    private let attachButton = KasugaiFlatButton()
    private let modelMenuButton = ModelPickerPillButton()
    private let approvalMenuButton = KasugaiFlatButton()
    private let enqueueButton = KasugaiFlatButton()
    private let stopCircleButton = ComposerActionButton()
    private let actionCircleButton = ComposerActionButton()

    private var providers: [KasugaiProviderSpec] = []
    private var availableModels: [String] = []
    private var attachments: [String] = []
    private var currentProviderId: String = "claude_code"
    private var currentProviderName: String = "Claude Code"
    private var currentModel: String = "default"
    private var currentEffort: String = "medium"
    private var currentApprovalPolicy: KasugaiToolApprovalPolicy = .alwaysAllow
    private var isTurnActive: Bool = false
    private var isFocused: Bool = false
    private var isRestoringDraft: Bool = false
    private var palette: KasugaiPalette = .kasugai
    private var theme: KasugaiThemeTokens = KasugaiThemeTokens.resolve(
        palette: .kasugai, isLight: false)
    private var modelPickerPopover: NSPopover?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
        applyTheme()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func focusInput() {
        window?.makeFirstResponder(textView)
    }

    func appendExternalAttachments(_ paths: [String]) {
        appendAttachments(paths)
        focusInput()
    }

    var currentDraft: KasugaiComposerDraft {
        KasugaiComposerDraft(text: textView.string, attachments: attachments)
    }

    func restoreDraft(_ draft: KasugaiComposerDraft?) {
        isRestoringDraft = true
        defer { isRestoringDraft = false }
        let nextText = draft?.text ?? ""
        let fm = FileManager.default
        let nextAttachments = (draft?.attachments ?? []).filter {
            !$0.isEmpty && fm.fileExists(atPath: $0)
        }
        textView.string = nextText
        let end = (nextText as NSString).length
        textView.setSelectedRange(NSRange(location: end, length: 0))
        textView.needsDisplay = true
        attachments = nextAttachments
        updateTextHeight()
        refreshAttachmentStrip()
        syncActionCircle()
    }

    func update(palette: KasugaiPalette) {
        self.palette = palette
        applyTheme()
    }

    func update(approvalPolicy: KasugaiToolApprovalPolicy) {
        currentApprovalPolicy = approvalPolicy
        syncApprovalButton()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTheme()
    }

    func applyTheme() {
        theme = KasugaiThemeTokens.resolve(palette: palette, appearance: effectiveAppearance)
        outerSurface.fillColor = theme.canvasBg
        cardSurface.fillColor = theme.surfaceBg
        cardSurface.strokeColor = isFocused ? theme.borderStrong : theme.borderSubtle
        queueBar.fillColor = theme.warning.withAlphaComponent(0.12)
        queueBar.strokeColor = theme.warning.withAlphaComponent(0.26)
        queueStatusLabel.textColor = theme.warning
        runQueueButton.apply(theme: theme)
        textView.textColor = theme.textPrimary
        textView.insertionPointColor = theme.accent
        textView.placeholderColor = theme.textMuted
        attachButton.apply(theme: theme)
        modelMenuButton.apply(theme: theme)
        syncApprovalButton()
        enqueueButton.apply(theme: theme)
        syncActionCircle()
        refreshAttachmentStrip()
    }

    func update(snapshot: KasugaiCoreSnapshot) {
        providers = snapshot.providers
        guard let thread = snapshot.activeThread else {
            isTurnActive = false
            queueBar.isHidden = true
            syncActionCircle()
            return
        }

        currentProviderId = thread.provider
        currentProviderName = thread.providerName
        currentModel = thread.model
        currentEffort = thread.effort
        availableModels = thread.availableModels
        isTurnActive = thread.status == "running" || thread.status == "awaiting_approval"

        let displayLabel = ProviderModelCatalog.shared.pillTitle(
            providerId: thread.provider,
            providerName: thread.providerName,
            model: thread.model,
            effort: thread.effort
        )
        modelMenuButton.configure(providerId: thread.provider, title: displayLabel)
        modelMenuButton.apply(theme: theme)

        if thread.queue.isEmpty || isTurnActive {
            queueBar.isHidden = true
        } else {
            queueBar.isHidden = false
            queueStatusLabel.stringValue = "待機中のキュー: \(thread.queue.count) 件"
            runQueueButton.isHidden = false
        }

        syncActionCircle()
    }

    private func setupView() {
        wantsLayer = true
        outerSurface.translatesAutoresizingMaskIntoConstraints = false

        cardSurface.cornerRadius = 16
        cardSurface.strokeWidth = 1
        cardSurface.translatesAutoresizingMaskIntoConstraints = false

        queueBar.cornerRadius = 10
        queueBar.strokeWidth = 1
        queueBar.isHidden = true
        queueBar.translatesAutoresizingMaskIntoConstraints = false

        queueStatusLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        queueStatusLabel.lineBreakMode = .byTruncatingTail
        queueStatusLabel.setContentHuggingPriority(.init(200), for: .horizontal)
        queueStatusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        runQueueButton.buttonStyle = .subtleFilled
        runQueueButton.horizontalPadding = 8
        runQueueButton.font = .systemFont(ofSize: 11, weight: .semibold)
        runQueueButton.title = "今すぐ実行"
        runQueueButton.target = self
        runQueueButton.action = #selector(handleProcessQueue)

        let queueSpacer = NSView()
        queueSpacer.setContentHuggingPriority(.init(100), for: .horizontal)

        let queueRow = NSStackView(views: [queueStatusLabel, queueSpacer, runQueueButton])
        queueRow.orientation = .horizontal
        queueRow.alignment = .centerY
        queueRow.spacing = 8
        queueRow.translatesAutoresizingMaskIntoConstraints = false
        queueBar.addSubview(queueRow)
        NSLayoutConstraint.activate([
            queueRow.topAnchor.constraint(equalTo: queueBar.topAnchor, constant: 5),
            queueRow.bottomAnchor.constraint(equalTo: queueBar.bottomAnchor, constant: -5),
            queueRow.leadingAnchor.constraint(equalTo: queueBar.leadingAnchor, constant: 12),
            queueRow.trailingAnchor.constraint(equalTo: queueBar.trailingAnchor, constant: -10),
        ])

        attachmentStrip.orientation = .horizontal
        attachmentStrip.alignment = .centerY
        attachmentStrip.spacing = 6
        attachmentStrip.isHidden = true
        attachmentStrip.translatesAutoresizingMaskIntoConstraints = false

        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 22
        textView.font = .systemFont(ofSize: 14)
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 14),
            .paragraphStyle: paragraph,
        ]
        textView.drawsBackground = false
        textView.registerForDraggedTypes([.fileURL, .png, .tiff])
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 2, height: 3)
        textView.minSize = NSSize(width: 0, height: 30)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self
        textView.onSubmit = { [weak self] in
            self?.handlePrimarySubmit()
        }
        textView.onAttachPaths = { [weak self] paths in
            self?.appendAttachments(paths)
        }
        textView.onFocusChanged = { [weak self] focused in
            self?.isFocused = focused
            self?.applyTheme()
        }
        textView.onContentHeightInvalidated = { [weak self] in
            self?.updateTextHeight()
        }

        let clipView = FlippedClipView()
        clipView.drawsBackground = false
        textScrollView.contentView = clipView
        textScrollView.documentView = textView
        textScrollView.hasVerticalScroller = true
        textScrollView.autohidesScrollers = true
        textScrollView.drawsBackground = false
        textScrollView.borderType = .noBorder
        textScrollView.translatesAutoresizingMaskIntoConstraints = false
        let heightConstraint = textScrollView.heightAnchor.constraint(equalToConstant: 30)
        heightConstraint.isActive = true
        textHeightConstraint = heightConstraint

        attachButton.buttonStyle = .ghost
        attachButton.horizontalPadding = 6
        attachButton.configureSymbol("paperclip", pointSize: 13, weight: .medium)
        attachButton.toolTip = "ファイルを添付…"
        attachButton.target = self
        attachButton.action = #selector(handleAttachFile)

        modelMenuButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        modelMenuButton.configure(providerId: currentProviderId, title: "Claude Code")
        modelMenuButton.target = self
        modelMenuButton.action = #selector(handleShowModelMenu)

        approvalMenuButton.buttonStyle = .ghost
        approvalMenuButton.horizontalPadding = 6
        approvalMenuButton.sendAction(on: [.leftMouseDown])
        approvalMenuButton.target = self
        approvalMenuButton.action = #selector(handleShowApprovalPolicyMenu)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        enqueueButton.buttonStyle = .ghost
        enqueueButton.horizontalPadding = 6
        enqueueButton.configureSymbol(
            "text.badge.plus",
            pointSize: 13,
            weight: .medium
        )
        enqueueButton.toolTip = "キューに追加（完了後に送信）"
        enqueueButton.target = self
        enqueueButton.action = #selector(handleEnqueue)

        stopCircleButton.mode = .stop
        stopCircleButton.toolTip = "停止"
        stopCircleButton.isHidden = true
        stopCircleButton.target = self
        stopCircleButton.action = #selector(handleStopCircle)

        actionCircleButton.target = self
        actionCircleButton.action = #selector(handleActionCircle)

        let bottomBar = NSStackView(views: [
            attachButton,
            modelMenuButton,
            approvalMenuButton,
            spacer,
            enqueueButton,
            stopCircleButton,
            actionCircleButton,
        ])
        bottomBar.orientation = .horizontal
        bottomBar.alignment = .centerY
        bottomBar.spacing = 4
        bottomBar.translatesAutoresizingMaskIntoConstraints = false

        let cardStack = NSStackView(views: [attachmentStrip, textScrollView, bottomBar])
        cardStack.orientation = .vertical
        cardStack.alignment = .width
        cardStack.spacing = 6
        cardStack.translatesAutoresizingMaskIntoConstraints = false

        cardSurface.addSubview(cardStack)

        let outerColumn = NSStackView(views: [queueBar, cardSurface])
        outerColumn.orientation = .vertical
        outerColumn.alignment = .width
        outerColumn.spacing = 6
        outerColumn.translatesAutoresizingMaskIntoConstraints = false

        outerSurface.addSubview(outerColumn)
        addSubview(outerSurface)

        let widthCap = outerColumn.widthAnchor.constraint(lessThanOrEqualToConstant: 760)
        let idealWidth = outerColumn.widthAnchor.constraint(equalToConstant: 760)
        idealWidth.priority = NSLayoutConstraint.Priority(240)

        NSLayoutConstraint.activate([
            outerSurface.topAnchor.constraint(equalTo: topAnchor),
            outerSurface.leadingAnchor.constraint(equalTo: leadingAnchor),
            outerSurface.trailingAnchor.constraint(equalTo: trailingAnchor),
            outerSurface.bottomAnchor.constraint(equalTo: bottomAnchor),

            outerColumn.topAnchor.constraint(equalTo: outerSurface.topAnchor, constant: 4),
            outerColumn.bottomAnchor.constraint(equalTo: outerSurface.bottomAnchor, constant: -12),
            outerColumn.centerXAnchor.constraint(equalTo: outerSurface.centerXAnchor),
            outerColumn.leadingAnchor.constraint(
                greaterThanOrEqualTo: outerSurface.leadingAnchor, constant: 20),
            outerColumn.trailingAnchor.constraint(
                lessThanOrEqualTo: outerSurface.trailingAnchor, constant: -20),
            widthCap,
            idealWidth,

            cardStack.topAnchor.constraint(equalTo: cardSurface.topAnchor, constant: 8),
            cardStack.leadingAnchor.constraint(equalTo: cardSurface.leadingAnchor, constant: 12),
            cardStack.trailingAnchor.constraint(equalTo: cardSurface.trailingAnchor, constant: -12),
            cardStack.bottomAnchor.constraint(equalTo: cardSurface.bottomAnchor, constant: -8),
        ])
    }

    override func layout() {
        super.layout()
        if abs(bounds.width - lastLayoutWidth) > 0.5 {
            lastLayoutWidth = bounds.width
            updateTextHeight()
        }
    }

    private func updateTextHeight() {
        guard let layoutManager = textView.layoutManager,
            let container = textView.textContainer
        else {
            return
        }
        layoutManager.ensureLayout(for: container)
        let insetHeight = textView.textContainerInset.height * 2
        let used = layoutManager.usedRect(for: container).height + insetHeight
        let target = min(max(30, ceil(used)), 140)
        if textHeightConstraint?.constant != target {
            textHeightConstraint?.constant = target
        }
    }

    private func syncApprovalButton() {
        let symbolName =
            currentApprovalPolicy == .alwaysAllow ? "bolt.shield" : "lock.shield"
        approvalMenuButton.customTintColor =
            currentApprovalPolicy == .alwaysAllow ? theme.warning : nil
        approvalMenuButton.toolTip = "ツール実行の承認: \(currentApprovalPolicy.label)"
        approvalMenuButton.configureSymbol(
            symbolName,
            pointSize: 13,
            weight: .medium
        )
        approvalMenuButton.apply(theme: theme)
    }

    func setTurnActiveForSnapshot(_ active: Bool) {
        isTurnActive = active
        syncActionCircle()
    }

    private func syncActionCircle() {
        let hasInput =
            !textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !attachments.isEmpty
        enqueueButton.isHidden = !hasInput
        enqueueButton.isEnabled = hasInput
        if isTurnActive {
            stopCircleButton.isHidden = false
            stopCircleButton.mode = .stop
            stopCircleButton.toolTip = "停止"
            stopCircleButton.apply(theme: theme)

            actionCircleButton.isHidden = !hasInput
            actionCircleButton.mode = .sendReady
            actionCircleButton.toolTip =
                currentProviderId == "antigravity_acp" ? "差し込み送信" : "送信"
        } else {
            stopCircleButton.isHidden = true
            actionCircleButton.isHidden = false
            actionCircleButton.mode = hasInput ? .sendReady : .sendIdle
            actionCircleButton.toolTip = "送信"
        }
        actionCircleButton.apply(theme: theme)
    }

    private func notifyDraftChanged() {
        guard !isRestoringDraft else {
            return
        }
        onDraftChanged?(currentDraft)
    }

    private func appendAttachments(_ paths: [String]) {
        var added = false
        for path in paths where !path.isEmpty && !attachments.contains(path) {
            attachments.append(path)
            added = true
        }
        refreshAttachmentStrip()
        if added {
            syncActionCircle()
            notifyDraftChanged()
        }
    }

    private func makeAttachmentChip(path: String, index: Int) -> NSView {
        let chip = KasugaiSurfaceView()
        chip.cornerRadius = 8
        chip.strokeWidth = 1
        chip.fillColor = theme.surfaceElevated
        chip.strokeColor = theme.borderSubtle
        chip.translatesAutoresizingMaskIntoConstraints = false

        var views: [NSView] = []
        if AttachmentStorage.isImagePath(path), let img = NSImage(contentsOfFile: path) {
            let thumb = NSImageView(image: img)
            thumb.imageScaling = .scaleProportionallyUpOrDown
            thumb.wantsLayer = true
            thumb.layer?.cornerRadius = 4
            thumb.layer?.masksToBounds = true
            thumb.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                thumb.widthAnchor.constraint(equalToConstant: 20),
                thumb.heightAnchor.constraint(equalToConstant: 20),
            ])
            views.append(thumb)
        } else {
            let icon = NSImageView()
            let cfg = NSImage.SymbolConfiguration(pointSize: 10.5, weight: .medium)
            icon.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: nil)?
                .withSymbolConfiguration(cfg)
            icon.contentTintColor = theme.textSecondary
            icon.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                icon.widthAnchor.constraint(equalToConstant: 12),
                icon.heightAnchor.constraint(equalToConstant: 12),
            ])
            views.append(icon)
        }

        let name = URL(fileURLWithPath: path).lastPathComponent
        let label = NSTextField(labelWithString: name)
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = theme.textPrimary
        label.lineBreakMode = .byTruncatingMiddle
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        views.append(label)

        let removeBtn = KasugaiFlatButton()
        removeBtn.buttonStyle = .ghost
        removeBtn.customHeight = 18
        removeBtn.horizontalPadding = 3
        removeBtn.tag = index
        removeBtn.configureSymbol("xmark", pointSize: 8.5, weight: .semibold)
        removeBtn.toolTip = "添付を削除"
        removeBtn.apply(theme: theme)
        removeBtn.target = self
        removeBtn.action = #selector(handleRemoveAttachment(_:))
        views.append(removeBtn)

        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false

        chip.addSubview(row)
        NSLayoutConstraint.activate([
            chip.heightAnchor.constraint(equalToConstant: 28),
            chip.widthAnchor.constraint(lessThanOrEqualToConstant: 200),
            row.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 6),
            row.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -4),
            row.centerYAnchor.constraint(equalTo: chip.centerYAnchor),
        ])
        return chip
    }

    private func refreshAttachmentStrip() {
        for view in attachmentStrip.arrangedSubviews {
            attachmentStrip.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        if attachments.isEmpty {
            attachmentStrip.isHidden = true
            return
        }
        attachmentStrip.isHidden = false
        for (idx, path) in attachments.prefix(4).enumerated() {
            attachmentStrip.addArrangedSubview(makeAttachmentChip(path: path, index: idx))
        }
        if attachments.count > 4 {
            let extra = NSTextField(labelWithString: "+\(attachments.count - 4) 件")
            extra.font = .systemFont(ofSize: 11)
            extra.textColor = theme.textMuted
            attachmentStrip.addArrangedSubview(extra)
        }
        let filler = NSView()
        filler.setContentHuggingPriority(.defaultLow, for: .horizontal)
        attachmentStrip.addArrangedSubview(filler)
    }

    private func currentComposerPayload() -> (text: String, files: [String])? {
        let trimmed = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return (trimmed, attachments)
        }
        guard !attachments.isEmpty else {
            return nil
        }
        let allImages = attachments.allSatisfy { AttachmentStorage.isImagePath($0) }
        return (allImages ? "添付画像" : "添付ファイル", attachments)
    }

    private func clearComposerPayload() {
        textView.string = ""
        textView.needsDisplay = true
        updateTextHeight()
        attachments = []
        refreshAttachmentStrip()
        syncActionCircle()
        notifyDraftChanged()
    }

    func textDidChange(_ notification: Notification) {
        textView.needsDisplay = true
        updateTextHeight()
        syncActionCircle()
        notifyDraftChanged()
    }

    private func handlePrimarySubmit() {
        guard let payload = currentComposerPayload() else {
            return
        }
        let delivered: Bool
        if isTurnActive && currentProviderId != "antigravity_acp" {
            delivered = onEnqueue?(payload.text, payload.files) ?? false
        } else {
            delivered = onSend?(payload.text, payload.files) ?? false
        }
        if delivered {
            clearComposerPayload()
        }
    }

    @objc private func handleActionCircle() {
        handlePrimarySubmit()
    }

    @objc private func handleStopCircle() {
        onCancelTurn?()
    }

    @objc private func handleEnqueue() {
        guard let payload = currentComposerPayload() else {
            return
        }
        if onEnqueue?(payload.text, payload.files) ?? false {
            clearComposerPayload()
        }
    }

    @objc private func handleProcessQueue() {
        onProcessQueue?()
    }

    @objc private func handleRemoveAttachment(_ sender: NSButton) {
        let idx = sender.tag
        guard idx >= 0, idx < attachments.count else {
            return
        }
        attachments.remove(at: idx)
        refreshAttachmentStrip()
        syncActionCircle()
        notifyDraftChanged()
    }

    @objc private func handleShowModelMenu() {
        if let existing = modelPickerPopover, existing.isShown {
            existing.performClose(nil)
            return
        }
        let picker = ModelPickerPopoverViewController(
            providers: providers,
            activeProviderId: currentProviderId,
            activeModelId: currentModel,
            activeEffort: currentEffort,
            discoveredModels: availableModels,
            theme: theme
        )
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = effectiveAppearance
        popover.contentViewController = picker
        popover.contentSize = ModelPickerPopoverViewController.fixedPopoverSize
        picker.onSelectModel = { [weak self] provId, modelId, effort in
            guard let self else {
                return
            }
            if let spec = self.providers.first(where: { $0.id == provId }) {
                self.currentProviderId = spec.id
                self.currentProviderName = spec.displayName
            } else {
                self.currentProviderId = provId
            }
            self.currentModel = modelId
            self.currentEffort = effort
            let label = ProviderModelCatalog.shared.pillTitle(
                providerId: self.currentProviderId,
                providerName: self.currentProviderName,
                model: modelId,
                effort: effort
            )
            self.modelMenuButton.configure(providerId: self.currentProviderId, title: label)
            self.modelMenuButton.apply(theme: self.theme)
            self.onProviderChanged?(self.currentProviderId, modelId, effort)
        }
        picker.onSelectEffort = { [weak self] effort in
            guard let self else {
                return
            }
            self.currentEffort = effort
            let label = ProviderModelCatalog.shared.pillTitle(
                providerId: self.currentProviderId,
                providerName: self.currentProviderName,
                model: self.currentModel,
                effort: effort
            )
            self.modelMenuButton.configure(providerId: self.currentProviderId, title: label)
            self.modelMenuButton.apply(theme: self.theme)
            self.onProviderChanged?(self.currentProviderId, self.currentModel, effort)
        }
        picker.onRequestCustomModel = { [weak self, weak popover] provId in
            popover?.performClose(nil)
            guard let self else {
                return
            }
            if let spec = self.providers.first(where: { $0.id == provId }) {
                self.currentProviderId = spec.id
                self.currentProviderName = spec.displayName
            }
            self.handlePromptCustomModel()
        }
        modelPickerPopover = popover
        popover.show(
            relativeTo: modelMenuButton.bounds,
            of: modelMenuButton,
            preferredEdge: .maxY
        )
    }

    @objc private func handleShowApprovalPolicyMenu() {
        let menu = NSMenu()
        let header = NSMenuItem(title: "ツール実行の承認", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for policy in KasugaiToolApprovalPolicy.allCases {
            let menuItem = NSMenuItem(
                title: policy.label,
                action: #selector(handlePickApprovalPolicy(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.representedObject = policy.rawValue
            menuItem.state = policy == currentApprovalPolicy ? .on : .off
            menu.addItem(menuItem)
        }
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: 0),
            in: approvalMenuButton
        )
    }

    @objc private func handlePickApprovalPolicy(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
            let policy = KasugaiToolApprovalPolicy(rawValue: raw)
        else {
            return
        }
        currentApprovalPolicy = policy
        syncApprovalButton()
        onApprovalPolicyChanged?(policy)
    }

    @objc private func handlePromptCustomModel() {
        let alert = NSAlert()
        alert.messageText = "モデル名を指定"
        alert.informativeText = "\(currentProviderName) で使用するモデル ID を入力してください。"
        alert.addButton(withTitle: "適用")
        alert.addButton(withTitle: "キャンセル")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = currentModel
        field.placeholderString = "例: default"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        let nextModel = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nextModel.isEmpty else {
            return
        }
        currentModel = nextModel
        onProviderChanged?(currentProviderId, nextModel, currentEffort)
    }

    @objc private func handleAttachFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "添付"
        if panel.runModal() == .OK {
            appendAttachments(panel.urls.map(\.path))
        }
    }

    static func runSelfTests() -> Bool {
        _ = NSApplication.shared
        let composer = ComposerView(frame: NSRect(x: 0, y: 0, width: 760, height: 100))
        composer.layoutSubtreeIfNeeded()
        let initialHeight = composer.textHeightConstraint?.constant ?? 999
        let claudeModels = ProviderModelCatalog.shared.options(for: "claude_code")
        let codexModels = ProviderModelCatalog.shared.options(for: "codex")
        let noOpaqueLabels = (claudeModels + codexModels).allSatisfy {
            !$0.label.contains("最新") && $0.id != "default" && $0.id != "opus" && $0.id != "sonnet"
        }
        guard composer.textScrollView.contentView.isFlipped,
            composer.textView.shouldDrawPlaceholder,
            initialHeight <= 32,
            claudeModels.count >= 4,
            codexModels.count >= 4,
            noOpaqueLabels
        else {
            return false
        }
        composer.textView.setMarkedText(
            "こん",
            selectedRange: NSRange(location: 2, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        let markedHeight = composer.textHeightConstraint?.constant ?? 999
        guard !composer.textView.shouldDrawPlaceholder, markedHeight == initialHeight else {
            return false
        }
        composer.textView.unmarkText()
        composer.textView.string = "hello"
        composer.updateTextHeight()
        let asciiHeight = composer.textHeightConstraint?.constant ?? 999
        composer.textView.string = "日本語のテスト"
        composer.updateTextHeight()
        let japaneseHeight = composer.textHeightConstraint?.constant ?? 999
        guard asciiHeight == initialHeight, japaneseHeight == initialHeight else {
            return false
        }
        composer.textView.string = ""
        composer.updateTextHeight()
        composer.update(approvalPolicy: .askEveryTime)
        let askTip = composer.approvalMenuButton.toolTip ?? ""
        composer.update(approvalPolicy: .alwaysAllow)
        let allowTip = composer.approvalMenuButton.toolTip ?? ""
        composer.restoreDraft(KasugaiComposerDraft(text: "再起動前の下書き", attachments: []))
        let restoredText = composer.currentDraft.text
        let actionReadyMode = composer.actionCircleButton.mode
        let enqueueVisibleWithDraft = !composer.enqueueButton.isHidden
        composer.restoreDraft(nil)
        let actionIdleMode = composer.actionCircleButton.mode
        let enqueueHiddenWhenEmpty = composer.enqueueButton.isHidden
        composer.isTurnActive = true
        composer.syncActionCircle()
        let stopVisibleWhenBusyEmpty =
            !composer.stopCircleButton.isHidden && composer.stopCircleButton.mode == .stop
        let sendHiddenWhenBusyEmpty = composer.actionCircleButton.isHidden
        composer.restoreDraft(KasugaiComposerDraft(text: "差し込みメッセージ", attachments: []))
        let stopAndSendVisibleWhenBusyTyped =
            !composer.stopCircleButton.isHidden && !composer.actionCircleButton.isHidden
            && composer.actionCircleButton.mode == .sendReady && !composer.enqueueButton.isHidden
        composer.restoreDraft(nil)
        composer.isTurnActive = false
        composer.syncActionCircle()
        composer.layoutSubtreeIfNeeded()
        let actionSize = composer.actionCircleButton.frame.size
        let actionIntrinsic = composer.actionCircleButton.intrinsicContentSize
        let claudeEffortMax = ProviderModelCatalog.shared.effortLabel(
            for: "claude_code",
            effort: "xhigh"
        )
        let codexEffortXHigh = ProviderModelCatalog.shared.effortLabel(
            for: "codex",
            effort: "xhigh"
        )
        let claudePill = ProviderModelCatalog.shared.pillTitle(
            providerId: "claude_code",
            providerName: "Claude Code",
            model: "claude-opus-5-5",
            effort: "high"
        )
        let agyPill = ProviderModelCatalog.shared.pillTitle(
            providerId: "antigravity_acp",
            providerName: "Antigravity (ACP)",
            model: "gemini-4-neon-high",
            effort: "high"
        )
        let sampleProviders = [
            KasugaiProviderSpec(
                id: "claude_code",
                displayName: "Claude Code",
                transport: "claude_stream_json",
                defaultModel: "default",
                ready: true,
                launchSpec: ""
            ),
            KasugaiProviderSpec(
                id: "codex",
                displayName: "Codex",
                transport: "codex_app_server",
                defaultModel: "default",
                ready: true,
                launchSpec: ""
            ),
            KasugaiProviderSpec(
                id: "antigravity_acp",
                displayName: "Antigravity (ACP)",
                transport: "acp_stdio",
                defaultModel: "default",
                ready: true,
                launchSpec: ""
            ),
        ]
        let picker = ModelPickerPopoverViewController(
            providers: sampleProviders,
            activeProviderId: "claude_code",
            activeModelId: "claude-opus-5-5",
            activeEffort: "high",
            discoveredModels: [],
            theme: KasugaiThemeTokens.resolve(palette: .kasugai, isLight: false)
        )
        _ = picker.view
        let pickerHeight = picker.preferredContentSize.height
        let pickerWidth = picker.preferredContentSize.width
        let pickerFrameBefore = picker.view.frame
        let pickerRootAutoMask = picker.view.translatesAutoresizingMaskIntoConstraints
        let tabFrames = picker.providerTabFrames
        let effortFrames = picker.effortRowFrames
        let tabsFit =
            tabFrames.count == 3
            && tabFrames.allSatisfy {
                $0.width >= 140 && $0.height == 34 && $0.minX >= 0 && $0.maxX <= 164
                    && $0.minY >= 0 && $0.maxY <= pickerHeight
            }
        let effortsFit =
            effortFrames.count == 4
            && effortFrames.allSatisfy {
                $0.width >= 115 && $0.height == 32 && $0.minX >= 438 && $0.maxX <= pickerWidth
                    && $0.minY >= 0 && $0.maxY <= pickerHeight
            }
        let claudeEffortLabels = picker.displayedEffortLabels
        picker.selectProviderTabForTest("codex")
        let pickerFrameAfter = picker.view.frame
        let codexEffortLabels = picker.displayedEffortLabels
        let codexModelCount = picker.displayedModelCount

        let sampleImg = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
            NSColor.systemBlue.setFill()
            rect.fill()
            return true
        }
        let testPb = NSPasteboard(
            name: NSPasteboard.Name("kasugai.selfTest.paste.\(UUID().uuidString)")
        )
        testPb.clearContents()
        if let tiff = sampleImg.tiffRepresentation {
            testPb.setData(tiff, forType: .tiff)
        }
        let pbHasImage = AttachmentStorage.hasAttachableContent(in: testPb)
        let extractedImages = AttachmentStorage.extractPaths(from: testPb)
        let readableHasImages =
            composer.textView.readablePasteboardTypes.contains(.png)
            && composer.textView.readablePasteboardTypes.contains(.tiff)
        composer.appendAttachments(extractedImages)
        let imageOnlyReady = composer.actionCircleButton.mode == .sendReady
        let imageOnlyPayload = composer.currentComposerPayload()
        composer.clearComposerPayload()
        for p in extractedImages {
            try? FileManager.default.removeItem(atPath: p)
        }

        guard composer.textView.shouldDrawPlaceholder,
            composer.approvalMenuButton.title.isEmpty,
            composer.modelMenuButton.hasProviderIcon,
            !composer.modelMenuButton.displayTitle.contains("⌄"),
            pbHasImage,
            readableHasImages,
            extractedImages.count == 1,
            imageOnlyReady,
            imageOnlyPayload?.files.count == 1,
            askTip.contains("毎回確認"),
            allowTip.contains("常に許可"),
            restoredText == "再起動前の下書き",
            composer.currentDraft.isEmpty,
            claudeEffortMax == "Max",
            codexEffortXHigh == "XHigh",
            claudePill.contains("High"),
            !agyPill.contains("· High"),
            pickerHeight <= 320,
            pickerRootAutoMask,
            pickerFrameBefore == pickerFrameAfter,
            tabsFit,
            effortsFit,
            claudeEffortLabels.last == "Max",
            codexEffortLabels.last == "XHigh",
            codexModelCount >= 4,
            actionReadyMode == .sendReady,
            actionIdleMode == .sendIdle,
            stopVisibleWhenBusyEmpty,
            sendHiddenWhenBusyEmpty,
            stopAndSendVisibleWhenBusyTyped,
            enqueueVisibleWithDraft,
            enqueueHiddenWhenEmpty,
            actionIntrinsic == NSSize(width: 28, height: 28),
            actionSize == NSSize(width: 28, height: 28)
        else {
            fputs(
                "ComposerView self-test failed: pickerFrameBefore=\(pickerFrameBefore) after=\(pickerFrameAfter) tabsFit=\(tabsFit) effortsFit=\(effortsFit) tabFrames=\(tabFrames) effortFrames=\(effortFrames)\n",
                stderr
            )
            return false
        }
        return true
    }
}
