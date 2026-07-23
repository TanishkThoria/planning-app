import SwiftUI

/// The routines library: start a guided routine, or create/edit your own.
struct RoutinesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = RoutineStore.shared
    @AppStorage(Prefs.routineVoiceEnabled) private var voiceEnabled = true

    @State private var running: Routine?
    @State private var editing: Routine?
    @State private var scheduling: Routine?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    intro
                    ForEach(store.routines) { routine in
                        routineCard(routine)
                    }
                    Button { editing = Routine(name: "New routine", emoji: "✨", steps: [RoutineStep(title: "First step", seconds: 300)]) } label: {
                        Label("New routine", systemImage: "plus")
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(Theme.accentColor)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(Theme.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Metric.radius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(18)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg)
            .navigationTitle("Routines")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .chronosAppearance()
        .sheet(item: $running) { RoutineRunnerView(routine: $0) }
        .sheet(item: $editing) { routine in
            RoutineEditorSheet(routine: routine) { store.upsert($0) } onDelete: { store.delete($0) }
        }
        .sheet(item: $scheduling) { RoutineScheduleSheet(routine: $0) }
    }

    private var intro: some View {
        HStack(spacing: 8) {
            Image(systemName: voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 13.5)).foregroundStyle(Theme.accentColor)
            Text("Build a routine to follow step by step — timed steps count down and are announced aloud, or add check-off steps for things like “no phone”. Great for mornings and beating time-blindness.")
                .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    private func cardSubtitle(_ routine: Routine) -> String {
        let steps = "\(routine.steps.count) step\(routine.steps.count == 1 ? "" : "s")"
        return routine.totalSeconds > 0 ? "\(steps) · \(routine.totalMinutes) min" : steps
    }

    private func routineCard(_ routine: Routine) -> some View {
        HStack(spacing: 12) {
            Text(routine.emoji).font(.system(size: 26))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(routine.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if routine.tracked {
                        let streak = store.streak(routine)
                        Label(streak > 0 ? "\(streak)" : "Tracked", systemImage: streak > 0 ? "flame.fill" : "repeat")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(streak > 0 ? Theme.warning : Theme.accentColor)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background((streak > 0 ? Theme.warning : Theme.accentColor).opacity(0.14), in: Capsule())
                    }
                }
                Text(cardSubtitle(routine))
                    .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Menu {
                Button { editing = routine } label: { Label("Edit routine", systemImage: "slider.horizontal.3") }
                Button { scheduling = routine } label: { Label("Add to Calendar", systemImage: "calendar.badge.plus") }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary).frame(width: 34, height: 34)
                    .background(Theme.fill, in: Circle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Button { running = routine } label: {
                Label("Start", systemImage: "play.fill")
                    .font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Theme.bg)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Theme.accentColor, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Metric.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Metric.radius, style: .continuous)
            .strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

// MARK: - Editor

private struct RoutineEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var routine: Routine
    let onSave: (Routine) -> Void
    let onDelete: (Routine) -> Void

    init(routine: Routine, onSave: @escaping (Routine) -> Void, onDelete: @escaping (Routine) -> Void) {
        _routine = State(initialValue: routine)
        self.onSave = onSave
        self.onDelete = onDelete
    }

    private let emojis = ["✨", "☀️", "🌙", "📚", "🏃", "🧘", "🧹", "💻", "☕️", "🛏️"]
    static let durationPresets = [1, 2, 3, 5, 10, 15, 20, 25, 30, 45, 60, 90]

    private func move(_ step: RoutineStep, by offset: Int) {
        guard let i = routine.steps.firstIndex(where: { $0.id == step.id }) else { return }
        let j = i + offset
        guard routine.steps.indices.contains(j) else { return }
        routine.steps.swapAt(i, j)
        Haptics.selection()
    }

    /// Turn a routine into one you're establishing: tracked like a habit, with
    /// a streak, a cadence, and an optional reminder.
    private var trackSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("BUILD THE HABIT").font(.system(size: 11.5, weight: .semibold)).tracking(1.2).foregroundStyle(Theme.textTertiary)
            fieldRow {
                Toggle(isOn: $routine.tracked) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Track this routine").font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.textPrimary)
                        Text("Log it each day and build a streak").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                    }
                }
                .toggleStyle(.switch)
            }
            if routine.tracked {
                fieldRow {
                    Text("Cadence").font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Picker("", selection: $routine.cadence) {
                        ForEach(HabitCadence.allCases) { c in Text(c.label).tag(c) }
                    }
                    .labelsHidden().fixedSize()
                }
                fieldRow {
                    Text("Reminder").font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { routine.reminderMinutes != nil },
                        set: { routine.reminderMinutes = $0 ? (routine.reminderMinutes ?? 7 * 60) : nil }
                    )).labelsHidden().toggleStyle(.switch)
                }
                if routine.reminderMinutes != nil {
                    fieldRow {
                        Text("At").font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                        Spacer()
                        DatePicker("", selection: Binding(
                            get: { Date().startOfDay.at(minutes: routine.reminderMinutes ?? 7 * 60) },
                            set: { routine.reminderMinutes = $0.minutesSinceMidnight }
                        ), displayedComponents: [.hourAndMinute]).labelsHidden()
                    }
                }
            }
        }
    }

    private func fieldRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack { content() }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NAME").font(.system(size: 11.5, weight: .semibold)).tracking(1.2).foregroundStyle(Theme.textTertiary)
                        TextField("Routine name", text: $routine.name)
                            .textFieldStyle(.plain).font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
                            ForEach(emojis, id: \.self) { e in
                                Button { routine.emoji = e } label: {
                                    Text(e).font(.system(size: 22)).frame(width: 42, height: 42)
                                        .background(routine.emoji == e ? Theme.accentColor.opacity(0.18) : Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(routine.emoji == e ? Theme.accentColor : Theme.hairline, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("STEPS").font(.system(size: 11.5, weight: .semibold)).tracking(1.2).foregroundStyle(Theme.textTertiary)
                            Spacer()
                            Text("Timed or check-off").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                        }
                        ForEach($routine.steps) { $step in
                            HStack(spacing: 10) {
                                TextField("Step", text: $step.title)
                                    .textFieldStyle(.plain).font(.system(size: 15)).foregroundStyle(Theme.textPrimary)
                                if step.untimed {
                                    Text("Check-off")
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(Theme.accentColor)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Theme.accentColor.opacity(0.14), in: Capsule())
                                } else {
                                    Menu {
                                        ForEach(Self.durationPresets, id: \.self) { m in
                                            Button {
                                                $step.wrappedValue.seconds = m * 60
                                            } label: {
                                                Label(Fmt.duration(minutes: m),
                                                      systemImage: max(1, step.seconds / 60) == m ? "checkmark" : "")
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 3) {
                                            Text("\(max(1, step.seconds / 60)) min")
                                                .font(.system(size: 13.5, weight: .semibold))
                                                .foregroundStyle(Theme.accentColor).monospacedDigit()
                                            Image(systemName: "chevron.up.chevron.down")
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundStyle(Theme.textTertiary)
                                        }
                                        .padding(.horizontal, 9).padding(.vertical, 5)
                                        .background(Theme.accentColor.opacity(0.12), in: Capsule())
                                    }
                                    .menuIndicator(.hidden)
                                }
                                Menu {
                                    Button {
                                        $step.wrappedValue.untimed.toggle()
                                        if !$step.wrappedValue.untimed, $step.wrappedValue.seconds < 60 { $step.wrappedValue.seconds = 300 }
                                    } label: {
                                        Label(step.untimed ? "Make it timed" : "Make it check-off",
                                              systemImage: step.untimed ? "timer" : "checkmark.circle")
                                    }
                                    Button { move(step, by: -1) } label: { Label("Move up", systemImage: "arrow.up") }
                                    Button { move(step, by: 1) } label: { Label("Move down", systemImage: "arrow.down") }
                                    Divider()
                                    Button(role: .destructive) { routine.steps.removeAll { $0.id == step.id } } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle").font(.system(size: 16)).foregroundStyle(Theme.textTertiary)
                                }
                                .menuIndicator(.hidden)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                        }
                        HStack(spacing: 10) {
                            Button { routine.steps.append(RoutineStep(title: "New step", seconds: 300)) } label: {
                                Label("Timed step", systemImage: "plus").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accentColor)
                            }
                            .buttonStyle(.plain)
                            Button { routine.steps.append(RoutineStep(title: "New step", seconds: 60, untimed: true)) } label: {
                                Label("Check-off step", systemImage: "checkmark.circle").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    trackSection

                    Button(role: .destructive) { onDelete(routine); dismiss() } label: {
                        Text("Delete routine").font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Theme.danger)
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
                .frame(maxWidth: 480)
            }
            .background(Theme.bg)
            .navigationTitle("Edit routine")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        routine.steps = routine.steps.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
                        if !routine.steps.isEmpty { onSave(routine) }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .chronosAppearance()
    }
}

// MARK: - Schedule on calendar

/// Lay a routine onto the calendar as real time blocks — pick a day and start
/// time, and whether each step becomes its own consecutive block.
private struct RoutineScheduleSheet: View {
    let routine: Routine
    @EnvironmentObject private var service: EventKitService
    @Environment(\.dismiss) private var dismiss

    @State private var start = Date.nextCleanSlot()
    @State private var perStep = false
    @State private var calendarID: String?

    var body: some View {
        EditorSheet(title: "Add to Calendar", confirmLabel: "Add", onConfirm: schedule) {
            HStack(spacing: 10) {
                Text(routine.emoji).font(.system(size: 24))
                VStack(alignment: .leading, spacing: 2) {
                    Text(routine.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text("\(routine.steps.count) step\(routine.steps.count == 1 ? "" : "s") · \(routine.plannedMinutes) min")
                        .font(.system(size: 12.5)).foregroundStyle(Theme.textTertiary)
                }
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            FieldRow(label: "Starts") {
                DatePicker("", selection: $start, displayedComponents: [.date, .hourAndMinute]).labelsHidden()
            }

            CalendarPickerRow(label: "Calendar", options: service.calendars, selection: $calendarID)

            FieldRow(label: "Each step as its own block") {
                Toggle("", isOn: $perStep).labelsHidden().toggleStyle(.switch)
            }

            Text(summary)
                .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
        }
        .onAppear {
            if calendarID == nil { calendarID = service.calendars.first(where: \.isEditable)?.id }
        }
    }

    private var summary: String {
        let end = start.adding(minutes: max(5, routine.plannedMinutes))
        let range = "\(Fmt.time.string(from: start))–\(Fmt.time.string(from: end))"
        if perStep {
            return "Creates \(routine.steps.count) back-to-back blocks starting \(Fmt.time.string(from: start))."
        }
        return "Creates one \(routine.plannedMinutes)-minute block, \(range), with the steps in its notes."
    }

    private func schedule() {
        service.scheduleRoutine(routine, startingAt: start, calendarID: calendarID, perStep: perStep)
        Haptics.success()
    }
}
