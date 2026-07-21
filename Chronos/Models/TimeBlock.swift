import SwiftUI

/// An immutable snapshot of a calendar event, rendered by the timeline.
/// The `id` is unique per *occurrence* (recurring events share an
/// `eventID` but differ by start date). All mutation goes through
/// `EventKitService`, which keeps the live `EKEvent` instances cached
/// under the same ids.
struct TimeBlock: Identifiable, Hashable {
    let id: String
    let eventID: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var calendarID: String
    var calendarTitle: String
    var color: Color
    var notes: String?
    var location: String?
    var linkedTaskID: String?
    var hasRecurrence: Bool
    var isEditable: Bool
    /// True when the event carries an explicit per-block color (a Chronos
    /// `[color:…]` override) — so category color-coding leaves it alone.
    var hasColorOverride: Bool = false
    /// True when Chronos itself created this block (a planned "time block"), via
    /// its origin marker or a linked task — as opposed to a real external event
    /// (a doctor's appointment). Real events don't get the focus timer and are
    /// counted as attended/focused automatically.
    var isChronosBlock: Bool = false
    /// A detected video-conferencing link (Zoom/Meet/Teams/…) if the event
    /// carries one — powers the "Join" button.
    var meetingURL: URL? = nil
    var meetingPlatform: String? = nil

    var hasMeeting: Bool { meetingURL != nil }
    /// A real (non-Chronos) event: not created by Plan My Day or the block
    /// creator, and not an all-day banner.
    var isRealEvent: Bool { !isChronosBlock && !isAllDay }

    var duration: TimeInterval { end.timeIntervalSince(start) }
    var durationMinutes: Int { max(0, Int(duration / 60)) }

    var isPast: Bool { end < Date() }
    var isNow: Bool {
        let now = Date()
        return start <= now && now < end
    }

    func overlaps(_ other: TimeBlock) -> Bool {
        start < other.end && other.start < end
    }

    /// Portion of the block that falls on `day`, clamped to that day's
    /// bounds — lets blocks spanning midnight render correctly.
    func clamped(to day: Date) -> (start: Date, end: Date)? {
        let dayStart = day.startOfDay
        let dayEnd = dayStart.adding(days: 1)
        let s = max(start, dayStart)
        let e = min(end, dayEnd)
        guard s < e else { return nil }
        return (s, e)
    }
}

/// Everything needed to create or edit a block, decoupled from EventKit
/// so editors can be pure SwiftUI.
struct BlockDraft {
    var title: String = ""
    var calendarID: String?
    var start: Date = .nextCleanSlot()
    var end: Date = Date.nextCleanSlot().adding(minutes: 30)
    var isAllDay: Bool = false
    var location: String = ""
    var urlString: String = ""
    var notes: String = ""
    /// Per-block color override (nil = use the calendar's color).
    var colorHex: UInt32?
    var recurrence: RecurrenceOption = .none
    var alarm: AlarmOption = .none
    var secondAlarm: AlarmOption = .none
    var availability: EventAvailability = .busy
    /// Minutes of travel buffer to add as a preceding block (0 = none).
    var travelMinutes: Int = 0
    var linkedTaskID: String?
    /// Explicit category tag for this event's series (nil = auto-detect from
    /// the title). Applied to TagStore on save, keyed by the event series id.
    var categoryOverride: ActivityCategory?

    /// Snapshot of the recurrence/alarm the event had when editing began;
    /// rules are only rewritten when the user actually changes the picker,
    /// so exotic rules created in Apple Calendar survive a Chronos edit.
    var originalRecurrence: RecurrenceOption = .none
    var originalAlarm: AlarmOption = .none
    var originalSecondAlarm: AlarmOption = .none
    var originalTravelMinutes: Int = 0

    var durationMinutes: Int {
        max(0, Int(end.timeIntervalSince(start) / 60))
    }
}

/// Per-event metadata Chronos keeps inside the event's notes — currently a
/// color override (`[color:7C8CF8]`) so blocks can be colour-coded
/// independently of their calendar and still sync everywhere EventKit does.
enum BlockMetadata {
    private static let colorPattern = "\\[color:([0-9A-Fa-f]{6})\\]"
    /// Marks a block Chronos itself created (a planned "time block") as opposed
    /// to a real external event synced from Apple Calendar (a doctor's
    /// appointment). Timeblocks get the focus timer; real events don't.
    private static let chronosToken = "[chronos:tb]"
    private static let chronosPattern = "\\[chronos:tb\\]"
    private static let allPatterns = [colorPattern, chronosPattern]

    static func colorHex(from notes: String?) -> UInt32? {
        guard let notes,
              let regex = try? NSRegularExpression(pattern: colorPattern),
              let match = regex.firstMatch(in: notes, range: NSRange(notes.startIndex..., in: notes)),
              let range = Range(match.range(at: 1), in: notes)
        else { return nil }
        return UInt32(notes[range], radix: 16)
    }

    /// True when the notes carry the Chronos-origin marker.
    static func isChronos(from notes: String?) -> Bool {
        guard let notes else { return false }
        return notes.contains(chronosToken)
    }

    static func strippingTokens(_ notes: String?) -> String? {
        guard var cleaned = notes else { return nil }
        for pattern in allPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            cleaned = regex.stringByReplacingMatches(
                in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned), withTemplate: ""
            )
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    static func encode(notes: String, colorHex: UInt32?, chronos: Bool = false) -> String? {
        let base = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !base.isEmpty { parts.append(base) }
        if let colorHex { parts.append(String(format: "[color:%06X]", colorHex)) }
        if chronos { parts.append(chronosToken) }
        let joined = parts.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }
}

/// Identifiable wrapper that drives the block editor sheet.
struct BlockEditorContext: Identifiable {
    let id = UUID()
    var draft: BlockDraft
    /// Occurrence id of the block being edited; nil when creating.
    var existingID: String?
    var isRecurring: Bool = false
    /// Read-only attendee display names, if the event has any.
    var attendees: [String] = []
}
