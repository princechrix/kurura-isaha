import Foundation

/// Parsing and printing of durations, shared by the HUD, the menu, and the CLI so
/// `kurura start --duration 25m` and the drag gesture agree on what "25m" means.
public enum DurationFormat {
    /// Accepts `25m`, `1h30m`, `90s`, `2h`, `1h 30m`, and a bare `25` (read as minutes).
    /// Returns nil rather than guessing when the text is not a duration.
    public static func parse(_ text: String) -> TimeInterval? {
        let cleaned = text.lowercased().replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty else { return nil }

        if let bareMinutes = Double(cleaned) {
            return bareMinutes > 0 ? bareMinutes * 60 : nil
        }

        var total: TimeInterval = 0
        var number = ""
        var sawUnit = false

        for character in cleaned {
            if character.isNumber || character == "." {
                number.append(character)
                continue
            }
            guard let value = Double(number) else { return nil }
            switch character {
            case "h": total += value * 3600
            case "m": total += value * 60
            case "s": total += value
            default: return nil
            }
            number = ""
            sawUnit = true
        }

        // Trailing digits with no unit ("1h30") read as minutes, which is what people mean.
        if !number.isEmpty {
            guard let value = Double(number) else { return nil }
            total += value * 60
        }
        guard sawUnit, total > 0 else { return nil }
        return total
    }

    /// Accepts `14:45` and `2:05pm`, resolved against the next occurrence of that time.
    public static func parseClockTime(_ text: String, from now: Date = Date(), calendar: Calendar = .current) -> Date? {
        let cleaned = text.lowercased().replacingOccurrences(of: " ", with: "")
        var body = cleaned
        var meridiemOffset: Int?

        if body.hasSuffix("pm") { meridiemOffset = 12; body.removeLast(2) }
        else if body.hasSuffix("am") { meridiemOffset = 0; body.removeLast(2) }

        let parts = body.split(separator: ":")
        guard (1...2).contains(parts.count), var hour = Int(parts[0]) else { return nil }
        let minute = parts.count == 2 ? Int(parts[1]) : 0
        guard let minute, (0..<60).contains(minute) else { return nil }

        if let meridiemOffset {
            guard (1...12).contains(hour) else { return nil }
            hour = (hour % 12) + meridiemOffset
        }
        guard (0..<24).contains(hour) else { return nil }

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard let candidate = calendar.date(from: components) else { return nil }
        // A time that has already passed today means tomorrow, not a negative timer.
        return candidate > now ? candidate : calendar.date(byAdding: .day, value: 1, to: candidate)
    }

    /// `4m`, `25m`, `1h 30m`, `2h`. Used wherever a length is described rather than counted down.
    public static func short(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        if total < 60 { return "\(total)s" }
        let minutes = total / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    /// `24:13` under an hour, `1:24:13` above it. Monospaced-digit friendly.
    public static func countdown(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded(.up)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// "Ends at 14:45", in the user's own clock format.
    public static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}
