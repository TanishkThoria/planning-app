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
    /// A detected video-conferencing link (Zoom/Meet/Teams/…) if the event
    /// carries one — powers the "Join" button.
    var meetingURL: URL? = nil
    var meetingPlatform: String? = nil

    var hasMeeting: Bool { meetingURL != nil }

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

    static func colorHex(from notes: String?) -> UInt32? {
        guard let notes,
              let regex = try? NSRegularExpression(pattern: colorPattern),
              let match = regex.firstMatch(in: notes, range: NSRange(notes.startIndex..., in: notes)),
              let range = Range(match.range(at: 1), in: notes)
        else { return nil }
        return UInt32(notes[range], radix: 16)
    }

    static func strippingTokens(_ notes: String?) -> String? {
        guard let notes, let regex = try? NSRegularExpression(pattern: colorPattern) else { return notes }
        let cleaned = regex.stringByReplacingMatches(
            in: notes, range: NSRange(notes.startIndex..., in: notes), withTemplate: ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    static func encode(notes: String, colorHex: UInt32?) -> String? {
        let base = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !base.isEmpty { parts.append(base) }
        if let colorHex { parts.append(String(format: "[color:%06X]", colorHex)) }
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
