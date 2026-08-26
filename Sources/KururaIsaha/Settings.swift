import AppKit
import Foundation
import KururaCore

/// Every user-visible preference, backed by `UserDefaults`.
///
/// `ObservableObject` so the SwiftUI settings pane and the AppKit overlay can both watch
/// it; every setter announces the change so a toggle flipped in the menu redraws the pane
/// and vice versa.
final class Settings: ObservableObject {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let scalingMode = "scalingMode"
        static let tickSounds = "tickSounds"
        static let haptics = "haptics"
        static let showHUD = "showHUD"
        static let secondsInMenuBar = "secondsInMenuBar"
        static let askForReminder = "askForReminder"

        static let alarmSound = "alarmSound"
        static let customAlarmPath = "customAlarmPath"
        static let loopAlarm = "loopAlarm"
        static let ambientPath = "ambientPath"
        static let playAmbient = "playAmbient"

        static let preventSleep = "preventSleep"
        static let autoTag = "autoTag"
        static let syncFocus = "syncFocus"
        static let focusShortcutOn = "focusShortcutOn"
        static let focusShortcutOff = "focusShortcutOff"

        static let chainBreaks = "chainBreaks"
        static let breakMinutes = "breakMinutes"

        static let hooksEnabled = "hooksEnabled"
        static let hookOnStart = "hookOnStart"
        static let hookOnExpire = "hookOnExpire"
        static let webhookURL = "webhookURL"

        static let strictFocus = "strictFocus"
        static let blockedApps = "blockedApps"
        static let panicPhrase = "panicPhrase"
    }

    private init() {
        defaults.register(defaults: [
            Key.scalingMode: ScalingMode.logarithmic.rawValue,
            Key.tickSounds: true,
            Key.haptics: true,
            Key.showHUD: true,
            Key.secondsInMenuBar: true,
            Key.askForReminder: true,
            Key.alarmSound: "Glass",
            Key.loopAlarm: false,
            Key.playAmbient: false,
            Key.preventSleep: true,
            Key.autoTag: true,
            Key.syncFocus: false,
            Key.focusShortcutOn: "",
            Key.focusShortcutOff: "",
            Key.chainBreaks: false,
            Key.breakMinutes: 5,
            Key.hooksEnabled: false,
            Key.hookOnStart: "",
            Key.hookOnExpire: "",
            Key.webhookURL: "",
            Key.strictFocus: false,
            Key.blockedApps: [String](),
            Key.panicPhrase: "let me out",
        ])
    }

    // MARK: - Gesture

    var scalingMode: ScalingMode {
        get { ScalingMode(rawValue: defaults.string(forKey: Key.scalingMode) ?? "") ?? .logarithmic }
        set { write(newValue.rawValue, Key.scalingMode) }
    }

    var tickSounds: Bool {
        get { defaults.bool(forKey: Key.tickSounds) }
        set { write(newValue, Key.tickSounds) }
    }

    /// Only ever felt on a Force Touch trackpad; a mouse silently gets nothing.
    var haptics: Bool {
        get { defaults.bool(forKey: Key.haptics) }
        set { write(newValue, Key.haptics) }
    }

    var showHUD: Bool {
        get { defaults.bool(forKey: Key.showHUD) }
        set { write(newValue, Key.showHUD) }
    }

    var secondsInMenuBar: Bool {
        get { defaults.bool(forKey: Key.secondsInMenuBar) }
        set { write(newValue, Key.secondsInMenuBar) }
    }

    /// Whether releasing a pull opens the card that asks what the timer is for.
    var askForReminder: Bool {
        get { defaults.bool(forKey: Key.askForReminder) }
        set { write(newValue, Key.askForReminder) }
    }

    // MARK: - Sound

    var alarmSound: String {
        get { defaults.string(forKey: Key.alarmSound) ?? "Glass" }
        set { write(newValue, Key.alarmSound) }
    }

    var customAlarmPath: String {
        get { defaults.string(forKey: Key.customAlarmPath) ?? "" }
        set { write(newValue, Key.customAlarmPath) }
    }

    var loopAlarm: Bool {
        get { defaults.bool(forKey: Key.loopAlarm) }
        set { write(newValue, Key.loopAlarm) }
    }

    var ambientPath: String {
        get { defaults.string(forKey: Key.ambientPath) ?? "" }
        set { write(newValue, Key.ambientPath) }
    }

    var playAmbient: Bool {
        get { defaults.bool(forKey: Key.playAmbient) }
        set { write(newValue, Key.playAmbient) }
    }

    // MARK: - Behaviour

    var preventSleep: Bool {
        get { defaults.bool(forKey: Key.preventSleep) }
        set { write(newValue, Key.preventSleep) }
    }

    var autoTag: Bool {
        get { defaults.bool(forKey: Key.autoTag) }
        set { write(newValue, Key.autoTag) }
    }

    var syncFocus: Bool {
        get { defaults.bool(forKey: Key.syncFocus) }
        set { write(newValue, Key.syncFocus) }
    }

    var focusShortcutOn: String {
        get { defaults.string(forKey: Key.focusShortcutOn) ?? "" }
        set { write(newValue, Key.focusShortcutOn) }
    }

    var focusShortcutOff: String {
        get { defaults.string(forKey: Key.focusShortcutOff) ?? "" }
        set { write(newValue, Key.focusShortcutOff) }
    }

    var chainBreaks: Bool {
        get { defaults.bool(forKey: Key.chainBreaks) }
        set { write(newValue, Key.chainBreaks) }
    }

    var breakMinutes: Int {
        get { max(1, defaults.integer(forKey: Key.breakMinutes)) }
        set { write(max(1, newValue), Key.breakMinutes) }
    }

    // MARK: - Hooks

    var hooksEnabled: Bool {
        get { defaults.bool(forKey: Key.hooksEnabled) }
        set { write(newValue, Key.hooksEnabled) }
    }

    var hookOnStart: String {
        get { defaults.string(forKey: Key.hookOnStart) ?? "" }
        set { write(newValue, Key.hookOnStart) }
    }

    var hookOnExpire: String {
        get { defaults.string(forKey: Key.hookOnExpire) ?? "" }
        set { write(newValue, Key.hookOnExpire) }
    }

    var webhookURL: String {
        get { defaults.string(forKey: Key.webhookURL) ?? "" }
        set { write(newValue, Key.webhookURL) }
    }

    // MARK: - Strict Focus

    var strictFocus: Bool {
        get { defaults.bool(forKey: Key.strictFocus) }
        set { write(newValue, Key.strictFocus) }
    }

    var blockedApps: [String] {
        get { defaults.stringArray(forKey: Key.blockedApps) ?? [] }
        set { write(newValue, Key.blockedApps) }
    }

    var panicPhrase: String {
        get { defaults.string(forKey: Key.panicPhrase) ?? "let me out" }
        set { write(newValue, Key.panicPhrase) }
    }

    private func write(_ value: Any, _ key: String) {
        objectWillChange.send()
        defaults.set(value, forKey: key)
    }
}
