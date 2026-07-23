import SwiftUI

/// "Where did my time actually go." Time allocation across a chosen range,
/// broken down by calendar and by cognitive load, with a comparison to the
/// previous period so you can see the trend, not just the total.
struct TimeReportView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var focusLog: FocusLog
    @Environment(\.dismiss) private var dismiss

    enum Span: String, CaseIterable, Identifiable {
        case week = "This Week", month = "This Month"
        var id: String { rawValue }
    }
    @State private var span: Span = .week

    private var range: DateInterval {
        let cal = Calendar.current
        let now = Date()
        switch span {
        case .week:
            let start = now.startOfWeek
            return DateInterval(start: start, end: start.adding(days: 7))
        case .month:
            let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now.startOfDay
            let end = cal.date(byAdding: .month, value: 1, to: start) ?? start.adding(days: 30)
            return DateInterval(start: start, end: end)
        }
    }

    private var previousRange: DateInterval {
        let length = range.duration
        return DateInterval(start: range.start.addingTimeInterval(-length), duration: length)
    }

    private func minutes(in interval: DateInterval) -> Int {
        service.blocks(from: interval.start, to: interval.end, hiddenCalendars: model.hiddenCalendarIDs)
            .reduce(0) { $0 + clampMinutes($1, to: interval) }
    }

    private func clampMinutes(_ block: TimeBlock, to interval: DateInterval) -> Int {
        let s = max(block.start, interval.start)
        let e = min(block.end, interval.end)
        return e > s ? Int(e.timeIntervalSince(s) / 60) : 0
    }

    private var byCalendar: [(cal: CalendarInfo, minutes: Int)] {
        var totals: [String: Int] = [:]
        for block in service.blocks(from: range.start, to: range.end, hiddenCalendars: model.hiddenCalendarIDs) {
            totals[block.calendarID, default: 0] += clampMinutes(block, to: range)
        }
        return totals
            .compactMap { id, m in service.calendarInfo(withID: id).map { ($0, m) } }
            .sorted { $0.1 > $1.1 }
    }

    private var byEnergy: (deep: Int, shallow: Int, other: Int) {
        var deep = 0, shallow = 0, other = 0
        for block in service.blocks(from: range.start, to: range.end, hiddenCalendars: model.hiddenCalendarIDs) {
            let m = clampMinutes(block, to: range)
            switch block.linkedTaskID.flatMap({ service.task(withID: $0) })?.energy {
            case .deep: deep += m
            case .shallow: shallow += m
            default: other += m
            }
        }
        return (deep, shallow, other)
    }

    private func focusMinutes(in interval: DateInterval) -> Int {
        focusLog.sessions
            .filter { interval.contains($0.start) }
            .reduce(0) { $0 + $1.actualMinutes }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.hairline).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("", selection: $span) {
                        ForEach(Span.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()

                    headlineCard
                    categoryCard
                    calendarCard
                    energyCard
                }
                .padding(18)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.bg)
        .chronosAppearance()
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Time Report")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Where your hours actually went")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20)).foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
    }

    private var headlineCard: some View {
        let planned = minutes(in: range)
        let prev = minutes(in: previousRange)
        let focus = focusMinutes(in: range)
        return HStack(spacing: 10) {
            bigStat("calendar", Theme.accentColor, Fmt.duration(minutes: planned), "Scheduled", delta: planned - prev)
            Rectangle().fill(Theme.hairline).frame(width: 1, height: 56)
            bigStat("timer", Color(hex: 0xFF7A59), Fmt.duration(minutes: focus), "Focused", delta: focus - focusMinutes(in: previousRange))
        }
        .frame(maxWidth: .infinity)
        .panel()
    }

    private func bigStat(_ icon: String, _ tint: Color, _ value: String, _ label: String, delta: Int) -> some View {
        VStack(spacing: 6) {
            IconChip(icon: icon, tint: tint, size: 32)
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(1)
                .foregroundStyle(Theme.textTertiary)
            if delta != 0 {
                Label("\(delta > 0 ? "+" : "")\(Fmt.duration(minutes: abs(delta)))",
                      systemImage: delta > 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(delta > 0 ? Theme.success : Theme.textTertiary)
            } else {
                Text("—").font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var byCategory: [(category: ActivityCategory, minutes: Int)] {
        var totals: [ActivityCategory: Int] = [:]
        for block in service.blocks(from: range.start, to: range.end, hiddenCalendars: model.hiddenCalendarIDs) where !block.isAllDay {
            let m = clampMinutes(block, to: range)
            guard m > 0 else { continue }
            totals[TagStore.shared.category(for: block), default: 0] += m
        }
        return totals.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    private var categoryCard: some View {
        let data = byCategory
        let peak = max(data.map(\.minutes).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "By category")
            if data.isEmpty {
                Text("No time blocked in this period.")
                    .font(.system(size: 13.5)).foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(data, id: \.category.id) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: entry.category.icon)
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundStyle(entry.category.color).frame(width: 14)
                                Text(entry.category.title).font(.system(size: 13.5, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary).lineLimit(1)
                            }
                            Spacer()
                            Text(Fmt.duration(minutes: entry.minutes))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        GeometryReader { geo in
                            Capsule().fill(entry.category.color)
                                .frame(width: max(geo.size.width * CGFloat(entry.minutes) / CGFloat(peak), 4))
                        }
                        .frame(height: 5)
                        .background(Theme.fill, in: Capsule())
                    }
                }
            }
        }
        .panel()
    }

    private var calendarCard: some View {
        let data = byCalendar
        let peak = max(data.map(\.minutes).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "By calendar")
            if data.isEmpty {
                Text("No time blocked in this period.")
                    .font(.system(size: 13.5)).foregroundStyle(Theme.textTertiary)
            } else {
                ForEach(data, id: \.cal.id) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            HStack(spacing: 6) {
                                Circle().fill(entry.cal.color).frame(width: 7, height: 7)
                                Text(entry.cal.title).font(.system(size: 13.5, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary).lineLimit(1)
                            }
                            Spacer()
                            Text(Fmt.duration(minutes: entry.minutes))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        GeometryReader { geo in
                            Capsule().fill(entry.cal.color)
                                .frame(width: max(geo.size.width * CGFloat(entry.minutes) / CGFloat(peak), 4))
                        }
                        .frame(height: 5)
                        .background(Theme.fill, in: Capsule())
                    }
                }
            }
        }
        .panel()
    }

    private var energyCard: some View {
        let e = byEnergy
        let total = max(e.deep + e.shallow + e.other, 1)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "By focus type", trailing: e.deep + e.shallow > 0 ? "\(Int(Double(e.deep) / Double(max(e.deep + e.shallow, 1)) * 100))% deep" : nil)
            GeometryReader { geo in
                HStack(spacing: 2) {
                    segment(TaskEnergy.deep.color, e.deep, total, geo.size.width)
                    segment(TaskEnergy.shallow.color, e.shallow, total, geo.size.width)
                    segment(Theme.textTertiary.opacity(0.4), e.other, total, geo.size.width)
                }
            }
            .frame(height: 12)
            HStack(spacing: 14) {
                legend(TaskEnergy.deep.color, "Deep", e.deep)
                legend(TaskEnergy.shallow.color, "Shallow", e.shallow)
                legend(Theme.textTertiary.opacity(0.5), "Untagged", e.other)
            }
        }
        .panel()
    }

    private func segment(_ color: Color, _ value: Int, _ total: Int, _ width: CGFloat) -> some View {
        Capsule().fill(color)
            .frame(width: value > 0 ? max((width - 4) * CGFloat(value) / CGFloat(total), 3) : 0)
    }

    private func legend(_ color: Color, _ label: String, _ minutes: Int) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(label) · \(Fmt.duration(minutes: minutes))")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }
}
