import Foundation

/// Natural-language quick add. Examples it understands:
///
///   "Deep work 9-11am"                → block 9:00–11:00 today
///   "Standup 9:15am tomorrow 15m"     → 15-minute block tomorrow
///   "Gym fri 6pm 1h"                  → 1-hour block next Friday
///   "Lunch 12pm"                      → block at noon, default length
///   "Review PRD"                      → block at the next free slot
///   "todo Buy milk tomorrow !!"       → medium-priority reminder due tomorrow
///   "t Send invoice fri 5pm ~30m"     → reminder w/ due time + 30m estimate
///
/// Prefixes "t ", "todo ", "task " or "- " force a task; everything else
/// becomes a time block. "!" = low, "!!" = medium, "!!!" = high priority.
/// "~30m" attaches a time estimate to a task.
enum QuickAddParser {

    enum Kind {
        case block, task
    }

    struct Result {
        var kind: Kind = .block
        var title: String = ""
        /// For blocks: start time. For tasks: due date.
        var date: Date?
        var hasExplicitTime: Bool = false
        var durationMinutes: Int?
        var priority: TaskPriority = .none
        var estimateMinutes: Int?

        var isValid: Bool { !title.isEmpty }
    }

    static func parse(_ rawInput: String, defaultDurationMinutes: Int = 30, reference: Date = Date()) -> Result {
        var text = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = Result()

        // 1. Kind prefix
        for prefix in ["todo ", "task ", "t ", "- "] {
            if text.lowercased().hasPrefix(prefix) {
                result.kind = .task
                text = String(text.dropFirst(prefix.count))
                break
            }
        }

        // 2. Priority (!!! before !! before !)
        for (marker, priority) in [("!!!", TaskPriority.high), ("!!", .medium), ("!", .low)] {
            if let range = text.range(of: marker) {
                result.priority = priority
                text.removeSubrange(range)
                if result.kind == .block { result.kind = .task } // priority implies task
                break
            }
        }

        // 3. Estimate "~30m" / "~1h"
        if let (minutes, range) = firstDuration(in: text, prefixedBy: "~") {
            result.estimateMinutes = minutes
            text.removeSubrange(range)
            result.kind = .task
        }

        // 4. Day words
        var day = reference.startOfDay
        if let (foundDay, range) = firstDayReference(in: text, reference: reference) {
            day = foundDay
            text.removeSubrange(range)
        }

        // 5. Time range "9-11am", "9:30am-10:15", "14:00-15:30"
        if let (start, end, range) = firstTimeRange(in: text, on: day) {
            result.date = start
            result.hasExplicitTime = true
            result.durationMinutes = max(5, Int(end.timeIntervalSince(start) / 60))
            text.removeSubrange(range)
        }
        // 6. Single time "3pm", "at 15:30"
        else if let (time, range) = firstSingleTime(in: text, on: day) {
            result.date = time
            result.hasExplicitTime = true
            text.removeSubrange(range)
        }
        // A bare day word ("tomorrow") still sets the date.
        else if !day.isSameDay(as: reference) {
            result.date = day
        }

        // 7. Standalone duration "45m", "1.5h", "for 2h"
        if result.durationMinutes == nil, let (minutes, range) = firstDuration(in: text, prefixedBy: "") {
            result.durationMinutes = minutes
            text.removeSubrange(range)
        }

        if result.kind == .block, result.durationMinutes == nil {
            result.durationMinutes = defaultDurationMinutes
        }

        // 8. Whatever is left is the title.
        result.title = text
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))

        return result
    }

    // MARK: - Matchers

    private static func regexMatch(_ pattern: String, in text: String) -> (match: NSTextCheckingResult, range: Range<String.Index>)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text)
        else { return nil }
        return (match, range)
    }

    private static func group(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String? {
        guard index < match.numberOfRanges, let range = Range(match.range(at: index), in: text) else { return nil }
        return String(text[range])
    }

    /// "45m", "1h", "1.5h", optionally prefixed ("for ", "~").
    private static func firstDuration(in text: String, prefixedBy prefix: String) -> (Int, Range<String.Index>)? {
        let escapedPrefix = NSRegularExpression.escapedPattern(for: prefix)
        let pattern = "(?:\\bfor\\s+)?\(escapedPrefix)(\\d+(?:\\.\\d+)?)\\s*(h|hr|hrs|hours?|m|min|mins|minutes?)\\b"
        guard let (match, range) = regexMatch(pattern, in: text),
              let numberText = group(match, 1, in: text),
              let unit = group(match, 2, in: text)?.lowercased(),
              let number = Double(numberText)
        else { return nil }
        let minutes = unit.hasPrefix("h") ? Int(number * 60) : Int(number)
        guard minutes > 0 else { return nil }
        return (minutes, range)
    }

    /// today / tomorrow / tmr / weekday names ("fri", "friday", "next fri").
    private static func firstDayReference(in text: String, reference: Date) -> (Date, Range<String.Index>)? {
        let cal = Calendar.current
        let today = reference.startOfDay

        if let (_, range) = regexMatch("\\btoday\\b|\\btonight\\b", in: text) {
            return (today, range)
        }
        if let (_, range) = regexMatch("\\btomorrow\\b|\\btmr\\b|\\btmrw\\b", in: text) {
            return (today.adding(days: 1), range)
        }

        // Weekday names — full or 3-letter, optional "next" (= skip a week).
        let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        let pattern = "\\b(next\\s+)?(sun|mon|tue|tues|wed|thu|thur|thurs|fri|sat)(day|sday|nesday|rsday|urday)?\\b"
        guard let (match, range) = regexMatch(pattern, in: text),
              let stem = group(match, 2, in: text)?.lowercased()
        else { return nil }

        guard let weekdayIndex = names.firstIndex(where: { $0.hasPrefix(String(stem.prefix(3))) }) else { return nil }
        let target = weekdayIndex + 1 // Calendar weekday: 1 = Sunday
        let current = cal.component(.weekday, from: today)
        var delta = (target - current + 7) % 7
        if delta == 0 { delta = 7 } // "friday" on a Friday means next week's
        if group(match, 1, in: text) != nil { delta += 7 }
        return (today.adding(days: delta), range)
    }

    /// "9-11am", "9:30am-10:15am", "14:00-15:30".
    private static func firstTimeRange(in text: String, on day: Date) -> (Date, Date, Range<String.Index>)? {
        let time = "(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)?"
        let pattern = "\\b\(time)\\s*(?:-|–|to)\\s*\(time)\\b"
        guard let (match, range) = regexMatch(pattern, in: text) else { return nil }

        let startHour = group(match, 1, in: text).flatMap { Int($0) }
        let startMin = group(match, 2, in: text).flatMap { Int($0) } ?? 0
        let startMeridiem = group(match, 3, in: text)?.lowercased()
        let endHour = group(match, 4, in: text).flatMap { Int($0) }
        let endMin = group(match, 5, in: text).flatMap { Int($0) } ?? 0
        let endMeridiem = group(match, 6, in: text)?.lowercased()

        guard let sh = startHour, let eh = endHour else { return nil }

        // "9-11am" — the start inherits the end's meridiem.
        let effectiveStartMeridiem = startMeridiem ?? endMeridiem
        guard var startMinutes = minutesOfDay(hour: sh, minute: startMin, meridiem: effectiveStartMeridiem),
              var endMinutes = minutesOfDay(hour: eh, minute: endMin, meridiem: endMeridiem)
        else { return nil }

        // "11-1pm" style wrap: if end <= start, assume it crosses noon/midnight.
        if endMinutes <= startMinutes {
            if endMinutes + 12 * 60 <= 24 * 60, endMeridiem == nil {
                endMinutes += 12 * 60
            } else if startMinutes >= 12 * 60, effectiveStartMeridiem == nil {
                startMinutes -= 12 * 60
            } else {
                endMinutes = startMinutes + 60
            }
        }

        return (day.at(minutes: startMinutes), day.at(minutes: endMinutes), range)
    }

    /// "3pm", "at 15:30", "9:15am". Bare numbers require am/pm or an "at"
    /// prefix so "review 3 designs" doesn't grow a start time.
    private static func firstSingleTime(in text: String, on day: Date) -> (Date, Range<String.Index>)? {
        let pattern = "\\b(?:at\\s+)?(\\d{1,2})(?::(\\d{2}))\\s*(am|pm)?\\b|\\b(?:at\\s+)?(\\d{1,2})\\s*(am|pm)\\b"
        guard let (match, range) = regexMatch(pattern, in: text) else { return nil }

        let hour: Int?
        let minute: Int
        let meridiem: String?
        if let h = group(match, 1, in: text).flatMap({ Int($0) }) {
            hour = h
            minute = group(match, 2, in: text).flatMap { Int($0) } ?? 0
            meridiem = group(match, 3, in: text)?.lowercased()
        } else {
            hour = group(match, 4, in: text).flatMap { Int($0) }
            minute = 0
            meridiem = group(match, 5, in: text)?.lowercased()
        }

        guard let h = hour, let minutes = minutesOfDay(hour: h, minute: minute, meridiem: meridiem) else { return nil }
        return (day.at(minutes: minutes), range)
    }

    private static func minutesOfDay(hour: Int, minute: Int, meridiem: String?) -> Int? {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        var h = hour
        if meridiem == "pm", h < 12 { h += 12 }
        if meridiem == "am", h == 12 { h = 0 }
        guard h < 24 else { return nil }
        return h * 60 + minute
    }
}
