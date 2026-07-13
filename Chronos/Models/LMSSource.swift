import Foundation

/// A learning-management system Chronos can pull assignments from via its
/// public calendar (.ics) feed.
enum LMSProvider: String, Codable, CaseIterable, Identifiable {
    case canvas, schoology, other
    var id: String { rawValue }

    var name: String {
        switch self {
        case .canvas: return "Canvas"
        case .schoology: return "Schoology"
        case .other: return "Other (.ics feed)"
        }
    }

    var icon: String {
        switch self {
        case .canvas: return "graduationcap.fill"
        case .schoology: return "book.fill"
        case .other: return "link"
        }
    }

    /// Step-by-step for finding the calendar feed URL, shown during setup.
    var steps: [String] {
        switch self {
        case .canvas:
            return [
                "Open Canvas in a web browser and go to Calendar.",
                "Scroll down the right sidebar and click “Calendar Feed”.",
                "Copy the feed link (it starts with https:// and ends in .ics).",
                "Paste it below."
            ]
        case .schoology:
            return [
                "Open Schoology and go to your Calendar.",
                "Click the gear / settings icon, then “iCal Feed”.",
                "Copy the feed URL it shows you.",
                "Paste it below."
            ]
        case .other:
            return [
                "Find your school calendar's iCal / .ics subscription URL.",
                "It usually starts with https:// or webcal:// and ends in .ics.",
                "Paste it below."
            ]
        }
    }
}

/// A configured LMS feed: which subscribed calendar it maps to, and which
/// reminder list its assignments land in.
struct LMSSource: Codable, Identifiable {
    var id = UUID()
    var provider: LMSProvider
    var name: String
    var calendarID: String
    var listID: String
    var lastSyncEpoch: TimeInterval?
}

/// Decides whether an item from an LMS calendar is a deadline (→ becomes a
/// reminder) or a genuine scheduled event (→ stays on the calendar). The core
/// heuristic: a real span of time is a class / office hours / exam; a
/// point-in-time or all-day entry is a due date.
enum LMSClassifier {
    enum Kind { case assignment, event }

    static let eventKeywords = [
        "lecture", "class", "office hour", "seminar", "section", "recitation",
        "lab", "exam", "midterm", "final", "review session", "meeting",
        "workshop", "discussion section", "tutorial", "no class", "holiday", "break"
    ]

    static func classify(title: String, isAllDay: Bool, durationMinutes: Int) -> Kind {
        let t = title.lowercased()
        // A real block of scheduled time is almost always a class or meeting.
        if !isAllDay && durationMinutes >= 20 { return .event }
        // An all-day entry that names a real event (holiday, exam day) stays.
        if isAllDay && eventKeywords.contains(where: t.contains) { return .event }
        // Everything else is a deadline moment.
        return .assignment
    }
}
