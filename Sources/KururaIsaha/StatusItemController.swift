import AppKit
import Combine
import KururaCore
import ServiceManagement

/// The menu bar presence, and the gesture that gives the app its name.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let engine: TimerEngine
    private let openWindow: (AppSection) -> Void
    private let overlay = OverlayController()
    private let feedback = Feedback()
    private let reminder = ReminderPrompt()
    private let menu = NSMenu()
    private var cancellables: Set<AnyCancellable> = []
    private var isTracking = false

    private struct TimerAction {
        let id: String
        let seconds: TimeInterval
    }

    init(engine: TimerEngine, openWindow: @escaping (AppSection) -> Void) {
        self.engine = engine
        self.openWindow = openWindow
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        menu.delegate = self
        // Deliberately *not* `statusItem.menu = menu`. A status item that owns a menu opens
        // it on mouseDown and swallows the event, which is precisely the event the whole
        // app is built on. The menu is attached only for the moment it is shown, below.
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(buttonPressed)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
            button.toolTip = "Pull down to set a timer · click for the menu"
        }

        engine.$timers
            .sink { [weak self] timers in self?.refreshAppearance(with: timers) }
            .store(in: &cancellables)

        refreshAppearance(with: engine.timers)
    }

    // MARK: - Appearance

    private func refreshAppearance(with timers: [TimerSnapshot]) {
        guard let button = statusItem.button else { return }

        let active = timers.filter { !$0.isPaused }.min { $0.endsAt < $1.endsAt } ?? timers.first
        guard let active else {
            button.image = pullMark()
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
            return
        }

        let remaining = active.remaining()
        let tint = PullPalette.color(forDuration: active.total)
        button.image = ringImage(progress: active.progress(), tint: active.isPaused ? .secondaryLabelColor : tint)
        button.imagePosition = .imageLeading

        let text = Settings.shared.secondsInMenuBar || remaining < 60
            ? DurationFormat.countdown(remaining)
            : DurationFormat.short(remaining)
        button.attributedTitle = NSAttributedString(
            string: " \(active.isPaused ? "❙❙ " : "")\(text)",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)])

        button.toolTip = "\(active.displayLabel) — ends at \(DurationFormat.clock(active.endsAt))"
    }

    /// The idle mark: the same cord and knob as the app icon, reduced to what survives at
    /// fifteen points. Drawn as a template so macOS handles light bars, dark bars and the
    /// inversion while the menu is open.
    private func pullMark() -> NSImage {
        let image = NSImage(size: NSSize(width: 15, height: 15), flipped: false) { rect in
            NSColor.black.setStroke()
            let cord = NSBezierPath()
            cord.move(to: CGPoint(x: rect.midX, y: rect.maxY - 1))
            cord.line(to: CGPoint(x: rect.midX, y: 6.4))
            cord.lineWidth = 1.7
            cord.lineCapStyle = .round
            cord.stroke()

            NSColor.black.setFill()
            NSBezierPath(ovalIn: CGRect(x: rect.midX - 3.1, y: 1.1, width: 6.2, height: 6.2)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Kurura Isaha — pull down to set a timer"
        return image
    }

    /// A countdown ring, drawn rather than composed from SF Symbols so the sweep is exact.
    private func ringImage(progress: Double, tint: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 15, height: 15), flipped: false) { rect in
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = rect.width / 2 - 1.6

            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = 2
            NSColor.tertiaryLabelColor.setStroke()
            track.stroke()

            let swept = NSBezierPath()
            swept.appendArc(
                withCenter: center, radius: radius,
                startAngle: 90, endAngle: 90 - 360 * CGFloat(min(1, max(0.001, progress))),
                clockwise: true)
            swept.lineWidth = 2
            swept.lineCapStyle = .round
            tint.setStroke()
            swept.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - The pull

    @objc private func buttonPressed() {
        guard let event = NSApp.currentEvent else { showMenu(); return }
        if event.type == .rightMouseDown || event.modifierFlags.contains(.control) {
            showMenu()
            return
        }
        trackPull()
    }

    /// Runs a nested event loop for the lifetime of the drag.
    ///
    /// This is the classic AppKit mouse-tracking idiom, and the only way to see the drag
    /// at all: the status item's button reports mouseDown through its action, and every
    /// subsequent event has to be pulled off the queue by hand.
    private func trackPull() {
        guard !isTracking, let button = statusItem.button, let window = button.window else { return }
        isTracking = true
        defer { isTracking = false }

        let anchorRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let anchor = CGPoint(x: anchorRect.midX, y: anchorRect.minY)
        let anchorScreen = NSScreen.screens.first { $0.frame.contains(anchor) }
            ?? window.screen ?? NSScreen.main ?? NSScreen.screens[0]

        var session = PullSession(
            anchor: anchor,
            anchorScreen: anchorScreen,
            location: NSEvent.mouseLocation,
            modifiers: NSEvent.modifierFlags)

        var didPull = false
        button.highlight(true)
        feedback.pullCancelled()

        tracking: while true {
            // A short timeout rather than `.distantFuture`: it keeps the loop breathing
            // while the hand is still, so a modifier pressed without moving the mouse
            // still registers and the "ends at" clock stays honest.
            let event = NSApp.nextEvent(
                matching: [.leftMouseUp, .leftMouseDragged, .flagsChanged],
                until: Date().addingTimeInterval(0.05),
                inMode: .eventTracking,
                dequeue: true)

            if event?.type == .leftMouseUp { break tracking }
            // Safety net. If the mouseUp is ever delivered somewhere else, the loop must
            // not strand the main thread waiting for an event that will never come.
            if event == nil, NSEvent.pressedMouseButtons & 1 == 0 { break tracking }

            session.location = NSEvent.mouseLocation
            session.modifiers = NSEvent.modifierFlags

            if session.isPull {
                if !didPull {
                    overlay.begin()
                    didPull = true
                }
                overlay.update(session)
                feedback.pullMoved(to: session.reading.duration)
            } else if didPull {
                overlay.update(session)
            }
        }

        button.highlight(false)
        overlay.end()

        if session.isPull {
            commit(session)
        } else if didPull {
            // Dragged back up into the menu bar: the gesture's own undo.
            feedback.pullCancelled()
        } else {
            showMenu()
        }
    }

    private func commit(_ session: PullSession) {
        feedback.pullCommitted()
        let timer = engine.start(
            duration: session.reading.duration,
            kind: session.kind,
            bindsFocus: session.bindsFocus)

        guard Settings.shared.askForReminder else { return }
        // The timer is already running. This only gives it a name, and only if the user
        // feels like offering one.
        let screen = NSScreen.screens.first { $0.frame.contains(session.location) }
            ?? session.anchorScreen
        reminder.ask(for: timer, near: session.lineEnd, on: screen) { [weak self] text in
            self?.engine.setNote(text, on: timer.id)
        }
    }

    private func showMenu() {
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let timers = engine.timers.sorted { $0.endsAt < $1.endsAt }
        if timers.isEmpty {
            menu.addItem(header("Pull down from the icon to set a timer"))
            menu.addItem(header("⌥ snap to 5m   ⇧ bind Focus   ⌘ set an alarm"))
        } else {
            for timer in timers { menu.addItem(timerItem(timer)) }
        }

        menu.addItem(.separator())
        menu.addItem(presetsItem())
        if engine.isAlarmSounding {
            menu.addItem(item("Stop Alarm", #selector(stopAlarm), key: ""))
        }

        menu.addItem(.separator())
        menu.addItem(item("Analytics…", #selector(openAnalytics), key: "a"))
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))

        menu.addItem(.separator())
        let login = item("Start at Login", #selector(toggleLoginItem), key: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("Quit Kurura Isaha", #selector(quit), key: "q"))
    }

    private func timerItem(_ timer: TimerSnapshot) -> NSMenuItem {
        // A reminder can be a whole sentence; the menu should not stretch to fit it.
        let label = truncated(timer.displayLabel, to: 34)
        let parent = NSMenuItem(
            title: "\(DurationFormat.countdown(timer.remaining()))   \(label)",
            action: nil, keyEquivalent: "")

        let submenu = NSMenu()
        if timer.hasNote { submenu.addItem(header(timer.displayLabel)) }
        submenu.addItem(header("Ends at \(DurationFormat.clock(timer.endsAt))"))
        submenu.addItem(header("\(DurationFormat.short(timer.total)) · \(timer.preset) · \(timer.id)"))
        submenu.addItem(.separator())

        for minutes in [5, 15] {
            let add = item("Add \(minutes) Minutes", #selector(extendTimer(_:)), key: "")
            add.representedObject = TimerAction(id: timer.id, seconds: Double(minutes) * 60)
            submenu.addItem(add)
        }

        let toggle = item(timer.isPaused ? "Resume" : "Pause", #selector(togglePause(_:)), key: "")
        toggle.representedObject = TimerAction(id: timer.id, seconds: 0)
        submenu.addItem(toggle)

        submenu.addItem(.separator())
        let cancel = item("Cancel Timer", #selector(cancelTimer(_:)), key: "")
        cancel.representedObject = TimerAction(id: timer.id, seconds: 0)
        submenu.addItem(cancel)

        parent.submenu = submenu
        return parent
    }

    private func presetsItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Start a Timer", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for minutes in [5, 15, 25, 45, 60, 90] {
            let entry = item(DurationFormat.short(Double(minutes) * 60), #selector(startPreset(_:)), key: "")
            entry.representedObject = Double(minutes) * 60
            submenu.addItem(entry)
        }
        parent.submenu = submenu
        return parent
    }

    private func truncated(_ text: String, to limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
    }

    private func header(_ title: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.isEnabled = false
        return entry
    }

    private func item(_ title: String, _ action: Selector, key: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self
        return entry
    }

    // MARK: - Actions

    @objc private func startPreset(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? TimeInterval else { return }
        engine.start(duration: seconds)
    }

    @objc private func extendTimer(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? TimerAction else { return }
        _ = engine.extend(id: action.id, by: action.seconds)
    }

    @objc private func togglePause(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? TimerAction else { return }
        if !engine.pause(id: action.id) { _ = engine.resume(id: action.id) }
    }

    @objc private func cancelTimer(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? TimerAction else { return }
        engine.cancel(id: action.id)
    }

    @objc private func stopAlarm() { engine.dismissAlarm() }
    @objc private func openAnalytics() { openWindow(.analytics) }
    @objc private func openSettings() { openWindow(.settings) }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change the login item"
            alert.informativeText = """
                \(error.localizedDescription)

                Login item registration needs the app to live somewhere stable. Move \
                Kurura Isaha.app into /Applications and try again.
                """
            alert.alertStyle = .warning
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}
