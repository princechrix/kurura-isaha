import AppKit
import Foundation

/// Keeps one overlay panel per display alive for the duration of a pull.
///
/// One window per screen rather than one giant window spanning the union: a single window
/// covering a mixed-DPI, non-rectangular arrangement gets clipped at the seams, and each
/// panel drawing its own slice of the same global line joins up correctly for free.
final class OverlayController {
    private var windows: [PullOverlayWindow] = []
    private var builtFor: [CGRect] = []

    func begin() {
        ensureWindows()
        windows.forEach { $0.orderFrontRegardless() }
    }

    func update(_ session: PullSession) {
        let cursorScreen = NSScreen.screens.first { $0.frame.contains(session.location) }
        let showHUD = Settings.shared.showHUD
        for window in windows {
            // The card belongs to whichever screen the cursor is actually on; the others
            // only draw their share of the line.
            let ownsCursor = cursorScreen?.frame == window.owningScreen.frame
            window.render(session, showHUD: showHUD && ownsCursor)
        }
    }

    func end() {
        for window in windows {
            window.clear()
            window.orderOut(nil)
        }
    }

    /// Screens come and go — a display is unplugged, a projector arrives, the arrangement
    /// changes. Frames are the cheapest stable identity for that.
    private func ensureWindows() {
        let frames = NSScreen.screens.map(\.frame)
        guard frames != builtFor else { return }

        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map { PullOverlayWindow(screen: $0) }
        builtFor = frames
    }
}
