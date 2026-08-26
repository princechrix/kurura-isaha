import AppKit
import KururaCore

/// The card that appears where a pull was released, asking what the timer is for.
///
/// The timer is already running by the time this shows up. The prompt only names it — it
/// never gates it. Ignore the card and it takes itself away with the automatic tag intact,
/// which is the whole difference between an optional label and a modal dialog.
///
/// Built in AppKit rather than SwiftUI: a text field inside a non-activating panel has to
/// take first responder deterministically, and `@FocusState` in a hosted view is one more
/// timing question than this needs to answer.
final class ReminderPrompt: NSObject, NSTextFieldDelegate {
    /// How long an untouched card waits before deciding the answer was "leave it". The
    /// clock stops the moment anything is typed, so nobody gets cut off mid-thought.
    private static let patience: TimeInterval = 8
    private static let width: CGFloat = 300
    private static let height: CGFloat = 104

    private var panel: PromptPanel?
    private let caption = NSTextField(labelWithString: "")
    private let field = NSTextField()
    private let hint = NSTextField(labelWithString: "↩ save    esc leave it")

    private var commit: ((String) -> Void)?
    private var timeout: DispatchSourceTimer?
    private var isShowing = false

    // MARK: - Showing

    func ask(
        for timer: TimerSnapshot,
        near point: CGPoint,
        on screen: NSScreen,
        commit: @escaping (String) -> Void
    ) {
        // A second pull while the first card is open keeps whatever was typed into it.
        dismiss(saving: true)

        let panel = self.panel ?? build()
        self.panel = panel
        self.commit = commit

        caption.stringValue = timer.kind == .alarm
            ? "Alarm set · rings at \(DurationFormat.clock(timer.endsAt))"
            : "\(DurationFormat.short(timer.total)) running · ends at \(DurationFormat.clock(timer.endsAt))"
        field.stringValue = ""

        panel.setFrameOrigin(origin(near: point, on: screen, size: panel.frame.size))
        isShowing = true
        // `.nonactivatingPanel` is what lets this take keystrokes without pulling the
        // frontmost app out from under whatever the user was doing.
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
        startTimeout()
    }

    private func dismiss(saving: Bool) {
        guard isShowing else { return }
        isShowing = false
        stopTimeout()

        let text = saving
            ? field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let action = commit
        commit = nil
        panel?.orderOut(nil)
        if !text.isEmpty { action?(text) }
    }

    // MARK: - Text field

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            dismiss(saving: true)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss(saving: false)
            return true
        default:
            return false
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        // Somebody is thinking. Stop counting.
        stopTimeout()
    }

    // MARK: - Timeout

    private func startTimeout() {
        stopTimeout()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + Self.patience)
        timer.setEventHandler { [weak self] in self?.dismiss(saving: false) }
        timer.resume()
        timeout = timer
    }

    private func stopTimeout() {
        timeout?.cancel()
        timeout = nil
    }

    // MARK: - Placement

    /// Beside the release point, flipped rather than allowed to run off the edge, and
    /// inside the safe area so a notch never clips it.
    private func origin(near point: CGPoint, on screen: NSScreen, size: CGSize) -> CGPoint {
        let insets = screen.safeAreaInsets
        var safe = screen.frame
        safe.origin.x += insets.left
        safe.size.width -= insets.left + insets.right
        safe.origin.y += insets.bottom
        safe.size.height -= insets.top + insets.bottom

        let margin: CGFloat = 12
        var x = point.x + 26
        if x + size.width > safe.maxX - margin { x = point.x - 26 - size.width }
        let maxX = max(safe.minX + margin, safe.maxX - size.width - margin)
        let maxY = max(safe.minY + margin, safe.maxY - size.height - margin)

        return CGPoint(
            x: min(max(x, safe.minX + margin), maxX),
            y: min(max(point.y - size.height / 2, safe.minY + margin), maxY))
    }

    // MARK: - Construction

    private func build() -> PromptPanel {
        let bounds = NSRect(x: 0, y: 0, width: Self.width, height: Self.height)
        let panel = PromptPanel(
            contentRect: bounds,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.worksWhenModal = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let glass = NSVisualEffectView(frame: bounds)
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 14
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true
        glass.layer?.borderWidth = 1
        glass.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor

        caption.frame = NSRect(x: 16, y: 75, width: Self.width - 32, height: 15)
        caption.font = .systemFont(ofSize: 11)
        caption.textColor = .secondaryLabelColor
        caption.lineBreakMode = .byTruncatingTail

        let well = NSView(frame: NSRect(x: 14, y: 36, width: Self.width - 28, height: 30))
        well.wantsLayer = true
        well.layer?.cornerRadius = 8
        well.layer?.cornerCurve = .continuous
        well.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        well.layer?.borderWidth = 1
        well.layer?.borderColor = NSColor.white.withAlphaComponent(0.10).cgColor

        field.frame = NSRect(x: 24, y: 41, width: Self.width - 48, height: 19)
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.placeholderString = "What is this for?"
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingTail
        field.delegate = self

        hint.frame = NSRect(x: 16, y: 15, width: Self.width - 32, height: 13)
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor

        glass.addSubview(caption)
        glass.addSubview(well)
        glass.addSubview(field)
        glass.addSubview(hint)
        panel.contentView = glass

        // Clicking back into another app is an answer too: keep whatever was typed rather
        // than throwing it away for the sake of a rule.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.dismiss(saving: true)
        }

        return panel
    }
}

/// A borderless panel still has to be allowed to take the keyboard, which is the one thing
/// `.borderless` otherwise rules out.
final class PromptPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
