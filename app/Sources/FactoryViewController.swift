import AppKit
import Foundation
import QuartzCore

private final class FactoryFlippedClipView: NSClipView {
    override var isFlipped: Bool {
        true
    }
}

private final class FactoryPromptTextView: NSTextView {
    var onSubmitShortcut: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) && (event.keyCode == 36 || event.keyCode == 76) {
            onSubmitShortcut?()
            return
        }
        super.keyDown(with: event)
    }
}

private final class FactoryWorkflowDiagramView: NSView {
    var onSelectChildRun: ((String) -> Void)?

    private var run: FactoryRunRecord?
    private var childRuns: [String: FactoryRunRecord] = [:]
    private var theme = KasugaiThemeTokens.resolve(palette: .kasugai, isLight: false)
    private let pulseLayer = CAShapeLayer()
    private let progressTrackLayer = CALayer()
    private let progressFillLayer = CALayer()
    private var lastPulseRect: CGRect = .zero
    private var lastPulseColor: CGColor?

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        pulseLayer.fillColor = NSColor.clear.cgColor
        pulseLayer.lineWidth = 2.0
        pulseLayer.opacity = 0
        layer?.addSublayer(pulseLayer)

        progressTrackLayer.cornerRadius = 1.5
        progressTrackLayer.masksToBounds = true
        progressTrackLayer.isHidden = true
        progressFillLayer.cornerRadius = 1.5
        progressTrackLayer.addSublayer(progressFillLayer)
        layer?.addSublayer(progressTrackLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func preferredHeight(for run: FactoryRunRecord) -> CGFloat {
        let loopCount = max(1, run.loops.count)
        let liveFooter: CGFloat = run.status == .running ? 24 : 0
        return 126 + CGFloat(loopCount) * 26 + liveFooter
    }

    func configure(
        run: FactoryRunRecord,
        childRuns: [String: FactoryRunRecord],
        theme: KasugaiThemeTokens
    ) {
        self.run = run
        self.childRuns = childRuns
        self.theme = theme
        needsDisplay = true
        updatePulseOverlay()
    }

    override func layout() {
        super.layout()
        updatePulseOverlay()
    }

    override func resetCursorRects() {
        guard let run, let children = run.childRunIds, !children.isEmpty else {
            return
        }
        let rects = stageRects(in: bounds, count: run.stages.count)
        for (idx, stage) in run.stages.enumerated() where idx < rects.count {
            if children[stage.id] != nil {
                addCursorRect(rects[idx], cursor: .pointingHand)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let run, let children = run.childRunIds, !children.isEmpty else {
            super.mouseDown(with: event)
            return
        }
        let local = convert(event.locationInWindow, from: nil)
        let rects = stageRects(in: bounds, count: run.stages.count)
        for (idx, stage) in run.stages.enumerated() where idx < rects.count {
            if rects[idx].contains(local), let childId = children[stage.id] {
                onSelectChildRun?(childId)
                return
            }
        }
        super.mouseDown(with: event)
    }

    private func stageRects(in rect: NSRect, count stageCount: Int) -> [NSRect] {
        guard stageCount > 0 else {
            return []
        }
        let padX: CGFloat = 14
        let topY: CGFloat = 24
        let nodeH: CGFloat = 78
        let arrowGap: CGFloat = max(14, min(28, rect.width * 0.036))
        let count = CGFloat(stageCount)
        let usableW = max(220, rect.width - padX * 2 - arrowGap * max(0, count - 1))
        let nodeW = floor(usableW / count)
        var result: [NSRect] = []
        for idx in 0..<stageCount {
            let x = padX + CGFloat(idx) * (nodeW + arrowGap)
            result.append(NSRect(x: x, y: topY, width: nodeW, height: nodeH))
        }
        return result
    }

    private func stageState(at idx: Int, for run: FactoryRunRecord) -> (
        done: Bool, active: Bool, failed: Bool
    ) {
        let currentIndex = run.stages.firstIndex(where: { $0.id == run.currentStageId }) ?? 0
        switch run.status {
        case .previewReady, .published, .discarded:
            return (true, false, false)
        case .failed:
            return (idx < currentIndex, false, idx == currentIndex)
        case .running:
            return (idx < currentIndex, idx == currentIndex, false)
        case .draft:
            return (false, false, false)
        }
    }

    private func updatePulseOverlay() {
        guard let run, run.status == .running else {
            pulseLayer.removeAllAnimations()
            pulseLayer.opacity = 0
            progressFillLayer.removeAllAnimations()
            progressTrackLayer.isHidden = true
            lastPulseRect = .zero
            return
        }
        guard let activeIdx = run.stages.firstIndex(where: { $0.id == run.currentStageId }) else {
            return
        }
        let rects = stageRects(in: bounds, count: run.stages.count)
        guard activeIdx < rects.count else {
            return
        }
        let nodeRect = rects[activeIdx]
        let target = nodeRect.insetBy(dx: -3, dy: -3)
        let path = CGPath(
            roundedRect: target,
            cornerWidth: 14,
            cornerHeight: 14,
            transform: nil
        )
        pulseLayer.path = path
        let color = theme.accent.cgColor
        pulseLayer.strokeColor = color

        let barInset: CGFloat = 10
        let barW = max(20, nodeRect.width - barInset * 2)
        let trackFrame = CGRect(
            x: nodeRect.minX + barInset,
            y: nodeRect.maxY - 7,
            width: barW,
            height: 3
        )
        progressTrackLayer.isHidden = false
        progressTrackLayer.frame = trackFrame
        progressTrackLayer.backgroundColor = theme.accent.withAlphaComponent(0.20).cgColor
        progressFillLayer.backgroundColor = color

        let fillW = max(18, barW * 0.42)
        progressFillLayer.frame = CGRect(x: 0, y: 0, width: fillW, height: 3)

        if lastPulseRect == target && lastPulseColor == color
            && pulseLayer.animation(forKey: "factoryPulse") != nil
        {
            return
        }
        lastPulseRect = target
        lastPulseColor = color
        pulseLayer.removeAllAnimations()
        progressFillLayer.removeAllAnimations()
        if KasugaiInteractiveMotion.shouldAnimate {
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = 0.85
            anim.toValue = 0.14
            anim.duration = 0.95
            anim.autoreverses = true
            anim.repeatCount = .infinity
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pulseLayer.opacity = 0.85
            pulseLayer.add(anim, forKey: "factoryPulse")

            let sweep = CABasicAnimation(keyPath: "position.x")
            sweep.fromValue = -fillW * 0.5
            sweep.toValue = barW + fillW * 0.5
            sweep.duration = 1.35
            sweep.repeatCount = .infinity
            sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            progressFillLayer.add(sweep, forKey: "factorySweep")
        } else {
            pulseLayer.opacity = 0.72
            progressFillLayer.frame = CGRect(x: barW * 0.24, y: 0, width: fillW, height: 3)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let run, !run.stages.isEmpty else {
            return
        }

        let bg = NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14)
        theme.surfaceBg.setFill()
        bg.fill()
        theme.borderSubtle.setStroke()
        bg.lineWidth = 1
        bg.stroke()

        let rects = stageRects(in: bounds, count: run.stages.count)
        guard rects.count == run.stages.count else {
            return
        }

        for idx in 0..<(rects.count - 1) {
            let left = rects[idx]
            let right = rects[idx + 1]
            let stLeft = stageState(at: idx, for: run)
            let stRight = stageState(at: idx + 1, for: run)
            let lit = stLeft.done || stRight.active || stRight.done
            let lineColor = lit ? theme.accent : theme.borderStrong
            let y = left.midY
            let x1 = left.maxX + 3
            let x2 = right.minX - 4
            drawHorizontalArrow(fromX: x1, toX: x2, y: y, color: lineColor, width: lit ? 2.0 : 1.3)
        }

        let activeLoopIds = Set(run.iterations.flatMap(\.activeLoopIds))
        let stuckHit = run.iterations.contains(where: \.stuckDetected)

        for (loopIdx, loop) in run.loops.enumerated() {
            guard
                let fromIdx = run.stages.firstIndex(where: { $0.id == loop.fromStageId }),
                let toIdx = run.stages.firstIndex(where: { $0.id == loop.toStageId }),
                fromIdx < rects.count,
                toIdx < rects.count
            else {
                continue
            }
            let isLit = activeLoopIds.contains(loop.id)
            let matchedIter = run.iterations.last { $0.activeLoopIds.contains(loop.id) }
            let bottomY = rects[0].maxY + 22 + CGFloat(loopIdx) * 26
            let targetOffset = CGFloat(run.loops.count - 1 - loopIdx * 2) * 12
            let color: NSColor
            if isLit && stuckHit {
                color = theme.danger
            } else if isLit {
                color = theme.warning
            } else {
                color = theme.borderStrong.withAlphaComponent(0.65)
            }
            let labelText: String
            if isLit, let note = matchedIter?.loopNote, !note.isEmpty {
                labelText = note
            } else if isLit {
                labelText = loop.activeLabel
            } else {
                labelText = loop.label
            }
            drawFeedbackLoop(
                fromX: rects[fromIdx].midX,
                fromY: rects[fromIdx].maxY + 3,
                toX: rects[toIdx].midX + targetOffset,
                toY: rects[toIdx].maxY + 4,
                bottomY: bottomY,
                color: color,
                dashed: !isLit,
                label: labelText
            )
        }

        for (idx, stage) in run.stages.enumerated() {
            drawNode(stage: stage, index: idx, rect: rects[idx], run: run)
        }

        if run.status == .running, let latest = run.logs.last, !latest.isEmpty {
            let y = bounds.maxY - 22
            let dotRect = NSRect(x: 16, y: y + 4, width: 6, height: 6)
            theme.accent.setFill()
            NSBezierPath(ovalIn: dotRect).fill()

            let para = NSMutableParagraphStyle()
            para.lineBreakMode = .byTruncatingTail
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular),
                .foregroundColor: theme.textSecondary,
                .paragraphStyle: para,
            ]
            NSAttributedString(string: latest, attributes: attrs).draw(
                in: NSRect(x: 28, y: y, width: max(40, bounds.width - 44), height: 15)
            )
        }
    }

    private func drawHorizontalArrow(
        fromX: CGFloat,
        toX: CGFloat,
        y: CGFloat,
        color: NSColor,
        width: CGFloat
    ) {
        guard toX > fromX + 4 else {
            return
        }
        let shaft = NSBezierPath()
        shaft.move(to: NSPoint(x: fromX, y: y))
        shaft.line(to: NSPoint(x: toX - 4, y: y))
        shaft.lineWidth = width
        shaft.lineCapStyle = .round
        color.setStroke()
        shaft.stroke()

        let head = NSBezierPath()
        head.move(to: NSPoint(x: toX, y: y))
        head.line(to: NSPoint(x: toX - 6, y: y - 4))
        head.line(to: NSPoint(x: toX - 6, y: y + 4))
        head.close()
        color.setFill()
        head.fill()
    }

    private func drawFeedbackLoop(
        fromX: CGFloat,
        fromY: CGFloat,
        toX: CGFloat,
        toY: CGFloat,
        bottomY: CGFloat,
        color: NSColor,
        dashed: Bool,
        label: String
    ) {
        let r: CGFloat = 10
        let dir: CGFloat = fromX >= toX ? -1 : 1
        let path = NSBezierPath()
        path.move(to: NSPoint(x: fromX, y: fromY))
        path.line(to: NSPoint(x: fromX, y: bottomY - r))
        path.curve(
            to: NSPoint(x: fromX + dir * r, y: bottomY),
            controlPoint1: NSPoint(x: fromX, y: bottomY),
            controlPoint2: NSPoint(x: fromX, y: bottomY)
        )
        path.line(to: NSPoint(x: toX - dir * r, y: bottomY))
        path.curve(
            to: NSPoint(x: toX, y: bottomY - r),
            controlPoint1: NSPoint(x: toX, y: bottomY),
            controlPoint2: NSPoint(x: toX, y: bottomY)
        )
        path.line(to: NSPoint(x: toX, y: toY + 4))
        path.lineWidth = dashed ? 1.2 : 1.8
        if dashed {
            let pattern: [CGFloat] = [4, 3]
            path.setLineDash(pattern, count: 2, phase: 0)
        }
        color.setStroke()
        path.stroke()

        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: toX, y: toY))
        arrow.line(to: NSPoint(x: toX - 4, y: toY + 6))
        arrow.line(to: NSPoint(x: toX + 4, y: toY + 6))
        arrow.close()
        color.setFill()
        arrow.fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: dashed ? .regular : .semibold),
            .foregroundColor: dashed ? theme.textMuted : color,
        ]
        let attrStr = NSAttributedString(string: label, attributes: attrs)
        let size = attrStr.size()
        let midX = (fromX + toX) * 0.5
        let pillRect = NSRect(
            x: midX - size.width * 0.5 - 7,
            y: bottomY - size.height * 0.5 - 2,
            width: size.width + 14,
            height: size.height + 4
        )
        let pill = NSBezierPath(roundedRect: pillRect, xRadius: 7, yRadius: 7)
        theme.surfaceBg.setFill()
        pill.fill()
        if !dashed {
            color.withAlphaComponent(0.35).setStroke()
            pill.lineWidth = 1
            pill.stroke()
        }
        attrStr.draw(at: NSPoint(x: pillRect.minX + 7, y: pillRect.minY + 2))
    }

    private func drawNode(
        stage: FactoryStageBlueprint,
        index: Int,
        rect: NSRect,
        run: FactoryRunRecord
    ) {
        let state = stageState(at: index, for: run)
        let accent: NSColor
        if state.failed {
            accent = theme.danger
        } else if state.done {
            accent = theme.success
        } else if state.active {
            accent = theme.accent
        } else {
            accent = theme.textMuted
        }

        let hasSubFactory = stage.subBlueprintId != nil
        let isGate = !hasSubFactory && run.loops.contains(where: { $0.fromStageId == stage.id })
        if hasSubFactory {
            let outerFrame = NSBezierPath(
                roundedRect: rect.insetBy(dx: -3.5, dy: -3.5), xRadius: 13.5, yRadius: 13.5)
            let dashColor =
                (state.active || state.done || state.failed)
                ? accent.withAlphaComponent(0.65)
                : theme.accent.withAlphaComponent(0.45)
            dashColor.setStroke()
            outerFrame.lineWidth = 1.25
            let pattern: [CGFloat] = [4, 3]
            outerFrame.setLineDash(pattern, count: 2, phase: 0)
            outerFrame.stroke()
        }

        let card = NSBezierPath(
            roundedRect: rect, xRadius: isGate ? 8 : 11, yRadius: isGate ? 8 : 11)
        let fill: NSColor
        if state.active {
            fill = accent.withAlphaComponent(theme.isLight ? 0.14 : 0.19)
        } else if state.done || state.failed {
            fill = accent.withAlphaComponent(theme.isLight ? 0.08 : 0.11)
        } else if hasSubFactory {
            fill = theme.accent.withAlphaComponent(theme.isLight ? 0.05 : 0.07)
        } else {
            fill = theme.canvasBg
        }
        fill.setFill()
        card.fill()

        let stroke: NSColor =
            (state.active || state.done || state.failed)
            ? accent.withAlphaComponent(state.active ? 0.85 : 0.52)
            : (hasSubFactory
                ? theme.accent.withAlphaComponent(0.40)
                : (isGate ? theme.warning.withAlphaComponent(0.45) : theme.borderSubtle))
        stroke.setStroke()
        card.lineWidth = state.active ? 1.8 : (isGate ? 1.4 : 1.0)
        card.stroke()

        if isGate {
            let gateColor: NSColor =
                (state.active || state.done || state.failed) ? accent : theme.warning
            let leftBarRect = NSRect(
                x: rect.minX + 1,
                y: rect.minY + 6,
                width: 3.5,
                height: rect.height - 12
            )
            let leftBar = NSBezierPath(roundedRect: leftBarRect, xRadius: 1.75, yRadius: 1.75)
            gateColor.withAlphaComponent(0.9).setFill()
            leftBar.fill()

            let gateIdx =
                run.loops.firstIndex(where: { $0.fromStageId == stage.id }).map { $0 + 1 } ?? 1
            let tagText = "GATE \(gateIdx)"
            let tagAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 8.5, weight: .bold),
                .foregroundColor: gateColor,
            ]
            let tagStr = NSAttributedString(string: tagText, attributes: tagAttrs)
            let tagSize = tagStr.size()
            let tagRect = NSRect(
                x: rect.minX + 10,
                y: rect.minY - tagSize.height * 0.5 - 2,
                width: tagSize.width + 10,
                height: tagSize.height + 4
            )
            let tagPill = NSBezierPath(roundedRect: tagRect, xRadius: 5, yRadius: 5)
            theme.surfaceBg.setFill()
            tagPill.fill()
            gateColor.withAlphaComponent(0.65).setStroke()
            tagPill.lineWidth = 1.0
            tagPill.stroke()
            tagStr.draw(at: NSPoint(x: tagRect.minX + 5, y: tagRect.minY + 2))
        }

        let symbolName: String
        if hasSubFactory {
            symbolName = "gearshape.2.fill"
        } else if state.done {
            symbolName = "checkmark.circle.fill"
        } else if state.failed {
            symbolName = "xmark.circle.fill"
        } else {
            symbolName = stage.symbol
        }

        let iconTint = (hasSubFactory && !state.done && !state.failed) ? theme.accent : accent
        let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        if let rawImg = NSImage(
            systemSymbolName: symbolName, accessibilityDescription: stage.title)?
            .withSymbolConfiguration(cfg)
        {
            let tinted = NSImage(size: rawImg.size, flipped: false) { r in
                rawImg.draw(in: r)
                iconTint.set()
                r.fill(using: .sourceAtop)
                return true
            }
            let iconRect = NSRect(x: rect.minX + 10, y: rect.minY + 10, width: 15, height: 15)
            tinted.draw(in: iconRect)
        }

        if state.active {
            let dot = NSBezierPath(
                ovalIn: NSRect(x: rect.maxX - 15, y: rect.minY + 12, width: 6, height: 6))
            theme.accent.setFill()
            dot.fill()
        }

        let titlePara = NSMutableParagraphStyle()
        titlePara.lineBreakMode = .byTruncatingTail
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11.5, weight: state.active ? .bold : .semibold),
            .foregroundColor: (state.active || state.done || state.failed || hasSubFactory)
                ? theme.textPrimary : theme.textSecondary,
            .paragraphStyle: titlePara,
        ]
        let titleStr = NSAttributedString(
            string: "\(index + 1). \(stage.title)", attributes: titleAttrs)
        titleStr.draw(
            in: NSRect(
                x: rect.minX + 28,
                y: rect.minY + 9,
                width: rect.width - (state.active ? 46 : 36),
                height: 17
            )
        )

        if hasSubFactory {
            drawSubFactoryMiniPipeline(in: rect, stage: stage, state: state, accent: accent)
            let hasChild = run.childRunIds?[stage.id] != nil
            let footLabel = hasChild ? (state.done ? "子工場 · 納品済み ↗" : "子工場を開く ↗") : "子工場（4 工程）"
            let footPara = NSMutableParagraphStyle()
            footPara.lineBreakMode = .byTruncatingTail
            let footAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9.5, weight: .semibold),
                .foregroundColor: hasChild
                    ? (state.done ? theme.success : theme.accent) : theme.textMuted,
                .paragraphStyle: footPara,
            ]
            NSAttributedString(string: footLabel, attributes: footAttrs).draw(
                in: NSRect(x: rect.minX + 10, y: rect.maxY - 19, width: rect.width - 20, height: 14)
            )
            return
        }

        let subtitle = nodeSubtitle(stage: stage, index: index, state: state, run: run)
        let subPara = NSMutableParagraphStyle()
        subPara.lineBreakMode = .byTruncatingTail
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: state.active ? .semibold : .regular),
            .foregroundColor: state.active ? accent : theme.textMuted,
            .paragraphStyle: subPara,
        ]
        let subStr = NSAttributedString(string: subtitle, attributes: subAttrs)
        subStr.draw(
            in: NSRect(x: rect.minX + 10, y: rect.minY + 34, width: rect.width - 20, height: 15)
        )

        let statusLine = nodeFootline(stage: stage, index: index, state: state, run: run)
        let footAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium),
            .foregroundColor: state.done
                ? theme.success : (state.failed ? theme.danger : theme.textMuted),
            .paragraphStyle: subPara,
        ]
        let footStr = NSAttributedString(string: statusLine, attributes: footAttrs)
        footStr.draw(
            in: NSRect(x: rect.minX + 10, y: rect.minY + 53, width: rect.width - 20, height: 14)
        )
    }

    private func drawSubFactoryMiniPipeline(
        in rect: NSRect,
        stage: FactoryStageBlueprint,
        state: (done: Bool, active: Bool, failed: Bool),
        accent: NSColor
    ) {
        let wellRect = NSRect(
            x: rect.minX + 9,
            y: rect.minY + 29,
            width: rect.width - 18,
            height: 26
        )
        let well = NSBezierPath(roundedRect: wellRect, xRadius: 6, yRadius: 6)
        theme.canvasBg.withAlphaComponent(0.75).setFill()
        well.fill()
        theme.borderSubtle.setStroke()
        well.lineWidth = 0.8
        well.stroke()

        let child = childRuns[stage.id]
        let subCount = max(3, min(4, child?.stages.count ?? 4))
        let childCurrentIdx: Int
        if let child {
            if child.status == .published || child.status == .previewReady {
                childCurrentIdx = subCount
            } else {
                childCurrentIdx =
                    child.stages.firstIndex(where: { $0.id == child.currentStageId }) ?? 0
            }
        } else if state.done {
            childCurrentIdx = subCount
        } else if state.active {
            childCurrentIdx = 1
        } else {
            childCurrentIdx = -1
        }

        let insetX: CGFloat = 10
        let spanW = max(24, wellRect.width - insetX * 2)
        let stepX = subCount > 1 ? spanW / CGFloat(subCount - 1) : 0
        let lineY = wellRect.minY + 9.5
        let dotR: CGFloat = 3.2

        for i in 0..<(subCount - 1) {
            let x1 = wellRect.minX + insetX + CGFloat(i) * stepX + dotR + 1
            let x2 = wellRect.minX + insetX + CGFloat(i + 1) * stepX - dotR - 1
            if x2 > x1 {
                let seg = NSBezierPath()
                seg.move(to: NSPoint(x: x1, y: lineY))
                seg.line(to: NSPoint(x: x2, y: lineY))
                seg.lineWidth = 1.2
                let segColor =
                    (i < childCurrentIdx) ? theme.success : theme.borderStrong
                segColor.setStroke()
                seg.stroke()
            }
        }

        let loopStartX = wellRect.minX + insetX + CGFloat(min(2, subCount - 1)) * stepX
        let loopEndX = wellRect.minX + insetX
        let loopY = wellRect.minY + 19.5
        let miniLoop = NSBezierPath()
        miniLoop.move(to: NSPoint(x: loopStartX, y: lineY + dotR + 1))
        miniLoop.line(to: NSPoint(x: loopStartX, y: loopY))
        miniLoop.line(to: NSPoint(x: loopEndX, y: loopY))
        miniLoop.line(to: NSPoint(x: loopEndX, y: lineY + dotR + 1))
        miniLoop.lineWidth = 1.0
        let loopColor =
            (child?.iterations.contains(where: { !$0.activeLoopIds.isEmpty }) == true)
            ? theme.warning
            : theme.borderStrong.withAlphaComponent(0.7)
        loopColor.setStroke()
        miniLoop.stroke()

        for i in 0..<subCount {
            let cx = wellRect.minX + insetX + CGFloat(i) * stepX
            let dotRect = NSRect(x: cx - dotR, y: lineY - dotR, width: dotR * 2, height: dotR * 2)
            let dot = NSBezierPath(ovalIn: dotRect)
            let dotColor: NSColor
            if state.failed && i == childCurrentIdx {
                dotColor = theme.danger
            } else if i < childCurrentIdx {
                dotColor = theme.success
            } else if i == childCurrentIdx {
                dotColor = accent
            } else {
                dotColor = theme.textMuted.withAlphaComponent(0.55)
            }
            dotColor.setFill()
            dot.fill()
        }
    }

    private func nodeSubtitle(
        stage: FactoryStageBlueprint,
        index: Int,
        state: (done: Bool, active: Bool, failed: Bool),
        run: FactoryRunRecord
    ) -> String {
        if stage.subBlueprintId != nil {
            if let childId = run.childRunIds?[stage.id], !childId.isEmpty {
                return state.active ? "子工場 稼働中…" : "クリックで子工場を開く"
            }
            return stage.subtitle
        }
        if index == 0 {
            let label = FactoryViewController.providerDisplayLabel(for: run.workerProvider)
            return state.active ? "\(label) が生成中…" : label
        }
        if stage.id == "review" {
            let label = FactoryViewController.providerDisplayLabel(for: run.criticProvider)
            return state.active ? "\(label) が隔離審査中…" : "\(label)（隔離）"
        }
        return state.active ? "\(stage.title)を実行中…" : stage.subtitle
    }

    private func nodeFootline(
        stage: FactoryStageBlueprint,
        index: Int,
        state: (done: Bool, active: Bool, failed: Bool),
        run: FactoryRunRecord
    ) -> String {
        let iterCount = max(1, run.iterations.count)
        let latest = run.iterations.last
        if state.active {
            return stage.subBlueprintId != nil ? "子工場 実行中" : "第 \(iterCount) 周 稼働中"
        }
        if state.failed {
            return "停止・エラー"
        }
        if index == 0 {
            return state.done ? "第 \(iterCount) 周 完了" : "待機"
        }
        if stage.subBlueprintId != nil {
            return state.done ? "納品完了" : "待機"
        }
        if stage.id == "verify" || stage.id == "audio_lint", let p0 = latest?.panels.first {
            return p0.statusText
        }
        if stage.id == "review", let p1 = latest?.panels.dropFirst().first {
            return p1.statusText
        }
        if index == run.stages.count - 1 {
            switch run.status {
            case .published:
                return "本番公開済み"
            case .previewReady:
                return "確認待ち"
            case .discarded:
                return "破棄済み"
            default:
                return "待機"
            }
        }
        return state.done ? "通過" : "待機"
    }
}

final class FactoryViewController: NSViewController, NSTextViewDelegate {
    var onToggleSidebar: (() -> Void)?
    var onToggleRightPane: (() -> Void)?
    var onToggleTerminal: (() -> Void)?
    var onStartRun:
        (
            (String, String, String, String, String, String, String, Int, Int, [String], Bool) ->
                Void
        )?
    var onStopRun: ((String) -> Void)?
    var onOpenLocalPreview: ((FactoryRunRecord) -> Void)?
    var onOpenExternalURL: ((String) -> Void)?
    var onPublishRun: ((String) -> Void)?
    var onDiscardRun: ((String) -> Void)?
    var onSelectThread: ((Int64) -> Void)?
    var onSelectRun: ((String) -> Void)?
    var onSaveBlueprint: ((FactoryBlueprint) -> Void)?
    var onDuplicateBlueprint: ((String, String) -> FactoryBlueprint?)?
    var onOpenBlueprintFile: ((String) -> Void)?

    private enum DetailTab {
        case iterations
        case tuning
        case logs
    }

    private let rootSurface = KasugaiSurfaceView()
    private let headerBar = NSStackView()
    private let headerDivider = KasugaiSurfaceView()
    private var headerLeadingConstraint: NSLayoutConstraint?
    private let sidebarButton = KasugaiFlatButton()
    private let headerIconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "工場")
    private let statusBadgeSurface = KasugaiSurfaceView()
    private let statusBadgeLabel = NSTextField(labelWithString: "")
    private let terminalButton = KasugaiFlatButton()
    private let rightPaneButton = KasugaiFlatButton()

    private let draftScrollView = NSScrollView()
    private let draftDocView = NSView()
    private let draftCard = KasugaiSurfaceView()
    private let draftHeadingLabel = NSTextField(labelWithString: "新規製造")
    private let blueprintPopup = NSPopUpButton()
    private let duplicateBlueprintButton = KasugaiFlatButton()
    private let openBlueprintButton = KasugaiFlatButton()
    private let draftSubLabel = NSTextField(wrappingLabelWithString: "")
    private let promptSurface = KasugaiSurfaceView()
    private let promptScrollView = NSScrollView()
    private let promptTextView = FactoryPromptTextView()
    private let promptPlaceholderLabel = NSTextField(wrappingLabelWithString: "")
    private let charCountLabel = NSTextField(labelWithString: "0 / 200 字")
    private let workerLabel = NSTextField(labelWithString: "実装")
    private let workerPopup = NSPopUpButton()
    private let workerModelPopup = NSPopUpButton()
    private let criticLabel = NSTextField(labelWithString: "独立レビュー")
    private let criticPopup = NSPopUpButton()
    private let criticModelPopup = NSPopUpButton()
    private let maxIterLabel = NSTextField(labelWithString: "最大周回数")
    private let maxIterPopup = NSPopUpButton()
    private let minScoreLabel = NSTextField(labelWithString: "合格点")
    private let minScorePopup = NSPopUpButton()
    private let rulesToggleButton = KasugaiFlatButton()
    private let rulesContainer = NSView()
    private let rulesSurface = KasugaiSurfaceView()
    private let rulesScrollView = NSScrollView()
    private let rulesTextView = NSTextView()
    private let saveRulesButton = KasugaiFlatButton()
    private let startButton = KasugaiFlatButton()
    private let demoButton = KasugaiFlatButton()

    private let pipelineScrollView = NSScrollView()
    private let pipelineDocumentView = NSView()
    private let pipelineStack = NSStackView()
    private let workflowDiagram = FactoryWorkflowDiagramView()
    private var workflowHeightConstraint: NSLayoutConstraint?

    static let providerChoices: [(id: String, label: String)] = [
        ("opencode_acp", "OpenCode"),
        ("codex", "Codex"),
        ("claude_code", "Claude"),
        ("antigravity_acp", "Antigravity"),
    ]

    static func providerDisplayLabel(for id: String) -> String {
        providerChoices.first(where: { $0.id == id })?.label ?? id
    }

    private var blueprints: [FactoryBlueprint] = FactoryBlueprint.builtInDefaults()
    private var selectedBlueprintId: String = "web-game"
    private var workerModelOptions: [KasugaiModelOption] = []
    private var criticModelOptions: [KasugaiModelOption] = []
    private var isDraftRulesExpanded = false

    private var currentRun: FactoryRunRecord?
    private var currentChildRuns: [String: FactoryRunRecord] = [:]
    private weak var liveElapsedLabel: NSTextField?
    private var elapsedTimer: Timer?

    deinit {
        elapsedTimer?.invalidate()
    }
    private var selectedIterationIndex: Int?
    private var selectedDetailTab: DetailTab = .iterations
    private var tuningRulesTextView: NSTextView?
    private var tuningScorePopup: NSPopUpButton?
    private var tuningIterPopup: NSPopUpButton?
    private var palette: KasugaiPalette = .kasugai
    private var theme: KasugaiThemeTokens = KasugaiThemeTokens.resolve(
        palette: .kasugai, isLight: false)
    private var leftSidebarCollapsed = false
    private var rightPaneOpen = false
    private var terminalPaneOpen = false

    override func loadView() {
        rootSurface.frame = NSRect(x: 0, y: 0, width: 760, height: 600)
        setupHeader()
        setupDraftView()
        setupPipelineView()

        rootSurface.addSubview(headerBar)
        rootSurface.addSubview(headerDivider)
        rootSurface.addSubview(draftScrollView)
        rootSurface.addSubview(pipelineScrollView)

        let leading = headerBar.leadingAnchor.constraint(
            equalTo: rootSurface.leadingAnchor,
            constant: leftSidebarCollapsed ? KasugaiChromeMetrics.trafficLightLeadingInset : 12
        )
        headerLeadingConstraint = leading

        NSLayoutConstraint.activate([
            headerBar.topAnchor.constraint(equalTo: rootSurface.topAnchor),
            leading,
            headerBar.trailingAnchor.constraint(equalTo: rootSurface.trailingAnchor, constant: -12),
            headerBar.heightAnchor.constraint(
                equalToConstant: KasugaiChromeMetrics.headerBarHeight),

            headerDivider.topAnchor.constraint(
                equalTo: rootSurface.topAnchor, constant: KasugaiChromeMetrics.headerHeight),
            headerDivider.leadingAnchor.constraint(equalTo: rootSurface.leadingAnchor),
            headerDivider.trailingAnchor.constraint(equalTo: rootSurface.trailingAnchor),
            headerDivider.heightAnchor.constraint(equalToConstant: 1),

            draftScrollView.topAnchor.constraint(equalTo: headerDivider.bottomAnchor),
            draftScrollView.leadingAnchor.constraint(equalTo: rootSurface.leadingAnchor),
            draftScrollView.trailingAnchor.constraint(equalTo: rootSurface.trailingAnchor),
            draftScrollView.bottomAnchor.constraint(equalTo: rootSurface.bottomAnchor),

            pipelineScrollView.topAnchor.constraint(equalTo: headerDivider.bottomAnchor),
            pipelineScrollView.leadingAnchor.constraint(equalTo: rootSurface.leadingAnchor),
            pipelineScrollView.trailingAnchor.constraint(equalTo: rootSurface.trailingAnchor),
            pipelineScrollView.bottomAnchor.constraint(equalTo: rootSurface.bottomAnchor),
        ])

        self.view = rootSurface
        rootSurface.onAppearanceChanged = { [weak self] in
            self?.applyTheme()
        }
        applyTheme()
    }

    private func setupHeader() {
        sidebarButton.buttonStyle = .ghost
        sidebarButton.customHeight = 22
        sidebarButton.horizontalPadding = 5
        sidebarButton.configureSymbol("sidebar.left", pointSize: 12.5, weight: .medium)
        sidebarButton.toolTip = "左サイドバーを切り替え"
        sidebarButton.target = self
        sidebarButton.action = #selector(handleToggleSidebar)

        headerIconView.imageScaling = .scaleProportionallyDown
        headerIconView.translatesAutoresizingMaskIntoConstraints = false
        let iconCfg = NSImage.SymbolConfiguration(pointSize: 12.5, weight: .semibold)
        headerIconView.image = NSImage(
            systemSymbolName: "gearshape.2",
            accessibilityDescription: "工場"
        )?.withSymbolConfiguration(iconCfg)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        statusBadgeSurface.cornerRadius = 9
        statusBadgeSurface.strokeWidth = 1
        statusBadgeSurface.translatesAutoresizingMaskIntoConstraints = false
        statusBadgeLabel.font = .systemFont(ofSize: 10.5, weight: .semibold)
        statusBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        statusBadgeSurface.addSubview(statusBadgeLabel)
        NSLayoutConstraint.activate([
            headerIconView.widthAnchor.constraint(equalToConstant: 15),
            headerIconView.heightAnchor.constraint(equalToConstant: 15),
            statusBadgeLabel.topAnchor.constraint(
                equalTo: statusBadgeSurface.topAnchor, constant: 2),
            statusBadgeLabel.bottomAnchor.constraint(
                equalTo: statusBadgeSurface.bottomAnchor, constant: -2),
            statusBadgeLabel.leadingAnchor.constraint(
                equalTo: statusBadgeSurface.leadingAnchor, constant: 7),
            statusBadgeLabel.trailingAnchor.constraint(
                equalTo: statusBadgeSurface.trailingAnchor, constant: -7),
        ])

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        terminalButton.buttonStyle = .ghost
        terminalButton.customHeight = 22
        terminalButton.horizontalPadding = 5
        terminalButton.configureSymbol("terminal", pointSize: 12, weight: .medium)
        terminalButton.toolTip = "ターミナルを切り替え（⌘J）"
        terminalButton.target = self
        terminalButton.action = #selector(handleToggleTerminal)

        rightPaneButton.buttonStyle = .ghost
        rightPaneButton.customHeight = 22
        rightPaneButton.horizontalPadding = 5
        rightPaneButton.configureSymbol("sidebar.right", pointSize: 12.5, weight: .medium)
        rightPaneButton.toolTip = "右ペインを切り替え（⌘D）"
        rightPaneButton.target = self
        rightPaneButton.action = #selector(handleToggleRightPane)

        for item in [
            sidebarButton,
            headerIconView,
            titleLabel,
            statusBadgeSurface,
            spacer,
            terminalButton,
            rightPaneButton,
        ] {
            headerBar.addArrangedSubview(item)
        }
        headerBar.orientation = .horizontal
        headerBar.alignment = .centerY
        headerBar.spacing = 6
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        headerDivider.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupDraftView() {
        draftScrollView.contentView = FactoryFlippedClipView()
        draftScrollView.hasVerticalScroller = true
        draftScrollView.drawsBackground = false
        draftScrollView.borderType = .noBorder
        draftScrollView.translatesAutoresizingMaskIntoConstraints = false

        draftDocView.translatesAutoresizingMaskIntoConstraints = false
        draftScrollView.documentView = draftDocView

        draftCard.cornerRadius = 16
        draftCard.strokeWidth = 1
        draftCard.translatesAutoresizingMaskIntoConstraints = false

        draftHeadingLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        blueprintPopup.controlSize = .small
        blueprintPopup.target = self
        blueprintPopup.action = #selector(handleBlueprintChanged)

        duplicateBlueprintButton.buttonStyle = .ghost
        duplicateBlueprintButton.customHeight = 24
        duplicateBlueprintButton.horizontalPadding = 7
        duplicateBlueprintButton.configureSymbol(
            "plus.square.on.square", title: "複製…", pointSize: 11, weight: .medium)
        duplicateBlueprintButton.toolTip = "現在の工場を複製して別工場を作成"
        duplicateBlueprintButton.target = self
        duplicateBlueprintButton.action = #selector(handleDuplicateBlueprintClicked)

        openBlueprintButton.buttonStyle = .ghost
        openBlueprintButton.customHeight = 24
        openBlueprintButton.horizontalPadding = 7
        openBlueprintButton.configureSymbol(
            "doc.text", title: "JSON", pointSize: 11, weight: .medium)
        openBlueprintButton.toolTip = "工場定義 JSON を開く"
        openBlueprintButton.target = self
        openBlueprintButton.action = #selector(handleOpenBlueprintFileClicked)

        let topBar = NSStackView(views: [
            draftHeadingLabel,
            makeFlexibleSpacer(),
            blueprintPopup,
            duplicateBlueprintButton,
            openBlueprintButton,
        ])
        topBar.orientation = .horizontal
        topBar.alignment = .centerY
        topBar.spacing = 6

        draftSubLabel.font = .systemFont(ofSize: 12, weight: .regular)
        draftSubLabel.maximumNumberOfLines = 2
        draftSubLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        promptSurface.cornerRadius = 12
        promptSurface.strokeWidth = 1
        promptSurface.translatesAutoresizingMaskIntoConstraints = false

        promptScrollView.hasVerticalScroller = true
        promptScrollView.drawsBackground = false
        promptScrollView.borderType = .noBorder
        promptScrollView.translatesAutoresizingMaskIntoConstraints = false

        promptTextView.isRichText = false
        promptTextView.allowsUndo = true
        promptTextView.drawsBackground = false
        promptTextView.font = .systemFont(ofSize: 13.5, weight: .regular)
        promptTextView.textContainerInset = NSSize(width: 4, height: 6)
        promptTextView.isVerticallyResizable = true
        promptTextView.isHorizontallyResizable = false
        promptTextView.autoresizingMask = [.width]
        promptTextView.delegate = self
        promptTextView.onSubmitShortcut = { [weak self] in
            self?.handleStartClicked()
        }
        promptScrollView.documentView = promptTextView

        promptPlaceholderLabel.font = .systemFont(ofSize: 12.5, weight: .regular)
        promptPlaceholderLabel.maximumNumberOfLines = 3
        promptPlaceholderLabel.translatesAutoresizingMaskIntoConstraints = false

        promptSurface.addSubview(promptScrollView)
        promptSurface.addSubview(promptPlaceholderLabel)

        charCountLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)

        workerLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        workerPopup.addItems(withTitles: Self.providerChoices.map(\.label))
        workerPopup.controlSize = .small
        workerPopup.target = self
        workerPopup.action = #selector(handleWorkerProviderChanged)
        workerModelPopup.controlSize = .small

        criticLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        criticPopup.addItems(withTitles: Self.providerChoices.map(\.label))
        criticPopup.controlSize = .small
        criticPopup.target = self
        criticPopup.action = #selector(handleCriticProviderChanged)
        criticModelPopup.controlSize = .small

        maxIterLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        maxIterPopup.addItems(withTitles: ["3 周", "5 周"])
        maxIterPopup.controlSize = .small

        minScoreLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        minScorePopup.addItems(withTitles: ["70 点", "80 点", "85 点", "90 点"])
        minScorePopup.controlSize = .small

        let workerRow = NSStackView(views: [
            workerLabel,
            workerPopup,
            workerModelPopup,
            makeFlexibleSpacer(),
        ])
        workerRow.orientation = .horizontal
        workerRow.alignment = .centerY
        workerRow.spacing = 8

        let criticRow = NSStackView(views: [
            criticLabel,
            criticPopup,
            criticModelPopup,
            makeFlexibleSpacer(),
        ])
        criticRow.orientation = .horizontal
        criticRow.alignment = .centerY
        criticRow.spacing = 8

        let limitRow = NSStackView(views: [
            maxIterLabel,
            maxIterPopup,
            minScoreLabel,
            minScorePopup,
            makeFlexibleSpacer(),
            charCountLabel,
        ])
        limitRow.orientation = .horizontal
        limitRow.alignment = .centerY
        limitRow.spacing = 8

        rulesToggleButton.buttonStyle = .ghost
        rulesToggleButton.customHeight = 24
        rulesToggleButton.horizontalPadding = 6
        rulesToggleButton.configureSymbol(
            "slider.horizontal.3", title: "ハーネスルールを微調整…", pointSize: 11, weight: .medium)
        rulesToggleButton.target = self
        rulesToggleButton.action = #selector(handleToggleDraftRules)

        rulesContainer.translatesAutoresizingMaskIntoConstraints = false
        rulesContainer.isHidden = true

        rulesSurface.cornerRadius = 10
        rulesSurface.strokeWidth = 1
        rulesSurface.translatesAutoresizingMaskIntoConstraints = false

        rulesScrollView.hasVerticalScroller = true
        rulesScrollView.drawsBackground = false
        rulesScrollView.borderType = .noBorder
        rulesScrollView.translatesAutoresizingMaskIntoConstraints = false

        rulesTextView.isRichText = false
        rulesTextView.allowsUndo = true
        rulesTextView.drawsBackground = false
        rulesTextView.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        rulesTextView.textContainerInset = NSSize(width: 4, height: 6)
        rulesTextView.isVerticallyResizable = true
        rulesTextView.isHorizontallyResizable = false
        rulesTextView.autoresizingMask = [.width]
        rulesScrollView.documentView = rulesTextView
        rulesSurface.addSubview(rulesScrollView)

        saveRulesButton.buttonStyle = .pill
        saveRulesButton.customHeight = 24
        saveRulesButton.horizontalPadding = 10
        saveRulesButton.configureSymbol(
            "square.and.arrow.down", title: "工場プリセットに保存", pointSize: 10.5, weight: .medium)
        saveRulesButton.target = self
        saveRulesButton.action = #selector(handleSaveDraftBlueprint)

        let rulesStack = NSStackView(views: [rulesSurface, wrapLeading(saveRulesButton)])
        rulesStack.orientation = .vertical
        rulesStack.alignment = .leading
        rulesStack.spacing = 6
        rulesStack.translatesAutoresizingMaskIntoConstraints = false
        rulesContainer.addSubview(rulesStack)
        NSLayoutConstraint.activate([
            rulesSurface.heightAnchor.constraint(equalToConstant: 88),
            rulesSurface.widthAnchor.constraint(equalTo: rulesStack.widthAnchor),
            rulesScrollView.topAnchor.constraint(equalTo: rulesSurface.topAnchor, constant: 6),
            rulesScrollView.leadingAnchor.constraint(
                equalTo: rulesSurface.leadingAnchor, constant: 8),
            rulesScrollView.trailingAnchor.constraint(
                equalTo: rulesSurface.trailingAnchor, constant: -8),
            rulesScrollView.bottomAnchor.constraint(
                equalTo: rulesSurface.bottomAnchor, constant: -6),
            rulesStack.topAnchor.constraint(equalTo: rulesContainer.topAnchor),
            rulesStack.leadingAnchor.constraint(equalTo: rulesContainer.leadingAnchor),
            rulesStack.trailingAnchor.constraint(equalTo: rulesContainer.trailingAnchor),
            rulesStack.bottomAnchor.constraint(equalTo: rulesContainer.bottomAnchor),
        ])

        demoButton.buttonStyle = .pill
        demoButton.customHeight = 32
        demoButton.horizontalPadding = 12
        demoButton.configureSymbol("play.circle", title: "デモで表示", pointSize: 12.5, weight: .medium)
        demoButton.target = self
        demoButton.action = #selector(handleDemoClicked)

        startButton.buttonStyle = .circlePrimary
        startButton.customHeight = 32
        startButton.horizontalPadding = 16
        startButton.configureSymbol(
            "arrow.up.circle.fill", title: "開始", pointSize: 13, weight: .semibold)
        startButton.target = self
        startButton.action = #selector(handleStartClicked)

        let actionRow = NSStackView(views: [
            rulesToggleButton,
            makeFlexibleSpacer(),
            demoButton,
            startButton,
        ])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 8

        let cardStack = NSStackView()
        cardStack.orientation = .vertical
        cardStack.alignment = .leading
        cardStack.spacing = 11
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        addFullWidth(topBar, to: cardStack)
        addFullWidth(draftSubLabel, to: cardStack)
        addFullWidth(promptSurface, to: cardStack)
        addFullWidth(workerRow, to: cardStack)
        addFullWidth(criticRow, to: cardStack)
        addFullWidth(limitRow, to: cardStack)
        addFullWidth(rulesContainer, to: cardStack)
        addFullWidth(actionRow, to: cardStack)

        draftCard.addSubview(cardStack)
        draftDocView.addSubview(draftCard)

        let idealWidth = draftCard.widthAnchor.constraint(equalToConstant: 660)
        idealWidth.priority = NSLayoutConstraint.Priority(240)

        NSLayoutConstraint.activate([
            draftDocView.topAnchor.constraint(equalTo: draftScrollView.contentView.topAnchor),
            draftDocView.leadingAnchor.constraint(
                equalTo: draftScrollView.contentView.leadingAnchor),
            draftDocView.trailingAnchor.constraint(
                equalTo: draftScrollView.contentView.trailingAnchor),
            draftDocView.widthAnchor.constraint(equalTo: draftScrollView.contentView.widthAnchor),

            draftCard.topAnchor.constraint(equalTo: draftDocView.topAnchor, constant: 24),
            draftCard.bottomAnchor.constraint(equalTo: draftDocView.bottomAnchor, constant: -24),
            draftCard.centerXAnchor.constraint(equalTo: draftDocView.centerXAnchor),
            draftCard.leadingAnchor.constraint(
                greaterThanOrEqualTo: draftDocView.leadingAnchor, constant: 20),
            draftCard.trailingAnchor.constraint(
                lessThanOrEqualTo: draftDocView.trailingAnchor, constant: -20),
            draftCard.widthAnchor.constraint(lessThanOrEqualToConstant: 680),
            idealWidth,

            cardStack.topAnchor.constraint(equalTo: draftCard.topAnchor, constant: 20),
            cardStack.leadingAnchor.constraint(equalTo: draftCard.leadingAnchor, constant: 20),
            cardStack.trailingAnchor.constraint(equalTo: draftCard.trailingAnchor, constant: -20),
            cardStack.bottomAnchor.constraint(equalTo: draftCard.bottomAnchor, constant: -18),

            promptSurface.heightAnchor.constraint(equalToConstant: 118),
            promptScrollView.topAnchor.constraint(equalTo: promptSurface.topAnchor, constant: 8),
            promptScrollView.leadingAnchor.constraint(
                equalTo: promptSurface.leadingAnchor, constant: 10),
            promptScrollView.trailingAnchor.constraint(
                equalTo: promptSurface.trailingAnchor, constant: -10),
            promptScrollView.bottomAnchor.constraint(
                equalTo: promptSurface.bottomAnchor, constant: -8),

            promptPlaceholderLabel.topAnchor.constraint(
                equalTo: promptSurface.topAnchor, constant: 14),
            promptPlaceholderLabel.leadingAnchor.constraint(
                equalTo: promptSurface.leadingAnchor, constant: 18),
            promptPlaceholderLabel.trailingAnchor.constraint(
                equalTo: promptSurface.trailingAnchor, constant: -18),
        ])

        refreshBlueprintPopup()
        applyBlueprintToDraftControls(currentBlueprint())
    }

    private func setupPipelineView() {
        pipelineScrollView.contentView = FactoryFlippedClipView()
        pipelineScrollView.hasVerticalScroller = true
        pipelineScrollView.drawsBackground = false
        pipelineScrollView.borderType = .noBorder
        pipelineScrollView.translatesAutoresizingMaskIntoConstraints = false

        pipelineDocumentView.translatesAutoresizingMaskIntoConstraints = false
        pipelineStack.orientation = .vertical
        pipelineStack.alignment = .leading
        pipelineStack.spacing = 14
        pipelineStack.translatesAutoresizingMaskIntoConstraints = false

        workflowDiagram.translatesAutoresizingMaskIntoConstraints = false
        workflowDiagram.onSelectChildRun = { [weak self] childId in
            self?.onSelectRun?(childId)
        }
        let hConstraint = workflowDiagram.heightAnchor.constraint(equalToConstant: 156)
        hConstraint.isActive = true
        workflowHeightConstraint = hConstraint

        pipelineDocumentView.addSubview(pipelineStack)
        pipelineScrollView.documentView = pipelineDocumentView

        NSLayoutConstraint.activate([
            pipelineDocumentView.topAnchor.constraint(
                equalTo: pipelineScrollView.contentView.topAnchor),
            pipelineDocumentView.leadingAnchor.constraint(
                equalTo: pipelineScrollView.contentView.leadingAnchor),
            pipelineDocumentView.trailingAnchor.constraint(
                equalTo: pipelineScrollView.contentView.trailingAnchor),
            pipelineDocumentView.widthAnchor.constraint(
                equalTo: pipelineScrollView.contentView.widthAnchor),

            pipelineStack.topAnchor.constraint(
                equalTo: pipelineDocumentView.topAnchor, constant: 14),
            pipelineStack.leadingAnchor.constraint(
                equalTo: pipelineDocumentView.leadingAnchor, constant: 18),
            pipelineStack.trailingAnchor.constraint(
                equalTo: pipelineDocumentView.trailingAnchor, constant: -18),
            pipelineStack.bottomAnchor.constraint(
                equalTo: pipelineDocumentView.bottomAnchor, constant: -24),
        ])
    }

    func update(blueprints: [FactoryBlueprint]) {
        self.blueprints = blueprints.isEmpty ? FactoryBlueprint.builtInDefaults() : blueprints
        refreshBlueprintPopup()
        if let run = currentRun, run.status == .draft {
            applyBlueprintToDraftControls(currentBlueprint())
        }
    }

    func update(palette: KasugaiPalette) {
        self.palette = palette
        applyTheme()
    }

    func updatePaneStates(
        leftSidebarCollapsed: Bool,
        rightPaneOpen: Bool,
        terminalPaneOpen: Bool
    ) {
        self.leftSidebarCollapsed = leftSidebarCollapsed
        self.rightPaneOpen = rightPaneOpen
        self.terminalPaneOpen = terminalPaneOpen
        sidebarButton.isHidden = !leftSidebarCollapsed
        rightPaneButton.isHidden = rightPaneOpen
        terminalButton.isSelectedPill = terminalPaneOpen
        headerLeadingConstraint?.constant =
            leftSidebarCollapsed ? KasugaiChromeMetrics.trafficLightLeadingInset : 12
        applyHeaderButtonStyles()
    }

    func display(run: FactoryRunRecord?, childRuns: [String: FactoryRunRecord] = [:]) {
        let switchedRun = currentRun?.id != run?.id
        if !switchedRun && currentRun == run && currentChildRuns == childRuns {
            return
        }
        let prevIterCount = currentRun?.iterations.count ?? 0
        currentRun = run
        currentChildRuns = childRuns
        guard let run else {
            titleLabel.stringValue = "工場"
            statusBadgeSurface.isHidden = true
            draftScrollView.isHidden = true
            pipelineScrollView.isHidden = true
            return
        }

        if switchedRun || run.iterations.count > prevIterCount {
            selectedIterationIndex = run.iterations.last?.index
            if switchedRun {
                selectedDetailTab = .iterations
            }
        }

        titleLabel.stringValue = run.displayTitle
        statusBadgeSurface.isHidden = false
        statusBadgeLabel.stringValue = run.status.label
        applyStatusBadgeStyle(for: run.status)

        if run.status == .draft {
            draftScrollView.isHidden = false
            pipelineScrollView.isHidden = true
            if switchedRun {
                selectedBlueprintId = run.blueprintId
                refreshBlueprintPopup()
                applyBlueprintToDraftControls(currentBlueprint())
                promptTextView.string = run.prompt
                selectProvider(run.workerProvider, in: workerPopup)
                reloadModelPopup(
                    workerModelPopup,
                    providerId: run.workerProvider,
                    selectedModel: run.workerModel,
                    storeInto: &workerModelOptions
                )
                selectProvider(run.criticProvider, in: criticPopup)
                reloadModelPopup(
                    criticModelPopup,
                    providerId: run.criticProvider,
                    selectedModel: run.criticModel,
                    storeInto: &criticModelOptions
                )
                maxIterPopup.selectItem(at: run.maxIterations >= 5 ? 1 : 0)
                selectScore(run.minReviewScore, in: minScorePopup)
                rulesTextView.string = run.harnessRules.joined(separator: "\n")
                updateDraftControls()
                view.window?.makeFirstResponder(promptTextView)
            }
        } else {
            draftScrollView.isHidden = true
            pipelineScrollView.isHidden = false
            rebuildPipelineContent(for: run)
        }
        syncElapsedTimer(for: run)
    }

    private func syncElapsedTimer(for run: FactoryRunRecord) {
        if run.status == .running {
            if elapsedTimer == nil {
                let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                    guard let self, let active = self.currentRun, active.status == .running else {
                        self?.elapsedTimer?.invalidate()
                        self?.elapsedTimer = nil
                        return
                    }
                    self.liveElapsedLabel?.stringValue = "稼働 \(active.formattedElapsed())"
                }
                RunLoop.main.add(timer, forMode: .common)
                elapsedTimer = timer
            }
        } else {
            elapsedTimer?.invalidate()
            elapsedTimer = nil
        }
    }

    func textDidChange(_ notification: Notification) {
        updateDraftControls()
    }

    private func currentBlueprint() -> FactoryBlueprint {
        blueprints.first(where: { $0.id == selectedBlueprintId })
            ?? blueprints.first
            ?? FactoryBlueprint.builtInDefaults()[0]
    }

    private func refreshBlueprintPopup() {
        blueprintPopup.removeAllItems()
        for bp in blueprints {
            blueprintPopup.addItem(withTitle: bp.name)
        }
        if let idx = blueprints.firstIndex(where: { $0.id == selectedBlueprintId }) {
            blueprintPopup.selectItem(at: idx)
        } else if let first = blueprints.first {
            selectedBlueprintId = first.id
            blueprintPopup.selectItem(at: 0)
        }
    }

    private func applyBlueprintToDraftControls(_ bp: FactoryBlueprint) {
        draftSubLabel.stringValue = bp.summary
        promptPlaceholderLabel.stringValue = bp.placeholderPrompt
        selectProvider(bp.defaultWorkerProvider, in: workerPopup)
        reloadModelPopup(
            workerModelPopup,
            providerId: bp.defaultWorkerProvider,
            selectedModel: bp.defaultWorkerModel,
            storeInto: &workerModelOptions
        )
        selectProvider(bp.defaultCriticProvider, in: criticPopup)
        reloadModelPopup(
            criticModelPopup,
            providerId: bp.defaultCriticProvider,
            selectedModel: bp.defaultCriticModel,
            storeInto: &criticModelOptions
        )
        maxIterPopup.selectItem(at: bp.maxIterations >= 5 ? 1 : 0)
        selectScore(bp.minReviewScore, in: minScorePopup)
        rulesTextView.string = bp.harnessRules.joined(separator: "\n")
        updateDraftControls()
    }

    private func selectProvider(_ id: String, in popup: NSPopUpButton) {
        if let idx = Self.providerChoices.firstIndex(where: { $0.id == id }) {
            popup.selectItem(at: idx)
        } else {
            popup.selectItem(at: 0)
        }
    }

    private func selectedProviderId(in popup: NSPopUpButton, fallback: String) -> String {
        let idx = popup.indexOfSelectedItem
        guard idx >= 0, idx < Self.providerChoices.count else {
            return fallback
        }
        return Self.providerChoices[idx].id
    }

    private func reloadModelPopup(
        _ popup: NSPopUpButton,
        providerId: String,
        selectedModel: String,
        storeInto storage: inout [KasugaiModelOption]
    ) {
        var opts = ProviderModelCatalog.shared.options(for: providerId)
        if !selectedModel.isEmpty && !opts.contains(where: { $0.id == selectedModel }) {
            opts.insert(KasugaiModelOption(id: selectedModel, label: selectedModel), at: 0)
        }
        storage = opts
        popup.removeAllItems()
        for item in opts {
            popup.addItem(withTitle: item.label)
        }
        if let idx = opts.firstIndex(where: { $0.id == selectedModel }) {
            popup.selectItem(at: idx)
        } else if !opts.isEmpty {
            popup.selectItem(at: 0)
        }
    }

    private func selectedModelId(
        in popup: NSPopUpButton,
        options: [KasugaiModelOption],
        fallback: String
    ) -> String {
        let idx = popup.indexOfSelectedItem
        guard idx >= 0, idx < options.count else {
            return fallback
        }
        return options[idx].id
    }

    private func selectScore(_ score: Int, in popup: NSPopUpButton) {
        let values = [70, 80, 85, 90]
        if let idx = values.firstIndex(of: score) {
            popup.selectItem(at: idx)
        } else {
            popup.selectItem(at: 1)
        }
    }

    private func selectedScoreValue(in popup: NSPopUpButton) -> Int {
        let values = [70, 80, 85, 90]
        let idx = popup.indexOfSelectedItem
        return (idx >= 0 && idx < values.count) ? values[idx] : 80
    }

    private func parseRules(from text: String) -> [String] {
        text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func updateDraftControls() {
        let text = promptTextView.string
        let count = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        promptPlaceholderLabel.isHidden = !text.isEmpty
        charCountLabel.stringValue = "\(count) / 200 字"
        charCountLabel.textColor = count > 200 ? theme.warning : theme.textMuted
        startButton.isEnabled = count > 0
    }

    private func applyTheme() {
        theme = KasugaiThemeTokens.resolve(
            palette: palette,
            appearance: view.effectiveAppearance
        )
        rootSurface.fillColor = theme.canvasBg
        headerDivider.fillColor = theme.borderSubtle
        headerIconView.contentTintColor = theme.accent
        titleLabel.textColor = theme.textPrimary
        applyHeaderButtonStyles()

        draftCard.fillColor = theme.surfaceBg
        draftCard.strokeColor = theme.borderSubtle
        draftHeadingLabel.textColor = theme.textPrimary
        draftSubLabel.textColor = theme.textSecondary
        duplicateBlueprintButton.apply(theme: theme)
        openBlueprintButton.apply(theme: theme)
        promptSurface.fillColor = theme.canvasBg
        promptSurface.strokeColor = theme.borderStrong
        promptTextView.textColor = theme.textPrimary
        promptTextView.insertionPointColor = theme.accent
        promptPlaceholderLabel.textColor = theme.textMuted
        workerLabel.textColor = theme.textSecondary
        criticLabel.textColor = theme.textSecondary
        maxIterLabel.textColor = theme.textSecondary
        minScoreLabel.textColor = theme.textSecondary
        rulesToggleButton.apply(theme: theme)
        rulesSurface.fillColor = theme.canvasBg
        rulesSurface.strokeColor = theme.borderSubtle
        rulesTextView.textColor = theme.textPrimary
        rulesTextView.insertionPointColor = theme.accent
        saveRulesButton.apply(theme: theme)
        startButton.apply(theme: theme)
        demoButton.apply(theme: theme)
        updateDraftControls()

        if let run = currentRun {
            applyStatusBadgeStyle(for: run.status)
            if run.status != .draft {
                rebuildPipelineContent(for: run)
            }
        }
    }

    private func applyHeaderButtonStyles() {
        sidebarButton.apply(theme: theme)
        terminalButton.isSelectedPill = terminalPaneOpen
        terminalButton.apply(theme: theme)
        rightPaneButton.isSelectedPill = rightPaneOpen
        rightPaneButton.apply(theme: theme)
    }

    private func applyStatusBadgeStyle(for status: FactoryRunStatus) {
        let color: NSColor
        switch status {
        case .draft:
            color = theme.textMuted
        case .running:
            color = theme.accent
        case .previewReady:
            color = theme.warning
        case .published:
            color = theme.success
        case .discarded:
            color = theme.textMuted
        case .failed:
            color = theme.danger
        }
        statusBadgeSurface.fillColor = color.withAlphaComponent(0.14)
        statusBadgeSurface.strokeColor = color.withAlphaComponent(0.35)
        statusBadgeLabel.textColor = color
    }

    private func color(for tone: FactoryTone) -> NSColor {
        switch tone {
        case .neutral:
            return theme.textMuted
        case .accent:
            return theme.accent
        case .success:
            return theme.success
        case .warning:
            return theme.warning
        case .danger:
            return theme.danger
        }
    }

    private func addFullWidth(_ view: NSView, to stack: NSStackView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func rebuildPipelineContent(for run: FactoryRunRecord) {
        for sub in pipelineStack.arrangedSubviews {
            pipelineStack.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }

        addFullWidth(makeCompactSpecStrip(for: run), to: pipelineStack)

        workflowHeightConstraint?.constant = workflowDiagram.preferredHeight(for: run)
        workflowDiagram.configure(run: run, childRuns: currentChildRuns, theme: theme)
        addFullWidth(workflowDiagram, to: pipelineStack)

        if run.status == .previewReady || run.status == .published
            || run.status == .discarded || run.localPreviewURL != nil
            || run.stagingPreviewURL != nil
        {
            addFullWidth(makeReleaseSpotlightBar(for: run), to: pipelineStack)
        }

        if let err = run.errorMessage, !err.isEmpty {
            addFullWidth(makeErrorBanner(message: err), to: pipelineStack)
        }

        addFullWidth(makeDetailHeaderBar(for: run), to: pipelineStack)

        switch selectedDetailTab {
        case .logs:
            addFullWidth(makeLogsPanel(logs: run.logs), to: pipelineStack)
        case .tuning:
            addFullWidth(makeTuningPanel(for: run), to: pipelineStack)
        case .iterations:
            if let iter = activeIteration(in: run) {
                addFullWidth(makeIterationInspector(iter), to: pipelineStack)
            } else {
                addFullWidth(makeWaitingInspector(for: run), to: pipelineStack)
            }
        }
    }

    private func activeIteration(in run: FactoryRunRecord) -> FactoryIterationRecord? {
        if let idx = selectedIterationIndex,
            let matched = run.iterations.first(where: { $0.index == idx })
        {
            return matched
        }
        return run.iterations.last
    }

    private func makeCompactSpecStrip(for run: FactoryRunRecord) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8

        if let parentId = run.parentRunId, !parentId.isEmpty {
            let backBtn = KasugaiFlatButton()
            backBtn.buttonStyle = .pill
            backBtn.customHeight = 22
            backBtn.horizontalPadding = 8
            backBtn.configureSymbol(
                "chevron.left", title: "親工場へ戻る", pointSize: 10, weight: .semibold)
            backBtn.apply(theme: theme)
            backBtn.target = self
            backBtn.action = #selector(handleBackToParentRun)
            row.addArrangedSubview(backBtn)
        }

        let promptLine = NSTextField(labelWithString: "「\(run.prompt)」")
        promptLine.font = .systemFont(ofSize: 12, weight: .medium)
        promptLine.textColor = theme.textSecondary
        promptLine.lineBreakMode = .byTruncatingTail
        promptLine.toolTip = run.prompt
        promptLine.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let elapsedChip = makeLiveTelemetryChip(
            symbol: "clock",
            text: "稼働 \(run.formattedElapsed())",
            tooltip: "ファクトリー累計稼働時間",
            captureLabel: true
        )
        let tokenChip = makeLiveTelemetryChip(
            symbol: "gauge.medium",
            text: "トークン \(run.formattedTokens)",
            tooltip: run.tokenBreakdownTooltip,
            captureLabel: false
        )

        let bpChip = makeMetricChip(
            "\(run.blueprintName) · \(Self.providerDisplayLabel(for: run.workerProvider)) → \(Self.providerDisplayLabel(for: run.criticProvider))"
        )

        row.addArrangedSubview(promptLine)
        row.addArrangedSubview(makeFlexibleSpacer())
        if let children = run.childRunIds,
            let firstStage = run.stages.first(where: { children[$0.id] != nil }),
            let childId = children[firstStage.id]
        {
            let childBtn = KasugaiFlatButton()
            childBtn.buttonStyle = .pill
            childBtn.customHeight = 22
            childBtn.horizontalPadding = 8
            childBtn.customTintColor = theme.accent
            childBtn.configureSymbol(
                firstStage.symbol,
                title: "子工場: \(firstStage.title)",
                pointSize: 10,
                weight: .semibold
            )
            childBtn.apply(theme: theme)
            childBtn.toolTip = childId
            childBtn.target = self
            childBtn.action = #selector(handleOpenChildRun(_:))
            row.addArrangedSubview(childBtn)
        }
        row.addArrangedSubview(elapsedChip)
        row.addArrangedSubview(tokenChip)
        row.addArrangedSubview(bpChip)

        if run.status == .running {
            let stopBtn = KasugaiFlatButton()
            stopBtn.buttonStyle = .pill
            stopBtn.customHeight = 22
            stopBtn.horizontalPadding = 8
            stopBtn.customTintColor = theme.danger
            stopBtn.configureSymbol("stop.fill", title: "停止", pointSize: 9.5, weight: .semibold)
            stopBtn.apply(theme: theme)
            stopBtn.target = self
            stopBtn.action = #selector(handleStopClicked)
            row.addArrangedSubview(stopBtn)
        }
        return row
    }

    private func makeReleaseSpotlightBar(for run: FactoryRunRecord) -> NSView {
        let bar = KasugaiSurfaceView()
        bar.cornerRadius = 12
        bar.strokeWidth = 1
        let accent: NSColor
        let titleText: String
        switch run.status {
        case .previewReady:
            accent = theme.warning
            titleText = "製造完了 · 右ペインで遊んで確認"
        case .published:
            accent = theme.success
            titleText = "\(run.publishTargetLabel) に公開済み"
        case .discarded:
            accent = theme.textMuted
            titleText = "破棄済み（工場を微調整して再製造できます）"
        default:
            accent = theme.accent
            titleText = "プレビュー"
        }
        bar.fillColor = accent.withAlphaComponent(theme.isLight ? 0.08 : 0.11)
        bar.strokeColor = accent.withAlphaComponent(0.38)
        bar.translatesAutoresizingMaskIntoConstraints = false

        let heading = NSTextField(labelWithString: titleText)
        heading.font = .systemFont(ofSize: 12.5, weight: .semibold)
        heading.textColor = theme.textPrimary

        let urlText = run.productionURL ?? run.stagingPreviewURL ?? run.localPreviewURL ?? ""
        let urlLabel = NSTextField(labelWithString: urlText)
        urlLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        urlLabel.textColor = theme.textSecondary
        urlLabel.lineBreakMode = .byTruncatingMiddle
        urlLabel.isSelectable = true
        urlLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let leftStack = NSStackView(views: [heading, urlLabel])
        leftStack.orientation = .vertical
        leftStack.alignment = .leading
        leftStack.spacing = 2
        leftStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 6

        if run.localPreviewURL != nil {
            let previewBtn = KasugaiFlatButton()
            previewBtn.buttonStyle = .pill
            previewBtn.customHeight = 28
            previewBtn.horizontalPadding = 10
            previewBtn.configureSymbol(
                "sidebar.right", title: "右ペインで表示", pointSize: 11, weight: .medium)
            previewBtn.apply(theme: theme)
            previewBtn.target = self
            previewBtn.action = #selector(handleOpenLocalPreviewClicked)
            actions.addArrangedSubview(previewBtn)
        }

        if let extURL = run.productionURL ?? run.stagingPreviewURL, !extURL.isEmpty {
            let browserBtn = KasugaiFlatButton()
            browserBtn.buttonStyle = .pill
            browserBtn.customHeight = 28
            browserBtn.horizontalPadding = 10
            browserBtn.configureSymbol("safari", title: "ブラウザで開く", pointSize: 11, weight: .medium)
            browserBtn.apply(theme: theme)
            browserBtn.target = self
            browserBtn.action = #selector(handleOpenExternalURLClicked)
            actions.addArrangedSubview(browserBtn)
        }

        if run.status == .previewReady {
            let discardBtn = KasugaiFlatButton()
            discardBtn.buttonStyle = .pill
            discardBtn.customHeight = 28
            discardBtn.horizontalPadding = 10
            discardBtn.customTintColor = theme.danger
            discardBtn.configureSymbol("trash", title: "破棄…", pointSize: 11, weight: .medium)
            discardBtn.apply(theme: theme)
            discardBtn.target = self
            discardBtn.action = #selector(handleDiscardClicked)
            actions.addArrangedSubview(discardBtn)

            let publishBtn = KasugaiFlatButton()
            publishBtn.buttonStyle = .circlePrimary
            publishBtn.customHeight = 28
            publishBtn.horizontalPadding = 14
            publishBtn.configureSymbol(
                "checkmark.seal.fill", title: "本番に公開…", pointSize: 11.5, weight: .semibold)
            publishBtn.apply(theme: theme)
            publishBtn.target = self
            publishBtn.action = #selector(handlePublishClicked)
            actions.addArrangedSubview(publishBtn)
        }

        let outer = NSStackView(views: [leftStack, actions])
        outer.orientation = .horizontal
        outer.alignment = .centerY
        outer.spacing = 10
        outer.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(outer)
        pin(outer, inside: bar, inset: 12)
        return bar
    }

    private func makeErrorBanner(message: String) -> NSView {
        let bar = KasugaiSurfaceView()
        bar.cornerRadius = 10
        bar.strokeWidth = 1
        bar.fillColor = theme.danger.withAlphaComponent(0.10)
        bar.strokeColor = theme.danger.withAlphaComponent(0.35)
        bar.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(wrappingLabelWithString: message)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = theme.danger
        label.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(label)
        pin(label, inside: bar, inset: 11)
        return bar
    }

    private func makeDetailHeaderBar(for run: FactoryRunRecord) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6

        for iter in run.iterations {
            let btn = KasugaiFlatButton()
            btn.buttonStyle = .pill
            btn.customHeight = 26
            btn.horizontalPadding = 9
            btn.tag = iter.index
            let sym: String
            let tint: NSColor
            switch iter.outcome {
            case "passed":
                sym = "checkmark.circle.fill"
                tint = theme.success
            case "retry":
                sym = "arrow.uturn.left.circle.fill"
                tint = theme.warning
            case "pivot":
                sym = "exclamationmark.triangle.fill"
                tint = theme.danger
            default:
                sym = "circle.dotted"
                tint = theme.accent
            }
            let durSuffix = iter.durationSeconds.map { " · \(Int($0.rounded()))秒" } ?? ""
            let badgeSuffix = iter.badgeText.map { " \($0)" } ?? ""
            btn.configureSymbol(
                sym,
                title: "第 \(iter.index) 周\(durSuffix)\(badgeSuffix)",
                pointSize: 10.5,
                weight: .semibold
            )
            btn.isSelectedPill =
                selectedDetailTab == .iterations
                && activeIteration(in: run)?.index == iter.index
            btn.customTintColor = tint
            btn.apply(theme: theme)
            btn.target = self
            btn.action = #selector(handleSelectIteration(_:))
            row.addArrangedSubview(btn)
        }

        if run.iterations.isEmpty {
            let label = NSTextField(labelWithString: "第 1 周 準備中…")
            label.font = .systemFont(ofSize: 11.5, weight: .medium)
            label.textColor = theme.textMuted
            row.addArrangedSubview(label)
        }

        row.addArrangedSubview(makeFlexibleSpacer())

        let tuneBtn = KasugaiFlatButton()
        tuneBtn.buttonStyle = .pill
        tuneBtn.customHeight = 26
        tuneBtn.horizontalPadding = 9
        tuneBtn.configureSymbol(
            "slider.horizontal.3",
            title: "工場を調整",
            pointSize: 10.5,
            weight: .medium
        )
        tuneBtn.isSelectedPill = selectedDetailTab == .tuning
        tuneBtn.apply(theme: theme)
        tuneBtn.target = self
        tuneBtn.action = #selector(handleToggleTuningTab)
        row.addArrangedSubview(tuneBtn)

        let logBtn = KasugaiFlatButton()
        logBtn.buttonStyle = .pill
        logBtn.customHeight = 26
        logBtn.horizontalPadding = 9
        logBtn.configureSymbol(
            "text.alignleft",
            title: "ログ（\(run.logs.count)）",
            pointSize: 10.5,
            weight: .medium
        )
        logBtn.isSelectedPill = selectedDetailTab == .logs
        logBtn.apply(theme: theme)
        logBtn.target = self
        logBtn.action = #selector(handleToggleLogsTab)
        row.addArrangedSubview(logBtn)

        return row
    }

    private func makeIterationInspector(_ iter: FactoryIterationRecord) -> NSView {
        let panels = iter.panels
        guard !panels.isEmpty else {
            return makeSubtlePanel()
        }
        if panels.count == 1 {
            return makeGatePanelCard(panels[0])
        }

        let leftPane = makeGatePanelCard(panels[0])
        let rightPane = makeGatePanelCard(panels[1])

        let connector = NSImageView()
        let leftPassed = panels[0].tone == .success
        let leftFailed = panels[0].tone == .danger
        let sym = leftFailed ? "xmark" : "arrow.right"
        let cfg = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        connector.image = NSImage(systemSymbolName: sym, accessibilityDescription: "次の工程")?
            .withSymbolConfiguration(cfg)
        connector.contentTintColor =
            leftPassed ? theme.success : (leftFailed ? theme.danger : theme.textMuted)
        connector.toolTip =
            leftFailed
            ? "自動検査で不合格のため独立レビューを省略しました"
            : "自動検査を通過すると独立レビューへ進みます"
        connector.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(leftPane)
        container.addSubview(connector)
        container.addSubview(rightPane)
        NSLayoutConstraint.activate([
            leftPane.topAnchor.constraint(equalTo: container.topAnchor),
            leftPane.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            leftPane.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            connector.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            connector.leadingAnchor.constraint(equalTo: leftPane.trailingAnchor, constant: 6),
            connector.widthAnchor.constraint(equalToConstant: 16),
            connector.heightAnchor.constraint(equalToConstant: 16),

            rightPane.topAnchor.constraint(equalTo: container.topAnchor),
            rightPane.leadingAnchor.constraint(equalTo: connector.trailingAnchor, constant: 6),
            rightPane.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rightPane.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            rightPane.widthAnchor.constraint(equalTo: leftPane.widthAnchor),
        ])
        return container
    }

    private func makeGatePanelCard(_ panel: FactoryGatePanel) -> NSView {
        let box = makeSubtlePanel()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: panel.title)
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        title.textColor = theme.textPrimary

        let gateNum = panel.id == "gate2" ? "GATE 2" : "GATE 1"
        let gateColor: NSColor = panel.tone == .neutral ? theme.warning : color(for: panel.tone)
        let gateTag = makePillLabel(text: gateNum, color: gateColor)

        let header = NSStackView(views: [
            gateTag,
            title,
            makeFlexibleSpacer(),
            makePillLabel(text: panel.statusText, color: color(for: panel.tone)),
        ])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 6
        addFullWidth(header, to: stack)

        if !panel.metrics.isEmpty {
            let tiles = panel.metrics.map { item in
                makeStatTile(
                    label: item.label,
                    value: item.value,
                    accent: item.tone == .neutral ? nil : color(for: item.tone)
                )
            }
            let gridRow = NSView()
            gridRow.translatesAutoresizingMaskIntoConstraints = false
            for (idx, tile) in tiles.enumerated() {
                gridRow.addSubview(tile)
                tile.topAnchor.constraint(equalTo: gridRow.topAnchor).isActive = true
                tile.bottomAnchor.constraint(equalTo: gridRow.bottomAnchor).isActive = true
                if idx == 0 {
                    tile.leadingAnchor.constraint(equalTo: gridRow.leadingAnchor).isActive = true
                } else {
                    tile.leadingAnchor.constraint(
                        equalTo: tiles[idx - 1].trailingAnchor, constant: 8
                    ).isActive = true
                    tile.widthAnchor.constraint(equalTo: tiles[0].widthAnchor).isActive = true
                }
                if idx == tiles.count - 1 {
                    tile.trailingAnchor.constraint(equalTo: gridRow.trailingAnchor).isActive = true
                }
            }
            addFullWidth(gridRow, to: stack)
        }

        if let summary = panel.summary, !summary.isEmpty {
            let summaryLabel = NSTextField(wrappingLabelWithString: summary)
            summaryLabel.font = .systemFont(ofSize: 12, weight: .regular)
            summaryLabel.textColor =
                panel.tone == .danger ? theme.danger : theme.textPrimary
            addFullWidth(summaryLabel, to: stack)
        }

        for bullet in panel.bullets {
            let item = NSTextField(wrappingLabelWithString: "• \(bullet)")
            item.font = .systemFont(ofSize: 11.5, weight: .regular)
            item.textColor = theme.textSecondary
            addFullWidth(item, to: stack)
        }

        if let sheetPath = panel.imagePath,
            FileManager.default.fileExists(atPath: sheetPath),
            let img = NSImage(contentsOfFile: sheetPath)
        {
            let imgView = NSImageView(image: img)
            imgView.imageScaling = .scaleProportionallyDown
            imgView.wantsLayer = true
            imgView.layer?.cornerRadius = 8
            imgView.layer?.masksToBounds = true
            imgView.translatesAutoresizingMaskIntoConstraints = false
            imgView.heightAnchor.constraint(equalToConstant: 110).isActive = true
            addFullWidth(imgView, to: stack)
        }

        let bottomFiller = NSView()
        bottomFiller.setContentHuggingPriority(.init(1), for: .vertical)
        bottomFiller.setContentCompressionResistancePriority(.init(1), for: .vertical)
        stack.addArrangedSubview(bottomFiller)

        if let tid = panel.threadId {
            let btn = KasugaiFlatButton()
            btn.buttonStyle = .ghost
            btn.customHeight = 24
            btn.horizontalPadding = 8
            btn.tag = Int(tid)
            let sym = panel.id == "gate2" ? "eye" : "bubble.left"
            btn.configureSymbol(
                sym,
                title: panel.threadLabel ?? "スレッドを表示",
                pointSize: 11,
                weight: .medium
            )
            btn.apply(theme: theme)
            btn.target = self
            btn.action = #selector(handleOpenLinkedThread(_:))
            stack.addArrangedSubview(btn)
        }

        box.addSubview(stack)
        pin(stack, inside: box, inset: 13)
        return box
    }

    private func makeTuningPanel(for run: FactoryRunRecord) -> NSView {
        let bp = blueprints.first(where: { $0.id == run.blueprintId }) ?? currentBlueprint()
        let box = makeSubtlePanel()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        let heading = NSTextField(labelWithString: "\(bp.name) の設定を微調整（次回の製造から反映）")
        heading.font = .systemFont(ofSize: 12, weight: .semibold)
        heading.textColor = theme.textPrimary

        let openJsonBtn = KasugaiFlatButton()
        openJsonBtn.buttonStyle = .ghost
        openJsonBtn.customHeight = 24
        openJsonBtn.horizontalPadding = 8
        openJsonBtn.configureSymbol("doc.text", title: "JSON を開く", pointSize: 11, weight: .medium)
        openJsonBtn.apply(theme: theme)
        openJsonBtn.target = self
        openJsonBtn.action = #selector(handleOpenActiveBlueprintJSON)

        let headRow = NSStackView(views: [heading, makeFlexibleSpacer(), openJsonBtn])
        headRow.orientation = .horizontal
        headRow.alignment = .centerY
        addFullWidth(headRow, to: stack)

        let iterLabel = NSTextField(labelWithString: "最大周回数")
        iterLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        iterLabel.textColor = theme.textSecondary
        let iterPopup = NSPopUpButton()
        iterPopup.addItems(withTitles: ["3 周", "5 周"])
        iterPopup.controlSize = .small
        iterPopup.selectItem(at: bp.maxIterations >= 5 ? 1 : 0)
        tuningIterPopup = iterPopup

        let scoreLabel = NSTextField(labelWithString: "合格点")
        scoreLabel.font = .systemFont(ofSize: 11.5, weight: .medium)
        scoreLabel.textColor = theme.textSecondary
        let scorePopup = NSPopUpButton()
        scorePopup.addItems(withTitles: ["70 点", "80 点", "85 点", "90 点"])
        scorePopup.controlSize = .small
        selectScore(bp.minReviewScore, in: scorePopup)
        tuningScorePopup = scorePopup

        let paramRow = NSStackView(views: [
            iterLabel, iterPopup, scoreLabel, scorePopup, makeFlexibleSpacer(),
        ])
        paramRow.orientation = .horizontal
        paramRow.alignment = .centerY
        paramRow.spacing = 8
        addFullWidth(paramRow, to: stack)

        let rulesTitle = NSTextField(labelWithString: "ハーネスルール（1 行 1 ルール）")
        rulesTitle.font = .systemFont(ofSize: 11, weight: .medium)
        rulesTitle.textColor = theme.textMuted
        stack.addArrangedSubview(rulesTitle)

        let editorSurface = KasugaiSurfaceView()
        editorSurface.cornerRadius = 10
        editorSurface.strokeWidth = 1
        editorSurface.fillColor = theme.canvasBg
        editorSurface.strokeColor = theme.borderSubtle
        editorSurface.translatesAutoresizingMaskIntoConstraints = false

        let editorScroll = NSScrollView()
        editorScroll.hasVerticalScroller = true
        editorScroll.drawsBackground = false
        editorScroll.borderType = .noBorder
        editorScroll.translatesAutoresizingMaskIntoConstraints = false

        let tv = NSTextView()
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        tv.textColor = theme.textPrimary
        tv.insertionPointColor = theme.accent
        tv.textContainerInset = NSSize(width: 4, height: 6)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.string = bp.harnessRules.joined(separator: "\n")
        tuningRulesTextView = tv
        editorScroll.documentView = tv

        editorSurface.addSubview(editorScroll)
        NSLayoutConstraint.activate([
            editorSurface.heightAnchor.constraint(equalToConstant: 96),
            editorScroll.topAnchor.constraint(equalTo: editorSurface.topAnchor, constant: 6),
            editorScroll.leadingAnchor.constraint(
                equalTo: editorSurface.leadingAnchor, constant: 8),
            editorScroll.trailingAnchor.constraint(
                equalTo: editorSurface.trailingAnchor, constant: -8),
            editorScroll.bottomAnchor.constraint(equalTo: editorSurface.bottomAnchor, constant: -6),
        ])
        addFullWidth(editorSurface, to: stack)

        let saveBtn = KasugaiFlatButton()
        saveBtn.buttonStyle = .circlePrimary
        saveBtn.customHeight = 28
        saveBtn.horizontalPadding = 14
        saveBtn.configureSymbol("checkmark", title: "設定を保存", pointSize: 11.5, weight: .semibold)
        saveBtn.apply(theme: theme)
        saveBtn.target = self
        saveBtn.action = #selector(handleSaveActiveBlueprintTuning)

        let footRow = NSStackView(views: [makeFlexibleSpacer(), saveBtn])
        footRow.orientation = .horizontal
        footRow.alignment = .centerY
        addFullWidth(footRow, to: stack)

        box.addSubview(stack)
        pin(stack, inside: box, inset: 14)
        return box
    }

    private func makeWaitingInspector(for run: FactoryRunRecord) -> NSView {
        let box = makeSubtlePanel()
        let label = NSTextField(
            wrappingLabelWithString:
                "\(Self.providerDisplayLabel(for: run.workerProvider)) が第 1 周の実装を開始しています。検査結果が届き次第ここに表示されます。"
        )
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = theme.textSecondary
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        pin(label, inside: box, inset: 14)
        return box
    }

    private func makeLogsPanel(logs: [String]) -> NSView {
        let box = makeSubtlePanel()
        let text = logs.isEmpty ? "ログはまだありません。" : logs.suffix(40).joined(separator: "\n")
        let logLabel = NSTextField(wrappingLabelWithString: text)
        logLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logLabel.textColor = theme.textSecondary
        logLabel.isSelectable = true
        logLabel.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(logLabel)
        pin(logLabel, inside: box, inset: 13)
        return box
    }

    private func makeSubtlePanel() -> KasugaiSurfaceView {
        let surface = KasugaiSurfaceView()
        surface.cornerRadius = 12
        surface.strokeWidth = 1
        surface.fillColor = theme.surfaceBg
        surface.strokeColor = theme.borderSubtle
        surface.translatesAutoresizingMaskIntoConstraints = false
        return surface
    }

    private func makeStatTile(label: String, value: String, accent: NSColor? = nil) -> NSView {
        let tile = KasugaiSurfaceView()
        tile.cornerRadius = 8
        tile.strokeWidth = 1
        tile.fillColor = theme.canvasBg
        tile.strokeColor = theme.borderSubtle
        tile.translatesAutoresizingMaskIntoConstraints = false

        let l = NSTextField(labelWithString: label)
        l.font = .systemFont(ofSize: 9.5, weight: .medium)
        l.textColor = theme.textMuted
        l.lineBreakMode = .byTruncatingTail

        let v = NSTextField(labelWithString: value)
        v.font = .monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold)
        v.textColor = accent ?? theme.textPrimary
        v.lineBreakMode = .byTruncatingTail

        let col = NSStackView(views: [l, v])
        col.orientation = .vertical
        col.alignment = .leading
        col.spacing = 2
        col.translatesAutoresizingMaskIntoConstraints = false
        tile.addSubview(col)
        pin(col, inside: tile, inset: 8)
        return tile
    }

    private func makePillLabel(text: String, color: NSColor) -> NSView {
        let pill = KasugaiSurfaceView()
        pill.cornerRadius = 8
        pill.strokeWidth = 1
        pill.fillColor = color.withAlphaComponent(0.13)
        pill.strokeColor = color.withAlphaComponent(0.32)
        pill.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 10.5, weight: .semibold)
        label.textColor = color
        label.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: pill.topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -2),
            label.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -7),
        ])
        return pill
    }

    private func makeLiveTelemetryChip(
        symbol: String,
        text: String,
        tooltip: String,
        captureLabel: Bool
    ) -> NSView {
        let chip = KasugaiSurfaceView()
        chip.cornerRadius = 7
        chip.strokeWidth = 1
        chip.fillColor = theme.surfaceBg
        chip.strokeColor = theme.borderSubtle
        chip.toolTip = tooltip
        chip.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        let cfg = NSImage.SymbolConfiguration(pointSize: 9.5, weight: .semibold)
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: text)?
            .withSymbolConfiguration(cfg)
        icon.contentTintColor = theme.textMuted
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: text)
        label.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
        label.textColor = theme.textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false
        if captureLabel {
            liveElapsedLabel = label
        }

        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        chip.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: chip.topAnchor, constant: 3),
            stack.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: -3),
            stack.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 7),
            stack.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -7),
        ])
        return chip
    }

    private func makeMetricChip(_ text: String) -> NSView {
        let chip = KasugaiSurfaceView()
        chip.cornerRadius = 7
        chip.strokeWidth = 1
        chip.fillColor = theme.surfaceBg
        chip.strokeColor = theme.borderSubtle
        chip.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: text)
        label.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        label.textColor = theme.textSecondary
        label.translatesAutoresizingMaskIntoConstraints = false
        chip.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: chip.topAnchor, constant: 3),
            label.bottomAnchor.constraint(equalTo: chip.bottomAnchor, constant: -3),
            label.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -8),
        ])
        return chip
    }

    private func wrapLeading(_ view: NSView) -> NSView {
        view.setContentHuggingPriority(.required, for: .horizontal)
        let row = NSStackView(views: [view, makeFlexibleSpacer()])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 0
        return row
    }

    private func makeFlexibleSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return spacer
    }

    private func pin(_ child: NSView, inside parent: NSView, inset: CGFloat) {
        NSLayoutConstraint.activate([
            child.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset),
        ])
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

    @objc private func handleBlueprintChanged() {
        let idx = blueprintPopup.indexOfSelectedItem
        guard idx >= 0, idx < blueprints.count else {
            return
        }
        selectedBlueprintId = blueprints[idx].id
        applyBlueprintToDraftControls(blueprints[idx])
    }

    @objc private func handleDuplicateBlueprintClicked() {
        let alert = NSAlert()
        alert.messageText = "新しい工場を作成"
        alert.informativeText = "現在の工場をベースに複製します。工場名を入力してください。"
        alert.addButton(withTitle: "作成")
        alert.addButton(withTitle: "キャンセル")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "例: 脱出ゲーム工場"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
            let created = onDuplicateBlueprint?(selectedBlueprintId, name)
        else {
            return
        }
        selectedBlueprintId = created.id
        refreshBlueprintPopup()
        applyBlueprintToDraftControls(created)
    }

    @objc private func handleOpenBlueprintFileClicked() {
        onOpenBlueprintFile?(selectedBlueprintId)
    }

    @objc private func handleOpenActiveBlueprintJSON() {
        guard let run = currentRun else {
            return
        }
        onOpenBlueprintFile?(run.blueprintId)
    }

    @objc private func handleWorkerProviderChanged() {
        let providerId = selectedProviderId(in: workerPopup, fallback: "opencode_acp")
        let defaultModel = ProviderModelCatalog.shared.defaultModelId(for: providerId)
        reloadModelPopup(
            workerModelPopup,
            providerId: providerId,
            selectedModel: defaultModel,
            storeInto: &workerModelOptions
        )
    }

    @objc private func handleCriticProviderChanged() {
        let providerId = selectedProviderId(in: criticPopup, fallback: "antigravity_acp")
        let defaultModel = ProviderModelCatalog.shared.defaultModelId(for: providerId)
        reloadModelPopup(
            criticModelPopup,
            providerId: providerId,
            selectedModel: defaultModel,
            storeInto: &criticModelOptions
        )
    }

    @objc private func handleToggleDraftRules() {
        isDraftRulesExpanded.toggle()
        rulesContainer.isHidden = !isDraftRulesExpanded
    }

    @objc private func handleSaveDraftBlueprint() {
        var bp = currentBlueprint()
        bp.defaultWorkerProvider = selectedProviderId(
            in: workerPopup, fallback: bp.defaultWorkerProvider)
        bp.defaultWorkerModel = selectedModelId(
            in: workerModelPopup, options: workerModelOptions, fallback: bp.defaultWorkerModel)
        bp.defaultCriticProvider = selectedProviderId(
            in: criticPopup, fallback: bp.defaultCriticProvider)
        bp.defaultCriticModel = selectedModelId(
            in: criticModelPopup, options: criticModelOptions, fallback: bp.defaultCriticModel)
        bp.maxIterations = maxIterPopup.indexOfSelectedItem == 1 ? 5 : 3
        bp.minReviewScore = selectedScoreValue(in: minScorePopup)
        bp.harnessRules = parseRules(from: rulesTextView.string)
        onSaveBlueprint?(bp)
    }

    @objc private func handleSaveActiveBlueprintTuning() {
        guard let run = currentRun else {
            return
        }
        var bp = blueprints.first(where: { $0.id == run.blueprintId }) ?? currentBlueprint()
        if let iterPopup = tuningIterPopup {
            bp.maxIterations = iterPopup.indexOfSelectedItem == 1 ? 5 : 3
        }
        if let scorePopup = tuningScorePopup {
            bp.minReviewScore = selectedScoreValue(in: scorePopup)
        }
        if let tv = tuningRulesTextView {
            bp.harnessRules = parseRules(from: tv.string)
        }
        onSaveBlueprint?(bp)
        selectedDetailTab = .iterations
        rebuildPipelineContent(for: run)
    }

    @objc private func handleStartClicked() {
        submitDraft(demoMode: false)
    }

    @objc private func handleDemoClicked() {
        if promptTextView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let sample = currentBlueprint().placeholderPrompt
                .replacingOccurrences(of: "例: ", with: "")
            promptTextView.string = sample
            updateDraftControls()
        }
        submitDraft(demoMode: true)
    }

    private func submitDraft(demoMode: Bool) {
        guard let run = currentRun else {
            return
        }
        let prompt = promptTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            return
        }
        let bp = currentBlueprint()
        let worker = selectedProviderId(in: workerPopup, fallback: bp.defaultWorkerProvider)
        let workerModel = selectedModelId(
            in: workerModelPopup, options: workerModelOptions, fallback: bp.defaultWorkerModel)
        let critic = selectedProviderId(in: criticPopup, fallback: bp.defaultCriticProvider)
        let criticModel = selectedModelId(
            in: criticModelPopup, options: criticModelOptions, fallback: bp.defaultCriticModel)
        let maxIter = maxIterPopup.indexOfSelectedItem == 1 ? 5 : 3
        let minScore = selectedScoreValue(in: minScorePopup)
        let rules = parseRules(from: rulesTextView.string)
        onStartRun?(
            run.id,
            bp.id,
            prompt,
            worker,
            workerModel,
            critic,
            criticModel,
            maxIter,
            minScore,
            rules,
            demoMode
        )
    }

    @objc private func handleStopClicked() {
        guard let run = currentRun else {
            return
        }
        onStopRun?(run.id)
    }

    @objc private func handleSelectIteration(_ sender: NSButton) {
        selectedDetailTab = .iterations
        selectedIterationIndex = sender.tag
        if let run = currentRun {
            rebuildPipelineContent(for: run)
        }
    }

    @objc private func handleToggleTuningTab() {
        selectedDetailTab = selectedDetailTab == .tuning ? .iterations : .tuning
        if let run = currentRun {
            rebuildPipelineContent(for: run)
        }
    }

    @objc private func handleToggleLogsTab() {
        selectedDetailTab = selectedDetailTab == .logs ? .iterations : .logs
        if let run = currentRun {
            rebuildPipelineContent(for: run)
        }
    }

    @objc private func handleOpenLocalPreviewClicked() {
        guard let run = currentRun else {
            return
        }
        onOpenLocalPreview?(run)
    }

    @objc private func handleOpenExternalURLClicked() {
        guard let run = currentRun,
            let url = run.productionURL ?? run.stagingPreviewURL,
            !url.isEmpty
        else {
            return
        }
        onOpenExternalURL?(url)
    }

    @objc private func handlePublishClicked() {
        guard let run = currentRun else {
            return
        }
        let alert = NSAlert()
        alert.messageText = "\(run.publishTargetLabel) に公開しますか？"
        alert.informativeText = "生成された成果物をそのまま本番環境へ配信します。"
        alert.addButton(withTitle: "公開")
        alert.addButton(withTitle: "キャンセル")
        if alert.runModal() == .alertFirstButtonReturn {
            onPublishRun?(run.id)
        }
    }

    @objc private func handleDiscardClicked() {
        guard let run = currentRun else {
            return
        }
        let alert = NSAlert()
        alert.messageText = "この製造結果を破棄しますか？"
        alert.informativeText = "成果物は採用せず、履歴に破棄済みとして記録します。"
        alert.addButton(withTitle: "破棄")
        alert.addButton(withTitle: "キャンセル")
        if alert.runModal() == .alertFirstButtonReturn {
            onDiscardRun?(run.id)
        }
    }

    @objc private func handleOpenLinkedThread(_ sender: NSButton) {
        let tid = Int64(sender.tag)
        if tid > 0 {
            onSelectThread?(tid)
        }
    }

    @objc private func handleBackToParentRun() {
        if let parentId = currentRun?.parentRunId, !parentId.isEmpty {
            onSelectRun?(parentId)
        }
    }

    @objc private func handleOpenChildRun(_ sender: NSButton) {
        if let childId = sender.toolTip, !childId.isEmpty {
            onSelectRun?(childId)
        }
    }
}
