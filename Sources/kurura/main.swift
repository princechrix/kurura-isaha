import Darwin
import Foundation
import KururaCore

// The terminal half of Kurura Isaha. It holds no state of its own: every subcommand is
// one line of JSON over the app's control socket, so a timer started here is the same
// object as one pulled out of the menu bar.

let bundleIdentifier = "com.local.kururaisaha"

// MARK: - Argument handling

var tokens = Array(CommandLine.arguments.dropFirst())

func takeFlag(_ names: String...) -> Bool {
    for name in names {
        if let index = tokens.firstIndex(of: name) {
            tokens.remove(at: index)
            return true
        }
    }
    return false
}

func takeValue(_ names: String...) -> String? {
    for name in names {
        if let index = tokens.firstIndex(of: name) {
            guard index + 1 < tokens.count else {
                fail("\(name) needs a value")
            }
            let value = tokens[index + 1]
            tokens.removeSubrange(index...(index + 1))
            return value
        }
        if let index = tokens.firstIndex(where: { $0.hasPrefix(name + "=") }) {
            let value = String(tokens[index].dropFirst(name.count + 1))
            tokens.remove(at: index)
            return value
        }
    }
    return nil
}

func fail(_ message: String, code: Int32 = 64) -> Never {
    FileHandle.standardError.write(Data("kurura: \(message)\n".utf8))
    exit(code)
}

func usage() {
    print("""
    kurura — drive Kurura Isaha from the terminal.

    Usage:
      kurura start --duration 25m [--tag NAME] [--note TEXT]
                                                 start a countdown
      kurura 25m [--tag NAME] [--note TEXT]      shorthand for the above
      kurura alarm --at 14:45 [--tag NAME]       count down to a wall-clock time
      kurura status                              what is running right now
      kurura extend 5m [--id ID]                 add time to a running timer
      kurura cancel [--id ID] [--all]            stop a timer
      kurura pause [--id ID]                     freeze a timer
      kurura resume [--id ID]                    unfreeze it
      kurura stats [--days 7]                    focused time per day and per tag
      kurura export [--out FILE]                 write the full history as CSV
      kurura ping                                check the app is listening

    Options:
      --note TEXT   what the timer is for; becomes the alert when it finishes
      --tag NAME    how the session is grouped in the analytics
      --json        machine-readable output, for scripts and status bars
      --no-launch   fail instead of starting the app when it is not running
      --version     print the version
      --help        this text

    Exit codes: 0 success, 1 refused by the app, 3 app not running, 64 bad usage.
    """)
}

let wantsJSON = takeFlag("--json")
let noLaunch = takeFlag("--no-launch")

if takeFlag("--help", "-h") { usage(); exit(0) }
if takeFlag("--version", "-v") { print("kurura \(KururaVersion.string)"); exit(0) }

// MARK: - Talking to the app

/// LaunchServices needs the app to have been opened once from a stable location before
/// `open -b` can find it, so a failure here is reported rather than swallowed.
func launchApp() -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    task.arguments = ["-g", "-b", bundleIdentifier]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    do { try task.run() } catch { return false }
    task.waitUntilExit()
    guard task.terminationStatus == 0 else { return false }

    // Give the app a moment to bind its socket before the command is retried.
    for _ in 0..<40 {
        if ControlClient.isServerReachable() { return true }
        usleep(250_000)
    }
    return false
}

func send(_ command: ControlCommand, mayLaunch: Bool = false) -> ControlResponse {
    do {
        return try ControlClient.send(command)
    } catch ControlClientError.notRunning {
        guard mayLaunch, !noLaunch else {
            FileHandle.standardError.write(Data("kurura: Kurura Isaha is not running.\n".utf8))
            exit(3)
        }
        guard launchApp() else {
            FileHandle.standardError.write(Data(
                "kurura: could not launch Kurura Isaha. Open it once from /Applications first.\n".utf8))
            exit(3)
        }
        do { return try ControlClient.send(command) }
        catch { fail(error.localizedDescription, code: 3) }
    } catch {
        fail(error.localizedDescription, code: 3)
    }
}

// MARK: - Output

func emit(_ response: ControlResponse, render: (ControlResponse) -> Void) -> Never {
    if wantsJSON {
        let encoder = ControlCoding.encoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(response), let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    } else if response.ok {
        render(response)
    } else {
        FileHandle.standardError.write(Data("kurura: \(response.message)\n".utf8))
    }
    exit(response.ok ? 0 : 1)
}

/// `padding(toLength:)` truncates an over-long string with no sign that it did, which
/// turns a reminder into a sentence fragment. Anything too wide gets an ellipsis instead.
func column(_ text: String, _ width: Int) -> String {
    guard text.count >= width else {
        return text.padding(toLength: width, withPad: " ", startingAt: 0)
    }
    return String(text.prefix(width - 2)) + "… "
}

func describe(_ timer: TimerSnapshot) -> String {
    let remaining = DurationFormat.countdown(timer.remaining())
    let state = timer.isPaused ? "paused" : "running"
    // A paused timer's end date is frozen at the moment it was paused, so printing it
    // would name a time that is now in the past.
    let ending = timer.isPaused ? "on hold" : "ends \(DurationFormat.clock(timer.endsAt))"
    return "  " + column(remaining, 10) + column(timer.displayLabel, 28)
        + column(state, 9) + column(ending, 16) + timer.id
}

func renderTimers(_ response: ControlResponse) {
    if response.timers.isEmpty {
        print(response.message.isEmpty ? "nothing running" : response.message)
        return
    }
    if !response.message.isEmpty { print(response.message) }
    for timer in response.timers { print(describe(timer)) }
}

// MARK: - Dispatch

let subcommand = tokens.first.map { $0.hasPrefix("-") ? "" : $0 } ?? "status"
if !subcommand.isEmpty { tokens.removeFirst() }

let tag = takeValue("--tag", "-t")
let note = takeValue("--note", "-n")

switch subcommand {
case "start", "":
    let text = takeValue("--duration", "-d") ?? tokens.first
    guard let text, let seconds = DurationFormat.parse(text) else {
        fail("start needs a duration, e.g. --duration 25m")
    }
    emit(send(.start(duration: seconds, tag: tag, kind: .timer, note: note), mayLaunch: true)) { response in
        print(response.message)
        response.timers.forEach { print(describe($0)) }
    }

case "alarm":
    let text = takeValue("--at", "-a") ?? tokens.first
    guard let text, let when = DurationFormat.parseClockTime(text) else {
        fail("alarm needs a time, e.g. --at 14:45")
    }
    emit(send(.alarm(at: when, tag: tag, note: note), mayLaunch: true)) { response in
        print(response.message)
        response.timers.forEach { print(describe($0)) }
    }

case "status", "list", "ls":
    emit(send(.status), render: renderTimers)

case "extend":
    let text = takeValue("--duration", "-d") ?? tokens.first ?? "5m"
    guard let seconds = DurationFormat.parse(text) else { fail("extend needs a duration, e.g. 5m") }
    emit(send(.extend(seconds: seconds, id: takeValue("--id")), mayLaunch: false), render: renderTimers)

case "cancel", "stop":
    let identifier = takeFlag("--all") ? "*" : takeValue("--id")
    emit(send(.cancel(id: identifier))) { print($0.message) }

case "pause":
    emit(send(.pause(id: takeValue("--id"))), render: renderTimers)

case "resume":
    emit(send(.resume(id: takeValue("--id"))), render: renderTimers)

case "stats":
    let days = takeValue("--days").flatMap { Int($0) } ?? 7
    emit(send(.stats(days: max(1, days)))) { response in
        print("Focused time, last \(max(1, days)) days")
        for day in response.days {
            let bar = String(repeating: "█", count: min(40, Int(day.seconds / 900)))
            print("  \(day.day)  \(DurationFormat.short(day.seconds).padding(toLength: 9, withPad: " ", startingAt: 0))\(bar)")
        }
        guard !response.tags.isEmpty else { return }
        print("\nBy tag")
        for tag in response.tags {
            print("  \(tag.tag.padding(toLength: 22, withPad: " ", startingAt: 0))"
                + "\(DurationFormat.short(tag.seconds).padding(toLength: 9, withPad: " ", startingAt: 0))"
                + "\(tag.sessions) session\(tag.sessions == 1 ? "" : "s")")
        }
    }

case "export":
    emit(send(.export(path: takeValue("--out", "-o")))) { print($0.path ?? $0.message) }

case "ping":
    emit(send(.ping)) { print($0.message) }

default:
    // `kurura 25m` — the shorthand that makes the CLI worth typing.
    if let seconds = DurationFormat.parse(subcommand) {
        emit(send(.start(duration: seconds, tag: tag, kind: .timer, note: note), mayLaunch: true)) { response in
            print(response.message)
            response.timers.forEach { print(describe($0)) }
        }
    }
    fail("unknown command: \(subcommand)")
}
