import SwiftUI

/// Weekly time budgets by activity category: set a target number of hours for
/// what you're *doing* (Work, Gym, Social, …) and track how the current week is
/// tracking against it. Turns vague intentions ("more exercise, less busywork")
/// into a measurable weekly allocation, independent of which calendar it lives on.
struct BudgetsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService
    @EnvironmentObject private var life: LifeStore
    @Environment(\.dismiss) private var dismiss

    /// Categories worth budgeting (Other isn't a meaningful target).
    private var categories: [ActivityCategory] {
        ActivityCategory.allCases.filter { $0 != .other }
    }

    private var weekDays: [Date] {
        let start = model.selectedDate.startOfWeek
        return (0..<7).map { start.adding(days: $0) }
    }

    /// Minutes spent per category across this week, computed in one pass.
    private var minutesByCategory: [ActivityCategory: Int] {
        var totals: [ActivityCategory: Int] = [:]
        for day in weekDays {
            for block in service.blocks(on: day, hiddenCalendars: model.hiddenCalendarIDs) where !block.isAllDay {
                guard let clamped = block.clamped(to: day) else { continue }
                let m = Int(clamped.end.timeIntervalSince(clamped.start) / 60)
                guard m > 0 else { continue }
                totals[TagStore.shared.category(for: block), default: 0] += m
            }
        }
        return totals
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Rectangle().fill(Theme.hairline).frame(height: 1)

            ScrollView {
                let byCat = minutesByCategory
                VStack(alignment: .leading, spacing: 10) {
                    Text("Set a weekly hour target for the kinds of things you want more (or less) of. Progress reflects this week's blocks, categorised automatically.")
                        .font(.system(size: 13)).foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 2)
                    ForEach(categories) { category in
                        budgetRow(category, actual: byCat[category] ?? 0)
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
                .buttonStyle(.plain).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Theme.accentColor)
                .keyboardShortcut(.defaultAction)
            Spacer()
            Text("Time Budgets").font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Text("Done").font(.system(size: 14.5)).hidden()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func budgetRow(_ category: ActivityCategory, actual: Int) -> some View {
        let target = life.budget(for: category)?.weeklyHoursTarget ?? 0
        let frac = target > 0 ? Double(actual) / (target * 60) : 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(category.color)
                    .frame(width: 18)
                Text(category.title).font(.system(size: 14.5, weight: .medium)).foregroundStyle(Theme.textPrimary).lineLimit(1)
                Spacer()
                Stepper(value: Binding(
                    get: { target },
                    set: { life.setBudget(category: category, hours: $0) }
                ), in: 0...80, step: 0.5) {
                    Text(target > 0 ? String(format: "%g h", target) : "Off")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(target > 0 ? Theme.textPrimary : Theme.textTertiary)
                }
                .fixedSize()
            }
            if target > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.fill)
                        Capsule().fill(frac >= 1 ? Theme.success : category.color)
                            .frame(width: min(geo.size.width, geo.size.width * frac))
                    }
                }
                .frame(height: 6)
                Text("\(Fmt.duration(minutes: actual)) of \(String(format: "%g h", target)) this week")
                    .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            } else if actual > 0 {
                Text("\(Fmt.duration(minutes: actual)) this week")
                    .font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
            }
        }
        .panel(padding: 12)
    }
}
