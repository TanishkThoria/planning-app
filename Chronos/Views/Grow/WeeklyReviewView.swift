import SwiftUI

/// A guided weekly review — the GTD-style ritual of looking back before
/// looking forward. Celebrates the week's numbers, checks goals and habits,
/// and flows straight into planning the week ahead.
struct WeeklyReviewView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var focusLog: FocusLog
    @EnvironmentObject private var life: LifeStore
    @Environment(\.dismiss) private var dismiss

    private var days: [Date] {
        let today = Date().startOfDay
        return (0..<7).map { today.adding(days: -6 + $0) }
    }

    private var stats: StatsEngine.Stats {
        StatsEngine.compute(
            days: days,
            blocks: { service.blocks(on: $0, hiddenCalendars: model.hiddenCalendarIDs) },
            allTasks: service.tasks,
            taskLookup: { service.task(withID: $0) },
            sessions: focusLog.sessions
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Rectangle().fill(Theme.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro
                    statTiles
                    goalsSection
                    habitsSection
                }
                .padding(18)
            }
            .scrollIndicators(.hidden)

            Rectangle().fill(Theme.hairline).frame(height: 1)
            footer
        }
        .background(
            LinearGradient(colors: [Color.accentColor.opacity(0.12), Theme.elevated],
                           startPoint: .top, endPoint: .center).ignoresSafeArea()
        )
        .background(Theme.elevated)
        .preferredColorScheme(.dark)
        #if os(macOS)
        .frame(width: 480, height: 640)
        #else
        .presentationDetents([.large])
        #endif
    }

    private var headerBar: some View {
        HStack {
            Button("Close") { dismiss() }
                .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text("Weekly Review").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("Close").font(.system(size: 13)).hidden()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "calendar.badge.checkmark").font(.system(size: 28)).foregroundStyle(Color.accentColor)
            Text("Look back before you leap")
                .font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
            if let first = days.first, let last = days.last {
                Text("\(Fmt.monthDay.string(from: first)) – \(Fmt.monthDay.string(from: last))")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var statTiles: some View {
        HStack(spacing: 10) {
            tile("\(stats.tasksCompleted)", "Done")
            tile(Fmt.duration(minutes: stats.plannedMinutes), "Planned")
            tile(Fmt.duration(minutes: stats.focusMinutes), "Focused")
            tile("\(Int((stats.completionRate * 100).rounded()))%", "On-plan")
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 19, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel(padding: 12)
    }

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Goals this week")
            if life.activeGoals.isEmpty {
                Text("No goals yet — set one to give next week direction.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(life.activeGoals) { goal in
                    let p = goalProgress(goal)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            HStack(spacing: 6) {
                                Circle().fill(goal.color).frame(width: 7, height: 7)
                                Text(goal.title.isEmpty ? "Untitled goal" : goal.title)
                                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                            }
                            Spacer()
                            Text("\(Int((p * 100).rounded()))%")
                                .font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(goal.color)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.fill)
                                Capsule().fill(goal.color).frame(width: min(geo.size.width, geo.size.width * p))
                            }
                        }
                        .frame(height: 5)
                    }
                }
            }
        }
        .panel()
    }

    private func goalProgress(_ goal: Goal) -> Double {
        switch goal.kind {
        case .time:
            let minutes = days.reduce(0) { acc, day in
                acc + service.blocks(on: day)
                    .filter { !$0.isAllDay && (goal.linkedCalendarID == nil || $0.calendarID == goal.linkedCalendarID) }
                    .compactMap { $0.clamped(to: day) }
                    .reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) }
            }
            let target = goal.weeklyHoursTarget * 60
            return target <= 0 ? 0 : min(1, Double(minutes) / target)
        case .milestone:
            return goal.milestoneProgress
        case .habitLink:
            guard let hid = goal.linkedHabitID, let habit = life.habits.first(where: { $0.id == hid }) else { return 0 }
            return min(1, Double(life.completionCount(habit, inLast: 7)) / 7)
        }
    }

    private var habitsSection: some View {
        let habits = life.activeHabits
        var due = 0, done = 0
        for day in days {
            for habit in habits where habit.isDue(on: day) {
                due += 1
                if life.isDone(habit, on: day) { done += 1 }
            }
        }
        let rate = due == 0 ? 0 : Double(done) / Double(due)
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Habits")
            if habits.isEmpty {
                Text("No habits tracked yet.").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            } else {
                HStack {
                    Text("\(done) of \(due) completed").font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(Int((rate * 100).rounded()))%")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(rate >= 0.7 ? Theme.success : Theme.warning)
                }
            }
        }
        .panel()
    }

    private var footer: some View {
        HStack {
            Button {
                model.eveningRitualPresented = true
            } label: {
                Text("Reflect").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                model.selectedDate = Date().startOfDay.adding(days: 7).startOfWeek
                dismiss()
                model.planWeekPresented = true
            } label: {
                Label("Plan Next Week", systemImage: "wand.and.stars")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.bg)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .padding(14)
    }
}
