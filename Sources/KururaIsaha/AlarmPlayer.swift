import AppKit
import Foundation

/// The sound a finished timer makes, and the optional ambience while it runs.
///
/// `NSSound` rather than `AVAudioPlayer`: it loops natively, takes a system sound by name
/// or a file by URL with the same call, and needs no session configuration for what is
/// ultimately a doorbell.
final class AlarmPlayer {
    private var alarm: NSSound?
    private var ambient: NSSound?

    var isAlarmSounding: Bool { alarm?.isPlaying ?? false }

    // MARK: - Alarm

    func startAlarm() {
        stopAlarm()
        let settings = Settings.shared
        let sound: NSSound?

        let custom = settings.customAlarmPath.trimmingCharacters(in: .whitespaces)
        if !custom.isEmpty, FileManager.default.isReadableFile(atPath: custom) {
            sound = NSSound(contentsOfFile: custom, byReference: true)
        } else {
            sound = NSSound(named: settings.alarmSound) ?? NSSound(named: "Glass")
        }

        guard let sound else { return }
        sound.loops = settings.loopAlarm
        alarm = sound
        sound.play()
    }

    func stopAlarm() {
        alarm?.stop()
        alarm = nil
    }

    // MARK: - Ambience

    func startAmbient() {
        guard Settings.shared.playAmbient, ambient == nil else { return }
        let path = Settings.shared.ambientPath.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty, FileManager.default.isReadableFile(atPath: path),
              let sound = NSSound(contentsOfFile: path, byReference: true) else { return }
        sound.loops = true
        ambient = sound
        sound.play()
    }

    func stopAmbient() {
        ambient?.stop()
        ambient = nil
    }
}
