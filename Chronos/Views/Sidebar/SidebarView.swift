import SwiftUI

/// macOS / iPad sidebar: navigation, a mini month for jumping around, and
/// visibility toggles for every calendar and reminder list.
struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                VStack(alignment: .leading, spacing: 2) {
                    ForEach(AppModel.Screen.sidebarCases) { screen in
                        navRow(screen)
                    }
                }

                MiniMonthView(selectedDate: $model.selectedDate) {
                    if model.screen != .day && model.screen != .week {
                        model.screen = .day
                    }
                }

                calendarSection(
                    title: "Calendars",
                    items: service.calendars,
                    hidden: model.hiddenCalendarIDs,
                    toggle: model.toggleCalendar
                )

                calendarSection(
                    title: "Reminder Lists",
                    items: service.taskLists,
                    hidden: model.hiddenListIDs,
                    toggle: model.toggleList
                )
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "hexagon.fill")
                .font(.system(size: 14))
                .foregroundStyle(.tint)
            Text("CHRONOS")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .tracking(3)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
        }
        .padding(.top, 4)
    }

    private func navRow(_ screen: AppModel.Screen) -> some View {
        Button {
            model.screen = screen
        } label: {
            HStack(spacing: 10) {
                Image(systemName: screen.icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 20)
                Text(screen.title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                if let key = screen.shortcut {
                    Text("⌘\(String(key.character).uppercased())")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .foregroundStyle(model.screen == screen ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                model.screen == screen ? Theme.fill : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private func calendarSection(
        title: String,
        items: [CalendarInfo],
        hidden: Set<String>,
        toggle: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 10)

            ForEach(items) { item in
                Button {
                    toggle(item.id)
                } label: {
                    HStack(spacing: 9) {
                        Circle()
                            .fill(hidden.contains(item.id) ? Color.clear : item.color)
                            .overlay(Circle().strokeBorder(item.color, lineWidth: 1.5))
                            .frame(width: 9, height: 9)
                        Text(item.title)
                            .font(.system(size: 12.5))
                            .lineLimit(1)
                            .foregroundStyle(
                                hidden.contains(item.id) ? Theme.textTertiary : Theme.textSecondary
                            )
                        Spacer()
                        if !item.isEditable {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
