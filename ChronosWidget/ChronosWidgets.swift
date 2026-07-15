import WidgetKit
import SwiftUI

// MARK: - Shared timeline plumbing

/// A single entry: the latest snapshot the app wrote, stamped with the moment
/// WidgetKit asked for it so relative times stay fresh.
struct ChronosEntry: TimelineEntry {
    var date: Date
    var snapshot: TodaySnapshot
}

/// Reads whatever the app last wrote to the App Group. Refreshes on its own
/// modest cadence too, so "up next" advances even if the app never reopens.
struct ChronosProvider: TimelineProvider {
    func placeholder(in context: Context) -> ChronosEntry {
        ChronosEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (ChronosEntry) -> Void) {
        let snap = context.isPreview ? .placeholder : (SnapshotStore.read() ?? .placeholder)
        completion(ChronosEntry(date: Date(), snapshot: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ChronosEntry>) -> Void) {
        let snapshot = SnapshotStore.read() ?? .placeholder
        let now = Date()
        // Re-render every 15 minutes so the current/next block rolls over even
        // without an app-side write.
        var entries: [ChronosEntry] = []
        for step in 0..<8 {
            let date = Calendar.current.date(byAdding: .minute, value: step * 15, to: now) ?? now
            entries.append(ChronosEntry(date: date, snapshot: snapshot))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - Palette

extension Color {
    /// Rebuild a `Color` from a `0xRRGGBB` value handed over by the app.
    init(rgb: UInt32) {
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

private enum WTheme {
    // Mirrors the app's dark palette so the widgets read as the same system:
    // true-black ground, elevated graphite cards, Apple system-blue accent.
    static let bg = Color(rgb: 0x000000)
    static let card = Color(rgb: 0x2C2C2E)
    static let primary = Color(rgb: 0xF5F5F7)
    static let secondary = Color.white.opacity(0.58)
    static let tertiary = Color.white.opacity(0.34)
    static let accent = Color(rgb: 0x0A84FF)
}

private func timeLabel(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "h:mm a"
    return f.string(from: date)
}

// MARK: - Today (summary + progress)

struct ChronosTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ChronosToday", provider: ChronosProvider()) { entry in
            ChronosTodayView(snapshot: entry.snapshot, now: entry.date)
                .containerBackground(WTheme.bg, for: .widget)
                .widgetURL(URL(string: "chronos://today"))
        }
        .configurationDisplayName("Today")
        .description("Your day at a glance — schedule, habits, and tasks.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ChronosTodayView: View {
    let snapshot: TodaySnapshot
    let now: Date
    @Environment(\.widgetFamily) private var family

    private var progress: Double {
        guard snapshot.plannedMinutes > 0 else { return 0 }
        return min(1, Double(snapshot.elapsedPlannedMinutes) / Double(snapshot.plannedMinutes))
    }

    /// The user's accent, carried in the snapshot (falls back to system blue).
    private var accent: Color { snapshot.accentHex.map(Color.init(rgb:)) ?? WTheme.accent }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text("TODAY")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(WTheme.tertiary)
                Spacer(minLength: 6)
                if let block = snapshot.current {
                    liveRow("NOW", block)
                } else if let block = snapshot.next {
                    liveRow("NEXT", block)
                } else {
                    Text("Nothing scheduled")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WTheme.secondary)
                }
                Spacer(minLength: 6)
                HStack(spacing: 10) {
                    stat("\(snapshot.tasksDoneToday)/\(snapshot.tasksDueToday + snapshot.tasksDoneToday)", "tasks")
                    stat("\(snapshot.habitsDone)/\(snapshot.habits.count)", "habits")
                }
            }
            if family != .systemSmall {
                ringColumn
            }
        }
        .padding(14)
    }

    private func liveRow(_ tag: String, _ block: SnapshotBlock) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(tag)
                .font(.system(size: 9, weight: .bold))
                .tracking(1)
                .foregroundStyle(Color(rgb: block.colorHex))
            Text(block.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WTheme.primary)
                .lineLimit(1)
            Text("\(timeLabel(block.start)) – \(timeLabel(block.end))")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WTheme.secondary)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(WTheme.primary)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(WTheme.tertiary)
        }
    }

    private var ringColumn: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(WTheme.card, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WTheme.primary)
            }
            .frame(width: 74, height: 74)
            Text("\(snapshot.blockCount) blocks")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(WTheme.tertiary)
        }
    }
}

// MARK: - Up Next (single focus)

struct ChronosUpNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ChronosUpNext", provider: ChronosProvider()) { entry in
            ChronosUpNextView(snapshot: entry.snapshot)
                .containerBackground(WTheme.bg, for: .widget)
                .widgetURL(URL(string: "chronos://today"))
        }
        .configurationDisplayName("Up Next")
        .description("The block you're in — or the one coming up.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

struct ChronosUpNextView: View {
    let snapshot: TodaySnapshot
    @Environment(\.widgetFamily) private var family

    private var shown: (tag: String, block: SnapshotBlock)? {
        if let c = snapshot.current { return ("NOW", c) }
        if let n = snapshot.next { return ("NEXT", n) }
        return nil
    }

    var body: some View {
        if family == .accessoryRectangular {
            accessory
        } else {
            full
        }
    }

    private var full: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let shown {
                Text(shown.tag)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Color(rgb: shown.block.colorHex))
                Text(shown.block.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(WTheme.primary)
                    .lineLimit(3)
                Spacer(minLength: 0)
                Label("\(timeLabel(shown.block.start)) – \(timeLabel(shown.block.end))", systemImage: "clock")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WTheme.secondary)
            } else {
                Text("Clear")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(WTheme.primary)
                Text("No more blocks today")
                    .font(.system(size: 12))
                    .foregroundStyle(WTheme.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
    }

    private var accessory: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let shown {
                Text(shown.tag + " · " + timeLabel(shown.block.start))
                    .font(.system(size: 11, weight: .semibold))
                Text(shown.block.title)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(2)
            } else {
                Text("Clear")
                    .font(.system(size: 15, weight: .bold))
                Text("No more blocks")
                    .font(.system(size: 11))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Habits

struct ChronosHabitsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ChronosHabits", provider: ChronosProvider()) { entry in
            ChronosHabitsView(snapshot: entry.snapshot)
                .containerBackground(WTheme.bg, for: .widget)
                .widgetURL(URL(string: "chronos://grow"))
        }
        .configurationDisplayName("Habits")
        .description("Today's habit rings.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ChronosHabitsView: View {
    let snapshot: TodaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("HABITS")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(WTheme.tertiary)
                Spacer()
                Text("\(snapshot.habitsDone)/\(snapshot.habits.count)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(WTheme.primary)
            }
            if snapshot.habits.isEmpty {
                Spacer()
                Text("No habits due today")
                    .font(.system(size: 12))
                    .foregroundStyle(WTheme.secondary)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(snapshot.habits.prefix(4), id: \.name) { habit in
                        HStack(spacing: 8) {
                            Image(systemName: habit.done ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(habit.done ? Color(rgb: habit.colorHex) : WTheme.tertiary)
                            Text(habit.name)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(habit.done ? WTheme.secondary : WTheme.primary)
                                .strikethrough(habit.done, color: WTheme.tertiary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
    }
}
