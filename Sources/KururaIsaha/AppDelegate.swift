import AppKit
import Foundation
import KururaCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SessionStore()
    private let alarm = AlarmPlayer()
    private let server = ControlServer()
    private let strictFocus = StrictFocus()

    private lazy var engine = TimerEngine(store: store, alarm: alarm, notifier: Notifier.shared)
    private lazy var mainWindow = MainWindowController(engine: engine, store: store)
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.shared.requestAuthorization()
        Notifier.shared.onExtend = { [weak self] id in
            _ = self?.engine.extend(id: id.isEmpty ? nil : id, by: 300)
        }
        Notifier.shared.onDismiss = { [weak self] in self?.engine.dismissAlarm() }

        engine.onBusyChanged = { [weak self] busy in self?.strictFocus.setEngaged(busy) }

        statusItem = StatusItemController(engine: engine) { [weak self] section in
            self?.mainWindow.show(section)
        }

        server.handler = { [weak self] command in
            self?.respond(to: command) ?? .failure("the app is still starting up")
        }
        if !server.start() {
            NSLog("Kurura Isaha: could not open the control socket at \(ControlPaths.socketPath); the kurura command will not work.")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server.stop()
        alarm.stopAlarm()
        alarm.stopAmbient()
    }

    /// Quitting the app is not the same as cancelling the timers; they are restored on the
    /// next launch and the app is meant to live at login anyway.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: - Control socket

    /// Soonest first, so every listing the CLI prints reads in the order things happen.
    private var sortedTimers: [TimerSnapshot] {
        engine.timers.sorted { $0.endsAt < $1.endsAt }
    }

    private func respond(to command: ControlCommand) -> ControlResponse {
        switch command {
        case .ping:
            return ControlResponse(ok: true, message: "Kurura Isaha \(KururaVersion.string) is listening")

        case .start(let duration, let tag, let kind, let note):
            let timer = engine.start(duration: duration, tag: tag, kind: kind, note: note)
            return ControlResponse(
                ok: true,
                message: "Started \(DurationFormat.short(duration)) — ends at \(DurationFormat.clock(timer.endsAt))",
                timers: [timer])

        case .alarm(let date, let tag, let note):
            guard let timer = engine.startAlarm(at: date, tag: tag, note: note) else {
                return .failure("\(DurationFormat.clock(date)) has already passed")
            }
            return ControlResponse(
                ok: true,
                message: "Alarm set for \(DurationFormat.clock(timer.endsAt))",
                timers: [timer])

        case .extend(let seconds, let id):
            guard engine.extend(id: id, by: seconds) else {
                return .failure(id.map { "no timer with id \($0)" } ?? "nothing is running")
            }
            return ControlResponse(
                ok: true,
                message: "Added \(DurationFormat.short(seconds))",
                timers: sortedTimers)

        case .cancel(let id):
            let count = engine.cancel(id: id)
            guard count > 0 else {
                return .failure(id.map { "no timer with id \($0)" } ?? "nothing is running")
            }
            return ControlResponse(ok: true, message: "Cancelled \(count) timer\(count == 1 ? "" : "s")")

        case .pause(let id):
            guard engine.pause(id: id) else { return .failure("nothing to pause") }
            return ControlResponse(ok: true, message: "Paused", timers: sortedTimers)

        case .resume(let id):
            guard engine.resume(id: id) else { return .failure("nothing to resume") }
            return ControlResponse(ok: true, message: "Resumed", timers: sortedTimers)

        case .status:
            let timers = sortedTimers
            return ControlResponse(
                ok: true,
                message: timers.isEmpty ? "nothing running" : "",
                timers: timers)

        case .stats(let days):
            return ControlResponse(
                ok: true,
                message: "",
                days: store.dayStats(days: days),
                tags: store.tagStats(days: days))

        case .export(let path):
            let destination = path.map {
                URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)
            }
            do {
                let written = try store.exportCSV(to: destination)
                return ControlResponse(ok: true, message: "exported", path: written.path)
            } catch {
                return .failure(error.localizedDescription)
            }
        }
    }
}
