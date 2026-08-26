import AppKit
import Foundation
import KururaCore

/// One in-flight drag, from mouseDown on the status item to mouseUp anywhere.
///
/// A value type on purpose: the tracking loop rebuilds it on every event and hands a copy
/// to the overlay, so nothing downstream can mutate the gesture out from under the loop.
struct PullSession {
    /// Bottom-centre of the status item, in screen coordinates.
    let anchor: CGPoint
    /// The screen the status item lives on, which sets how far a full pull reaches.
    let anchorScreen: NSScreen
    var location: CGPoint
    var modifiers: NSEvent.ModifierFlags

    init(anchor: CGPoint, anchorScreen: NSScreen, location: CGPoint, modifiers: NSEvent.ModifierFlags) {
        self.anchor = anchor
        self.anchorScreen = anchorScreen
        self.location = location
        self.modifiers = modifiers
    }

    /// Usable pull height: the status item down to the bottom of its own screen. Dragging
    /// onto a display below simply saturates rather than running a second scale.
    var travel: CGFloat { max(200, anchor.y - anchorScreen.frame.minY) }

    /// Positive downwards, which is the direction the whole gesture is named after.
    var distance: CGFloat { anchor.y - location.y }

    var scale: PullScale {
        PullScale(
            mode: Settings.shared.scalingMode,
            travel: travel,
            snapToFiveMinutes: modifiers.contains(.option))
    }

    var reading: PullReading { PullReading(distance: distance, scale: scale) }

    /// Command turns the pull into "wake me at a time" rather than "in this long".
    var kind: TimerKind { modifiers.contains(.command) ? .alarm : .timer }

    /// Shift binds the macOS Focus shortcut to this timer's lifetime.
    var bindsFocus: Bool { modifiers.contains(.shift) }

    /// Below the threshold the gesture is still a click, and mouseUp should open the menu.
    var isPull: Bool { distance > PullScale.dragThreshold }

    /// Where the line should stop. Clamped to the anchor so an upward drag does not draw
    /// a line into the menu bar itself.
    var lineEnd: CGPoint {
        CGPoint(x: location.x, y: min(location.y, anchor.y))
    }
}

/// The colours a pull moves through as it gets longer.
enum PullPalette {
    static let brief = NSColor(srgbRed: 0.24, green: 0.82, blue: 0.73, alpha: 1)
    static let middling = NSColor(srgbRed: 0.98, green: 0.70, blue: 0.25, alpha: 1)
    static let lengthy = NSColor(srgbRed: 0.96, green: 0.36, blue: 0.47, alpha: 1)

    /// Position of a duration on the 1 min … 4 h log scale, 0…1.
    static func progress(forDuration duration: TimeInterval) -> CGFloat {
        let ratio = log(max(duration, PullScale.minimum) / PullScale.minimum)
            / log(PullScale.maximum / PullScale.minimum)
        return CGFloat(min(1, max(0, ratio)))
    }

    /// Teal through amber to rose. The midpoint lands on fifteen minutes, which is exactly
    /// where the presets stop being "a quick thing" and start being "a block of work".
    static func color(forDuration duration: TimeInterval) -> NSColor {
        let position = progress(forDuration: duration)
        if position < 0.5 { return blend(brief, middling, position / 0.5) }
        return blend(middling, lengthy, (position - 0.5) / 0.5)
    }

    private static func blend(_ from: NSColor, _ to: NSColor, _ amount: CGFloat) -> NSColor {
        let t = min(1, max(0, amount))
        return NSColor(
            srgbRed: from.redComponent + (to.redComponent - from.redComponent) * t,
            green: from.greenComponent + (to.greenComponent - from.greenComponent) * t,
            blue: from.blueComponent + (to.blueComponent - from.blueComponent) * t,
            alpha: 1)
    }
}
