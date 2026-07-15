import SwiftUI

/// Weekly time budgets: set a target number of hours per calendar and track
/// how the current week is tracking against it. Turns vague intentions
/// ("more exercise, less email") into a measurable weekly allocation.
struct BudgetsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var life: LifeStore
    @Environment(\.dismiss) private var dismiss

    private var weekDays: [Date] {
        let start = model.selectedDate.startOfWeek
        return (0..<7).map { start.adding(days: $0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Rectangle().fill(Theme.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Set a weekly hour target for the calendars that matter. Progress reflects this week's blocks.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 2)
                    ForEach(service.calendars.filter(\.isEditable)) { cal in
                        budgetRow(cal)
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
        }
        .background(Theme.elevated)
        .chronosAppearance()
        #if os(macOS)
        .frame(width: 460, height: 560)
        #else
        .presentationDetents([.large])
        #endif
    }

    private var headerBar: some View {
        HStack {
            Button("Done") { dismiss() }
                .buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.accentColor)
                .keyboardShortcut(.defaultAction)
            Spacer()
            Text("Time Budgets").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("Done").font(.system(size: 13)).hidden()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func budgetRow(_ cal: CalendarInfo) -> some View {
        let target = life.budget(for: cal.id)?.weeklyHoursTarget ?? 0
        let actual = weekMinutes(cal.id)
        let frac = target > 0 ? Double(actual) / (target * 60) : 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(cal.color).frame(width: 8, height: 8)
                Text(cal.title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer()
                Stepper(value: Binding(
                    get: { target },
                    set: { life.setBudget(calendarID: cal.id, hours: $0) }
                ), in: 0...80, step: 0.5) {
                    Text(target > 0 ? String(format: "%g h", target) : "Off")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(target > 0 ? Theme.textPrimary : Theme.textTertiary)
                }
                .fixedSize()
            }
            if target > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.fill)
                        Capsule().fill(frac >= 1 ? Theme.success : cal.color)
                            .frame(width: min(geo.size.width, geo.size.width * frac))
                    }
                }
                .frame(height: 6)
                Text("\(Fmt.duration(minutes: actual)) of \(String(format: "%g h", target)) this week")
                    .font(.system(size: 10.5, design: .rounded)).foregroundStyle(Theme.textTertiary)
            }
        }
        .panel(padding: 12)
    }

    private func weekMinutes(_ calendarID: String) -> Int {
        weekDays.reduce(0) { acc, day in
            acc + service.blocks(on: day)
                .filter { !$0.isAllDay && $0.calendarID == calendarID }
                .compactMap { $0.clamped(to: day) }
                .reduce(0) { $0 + Int($1.end.timeIntervalSince($1.start) / 60) }
        }
    }
}
