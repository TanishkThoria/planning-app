import SwiftUI

/// Hour labels running down the left side of day/week timelines.
struct TimeGutter: View {
    let hourHeight: CGFloat
    static let width: CGFloat = 54

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
            ForEach(1..<24, id: \.self) { hour in
                Text(label(for: hour))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.trailing, 8)
                    .offset(y: CGFloat(hour) * hourHeight - 6)
                    .id("hour-\(hour)")
            }
        }
        .frame(width: Self.width, height: 24 * hourHeight, alignment: .topTrailing)
    }

    private func label(for hour: Int) -> String {
        Fmt.hourLabel.string(from: Date().startOfDay.at(minutes: hour * 60))
    }
}

/// The red "current time" indicator.
struct NowLine: View {
    let hourHeight: CGFloat
    let now: Date

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Theme.nowLine)
                .frame(width: 7, height: 7)
            Rectangle()
                .fill(Theme.nowLine)
                .frame(height: 1.5)
        }
        .offset(y: CGFloat(now.minutesSinceMidnight) / 60 * hourHeight - 3.5)
        .allowsHitTesting(false)
    }
}

/// Live "Now / Up next" strip shown under the day header.
struct UpNextStrip: View {
    let blocks: [TimeBlock]
    let now: Date

    var body: some View {
        if let text = statusText {
            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.accentColor)
                    .frame(width: 5, height: 5)
                Text(text)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
        }
    }

    private var statusText: String? {
        let timed = blocks.filter { !$0.isAllDay }.sorted { $0.start < $1.start }
        if let current = timed.first(where: { $0.start <= now && now < $0.end }) {
            let left = Fmt.duration(current.end.timeIntervalSince(now))
            return "Now · \(current.title) · \(left) left"
        }
        if let next = timed.first(where: { $0.start > now }) {
            let inTime = Fmt.duration(next.start.timeIntervalSince(now))
            return "Next · \(next.title) · in \(inTime)"
        }
        return nil
    }
}
