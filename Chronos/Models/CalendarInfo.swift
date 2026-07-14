import SwiftUI
import EventKit

/// Lightweight snapshot of an EKCalendar (event calendar or reminder list).
struct CalendarInfo: Identifiable, Hashable {
    let id: String
    var title: String
    var color: Color
    var isEditable: Bool
    var sourceTitle: String
    /// True for read-only subscribed feeds (e.g. a Canvas/Schoology .ics).
    var isSubscribed: Bool = false
    /// True when the calendar lives only on this device (a local `webcal`
    /// subscription) rather than in iCloud — meaning it won't appear on the
    /// user's other devices.
    var isLocalSubscription: Bool = false
}

/// Free/busy status shown to others — mirrors EKEventAvailability.
enum EventAvailability: Int, CaseIterable, Identifiable {
    case busy, free, tentative, unavailable
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .busy: return "Busy"
        case .free: return "Free"
        case .tentative: return "Tentative"
        case .unavailable: return "Unavailable"
        }
    }

    func ek() -> EKEventAvailability {
        switch self {
        case .busy: return .busy
        case .free: return .free
        case .tentative: return .tentative
        case .unavailable: return .unavailable
        }
    }

    /// The calendar-capability mask bit, to check whether a calendar
    /// supports this availability before setting it.
    var mask: EKCalendarEventAvailabilityMask {
        switch self {
        case .busy: return .busy
        case .free: return .free
        case .tentative: return .tentative
        case .unavailable: return .unavailable
        }
    }

    static func from(_ availability: EKEventAvailability) -> EventAvailability {
        switch availability {
        case .free: return .free
        case .tentative: return .tentative
        case .unavailable: return .unavailable
        default: return .busy
        }
    }
}

enum RecurrenceOption: String, CaseIterable, Identifiable {
    case none = "Never"
    case daily = "Every Day"
    case weekdays = "Weekdays"
    case weekly = "Every Week"
    case biweekly = "Every 2 Weeks"
    case monthly = "Every Month"
    case yearly = "Every Year"
    /// An existing rule Chronos doesn't model (e.g. "3rd Tuesday"); kept
    /// as-is unless the user picks something else.
    case custom = "Custom"

    var id: String { rawValue }

    /// Options offered in the editor picker (custom is display-only).
    static var pickable: [RecurrenceOption] {
        allCases.filter { $0 != .custom }
    }

    func rule() -> EKRecurrenceRule? {
        switch self {
        case .none, .custom:
            return nil
        case .daily:
            return EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        case .weekdays:
            let days: [EKRecurrenceDayOfWeek] = [
                EKRecurrenceDayOfWeek(.monday), EKRecurrenceDayOfWeek(.tuesday),
                EKRecurrenceDayOfWeek(.wednesday), EKRecurrenceDayOfWeek(.thursday),
                EKRecurrenceDayOfWeek(.friday),
            ]
            return EKRecurrenceRule(
                recurrenceWith: .weekly, interval: 1, daysOfTheWeek: days,
                daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil,
                daysOfTheYear: nil, setPositions: nil, end: nil
            )
        case .weekly:
            return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        case .biweekly:
            return EKRecurrenceRule(recurrenceWith: .weekly, interval: 2, end: nil)
        case .monthly:
            return EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)
        case .yearly:
            return EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)
        }
    }

    static func from(rules: [EKRecurrenceRule]?) -> RecurrenceOption {
        guard let rule = rules?.first else { return .none }
        switch (rule.frequency, rule.interval) {
        case (.daily, 1):
            return rule.daysOfTheWeek == nil ? .daily : .custom
        case (.weekly, 1):
            if let days = rule.daysOfTheWeek {
                let weekdays: Set<EKWeekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
                return Set(days.map(\.dayOfTheWeek)) == weekdays ? .weekdays : .custom
            }
            return .weekly
        case (.weekly, 2):
            return rule.daysOfTheWeek == nil ? .biweekly : .custom
        case (.monthly, 1):
            return rule.daysOfTheMonth == nil && rule.setPositions == nil ? .monthly : .custom
        case (.yearly, 1):
            return .yearly
        default:
            return .custom
        }
    }
}

enum AlarmOption: Int, CaseIterable, Identifiable {
    case none = -1
    case atTime = 0
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .none: return "None"
        case .atTime: return "At time of event"
        case .fiveMinutes: return "5 minutes before"
        case .fifteenMinutes: return "15 minutes before"
        case .thirtyMinutes: return "30 minutes before"
        case .oneHour: return "1 hour before"
        }
    }

    func alarm() -> EKAlarm? {
        guard self != .none else { return nil }
        return EKAlarm(relativeOffset: TimeInterval(-rawValue * 60))
    }

    static func from(alarms: [EKAlarm]?) -> AlarmOption {
        guard let alarm = alarms?.first else { return .none }
        let minutesBefore = Int(-alarm.relativeOffset / 60)
        return AlarmOption(rawValue: minutesBefore) ?? .fifteenMinutes
    }
}
