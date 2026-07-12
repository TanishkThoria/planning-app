import SwiftUI

/// The unified Calendar screen. One header — title, date navigation, a
/// segmented Day / Week / Agenda switch, and an actions menu — sits above
/// whichever planner mode is active (rendered header-less). This replaces
/// the old separate Day/Week/Agenda destinations so nothing hides behind an
/// overflow menu on iPhone, and the three views feel like one place.
struct PlannerScreen: View {
    @EnvironmentObject private var model: AppModel

    @AppStorage(Prefs.hourHeight) private var hourHeight = 64.0

    private var weekDays: [Date] {
        let start = model.selectedDate.startOfWeek
        return (0..<7).map { start.adding(days: $0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Rectangle().fill(Theme.hairline).frame(height: 1)
            content
        }
        .background(Theme.bg)
    }

    // MARK: Header

    private var headerBar: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                DateNavigator()
                actionsMenu
                HeaderIconButton(icon: "plus", prominent: true) {
                    model.quickAddPresented = true
                }
                .keyboardShortcut("k", modifiers: .command)
            }

            Picker("", selection: $model.plannerMode) {
                ForEach(AppModel.PlannerMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var actionsMenu: some View {
        Menu {
            Button {
                model.morningPlanningPresented = true
            } label: { Label("Plan Today", systemImage: "sunrise") }

            if model.plannerMode == .week {
                Button { model.planWeekPresented = true } label: {
                    Label("Plan My Week", systemImage: "wand.and.stars")
                }
            } else {
                Button { model.planDayPresented = true } label: {
                    Label("Plan My Day", systemImage: "wand.and.stars")
                }
            }

            Button { model.reviewPresented = true } label: {
                Label("Review Day", systemImage: "checkmark.circle")
            }
            Button { model.startFocus(taskID: nil, title: "Focus") } label: {
                Label("Focus Timer", systemImage: "timer")
            }

            #if os(iOS)
            Divider()
            Button { model.settingsPresented = true } label: {
                Label("Settings", systemImage: "gearshape")
            }
            #endif

            if model.plannerMode == .day {
                Divider()
                Button { model.backlogVisible.toggle() } label: {
                    Label(model.backlogVisible ? "Hide Backlog" : "Show Backlog", systemImage: "sidebar.right")
                }
                Button { hourHeight = min(160, hourHeight + 10) } label: {
                    Label("Zoom In", systemImage: "plus.magnifyingglass")
                }
                Button { hourHeight = max(40, hourHeight - 10) } label: {
                    Label("Zoom Out", systemImage: "minus.magnifyingglass")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 28, height: 26)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .menuIndicator(.hidden)
    }

    // MARK: Title text

    private var title: String {
        switch model.plannerMode {
        case .day: return Fmt.relativeDay(model.selectedDate)
        case .week: return Fmt.monthTitle.string(from: model.selectedDate)
        case .agenda: return "Agenda"
        }
    }

    private var subtitle: String {
        switch model.plannerMode {
        case .day:
            return Fmt.monthDayYear.string(from: model.selectedDate)
        case .week:
            guard let first = weekDays.first, let last = weekDays.last else { return "" }
            return "\(Fmt.monthDay.string(from: first)) – \(Fmt.monthDay.string(from: last))"
        case .agenda:
            return "Next 14 days"
        }
    }

    // MARK: Body

    @ViewBuilder
    private var content: some View {
        switch model.plannerMode {
        case .day: DayPlannerView(embedded: true)
        case .week: WeekPlannerView(embedded: true)
        case .agenda: AgendaView(embedded: true)
        }
    }
}
