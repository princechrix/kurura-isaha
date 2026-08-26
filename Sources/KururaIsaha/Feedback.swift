import AppKit
import Foundation

/// The clicks felt and heard while a pull crosses minute boundaries.
///
/// `NSHapticFeedbackManager` only ever reaches a Force Touch trackpad — on a mouse the
/// haptic call is a no-op, which is why the audio tick is a separate switch rather than
/// a fallback for the same setting.
final class Feedback {
    private var lastMark: Int = .min
    private let tick = NSSound(named: "Tink")

    /// Call on every frame of a drag; it debounces itself against the last whole minute.
    func pullMoved(to duration: TimeInterval) {
        let mark = Int(duration / 60)
        guard mark != lastMark else { return }
        let isFirstFrame = lastMark == .min
        lastMark = mark
        guard !isFirstFrame else { return }

        if Settings.shared.haptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        if Settings.shared.tickSounds, let tick {
            // Restart rather than overlap: a fast drag would otherwise stack a dozen
            // copies of the same click on top of each other.
            tick.stop()
            tick.play()
        }
    }

    /// A firmer click for the moment the timer is actually committed.
    func pullCommitted() {
        lastMark = .min
        if Settings.shared.haptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }

    func pullCancelled() {
        lastMark = .min
    }
}
