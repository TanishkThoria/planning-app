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
    @Environment(\.dismiss) private var dismiss

    @State private var newMilestone = ""
    @State private var updateText = ""
    @State private var stampProgress = true
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
                if project.manualProgress != nil { manualProgressCard(project) }
                milestonesSection(project)
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

    private func manualProgressCard(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Progress")
            Slider(value: Binding(
                get: { project.manualProgress ?? 0 },
                set: { var p = project; p.manualProgress = $0; life.upsert(p) }
            ), in: 0...1)
            .tint(project.color)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
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
                Text(Fmt.time.string(from: update.date))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
            Text(update.text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .contextMenu {
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
    @State private var confirmingDelete = false
    let isNew: Bool

    private let emojis = ["🎯", "🚀", "📚", "💪", "🎨", "💼", "🏗️", "🌱", "🎓", "✍️", "🏃", "🧠", "🎸", "💰", "🏠", "❤️"]

    init(project: Project, isNew: Bool) {
        _project = State(initialValue: project)
        _hasTarget = State(initialValue: project.targetDate != nil)
        _manualMode = State(initialValue: project.manualProgress != nil)
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
                 ? "Progress is a slider you set yourself."
                 : "Progress comes from the milestones you complete.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 4)

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
        if manualMode { if project.manualProgress == nil { project.manualProgress = project.milestoneProgress } }
        else { project.manualProgress = nil }
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
