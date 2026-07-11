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
    var recurrence: RecurrenceOption = .none
    var alarm: AlarmOption = .none
    var linkedTaskID: String?

    /// Snapshot of the recurrence/alarm the event had when editing began;
    /// rules are only rewritten when the user actually changes the picker,
    /// so exotic rules created in Apple Calendar survive a Chronos edit.
    var originalRecurrence: RecurrenceOption = .none
    var originalAlarm: AlarmOption = .none

    var durationMinutes: Int {
        max(0, Int(end.timeIntervalSince(start) / 60))
    }
}

/// Identifiable wrapper that drives the block editor sheet.
struct BlockEditorContext: Identifiable {
    let id = UUID()
    var draft: BlockDraft
    /// Occurrence id of the block being edited; nil when creating.
    var existingID: String?
    var isRecurring: Bool = false
}
