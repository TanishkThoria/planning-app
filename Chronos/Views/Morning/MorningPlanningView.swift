import SwiftUI

/// Morning planning ritual: a guided start-of-day flow. Brain-dump what you
/// want to get done, tag rough effort, then let Chronos lay the whole day
/// out around your routines and focus window. A lighter, task-first cousin
/// of the calibration wizard.
struct MorningPlanningView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var profileStore: ProfileStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage(Prefs.defaultBlockMinutes) private var defaultBlockMinutes = 30
    @AppStorage(Prefs.snapMinutes) private var snapMinutes = 15
    @AppStorage(Prefs.workStartMinutes) private var workStartMinutes = 9 * 60
    @AppStorage(Prefs.workEndMinutes) private var workEndMinutes = 18 * 60
    @AppStorage(Prefs.planDayGapMinutes) private var gapMinutes = 5
    @AppStorage(Prefs.defaultCalendarID) private var defaultCalendarID = ""
    @AppStorage(Prefs.defaultListID) private var defaultListID = ""

    private enum Step { case dump, plan }
    @State private var step: Step = .dump

    @State private var entry = ""
    @State private var entryEnergy: TaskEnergy = .none
    /// Selection model: dated tasks are included by default (opt-out via
    /// `manualExclude`); undated tasks are opt-in (`manualInclude`). This
    /// way a task you add mid-flow — which is created due today — is picked
    /// up automatically once it syncs in, no fragile id lookup needed.
    @State private var manualInclude: Set<String> = []
    @State private var manualExclude: Set<String> = []
    @FocusState private var entryFocused: Bool

    private func isIncluded(_ task: TaskItem) -> Bool {
        if task.dueDate != nil { return !manualExclude.contains(task.id) }
        return manualInclude.contains(task.id)
    }

    private func toggle(_ task: TaskItem) {
        if task.dueDate != nil {
            if manualExclude.contains(task.id) { manualExclude.remove(task.id) }
            else { manualExclude.insert(task.id) }
        } else {
            if manualInclude.contains(task.id) { manualInclude.remove(task.id) }
            else { manualInclude.insert(task.id) }
        }
    }

    private var includedCount: Int { candidates.filter(isIncluded).count }

    private var day: Date { Date().startOfDay }

    /// Today's open, unscheduled tasks (due today/overdue/undated) that
    /// could go on the calendar.
    private var candidates: [TaskItem] {
        let scheduled = Set(service.blocks(on: day).compactMap(\.linkedTaskID))
        return service.tasks
            .filter { task in
                guard !task.isCompleted, !scheduled.contains(task.id),
                      !model.hiddenListIDs.contains(task.listID) else { return false }
                guard service.subtasks(of: task.id).allSatisfy(\.isCompleted) else { return false }
                guard let due = task.dueDate else { return true }
                return due.startOfDay <= day
            }
            .sorted { a, b in
                if a.priority.sortRank != b.priority.sortRank { return a.priority.sortRank < b.priority.sortRank }
                return (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture)
            }
    }

    private var proposals: [AutoScheduler.Proposal] {
        AutoScheduler.plan(
            tasks: candidates.filter(isIncluded),
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

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Rectangle().fill(Theme.hairline).frame(height: 1)

            if step == .dump { dumpStep } else { planStep }

            Rectangle().fill(Theme.hairline).frame(height: 1)
            footer
        }
        .background(Theme.elevated)
        .chronosAppearance()
        #if os(macOS)
        .frame(width: 500, height: 620)
        #else
        .presentationDetents([.large])
        #endif
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private var headerBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .keyboardShortcut(.cancelAction)
            Spacer()
            VStack(spacing: 1) {
                Text("Plan Today")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(step == .dump ? "What's on your plate?" : "Here's your day")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Text("Cancel").font(.system(size: 13)).hidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: Dump step

    private var dumpStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(greeting).")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Add everything you'd like to move forward today. Tag rough effort so deep work lands in your \(profileStore.profile.focus.rawValue.lowercased()) focus window.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineSpacing(2)
                }

                // Quick add
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textTertiary)
                        TextField("Add a task for today", text: $entry)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13.5))
                            .focused($entryFocused)
                            .onSubmit(addEntry)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Picker("", selection: $entryEnergy) {
                        ForEach(TaskEnergy.allCases) { energy in
                            Text(energy.label).tag(energy)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                SectionHeader(title: "Today's candidates", trailing: "\(candidates.count)")

                if candidates.isEmpty {
                    Text("Nothing yet — add a few tasks above.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    ForEach(candidates) { task in
                        candidateRow(task)
                    }
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .onAppear { entryFocused = true }
    }

    private func candidateRow(_ task: TaskItem) -> some View {
        let isIn = isIncluded(task)
        return Button {
            toggle(task)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isIn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15))
                    .foregroundStyle(isIn ? Color.accentColor : Theme.textTertiary)
                if task.energy != .none {
                    Image(systemName: task.energy.icon)
                        .font(.system(size: 10))
                        .foregroundStyle(task.energy.color)
                }
                Text(task.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text("~\(Fmt.duration(minutes: task.estimateMinutes ?? defaultBlockMinutes))")
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func addEntry() {
        let title = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        var draft = TaskDraft()
        draft.title = title
        draft.listID = defaultListID.isEmpty ? nil : defaultListID
        draft.hasDue = true
        draft.due = Date().endOfDay
        draft.energy = entryEnergy
        service.createTask(draft)
        entry = ""
        // Created due today, so it's auto-included by the dated-default rule
        // as soon as it syncs in — no id bookkeeping required.
    }

    // MARK: Plan step

    private var planStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if proposals.isEmpty {
                    EmptyStateView(
                        icon: "calendar.badge.exclamationmark",
                        title: "No room to plan",
                        message: "There aren't enough free gaps today for the tasks you picked. Try selecting fewer, or shorten their estimates."
                    )
                } else {
                    SectionHeader(title: "Proposed blocks", trailing: "\(proposals.count)")
                    ForEach(proposals) { proposal in
                        HStack(spacing: 10) {
                            Text(Fmt.time.string(from: proposal.start))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.accentColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .frame(width: 62, alignment: .leading)
                            if proposal.task.energy != .none {
                                Image(systemName: proposal.task.energy.icon)
                                    .font(.system(size: 10))
                                    .foregroundStyle(proposal.task.energy.color)
                            }
                            Text(proposal.task.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(Fmt.duration(minutes: proposal.minutes))
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if step == .plan {
                Button {
                    step = .dump
                } label: {
                    Text("Back")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button {
                if step == .dump {
                    step = .plan
                } else {
                    apply()
                }
            } label: {
                Text(step == .dump ? "Build My Day" : "Add \(proposals.count) to Calendar")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Theme.bg)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(Color.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(step == .dump ? includedCount == 0 : proposals.isEmpty)
            .opacity((step == .dump ? includedCount == 0 : proposals.isEmpty) ? 0.4 : 1)
            .keyboardShortcut(.defaultAction)
        }
        .padding(14)
    }

    private func apply() {
        let confirmed = proposals
        for proposal in confirmed {
            service.scheduleTask(
                proposal.task,
                at: proposal.start,
                minutes: proposal.minutes,
                calendarID: defaultCalendarID.isEmpty ? nil : defaultCalendarID
            )
        }
        model.openDay(day)
        dismiss()
    }
}
