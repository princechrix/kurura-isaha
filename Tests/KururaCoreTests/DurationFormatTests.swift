import XCTest
@testable import KururaCore

final class TimerSnapshotTests: XCTestCase {
    private func snapshot(tag: String, preset: String, note: String?) -> TimerSnapshot {
        TimerSnapshot(
            id: "abc123", tag: tag, preset: preset, kind: .timer,
            startedAt: Date(), endsAt: Date().addingTimeInterval(600), note: note)
    }

    func testReminderWinsOverTag() {
        let timer = snapshot(tag: "Coding", preset: "Sprint", note: "take the bread out")
        XCTAssertEqual(timer.displayLabel, "take the bread out")
        XCTAssertTrue(timer.hasNote)
    }

    func testTagIsUsedWhenNoReminderWasGiven() {
        XCTAssertEqual(snapshot(tag: "Coding", preset: "Sprint", note: nil).displayLabel, "Coding")
    }

    func testPresetIsTheLastResort() {
        XCTAssertEqual(snapshot(tag: "", preset: "Sprint", note: nil).displayLabel, "Sprint")
    }

    /// Skipping the prompt writes nothing, and an empty note must not shadow the tag.
    func testEmptyReminderIsNotAReminder() {
        let timer = snapshot(tag: "Coding", preset: "Sprint", note: "")
        XCTAssertFalse(timer.hasNote)
        XCTAssertEqual(timer.displayLabel, "Coding")
    }

    /// A snapshot persisted before the reminder field existed still has to load.
    func testDecodesWithoutTheReminderField() throws {
        let legacy = """
            {"id":"abc123","tag":"Coding","preset":"Sprint","kind":"timer",
             "startedAt":"2026-08-26T07:56:22Z","endsAt":"2026-08-26T08:21:22Z","isPaused":false}
            """
        let timer = try ControlCoding.decoder().decode(TimerSnapshot.self, from: Data(legacy.utf8))
        XCTAssertNil(timer.note)
        XCTAssertEqual(timer.displayLabel, "Coding")
    }
}

final class DurationFormatTests: XCTestCase {
    func testParsesUnitSuffixes() {
        XCTAssertEqual(DurationFormat.parse("25m"), 1500)
        XCTAssertEqual(DurationFormat.parse("2h"), 7200)
        XCTAssertEqual(DurationFormat.parse("90s"), 90)
    }

    func testParsesCompoundDurations() {
        XCTAssertEqual(DurationFormat.parse("1h30m"), 5400)
        XCTAssertEqual(DurationFormat.parse("1h 30m"), 5400)
        XCTAssertEqual(DurationFormat.parse("1h30"), 5400)
    }

    func testBareNumberIsMinutes() {
        XCTAssertEqual(DurationFormat.parse("25"), 1500)
    }

    func testRejectsNonsense() {
        XCTAssertNil(DurationFormat.parse(""))
        XCTAssertNil(DurationFormat.parse("soon"))
        XCTAssertNil(DurationFormat.parse("25x"))
        XCTAssertNil(DurationFormat.parse("0"))
    }

    func testShortFormatting() {
        XCTAssertEqual(DurationFormat.short(45), "45s")
        XCTAssertEqual(DurationFormat.short(1500), "25m")
        XCTAssertEqual(DurationFormat.short(5400), "1h 30m")
        XCTAssertEqual(DurationFormat.short(7200), "2h")
    }

    func testCountdownFormatting() {
        XCTAssertEqual(DurationFormat.countdown(1453), "24:13")
        XCTAssertEqual(DurationFormat.countdown(5053), "1:24:13")
        XCTAssertEqual(DurationFormat.countdown(-5), "0:00")
    }

    func testClockTimeResolvesForward() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let noon = calendar.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 12))!

        let afternoon = DurationFormat.parseClockTime("14:45", from: noon, calendar: calendar)
        XCTAssertEqual(afternoon, calendar.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 14, minute: 45)))

        // A time already past today means tomorrow, never a negative timer.
        let morning = DurationFormat.parseClockTime("09:00", from: noon, calendar: calendar)
        XCTAssertEqual(morning, calendar.date(from: DateComponents(year: 2026, month: 8, day: 27, hour: 9)))
    }

    func testClockTimeUnderstandsMeridiem() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 8))!
        let target = DurationFormat.parseClockTime("2:05pm", from: morning, calendar: calendar)
        XCTAssertEqual(target, calendar.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 14, minute: 5)))
    }
}
