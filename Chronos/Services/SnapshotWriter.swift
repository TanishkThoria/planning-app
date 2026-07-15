import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Bridges the app's live data into the shared App Group container that the
/// widgets read. Call `refresh(...)` whenever "today" changes — the timeline,
/// habits, or task completion — and it rebuilds a small `TodaySnapshot` and
/// pokes WidgetKit to reload.
///
/// Everything here is best-effort: if the App Group isn't configured yet
/// (before capabilities are added, or on a free signing profile) the writes
/// simply no-op and the widgets fall back to their placeholder.
enum SnapshotWriter {

    @MainActor
    static func refresh(service: EventKitService, life: LifeStore, focusLog: FocusLog? = nil, accentName: String) {
        let now = Date()
        let today = now.startOfDay

        let dayBlocks = service.blocks(on: today)
            .filter { !$0.isAllDay }
            .sorted { $0.start < $1.start }

        let current = dayBlocks.first { $0.start <= now && now < $0.end }
        let next = dayBlocks.first { $0.start > now }

        let plannedMinutes = dayBlocks.reduce(0) { $0 + $1.durationMinutes }
        let elapsedPlanned = dayBlocks.reduce(0) { acc, block in
            let end = min(block.end, now)
            guard end > block.start else { return acc }
            return acc + Int(end.timeIntervalSince(block.start) / 60)
        }

        let habits = life.activeHabits
            .filter { $0.isDue(on: today) }
            .map { habit in
                SnapshotHabit(
                    name: habit.title,
                    colorHex: habit.colorHex,
                    done: life.isDone(habit, on: today)
                )
            }

        let dueToday = service.tasks.filter { $0.isDueToday && !$0.isCompleted }.count
        let doneToday = service.tasks.filter {
            $0.isCompleted && ($0.completionDate?.isToday ?? false)
        }.count

        let momentum = MomentumEngine.score(.init(
            plannedBlocks: dayBlocks.count,
            didMorningPlan: life.entry(for: today)?.hasMorning ?? false,
            tasksCompletedToday: doneToday,
            focusMinutesToday: focusLog?.sessions(on: today).reduce(0) { $0 + $1.actualMinutes } ?? 0,
            habitsDue: habits.count,
            habitsDone: habits.filter(\.done).count,
            journaledEvening: life.entry(for: today)?.hasEvening ?? false,
            frogEaten: false
        ))

        // Match the timeline: colour blocks by category when the user has that
        // on (unless they set an explicit per-block colour).
        let colorByCategory = UserDefaults.standard.object(forKey: Prefs.colorByCategory) as? Bool ?? true
        func blockColorHex(_ block: TimeBlock) -> UInt32 {
            if colorByCategory && !block.hasColorOverride {
                return TagStore.shared.category(for: block).colorHex
            }
            return block.color.hexRGB
        }

        let snapshot = TodaySnapshot(
            generatedEpoch: now.timeIntervalSince1970,
            current: current.map { snapshotBlock($0, colorHex: blockColorHex($0)) },
            next: next.map { snapshotBlock($0, colorHex: blockColorHex($0)) },
            blockCount: dayBlocks.count,
            plannedMinutes: plannedMinutes,
            elapsedPlannedMinutes: min(elapsedPlanned, plannedMinutes),
            habits: habits,
            tasksDueToday: dueToday,
            tasksDoneToday: doneToday,
            momentum: momentum,
            accentHex: Theme.accent(named: accentName).hexRGB
        )

        SnapshotStore.write(snapshot)
        reloadWidgets()
    }

    private static func snapshotBlock(_ block: TimeBlock, colorHex: UInt32) -> SnapshotBlock {
        SnapshotBlock(
            title: block.title,
            startEpoch: block.start.timeIntervalSince1970,
            endEpoch: block.end.timeIntervalSince1970,
            colorHex: colorHex
        )
    }

    private static func reloadWidgets() {
        #if canImport(WidgetKit) && os(iOS)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

extension Color {
    /// The color's RGB packed into a 24-bit `0xRRGGBB` value, for handing off
    /// to the widget target (which can't share `Color` instances).
    var hexRGB: UInt32 {
        #if canImport(UIKit)
        let native = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        native.getRed(&r, green: &g, blue: &b, alpha: &a)
        #elseif canImport(AppKit)
        let native = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        native.getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        let r: CGFloat = 0.49, g: CGFloat = 0.55, b: CGFloat = 0.97
        #endif
        let ri = UInt32(max(0, min(255, r * 255)))
        let gi = UInt32(max(0, min(255, g * 255)))
        let bi = UInt32(max(0, min(255, b * 255)))
        return (ri << 16) | (gi << 8) | bi
    }
}
