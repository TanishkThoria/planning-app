import SwiftUI

/// The Life Map — the single view that makes purpose visible. It threads a line
/// from the person you're becoming, down through your dreams, your projects, the
/// habits that power them, to the one step in front of you today. "This task
/// supports this project supports this life."
struct LifeMapView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var life: LifeStore
    @EnvironmentObject private var service: EventKitService

    private var today: Date { Date().startOfDay }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    intro.padding(.bottom, 8)
                    destinationNode
                    if !visionText.isEmpty { visionNode }
                    projectsNode
                    habitsNode
                    todayNode
                }
                .padding(Theme.Metric.screen)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg)
            .navigationTitle("Life Map")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .chronosAppearance()
    }

    private var intro: some View {
        Text("Every task supports a project. Every project supports a life. Here's the thread from today all the way up to who you're becoming.")
            .font(.system(size: 13.5)).foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Nodes (top = the destination, bottom = today)

    private var destinationNode: some View {
        node(icon: "figure.stand", tint: Theme.accentColor, isFirst: true, tapsToFutureSelf: true) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Who you're becoming").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary).textCase(.uppercase)
                Text(life.futureSelf.isDefined && !life.futureSelf.name.isEmpty
                     ? life.futureSelf.name : "Define your future self")
                    .font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.textPrimary)
                if !life.activePillars.isEmpty {
                    FlowChips(items: life.activePillars.prefix(4).map(\.name), tint: Theme.accentColor)
                }
            }
        }
    }

    private var visionNode: some View {
        node(icon: "mountain.2.fill", tint: Color(hex: 0x9C7BFA)) {
            VStack(alignment: .leading, spacing: 4) {
                Text("The long arc").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary).textCase(.uppercase)
                Text(visionText).font(.system(size: 14)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true).lineLimit(4)
            }
        }
    }

    private var projectsNode: some View {
        let projects = life.activeProjects
        return node(icon: "square.stack.3d.up.fill", tint: Color(hex: 0x5B6CF0), tapAction: { open(.projects) }) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What you're building").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary).textCase(.uppercase)
                if projects.isEmpty {
                    Text("No active projects — the vehicles that carry you toward the vision.")
                        .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(projects.prefix(4)) { p in
                        HStack(spacing: 8) {
                            Text(p.emoji).font(.system(size: 15))
                            Text(p.title.isEmpty ? "Untitled" : p.title)
                                .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                            Spacer(minLength: 4)
                            Text("\(Int((p.progress * 100).rounded()))%")
                                .font(.system(size: 12.5, weight: .bold)).foregroundStyle(p.color)
                        }
                    }
                    if projects.count > 4 {
                        Text("+\(projects.count - 4) more").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
    }

    private var habitsNode: some View {
        let habits = life.activeHabits
        return node(icon: "repeat", tint: Color(hex: 0x3FC97A), tapAction: { open(.grow) }) {
            VStack(alignment: .leading, spacing: 8) {
                Text("The daily engine").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary).textCase(.uppercase)
                if habits.isEmpty {
                    Text("No habits yet — the small repeated actions that compound into all of it.")
                        .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    FlowChips(items: habits.prefix(6).map { $0.title.isEmpty ? "Habit" : $0.title },
                              tint: Color(hex: 0x3FC97A))
                }
            }
        }
    }

    private var todayNode: some View {
        let intent = life.intent(for: today)
        let dueCount = service.tasks.filter { !$0.isCompleted && $0.isDueToday && !model.hiddenListIDs.contains($0.listID) }.count
        return node(icon: "sun.max.fill", tint: Color(hex: 0xFFB23E), isLast: true, tapAction: { open(.today) }) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Today's step").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary).textCase(.uppercase)
                if let intent, !intent.mustWins.isEmpty {
                    ForEach(intent.mustWins.prefix(3)) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 14)).foregroundStyle(item.isDone ? Theme.success : Theme.textTertiary)
                            Text(item.text).font(.system(size: 14))
                                .foregroundStyle(item.isDone ? Theme.textTertiary : Theme.textPrimary)
                                .strikethrough(item.isDone, color: Theme.textTertiary).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                } else if dueCount > 0 {
                    Text("\(dueCount) task\(dueCount == 1 ? "" : "s") due today — each one is a small vote for who you're becoming.")
                        .font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Nothing scheduled yet. Set today's minimum and take one step.")
                        .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Node scaffold (rail + connector + card)

    private func node<Content: View>(
        icon: String, tint: Color,
        isFirst: Bool = false, isLast: Bool = false,
        tapsToFutureSelf: Bool = false, tapAction: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Rectangle().fill(isFirst ? Color.clear : Theme.hairline).frame(width: 2, height: 14)
                IconChip(icon: icon, tint: tint, size: 36)
                Rectangle().fill(isLast ? Color.clear : Theme.hairline).frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 36)

            Button {
                if tapsToFutureSelf { model.futureSelfPresented = true } else { tapAction?() }
            } label: {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .panel(padding: 14)
            }
            .buttonStyle(.plain)
            .disabled(!tapsToFutureSelf && tapAction == nil)
            .padding(.bottom, 12)
        }
    }

    private var visionText: String {
        let fs = life.futureSelf
        if !fs.visionTenYear.isEmpty { return fs.visionTenYear }
        if !fs.visionFiveYear.isEmpty { return fs.visionFiveYear }
        if !fs.visionOneYear.isEmpty { return fs.visionOneYear }
        if !life.bigDream.isEmpty { return life.bigDream }
        return ""
    }

    private enum Dest { case projects, grow, today }
    private func open(_ dest: Dest) {
        dismiss()
        model.afterDismiss {
            switch dest {
            case .projects: model.projectsInitialID = nil; model.projectsPresented = true
            case .grow: model.screen = .grow
            case .today: model.screen = .today
            }
        }
    }
}
