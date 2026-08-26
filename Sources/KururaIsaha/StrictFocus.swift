import AppKit
import Foundation

/// Pushes distracting apps back out of the way while a timer runs.
///
/// Honest about what it is: this watches for a blocked app coming to the front and hides
/// it again. It is a speed bump, not a sandbox. Actually *preventing* an app from
/// launching needs the Screen Time (`FamilyControls`) entitlement, which Apple grants by
/// request, and blocking websites needs either a root-owned helper editing `/etc/hosts` or
/// a Network Extension content filter. Neither belongs in a menu bar timer that anyone can
/// build and run themselves, so the README says so plainly rather than the app pretending.
final class StrictFocus {
    private var observer: NSObjectProtocol?
    private var lastNudge = Date.distantPast
    private(set) var isEngaged = false

    func setEngaged(_ engaged: Bool) {
        guard Settings.shared.strictFocus else {
            disengage()
            return
        }
        engaged ? engage() : disengage()
    }

    private func engage() {
        guard !isEngaged else { return }
        isEngaged = true
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            self?.intercept(app)
        }
    }

    private func disengage() {
        guard isEngaged else { return }
        isEngaged = false
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    private func intercept(_ app: NSRunningApplication) {
        guard let identifier = app.bundleIdentifier,
              Settings.shared.blockedApps.contains(identifier) else { return }
        app.hide()

        // One nudge per app per twenty seconds. Somebody hammering Command-Tab should not
        // be able to fill Notification Centre with their own frustration.
        guard Date().timeIntervalSince(lastNudge) > 20 else { return }
        lastNudge = Date()
        Notifier.shared.post(
            title: "Blocked while focusing",
            body: "\(app.localizedName ?? identifier) is on your Strict Focus list. "
                + "Cancel the timer from the menu bar if you really need it.",
            identifier: "strict-\(identifier)")
    }

    /// The escape hatch, deliberately made annoying: turning Strict Focus off mid-session
    /// means typing the phrase out. Long enough to interrupt an impulse, short enough not
    /// to be cruel.
    static func confirmDisable() -> Bool {
        let phrase = Settings.shared.panicPhrase
        guard !phrase.isEmpty else { return true }

        let alert = NSAlert()
        alert.messageText = "Turn off Strict Focus?"
        alert.informativeText = "Type “\(phrase)” to unblock your apps before the timer is done."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Unblock")
        alert.addButton(withTitle: "Keep Focusing")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = phrase
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        return field.stringValue.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(phrase) == .orderedSame
    }
}
