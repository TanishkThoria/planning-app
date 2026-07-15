import SwiftUI

/// The routines library: start a guided routine, or create/edit your own.
struct RoutinesView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = RoutineStore.shared
    @AppStorage(Prefs.routineVoiceEnabled) private var voiceEnabled = true

    @State private var running: Routine?
    @State private var editing: Routine?

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
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Metric.radius, style: .continuous))
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
    }

    private var intro: some View {
        HStack(spacing: 8) {
            Image(systemName: voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 12)).foregroundStyle(Color.accentColor)
            Text("Guided, hands-free. Each step counts down and is announced aloud — great for mornings and beating time-blindness.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    private func routineCard(_ routine: Routine) -> some View {
        HStack(spacing: 12) {
            Text(routine.emoji).font(.system(size: 26))
            VStack(alignment: .leading, spacing: 2) {
                Text(routine.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text("\(routine.steps.count) steps · \(routine.totalMinutes) min")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Button { editing = routine } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary).frame(width: 34, height: 34)
                    .background(Theme.fill, in: Circle())
            }
            .buttonStyle(.plain)
            Button { running = routine } label: {
                Label("Start", systemImage: "play.fill")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.bg)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Color.accentColor, in: Capsule())
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NAME").font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(Theme.textTertiary)
                        TextField("Routine name", text: $routine.name)
                            .textFieldStyle(.plain).font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
                            ForEach(emojis, id: \.self) { e in
                                Button { routine.emoji = e } label: {
                                    Text(e).font(.system(size: 22)).frame(width: 42, height: 42)
                                        .background(routine.emoji == e ? Color.accentColor.opacity(0.18) : Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(routine.emoji == e ? Color.accentColor : Theme.hairline, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("STEPS").font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(Theme.textTertiary)
                        ForEach($routine.steps) { $step in
                            HStack(spacing: 10) {
                                TextField("Step", text: $step.title)
                                    .textFieldStyle(.plain).font(.system(size: 14)).foregroundStyle(Theme.textPrimary)
                                Stepper(value: Binding(
                                    get: { max(1, step.seconds / 60) },
                                    set: { $step.wrappedValue.seconds = $0 * 60 }
                                ), in: 1...120) {
                                    Text("\(max(1, step.seconds / 60))m")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Theme.textSecondary).monospacedDigit()
                                }
                                .labelsHidden()
                                Button { routine.steps.removeAll { $0.id == step.id } } label: {
                                    Image(systemName: "minus.circle.fill").font(.system(size: 15)).foregroundStyle(Theme.textTertiary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
                        }
                        Button { routine.steps.append(RoutineStep(title: "New step", seconds: 300)) } label: {
                            Label("Add step", systemImage: "plus").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }

                    Button(role: .destructive) { onDelete(routine); dismiss() } label: {
                        Text("Delete routine").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.danger)
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
