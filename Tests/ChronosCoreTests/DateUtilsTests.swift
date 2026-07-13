import XCTest
@testable import ChronosCore

/// Unit tests for the platform-agnostic date math. These run on Linux in CI,
/// giving fast, real verification of the trickiest calendar logic without an
/// Apple SDK. Kept timezone-robust (day-relative assertions only).
final class DateUtilsTests: XCTestCase {

    /// A fixed reference instant built in the current calendar.
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func testStartOfDayZeroesTheClock() {
        let d = date(2026, 3, 14, 9, 37)
        XCTAssertEqual(d.startOfDay.minutesSinceMidnight, 0)
        XCTAssertTrue(Calendar.current.isDate(d.startOfDay, inSameDayAs: d))
    }

    func testMinutesSinceMidnight() {
        XCTAssertEqual(date(2026, 3, 14, 9, 37).minutesSinceMidnight, 9 * 60 + 37)
        XCTAssertEqual(date(2026, 3, 14, 0, 0).minutesSinceMidnight, 0)
        XCTAssertEqual(date(2026, 3, 14, 23, 59).minutesSinceMidnight, 23 * 60 + 59)
    }

    func testAtMinutesRoundTrip() {
        let day = date(2026, 3, 14).startOfDay
        XCTAssertEqual(day.at(minutes: 545).minutesSinceMidnight, 545)
        XCTAssertEqual(day.at(minutes: 0).minutesSinceMidnight, 0)
    }

    func testAddingDaysAndMinutes() {
        let d = date(2026, 3, 14, 10, 0)
        XCTAssertEqual(d.adding(minutes: 90).minutesSinceMidnight, 11 * 60 + 30)
        XCTAssertTrue(Calendar.current.isDate(d.adding(days: 1), inSameDayAs: date(2026, 3, 15)))
    }

    func testSnapping() {
        let base = date(2026, 3, 14).startOfDay
        XCTAssertEqual(base.at(minutes: 37).snapped(to: 15).minutesSinceMidnight, 30)  // rounds down
        XCTAssertEqual(base.at(minutes: 38).snapped(to: 15).minutesSinceMidnight, 45)  // rounds up
        XCTAssertEqual(base.at(minutes: 37).snappedDown(to: 15).minutesSinceMidnight, 30)
        XCTAssertEqual(base.at(minutes: 44).snappedDown(to: 15).minutesSinceMidnight, 30)
        // A zero increment is a no-op (guard against divide-by-zero).
        XCTAssertEqual(base.at(minutes: 37).snapped(to: 0).minutesSinceMidnight, 37)
    }

    func testStartOfWeek() {
        let d = date(2026, 3, 14)          // a specific day
        let s = d.startOfWeek
        // The week start is at midnight, on/before the day, within 7 days,
        // and idempotent — regardless of the locale's first weekday.
        XCTAssertEqual(s.minutesSinceMidnight, 0)
        XCTAssertTrue(s <= d.startOfDay)
        XCTAssertTrue(s.startOfWeek.isSameDay(as: s))
        let days = Calendar.current.dateComponents([.day], from: s, to: d.startOfDay).day ?? -1
        XCTAssertTrue((0...6).contains(days))
    }

    func testDayKeyIsStableFormat() {
        XCTAssertEqual(Fmt.dayKey(date(2026, 3, 14, 9, 37)), "2026-03-14")
        XCTAssertEqual(Fmt.dayKey(date(2026, 12, 1)), "2026-12-01")
    }

    func testDurationFormatting() {
        XCTAssertEqual(Fmt.duration(minutes: 5), "5m")
        XCTAssertEqual(Fmt.duration(minutes: 45), "45m")
        XCTAssertEqual(Fmt.duration(minutes: 60), "1h")
        XCTAssertEqual(Fmt.duration(minutes: 90), "1h 30m")
        XCTAssertEqual(Fmt.duration(minutes: 125), "2h 5m")
    }

    func testIsSameDay() {
        XCTAssertTrue(date(2026, 3, 14, 1, 0).isSameDay(as: date(2026, 3, 14, 23, 0)))
        XCTAssertFalse(date(2026, 3, 14).isSameDay(as: date(2026, 3, 15)))
    }
}
