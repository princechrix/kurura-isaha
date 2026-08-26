import AppKit
import Foundation

/// The app icon, drawn in code rather than shipped as a binary asset.
///
/// It is the pull the app is named after: a cord hanging out of the menu bar with a small
/// clock on the end of it, looking mildly alarmed about the whole business. Keeping it as
/// code means the icon is diffable, regenerates on every build, and can drop detail at the
/// small sizes the way a hand-tuned iconset would — a face that is charming at 512px is
/// mud at 16px, so below 64px it degrades to the plain mark.
enum IconArtwork {
    /// Everything is laid out against a 1024 grid and scaled from there.
    private static let grid: CGFloat = 1024

    private enum Palette {
        static let groundTop = NSColor(srgbRed: 0.25, green: 0.19, blue: 0.37, alpha: 1)
        static let groundBottom = NSColor(srgbRed: 0.10, green: 0.07, blue: 0.19, alpha: 1)
        static let brief = NSColor(srgbRed: 0.24, green: 0.82, blue: 0.73, alpha: 1)
        static let middling = NSColor(srgbRed: 0.98, green: 0.70, blue: 0.25, alpha: 1)
        static let lengthy = NSColor(srgbRed: 0.96, green: 0.36, blue: 0.47, alpha: 1)
        static let face = NSColor(srgbRed: 1.00, green: 0.96, blue: 0.91, alpha: 1)
        static let ink = NSColor(srgbRed: 0.17, green: 0.13, blue: 0.27, alpha: 1)
    }

    /// The sizes an `.icns` wants, and the names `iconutil` expects.
    static let iconsetEntries: [(name: String, pixels: Int)] = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]

    static func writeIconset(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for entry in iconsetEntries {
            guard let data = png(size: entry.pixels) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try data.write(to: directory.appendingPathComponent(entry.name))
        }
    }

    static func png(size: Int) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }

        rep.size = NSSize(width: size, height: size)
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        draw(into: context.cgContext, pixels: CGFloat(size))
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Drawing

    private static func draw(into context: CGContext, pixels: CGFloat) {
        let scale = pixels / grid
        func s(_ value: CGFloat) -> CGFloat { value * scale }

        // A face is charming at 512 and illegible at 16. Small sizes get the bare mark,
        // which is what a hand-tuned iconset would do anyway.
        let showsFace = pixels >= 64
        let showsDetail = pixels >= 128

        let body = CGRect(x: s(92), y: s(92), width: s(840), height: s(840))
        drawGround(context, body: body)

        let barY = s(812)
        if showsDetail { drawBar(context, centreX: s(512), y: barY, width: s(420), height: s(20)) }

        let clockCentre = CGPoint(x: s(512), y: s(342))
        let clockRadius = s(170)

        drawCord(context, from: CGPoint(x: s(512), y: barY), to: clockCentre, width: s(30))
        drawClock(
            context,
            centre: clockCentre,
            radius: clockRadius,
            showsFace: showsFace,
            showsDetail: showsDetail,
            scale: scale)

        if showsDetail { drawWobble(context, centre: clockCentre, radius: clockRadius, scale: scale) }
    }

    private static func drawGround(_ context: CGContext, body: CGRect) {
        context.saveGState()
        context.addPath(squircle(in: body))
        context.clip()
        gradient([Palette.groundBottom, Palette.groundTop])?
            .draw(from: CGPoint(x: body.midX, y: body.minY),
                  to: CGPoint(x: body.midX, y: body.maxY),
                  options: [])
        context.restoreGState()
    }

    private static func drawBar(
        _ context: CGContext, centreX: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat
    ) {
        let rect = CGRect(x: centreX - width / 2, y: y - height / 2, width: width, height: height)
        context.saveGState()
        context.setFillColor(NSColor.white.withAlphaComponent(0.22).cgColor)
        context.addPath(CGPath(
            roundedRect: rect, cornerWidth: height / 2, cornerHeight: height / 2, transform: nil))
        context.fillPath()
        context.restoreGState()
    }

    /// The cord, carrying the same teal-to-rose ramp the app draws while you drag.
    private static func drawCord(
        _ context: CGContext, from top: CGPoint, to clock: CGPoint, width: CGFloat
    ) {
        let path = CGMutablePath()
        path.move(to: top)
        path.addLine(to: clock)
        let stroked = path.copy(
            strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)

        context.saveGState()
        context.addPath(stroked)
        context.clip()
        gradient([Palette.brief, Palette.middling, Palette.lengthy])?
            .draw(from: top, to: clock, options: [])
        context.restoreGState()
    }

    private static func drawClock(
        _ context: CGContext,
        centre: CGPoint,
        radius: CGFloat,
        showsFace: Bool,
        showsDetail: Bool,
        scale: CGFloat
    ) {
        func s(_ value: CGFloat) -> CGFloat { value * scale }

        // Stretched very slightly along the pull. Squash and stretch is the cheapest way
        // to make a static shape look like it is being dragged.
        let bezel = CGRect(
            x: centre.x - radius,
            y: centre.y - radius * 1.05,
            width: radius * 2,
            height: radius * 2 * 1.05)

        context.saveGState()
        context.setShadow(
            offset: .zero, blur: s(70), color: Palette.lengthy.withAlphaComponent(0.55).cgColor)
        context.addEllipse(in: bezel)
        context.clip()
        gradient([Palette.lengthy, Palette.middling])?
            .draw(from: CGPoint(x: bezel.midX, y: bezel.minY),
                  to: CGPoint(x: bezel.midX, y: bezel.maxY),
                  options: [])
        context.restoreGState()

        let dial = bezel.insetBy(dx: s(34), dy: s(34))
        context.saveGState()
        context.setFillColor(Palette.face.cgColor)
        context.fillEllipse(in: dial)
        context.restoreGState()

        if showsDetail {
            // A single hairline ring says "dial" without competing with the face. Twelve
            // tick marks around a pair of eyes just reads as a wall socket.
            context.saveGState()
            context.setStrokeColor(Palette.ink.withAlphaComponent(0.13).cgColor)
            context.setLineWidth(s(7))
            context.strokeEllipse(in: dial.insetBy(dx: s(14), dy: s(14)))
            context.restoreGState()
        }

        guard showsFace else { return }

        // Big eyes with a catchlight high on each one. The highlight is what turns two
        // dark circles into a gaze — without it they are holes, and the whole face reads
        // as hardware rather than a character.
        let eyeRadius = s(40)
        let eyeY = centre.y + s(38)
        for offset in [-s(56), s(56)] {
            let eye = CGRect(
                x: centre.x + offset - eyeRadius, y: eyeY - eyeRadius,
                width: eyeRadius * 2, height: eyeRadius * 2)
            context.setFillColor(Palette.ink.cgColor)
            context.fillEllipse(in: eye)

            let spark = s(14)
            context.setFillColor(NSColor.white.withAlphaComponent(0.92).cgColor)
            context.fillEllipse(in: CGRect(
                x: eye.midX - s(12) - spark, y: eye.midY + s(11) - spark,
                width: spark * 2, height: spark * 2))
        }

        // Small round mouth, clearly smaller than the eyes so the three shapes never line
        // up into a socket again.
        context.setFillColor(Palette.ink.withAlphaComponent(0.88).cgColor)
        context.fillEllipse(in: CGRect(
            x: centre.x - s(19), y: centre.y - s(88),
            width: s(38), height: s(46)))
    }

    /// Swing lines, the way a cartoon shows something still moving.
    ///
    /// They sit out to the sides rather than above the head. Arcs placed over the face
    /// stop reading as motion and start reading as a pair of detached eyebrows, and a
    /// pendulum swings sideways anyway.
    private static func drawWobble(
        _ context: CGContext, centre: CGPoint, radius: CGFloat, scale: CGFloat
    ) {
        context.saveGState()
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.26).cgColor)
        context.setLineWidth(scale * 13)
        context.setLineCap(.round)
        for side in [CGFloat(0), .pi] {
            context.addArc(
                center: centre, radius: radius * 1.42,
                startAngle: side - 0.34, endAngle: side + 0.34,
                clockwise: false)
            context.strokePath()
        }
        context.restoreGState()
    }

    // MARK: - Shapes

    /// A superellipse rather than a rounded rectangle. Apple's icon shape has continuous
    /// curvature, and circular corners next to a real Dock icon look visibly wrong.
    private static func squircle(in rect: CGRect, exponent: CGFloat = 5) -> CGPath {
        let path = CGMutablePath()
        let a = rect.width / 2
        let b = rect.height / 2
        let steps = 720

        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps) * 2 * .pi
            let cosine = cos(t)
            let sine = sin(t)
            let x = rect.midX + a * pow(abs(cosine), 2 / exponent) * (cosine < 0 ? -1 : 1)
            let y = rect.midY + b * pow(abs(sine), 2 / exponent) * (sine < 0 ? -1 : 1)
            if step == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        path.closeSubpath()
        return path
    }

    private static func gradient(_ colors: [NSColor]) -> NSGradient? {
        NSGradient(colors: colors)
    }
}
