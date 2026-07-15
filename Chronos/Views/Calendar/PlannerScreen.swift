import SwiftUI

/// The unified Calendar screen. One header — title, date navigation, a
/// segmented Day / Week / Agenda switch, and an actions menu — sits above
/// whichever planner mode is active (rendered header-less). This replaces
/// the old separate Day/Week/Agenda destinations so nothing hides behind an
/// overflow menu on iPhone, and the three views feel like one place.
struct PlannerScreen: View {
    @EnvironmentObject private var model: AppModel

    @AppStorage(Prefs.hourHeight) private var hourHeight = 72.0

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
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                DateNavigator()
                HeaderIconButton(icon: "line.3.horizontal.decrease.circle") {
                    model.calendarFilterPresented = true
                }
                .help("Show & hide calendars")
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

            actionsRow
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    /// Labeled actions instead of an ellipsis "More" menu — every planner
    /// action is visible and named. Rarer commands stay in the ⌘K bar.
    private var actionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if model.plannerMode == .week {
                    actionChip("Plan week", "wand.and.stars") { model.planWeekPresented = true }
                } else {
                    actionChip("Plan day", "wand.and.stars") { model.planDayPresented = true }
                }
                actionChip("Review", "checkmark.circle") { model.reviewPresented = true }
                actionChip("Templates", "square.grid.3x3") { model.templatesPresented = true }
                actionChip("Focus", "timer") { model.startFocus(taskID: nil, title: "Focus") }
                if model.plannerMode == .day {
                    actionChip(model.backlogVisible ? "Hide backlog" : "Backlog", "sidebar.right") {
                        model.backlogVisible.toggle()
                    }
                    zoomControl
                }
            }
            .padding(.horizontal, 1)
            .padding(.vertical, 1)
        }
    }

    private func actionChip(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(Theme.accentColor)
            .padding(.horizontal, 11).padding(.vertical, 7)
            .background(Theme.accentColor.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var zoomControl: some View {
        HStack(spacing: 2) {
            Button { hourHeight = max(40, hourHeight - 10) } label: {
                Image(systemName: "minus.magnifyingglass").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accentColor)
                    .padding(.horizontal, 8).padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            Button { hourHeight = min(160, hourHeight + 10) } label: {
                Image(systemName: "plus.magnifyingglass").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accentColor)
                    .padding(.horizontal, 8).padding(.vertical, 7)
            }
            .buttonStyle(.plain)
        }
        .background(Theme.accentColor.opacity(0.12), in: Capsule())
    }

    // MARK: Title text

    private var title: String {
        switch model.plannerMode {
        case .day: return Fmt.relativeDay(model.selectedDate)
        case .week, .month: return Fmt.monthTitle.string(from: model.selectedDate)
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
        case .month:
            return "Tap a day to plan it"
        case .agenda:
            return "Next 7 days"
        }
    }

    // MARK: Body

    @ViewBuilder
    private var content: some View {
        switch model.plannerMode {
        case .day: DayPlannerView(embedded: true)
        case .week: WeekPlannerView(embedded: true)
        case .month: MonthView()
        case .agenda: AgendaView(embedded: true)
        }
    }
}
