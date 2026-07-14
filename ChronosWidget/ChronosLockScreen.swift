import WidgetKit
import SwiftUI

/// Lock Screen (accessory) complications: a momentum ring and an inline
/// "next up" line. Widget-target only; reuses the shared TodaySnapshot.

// MARK: - Momentum ring (accessoryCircular)

struct ChronosMomentumWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ChronosMomentum", provider: ChronosProvider()) { entry in
            ChronosMomentumView(snapshot: entry.snapshot)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Momentum")
        .description("Today's momentum at a glance.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct ChronosMomentumView: View {
    let snapshot: TodaySnapshot

    private var value: Double { Double(snapshot.momentum ?? 0) / 100 }

    var body: some View {
        Gauge(value: value) {
            Image(systemName: "bolt.fill")
        } currentValueLabel: {
            Text("\(snapshot.momentum ?? 0)")
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }
}

// MARK: - Next up (accessoryInline)

struct ChronosNextInlineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ChronosNextInline", provider: ChronosProvider()) { entry in
            ChronosNextInlineView(snapshot: entry.snapshot)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Next Up (Inline)")
        .description("Your current or next block, above the clock.")
        .supportedFamilies([.accessoryInline])
    }
}

struct ChronosNextInlineView: View {
    let snapshot: TodaySnapshot

    var body: some View {
        if let current = snapshot.current {
            Label("Now: \(current.title)", systemImage: "circle.fill")
        } else if let next = snapshot.next {
            Label("\(inlineTime(next.start)) \(next.title)", systemImage: "arrow.right")
        } else {
            Label("Clear ahead", systemImage: "checkmark")
        }
    }

    private func inlineTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}
