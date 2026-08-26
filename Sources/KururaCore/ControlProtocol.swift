import Darwin
import Foundation

// MARK: - Model

public enum TimerKind: String, Codable, Sendable {
    /// Counts down a length ("25 minutes from now").
    case timer
    /// Counts down to a wall-clock moment ("14:45").
    case alarm
}

public struct TimerSnapshot: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var tag: String
    public var preset: String
    public var kind: TimerKind
    public var startedAt: Date
    public var endsAt: Date
    /// What the user said this timer is for, typed after the pull. Optional rather than an
    /// empty string so that a snapshot written by a build without the field still decodes.
    public var note: String?
    public var isPaused: Bool
    /// Frozen remaining time. Only meaningful while `isPaused`.
    public var pausedRemaining: TimeInterval?

    public init(
        id: String,
        tag: String,
        preset: String,
        kind: TimerKind,
        startedAt: Date,
        endsAt: Date,
        note: String? = nil,
        isPaused: Bool = false,
        pausedRemaining: TimeInterval? = nil
    ) {
        self.id = id
        self.tag = tag
        self.preset = preset
        self.kind = kind
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.note = note
        self.isPaused = isPaused
        self.pausedRemaining = pausedRemaining
    }

    public var hasNote: Bool { !(note ?? "").isEmpty }

    /// What to call this timer in a menu, a listing, or an alert: the reminder the user
    /// typed, failing that the tag it was given, failing that the band it landed in.
    public var displayLabel: String {
        if let note, !note.isEmpty { return note }
        return tag.isEmpty ? preset : tag
    }

    public func remaining(at now: Date = Date()) -> TimeInterval {
        if isPaused { return pausedRemaining ?? 0 }
        return max(0, endsAt.timeIntervalSince(now))
    }

    public var total: TimeInterval {
        max(1, endsAt.timeIntervalSince(startedAt))
    }

    /// 0…1, for the ring in the menu and the bar in the HUD.
    public func progress(at now: Date = Date()) -> Double {
        min(1, max(0, 1 - remaining(at: now) / total))
    }
}

public struct DayStat: Codable, Sendable, Equatable {
    public var day: String        // yyyy-MM-dd, local
    public var seconds: TimeInterval
    public var sessions: Int

    public init(day: String, seconds: TimeInterval, sessions: Int) {
        self.day = day
        self.seconds = seconds
        self.sessions = sessions
    }
}

public struct TagStat: Codable, Sendable, Equatable {
    public var tag: String
    public var seconds: TimeInterval
    public var sessions: Int

    public init(tag: String, seconds: TimeInterval, sessions: Int) {
        self.tag = tag
        self.seconds = seconds
        self.sessions = sessions
    }
}

// MARK: - Wire format

public enum ControlCommand: Codable, Sendable {
    case ping
    case start(duration: TimeInterval, tag: String?, kind: TimerKind, note: String?)
    case alarm(at: Date, tag: String?, note: String?)
    case extend(seconds: TimeInterval, id: String?)
    case cancel(id: String?)
    case pause(id: String?)
    case resume(id: String?)
    case status
    case stats(days: Int)
    case export(path: String?)
}

public struct ControlResponse: Codable, Sendable {
    public var ok: Bool
    public var message: String
    public var timers: [TimerSnapshot]
    public var days: [DayStat]
    public var tags: [TagStat]
    public var path: String?

    public init(
        ok: Bool,
        message: String,
        timers: [TimerSnapshot] = [],
        days: [DayStat] = [],
        tags: [TagStat] = [],
        path: String? = nil
    ) {
        self.ok = ok
        self.message = message
        self.timers = timers
        self.days = days
        self.tags = tags
        self.path = path
    }

    public static func failure(_ message: String) -> ControlResponse {
        ControlResponse(ok: false, message: message)
    }
}

public enum ControlCoding {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - Where the socket lives

public enum ControlPaths {
    public static let supportDirectory: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("KururaIsaha", isDirectory: true)
    }()

    public static let databaseURL = supportDirectory.appendingPathComponent("sessions.sqlite")

    /// A `sockaddr_un` path is capped at 104 bytes including the terminator, and a long
    /// home directory can overrun it. `/tmp` is the escape hatch, keyed by uid so two
    /// accounts on one Mac never collide.
    public static let socketPath: String = {
        let preferred = supportDirectory.appendingPathComponent("control.sock").path
        return preferred.utf8.count < 100 ? preferred : "/tmp/kurura-\(getuid()).sock"
    }()
}

// MARK: - Client

public enum ControlClientError: Error, LocalizedError {
    case notRunning
    case io(String)
    case malformedResponse

    public var errorDescription: String? {
        switch self {
        case .notRunning:
            return "Kurura Isaha is not running. Launch the app, then try again."
        case .io(let detail):
            return "Could not talk to Kurura Isaha: \(detail)"
        case .malformedResponse:
            return "Kurura Isaha sent a response this version does not understand."
        }
    }
}

/// A one-shot, blocking client: connect, write one JSON line, read one JSON line, close.
/// Small enough that the CLI needs no runloop and starts instantly.
public enum ControlClient {
    public static func send(_ command: ControlCommand, timeout: TimeInterval = 5) throws -> ControlResponse {
        let path = ControlPaths.socketPath
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw ControlClientError.io(errnoText()) }
        defer { Darwin.close(descriptor) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

        let pathBytes = Array(path.utf8CString)
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            throw ControlClientError.io("socket path is too long: \(path)")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in
            pathBytes.withUnsafeBytes { source in
                destination.copyMemory(from: source)
            }
        }

        var window = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &window, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &window, socklen_t(MemoryLayout<timeval>.size))
        // An app that goes away mid-request must not kill the CLI with SIGPIPE.
        var noSignal: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))

        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                Darwin.connect(descriptor, generic, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if connected != 0 {
            // No socket file, or a stale one nobody is listening on: the app is down.
            if errno == ENOENT || errno == ECONNREFUSED { throw ControlClientError.notRunning }
            throw ControlClientError.io(errnoText())
        }

        var payload = try ControlCoding.encoder().encode(command)
        payload.append(0x0A)
        try writeAll(descriptor, payload)

        guard let line = try readLine(descriptor) else { throw ControlClientError.malformedResponse }
        do {
            return try ControlCoding.decoder().decode(ControlResponse.self, from: line)
        } catch {
            throw ControlClientError.malformedResponse
        }
    }

    /// True when something is listening. Used by the CLI to decide whether to offer a launch.
    public static func isServerReachable() -> Bool {
        (try? send(.ping, timeout: 1))?.ok == true
    }

    private static func writeAll(_ descriptor: Int32, _ data: Data) throws {
        var offset = 0
        try data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            while offset < buffer.count {
                let written = Darwin.write(descriptor, base + offset, buffer.count - offset)
                if written <= 0 {
                    if errno == EINTR { continue }
                    throw ControlClientError.io(errnoText())
                }
                offset += written
            }
        }
    }

    private static func readLine(_ descriptor: Int32) throws -> Data? {
        var accumulated = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(descriptor, &chunk, chunk.count)
            if count < 0 {
                if errno == EINTR { continue }
                throw ControlClientError.io(errnoText())
            }
            if count == 0 { break }
            accumulated.append(contentsOf: chunk[0..<count])
            if let newline = accumulated.firstIndex(of: 0x0A) {
                return accumulated[accumulated.startIndex..<newline]
            }
        }
        return accumulated.isEmpty ? nil : accumulated
    }

    private static func errnoText() -> String {
        String(cString: strerror(errno))
    }
}
