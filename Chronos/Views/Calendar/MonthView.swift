import SwiftUI

/// The zoomed-out month: a full grid for planning ahead at a glance, with
/// per-day event dots and a habit-completion ring. Tap any day to see and
/// add to it — the fast way to drop something on a future date, the way
/// Apple's month view feels. Great for spotting busy stretches and empty
/// space weeks out.
struct MonthView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var life: LifeStore

    @AppStorage(Prefs.defaultBlockMinutes) private var defaultBlockMinutes = 30
    @AppStorage(Prefs.defaultCalendarID) private var defaultCalendarID = ""

    private var calendar: Calendar { Calendar.current }

    private var monthDays: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: model.selectedDate) else { return [] }
        let firstDay = interval.start
        let dayCount = calendar.range(of: .day, in: .month, for: model.selectedDate)?.count ?? 30
        let leading = (calendar.component(.weekday, from: firstDay) - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<dayCount { cells.append(firstDay.adding(days: offset)) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                weekdayHeader
                monthGrid
                selectedDayPanel
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols(), id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var monthGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 62)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = day.isSameDay(as: model.selectedDate)
        let isToday = day.isToday
        let blocks = service.blocks(on: day, hiddenCalendars: model.hiddenCalendarIDs).filter { !$0.isAllDay }
        let dotColors = Array(blocks.prefix(4)).map(\.color)
        let habitFraction = habitCompletion(on: day)

        return Button {
            Haptics.selection()
            model.selectedDate = day.startOfDay
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    if isSelected {
                        Circle().fill(Theme.accentColor).frame(width: 26, height: 26)
                    } else if isToday {
                        Circle().fill(Theme.accentColor.opacity(0.16)).frame(width: 26, height: 26)
                    }
                    Text(Fmt.dayNumber.string(from: day))
                        .font(.system(size: 14.5, weight: isToday || isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? Theme.bg : (isToday ? Theme.accentColor : Theme.textPrimary))
                }
                .frame(height: 26)

                // Event dots
                HStack(spacing: 2.5) {
                    ForEach(Array(dotColors.enumerated()), id: \.offset) { _, color in
                        Circle().fill(color).frame(width: 4.5, height: 4.5)
                    }
                }
                .frame(height: 5)

                // Habit ring (past/today only)
                if let habitFraction, !life.activeHabits.isEmpty {
                    Circle()
                        .trim(from: 0, to: max(0.02, habitFraction))
                        .stroke(habitFraction >= 1 ? Theme.success : Theme.textTertiary,
                                style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 8, height: 8)
                } else {
                    Color.clear.frame(height: 8)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .background(
                isSelected ? Theme.fill : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Fraction of due habits completed on a day (nil for future days or none due).
    private func habitCompletion(on day: Date) -> Double? {
        guard day <= Date().startOfDay else { return nil }
        let due = life.activeHabits.filter { $0.isDue(on: day) }
        guard !due.isEmpty else { return nil }
        let done = due.filter { life.isDone($0, on: day) }.count
        return Double(done) / Double(due.count)
    }

    // MARK: Selected day panel

    private var selectedDayPanel: some View {
        let day = model.selectedDate
        let blocks = service.blocks(on: day, hiddenCalendars: model.hiddenCalendarIDs)
            .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
        let due = service.tasks.filter {
            !model.hiddenListIDs.contains($0.listID) && ($0.dueDate?.isSameDay(as: day) ?? false)
        }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Fmt.relativeDay(day))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button {
                    model.newBlock(at: day.at(minutes: 9 * 60), defaultMinutes: defaultBlockMinutes,
                                   calendarID: defaultCalendarID.isEmpty ? nil : defaultCalendarID)
                } label: {
                    Image(systemName: "plus").font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Theme.onAccent).frame(width: 26, height: 24)
                        .background(Theme.accentColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                Button { model.openDay(day) } label: {
                    Image(systemName: "arrow.up.right.square").font(.system(size: 14.5))
                        .foregroundStyle(Theme.textSecondary).frame(width: 26, height: 24)
                        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            if blocks.isEmpty && due.isEmpty {
                Text("Nothing planned — tap + to add something.")
                    .font(.system(size: 13.5)).foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, 6)
            } else {
                ForEach(blocks) { block in
                    Button { model.blockEditor = service.editorContext(for: block) } label: {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 2).fill(block.color).frame(width: 3, height: 26)
                            Text(block.isAllDay ? "all-day" : Fmt.time.string(from: block.start))
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary).frame(width: 56, alignment: .leading)
                            Text(block.title).font(.system(size: 14.5)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                ForEach(due) { task in
                    Button { model.taskEditor = service.editorContext(for: task) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 14.5))
                                .foregroundStyle(task.isCompleted ? Theme.success : task.priority.color)
                            Text(task.title).font(.system(size: 14.5))
                                .foregroundStyle(task.isCompleted ? Theme.textTertiary : Theme.textPrimary).lineLimit(1)
                                .strikethrough(task.isCompleted, color: Theme.textTertiary)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func weekdaySymbols() -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}
