import AppKit
import Foundation
import KururaCore
import UserNotifications

/// Delivers the "time is up" alert.
///
/// `UNUserNotificationCenter` traps when the process has no bundle identifier, which is
/// exactly what happens running the binary straight out of `.build/`. Every entry point
/// checks for a bundle first and falls back to an AppleScript notification, so the
/// executable stays usable outside the `.app` wrapper.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private enum ActionID {
        static let extend = "EXTEND_FIVE"
        static let dismiss = "DISMISS_ALARM"
        static let category = "TIMER_DONE"
    }

    private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }
    private(set) var authorized = false

    /// Set by the app delegate. `extend` carries the timer id the notification was for.
    var onExtend: ((String) -> Void)?
    var onDismiss: (() -> Void)?

    func requestAuthorization() {
        guard isBundled else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let extend = UNNotificationAction(identifier: ActionID.extend, title: "Add 5 Minutes", options: [])
        let dismiss = UNNotificationAction(
            identifier: ActionID.dismiss, title: "Dismiss", options: [.destructive])
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: ActionID.category,
                actions: [extend, dismiss],
                intentIdentifiers: [],
                options: [])
        ])

        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            self?.authorized = granted
        }
    }

    func permissionSummary(_ completion: @escaping (String) -> Void) {
        guard isBundled else {
            completion("running unbundled — using the AppleScript fallback")
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let text: String
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: text = "allowed"
            case .denied: text = "denied — falling back to AppleScript alerts"
            case .notDetermined: text = "not yet requested"
            @unknown default: text = "unknown"
            }
            DispatchQueue.main.async { completion(text) }
        }
    }

    func timerFinished(_ timer: TimerSnapshot) {
        let title: String
        if let note = timer.note, !note.isEmpty {
            // The entire point of asking after a pull: the alert says the thing the user
            // wanted to be told, not the name of the app that happened to be in front.
            title = note
        } else {
            let label = timer.tag.isEmpty ? timer.preset : timer.tag
            title = timer.kind == .alarm ? "Alarm — \(label)" : "\(label) done"
        }
        let kind = timer.kind == .alarm ? "alarm" : "timer"
        let body = "\(DurationFormat.short(timer.total)) \(kind) finished at \(DurationFormat.clock(timer.endsAt))."
        post(title: title, body: body, identifier: timer.id)
    }

    func post(title: String, body: String, identifier: String) {
        guard isBundled, authorized else {
            postViaAppleScript(title: title, body: body)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = ActionID.category
        content.userInfo = ["timerID": identifier]
        // A timer the user explicitly set is worth breaking through their own Focus for.
        // `.timeSensitive` needs the matching entitlement to actually pierce Focus; without
        // it the notification still arrives, just held until Focus ends.
        content.interruptionLevel = .timeSensitive
        // The looping alarm is ours to control, so the notification stays silent when it
        // would otherwise double up on the same sound.
        content.sound = Settings.shared.loopAlarm ? nil : .default

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if error != nil { self?.postViaAppleScript(title: title, body: body) }
        }
    }

    private func postViaAppleScript(title: String, body: String) {
        let escape: (String) -> String = {
            $0.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
        }
        let script = "display notification \"\(escape(body))\" with title \"\(escape(title))\""
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        task.arguments = ["-e", script]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.content.userInfo["timerID"] as? String ?? ""
        DispatchQueue.main.async { [weak self] in
            switch response.actionIdentifier {
            case ActionID.extend: self?.onExtend?(identifier)
            default: self?.onDismiss?()
            }
        }
        completionHandler()
    }
}
