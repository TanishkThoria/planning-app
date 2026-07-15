import SwiftUI

/// Week-level auto-plan: spreads your open tasks (and chunked-project
/// sessions) across the visible week's days, filling each day around
/// existing blocks and protected routines, then creates them all on confirm.
struct PlanWeekView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var profileStore: ProfileStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Prefs.workStartMinutes) private var workStartMinutes = 9 * 60
    @AppStorage(Prefs.workEndMinutes) private var workEndMinutes = 18 * 60
    @AppStorage(Prefs.snapMinutes) private var snapMinutes = 15
    @AppStorage(Prefs.defaultBlockMinutes) private var defaultBlockMinutes = 30
    @AppStorage(Prefs.planDayGapMinutes) private var gapMinutes = 5
    @AppStorage(Prefs.defaultCalendarID) private var defaultCalendarID = ""

    @State private var included: Set<String> = []
    @State private var initialized = false

    private var weekDays: [Date] {
        let start = model.selectedDate.startOfWeek
        // Plan from today forward within the visible week.
        return (0..<7).map { start.adding(days: $0) }.filter { $0.startOfDay >= Date().startOfDay }
    }

    private var candidates: [TaskItem] {
        let scheduled = Set(service.blocks.compactMap(\.linkedTaskID))
        return service.tasks
            .filter { task in
                guard !task.isCompleted, !scheduled.contains(task.id),
                      !model.hiddenListIDs.contains(task.listID) else { return false }
                guard service.subtasks(of: task.id).allSatisfy(\.isCompleted) else { return false }
                return true
            }
            .sorted { a, b in
                if a.priority.sortRank != b.priority.sortRank { return a.priority.sortRank < b.priority.sortRank }
                return (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture)
            }
    }

    private var planByDay: [Date: [AutoScheduler.Proposal]] {
        AutoScheduler.planWeek(
            tasks: candidates.filter { included.contains($0.id) },
            existing: service.blocks,
            days: weekDays,
            workStartMinutes: workStartMinutes,
            workEndMinutes: workEndMinutes,
            snapMinutes: snapMinutes,
            defaultMinutes: defaultBlockMinutes,
            gapPaddingMinutes: gapMinutes,
            profile: profileStore.profile
        )
    }

    private var totalPlanned: Int { planByDay.values.reduce(0) { $0 + $1.count } }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Rectangle().fill(Theme.hairline).frame(height: 1)

            if candidates.isEmpty {
                EmptyStateView(
                    icon: "checkmark.seal",
                    title: "Nothing to plan",
                    message: "Every open task is already scheduled or complete."
                )
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionHeader(title: "Include", trailing: "\(included.count)")
                            ForEach(candidates) { task in
                                taskToggle(task)
                            }
                        }

                        if totalPlanned > 0 {
                            SectionHeader(title: "Proposed week")
                            ForEach(planByDay.keys.sorted(), id: \.self) { day in
                                dayGroup(day, proposals: planByDay[day] ?? [])
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
        .frame(width: 500, height: 640)
        #else
        .presentationDetents([.large])
        #endif
        .onAppear {
            guard !initialized else { return }
            initialized = true
            included = Set(candidates.filter { $0.dueDate != nil }.map(\.id))
        }
    }

    private var headerBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                .keyboardShortcut(.cancelAction)
            Spacer()
            Text("Plan My Week")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("Cancel").font(.system(size: 13)).hidden()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func taskToggle(_ task: TaskItem) -> some View {
        let isIn = included.contains(task.id)
        return Button {
            if isIn { included.remove(task.id) } else { included.insert(task.id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isIn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundStyle(isIn ? Color.accentColor : Theme.textTertiary)
                if task.energy != .none {
                    Image(systemName: task.energy.icon).font(.system(size: 10)).foregroundStyle(task.energy.color)
                }
                Text(task.title)
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer()
                if task.effectiveSessionMinutes != nil {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
                }
                Text("~\(Fmt.duration(minutes: task.estimateMinutes ?? defaultBlockMinutes))")
                    .font(.system(size: 10.5, design: .rounded)).foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dayGroup(_ day: Date, proposals: [AutoScheduler.Proposal]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(Fmt.relativeDay(day))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(day.isToday ? Color.accentColor : Theme.textPrimary)
                .padding(.leading, 2)
            ForEach(proposals) { proposal in
                HStack(spacing: 10) {
                    Text(Fmt.time.string(from: proposal.start))
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 60, alignment: .leading)
                    Text(proposal.task.title)
                        .font(.system(size: 12.5)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                    Spacer()
                    Text(Fmt.duration(minutes: proposal.minutes))
                        .font(.system(size: 10.5, design: .rounded)).foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("\(totalPlanned) block\(totalPlanned == 1 ? "" : "s") across \(planByDay.keys.count) day\(planByDay.keys.count == 1 ? "" : "s")")
                .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Button {
                apply()
            } label: {
                Text("Add to Calendar")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.bg)
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .background(Color.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(totalPlanned == 0)
            .opacity(totalPlanned == 0 ? 0.4 : 1)
            .keyboardShortcut(.defaultAction)
        }
        .padding(14)
    }

    private func apply() {
        let snapshot = planByDay
        for (_, proposals) in snapshot {
            for proposal in proposals {
                service.scheduleTask(
                    proposal.task,
                    at: proposal.start,
                    minutes: proposal.minutes,
                    calendarID: defaultCalendarID.isEmpty ? nil : defaultCalendarID
                )
            }
        }
        dismiss()
    }
}
