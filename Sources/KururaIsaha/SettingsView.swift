import AppKit
import KururaCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var engine: TimerEngine
    @ObservedObject private var settings = Settings.shared

    @State private var shortcuts: [String] = []
    @State private var cliNotice: String?

    private static let systemSounds: [String] = {
        let url = URL(fileURLWithPath: "/System/Library/Sounds")
        let contents = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        return contents.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }()

    var body: some View {
        Form {
            pullSection
            soundSection
            runningSection
            focusSection
            strictSection
            hooksSection
            terminalSection
        }
        .formStyle(.grouped)
        .onAppear { shortcuts = FocusSync.availableShortcuts() }
    }

    // MARK: - The pull

    private var pullSection: some View {
        Section("The pull") {
            Picker("Scaling", selection: bind(\.scalingMode)) {
                ForEach(ScalingMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            Text("Logarithmic spends the top half of the screen on 1–15 minutes and the bottom half on 15 minutes to 4 hours. Linear is a flat 10 pixels per minute.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Toggle("Show the heads-up card while dragging", isOn: bind(\.showHUD))
            Toggle("Ask what the timer is for after releasing", isOn: bind(\.askForReminder))
            Text("The timer starts on release either way. Type a reminder and press return to name it, press escape to leave it, or ignore the card and it goes away by itself. Whatever you type becomes the alert when the time is up.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Toggle("Click on every minute crossed", isOn: bind(\.tickSounds))
            Toggle("Haptic feedback", isOn: bind(\.haptics))
            Text("Haptics are only felt on a Force Touch trackpad. A mouse gets the click instead.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Toggle("Count seconds in the menu bar", isOn: bind(\.secondsInMenuBar))
        }
    }

    // MARK: - Sound

    private var soundSection: some View {
        Section("Sound") {
            Picker("Alarm", selection: bind(\.alarmSound)) {
                ForEach(Self.systemSounds, id: \.self) { Text($0).tag($0) }
            }
            .disabled(!settings.customAlarmPath.isEmpty)

            HStack {
                Text("Custom alarm")
                Spacer()
                Text(displayName(settings.customAlarmPath) ?? "none")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button("Choose…") { pickAudio { settings.customAlarmPath = $0 } }
                if !settings.customAlarmPath.isEmpty {
                    Button("Clear") { settings.customAlarmPath = "" }
                }
            }

            Toggle("Loop the alarm until dismissed", isOn: bind(\.loopAlarm))

            Toggle("Play ambience while a timer runs", isOn: bind(\.playAmbient))
            HStack {
                Text("Ambience file")
                Spacer()
                Text(displayName(settings.ambientPath) ?? "none")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Button("Choose…") { pickAudio { settings.ambientPath = $0 } }
            }
            .disabled(!settings.playAmbient)
        }
    }

    // MARK: - Running

    private var runningSection: some View {
        Section("While a timer runs") {
            Toggle("Keep the Mac awake", isOn: bind(\.preventSleep))
            Text("Holds off idle sleep only. Closing the lid still sleeps the Mac; the timer catches up against the clock on wake.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Toggle("Tag sessions by the app in front", isOn: bind(\.autoTag))
            Toggle("Start a break when a timer finishes", isOn: bind(\.chainBreaks))
            if settings.chainBreaks {
                Stepper("Break length: \(settings.breakMinutes) min",
                        value: bind(\.breakMinutes), in: 1...60)
            }
        }
    }

    // MARK: - Focus

    private var focusSection: some View {
        Section("Focus") {
            Toggle("Bind every timer to a Focus mode", isOn: bind(\.syncFocus))
            Text("macOS has no public API for switching Focus, so this runs a Shortcut you make yourself: one that turns your Focus on, and one that turns it off. Hold ⇧ while pulling to bind a single timer without turning this on.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            if shortcuts.isEmpty {
                Text("No shortcuts found. Create them in the Shortcuts app, then reopen this window.")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            } else {
                Picker("On start", selection: bind(\.focusShortcutOn)) {
                    Text("none").tag("")
                    ForEach(shortcuts, id: \.self) { Text($0).tag($0) }
                }
                Picker("On finish", selection: bind(\.focusShortcutOff)) {
                    Text("none").tag("")
                    ForEach(shortcuts, id: \.self) { Text($0).tag($0) }
                }
            }
        }
    }

    // MARK: - Strict Focus

    private var strictSection: some View {
        Section("Strict Focus") {
            Toggle("Push blocked apps back down while a timer runs", isOn: strictBinding)
            Text("This hides a blocked app when it comes to the front. It is a speed bump, not a lock: stopping an app from launching at all needs Apple's Screen Time entitlement, and website blocking needs a system extension. Neither is in this build.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            ForEach(settings.blockedApps, id: \.self) { identifier in
                HStack {
                    Text(name(forBundleIdentifier: identifier))
                    Spacer()
                    Text(identifier).font(.system(size: 9)).foregroundStyle(.tertiary)
                    Button("Remove") { settings.blockedApps.removeAll { $0 == identifier } }
                }
            }
            HStack {
                Button("Block an App…", action: pickApp)
                Spacer()
            }

            TextField("Phrase to type when unblocking early", text: bind(\.panicPhrase))
        }
    }

    /// Turning the block off mid-session has to be deliberate, which is the entire point
    /// of the feature. Turning it on never asks anything.
    private var strictBinding: Binding<Bool> {
        Binding(
            get: { settings.strictFocus },
            set: { newValue in
                if !newValue, engine.isBusy, !StrictFocus.confirmDisable() { return }
                settings.strictFocus = newValue
            })
    }

    // MARK: - Hooks

    private var hooksSection: some View {
        Section("Hooks") {
            Toggle("Run my scripts on timer events", isOn: bind(\.hooksEnabled))
            Text("Off by default: this runs arbitrary shell commands triggered by a mouse gesture. Scripts get KURURA_EVENT, KURURA_TAG, KURURA_DURATION, KURURA_REMAINING and KURURA_ENDS_AT in their environment.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            TextField("On start", text: bind(\.hookOnStart), prompt: Text("osascript -e 'set volume output muted true'"))
                .font(.system(size: 11, design: .monospaced))
                .disabled(!settings.hooksEnabled)
            TextField("On finish", text: bind(\.hookOnExpire), prompt: Text("say \"time\""))
                .font(.system(size: 11, design: .monospaced))
                .disabled(!settings.hooksEnabled)
            TextField("Webhook URL", text: bind(\.webhookURL), prompt: Text("https://hooks.example.com/…"))
                .font(.system(size: 11, design: .monospaced))
                .disabled(!settings.hooksEnabled)
        }
    }

    // MARK: - Terminal

    private var terminalSection: some View {
        Section("Terminal") {
            HStack {
                Text("kurura command")
                Spacer()
                Text(CLIInstaller.installedAt?.path ?? "not installed")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Button("Install") { cliNotice = CLIInstaller.install() }
            }
            if let cliNotice {
                Text(cliNotice)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            HStack {
                Text("Control socket")
                Spacer()
                Text(ControlPaths.socketPath)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            Text("Kurura Isaha \(KururaVersion.string)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Helpers

    private func bind<Value>(_ keyPath: ReferenceWritableKeyPath<Settings, Value>) -> Binding<Value> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }

    private func displayName(_ path: String) -> String? {
        path.isEmpty ? nil : (path as NSString).lastPathComponent
    }

    private func name(forBundleIdentifier identifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else {
            return identifier
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private func pickAudio(_ assign: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        assign(url.path)
    }

    private func pickApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let identifier = Bundle(url: url)?.bundleIdentifier,
              !settings.blockedApps.contains(identifier) else { return }
        settings.blockedApps.append(identifier)
    }
}
