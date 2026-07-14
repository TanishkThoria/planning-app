import SwiftUI

/// Builds a "Year in Review" from everything Chronos knows — the Spotify
/// Wrapped moment for your time. Computed on demand from EventKit, the focus
/// log, and the lifestyle stores; nothing leaves the device.
@MainActor
enum WrappedEngine {

    struct TopCalendar: Identifiable {
        let id: String
        let title: String
        let color: Color
        let minutes: Int
    }

    struct Summary {
        var periodLabel: String
        var focusHours: Int
        var focusSessions: Int
        var longestFocusMinutes: Int
        var scheduledHours: Int
        var blockCount: Int
        var tasksCompleted: Int
        var topCalendars: [TopCalendar]
        var bestHabitStreak: Int
        var journalEntries: Int
        var mostProductiveWeekday: String?
        var deepHours: Int
        var hasEnoughData: Bool
    }

    static func compute(service: EventKitService, focusLog: FocusLog, life: LifeStore) async -> Summary {
        let cal = Calendar.current
        let now = Date()
        let yearStart = cal.date(from: cal.dateComponents([.year], from: now)) ?? now.startOfDay
        let year = cal.component(.year, from: now)

        // Focus log (full local history).
        let sessions = focusLog.sessions.filter { $0.start >= yearStart }
        let focusMinutes = sessions.reduce(0) { $0 + $1.actualMinutes }
        let longest = sessions.map(\.actualMinutes).max() ?? 0

        // Most productive weekday by focus minutes.
        var weekdayMinutes: [Int: Int] = [:]
        for session in sessions {
            let wd = cal.component(.weekday, from: session.start)
            weekdayMinutes[wd, default: 0] += session.actualMinutes
        }
        let mostProductiveWeekday = weekdayMinutes.max { $0.value < $1.value }.map {
            cal.weekdaySymbols[$0.key - 1]
        }

        // Calendar events over the year (direct EventKit query).
        let blocks = service.blocks(from: yearStart, to: now)
        var scheduledMinutes = 0
        var deepMinutes = 0
        var byCalendar: [String: (title: String, color: Color, minutes: Int)] = [:]
        for block in blocks {
            let m = block.durationMinutes
            scheduledMinutes += m
            if block.linkedTaskID.flatMap({ service.task(withID: $0) })?.energy == .deep {
                deepMinutes += m
            }
            var entry = byCalendar[block.calendarID] ?? (block.calendarTitle, block.color, 0)
            entry.minutes += m
            byCalendar[block.calendarID] = entry
        }
        let top = byCalendar
            .map { TopCalendar(id: $0.key, title: $0.value.title, color: $0.value.color, minutes: $0.value.minutes) }
            .sorted { $0.minutes > $1.minutes }
            .prefix(3)

        let tasksCompleted = await service.completedTaskCount(since: yearStart)
        let bestStreak = life.activeHabits.map { life.streak($0) }.max() ?? 0
        let yearPrefix = String(year)
        let journalCount = life.journal.filter {
            $0.dayKey.hasPrefix(yearPrefix) && ($0.hasMorning || $0.hasEvening)
        }.count

        let enough = focusMinutes > 0 || blocks.count > 5 || tasksCompleted > 5

        return Summary(
            periodLabel: "\(year)",
            focusHours: focusMinutes / 60,
            focusSessions: sessions.count,
            longestFocusMinutes: longest,
            scheduledHours: scheduledMinutes / 60,
            blockCount: blocks.count,
            tasksCompleted: tasksCompleted,
            topCalendars: Array(top),
            bestHabitStreak: bestStreak,
            journalEntries: journalCount,
            mostProductiveWeekday: mostProductiveWeekday,
            deepHours: deepMinutes / 60,
            hasEnoughData: enough
        )
    }
}
