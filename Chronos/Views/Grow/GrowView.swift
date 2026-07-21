import SwiftUI

/// The personal-growth hub: long-term goals, daily habits with streaks, and
/// the reflection journal — the "who am I becoming" counterpart to the
/// calendar's "what am I doing today." All local, all yours.
struct GrowView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var life: LifeStore

    private var today: Date { Date().startOfDay }

    private var weekDays: [Date] {
        let start = today.startOfWeek
        return (0..<7).map { start.adding(days: $0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 12)

            Rectangle().fill(Theme.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    journalCard
                    goalsSection
                    habitsSection
                    projectsSection
                    selfSection
                }
                .padding(18)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.bg)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Grow")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Goals, habits & reflection")
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            HeaderIconButton(icon: "chart.line.uptrend.xyaxis", label: "Trends") {
                model.trendsPresented = true
            }
            Menu {
                Button { model.goalEditor = GoalEditContext(goal: Goal(), isNew: true) } label: {
                    Label("New Goal", systemImage: "target")
                }
                Button { model.habitEditor = HabitEditContext(habit: Habit(), isNew: true) } label: {
                    Label("New Habit", systemImage: "repeat")
                }
                Button { model.journalPresented = true } label: {
                    Label("Open Journal", systemImage: "book.closed")
                }
                Button { model.routinesPresented = true } label: {
                    Label("Guided Routines", systemImage: "figure.walk.motion")
                }
                Divider()
                Button { model.projectsInitialID = nil; model.projectsPresented = true } label: {
                    Label("New Project", systemImage: "square.stack.3d.up")
                }
                Button { model.personalGrowthPresented = true } label: {
                    Label("Personal Growth", systemImage: "arrow.up.heart")
                }
                Button { model.niceToHavesPresented = true } label: {
                    Label("Nice-to-haves", systemImage: "star")
                }
                Divider()
                Button { model.weeklyReviewPresented = true } label: {
                    Label("Weekly Review", systemImage: "calendar.badge.checkmark")
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.bg)
                    .frame(width: 28, height: 26)
                    .background(Theme.accentColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .menuIndicator(.hidden)
        }
    }

    // MARK: Journal card

    private var journalCard: some View {
        let entry = life.entry(for: today)
        let morning = entry?.hasMorning ?? false
        let evening = entry?.hasEvening ?? false
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Daily rituals", systemImage: "sparkles")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if life.journalStreak > 0 {
                    Label("\(life.journalStreak)d", systemImage: "flame.fill")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.warning)
                }
                Button { model.journalPresented = true } label: {
                    Text("History").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.accentColor)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 10) {
                ritualButton("Morning", subtitle: "Set intentions", done: morning,
                             icon: "sunrise.fill", tint: Theme.warning) { model.morningRitualPresented = true }
                ritualButton("Evening", subtitle: "Reflect", done: evening,
                             icon: "moon.stars.fill", tint: Theme.accentChoices[0].color) { model.eveningRitualPresented = true }
            }
        }
        .panel()
    }

    private func ritualButton(_ label: String, subtitle: String, done: Bool, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: done ? "checkmark.circle.fill" : icon)
                    .font(.system(size: 16))
                    .foregroundStyle(done ? Theme.success : tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(done ? "Done" : subtitle).font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11).padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(done ? tint.opacity(0.1) : Theme.fill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Goals

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Goals", trailing: "\(life.activeGoals.count)")
                Spacer(minLength: 8)
                Button {
                    model.goalEditor = GoalEditContext(goal: Goal(), isNew: true)
                } label: {
                    Image(systemName: "plus").font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.accentColor)
                }
                .buttonStyle(.plain)
            }
            if life.activeGoals.isEmpty {
                emptyRow("target", "Set a goal", "Give your weeks a direction — hours on what matters, or a milestone to hit.")
            } else {
                ForEach(life.activeGoals) { goal in
                    goalRow(goal)
                }
            }
        }
    }

    private func goalRow(_ goal: Goal) -> some View {
        let p = progress(for: goal)
        return Button {
            model.goalEditor = GoalEditContext(goal: goal, isNew: false)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Theme.fill, lineWidth: 4)
                    Circle().trim(from: 0, to: max(0.001, min(1, p.fraction)))
                        .stroke(goal.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: goal.kind.icon)
                        .font(.system(size: 13.5))
                        .foregroundStyle(goal.color)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.title.isEmpty ? "Untitled goal" : goal.title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(p.label)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text("\(Int((p.fraction * 100).rounded()))%")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(goal.color)
            }
            .panel(padding: 12)
        }
        .buttonStyle(.plain)
    }

    /// (fraction 0…1, human label) for a goal's current progress.
    private func progress(for goal: Goal) -> (fraction: Double, label: String) {
        switch goal.kind {
        case .time:
            let minutes = weekMinutes(calendarID: goal.linkedCalendarID)
            let targetMin = goal.weeklyHoursTarget * 60
            let frac = targetMin <= 0 ? 0 : Double(minutes) / targetMin
            return (frac, "\(Fmt.duration(minutes: minutes)) of \(Fmt.duration(minutes: Int(targetMin))) this week")
        case .milestone:
            if let deadline = goal.deadline {
                let days = Calendar.current.dateComponents([.day], from: today, to: deadline.startOfDay).day ?? 0
                let countdown = days > 0 ? "\(days)d left" : (days == 0 ? "due today" : "overdue")
                return (goal.milestoneProgress, "\(Int((goal.milestoneProgress * 100).rounded()))% · \(countdown)")
            }
            return (goal.milestoneProgress, "\(Int((goal.milestoneProgress * 100).rounded()))% complete")
        case .habitLink:
            if let hid = goal.linkedHabitID, let habit = life.habits.first(where: { $0.id == hid }) {
                let streak = life.streak(habit)
                let done = life.completionCount(habit, inLast: 7)
                return (min(1, Double(done) / 7), "\(streak)-day streak · \(done)/7 this week")
            }
            return (0, "Link a habit to track")
        }
    }

    private func weekMinutes(calendarID: String?) -> Int {
        weekDays.reduce(0) { acc, day in
            acc + service.blocks(on: day)
                .filter { !$0.isAllDay && (calendarID == nil || $0.calendarID == calendarID) }
                .compactMap { $0.clamped(to: day) }
                .reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) }
        }
    }

    // MARK: Habits

    private var habitsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Habits", trailing: "\(life.activeHabits.count)")
                Spacer(minLength: 8)
                Button {
                    model.habitEditor = HabitEditContext(habit: Habit(), isNew: true)
                } label: {
                    Image(systemName: "plus").font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.accentColor)
                }
                .buttonStyle(.plain)
            }
            if life.activeHabits.isEmpty {
                emptyRow("repeat", "Build a habit", "Small, daily, repeated. Track a streak and watch it compound.")
            } else {
                ForEach(life.activeHabits) { habit in
                    habitRow(habit)
                }
            }
        }
    }

    private func habitRow(_ habit: Habit) -> some View {
        let done = life.doneToday(habit)
        let streak = life.streak(habit)
        return HStack(spacing: 12) {
            Button {
                withAnimation(.snappy) { life.toggle(habit, on: today) }
                Haptics.success()
            } label: {
                ZStack {
                    Circle().fill(done ? habit.color : Theme.fill)
                        .frame(width: 34, height: 34)
                    Image(systemName: done ? "checkmark" : habit.iconName)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(done ? Theme.bg : habit.color)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(habit.title.isEmpty ? "Untitled habit" : habit.title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                weekDots(habit)
            }
            Spacer()
            if streak > 0 {
                Label("\(streak)", systemImage: "flame.fill")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(Theme.warning)
            }
        }
        .panel(padding: 12)
        .contentShape(Rectangle())
        .onTapGesture { model.habitEditor = HabitEditContext(habit: habit, isNew: false) }
        .contextMenu {
            Button { model.habitEditor = HabitEditContext(habit: habit, isNew: false) } label: {
                Label("Edit", systemImage: "pencil")
            }
            if life.canFreeze(habit, on: today.adding(days: -1)) {
                Button {
                    withAnimation(.snappy) { life.freeze(habit, on: today.adding(days: -1)) }
                    Haptics.light()
                } label: {
                    Label("Freeze yesterday (\(2 - life.freezesUsed(habit)) left this month)",
                          systemImage: "snowflake")
                }
            }
            Button(role: .destructive) { life.deleteHabit(habit.id) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func weekDots(_ habit: Habit) -> some View {
        HStack(spacing: 4) {
            ForEach(weekDays, id: \.self) { day in
                let done = life.isDone(habit, on: day)
                let due = habit.isDue(on: day)
                let future = day > today
                Circle()
                    .fill(done ? habit.color : (due && !future ? Theme.fill : Color.clear))
                    .overlay(
                        Circle().strokeBorder(
                            day.isToday ? habit.color.opacity(0.8) : Theme.hairline,
                            lineWidth: day.isToday ? 1.5 : 1
                        )
                    )
                    .frame(width: 12, height: 12)
            }
        }
    }

    // MARK: Projects

    private var projectsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Projects", trailing: "\(life.activeProjects.count)")
                Spacer(minLength: 8)
                Button {
                    model.projectsInitialID = nil
                    model.projectsPresented = true
                } label: {
                    Image(systemName: "plus").font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Theme.accentColor)
                }
                .buttonStyle(.plain)
            }
            if life.activeProjects.isEmpty {
                Button { model.projectsPresented = true } label: {
                    emptyRow("square.stack.3d.up", "Track a long-term project",
                             "Milestones, updates, and progress for the big things — a thesis, a launch, getting fit.")
                }
                .buttonStyle(.plain)
            } else {
                ForEach(life.activeProjects.prefix(4)) { project in
                    projectRow(project)
                }
                if life.activeProjects.count > 4 {
                    Button { model.projectsPresented = true } label: {
                        Text("See all \(life.activeProjects.count) projects")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Theme.accentColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func projectRow(_ project: Project) -> some View {
        Button {
            model.projectsInitialID = project.id
            model.projectsPresented = true
        } label: {
            HStack(spacing: 12) {
                ProjectRing(progress: project.progress, color: project.color, emoji: project.emoji, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.title.isEmpty ? "Untitled project" : project.title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(projectSubtitle(project))
                        .font(.system(size: 12.5))
                        .foregroundStyle(project.isUpdateDue ? Theme.warning : Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(Int((project.progress * 100).rounded()))%")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(project.color)
            }
            .panel(padding: 12)
        }
        .buttonStyle(.plain)
    }

    private func projectSubtitle(_ project: Project) -> String {
        if project.isUpdateDue { return "Update due · \(project.updateCadence.short.lowercased())" }
        if !project.milestones.isEmpty {
            return "\(project.doneMilestoneCount)/\(project.milestones.count) milestones"
        }
        if let days = project.daysUntilTarget {
            if days == 0 { return "Target today" }
            return days < 0 ? "\(-days)d past target" : "\(days) days left"
        }
        return "In progress"
    }

    // MARK: Self (personal growth + nice-to-haves)

    private var selfSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Self")
            hubRow("arrow.up.heart.fill", "Personal growth",
                   "Start & stop doing, and the things you like about yourself",
                   tint: Color(hex: 0x5BD899)) { model.personalGrowthPresented = true }
            hubRow("star.fill", "Nice-to-haves",
                   "Fun & downtime for when the work is done",
                   tint: Theme.warning) { model.niceToHavesPresented = true }
        }
    }

    private func hubRow(_ icon: String, _ title: String, _ subtitle: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(subtitle).font(.system(size: 12.5)).foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.textTertiary)
            }
            .panel(padding: 12)
        }
        .buttonStyle(.plain)
    }

    private func emptyRow(_ icon: String, _ title: String, _ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 19))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                Text(message).font(.system(size: 12.5)).foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .panel(padding: 12)
    }
}
