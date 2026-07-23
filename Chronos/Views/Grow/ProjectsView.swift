import SwiftUI

/// The long-term projects hub: everything you're building over weeks or months,
/// with milestones to break it down, dated updates to keep a record, and a
/// progress reading that comes from either your milestones or your own feel.
struct ProjectsView: View {
    @EnvironmentObject private var life: LifeStore
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var editing: Project?
    @State private var path: [UUID] = []

    private var projects: [Project] { life.activeProjects }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if projects.isEmpty {
                        emptyState
                    } else {
                        ForEach(projects) { project in
                            Button { path.append(project.id) } label: { projectCard(project) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(Theme.Metric.screen)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg)
            .navigationTitle("Projects")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(for: UUID.self) { id in
                ProjectDetailView(projectID: id, onEdit: { editing = $0 })
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = Project() } label: { Image(systemName: "plus") }
                }
            }
        }
        .chronosAppearance()
        .sheet(item: $editing) { project in
            ProjectEditorView(project: project, isNew: !projects.contains { $0.id == project.id })
        }
        .onAppear {
            if let id = model.projectsInitialID {
                model.projectsInitialID = nil
                if life.project(id) != nil { path = [id] }
            }
        }
    }

    // MARK: Card

    private func projectCard(_ project: Project) -> some View {
        HStack(spacing: 14) {
            ProjectRing(progress: project.progress, color: project.color, emoji: project.emoji)
            VStack(alignment: .leading, spacing: 4) {
                Text(project.title.isEmpty ? "Untitled project" : project.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    if !project.milestones.isEmpty {
                        metaChip("\(project.doneMilestoneCount)/\(project.milestones.count)", "flag.checkered")
                    }
                    if let days = project.daysUntilTarget {
                        metaChip(targetLabel(days), "target", warn: days < 0)
                    }
                    if project.isUpdateDue {
                        metaChip("Update due", "pencil.line", warn: true)
                    }
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metric.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Metric.radius, style: .continuous)
            .strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private func metaChip(_ text: String, _ icon: String, warn: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            Text(text).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(warn ? Theme.warning : Theme.textTertiary)
    }

    private func targetLabel(_ days: Int) -> String {
        if days == 0 { return "Due today" }
        if days < 0 { return "\(-days)d over" }
        return "\(days)d left"
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 34))
                .foregroundStyle(Theme.accentColor)
            Text("Track the big things")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("A thesis, a side project, getting fit — anything that takes weeks. Add milestones to break it down and log updates to keep momentum.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button { editing = Project() } label: {
                Text("New project")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.bg)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(Theme.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 20)
    }

}

/// A progress ring with an emoji core, used on every project card & header.
struct ProjectRing: View {
    let progress: Double
    let color: Color
    let emoji: String
    var size: CGFloat = 46

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.16), lineWidth: 4)
            Circle().trim(from: 0, to: max(0.001, progress))
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(emoji).font(.system(size: size * 0.42))
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Detail

/// One project up close: progress, milestones you can check off, and a running
/// log of dated updates.
struct ProjectDetailView: View {
    let projectID: UUID
    var onEdit: (Project) -> Void

    @EnvironmentObject private var life: LifeStore
    @EnvironmentObject private var service: EventKitService
    @Environment(\.dismiss) private var dismiss

    @State private var newMilestone = ""
    @State private var updateText = ""
    @State private var stampProgress = true
    @State private var weekGoalText = ""
    @State private var editingUpdate: ProjectUpdate?
    @State private var editingTimeEntry: ProjectTimeEntry?
    @State private var loggingTime = false
    @State private var schedulingWork = false
    @State private var linkingPresented = false
    @State private var showAllWeeks = false
    @FocusState private var composing: Bool

    private var project: Project? { life.project(projectID) }

    var body: some View {
        Group {
            if let project {
                content(project)
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
    }

    private func content(_ project: Project) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                headerCard(project)
                progressCard(project)
                weeklyObjectiveSection(project)
                timeSection(project)
                milestonesSection(project)
                linkedSection(project)
                updatesSection(project)
            }
            .padding(Theme.Metric.screen)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg)
        .navigationTitle(project.title.isEmpty ? "Project" : project.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $editingUpdate) { update in
            ProjectUpdateEditorSheet(projectID: projectID, update: update)
                .environmentObject(life)
        }
        .sheet(item: $editingTimeEntry) { entry in
            ProjectTimeEntrySheet(projectID: projectID, entry: entry)
                .environmentObject(life)
        }
        .sheet(isPresented: $loggingTime) {
            ProjectTimeEntrySheet(projectID: projectID, entry: nil)
                .environmentObject(life)
        }
        .sheet(isPresented: $linkingPresented) {
            ProjectLinkPicker(projectID: projectID)
                .environmentObject(life)
                .environmentObject(service)
        }
        .sheet(isPresented: $schedulingWork) {
            ProjectWorkScheduleSheet(projectID: projectID)
                .environmentObject(life)
                .environmentObject(service)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { onEdit(project) } label: { Label("Edit project", systemImage: "pencil") }
                    Button {
                        var p = project; p.isComplete.toggle(); life.upsert(p); Haptics.success()
                    } label: {
                        Label(project.isComplete ? "Mark in progress" : "Mark complete",
                              systemImage: project.isComplete ? "arrow.uturn.backward" : "checkmark.circle")
                    }
                    Button {
                        var p = project; p.isArchived = true; life.upsert(p); dismiss()
                    } label: { Label("Archive", systemImage: "archivebox") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }

    // MARK: Header

    private func headerCard(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ProjectRing(progress: project.progress, color: project.color, emoji: project.emoji, size: 60)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Int((project.progress * 100).rounded()))% complete")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle(project))
                        .font(.system(size: 13.5))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            if !project.detail.isEmpty {
                Text(project.detail)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if project.isComplete {
                Label("Completed", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.success)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [project.color.opacity(0.16), Theme.surface],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private func subtitle(_ project: Project) -> String {
        var bits: [String] = []
        if let days = project.daysUntilTarget, let target = project.targetDate {
            if days == 0 { bits.append("Target today") }
            else if days < 0 { bits.append("\(-days)d past target") }
            else { bits.append("\(days)d to \(Fmt.monthDay.string(from: target))") }
        }
        bits.append(project.updateCadence.short)
        return bits.joined(separator: " · ")
    }

    // MARK: Progress (stamp a custom reading any time, independent of milestones)

    private func progressCard(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: "Progress")
                Spacer()
                if project.manualProgress != nil && !project.isComplete {
                    Button {
                        life.setProgress(nil, for: project.id); Haptics.light()
                    } label: {
                        Text(project.milestones.isEmpty ? "Clear" : "Use milestones")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 12) {
                Text("\(Int((project.progress * 100).rounded()))%")
                    .font(.system(size: 22, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 62, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { project.progress },
                        set: { life.setProgress($0, for: project.id) }
                    ),
                    in: 0...1, step: 0.01
                )
                .tint(project.color)
                .disabled(project.isComplete)
            }
            HStack(spacing: 6) {
                ForEach([0, 25, 50, 75, 100], id: \.self) { pct in
                    Button {
                        life.setProgress(Double(pct) / 100, for: project.id); Haptics.light()
                    } label: {
                        Text("\(pct)%")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(project.isComplete)
                }
            }
            Text(progressCaption(project))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private func progressCaption(_ project: Project) -> String {
        if project.isComplete { return "Marked complete — 100%." }
        if project.manualProgress != nil {
            return project.milestones.isEmpty
                ? "A reading you set by feel."
                : "Custom reading — overriding the \(project.doneMilestoneCount)/\(project.milestones.count) milestones below."
        }
        if !project.milestones.isEmpty {
            return "From \(project.doneMilestoneCount)/\(project.milestones.count) milestones. Drag to override with your own read."
        }
        if let target = project.targetHours, target > 0 {
            return "From \(timeLabel(project.totalLoggedMinutes)) of \(Fmt.duration(minutes: Int(target * 60))) logged. Drag to override."
        }
        return "Drag to set a reading, or add milestones below to track it by checklist."
    }

    // MARK: Weekly objectives (week-by-week steering for open-ended work)

    private func weeklyObjectiveSection(_ project: Project) -> some View {
        let current = project.weeklyGoal()
        let past = project.pastWeeklyGoals()
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "This week")
            if let goal = current {
                weeklyGoalRow(project, goal, isCurrent: true)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 17)).foregroundStyle(Theme.textTertiary)
                    TextField("This week's aim…", text: $weekGoalText)
                        .textFieldStyle(.plain).font(.system(size: 14.5))
                        .foregroundStyle(Theme.textPrimary)
                        .onSubmit { commitWeekGoal(project) }
                    if !weekGoalText.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button { commitWeekGoal(project) } label: {
                            Text("Set").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 11)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            }
            if current == nil {
                Text("For projects where the finish line is still fuzzy — set a small aim for the week and steer as you go.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !past.isEmpty {
                let shown = showAllWeeks ? past : Array(past.prefix(3))
                VStack(spacing: 8) {
                    ForEach(shown) { goal in weeklyGoalRow(project, goal, isCurrent: false) }
                }
                if past.count > 3 {
                    Button { withAnimation { showAllWeeks.toggle() } } label: {
                        Text(showAllWeeks ? "Show less" : "Show \(past.count - 3) earlier week\(past.count - 3 == 1 ? "" : "s")")
                            .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func weeklyGoalRow(_ project: Project, _ goal: ProjectWeeklyGoal, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            Button {
                life.toggleWeeklyGoal(goal.id, in: project.id); Haptics.light()
            } label: {
                Image(systemName: goal.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(goal.isDone ? project.color : Theme.textTertiary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.text)
                    .font(.system(size: 14.5, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(goal.isDone ? Theme.textTertiary : Theme.textPrimary)
                    .strikethrough(goal.isDone, color: Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if !isCurrent {
                    Text(weekLabel(goal.weekKey))
                        .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(isCurrent ? AnyShapeStyle(project.color.opacity(0.10)) : AnyShapeStyle(Theme.surface),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .contextMenu {
            Button(role: .destructive) {
                life.deleteWeeklyGoal(goal.id, from: project.id)
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func commitWeekGoal(_ project: Project) {
        life.setWeeklyGoal(weekGoalText, in: project.id)
        weekGoalText = ""
        Haptics.light()
    }

    private func weekLabel(_ weekKey: String) -> String {
        guard let date = Project.date(fromWeekKey: weekKey) else { return weekKey }
        return "Week of \(Fmt.monthDay.string(from: date))"
    }

    // MARK: Time logged

    private func timeSection(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Time", trailing: timeTrailing(project))
            HStack(spacing: 8) {
                ForEach([15, 30, 60], id: \.self) { mins in
                    Button {
                        life.logTime(to: project.id, minutes: mins); Haptics.success()
                    } label: {
                        Text("+\(Fmt.duration(minutes: mins))")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentColor)
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(Theme.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Button { loggingTime = true } label: {
                    Label("Custom", systemImage: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Button { schedulingWork = true } label: {
                Label("Schedule a work session", systemImage: "calendar.badge.plus")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentColor)
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(Theme.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            let entries = project.timeEntries.sorted { $0.epoch > $1.epoch }
            if entries.isEmpty {
                Text(project.targetHours != nil
                     ? "Log the hours you put in — you'll watch them add up toward your target."
                     : "Tap a chip after a work session to log time. Every bit builds the record.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 2)
            } else {
                VStack(spacing: 8) {
                    ForEach(entries.prefix(6)) { entry in timeEntryRow(project, entry) }
                }
                if entries.count > 6 {
                    Text("+ \(entries.count - 6) more logged")
                        .font(.system(size: 12)).foregroundStyle(Theme.textTertiary).padding(.leading, 2)
                }
            }
        }
    }

    private func timeTrailing(_ project: Project) -> String? {
        let total = project.totalLoggedMinutes
        guard total > 0 || project.targetHours != nil else { return nil }
        if let target = project.targetHours, target > 0 {
            return "\(timeLabel(total)) / \(Fmt.duration(minutes: Int(target * 60)))"
        }
        return timeLabel(total)
    }

    private func timeEntryRow(_ project: Project, _ entry: ProjectTimeEntry) -> some View {
        Button { editingTimeEntry = entry } label: {
            HStack(spacing: 12) {
                Text(timeLabel(entry.minutes))
                    .font(.system(size: 13.5, weight: .bold)).monospacedDigit()
                    .foregroundStyle(project.color)
                    .frame(width: 58, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.note.isEmpty ? "Focused time" : entry.note)
                        .font(.system(size: 14)).foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(Fmt.relativeDay(entry.date))
                        .font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "pencil").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { life.deleteTimeEntry(entry.id, from: project.id) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func timeLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    // MARK: Linked goals / habits / tasks

    @ViewBuilder
    private func linkedSection(_ project: Project) -> some View {
        let goals = life.linkedGoals(for: project)
        let habits = life.linkedHabits(for: project)
        let tasks = (project.linkedTaskIDs ?? []).compactMap { id in service.tasks.first { $0.id == id } }
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "Linked")
                Spacer()
                Button { linkingPresented = true } label: {
                    Label("Link", systemImage: "link")
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.accentColor)
                }
                .buttonStyle(.plain)
            }
            if goals.isEmpty && habits.isEmpty && tasks.isEmpty {
                Text("Pull in the goals, habits and tasks this project depends on, so its moving parts live in one place.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if let readout = linkedReadout(tasks: tasks, habits: habits) {
                    Text(readout)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 2)
                }
                VStack(spacing: 8) {
                    ForEach(goals) { goal in
                        linkedRow(icon: goal.kind.icon, tint: goal.color, title: goal.title,
                                  subtitle: "Goal") { life.toggleLinkedGoal(goal.id, in: project.id) }
                    }
                    ForEach(habits) { habit in
                        linkedRow(icon: habit.iconName, tint: habit.color, title: habit.title,
                                  subtitle: "Habit · \(life.streak(habit))-day streak") { life.toggleLinkedHabit(habit.id, in: project.id) }
                    }
                    ForEach(tasks) { task in
                        linkedRow(icon: task.isCompleted ? "checkmark.circle.fill" : "circle",
                                  tint: task.color, title: task.title,
                                  subtitle: task.isCompleted ? "Task · done" : "Task") { life.toggleLinkedTask(task.id, in: project.id) }
                    }
                }
            }
        }
    }

    private func linkedRow(icon: String, tint: Color, title: String, subtitle: String, unlink: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(subtitle).font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .contextMenu {
            Button(role: .destructive, action: unlink) { Label("Unlink", systemImage: "link.badge.minus") }
        }
    }

    /// A compact "how are the linked pieces doing" line — task completion and
    /// linked-habit consistency over the last week.
    private func linkedReadout(tasks: [TaskItem], habits: [Habit]) -> String? {
        var parts: [String] = []
        if !tasks.isEmpty {
            let done = tasks.filter(\.isCompleted).count
            parts.append("\(done)/\(tasks.count) tasks done")
        }
        if !habits.isEmpty {
            let did = habits.reduce(0) { $0 + life.completionCount($1, inLast: 7) }
            parts.append("habits \(did)/\(habits.count * 7) this week")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    // MARK: Milestones

    private func milestonesSection(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Milestones",
                          trailing: project.milestones.isEmpty ? nil : "\(project.doneMilestoneCount)/\(project.milestones.count)")
            VStack(spacing: 8) {
                ForEach(project.milestones) { milestone in
                    milestoneRow(project, milestone)
                }
                addMilestoneRow(project)
            }
        }
    }

    private func milestoneRow(_ project: Project, _ milestone: ProjectMilestone) -> some View {
        HStack(spacing: 12) {
            Button {
                life.toggleMilestone(milestone.id, in: project.id); Haptics.light()
            } label: {
                Image(systemName: milestone.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21))
                    .foregroundStyle(milestone.isDone ? project.color : Theme.textTertiary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(milestone.title)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(milestone.isDone ? Theme.textTertiary : Theme.textPrimary)
                    .strikethrough(milestone.isDone, color: Theme.textTertiary)
                if let target = milestone.targetDate {
                    Text(Fmt.relativeDay(target))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .contextMenu {
            Button(role: .destructive) {
                var p = project; p.milestones.removeAll { $0.id == milestone.id }; life.upsert(p)
            } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func addMilestoneRow(_ project: Project) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle").font(.system(size: 19)).foregroundStyle(Theme.textTertiary)
            TextField("Add a milestone", text: $newMilestone)
                .textFieldStyle(.plain)
                .font(.system(size: 14.5))
                .foregroundStyle(Theme.textPrimary)
                .onSubmit { commitMilestone(project) }
            if !newMilestone.trimmingCharacters(in: .whitespaces).isEmpty {
                Button { commitMilestone(project) } label: {
                    Text("Add").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func commitMilestone(_ project: Project) {
        let title = newMilestone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        var p = project
        p.milestones.append(ProjectMilestone(title: title))
        life.upsert(p)
        newMilestone = ""
        Haptics.light()
    }

    // MARK: Updates

    private func updatesSection(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Updates")
            updateComposer(project)
            if project.updates.isEmpty {
                Text("No updates yet. Jot a quick note on where things stand — you'll be glad to have the trail.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            } else {
                ForEach(project.updates.sorted { $0.epoch > $1.epoch }) { update in
                    updateRow(project, update)
                }
            }
        }
    }

    private func updateComposer(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("What happened? Where are things?", text: $updateText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14.5))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1...5)
                .focused($composing)
            HStack(spacing: 8) {
                Text("Stamp \(Int((project.progress * 100).rounded()))% progress")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                Toggle("", isOn: $stampProgress)
                    .toggleStyle(.switch)
                    .labelsHidden()
                Spacer()
                Button { commitUpdate(project) } label: {
                    Text("Log")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(canLog ? Theme.bg : Theme.textTertiary)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(canLog ? AnyShapeStyle(Theme.accentColor) : AnyShapeStyle(Theme.fill), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!canLog)
            }
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var canLog: Bool { !updateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func commitUpdate(_ project: Project) {
        let text = updateText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        life.addUpdate(to: project.id, text: text, stampProgress: stampProgress)
        updateText = ""
        composing = false
        Haptics.success()
    }

    private func updateRow(_ project: Project, _ update: ProjectUpdate) -> some View {
        Button { editingUpdate = update } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(Fmt.relativeDay(update.date))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    if let p = update.progress {
                        Text("\(Int((p * 100).rounded()))%")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(project.color)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(project.color.opacity(0.14), in: Capsule())
                    }
                    Spacer()
                    if update.wasEdited {
                        Text("edited").font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary)
                    }
                    Text(Fmt.time.string(from: update.date))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(update.text)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { editingUpdate = update } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) {
                life.deleteUpdate(update.id, from: project.id)
            } label: { Label("Delete update", systemImage: "trash") }
        }
    }
}

// MARK: - Editor

/// Create or edit a project's shape: name, look, target date, how progress is
/// measured, and how often you want to check in.
struct ProjectEditorView: View {
    @EnvironmentObject private var life: LifeStore
    @Environment(\.dismiss) private var dismiss

    @State private var project: Project
    @State private var hasTarget: Bool
    @State private var manualMode: Bool
    @State private var hasHours: Bool
    @State private var confirmingDelete = false
    let isNew: Bool

    private let emojis = ["🎯", "🚀", "📚", "💪", "🎨", "💼", "🏗️", "🌱", "🎓", "✍️", "🏃", "🧠", "🎸", "💰", "🏠", "❤️"]
    private let hourPresets: [Double] = [5, 10, 20, 40, 60, 100, 200]

    init(project: Project, isNew: Bool) {
        _project = State(initialValue: project)
        _hasTarget = State(initialValue: project.targetDate != nil)
        _manualMode = State(initialValue: project.manualProgress != nil)
        _hasHours = State(initialValue: project.targetHours != nil)
        self.isNew = isNew
    }

    var body: some View {
        EditorSheet(
            title: isNew ? "New Project" : "Edit Project",
            confirmDisabled: project.title.trimmingCharacters(in: .whitespaces).isEmpty,
            onConfirm: commit
        ) {
            TitleField(placeholder: "Project name", text: $project.title)

            FieldRow(label: "Notes") {
                TextField("What is it?", text: $project.detail, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1...3)
            }

            emojiRow
            colorRow

            FieldRow(label: "Target date") {
                Toggle("", isOn: $hasTarget).labelsHidden().toggleStyle(.switch)
            }
            if hasTarget {
                FieldRow(label: "By") {
                    DatePicker("", selection: Binding(
                        get: { project.targetDate ?? Date().adding(days: 30) },
                        set: { project.targetDate = $0 }
                    ), displayedComponents: [.date])
                    .labelsHidden()
                }
            }

            FieldRow(label: "Check-ins") {
                Picker("", selection: $project.updateCadence) {
                    ForEach(ProjectCadence.allCases) { c in Text(c.short).tag(c) }
                }
                .labelsHidden().fixedSize()
            }

            FieldRow(label: "Track by feel") {
                Toggle("", isOn: $manualMode).labelsHidden().toggleStyle(.switch)
            }
            Text(manualMode
                 ? "Starts progress as a reading you set yourself — you can still add milestones and stamp any % later."
                 : "Progress comes from the milestones you complete — you can still override it with a custom reading anytime.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 4)

            FieldRow(label: "Time target") {
                Toggle("", isOn: $hasHours).labelsHidden().toggleStyle(.switch)
            }
            if hasHours {
                FieldRow(label: "Aim for") {
                    Menu {
                        ForEach(hourPresets, id: \.self) { hrs in
                            Button("\(Int(hrs)) hours") { project.targetHours = hrs }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text("\(Int(project.targetHours ?? 10)) hours")
                                .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textPrimary)
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .fixedSize()
                }
                Text("Log time as you work and watch the hours add up toward this total — great for effort-based projects without a hard deadline.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textTertiary).padding(.horizontal, 4)
            }

            if !isNew {
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Text("Delete Project")
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Theme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        #if os(iOS)
        .presentationDetents([.large])
        #endif
        .confirmationDialog("Delete this project?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { life.deleteProject(project.id); dismiss() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func commit() {
        if !hasTarget { project.targetDate = nil }
        // "Track by feel" seeds an initial manual reading; the detail screen can
        // still stamp a custom % on a milestone project at any time.
        if manualMode { if project.manualProgress == nil { project.manualProgress = project.milestoneProgress } }
        else { project.manualProgress = nil }
        if !hasHours { project.targetHours = nil }
        else if project.targetHours == nil { project.targetHours = 10 }
        life.upsert(project)
    }

    private var emojiRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ICON").font(.system(size: 11.5, weight: .semibold)).tracking(1.2).foregroundStyle(Theme.textTertiary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(emojis, id: \.self) { e in
                        Button { project.emoji = e } label: {
                            Text(e).font(.system(size: 20))
                                .frame(width: 38, height: 38)
                                .background(project.emoji == e ? AnyShapeStyle(project.color.opacity(0.22)) : AnyShapeStyle(Theme.fill),
                                           in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(project.emoji == e ? project.color : .clear, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var colorRow: some View {
        HStack(spacing: 10) {
            ForEach(Palette.options, id: \.self) { hex in
                Button { project.colorHex = hex } label: {
                    Circle().fill(Palette.color(hex)).frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(project.colorHex == hex ? Theme.textPrimary : .clear, lineWidth: 2).padding(-3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

// MARK: - Update editor

/// Edit an existing project update — flesh out the note, adjust or remove its
/// stamped progress, or delete it.
struct ProjectUpdateEditorSheet: View {
    let projectID: UUID
    let update: ProjectUpdate

    @EnvironmentObject private var life: LifeStore
    @Environment(\.dismiss) private var dismiss

    @State private var text: String
    @State private var hasProgress: Bool
    @State private var progress: Double

    init(projectID: UUID, update: ProjectUpdate) {
        self.projectID = projectID
        self.update = update
        _text = State(initialValue: update.text)
        _hasProgress = State(initialValue: update.progress != nil)
        _progress = State(initialValue: update.progress ?? 0)
    }

    var body: some View {
        EditorSheet(
            title: "Edit Update",
            confirmDisabled: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onConfirm: save
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Text("NOTE").font(.system(size: 11, weight: .semibold)).tracking(1).foregroundStyle(Theme.textTertiary)
                TextEditor(text: $text)
                    .font(.system(size: 14.5)).scrollContentBackground(.hidden)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
            }

            FieldRow(label: "Stamp progress") {
                Toggle("", isOn: $hasProgress).labelsHidden().toggleStyle(.switch)
            }
            if hasProgress {
                VStack(spacing: 8) {
                    HStack {
                        Text("\(Int((progress * 100).rounded()))%")
                            .font(.system(size: 15, weight: .bold)).monospacedDigit().foregroundStyle(Theme.textPrimary)
                        Slider(value: $progress, in: 0...1, step: 0.01).tint(Theme.accentColor)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            Button(role: .destructive) {
                life.deleteUpdate(update.id, from: projectID); dismiss()
            } label: {
                Text("Delete Update")
                    .font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(Theme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func save() {
        var edited = update
        edited.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        edited.progress = hasProgress ? min(max(progress, 0), 1) : nil
        life.editUpdate(edited, in: projectID)
        Haptics.success()
    }
}

// MARK: - Time entry editor

/// Log a new chunk of time on a project, or edit/delete an existing one.
struct ProjectTimeEntrySheet: View {
    let projectID: UUID
    let entry: ProjectTimeEntry?

    @EnvironmentObject private var life: LifeStore
    @Environment(\.dismiss) private var dismiss

    @State private var minutes: Int
    @State private var day: Date
    @State private var note: String

    private let presets = [15, 30, 45, 60, 90, 120]

    init(projectID: UUID, entry: ProjectTimeEntry?) {
        self.projectID = projectID
        self.entry = entry
        _minutes = State(initialValue: entry?.minutes ?? 30)
        _day = State(initialValue: entry?.date ?? Date())
        _note = State(initialValue: entry?.note ?? "")
    }

    var body: some View {
        EditorSheet(
            title: entry == nil ? "Log Time" : "Edit Time",
            confirmDisabled: minutes <= 0,
            onConfirm: save
        ) {
            FieldRow(label: "Duration") {
                HStack(spacing: 10) {
                    Text(label(minutes)).font(.system(size: 14, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.textPrimary)
                    Stepper("", value: $minutes, in: 5...600, step: 5).labelsHidden()
                }
            }
            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { m in
                    Button { minutes = m } label: {
                        Text(Fmt.duration(minutes: m))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(minutes == m ? Theme.bg : Theme.textSecondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .background(minutes == m ? AnyShapeStyle(Theme.accentColor) : AnyShapeStyle(Theme.fill),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            FieldRow(label: "Day") {
                DatePicker("", selection: $day, in: ...Date(), displayedComponents: [.date]).labelsHidden()
            }

            FieldRow(label: "Note") {
                TextField("What did you work on?", text: $note)
                    .textFieldStyle(.plain).font(.system(size: 14))
                    .multilineTextAlignment(.trailing).foregroundStyle(Theme.textPrimary)
            }

            if let entry {
                Button(role: .destructive) {
                    life.deleteTimeEntry(entry.id, from: projectID); dismiss()
                } label: {
                    Text("Delete Entry")
                        .font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(Theme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func label(_ m: Int) -> String {
        if m < 60 { return "\(m)m" }
        let h = m / 60, r = m % 60
        return r == 0 ? "\(h)h" : "\(h)h \(r)m"
    }

    private func save() {
        if let entry {
            var edited = entry
            edited.minutes = minutes
            edited.epoch = day.timeIntervalSince1970
            edited.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
            life.updateTimeEntry(edited, in: projectID)
        } else {
            life.logTime(to: projectID, minutes: minutes,
                         note: note.trimmingCharacters(in: .whitespacesAndNewlines), on: day)
        }
        Haptics.success()
    }
}

// MARK: - Link picker

/// Pick which goals, habits and tasks belong to a project. Toggles apply
/// immediately, so it's just a "Done" away.
struct ProjectLinkPicker: View {
    let projectID: UUID

    @EnvironmentObject private var life: LifeStore
    @EnvironmentObject private var service: EventKitService
    @Environment(\.dismiss) private var dismiss

    private enum Kind: String, CaseIterable, Identifiable { case goals = "Goals", habits = "Habits", tasks = "Tasks"; var id: String { rawValue } }
    @State private var kind: Kind = .goals

    private var project: Project? { life.project(projectID) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 8) {
                        switch kind {
                        case .goals: goalsList
                        case .habits: habitsList
                        case .tasks: tasksList
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .background(Theme.bg)
            .navigationTitle("Link to project")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .chronosAppearance()
    }

    @ViewBuilder private var goalsList: some View {
        let linked = Set(project?.linkedGoalIDs ?? [])
        if life.activeGoals.isEmpty {
            emptyHint("No goals yet. Add goals in Grow and they'll show up here.")
        } else {
            ForEach(life.activeGoals) { goal in
                pickRow(icon: goal.kind.icon, tint: goal.color, title: goal.title,
                        subtitle: goal.kind.label, on: linked.contains(goal.id)) {
                    life.toggleLinkedGoal(goal.id, in: projectID); Haptics.light()
                }
            }
        }
    }

    @ViewBuilder private var habitsList: some View {
        let linked = Set(project?.linkedHabitIDs ?? [])
        if life.activeHabits.isEmpty {
            emptyHint("No habits yet. Build habits in Grow and they'll show up here.")
        } else {
            ForEach(life.activeHabits) { habit in
                pickRow(icon: habit.iconName, tint: habit.color, title: habit.title,
                        subtitle: "\(life.streak(habit))-day streak", on: linked.contains(habit.id)) {
                    life.toggleLinkedHabit(habit.id, in: projectID); Haptics.light()
                }
            }
        }
    }

    @ViewBuilder private var tasksList: some View {
        let linked = Set(project?.linkedTaskIDs ?? [])
        let candidates = service.tasks
            .filter { !$0.isCompleted || linked.contains($0.id) }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .prefix(40)
        if candidates.isEmpty {
            emptyHint("No open tasks. Reminders you add show up here to link.")
        } else {
            ForEach(Array(candidates)) { task in
                pickRow(icon: task.isCompleted ? "checkmark.circle.fill" : "circle", tint: task.color,
                        title: task.title, subtitle: task.listName, on: linked.contains(task.id)) {
                    life.toggleLinkedTask(task.id, in: projectID); Haptics.light()
                }
            }
        }
    }

    private func pickRow(icon: String, tint: Color, title: String, subtitle: String, on: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 15, weight: .medium)).foregroundStyle(tint).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Text(subtitle).font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20)).foregroundStyle(on ? Theme.accentColor : Theme.textTertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(on ? tint.opacity(0.5) : Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity).padding(.vertical, 30)
    }
}

// MARK: - Schedule a project work session

/// Reserve time for a project on the calendar — pick a length and let Chronos
/// drop it into the next free gap today, or set the time yourself.
struct ProjectWorkScheduleSheet: View {
    let projectID: UUID

    @EnvironmentObject private var life: LifeStore
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var profileStore: ProfileStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Prefs.workStartMinutes) private var workStartMinutes = 9 * 60
    @AppStorage(Prefs.workEndMinutes) private var workEndMinutes = 18 * 60
    @AppStorage(Prefs.defaultCalendarID) private var defaultCalendarID = ""

    @State private var minutes = 45
    @State private var start = Date.nextCleanSlot()
    @State private var calendarID: String?
    @State private var didInit = false

    private let presets = [30, 45, 60, 90, 120]

    private var project: Project? { life.project(projectID) }

    var body: some View {
        EditorSheet(title: "Schedule Work", confirmLabel: "Add", onConfirm: schedule) {
            if let project {
                HStack(spacing: 10) {
                    Text(project.emoji).font(.system(size: 24))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.title.isEmpty ? "Project" : project.title)
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        if let target = project.targetHours, target > 0 {
                            Text("\(Fmt.duration(minutes: project.totalLoggedMinutes)) of \(Fmt.duration(minutes: Int(target * 60))) logged")
                                .font(.system(size: 12.5)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            FieldRow(label: "Length") {
                HStack(spacing: 10) {
                    Text(durationLabel(minutes)).font(.system(size: 14, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.textPrimary)
                    Stepper("", value: $minutes, in: 15...240, step: 15).labelsHidden()
                }
            }
            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { m in
                    Button { minutes = m } label: {
                        Text(Fmt.duration(minutes: m))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(minutes == m ? Theme.bg : Theme.textSecondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                            .background(minutes == m ? AnyShapeStyle(Theme.accentColor) : AnyShapeStyle(Theme.fill),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            FieldRow(label: "Starts") {
                DatePicker("", selection: $start, displayedComponents: [.date, .hourAndMinute]).labelsHidden()
            }
            Button { if let slot = nextFreeSlot() { start = slot } } label: {
                Label("Find next free slot today", systemImage: "sparkles")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accentColor)
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(Theme.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            CalendarPickerRow(label: "Calendar", options: service.calendars, selection: $calendarID)
        }
        .onAppear {
            guard !didInit else { return }
            didInit = true
            if calendarID == nil { calendarID = service.calendars.first(where: \.isEditable)?.id }
            if let slot = nextFreeSlot() { start = slot }
        }
    }

    private func durationLabel(_ m: Int) -> String {
        if m < 60 { return "\(m)m" }
        let h = m / 60, r = m % 60
        return r == 0 ? "\(h)h" : "\(h)h \(r)m"
    }

    /// First free gap today big enough for the session, respecting the plan
    /// window and existing blocks.
    private func nextFreeSlot() -> Date? {
        AutoScheduler.freeGaps(
            on: Date(), existing: service.blocks(on: Date()),
            workStartMinutes: workStartMinutes, workEndMinutes: workEndMinutes,
            profile: profileStore.profile
        )
        .first { $0.minutes >= minutes }?
        .start
    }

    private func schedule() {
        guard let project else { return }
        var draft = BlockDraft()
        draft.title = "\(project.emoji) \(project.title.isEmpty ? "Project" : project.title)"
        draft.calendarID = calendarID
        draft.start = start
        draft.end = start.adding(minutes: minutes)
        draft.colorHex = project.colorHex
        service.createBlock(draft)
        Haptics.success()
    }
}
