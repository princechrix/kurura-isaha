import XCTest
@testable import KururaCore

final class PullScaleTests: XCTestCase {
    private let travel: CGFloat = 1000

    private func log(_ snap: Bool = false) -> PullScale {
        PullScale(mode: .logarithmic, travel: travel, snapToFiveMinutes: snap)
    }

    // MARK: - Endpoints

    func testNoPullIsTheMinimum() {
        XCTAssertEqual(log().duration(for: 0), PullScale.minimum)
    }

    func testPullingUpwardsCannotGoBelowTheMinimum() {
        XCTAssertEqual(log().duration(for: -400), PullScale.minimum)
    }

    func testFullTravelIsTheMaximum() {
        XCTAssertEqual(log().duration(for: travel), PullScale.maximum)
    }

    func testPullingPastTheBottomStaysAtTheMaximum() {
        XCTAssertEqual(log().duration(for: travel * 3), PullScale.maximum)
    }

    /// The headline promise of the curve: half a screen is a quarter of an hour, so the
    /// entire top half is spent on the 1–15 minute range people actually tune finely.
    func testHalfTheScreenIsFifteenMinutes() {
        XCTAssertEqual(log().duration(for: travel / 2), 15 * 60)
    }

    // MARK: - Shape

    func testDurationNeverDecreasesAsThePullGrows() {
        let scale = log()
        var previous = TimeInterval(0)
        for pixel in stride(from: CGFloat(0), through: travel, by: 1) {
            let value = scale.duration(for: pixel)
            XCTAssertGreaterThanOrEqual(value, previous, "went backwards at \(pixel)px")
            previous = value
        }
    }

    func testShortPullsResolveToWholeMinutes() {
        let scale = log()
        for pixel in stride(from: CGFloat(0), through: travel / 2, by: 5) {
            let value = scale.duration(for: pixel)
            XCTAssertEqual(value.truncatingRemainder(dividingBy: 60), 0, "not a whole minute at \(pixel)px")
        }
    }

    func testLongPullsRoundToCoarserSteps() {
        // Nothing above two hours should ever land on an odd minute count.
        let scale = log()
        for pixel in stride(from: travel * 0.9, through: travel, by: 1) {
            let value = scale.duration(for: pixel)
            guard value >= 2 * 3600 else { continue }
            XCTAssertEqual(value.truncatingRemainder(dividingBy: 1800), 0)
        }
    }

    func testOptionSnapProducesFiveMinuteMultiples() {
        let scale = log(true)
        for pixel in stride(from: CGFloat(0), through: travel, by: 3) {
            let value = scale.duration(for: pixel)
            XCTAssertEqual(value.truncatingRemainder(dividingBy: 300), 0, "not a 5m multiple at \(pixel)px")
        }
    }

    // MARK: - Linear mode

    func testLinearModeIsTenPixelsPerMinute() {
        let scale = PullScale(mode: .linear, travel: travel)
        XCTAssertEqual(scale.rawDuration(for: 100), 600)
        XCTAssertEqual(scale.rawDuration(for: 250), 1500)
    }

    func testLinearModeStillHonoursTheCeiling() {
        let scale = PullScale(mode: .linear, travel: travel)
        XCTAssertEqual(scale.duration(for: 100_000), PullScale.maximum)
    }

    // MARK: - Inverse

    func testDistanceRoundTripsThroughRawDuration() {
        let scale = log()
        for minutes in [1.0, 5.0, 15.0, 30.0, 60.0, 120.0, 240.0] {
            let seconds = minutes * 60
            let pixels = scale.distance(for: seconds)
            XCTAssertEqual(scale.rawDuration(for: pixels), seconds, accuracy: 0.5, "\(minutes)m")
        }
    }

    // MARK: - Presets

    func testPresetsTrackTheBands() {
        XCTAssertEqual(PullPreset.forDuration(3 * 60).name, "Quick")
        XCTAssertEqual(PullPreset.forDuration(10 * 60).name, "Sprint")
        XCTAssertEqual(PullPreset.forDuration(25 * 60).name, "Focus")
        XCTAssertEqual(PullPreset.forDuration(45 * 60).name, "Deep Work")
        XCTAssertEqual(PullPreset.forDuration(90 * 60).name, "Session")
        XCTAssertEqual(PullPreset.forDuration(200 * 60).name, "Marathon")
    }
}
