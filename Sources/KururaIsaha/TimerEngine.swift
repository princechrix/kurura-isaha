import AppKit
import Foundation
import KururaCore

/// Owns every running timer and everything that happens because one exists.
///
/// Timers are stored as an absolute end date, never as a remaining count. That is the
/// only representation that survives the machine sleeping mid-session: `DispatchSource`
/// does not tick while the Mac is out, so on wake the engine re-reads the wall clock and
/// fires whatever became due, rather than resuming a countdown that lost ten minutes.
final class TimerEngine: ObservableObject {
    @Published private(set) var timers: [TimerSnapshot] = []

    /// Fired when a timer reaches zero, for the menu bar flash.
    var onExpire: ((TimerSnapshot) -> Void)?
    /// Fired when the app goes from idle to busy or back, for Strict Focus.
    var onBusyChanged: ((Bool) -> Void)?

    private struct Record: Codable {
        var snapshot: TimerSnapshot
        /// What the pull originally asked for, before any extensions.
        var planned: TimeInterval
        var pausedTotal: TimeInterval = 0
        var pausedSince: Date?
        var app: String?
        var bindsFocus: Bool = false
    }

    private var records: [Record] = []
    private let store: SessionStore
    private let alarm: AlarmPlayer
    private let notifier: Notifier
    private let sleepGuard = SleepGuard()
    private var ticker: DispatchSourceTimer?
    private var focusEngaged = false
    private var wasBusy = false

    private static let activeKey = "activeTimers"

    init(store: SessionStore, alarm: AlarmPlayer, notifier: Notifier) {
        self.store = store
        self.alarm = alarm
        self.notifier = notifier

        restore()

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.tick()
        }
    }

    // MARK: - Commands

    @discardableResult
    func start(
        duration: TimeInterval,
        tag: String? = nil,
        kind: TimerKind = .timer,
        note: String? = nil,
        bindsFocus: Bool = false
    ) -> TimerSnapshot {
        let now = Date()
        let length = max(1, duration)
        let resolvedTag = (tag?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 }
            ?? AutoTagger.currentTag()
            ?? ""

        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = TimerSnapshot(
            id: Self.newIdentifier(),
            tag: resolvedTag,
            preset: PullPreset.forDuration(length).name,
            kind: kind,
            startedAt: now,
            endsAt: now.addingTimeInterval(length),
            note: (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote
        )
        let record = Record(
            snapshot: snapshot,
            planned: length,
            app: NSWorkspace.shared.frontmostApplication?.localizedName,
            bindsFocus: bindsFocus || Settings.shared.syncFocus
        )
        records.append(record)

        alarm.stopAlarm()
        alarm.startAmbient()
        sleepGuard.hold(reason: "Kurura Isaha timer running")
        if record.bindsFocus, !focusEngaged {
            FocusSync.engage()
            focusEngaged = true
        }
        HookRunner.fire(.start, timer: snapshot)

        publish()
        return snapshot
    }

    @discardableResult
    func startAlarm(at date: Date, tag: String? = nil, note: String? = nil) -> TimerSnapshot? {
        let seconds = date.timeIntervalSinceNow
        guard seconds > 0 else { return nil }
        return start(duration: seconds, tag: tag, kind: .alarm, note: note)
    }

    /// Names a timer after the fact, which is how the pull gesture works: the timer starts
    /// on release and the reminder arrives a few seconds later, if at all.
    ///
    /// A very short timer can finish before the typing does. There is nothing to rename by
    /// then and nothing worth reporting, so this quietly does nothing.
    @discardableResult
    func setNote(_ note: String, on id: String) -> Bool {
        guard let index = records.firstIndex(where: { $0.snapshot.id == id }) else { return false }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        records[index].snapshot.note = trimmed.isEmpty ? nil : trimmed
        publish()
        return true
    }

    func extend(id: String?, by seconds: TimeInterval) -> Bool {
        guard let index = index(of: id) else { return false }
        if records[index].snapshot.isPaused {
            records[index].snapshot.pausedRemaining = (records[index].snapshot.pausedRemaining ?? 0) + seconds
        } else {
            records[index].snapshot.endsAt.addTimeInterval(seconds)
        }
        alarm.stopAlarm()
        publish()
        return true
    }

    func pause(id: String?) -> Bool {
        guard let index = index(of: id, preferring: .running),
              !records[index].snapshot.isPaused else { return false }
        let now = Date()
        records[index].snapshot.pausedRemaining = records[index].snapshot.remaining(at: now)
        records[index].snapshot.isPaused = true
        records[index].pausedSince = now
        publish()
        return true
    }

    func resume(id: String?) -> Bool {
        guard let index = index(of: id, preferring: .paused),
              records[index].snapshot.isPaused else { return false }
        let now = Date()
        let remaining = records[index].snapshot.pausedRemaining ?? 0
        if let since = records[index].pausedSince {
            records[index].pausedTotal += now.timeIntervalSince(since)
        }
        records[index].pausedSince = nil
        records[index].snapshot.isPaused = false
        records[index].snapshot.pausedRemaining = nil
        records[index].snapshot.endsAt = now.addingTimeInterval(remaining)
        publish()
        return true
    }

    /// `id` of `"*"` cancels everything, nil cancels the timer ending soonest.
    @discardableResult
    func cancel(id: String?) -> Int {
        alarm.stopAlarm()
        if id == "*" {
            let all = records
            records.removeAll()
            all.forEach { finish($0, completed: false, at: Date()) }
            publish()
            return all.count
        }
        guard let index = index(of: id) else { return 0 }
        let record = records.remove(at: index)
        finish(record, completed: false, at: Date())
        publish()
        return 1
    }

    /// Silences a ringing alarm without touching any running timer.
    func dismissAlarm() {
        alarm.stopAlarm()
    }

    // MARK: - Reading

    var primary: TimerSnapshot? {
        records.filter { !$0.snapshot.isPaused }.min { $0.snapshot.endsAt < $1.snapshot.endsAt }?.snapshot
            ?? records.first?.snapshot
    }

    var isBusy: Bool { !records.isEmpty }

    var isAlarmSounding: Bool { alarm.isAlarmSounding }

    // MARK: - Ticking

    private func ensureTicker() {
        if records.isEmpty {
            ticker?.cancel()
            ticker = nil
            return
        }
        guard ticker == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        // Twice a second so the menu bar countdown never visibly stalls on a second
        // boundary; the work per tick is a date comparison per timer.
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        ticker = timer
    }

    private func tick() {
        let now = Date()
        let due = records.filter { !$0.snapshot.isPaused && $0.snapshot.endsAt <= now }
        guard !due.isEmpty else {
            // Nothing expired, but the remaining time moved, so the menu bar and any open
            // window still need a nudge.
            objectWillChange.send()
            timers = records.map(\.snapshot)
            return
        }

        let expiredIDs = Set(due.map(\.snapshot.id))
        records.removeAll { expiredIDs.contains($0.snapshot.id) }
        for record in due { finish(record, completed: true, at: now) }
        publish()
    }

    // MARK: - Lifecycle of one timer

    private func finish(_ record: Record, completed: Bool, at now: Date) {
        let snapshot = record.snapshot
        var pausedTotal = record.pausedTotal
        if let since = record.pausedSince { pausedTotal += now.timeIntervalSince(since) }
        let elapsed = max(0, now.timeIntervalSince(snapshot.startedAt) - pausedTotal)

        store.record(CompletedSession(
            id: snapshot.id,
            tag: snapshot.tag,
            preset: snapshot.preset,
            kind: snapshot.kind,
            startedAt: snapshot.startedAt,
            endedAt: now,
            planned: record.planned,
            actual: elapsed,
            completed: completed,
            app: record.app,
            note: snapshot.note
        ))

        if completed {
            notifier.timerFinished(snapshot)
            alarm.startAlarm()
            HookRunner.fire(.expire, timer: snapshot)
            onExpire?(snapshot)
            chainBreak(after: snapshot)
        } else {
            HookRunner.fire(.cancel, timer: snapshot)
        }
    }

    /// Pomodoro-style auto-chain. Guarded against chaining off a break, which would
    /// otherwise loop forever with no one asking for it.
    private func chainBreak(after snapshot: TimerSnapshot) {
        guard Settings.shared.chainBreaks, snapshot.tag != "Break", snapshot.kind == .timer else { return }
        let minutes = Settings.shared.breakMinutes
        start(duration: Double(minutes) * 60, tag: "Break", kind: .timer)
        notifier.post(
            title: "Break started",
            body: "\(minutes) minute break. It will chime when it is time to go again.",
            identifier: "break-\(snapshot.id)")
    }

    // MARK: - Persistence and publishing

    private func publish() {
        objectWillChange.send()
        timers = records.map(\.snapshot)
        ensureTicker()
        persist()

        if records.isEmpty {
            alarm.stopAmbient()
            sleepGuard.release()
        }
        if !records.contains(where: \.bindsFocus), focusEngaged {
            FocusSync.disengage()
            focusEngaged = false
        }
        if wasBusy != isBusy {
            wasBusy = isBusy
            onBusyChanged?(isBusy)
        }
    }

    private func persist() {
        guard let data = try? ControlCoding.encoder().encode(records) else { return }
        UserDefaults.standard.set(data, forKey: Self.activeKey)
    }

    private func restore() {
        defer { publish() }
        guard let data = UserDefaults.standard.data(forKey: Self.activeKey),
              let saved = try? ControlCoding.decoder().decode([Record].self, from: data) else { return }

        let now = Date()
        for record in saved {
            if !record.snapshot.isPaused, record.snapshot.endsAt <= now {
                // Ran out while the app was not running. It still belongs in the history,
                // but nobody wants a bell for something that finished overnight.
                finish(record, completed: true, at: record.snapshot.endsAt)
                alarm.stopAlarm()
            } else {
                records.append(record)
            }
        }
    }

    // MARK: - Helpers

    /// Which timer a command with no `--id` means.
    private enum Preference {
        case running
        case paused
        /// Soonest running, or a paused one if nothing is running.
        case any
    }

    private func index(of id: String?, preferring preference: Preference = .any) -> Int? {
        if let id, !id.isEmpty {
            return records.firstIndex { $0.snapshot.id == id }
        }
        func soonest(paused: Bool) -> Int? {
            records.indices
                .filter { records[$0].snapshot.isPaused == paused }
                .min { records[$0].snapshot.endsAt < records[$1].snapshot.endsAt }
        }
        switch preference {
        case .running: return soonest(paused: false)
        case .paused: return soonest(paused: true)
        case .any: return soonest(paused: false) ?? soonest(paused: true)
        }
    }

    /// Short enough to retype into `kurura extend --id`, long enough not to collide.
    private static func newIdentifier() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(6)).lowercased()
    }
}
