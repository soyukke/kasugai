import AppKit
import Foundation
import QuartzCore

struct KasugaiThemeTokens {
    let isLight: Bool
    let sidebarBg: NSColor
    let canvasBg: NSColor
    let surfaceBg: NSColor
    let surfaceElevated: NSColor
    let surfaceSelected: NSColor
    let borderSubtle: NSColor
    let borderStrong: NSColor
    let textPrimary: NSColor
    let textSecondary: NSColor
    let textMuted: NSColor
    let accent: NSColor
    let accentSoft: NSColor
    let sendBg: NSColor
    let sendFg: NSColor
    let success: NSColor
    let warning: NSColor
    let danger: NSColor

    static func resolve(palette: KasugaiPalette, appearance: NSAppearance?) -> KasugaiThemeTokens {
        let best = appearance?.bestMatch(from: [.darkAqua, .aqua])
        let isLight = best == .aqua
        return resolve(palette: palette, isLight: isLight)
    }

    static func resolve(palette: KasugaiPalette, isLight: Bool) -> KasugaiThemeTokens {
        switch (palette, isLight) {
        case (.slate, false):
            return KasugaiThemeTokens(
                isLight: false,
                sidebarBg: hex(0x0B1120),
                canvasBg: hex(0x0F172A),
                surfaceBg: hex(0x162033),
                surfaceElevated: hex(0x1E293B),
                surfaceSelected: hex(0xFFFFFF, alpha: 0.09),
                borderSubtle: hex(0x94A3B8, alpha: 0.14),
                borderStrong: hex(0x94A3B8, alpha: 0.24),
                textPrimary: hex(0xF1F5F9),
                textSecondary: hex(0x94A3B8),
                textMuted: hex(0x64748B),
                accent: hex(0x38BDF8),
                accentSoft: hex(0x38BDF8, alpha: 0.16),
                sendBg: hex(0xF1F5F9),
                sendFg: hex(0x0F172A),
                success: hex(0x4ADE80),
                warning: hex(0xFBBF24),
                danger: hex(0xF87171)
            )
        case (.slate, true):
            return KasugaiThemeTokens(
                isLight: true,
                sidebarBg: hex(0xEAF0F6),
                canvasBg: hex(0xF8FAFC),
                surfaceBg: hex(0xFFFFFF),
                surfaceElevated: hex(0xE2E8F0),
                surfaceSelected: hex(0x0F172A, alpha: 0.07),
                borderSubtle: hex(0x0F172A, alpha: 0.09),
                borderStrong: hex(0x0F172A, alpha: 0.16),
                textPrimary: hex(0x0F172A),
                textSecondary: hex(0x475569),
                textMuted: hex(0x64748B),
                accent: hex(0x0284C7),
                accentSoft: hex(0x0284C7, alpha: 0.12),
                sendBg: hex(0x0F172A),
                sendFg: hex(0xFFFFFF),
                success: hex(0x16A34A),
                warning: hex(0xD97706),
                danger: hex(0xDC2626)
            )
        case (.nord, false):
            return KasugaiThemeTokens(
                isLight: false,
                sidebarBg: hex(0x272C36),
                canvasBg: hex(0x2E3440),
                surfaceBg: hex(0x353C4A),
                surfaceElevated: hex(0x434C5E),
                surfaceSelected: hex(0xECEFF4, alpha: 0.10),
                borderSubtle: hex(0xD8DEE9, alpha: 0.12),
                borderStrong: hex(0xD8DEE9, alpha: 0.22),
                textPrimary: hex(0xECEFF4),
                textSecondary: hex(0xD8DEE9),
                textMuted: hex(0x9AA5B8),
                accent: hex(0x88C0D0),
                accentSoft: hex(0x88C0D0, alpha: 0.18),
                sendBg: hex(0xECEFF4),
                sendFg: hex(0x2E3440),
                success: hex(0xA3BE8C),
                warning: hex(0xEBCB8B),
                danger: hex(0xBF616A)
            )
        case (.nord, true):
            return KasugaiThemeTokens(
                isLight: true,
                sidebarBg: hex(0xE5E9F0),
                canvasBg: hex(0xF3F5F9),
                surfaceBg: hex(0xFFFFFF),
                surfaceElevated: hex(0xDCE2EC),
                surfaceSelected: hex(0x2E3440, alpha: 0.08),
                borderSubtle: hex(0x2E3440, alpha: 0.10),
                borderStrong: hex(0x2E3440, alpha: 0.18),
                textPrimary: hex(0x2E3440),
                textSecondary: hex(0x4C566A),
                textMuted: hex(0x6C778C),
                accent: hex(0x5E81AC),
                accentSoft: hex(0x5E81AC, alpha: 0.14),
                sendBg: hex(0x2E3440),
                sendFg: hex(0xECEFF4),
                success: hex(0x4F7D3E),
                warning: hex(0xB47B1E),
                danger: hex(0xB54552)
            )
        case (.warm, false):
            return KasugaiThemeTokens(
                isLight: false,
                sidebarBg: hex(0x161412),
                canvasBg: hex(0x1C1917),
                surfaceBg: hex(0x25211E),
                surfaceElevated: hex(0x312C28),
                surfaceSelected: hex(0xF5F1EB, alpha: 0.09),
                borderSubtle: hex(0xF5F1EB, alpha: 0.09),
                borderStrong: hex(0xF5F1EB, alpha: 0.17),
                textPrimary: hex(0xF5F1EB),
                textSecondary: hex(0xC2B6A8),
                textMuted: hex(0x8C7F70),
                accent: hex(0xF59E0B),
                accentSoft: hex(0xF59E0B, alpha: 0.16),
                sendBg: hex(0xF5F1EB),
                sendFg: hex(0x1C1917),
                success: hex(0x4ADE80),
                warning: hex(0xFBBF24),
                danger: hex(0xF87171)
            )
        case (.warm, true):
            return KasugaiThemeTokens(
                isLight: true,
                sidebarBg: hex(0xF3ECE2),
                canvasBg: hex(0xFAF6F0),
                surfaceBg: hex(0xFFFDF9),
                surfaceElevated: hex(0xEAE0D2),
                surfaceSelected: hex(0x292524, alpha: 0.07),
                borderSubtle: hex(0x292524, alpha: 0.09),
                borderStrong: hex(0x292524, alpha: 0.17),
                textPrimary: hex(0x292524),
                textSecondary: hex(0x57534E),
                textMuted: hex(0x78716C),
                accent: hex(0xB45309),
                accentSoft: hex(0xB45309, alpha: 0.12),
                sendBg: hex(0x292524),
                sendFg: hex(0xFAF6F0),
                success: hex(0x15803D),
                warning: hex(0xB45309),
                danger: hex(0xB91C1C)
            )
        case (.forest, false):
            return KasugaiThemeTokens(
                isLight: false,
                sidebarBg: hex(0x0D1512),
                canvasBg: hex(0x121C18),
                surfaceBg: hex(0x192621),
                surfaceElevated: hex(0x22332C),
                surfaceSelected: hex(0xE8F5EE, alpha: 0.09),
                borderSubtle: hex(0xA7F3D0, alpha: 0.11),
                borderStrong: hex(0xA7F3D0, alpha: 0.21),
                textPrimary: hex(0xECFDF5),
                textSecondary: hex(0xA7C4B5),
                textMuted: hex(0x6E8F7E),
                accent: hex(0x34D399),
                accentSoft: hex(0x34D399, alpha: 0.16),
                sendBg: hex(0xECFDF5),
                sendFg: hex(0x0D1512),
                success: hex(0x4ADE80),
                warning: hex(0xFBBF24),
                danger: hex(0xF87171)
            )
        case (.forest, true):
            return KasugaiThemeTokens(
                isLight: true,
                sidebarBg: hex(0xEAF2EC),
                canvasBg: hex(0xF5F9F6),
                surfaceBg: hex(0xFFFFFF),
                surfaceElevated: hex(0xDCE9E0),
                surfaceSelected: hex(0x143326, alpha: 0.07),
                borderSubtle: hex(0x143326, alpha: 0.09),
                borderStrong: hex(0x143326, alpha: 0.17),
                textPrimary: hex(0x14261D),
                textSecondary: hex(0x3F5C4D),
                textMuted: hex(0x648071),
                accent: hex(0x059669),
                accentSoft: hex(0x059669, alpha: 0.12),
                sendBg: hex(0x14261D),
                sendFg: hex(0xF5F9F6),
                success: hex(0x15803D),
                warning: hex(0xB45309),
                danger: hex(0xDC2626)
            )
        case (.rose, false):
            return KasugaiThemeTokens(
                isLight: false,
                sidebarBg: hex(0x161420),
                canvasBg: hex(0x191724),
                surfaceBg: hex(0x211E30),
                surfaceElevated: hex(0x2B273D),
                surfaceSelected: hex(0xE0DEF4, alpha: 0.10),
                borderSubtle: hex(0xE0DEF4, alpha: 0.10),
                borderStrong: hex(0xE0DEF4, alpha: 0.20),
                textPrimary: hex(0xE0DEF4),
                textSecondary: hex(0xB4B0CC),
                textMuted: hex(0x817C9C),
                accent: hex(0xEBBCBA),
                accentSoft: hex(0xEBBCBA, alpha: 0.16),
                sendBg: hex(0xEBBCBA),
                sendFg: hex(0x191724),
                success: hex(0x9CCFD8),
                warning: hex(0xF6C177),
                danger: hex(0xEB6F92)
            )
        case (.rose, true):
            return KasugaiThemeTokens(
                isLight: true,
                sidebarBg: hex(0xF4ECE8),
                canvasBg: hex(0xFAF4F1),
                surfaceBg: hex(0xFFFDFB),
                surfaceElevated: hex(0xEDE0DA),
                surfaceSelected: hex(0x575279, alpha: 0.08),
                borderSubtle: hex(0x575279, alpha: 0.10),
                borderStrong: hex(0x575279, alpha: 0.19),
                textPrimary: hex(0x3D3856),
                textSecondary: hex(0x635D80),
                textMuted: hex(0x8882A3),
                accent: hex(0xC45D78),
                accentSoft: hex(0xC45D78, alpha: 0.12),
                sendBg: hex(0x3D3856),
                sendFg: hex(0xFAF4F1),
                success: hex(0x286983),
                warning: hex(0xEA9D34),
                danger: hex(0xB4637A)
            )
        case (.twilight, false):
            return KasugaiThemeTokens(
                isLight: false,
                sidebarBg: hex(0x10111C),
                canvasBg: hex(0x161726),
                surfaceBg: hex(0x1E2034),
                surfaceElevated: hex(0x292C45),
                surfaceSelected: hex(0xE0E7FF, alpha: 0.10),
                borderSubtle: hex(0xC7D2FE, alpha: 0.11),
                borderStrong: hex(0xC7D2FE, alpha: 0.21),
                textPrimary: hex(0xEEF2FF),
                textSecondary: hex(0xB4BCE0),
                textMuted: hex(0x7B83A8),
                accent: hex(0xA78BFA),
                accentSoft: hex(0xA78BFA, alpha: 0.18),
                sendBg: hex(0xEEF2FF),
                sendFg: hex(0x161726),
                success: hex(0x4ADE80),
                warning: hex(0xFBBF24),
                danger: hex(0xFB7185)
            )
        case (.twilight, true):
            return KasugaiThemeTokens(
                isLight: true,
                sidebarBg: hex(0xEEEDF7),
                canvasBg: hex(0xF8F7FC),
                surfaceBg: hex(0xFFFFFF),
                surfaceElevated: hex(0xE3E0F3),
                surfaceSelected: hex(0x312E81, alpha: 0.08),
                borderSubtle: hex(0x312E81, alpha: 0.09),
                borderStrong: hex(0x312E81, alpha: 0.18),
                textPrimary: hex(0x1E1B4B),
                textSecondary: hex(0x4C497A),
                textMuted: hex(0x726F99),
                accent: hex(0x7C3AED),
                accentSoft: hex(0x7C3AED, alpha: 0.12),
                sendBg: hex(0x1E1B4B),
                sendFg: hex(0xFFFFFF),
                success: hex(0x16A34A),
                warning: hex(0xD97706),
                danger: hex(0xE11D48)
            )
        case (.highContrast, false):
            return KasugaiThemeTokens(
                isLight: false,
                sidebarBg: hex(0x000000),
                canvasBg: hex(0x000000),
                surfaceBg: hex(0x0E0E10),
                surfaceElevated: hex(0x1C1C21),
                surfaceSelected: hex(0xFFFFFF, alpha: 0.18),
                borderSubtle: hex(0xFFFFFF, alpha: 0.28),
                borderStrong: hex(0xFFFFFF, alpha: 0.52),
                textPrimary: hex(0xFFFFFF),
                textSecondary: hex(0xE5E7EB),
                textMuted: hex(0xCBD5E1),
                accent: hex(0x7CC4FF),
                accentSoft: hex(0x7CC4FF, alpha: 0.24),
                sendBg: hex(0xFFFFFF),
                sendFg: hex(0x000000),
                success: hex(0x5EEAD4),
                warning: hex(0xFDE047),
                danger: hex(0xFDA4AF)
            )
        case (.highContrast, true):
            return KasugaiThemeTokens(
                isLight: true,
                sidebarBg: hex(0xF5F5F5),
                canvasBg: hex(0xFFFFFF),
                surfaceBg: hex(0xFFFFFF),
                surfaceElevated: hex(0xE5E5E5),
                surfaceSelected: hex(0x000000, alpha: 0.12),
                borderSubtle: hex(0x000000, alpha: 0.28),
                borderStrong: hex(0x000000, alpha: 0.55),
                textPrimary: hex(0x000000),
                textSecondary: hex(0x1F2937),
                textMuted: hex(0x374151),
                accent: hex(0x0044AA),
                accentSoft: hex(0x0044AA, alpha: 0.16),
                sendBg: hex(0x000000),
                sendFg: hex(0xFFFFFF),
                success: hex(0x047857),
                warning: hex(0xB45309),
                danger: hex(0xB91C1C)
            )
        case (.kasugai, false):
            return KasugaiThemeTokens(
                isLight: false,
                sidebarBg: hex(0x0E0F12),
                canvasBg: hex(0x141519),
                surfaceBg: hex(0x1C1D22),
                surfaceElevated: hex(0x262830),
                surfaceSelected: hex(0xFFFFFF, alpha: 0.08),
                borderSubtle: hex(0xFFFFFF, alpha: 0.08),
                borderStrong: hex(0xFFFFFF, alpha: 0.15),
                textPrimary: hex(0xECEEF2),
                textSecondary: hex(0x9CA3AF),
                textMuted: hex(0x6B7280),
                accent: hex(0x60A5FA),
                accentSoft: hex(0x60A5FA, alpha: 0.16),
                sendBg: hex(0xECEEF2),
                sendFg: hex(0x111215),
                success: hex(0x4ADE80),
                warning: hex(0xFBBF24),
                danger: hex(0xF87171)
            )
        case (.kasugai, true):
            return KasugaiThemeTokens(
                isLight: true,
                sidebarBg: hex(0xF4F5F7),
                canvasBg: hex(0xFFFFFF),
                surfaceBg: hex(0xF7F8FA),
                surfaceElevated: hex(0xEBEDF1),
                surfaceSelected: hex(0x000000, alpha: 0.06),
                borderSubtle: hex(0x000000, alpha: 0.08),
                borderStrong: hex(0x000000, alpha: 0.15),
                textPrimary: hex(0x111318),
                textSecondary: hex(0x4B5563),
                textMuted: hex(0x6B7280),
                accent: hex(0x2563EB),
                accentSoft: hex(0x2563EB, alpha: 0.12),
                sendBg: hex(0x111318),
                sendFg: hex(0xFFFFFF),
                success: hex(0x16A34A),
                warning: hex(0xD97706),
                danger: hex(0xDC2626)
            )
        }
    }

    static func hex(_ rgb: UInt32, alpha: CGFloat = 1.0) -> NSColor {
        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgb & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}

final class KasugaiSurfaceView: NSView {
    var onAppearanceChanged: (() -> Void)?
    var fillColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }
    var strokeColor: NSColor = .clear {
        didSet { needsDisplay = true }
    }
    var strokeWidth: CGFloat = 0 {
        didSet { needsDisplay = true }
    }
    var cornerRadius: CGFloat = 0 {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChanged?()
        needsDisplay = true
    }

    override func updateLayer() {
        layer?.backgroundColor = fillColor.cgColor
        layer?.borderColor = strokeColor.cgColor
        layer?.borderWidth = strokeWidth
        layer?.cornerRadius = cornerRadius
    }

    override var wantsUpdateLayer: Bool {
        true
    }
}

enum KasugaiChromeMetrics {
    static let headerHeight: CGFloat = 30
    static let headerBarHeight: CGFloat = 28
    static let trafficLightLeadingInset: CGFloat = 78
}

enum KasugaiSlideDirection: String {
    case fromBottom = "from_bottom"
    case fromTop = "from_top"
    case fromLeft = "from_left"
    case fromRight = "from_right"
}

enum KasugaiInteractiveMotion {
    static weak var activeModalBackdrop: NSView?

    static func isInteractionBlocked(for view: NSView) -> Bool {
        guard let backdrop = activeModalBackdrop,
            !backdrop.isHidden,
            backdrop.superview != nil
        else {
            return false
        }
        return !view.isDescendant(of: backdrop)
    }

    static var shouldAnimate: Bool {
        if ProcessInfo.processInfo.environment["KASUGAI_SELF_TEST"] == "1" {
            return false
        }
        if CommandLine.arguments.dropFirst().first == "ui-snapshot" {
            return false
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            return false
        }
        return true
    }

    static var easeOutTiming: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.22, 1.0, 0.36, 1.0)
    }

    static var easeInTiming: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.32, 0.0, 0.67, 1.0)
    }

    static func clampedOriginOffset(
        from origin: NSPoint?,
        to targetFrame: NSRect,
        maxX: CGFloat = 132,
        maxY: CGFloat = 92
    ) -> CGPoint {
        guard let origin, targetFrame.width > 0, targetFrame.height > 0 else {
            return CGPoint(x: 0, y: -26)
        }
        let rawX = origin.x - targetFrame.midX
        let rawY = origin.y - targetFrame.midY
        let scaleX = abs(rawX) > maxX ? maxX / abs(rawX) : 1.0
        let scaleY = abs(rawY) > maxY ? maxY / abs(rawY) : 1.0
        let ratio = min(1.0, min(scaleX, scaleY))
        return CGPoint(x: rawX * ratio, y: rawY * ratio)
    }

    static func centeredTransform(
        for bounds: NSRect,
        dx: CGFloat,
        dy: CGFloat,
        scale: CGFloat
    ) -> CATransform3D {
        guard bounds.width > 0, bounds.height > 0 else {
            return CATransform3DMakeTranslation(dx, dy, 0)
        }
        let cx = bounds.midX
        let cy = bounds.midY
        var t = CATransform3DMakeTranslation(cx + dx, cy + dy, 0)
        t = CATransform3DScale(t, scale, scale, 1)
        t = CATransform3DTranslate(t, -cx, -cy, 0)
        return t
    }

    static func translationVector(
        for direction: KasugaiSlideDirection,
        distance: CGFloat,
        isFlipped: Bool
    ) -> CGPoint {
        let yDown: CGFloat = isFlipped ? 1 : -1
        switch direction {
        case .fromBottom:
            return CGPoint(x: 0, y: distance * yDown)
        case .fromTop:
            return CGPoint(x: 0, y: -distance * yDown)
        case .fromLeft:
            return CGPoint(x: -distance, y: 0)
        case .fromRight:
            return CGPoint(x: distance, y: 0)
        }
    }

    static func applyScale(to view: NSView, scale: CGFloat, animated: Bool = true) {
        view.wantsLayer = true
        guard let layer = view.layer else {
            return
        }
        let bounds = view.bounds
        let target: CATransform3D
        if abs(scale - 1.0) < 0.001 || bounds.width <= 0 || bounds.height <= 0 {
            target = CATransform3DIdentity
        } else {
            target = centeredTransform(for: bounds, dx: 0, dy: 0, scale: scale)
        }
        if animated && shouldAnimate {
            let anim = CASpringAnimation(keyPath: "transform")
            anim.fromValue = layer.presentation()?.transform ?? layer.transform
            anim.toValue = target
            anim.mass = 0.65
            anim.stiffness = 440
            anim.damping = 23
            anim.duration = anim.settlingDuration
            layer.add(anim, forKey: "kasugai.hoverScale")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = target
        CATransaction.commit()
    }

    static func animateModalPresent(
        backdrop: NSView,
        card: NSView,
        fromOriginInBackdrop origin: NSPoint?
    ) {
        backdrop.wantsLayer = true
        card.wantsLayer = true
        backdrop.layer?.removeAnimation(forKey: "kasugai.modalBackdrop")
        card.layer?.removeAnimation(forKey: "kasugai.modalTransform")
        card.layer?.removeAnimation(forKey: "kasugai.modalOpacity")

        guard shouldAnimate, let backdropLayer = backdrop.layer, let cardLayer = card.layer else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            backdrop.layer?.opacity = 1
            card.layer?.opacity = 1
            card.layer?.transform = CATransform3DIdentity
            CATransaction.commit()
            return
        }

        backdrop.layoutSubtreeIfNeeded()
        let offset = clampedOriginOffset(from: origin, to: card.frame)
        let startTransform = centeredTransform(
            for: card.bounds,
            dx: offset.x,
            dy: offset.y,
            scale: 0.90
        )

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdropLayer.opacity = 1
        cardLayer.opacity = 1
        cardLayer.transform = CATransform3DIdentity
        CATransaction.commit()

        let fadeBackdrop = CABasicAnimation(keyPath: "opacity")
        fadeBackdrop.fromValue = 0.0
        fadeBackdrop.toValue = 1.0
        fadeBackdrop.duration = 0.20
        fadeBackdrop.timingFunction = easeOutTiming
        backdropLayer.add(fadeBackdrop, forKey: "kasugai.modalBackdrop")

        let fadeCard = CABasicAnimation(keyPath: "opacity")
        fadeCard.fromValue = 0.0
        fadeCard.toValue = 1.0
        fadeCard.duration = 0.16
        fadeCard.timingFunction = easeOutTiming
        cardLayer.add(fadeCard, forKey: "kasugai.modalOpacity")

        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = startTransform
        spring.toValue = CATransform3DIdentity
        spring.mass = 0.72
        spring.stiffness = 380
        spring.damping = 28
        spring.duration = min(0.28, spring.settlingDuration)
        cardLayer.add(spring, forKey: "kasugai.modalTransform")
    }

    static func animateModalDismiss(
        backdrop: NSView,
        card: NSView,
        toOriginInBackdrop origin: NSPoint?,
        completion: @escaping () -> Void
    ) {
        backdrop.wantsLayer = true
        card.wantsLayer = true
        guard shouldAnimate, let backdropLayer = backdrop.layer, let cardLayer = card.layer else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            backdrop.layer?.opacity = 1
            card.layer?.opacity = 1
            card.layer?.transform = CATransform3DIdentity
            CATransaction.commit()
            completion()
            return
        }

        let offset = clampedOriginOffset(from: origin, to: card.frame, maxX: 112, maxY: 78)
        let endTransform = centeredTransform(
            for: card.bounds,
            dx: offset.x,
            dy: offset.y,
            scale: 0.91
        )
        let currentBackdropOpacity = backdropLayer.presentation()?.opacity ?? backdropLayer.opacity
        let currentCardOpacity = cardLayer.presentation()?.opacity ?? cardLayer.opacity
        let currentCardTransform = cardLayer.presentation()?.transform ?? cardLayer.transform

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            completion()
        }

        let fadeBackdrop = CABasicAnimation(keyPath: "opacity")
        fadeBackdrop.fromValue = currentBackdropOpacity
        fadeBackdrop.toValue = 0.0
        fadeBackdrop.duration = 0.16
        fadeBackdrop.timingFunction = easeInTiming
        backdropLayer.opacity = 0
        backdropLayer.add(fadeBackdrop, forKey: "kasugai.modalBackdrop")

        let fadeCard = CABasicAnimation(keyPath: "opacity")
        fadeCard.fromValue = currentCardOpacity
        fadeCard.toValue = 0.0
        fadeCard.duration = 0.14
        fadeCard.timingFunction = easeInTiming
        cardLayer.opacity = 0
        cardLayer.add(fadeCard, forKey: "kasugai.modalOpacity")

        let moveCard = CABasicAnimation(keyPath: "transform")
        moveCard.fromValue = currentCardTransform
        moveCard.toValue = endTransform
        moveCard.duration = 0.16
        moveCard.timingFunction = easeInTiming
        cardLayer.transform = endTransform
        cardLayer.add(moveCard, forKey: "kasugai.modalTransform")

        CATransaction.commit()
    }

    static func animateDirectionalEnter(
        view: NSView,
        direction: KasugaiSlideDirection,
        distance: CGFloat = 14,
        duration: CFTimeInterval = 0.20
    ) {
        view.wantsLayer = true
        guard let layer = view.layer else {
            return
        }
        layer.removeAnimation(forKey: "kasugai.directionalSlide")
        layer.removeAnimation(forKey: "kasugai.directionalFade")
        guard shouldAnimate else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.opacity = 1
            layer.transform = CATransform3DIdentity
            CATransaction.commit()
            return
        }

        let vec = translationVector(for: direction, distance: distance, isFlipped: view.isFlipped)
        let startTransform = CATransform3DMakeTranslation(vec.x, vec.y, 0)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 1
        layer.transform = CATransform3DIdentity
        CATransaction.commit()

        let slide = CABasicAnimation(keyPath: "transform")
        slide.fromValue = startTransform
        slide.toValue = CATransform3DIdentity
        slide.duration = duration
        slide.timingFunction = easeOutTiming
        layer.add(slide, forKey: "kasugai.directionalSlide")

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.0
        fade.toValue = 1.0
        fade.duration = duration * 0.85
        fade.timingFunction = easeOutTiming
        layer.add(fade, forKey: "kasugai.directionalFade")
    }

    static func animateDirectionalExit(
        view: NSView,
        to direction: KasugaiSlideDirection,
        distance: CGFloat = 10,
        duration: CFTimeInterval = 0.14,
        completion: @escaping () -> Void
    ) {
        view.wantsLayer = true
        guard shouldAnimate, let layer = view.layer else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            view.layer?.opacity = 1
            view.layer?.transform = CATransform3DIdentity
            CATransaction.commit()
            completion()
            return
        }

        let vec = translationVector(for: direction, distance: distance, isFlipped: view.isFlipped)
        let endTransform = CATransform3DMakeTranslation(vec.x, vec.y, 0)
        let currentOpacity = layer.presentation()?.opacity ?? layer.opacity
        let currentTransform = layer.presentation()?.transform ?? layer.transform

        CATransaction.begin()
        CATransaction.setCompletionBlock {
            completion()
        }

        let slide = CABasicAnimation(keyPath: "transform")
        slide.fromValue = currentTransform
        slide.toValue = endTransform
        slide.duration = duration
        slide.timingFunction = easeInTiming
        layer.transform = endTransform
        layer.add(slide, forKey: "kasugai.directionalSlide")

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = currentOpacity
        fade.toValue = 0.0
        fade.duration = duration
        fade.timingFunction = easeInTiming
        layer.opacity = 0
        layer.add(fade, forKey: "kasugai.directionalFade")

        CATransaction.commit()
    }

    static func animateDirectionalSwap(
        view: NSView,
        direction: KasugaiSlideDirection,
        distance: CGFloat = 8,
        applyChange: @escaping () -> Void
    ) {
        guard shouldAnimate else {
            applyChange()
            return
        }
        let exitDir: KasugaiSlideDirection
        switch direction {
        case .fromBottom:
            exitDir = .fromTop
        case .fromTop:
            exitDir = .fromBottom
        case .fromLeft:
            exitDir = .fromLeft
        case .fromRight:
            exitDir = .fromRight
        }
        animateDirectionalExit(view: view, to: exitDir, distance: distance, duration: 0.08) {
            applyChange()
            animateDirectionalEnter(
                view: view, direction: direction, distance: distance, duration: 0.15)
        }
    }

    static func animateSplitCollapse(
        _ item: NSSplitViewItem,
        collapsed: Bool,
        duration: TimeInterval = 0.22,
        completion: (() -> Void)? = nil
    ) {
        guard shouldAnimate else {
            item.isCollapsed = collapsed
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup(
            { ctx in
                ctx.duration = duration
                ctx.timingFunction = easeOutTiming
                item.animator().isCollapsed = collapsed
            },
            completionHandler: {
                completion?()
            }
        )
    }
}

final class KasugaiFlatButton: NSButton {
    enum Style {
        case ghost
        case pill
        case subtleFilled
        case circlePrimary
        case circleDanger
    }

    var buttonStyle: Style = .ghost {
        didSet { applyColors() }
    }
    var isSelectedPill: Bool = false {
        didSet { applyColors() }
    }
    var horizontalPadding: CGFloat = 8 {
        didSet { invalidateIntrinsicContentSize() }
    }
    var fixedDiameter: CGFloat? {
        didSet { invalidateIntrinsicContentSize() }
    }
    var customHeight: CGFloat? {
        didSet { invalidateIntrinsicContentSize() }
    }
    var customTintColor: NSColor? {
        didSet { applyColors() }
    }

    private var theme: KasugaiThemeTokens = KasugaiThemeTokens.resolve(
        palette: .kasugai, isLight: false)
    private var isHovered = false
    private var trackingAreaRef: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        wantsLayer = true
        focusRingType = .none
        font = .systemFont(ofSize: 12, weight: .medium)
        imagePosition = .imageLeading
        imageHugsTitle = true
        applyColors()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        if let fixedDiameter {
            return NSSize(width: fixedDiameter, height: fixedDiameter)
        }
        let base = super.intrinsicContentSize
        let h: CGFloat = customHeight ?? (buttonStyle == .pill ? 26 : 28)
        return NSSize(width: ceil(base.width) + horizontalPadding * 2, height: max(h, base.height))
    }

    func configureSymbol(
        _ name: String,
        title: String = "",
        pointSize: CGFloat = 12,
        weight: NSFont.Weight = .medium,
        position: NSControl.ImagePosition = .imageLeading
    ) {
        let cfg = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        image = NSImage(systemSymbolName: name, accessibilityDescription: title)?
            .withSymbolConfiguration(cfg)
        self.title = title
        imagePosition = title.isEmpty ? .imageOnly : position
        applyColors()
        invalidateIntrinsicContentSize()
    }

    func apply(theme: KasugaiThemeTokens) {
        self.theme = theme
        applyColors()
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

    private var hoverScale: CGFloat {
        bounds.width <= 52 ? 1.06 : 1.025
    }

    override func resetCursorRects() {
        if isEnabled && !KasugaiInteractiveMotion.isInteractionBlocked(for: self) {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard !KasugaiInteractiveMotion.isInteractionBlocked(for: self) else {
            return
        }
        isHovered = true
        applyColors()
        if isEnabled {
            KasugaiInteractiveMotion.applyScale(to: self, scale: hoverScale)
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        applyColors()
        KasugaiInteractiveMotion.applyScale(to: self, scale: 1.0)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled && !KasugaiInteractiveMotion.isInteractionBlocked(for: self) else {
            return
        }
        KasugaiInteractiveMotion.applyScale(to: self, scale: 0.94)
        super.mouseDown(with: event)
        KasugaiInteractiveMotion.applyScale(to: self, scale: isHovered ? hoverScale : 1.0)
    }

    override func layout() {
        super.layout()
        if let fixedDiameter {
            layer?.cornerRadius = fixedDiameter / 2.0
        } else if buttonStyle == .pill {
            layer?.cornerRadius = 7
        } else {
            layer?.cornerRadius = 7
        }
        if !isHovered {
            KasugaiInteractiveMotion.applyScale(to: self, scale: 1.0, animated: false)
        }
    }

    private func applyColors() {
        let fg: NSColor
        let bg: NSColor
        var borderColor: NSColor = .clear
        var borderW: CGFloat = 0

        switch buttonStyle {
        case .ghost:
            fg = (isSelectedPill || isHovered) ? theme.textPrimary : theme.textSecondary
            bg =
                isSelectedPill
                ? theme.surfaceSelected : (isHovered ? theme.surfaceSelected : .clear)
        case .pill:
            fg = (isSelectedPill || isHovered) ? theme.textPrimary : theme.textSecondary
            bg = isHovered ? theme.surfaceElevated : theme.surfaceBg
            borderColor = isHovered ? theme.borderStrong : theme.borderSubtle
            borderW = 1
        case .subtleFilled:
            fg = theme.textPrimary
            bg = isHovered ? theme.surfaceElevated : theme.surfaceSelected
        case .circlePrimary:
            fg = theme.sendFg
            bg = isHovered ? theme.sendBg.withAlphaComponent(0.88) : theme.sendBg
        case .circleDanger:
            fg = .white
            bg = isHovered ? theme.danger.withAlphaComponent(0.88) : theme.danger
        }

        layer?.backgroundColor = bg.cgColor
        layer?.borderColor = borderColor.cgColor
        layer?.borderWidth = borderW
        contentTintColor = customTintColor ?? fg

        if !title.isEmpty {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byTruncatingTail
            attributedTitle = NSAttributedString(
                string: title,
                attributes: [
                    .font: font ?? NSFont.systemFont(ofSize: 12, weight: .medium),
                    .foregroundColor: fg,
                    .paragraphStyle: paragraph,
                ]
            )
        }
    }
}

final class KasugaiSegmentedPill: NSView {
    var onSelectionChanged: ((Int) -> Void)?
    private(set) var selectedIndex: Int = 0

    private let container = KasugaiSurfaceView()
    private let stack = NSStackView()
    private var buttons: [KasugaiFlatButton] = []
    private var theme = KasugaiThemeTokens.resolve(palette: .kasugai, isLight: false)

    init(items: [(title: String, symbol: String, toolTip: String)]) {
        super.init(frame: .zero)
        wantsLayer = true
        container.cornerRadius = 8
        container.strokeWidth = 1
        container.translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        for (index, item) in items.enumerated() {
            let btn = KasugaiFlatButton()
            btn.tag = index
            btn.buttonStyle = .ghost
            btn.horizontalPadding = item.title.isEmpty ? 7 : 8
            btn.font = .systemFont(ofSize: 11.5, weight: .medium)
            btn.configureSymbol(
                item.symbol,
                title: item.title,
                pointSize: item.title.isEmpty ? 12.5 : 11,
                weight: .medium
            )
            btn.toolTip = item.toolTip.isEmpty ? item.title : item.toolTip
            btn.target = self
            btn.action = #selector(handleTap(_:))
            buttons.append(btn)
            stack.addArrangedSubview(btn)
        }

        container.addSubview(stack)
        addSubview(container)
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor),
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.heightAnchor.constraint(equalToConstant: 28),

            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -2),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
        ])
        syncSelection()
    }

    convenience init(items: [(title: String, symbol: String)]) {
        self.init(items: items.map { ($0.title, $0.symbol, $0.title) })
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setSelectedIndex(_ index: Int) {
        guard index >= 0, index < buttons.count else {
            return
        }
        selectedIndex = index
        syncSelection()
    }

    func apply(theme: KasugaiThemeTokens) {
        self.theme = theme
        container.fillColor = theme.surfaceBg
        container.strokeColor = theme.borderSubtle
        syncSelection()
    }

    private func syncSelection() {
        for (idx, btn) in buttons.enumerated() {
            btn.isSelectedPill = idx == selectedIndex
            btn.apply(theme: theme)
        }
    }

    @objc private func handleTap(_ sender: NSButton) {
        let next = sender.tag
        guard next != selectedIndex else {
            return
        }
        selectedIndex = next
        syncSelection()
        onSelectionChanged?(next)
    }
}

final class KasugaiModalBackdropView: NSView {
    weak var modalCardView: NSView?
    var onBackdropClick: (() -> Void)?
    var onAppearanceChanged: (() -> Void)?

    private let blurView = NSVisualEffectView()
    private let scrimView = KasugaiSurfaceView()
    private var trackingAreaRef: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        blurView.blendingMode = .withinWindow
        blurView.state = .active
        blurView.material = .hudWindow
        blurView.translatesAutoresizingMaskIntoConstraints = false

        scrimView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(blurView)
        addSubview(scrimView)
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            scrimView.topAnchor.constraint(equalTo: topAnchor),
            scrimView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrimView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrimView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    func apply(theme: KasugaiThemeTokens) {
        blurView.material = theme.isLight ? .popover : .hudWindow
        blurView.state = .active
        scrimView.fillColor = NSColor.black.withAlphaComponent(theme.isLight ? 0.14 : 0.34)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChanged?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.01 else {
            return nil
        }
        let local = convert(point, from: superview)
        guard bounds.contains(local) else {
            return nil
        }
        if let card = modalCardView, !card.isHidden, let hit = card.hitTest(local) {
            return hit
        }
        return self
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [
                .mouseEnteredAndExited,
                .mouseMoved,
                .cursorUpdate,
                .activeInKeyWindow,
                .inVisibleRect,
            ],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    override func cursorUpdate(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if let card = modalCardView, card.frame.contains(local) {
            return
        }
        NSCursor.arrow.set()
    }

    override func mouseMoved(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if let card = modalCardView, card.frame.contains(local) {
            return
        }
        NSCursor.arrow.set()
    }

    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if let card = modalCardView, card.frame.contains(local) {
            return
        }
        onBackdropClick?()
    }

    override func mouseUp(with event: NSEvent) {}

    override func mouseDragged(with event: NSEvent) {}

    override func rightMouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if let card = modalCardView, card.frame.contains(local) {
            return
        }
        onBackdropClick?()
    }

    override func rightMouseUp(with event: NSEvent) {}

    override func otherMouseDown(with event: NSEvent) {}

    override func otherMouseUp(with event: NSEvent) {}

    override func scrollWheel(with event: NSEvent) {}

    override func magnify(with event: NSEvent) {}

    override func smartMagnify(with event: NSEvent) {}

    override func swipe(with event: NSEvent) {}

    override func menu(for event: NSEvent) -> NSMenu? {
        nil
    }
}

final class KasugaiSplitView: NSSplitView {
    var isInteractionBlocked: Bool = false

    var themedBackgroundColor: NSColor = NSColor(srgbRed: 0.08, green: 0.08, blue: 0.1, alpha: 1) {
        didSet { needsDisplay = true }
    }

    var themedDividerColor: NSColor = NSColor(white: 1.0, alpha: 0.08) {
        didSet { needsDisplay = true }
    }

    override var dividerThickness: CGFloat {
        1
    }

    override var dividerColor: NSColor {
        themedDividerColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if isInteractionBlocked {
            return nil
        }
        return super.hitTest(point)
    }

    override func resetCursorRects() {
        if isInteractionBlocked {
            return
        }
        super.resetCursorRects()
    }

    override func drawDivider(in rect: NSRect) {
        themedBackgroundColor.setFill()
        rect.fill()
        themedDividerColor.setFill()
        rect.fill(using: .sourceOver)
    }
}

enum KasugaiBrandIcons {
    private static let monogramHues: [UInt32] = [
        0x3B82F6,
        0x10B981,
        0x8B5CF6,
        0xF59E0B,
        0xEC4899,
        0x06B6D4,
        0x6366F1,
        0x14B8A6,
    ]

    static func projectBadge(name: String, statusColor: NSColor?, isLight: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            var hash: UInt32 = 5381
            for byte in name.utf8 {
                hash = ((hash &<< 5) &+ hash) &+ UInt32(byte)
            }
            let baseHex = monogramHues[Int(hash % UInt32(monogramHues.count))]
            let bgAlpha: CGFloat = isLight ? 0.16 : 0.24
            let fgColor = KasugaiThemeTokens.hex(baseHex, alpha: 1.0)
            let bgColor = KasugaiThemeTokens.hex(baseHex, alpha: bgAlpha)

            let badgeRect = NSRect(x: 1, y: 1, width: 16, height: 16)
            let path = NSBezierPath(roundedRect: badgeRect, xRadius: 4.5, yRadius: 4.5)
            bgColor.setFill()
            path.fill()
            fgColor.withAlphaComponent(isLight ? 0.35 : 0.45).setStroke()
            path.lineWidth = 0.8
            path.stroke()

            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let initial = String(trimmed.prefix(1)).uppercased()
            let glyph = initial.isEmpty ? "K" : initial
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9.5, weight: .bold),
                .foregroundColor: fgColor,
            ]
            let textSize = (glyph as NSString).size(withAttributes: attrs)
            let pt = NSPoint(
                x: badgeRect.midX - textSize.width / 2.0,
                y: badgeRect.midY - textSize.height / 2.0
            )
            (glyph as NSString).draw(at: pt, withAttributes: attrs)

            if let statusColor {
                let ring = NSRect(x: rect.maxX - 7.5, y: 0.5, width: 7, height: 7)
                (isLight ? NSColor.white : NSColor.black).setFill()
                NSBezierPath(ovalIn: ring).fill()
                let dot = ring.insetBy(dx: 1.2, dy: 1.2)
                statusColor.setFill()
                NSBezierPath(ovalIn: dot).fill()
            }
            return true
        }
        return image
    }

    static func providerIcon(for providerId: String, size iconSize: CGFloat = 12) -> NSImage {
        let size = NSSize(width: iconSize, height: iconSize)
        return NSImage(size: size, flipped: false) { rect in
            let scale = iconSize / 12.0
            let transform = NSAffineTransform()
            transform.scale(by: scale)
            transform.concat()
            let base = NSRect(x: 0, y: 0, width: 12, height: 12)
            let cx = base.midX
            let cy = base.midY
            switch providerId {
            case "claude_code":
                let color = KasugaiThemeTokens.hex(0xD97757)
                color.setStroke()
                color.setFill()
                let path = NSBezierPath()
                path.lineWidth = 1.35
                path.lineCapStyle = .round
                for i in 0..<8 {
                    let angle = CGFloat(i) * (.pi / 4.0)
                    let outer: CGFloat = i % 2 == 0 ? 4.8 : 3.8
                    path.move(to: NSPoint(x: cx, y: cy))
                    path.line(
                        to: NSPoint(x: cx + cos(angle) * outer, y: cy + sin(angle) * outer)
                    )
                }
                path.stroke()
            case "codex":
                let color = KasugaiThemeTokens.hex(0x10A37F)
                color.setStroke()
                let hex = NSBezierPath()
                hex.lineWidth = 1.3
                hex.lineJoinStyle = .round
                for i in 0..<6 {
                    let angle = CGFloat(i) * (.pi / 3.0) - .pi / 6.0
                    let pt = NSPoint(x: cx + cos(angle) * 4.5, y: cy + sin(angle) * 4.5)
                    if i == 0 {
                        hex.move(to: pt)
                    } else {
                        hex.line(to: pt)
                    }
                }
                hex.close()
                hex.stroke()
                let core = NSBezierPath(
                    ovalIn: NSRect(x: cx - 1.6, y: cy - 1.6, width: 3.2, height: 3.2)
                )
                color.setFill()
                core.fill()
            case "opencode_acp":
                let color = KasugaiThemeTokens.hex(0x38BDF8)
                color.setStroke()
                let box = NSBezierPath(
                    roundedRect: base.insetBy(dx: 1.0, dy: 1.4),
                    xRadius: 2.2,
                    yRadius: 2.2
                )
                box.lineWidth = 1.15
                box.stroke()
                let chevron = NSBezierPath()
                chevron.lineWidth = 1.25
                chevron.lineCapStyle = .round
                chevron.lineJoinStyle = .round
                chevron.move(to: NSPoint(x: 3.5, y: 7.8))
                chevron.line(to: NSPoint(x: 5.7, y: 6.0))
                chevron.line(to: NSPoint(x: 3.5, y: 4.2))
                chevron.move(to: NSPoint(x: 6.6, y: 4.4))
                chevron.line(to: NSPoint(x: 8.6, y: 4.4))
                chevron.stroke()
            case "antigravity_acp":
                let star = NSBezierPath()
                star.move(to: NSPoint(x: cx, y: base.maxY - 0.8))
                star.curve(
                    to: NSPoint(x: base.maxX - 0.8, y: cy),
                    controlPoint1: NSPoint(x: cx + 0.4, y: cy + 1.0),
                    controlPoint2: NSPoint(x: cx + 1.0, y: cy + 0.4)
                )
                star.curve(
                    to: NSPoint(x: cx, y: base.minY + 0.8),
                    controlPoint1: NSPoint(x: cx + 1.0, y: cy - 0.4),
                    controlPoint2: NSPoint(x: cx + 0.4, y: cy - 1.0)
                )
                star.curve(
                    to: NSPoint(x: base.minX + 0.8, y: cy),
                    controlPoint1: NSPoint(x: cx - 0.4, y: cy - 1.0),
                    controlPoint2: NSPoint(x: cx - 1.0, y: cy - 0.4)
                )
                star.curve(
                    to: NSPoint(x: cx, y: base.maxY - 0.8),
                    controlPoint1: NSPoint(x: cx - 1.0, y: cy + 0.4),
                    controlPoint2: NSPoint(x: cx - 0.4, y: cy + 1.0)
                )
                star.close()
                if let gradient = NSGradient(
                    starting: KasugaiThemeTokens.hex(0x60A5FA),
                    ending: KasugaiThemeTokens.hex(0x8B5CF6)
                ) {
                    gradient.draw(in: star, angle: -45)
                } else {
                    KasugaiThemeTokens.hex(0x8B5CF6).setFill()
                    star.fill()
                }
            default:
                let color = KasugaiThemeTokens.hex(0x9CA3AF)
                color.setFill()
                NSBezierPath(ovalIn: base.insetBy(dx: 3, dy: 3)).fill()
            }
            return true
        }
    }

    static func relativeTimeLabel(fromMillis ms: Int64, now: Date = Date()) -> String {
        guard ms > 0 else {
            return ""
        }
        let delta = max(0, Int(now.timeIntervalSince1970) - Int(ms / 1000))
        if delta < 60 {
            return "今"
        }
        if delta < 3600 {
            return "\(delta / 60) 分"
        }
        if delta < 86400 {
            return "\(delta / 3600) 時間"
        }
        if delta < 86400 * 7 {
            return "\(delta / 86400) 日"
        }
        let date = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        let comps = Calendar.current.dateComponents([.month, .day], from: date)
        if let m = comps.month, let d = comps.day {
            return "\(m)/\(d)"
        }
        return ""
    }
}
