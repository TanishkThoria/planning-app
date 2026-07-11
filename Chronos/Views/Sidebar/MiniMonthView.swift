import SwiftUI

/// Compact month grid for fast date jumping. Locale-aware first weekday.
struct MiniMonthView: View {
    @Binding var selectedDate: Date
    var onSelect: () -> Void = {}

    @State private var visibleMonth: Date = Date().startOfDay

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(Fmt.monthTitle.string(from: visibleMonth))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button { shiftMonth(-1) } label: {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
                Button { shiftMonth(1) } label: {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, 6)
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
            LazyVGrid(columns: columns, spacing: 3) {
                // Symbols repeat ("S", "T"), so identify columns by index.
                ForEach(Array(weekdaySymbols().enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                ForEach(Array(monthDays().enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 22)
                    }
                }
            }
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onChange(of: selectedDate) { _, newDate in
            if !calendar.isDate(newDate, equalTo: visibleMonth, toGranularity: .month) {
                visibleMonth = newDate
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = day.isSameDay(as: selectedDate)
        let isToday = day.isToday
        return Button {
            selectedDate = day.startOfDay
            onSelect()
        } label: {
            Text(Fmt.dayNumber.string(from: day))
                .font(.system(size: 11, weight: isSelected || isToday ? .bold : .regular, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .foregroundStyle(
                    isSelected ? Theme.bg : (isToday ? Color.accentColor : Theme.textSecondary)
                )
                .background(
                    isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.clear),
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    private func shiftMonth(_ delta: Int) {
        visibleMonth = calendar.date(byAdding: .month, value: delta, to: visibleMonth) ?? visibleMonth
    }

    private func weekdaySymbols() -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// Day cells for the visible month, nil-padded to align the first
    /// weekday column.
    private func monthDays() -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: visibleMonth) else { return [] }
        let firstDay = interval.start
        let dayCount = calendar.range(of: .day, in: .month, for: visibleMonth)?.count ?? 30
        let leading = (calendar.component(.weekday, from: firstDay) - calendar.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<dayCount {
            cells.append(firstDay.adding(days: offset))
        }
        return cells
    }
}
