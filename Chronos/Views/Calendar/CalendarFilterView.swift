import SwiftUI

/// Show / hide event calendars and reminder lists on the timeline. On
/// Mac/iPad this lives in the sidebar; on iPhone it's a sheet reached from
/// the Calendar screen. Visibility is shared app-wide (Today, Agenda, and
/// the planners all respect it).
struct CalendarFilterView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Rectangle().fill(Theme.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section(
                        title: "Calendars",
                        items: service.calendars,
                        hidden: model.hiddenCalendarIDs,
                        toggle: model.toggleCalendar,
                        showAll: { model.hiddenCalendarIDs.subtract(service.calendars.map(\.id)) },
                        hideAll: { model.hiddenCalendarIDs.formUnion(service.calendars.map(\.id)) }
                    )
                    section(
                        title: "Reminder Lists",
                        items: service.taskLists,
                        hidden: model.hiddenListIDs,
                        toggle: model.toggleList,
                        showAll: { model.hiddenListIDs.subtract(service.taskLists.map(\.id)) },
                        hideAll: { model.hiddenListIDs.formUnion(service.taskLists.map(\.id)) }
                    )
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.elevated)
        .preferredColorScheme(.dark)
        #if os(macOS)
        .frame(width: 420, height: 560)
        #else
        .presentationDetents([.medium, .large])
        #endif
    }

    private var headerBar: some View {
        HStack {
            Button("Done") { dismiss() }
                .buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.accentColor)
                .keyboardShortcut(.defaultAction)
            Spacer()
            Text("Show & Hide").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("Done").font(.system(size: 13)).hidden()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func section(
        title: String,
        items: [CalendarInfo],
        hidden: Set<String>,
        toggle: @escaping (String) -> Void,
        showAll: @escaping () -> Void,
        hideAll: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionHeader(title: title, trailing: "\(items.filter { !hidden.contains($0.id) }.count)/\(items.count)")
                Spacer(minLength: 8)
                Button("All", action: showAll)
                    .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.accentColor)
                Button("None", action: hideAll)
                    .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textTertiary)
            }
            if items.isEmpty {
                Text("None available").font(.system(size: 12)).foregroundStyle(Theme.textTertiary).padding(.vertical, 6)
            } else {
                ForEach(items) { item in
                    let isVisible = !hidden.contains(item.id)
                    Button { toggle(item.id) } label: {
                        HStack(spacing: 11) {
                            Circle()
                                .fill(isVisible ? item.color : Color.clear)
                                .overlay(Circle().strokeBorder(item.color, lineWidth: 1.5))
                                .frame(width: 12, height: 12)
                            Text(item.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(isVisible ? Theme.textPrimary : Theme.textTertiary)
                                .lineLimit(1)
                            if !item.sourceTitle.isEmpty {
                                Text(item.sourceTitle)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.textTertiary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: isVisible ? "eye" : "eye.slash")
                                .font(.system(size: 12))
                                .foregroundStyle(isVisible ? Theme.textSecondary : Theme.textTertiary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
