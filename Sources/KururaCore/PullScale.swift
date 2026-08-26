import CoreGraphics
import Foundation

/// How pixels dragged turn into minutes.
public enum ScalingMode: String, Codable, CaseIterable, Sendable {
    /// Constant *ratio* per pixel. Short pulls stay precise, long pulls cover hours.
    case logarithmic
    /// Constant seconds per pixel. Predictable, but the bottom of the screen is
    /// only ever worth ~1h45m on a laptop display.
    case linear

    public var title: String {
        switch self {
        case .logarithmic: return "Logarithmic (recommended)"
        case .linear: return "Linear (10 px = 1 min)"
        }
    }
}

/// Which end of the range a duration sits at. Drives the colour of the pull line.
public enum PullTier: Sendable {
    case short   // under a quarter hour
    case medium  // under an hour
    case long    // an hour and up
}

/// The named band a duration falls into, shown live in the HUD while dragging.
public struct PullPreset: Sendable, Equatable {
    public let name: String
    public let symbol: String

    public init(name: String, symbol: String) {
        self.name = name
        self.symbol = symbol
    }

    public static func forDuration(_ duration: TimeInterval) -> PullPreset {
        switch duration {
        case ..<(5 * 60):   return PullPreset(name: "Quick", symbol: "bolt.fill")
        case ..<(15 * 60):  return PullPreset(name: "Sprint", symbol: "hare.fill")
        case ..<(30 * 60):  return PullPreset(name: "Focus", symbol: "scope")
        case ..<(60 * 60):  return PullPreset(name: "Deep Work", symbol: "brain.head.profile")
        case ..<(120 * 60): return PullPreset(name: "Session", symbol: "book.fill")
        default:            return PullPreset(name: "Marathon", symbol: "mountain.2.fill")
        }
    }
}

/// Maps a downward drag into a duration.
///
/// Deliberately pure. The entire feel of the app is one function of (pixels dragged,
/// travel available, modifier keys), and that is exactly the part worth being able to
/// exercise without a menu bar attached — see `PullScaleTests`.
public struct PullScale: Sendable {
    /// Shortest timer a pull can produce. Dragging up past the menu bar reads as this.
    public static let minimum: TimeInterval = 60
    /// Longest timer a full-height pull can produce.
    public static let maximum: TimeInterval = 4 * 3600
    /// Linear mode's constant, from the spec: 10 px is one minute.
    public static let secondsPerPixel: TimeInterval = 6
    /// Below this a mouseDown/mouseUp is a click that opens the menu, not a pull.
    public static let dragThreshold: CGFloat = 6

    public let mode: ScalingMode
    public let travel: CGFloat
    public let snapToFiveMinutes: Bool

    /// - Parameter travel: usable pull height, normally the distance from the status
    ///   item down to the bottom of its screen. Floored so that a very short display
    ///   (or a status item dragged near the bottom of a stacked layout) stays usable.
    public init(mode: ScalingMode, travel: CGFloat, snapToFiveMinutes: Bool = false) {
        self.mode = mode
        self.travel = max(travel, 200)
        self.snapToFiveMinutes = snapToFiveMinutes
    }

    /// Unquantised duration for a drag of `distance` points below the menu bar.
    public func rawDuration(for distance: CGFloat) -> TimeInterval {
        let clamped = max(0, distance)
        switch mode {
        case .linear:
            return clamp(TimeInterval(clamped) * Self.secondsPerPixel)
        case .logarithmic:
            // A constant ratio per pixel rather than constant seconds. With the range
            // 1 min … 4 h this puts the halfway point of the screen at ~15 minutes,
            // which is where the presets change character anyway.
            let progress = min(1, TimeInterval(clamped) / TimeInterval(travel))
            return clamp(Self.minimum * pow(Self.maximum / Self.minimum, progress))
        }
    }

    /// What the HUD shows and what the timer is actually set to.
    ///
    /// Granularity widens with length, so a three-hour pull does not shiver by single
    /// minutes under a hand that is merely resting.
    public func duration(for distance: CGFloat) -> TimeInterval {
        let raw = rawDuration(for: distance)
        let step = snapToFiveMinutes ? 300 : Self.step(for: raw)
        let snapped = max(step, (raw / step).rounded() * step)
        return clamp(snapped)
    }

    /// Rounding increment used at a given length.
    public static func step(for duration: TimeInterval) -> TimeInterval {
        switch duration {
        case ..<(15 * 60):  return 60
        case ..<(60 * 60):  return 5 * 60
        case ..<(120 * 60): return 15 * 60
        default:            return 30 * 60
        }
    }

    public static func tier(for duration: TimeInterval) -> PullTier {
        switch duration {
        case ..<(15 * 60): return .short
        case ..<(60 * 60): return .medium
        default:           return .long
        }
    }

    /// Distance, in points, at which `duration` would be produced. Used to place the
    /// tick marks the line draws itself against.
    public func distance(for duration: TimeInterval) -> CGFloat {
        let target = clamp(duration)
        switch mode {
        case .linear:
            return CGFloat(target / Self.secondsPerPixel)
        case .logarithmic:
            let progress = log(target / Self.minimum) / log(Self.maximum / Self.minimum)
            return CGFloat(progress) * travel
        }
    }

    private func clamp(_ seconds: TimeInterval) -> TimeInterval {
        min(max(seconds, Self.minimum), Self.maximum)
    }
}

/// Everything the overlay needs to render one frame of a drag.
public struct PullReading: Sendable {
    public let distance: CGFloat
    public let duration: TimeInterval
    public let preset: PullPreset
    public let tier: PullTier

    public init(distance: CGFloat, scale: PullScale) {
        let duration = scale.duration(for: distance)
        self.distance = distance
        self.duration = duration
        self.preset = PullPreset.forDuration(duration)
        self.tier = PullScale.tier(for: duration)
    }

    /// When a timer committed right now would end.
    public func endDate(from now: Date = Date()) -> Date {
        now.addingTimeInterval(duration)
    }
}
