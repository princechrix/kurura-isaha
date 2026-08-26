import KururaCore
import SwiftUI

/// The card that follows the cursor during a pull.
///
/// Sits inside an `NSVisualEffectView`, so everything here is drawn on top of real glass
/// rather than a painted approximation of it — hence no background of its own.
struct HUDView: View {
    let reading: PullReading
    let kind: TimerKind
    let snapping: Bool
    let bindsFocus: Bool

    private var tint: Color { Color(PullPalette.color(forDuration: reading.duration)) }

    private var subtitle: String {
        let end = DurationFormat.clock(reading.endDate())
        return kind == .alarm
            ? "Alarm · rings at \(end)"
            : "\(reading.preset.name) · ends at \(end)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(tint.opacity(0.18))
                    Image(systemName: kind == .alarm ? "alarm.fill" : reading.preset.symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 1) {
                    Text(DurationFormat.short(reading.duration))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            Divider().opacity(0.4)

            HStack(spacing: 6) {
                chip("⌥", "5-min", snapping)
                chip("⇧", "Focus", bindsFocus)
                chip("⌘", "Alarm", kind == .alarm)
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(width: 272, alignment: .leading)
    }

    private func chip(_ key: String, _ label: String, _ active: Bool) -> some View {
        HStack(spacing: 4) {
            Text(key).font(.system(size: 10, weight: .bold))
            Text(label).font(.system(size: 10))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(active ? tint.opacity(0.22) : Color.primary.opacity(0.06))
        )
        .foregroundStyle(active ? tint : Color.secondary)
    }
}
