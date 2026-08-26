import Foundation

/// Turns a macOS Focus mode on and off alongside a timer.
///
/// There is no public API for setting Focus or Do Not Disturb — Apple deliberately never
/// shipped one. The sanctioned route is the Shortcuts app: the user builds a shortcut
/// that flips Focus, and this runs it by name. That is why the settings pane asks for two
/// shortcut names rather than showing a list of Focus modes.
enum FocusSync {
    private static let shortcutsTool = "/usr/bin/shortcuts"

    static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: shortcutsTool)
    }

    static func engage() { run(named: Settings.shared.focusShortcutOn) }
    static func disengage() { run(named: Settings.shared.focusShortcutOff) }

    /// Names the user can pick from in the settings pane. Empty when Shortcuts has never
    /// been set up, which the pane reports rather than showing a mysteriously blank list.
    static func availableShortcuts() -> [String] {
        guard isAvailable else { return [] }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: shortcutsTool)
        task.arguments = ["list"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return [] }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted()
    }

    private static func run(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, isAvailable else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: shortcutsTool)
        task.arguments = ["run", trimmed]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }
}
