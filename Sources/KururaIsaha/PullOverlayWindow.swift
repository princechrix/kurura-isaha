import AppKit
import KururaCore
import SwiftUI

/// A transparent, click-through panel covering exactly one screen.
///
/// `.nonactivatingPanel` plus `ignoresMouseEvents` is what keeps the pull from stealing
/// focus: the frontmost app never resigns key, so a pull started while typing does not
/// interrupt the typing. The level sits above `.mainMenu` so the line can be drawn over
/// the menu bar it starts from.
final class PullOverlayWindow: NSPanel {
    let owningScreen: NSScreen

    private let lineView = PullLineView()
    private let hudShadow = NSView()
    private let glass = NSVisualEffectView()
    private var hostingView: NSHostingView<HUDView>?

    init(screen: NSScreen) {
        owningScreen = screen
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)

        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        worksWhenModal = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        setFrame(screen.frame, display: false)

        let container = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        container.autoresizingMask = [.width, .height]

        lineView.frame = container.bounds
        lineView.autoresizingMask = [.width, .height]
        container.addSubview(lineView)

        // The rounded glass cannot cast its own shadow while it is masking its corners,
        // so the shadow lives on a wrapper one level up.
        hudShadow.wantsLayer = true
        hudShadow.layer?.shadowColor = NSColor.black.cgColor
        hudShadow.layer?.shadowOpacity = 0.32
        hudShadow.layer?.shadowRadius = 18
        hudShadow.layer?.shadowOffset = CGSize(width: 0, height: -6)
        hudShadow.isHidden = true

        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 16
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true
        glass.layer?.borderWidth = 1
        glass.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor

        hudShadow.addSubview(glass)
        container.addSubview(hudShadow)
        contentView = container
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: - Rendering

    func render(_ session: PullSession, showHUD: Bool) {
        lineView.update(session, screenOrigin: owningScreen.frame.origin)

        guard showHUD, session.isPull else {
            hudShadow.isHidden = true
            return
        }

        let card = HUDView(
            reading: session.reading,
            kind: session.kind,
            snapping: session.modifiers.contains(.option),
            bindsFocus: session.bindsFocus)

        let host: NSHostingView<HUDView>
        if let hostingView {
            hostingView.rootView = card
            host = hostingView
        } else {
            host = NSHostingView(rootView: card)
            glass.addSubview(host)
            hostingView = host
        }

        let size = host.fittingSize
        hudShadow.frame = CGRect(origin: position(for: session, size: size), size: size)
        glass.frame = hudShadow.bounds
        host.frame = glass.bounds
        hudShadow.isHidden = false
    }

    func clear() {
        lineView.clear()
        hudShadow.isHidden = true
    }

    // MARK: - Placement

    /// Beside the cursor, flipped to the other side rather than allowed to run off the
    /// edge, and always inside the safe area so a notch never clips the card.
    private func position(for session: PullSession, size: CGSize) -> CGPoint {
        let origin = owningScreen.frame.origin
        let cursor = CGPoint(x: session.location.x - origin.x, y: session.location.y - origin.y)
        let safe = safeRect()
        let margin: CGFloat = 12

        var x = cursor.x + 26
        if x + size.width > safe.maxX - margin {
            x = cursor.x - 26 - size.width
        }
        let maxX = max(safe.minX + margin, safe.maxX - size.width - margin)
        let maxY = max(safe.minY + margin, safe.maxY - size.height - margin)

        return CGPoint(
            x: min(max(x, safe.minX + margin), maxX),
            y: min(max(cursor.y - size.height / 2, safe.minY + margin), maxY))
    }

    private func safeRect() -> CGRect {
        let insets = owningScreen.safeAreaInsets
        var rect = CGRect(origin: .zero, size: owningScreen.frame.size)
        rect.origin.x += insets.left
        rect.size.width -= insets.left + insets.right
        rect.origin.y += insets.bottom
        rect.size.height -= insets.top + insets.bottom
        return rect
    }
}
