import Foundation
import KururaCore

/// Shell scripts and webhooks fired on timer lifecycle events.
///
/// Off by default and gated behind a single switch, because this is arbitrary code
/// execution triggered by a mouse gesture. Scripts run detached with no shell profile,
/// and their output goes nowhere — a hook is a side effect, not a data source.
enum HookEvent: String {
    case start
    case expire
    case cancel
}

enum HookRunner {
    static func fire(_ event: HookEvent, timer: TimerSnapshot) {
        guard Settings.shared.hooksEnabled else { return }
        runScript(for: event, timer: timer)
        postWebhook(event, timer: timer)
    }

    private static func script(for event: HookEvent) -> String {
        switch event {
        case .start: return Settings.shared.hookOnStart
        case .expire, .cancel: return Settings.shared.hookOnExpire
        }
    }

    private static func runScript(for event: HookEvent, timer: TimerSnapshot) {
        let body = script(for: event).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", body]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice

        var environment = ProcessInfo.processInfo.environment
        environment["KURURA_EVENT"] = event.rawValue
        environment["KURURA_ID"] = timer.id
        environment["KURURA_TAG"] = timer.tag
        environment["KURURA_NOTE"] = timer.note ?? ""
        environment["KURURA_PRESET"] = timer.preset
        environment["KURURA_KIND"] = timer.kind.rawValue
        environment["KURURA_DURATION"] = String(Int(timer.total))
        environment["KURURA_REMAINING"] = String(Int(timer.remaining()))
        environment["KURURA_ENDS_AT"] = ISO8601DateFormatter().string(from: timer.endsAt)
        task.environment = environment

        try? task.run()
    }

    private static func postWebhook(_ event: HookEvent, timer: TimerSnapshot) {
        let text = Settings.shared.webhookURL.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, let url = URL(string: text), url.scheme?.hasPrefix("http") == true else { return }

        struct Payload: Encodable {
            let event: String
            let timer: TimerSnapshot
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = try? ControlCoding.encoder().encode(Payload(event: event.rawValue, timer: timer))
        // Fire and forget: a webhook that is down must never stall the timer that fired it.
        URLSession.shared.dataTask(with: request).resume()
    }
}
