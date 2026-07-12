import Foundation

extension Date {

    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    var endOfDay: Date {
        Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay) ?? self
    }

    func adding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }

    func adding(minutes: Int) -> Date {
        Calendar.current.date(byAdding: .minute, value: minutes, to: self) ?? self
    }

    /// Minutes elapsed since this date's own midnight.
    var minutesSinceMidnight: Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: self)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    /// Returns this date's day with the clock set to `minutes` past midnight.
    func at(minutes: Int) -> Date {
        Calendar.current.date(byAdding: .minute, value: minutes, to: startOfDay) ?? self
    }

    var isToday: Bool { Calendar.current.isDateInToday(self) }

    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }

    /// First day of the week containing this date, honouring the user's
    /// locale (Sunday vs Monday start).
    var startOfWeek: Date {
        let cal = Calendar.current
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return cal.date(from: comps) ?? startOfDay
    }

    /// Rounds to the nearest snap increment (e.g. 15 minutes).
    func snapped(to minutes: Int) -> Date {
        guard minutes > 0 else { return self }
        let mins = minutesSinceMidnight
        let snapped = Int((Double(mins) / Double(minutes)).rounded()) * minutes
        return startOfDay.adding(minutes: snapped)
    }

    /// Rounds down to the snap increment.
    func snappedDown(to minutes: Int) -> Date {
        guard minutes > 0 else { return self }
        let mins = minutesSinceMidnight
        return startOfDay.adding(minutes: (mins / minutes) * minutes)
    }

    /// The next "clean" boundary from now — used when creating a block
    /// without an explicit time.
    static func nextCleanSlot(snap: Int = 15) -> Date {
        let now = Date()
        let snapped = now.snappedDown(to: snap)
        return snapped < now ? snapped.adding(minutes: snap) : snapped
    }
}

/// Cached formatters — building DateFormatters per-frame is a classic
/// scrolling performance killer.
enum Fmt {

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f
    }()

    static let hourLabel: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("j")
        return f
    }()

    static let weekdayFull: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEE")
        return f
    }()

    static let weekdayShort: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f
    }()

    /// Narrow single-letter weekday (M, T, W…) for tight week grids.
    static let weekdayNarrow: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEEE")
        return f
    }()

    static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMd")
        return f
    }()

    static let monthDayYear: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMdyyyy")
        return f
    }()

    static let monthTitle: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return f
    }()

    static let dayNumber: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("d")
        return f
    }()

    static func timeRange(_ start: Date, _ end: Date) -> String {
        "\(time.string(from: start))–\(time.string(from: end))"
    }

    static func duration(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    static func duration(_ interval: TimeInterval) -> String {
        duration(minutes: max(0, Int(interval / 60)))
    }

    /// "Today", "Tomorrow", "Yesterday" or "Thu, Jul 17".
    static func relativeDay(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return f.string(from: date)
    }
}
