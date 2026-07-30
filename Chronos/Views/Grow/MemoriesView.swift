import SwiftUI

/// The Memory Engine — a personal timeline of the moments that mattered. Some
/// are captured automatically (a project finished, a level reached); most you add
/// yourself. Over years it becomes your life's archive, resurfaced with "On this
/// day…"
struct MemoriesView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var life: LifeStore

    private var grouped: [(year: Int, events: [LifeEvent])] {
        let cal = Calendar.current
        let byYear = Dictionary(grouping: life.timeline) { cal.component(.year, from: $0.date) }
        return byYear.map { (year: $0.key, events: $0.value) }.sorted { $0.year > $1.year }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    let onThisDay = life.onThisDay()
                    if !onThisDay.isEmpty { onThisDaySection(onThisDay) }

                    if life.timeline.isEmpty {
                        EmptyStateView(
                            icon: "clock.arrow.circlepath",
                            title: "Your story starts here",
                            message: "Mark the moments that matter — an acceptance, a finish line, a turning point. Chronos keeps them and brings them back.",
                            actionTitle: "Add a memory"
                        ) {
                            model.memoryEditor = MemoryEditContext(event: LifeEvent(), isNew: true)
                        }
                    } else {
                        ForEach(grouped, id: \.year) { group in
                            yearSection(group.year, group.events)
                        }
                    }
                }
                .padding(Theme.Metric.screen)
                .frame(maxWidth: 620, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg)
            .navigationTitle("Memories")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { model.memoryEditor = MemoryEditContext(event: LifeEvent(), isNew: true) } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .chronosAppearance()
        .sheet(item: $model.memoryEditor) { ctx in MemoryEditorView(context: ctx) }
    }

    private func onThisDaySection(_ events: [LifeEvent]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                IconChip(icon: "sparkles", tint: Color(hex: 0xFFB23E), size: 32)
                Text("On this day").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.textPrimary)
            }
            ForEach(events) { ev in
                HStack(spacing: 10) {
                    if ev.emoji.isEmpty {
                        Image(systemName: ev.kind.icon).font(.system(size: 15)).foregroundStyle(ev.kind.color)
                            .frame(width: 22)
                    } else {
                        Text(ev.emoji).font(.system(size: 18)).frame(width: 22)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ev.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        Text(yearsAgo(ev.date)).font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xFFB23E).opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color(hex: 0xFFB23E).opacity(0.25), lineWidth: 1))
    }

    private func yearSection(_ year: Int, _ events: [LifeEvent]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "\(year)", trailing: "\(events.count)")
            ForEach(events.sorted { $0.epoch > $1.epoch }) { ev in eventRow(ev) }
        }
    }

    private func eventRow(_ ev: LifeEvent) -> some View {
        Button {
            model.memoryEditor = MemoryEditContext(event: ev, isNew: false)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(ev.kind.color.opacity(0.16)).frame(width: 44, height: 44)
                    if ev.emoji.isEmpty {
                        Image(systemName: ev.kind.icon).font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(ev.kind.color)
                    } else {
                        Text(ev.emoji).font(.system(size: 22))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(ev.title.isEmpty ? "Untitled" : ev.title)
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(Fmt.monthDay.string(from: ev.date))
                            .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                        Text("· \(ev.kind.label)").font(.system(size: 12)).foregroundStyle(ev.kind.color)
                    }
                    if !ev.note.isEmpty {
                        Text(ev.note).font(.system(size: 12.5)).foregroundStyle(Theme.textSecondary)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .panel(padding: 12)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button { model.memoryEditor = MemoryEditContext(event: ev, isNew: false) } label: {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive) { life.deleteEvent(ev.id) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private func yearsAgo(_ date: Date) -> String {
        let years = Calendar.current.dateComponents([.year], from: date, to: Date()).year ?? 0
        if years <= 0 { return "Earlier today, in past years" }
        return years == 1 ? "1 year ago today" : "\(years) years ago today"
    }
}
