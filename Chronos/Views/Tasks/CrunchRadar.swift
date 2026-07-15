import SwiftUI

/// A 14-day forward look at deadline pressure: each square's intensity is the
/// estimated work due that day. Spot the crunch *before* it lands on you —
/// then hit Plan Deadlines to spread the work out.
struct CrunchRadar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var service: EventKitService

    private var days: [Date] {
        (0..<14).map { Date().startOfDay.adding(days: $0) }
    }

    /// Estimated minutes due per day (unestimated tasks count as 30m).
    private var loadByDay: [Date: Int] {
        var load: [Date: Int] = [:]
        for task in service.tasks where !task.isCompleted && !task.isSubtask {
            guard let due = task.dueDate else { continue }
            let day = due.startOfDay
            guard day >= days.first ?? day, day <= days.last ?? day else { continue }
            load[day, default: 0] += task.estimateMinutes ?? 30
        }
        return load
    }

    var body: some View {
        let load = loadByDay
        let peak = load.values.max() ?? 0

        if peak == 0 {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("CRUNCH RADAR", systemImage: "gauge.with.needle")
                        .font(.system(size: 10, weight: .bold))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                    if let peakDay = load.max(by: { $0.value < $1.value })?.key {
                        Text("peak \(Fmt.relativeDay(peakDay)) · \(Fmt.duration(minutes: peak))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                HStack(spacing: 4) {
                    ForEach(days, id: \.self) { day in
                        let minutes = load[day] ?? 0
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(color(for: minutes, peak: peak))
                                .frame(height: 20)
                            Text(Fmt.weekdayShort.string(from: day).prefix(1))
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(day.isToday ? Color.accentColor : Theme.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Button {
                    model.deadlinePlanPresented = true
                } label: {
                    Label("Spread the work out", systemImage: "calendar.badge.clock")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func color(for minutes: Int, peak: Int) -> Color {
        guard minutes > 0 else { return Theme.fill }
        let intensity = Double(minutes) / Double(max(peak, 1))
        if intensity > 0.75 { return Theme.danger.opacity(0.85) }
        if intensity > 0.45 { return Theme.warning.opacity(0.8) }
        return Color.accentColor.opacity(0.35 + intensity * 0.4)
    }
}
