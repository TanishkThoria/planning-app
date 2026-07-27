import SwiftUI

/// Create or edit an identity pillar: its name, look, which activity categories
/// count as evidence, and which habits / goals / projects are aimed at it.
struct IdentityPillarEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var life: LifeStore

    let context: PillarEditContext
    @State private var draft: IdentityPillar

    init(context: PillarEditContext) {
        self.context = context
        _draft = State(initialValue: context.pillar)
    }

    private let icons = [
        "heart.fill", "briefcase.fill", "book.fill", "person.2.fill", "paintbrush.fill",
        "flame.fill", "dollarsign.circle.fill", "tshirt.fill", "bolt.fill", "leaf.fill",
        "figure.run", "brain.head.profile", "star.fill", "mountain.2.fill", "graduationcap.fill",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Pillar") {
                    TextField("Name (\"Health\")", text: $draft.name)
                    TextField("What it means to you", text: $draft.detail, axis: .vertical)
                        .lineLimit(1...3)
                }

                Section("Look") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(icons, id: \.self) { icon in
                            Button { draft.iconName = icon } label: {
                                Image(systemName: icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(draft.iconName == icon ? Color.white : Theme.textSecondary)
                                    .frame(width: 40, height: 40)
                                    .background(draft.iconName == icon ? draft.color : Theme.fill,
                                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack(spacing: 10) {
                        ForEach(Palette.options, id: \.self) { hex in
                            Button { draft.colorHex = hex } label: {
                                Circle().fill(Palette.color(hex)).frame(width: 28, height: 28)
                                    .overlay(Circle().strokeBorder(Theme.textPrimary,
                                        lineWidth: draft.colorHex == hex ? 2.5 : 0))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(ActivityCategory.allCases) { cat in
                            let on = draft.categoryList.contains(cat)
                            Button {
                                var cats = draft.categoryList
                                if on { cats.removeAll { $0 == cat } } else { cats.append(cat) }
                                draft.categories = cats.isEmpty ? nil : cats
                            } label: {
                                Label(cat.title, systemImage: cat.icon)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(on ? Color.white : Theme.textSecondary)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(on ? cat.color : Theme.fill, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Counts as evidence")
                } footer: {
                    Text("Focus sessions and finished tasks in these categories automatically become evidence for this pillar.")
                }

                if !life.activeHabits.isEmpty {
                    Section("Linked habits") {
                        ForEach(life.activeHabits) { habit in
                            linkRow(title: habit.title, icon: habit.iconName, on: (draft.linkedHabitIDs ?? []).contains(habit.id)) {
                                toggle(&draft.linkedHabitIDs, habit.id)
                            }
                        }
                    }
                }
                if !life.activeGoals.isEmpty {
                    Section("Linked goals") {
                        ForEach(life.activeGoals) { goal in
                            linkRow(title: goal.title.isEmpty ? "Untitled goal" : goal.title,
                                    icon: goal.kind.icon, on: (draft.linkedGoalIDs ?? []).contains(goal.id)) {
                                toggle(&draft.linkedGoalIDs, goal.id)
                            }
                        }
                    }
                }
                if !life.activeProjects.isEmpty {
                    Section("Linked projects") {
                        ForEach(life.activeProjects) { project in
                            linkRow(title: project.title.isEmpty ? "Untitled project" : project.title,
                                    icon: "square.stack.3d.up", on: (draft.linkedProjectIDs ?? []).contains(project.id)) {
                                toggle(&draft.linkedProjectIDs, project.id)
                            }
                        }
                    }
                }

                if !context.isNew {
                    Section {
                        Button(role: .destructive) {
                            life.deletePillar(draft.id); dismiss()
                        } label: { Label("Delete pillar", systemImage: "trash") }
                    }
                }
            }
            .navigationTitle(context.isNew ? "New Pillar" : "Edit Pillar")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty { draft.name = "Pillar" }
                        life.upsert(draft); dismiss()
                    }
                }
            }
        }
    }

    private func linkRow(title: String, icon: String, on: Bool, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(draft.color).frame(width: 20)
                Text(title).font(.system(size: 14)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(on ? draft.color : Theme.textTertiary)
            }
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ ids: inout [UUID]?, _ id: UUID) {
        var arr = ids ?? []
        if let i = arr.firstIndex(of: id) { arr.remove(at: i) } else { arr.append(id) }
        ids = arr.isEmpty ? nil : arr
    }
}
