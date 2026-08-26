import Foundation
import KururaCore
import SQLite3

/// One finished timer, as it is written to disk.
struct CompletedSession {
    var id: String
    var tag: String
    var preset: String
    var kind: TimerKind
    var startedAt: Date
    var endedAt: Date
    /// What the pull asked for.
    var planned: TimeInterval
    /// What actually elapsed. Shorter than `planned` when a timer was cancelled early.
    var actual: TimeInterval
    var completed: Bool
    var app: String?
    /// What the user said the timer was for, if they said anything.
    var note: String?
}

/// The history behind the analytics pane, the `kurura stats` output, and the CSV export.
///
/// Plain `sqlite3` from the SDK rather than a wrapper package: the schema is one table,
/// and a menu bar utility should not pull a dependency tree in for that. Every call is
/// funnelled through one serial queue, so the control socket's background thread and the
/// main thread never touch the handle at once.
final class SessionStore {
    private var handle: OpaquePointer?
    private let queue = DispatchQueue(label: "rw.ivas.kurura.sessionstore")
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL = ControlPaths.databaseURL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK else {
            sqlite3_close_v2(database)
            return
        }
        handle = database
        migrate()
    }

    deinit {
        if let handle { sqlite3_close_v2(handle) }
    }

    private func migrate() {
        exec("PRAGMA journal_mode=WAL;")
        exec("""
            CREATE TABLE IF NOT EXISTS sessions (
                id          TEXT PRIMARY KEY,
                tag         TEXT NOT NULL DEFAULT '',
                preset      TEXT NOT NULL DEFAULT '',
                kind        TEXT NOT NULL DEFAULT 'timer',
                started_at  REAL NOT NULL,
                ended_at    REAL NOT NULL,
                planned     REAL NOT NULL,
                actual      REAL NOT NULL,
                completed   INTEGER NOT NULL DEFAULT 1,
                app         TEXT,
                note        TEXT
            );
            """)
        exec("CREATE INDEX IF NOT EXISTS sessions_started ON sessions(started_at);")

        // `CREATE TABLE IF NOT EXISTS` does nothing for a database that already exists, so
        // a column added after the fact has to be asked for by name.
        if !hasColumn("note") {
            exec("ALTER TABLE sessions ADD COLUMN note TEXT;")
        }
    }

    private func hasColumn(_ name: String) -> Bool {
        guard let statement = prepare("PRAGMA table_info(sessions);") else { return false }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            if text(statement, 1) == name { return true }
        }
        return false
    }

    // MARK: - Writing

    func record(_ session: CompletedSession) {
        queue.sync {
            let sql = """
                INSERT OR REPLACE INTO sessions
                (id, tag, preset, kind, started_at, ended_at, planned, actual, completed, app, note)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """
            guard let statement = prepare(sql) else { return }
            defer { sqlite3_finalize(statement) }

            bind(statement, 1, session.id)
            bind(statement, 2, session.tag)
            bind(statement, 3, session.preset)
            bind(statement, 4, session.kind.rawValue)
            sqlite3_bind_double(statement, 5, session.startedAt.timeIntervalSince1970)
            sqlite3_bind_double(statement, 6, session.endedAt.timeIntervalSince1970)
            sqlite3_bind_double(statement, 7, session.planned)
            sqlite3_bind_double(statement, 8, session.actual)
            sqlite3_bind_int(statement, 9, session.completed ? 1 : 0)
            if let app = session.app { bind(statement, 10, app) } else { sqlite3_bind_null(statement, 10) }
            if let note = session.note { bind(statement, 11, note) } else { sqlite3_bind_null(statement, 11) }

            sqlite3_step(statement)
        }
    }

    // MARK: - Reading

    /// One entry per day for the last `days` days, including days with nothing on them so
    /// the heatmap keeps a cell for every square.
    func dayStats(days: Int) -> [DayStat] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date().addingTimeInterval(-Double(days - 1) * 86400))

        var found: [String: DayStat] = [:]
        queue.sync {
            let sql = """
                SELECT date(started_at, 'unixepoch', 'localtime') AS day,
                       SUM(actual), COUNT(*)
                FROM sessions WHERE started_at >= ?
                GROUP BY day;
                """
            guard let statement = prepare(sql) else { return }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_double(statement, 1, start.timeIntervalSince1970)

            while sqlite3_step(statement) == SQLITE_ROW {
                let day = text(statement, 0)
                found[day] = DayStat(
                    day: day,
                    seconds: sqlite3_column_double(statement, 1),
                    sessions: Int(sqlite3_column_int(statement, 2))
                )
            }
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return (0..<days).compactMap { offset -> DayStat? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let key = formatter.string(from: date)
            return found[key] ?? DayStat(day: key, seconds: 0, sessions: 0)
        }
    }

    func tagStats(days: Int, limit: Int = 12) -> [TagStat] {
        let start = Calendar.current.startOfDay(for: Date().addingTimeInterval(-Double(days - 1) * 86400))
        var results: [TagStat] = []
        queue.sync {
            let sql = """
                SELECT CASE WHEN tag = '' THEN preset ELSE tag END AS label,
                       SUM(actual), COUNT(*)
                FROM sessions WHERE started_at >= ?
                GROUP BY label ORDER BY SUM(actual) DESC LIMIT ?;
                """
            guard let statement = prepare(sql) else { return }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_double(statement, 1, start.timeIntervalSince1970)
            sqlite3_bind_int(statement, 2, Int32(limit))

            while sqlite3_step(statement) == SQLITE_ROW {
                results.append(TagStat(
                    tag: text(statement, 0),
                    seconds: sqlite3_column_double(statement, 1),
                    sessions: Int(sqlite3_column_int(statement, 2))
                ))
            }
        }
        return results
    }

    /// Seconds focused today and how many sessions that took.
    func today() -> (seconds: TimeInterval, sessions: Int) {
        let stat = dayStats(days: 1).first
        return (stat?.seconds ?? 0, stat?.sessions ?? 0)
    }

    // MARK: - Export

    @discardableResult
    func exportCSV(to destination: URL? = nil) throws -> URL {
        var rows = ["id,tag,preset,kind,started_at,ended_at,planned_seconds,actual_seconds,completed,app,note"]
        let iso = ISO8601DateFormatter()

        queue.sync {
            let sql = """
                SELECT id, tag, preset, kind, started_at, ended_at, planned, actual, completed, app, note
                FROM sessions ORDER BY started_at ASC;
                """
            guard let statement = prepare(sql) else { return }
            defer { sqlite3_finalize(statement) }

            while sqlite3_step(statement) == SQLITE_ROW {
                let started = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
                let ended = Date(timeIntervalSince1970: sqlite3_column_double(statement, 5))
                let fields = [
                    text(statement, 0),
                    text(statement, 1),
                    text(statement, 2),
                    text(statement, 3),
                    iso.string(from: started),
                    iso.string(from: ended),
                    String(Int(sqlite3_column_double(statement, 6))),
                    String(Int(sqlite3_column_double(statement, 7))),
                    sqlite3_column_int(statement, 8) == 1 ? "yes" : "no",
                    text(statement, 9),
                    text(statement, 10),
                ]
                rows.append(fields.map(Self.escapeCSV).joined(separator: ","))
            }
        }

        let url = destination ?? defaultExportURL()
        try rows.joined(separator: "\n").appending("\n")
            .write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func defaultExportURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let name = "kurura-sessions-\(formatter.string(from: Date())).csv"
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        return (desktop ?? ControlPaths.supportDirectory).appendingPathComponent(name)
    }

    private static func escapeCSV(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    // MARK: - sqlite plumbing

    private func exec(_ sql: String) {
        guard let handle else { return }
        sqlite3_exec(handle, sql, nil, nil, nil)
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        guard let handle else { return nil }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            sqlite3_finalize(statement)
            return nil
        }
        return statement
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(statement, index, value, -1, Self.transient)
    }

    private func text(_ statement: OpaquePointer?, _ column: Int32) -> String {
        guard let pointer = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: pointer)
    }
}
