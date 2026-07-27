import SwiftUI

/// One-tap daily planning: pick the tasks that matter, Chronos fits them
/// into the free gaps of your working hours, you confirm, and real calendar
/// events (linked back to their reminders) are created.
struct PlanMyDayView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var life: LifeStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Prefs.workStartMinutes) private var workStartMinutes = 9 * 60
    @AppStorage(Prefs.workEndMinutes) private var workEndMinutes = 18 * 60
    @AppStorage(Prefs.snapMinutes) private var snapMinutes = 15
    @AppStorage(Prefs.defaultBlockMinutes) private var defaultBlockMinutes = 30
    @AppStorage(Prefs.planDayGapMinutes) private var gapMinutes = 5
    @AppStorage(Prefs.defaultCalendarID) private var defaultCalendarID = ""

    @State private var included: Set<String> = []
    @State private var includedRituals: Set<String> = []
    @State private var includedProjects: Set<UUID> = []
    @State private var initialized = false

    /// A suggested block of work toward a project's hours target.
    private struct ProjectSession: Identifiable {
        let project: Project
        let minutes: Int
        var id: UUID { project.id }
    }

    private var day: Date { model.selectedDate }

    /// Calibrated meal/routine windows flagged "put on calendar" that don't
    /// already have a matching or overlapping block on this day.
    private var ritualCandidates: [PlannerProfile.DayWindow] {
        let existing = service.blocks(on: day).filter { !$0.isAllDay }
        return profileStore.profile.routineWindows(on: day)
            .filter(\.autoBlock)
            .filter { window in
                window.end > Date() || !day.isToday
            }
            .filter { window in
                !existing.contains { block in
                    block.title == window.title || (block.start < window.end && window.start < block.end)
                }
            }
    }

    /// Candidates: open tasks with no block on this day already —
    /// overdue and due-today first, undated ones after. Parents with open
    /// subtasks step aside; their subtasks are the schedulable units.
    private var candidates: [TaskItem] {
        let scheduled = Set(service.blocks(on: day).compactMap(\.linkedTaskID))
        return service.tasks
            .filter { task in
                guard !task.isCompleted, !scheduled.contains(task.id),
                      !model.hiddenListIDs.contains(task.listID) else { return false }
                guard service.subtasks(of: task.id).allSatisfy(\.isCompleted) else { return false }
                guard let due = task.dueDate else { return true }
                return due.startOfDay <= day.startOfDay
            }
            .sorted { a, b in
                let aDated = a.dueDate != nil, bDated = b.dueDate != nil
                if aDated != bDated { return aDated }
                if a.priority.sortRank != b.priority.sortRank { return a.priority.sortRank < b.priority.sortRank }
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
    }

    private var proposals: [AutoScheduler.Proposal] {
        AutoScheduler.plan(
            tasks: candidates.filter { included.contains($0.id) },
            existing: service.blocks(on: day),
            on: day,
            workStartMinutes: workStartMinutes,
            workEndMinutes: workEndMinutes,
            snapMinutes: snapMinutes,
            defaultMinutes: defaultBlockMinutes,
            gapPaddingMinutes: gapMinutes,
            profile: profileStore.profile
        )
    }

    /// Effort-based projects (an hours target, not yet met) you can spend time
    /// toward today. Off by default — opt in per project.
    private var projectSessionCandidates: [ProjectSession] {
        life.activeProjects.compactMap { p in
            guard !p.isComplete, let target = p.targetHours, target > 0 else { return nil }
            let remaining = Int((target - p.totalLoggedHours) * 60)
            guard remaining >= 15 else { return nil }
            return ProjectSession(project: p, minutes: min(max(30, min(90, remaining)), remaining))
        }
    }

    /// Places the opted-in project sessions into the day's free gaps, after the
    /// task proposals and confirmed routine windows have claimed their time.
    private var projectPlacements: [(session: ProjectSession, start: Date)] {
        let chosen = projectSessionCandidates.filter { includedProjects.contains($0.id) }
        guard !chosen.isEmpty else { return [] }
        var reserved: [(start: Date, end: Date)] = proposals.map { ($0.start, $0.end) }
        reserved += ritualCandidates
            .filter { includedRituals.contains($0.id) }
            .map { ($0.start, $0.end) }

        var slots = AutoScheduler.freeGaps(
            on: day, existing: service.blocks(on: day),
            workStartMinutes: workStartMinutes, workEndMinutes: workEndMinutes,
            profile: profileStore.profile
        )
        // Carve the task/ritual reservations out of the free slots.
        for (rs, re) in reserved.sorted(by: { $0.start < $1.start }) {
            var next: [AutoScheduler.Gap] = []
            for g in slots {
                if re <= g.start || rs >= g.end { next.append(g); continue }
                if rs > g.start { next.append(AutoScheduler.Gap(start: g.start, end: rs)) }
                if re < g.end { next.append(AutoScheduler.Gap(start: re, end: g.end)) }
            }
            slots = next
        }
        slots = slots.filter { $0.minutes >= 15 }.sorted { $0.start < $1.start }

        var placements: [(ProjectSession, Date)] = []
        for session in chosen {
            guard let idx = slots.firstIndex(where: { $0.minutes >= session.minutes }) else { continue }
            let g = slots[idx]
            placements.append((session, g.start))
            slots[idx] = AutoScheduler.Gap(start: g.start.adding(minutes: session.minutes + gapMinutes), end: g.end)
        }
        return placements
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Rectangle().fill(Theme.hairline).frame(height: 1)

            if candidates.isEmpty && ritualCandidates.isEmpty && projectSessionCandidates.isEmpty {
                EmptyStateView(
                    icon: "checkmark.seal",
                    title: "Nothing to plan",
                    message: "Every open task for \(Fmt.relativeDay(day).lowercased()) is already on the timeline."
                )
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        if !ritualCandidates.isEmpty {
                            SectionHeader(title: "Routine")
                                .padding(.horizontal, 4)
                            ForEach(ritualCandidates) { window in
                                ritualRow(window)
                            }
                        }
                        if !candidates.isEmpty {
                            SectionHeader(title: "Tasks")
                                .padding(.horizontal, 4)
                                .padding(.top, ritualCandidates.isEmpty ? 0 : 10)
                            ForEach(candidates) { task in
                                candidateRow(task)
                            }
                        }
                        if !projectSessionCandidates.isEmpty {
                            SectionHeader(title: "Projects")
                                .padding(.horizontal, 4)
                                .padding(.top, candidates.isEmpty && ritualCandidates.isEmpty ? 0 : 10)
                            ForEach(projectSessionCandidates) { session in
                                projectSessionRow(session)
                            }
                        }
                    }
                    .padding(16)
                }
                .scrollIndicators(.hidden)
            }

            Rectangle().fill(Theme.hairline).frame(height: 1)
            footer
        }
        .background(Theme.elevated)
        .chronosAppearance()
        #if os(macOS)
        .frame(width: 480, height: 560)
        #else
        .presentationDetents([.large])
        #endif
        .onAppear {
            guard !initialized else { return }
            initialized = true
            // Dated (due/overdue) tasks are in by default; undated ones opt-in.
            included = Set(candidates.filter { $0.dueDate != nil }.map(\.id))
            includedRituals = Set(ritualCandidates.map(\.id))
        }
    }

    private var headerBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 14.5))
                .foregroundStyle(Theme.textSecondary)
                .keyboardShortcut(.cancelAction)
            Spacer()
            VStack(spacing: 1) {
                Text("Plan My Day")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(Fmt.relativeDay(day))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            // Symmetry spacer so the title stays centered.
            Text("Cancel").font(.system(size: 14.5)).hidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func ritualRow(_ window: PlannerProfile.DayWindow) -> some View {
        let isIncluded = includedRituals.contains(window.id)
        return Button {
            if isIncluded { includedRituals.remove(window.id) } else { includedRituals.insert(window.id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isIncluded ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundStyle(isIncluded ? Theme.accentColor : Theme.textTertiary)
                Image(systemName: "repeat")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textTertiary)
                Text(window.title)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(Fmt.timeRange(window.start, window.end))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isIncluded ? Theme.accentColor : Theme.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func projectSessionRow(_ session: ProjectSession) -> some View {
        let isIncluded = includedProjects.contains(session.id)
        let placement = projectPlacements.first { $0.session.id == session.id }
        let target = Int((session.project.targetHours ?? 0) * 60)
        return Button {
            if isIncluded { includedProjects.remove(session.id) } else { includedProjects.insert(session.id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isIncluded ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundStyle(isIncluded ? Theme.accentColor : Theme.textTertiary)
                Text(session.project.emoji).font(.system(size: 14))
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.project.title.isEmpty ? "Untitled project" : session.project.title)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Text("\(Fmt.duration(minutes: session.minutes)) session · \(Fmt.duration(minutes: session.project.totalLoggedMinutes)) of \(Fmt.duration(minutes: target)) logged")
                        .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                if isIncluded {
                    if let placement {
                        Text(Fmt.timeRange(placement.start, placement.start.adding(minutes: session.minutes)))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.accentColor)
                    } else {
                        Text("no room")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Theme.warning)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func candidateRow(_ task: TaskItem) -> some View {
        let proposal = proposals.first { $0.task.id == task.id }
        let isIncluded = included.contains(task.id)

        return Button {
            if isIncluded { included.remove(task.id) } else { included.insert(task.id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isIncluded ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16))
                    .foregroundStyle(isIncluded ? Theme.accentColor : Theme.textTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text("~\(Fmt.duration(minutes: task.estimateMinutes ?? defaultBlockMinutes))")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                        if task.isOverdue {
                            Text("overdue")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.danger)
                        }
                        if task.priority != .none {
                            Text(task.priority.badge)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(task.priority.color)
                        }
                    }
                }

                Spacer()

                if isIncluded {
                    if let proposal {
                        Text(Fmt.timeRange(proposal.start, proposal.end))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.accentColor)
                    } else {
                        Text("no room")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Theme.warning)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        let ritualCount = ritualCandidates.filter { includedRituals.contains($0.id) }.count
        let projectCount = projectPlacements.count
        let totalBlocks = proposals.count + ritualCount + projectCount
        return HStack {
            let unplaced = (included.count - proposals.count) + (includedProjects.count - projectCount)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(totalBlocks) block\(totalBlocks == 1 ? "" : "s") will be created")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                if unplaced > 0 {
                    Text("\(unplaced) didn't fit — free up time or shorten estimates")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.warning)
                }
            }
            Spacer()
            Button {
                apply()
            } label: {
                Text("Add to Calendar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Theme.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(totalBlocks == 0)
            .opacity(totalBlocks == 0 ? 0.4 : 1)
            .keyboardShortcut(.defaultAction)
        }
        .padding(14)
    }

    private func apply() {
        PlanningMeter.shared.recordPlanRun()
        // Snapshot both lists first: creating ritual blocks refreshes the
        // service, and re-computing `proposals` afterwards could shift or
        // drop task slots the user just confirmed.
        let confirmedRituals = ritualCandidates.filter { includedRituals.contains($0.id) }
        let confirmedProposals = proposals
        let confirmedProjects = projectPlacements

        for placement in confirmedProjects {
            var draft = BlockDraft()
            let project = placement.session.project
            draft.title = "\(project.emoji) \(project.title.isEmpty ? "Project" : project.title)"
            draft.calendarID = defaultCalendarID.isEmpty ? nil : defaultCalendarID
            draft.start = placement.start
            draft.end = placement.start.adding(minutes: placement.session.minutes)
            draft.colorHex = project.colorHex
            service.createBlock(draft)
        }

        for window in confirmedRituals {
            var draft = BlockDraft()
            draft.title = window.title
            draft.calendarID = defaultCalendarID.isEmpty ? nil : defaultCalendarID
            draft.start = window.start
            draft.end = window.end
            service.createBlock(draft)
        }
        for proposal in confirmedProposals {
            service.scheduleTask(
                proposal.task,
                at: proposal.start,
                minutes: proposal.minutes,
                calendarID: defaultCalendarID.isEmpty ? nil : defaultCalendarID
            )
        }
        dismiss()
    }
}
