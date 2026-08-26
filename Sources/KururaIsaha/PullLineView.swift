import AppKit
import Foundation
import KururaCore

/// Draws the pull: a dashed rail showing how far the gesture can reach, tick marks at the
/// durations worth aiming for, and the live line from the menu bar to the cursor.
///
/// The line is filled with a gradient sampled from the scale itself, so the colour at any
/// point on it is the colour of the duration that point represents. It doubles as the
/// legend for a scale that is otherwise invisible.
final class PullLineView: NSView {
    private static let notableDurations: [TimeInterval] = [
        5 * 60, 15 * 60, 30 * 60, 60 * 60, 2 * 3600, 4 * 3600,
    ]

    private var session: PullSession?
    private var screenOrigin: CGPoint = .zero

    func update(_ session: PullSession, screenOrigin: CGPoint) {
        self.session = session
        self.screenOrigin = screenOrigin
        needsDisplay = true
    }

    func clear() {
        session = nil
        needsDisplay = true
    }

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    private func local(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - screenOrigin.x, y: point.y - screenOrigin.y)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let session, session.isPull,
              let context = NSGraphicsContext.current?.cgContext else { return }

        let anchor = local(session.anchor)
        let end = local(session.lineEnd)
        let reading = session.reading
        let tint = PullPalette.color(forDuration: reading.duration)

        drawRail(context, anchor: anchor, travel: session.travel)
        drawTicks(context, session: session, anchor: anchor, reached: reading.distance)
        drawLine(context, session: session, from: anchor, to: end, tint: tint)
        drawKnob(context, at: end, tint: tint)
    }

    // MARK: - Pieces

    private func drawRail(_ context: CGContext, anchor: CGPoint, travel: CGFloat) {
        context.saveGState()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.10).cgColor)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [3, 6])
        context.move(to: anchor)
        context.addLine(to: CGPoint(x: anchor.x, y: anchor.y - travel))
        context.strokePath()
        context.restoreGState()
    }

    private func drawTicks(_ context: CGContext, session: PullSession, anchor: CGPoint, reached: CGFloat) {
        for mark in Self.notableDurations {
            let offset = session.scale.distance(for: mark)
            guard offset <= session.travel + 1 else { continue }

            let y = anchor.y - offset
            let passed = reached >= offset
            let base = passed ? PullPalette.color(forDuration: mark) : NSColor.white
            let stroke = base.withAlphaComponent(passed ? 0.9 : 0.2)

            context.saveGState()
            context.setStrokeColor(stroke.cgColor)
            context.setLineWidth(passed ? 2 : 1)
            context.move(to: CGPoint(x: anchor.x - 9, y: y))
            context.addLine(to: CGPoint(x: anchor.x + 9, y: y))
            context.strokePath()
            context.restoreGState()

            let label = DurationFormat.short(mark) as NSString
            label.draw(at: CGPoint(x: anchor.x + 15, y: y - 6), withAttributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
                .foregroundColor: base.withAlphaComponent(passed ? 0.95 : 0.3),
            ])
        }
    }

    private func drawLine(
        _ context: CGContext,
        session: PullSession,
        from anchor: CGPoint,
        to end: CGPoint,
        tint: NSColor
    ) {
        let path = CGMutablePath()
        path.move(to: anchor)
        path.addLine(to: end)

        context.saveGState()
        context.setStrokeColor(tint.withAlphaComponent(0.26).cgColor)
        context.setLineWidth(12)
        context.setLineCap(.round)
        context.addPath(path)
        context.strokePath()
        context.restoreGState()

        let stroked = path.copy(
            strokingWithWidth: 3.5, lineCap: .round, lineJoin: .round, miterLimit: 10)

        context.saveGState()
        context.addPath(stroked)
        context.clip()
        gradient(for: session).draw(from: anchor, to: end, options: [])
        context.restoreGState()
    }

    private func drawKnob(_ context: CGContext, at point: CGPoint, tint: NSColor) {
        let knob = CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)

        context.saveGState()
        context.setShadow(offset: .zero, blur: 10, color: tint.withAlphaComponent(0.85).cgColor)
        context.setFillColor(tint.cgColor)
        context.fillEllipse(in: knob)
        context.restoreGState()

        context.saveGState()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.92).cgColor)
        context.setLineWidth(1.5)
        context.strokeEllipse(in: knob.insetBy(dx: -1.5, dy: -1.5))
        context.restoreGState()
    }

    /// Colour stops sampled along the scale, so the line reads as its own legend.
    private func gradient(for session: PullSession) -> NSGradient {
        let steps = 8
        var colors: [NSColor] = []
        var locations: [CGFloat] = []
        for step in 0...steps {
            let fraction = CGFloat(step) / CGFloat(steps)
            let duration = session.scale.rawDuration(for: session.distance * fraction)
            colors.append(PullPalette.color(forDuration: duration))
            locations.append(fraction)
        }
        let built = locations.withUnsafeBufferPointer { buffer in
            NSGradient(colors: colors, atLocations: buffer.baseAddress, colorSpace: .sRGB)
        }
        return built ?? NSGradient(starting: colors.first ?? .white, ending: colors.last ?? .white)!
    }
}
