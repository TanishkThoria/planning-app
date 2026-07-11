# Chronos

A minimalist, dark-mode timeblocking planner for iOS and macOS that uses **Apple Calendar and Apple Reminders as its only data store** — no separate database, no import/export, no sync conflicts. Every time block you draw is a real calendar event; every task is a real reminder. Edit anything in the Apple apps (or via Siri, or on another device) and it shows up in Chronos instantly, and vice-versa.

Built for power users and serious planners: fast, keyboard-driven, and designed around the daily ritual of turning a task list into a realistic schedule.

## Features

### Timeblocking
- **Day planner** — a zoomable 24-hour timeline with a live "now" line, all-day event chips, and an *Up Next* status strip.
- **Drag to move, drag to resize** — blocks snap to your configured increment (5/10/15/30 min) with live time feedback while dragging.
- **Double-click / double-tap an empty slot** to create a block right there.
- **Backlog rail** — the day's unscheduled tasks sit beside the timeline; drag one onto the canvas to timeblock it, or hit the ⚡ button to drop it into the next free slot.
- **Week planner** — seven columns, same interactions, tap a day header to dive in.
- **Overlap handling** — conflicting events split into side-by-side lanes, Apple Calendar style.
- **Recurring events & alerts** — repeat rules (daily/weekdays/weekly/biweekly/monthly/yearly) and relative alarms, with "this occurrence vs. future occurrences" handling on edit and delete. Custom rules created in Apple Calendar are preserved.

### Task ↔ calendar bridge (the core idea)
- **Schedule any reminder as a time block.** The event is linked back to the reminder (via a `chronos://task/…` URL on the event, so the link syncs through iCloud like everything else).
- **Complete the task from the block** — linked blocks show a checkbox; ticking it completes the underlying Apple Reminder.
- **Time estimates on tasks** (`~30m`) are stored as a `[est:30m]` token in the reminder's notes, so they round-trip through Apple Reminders too.

### Plan My Day
One command (⇧⌘P) that takes your overdue + due-today tasks, fits them into the free gaps of your working hours by priority and due date, shows you the proposed schedule, and creates the linked blocks when you confirm — with configurable breathing room between blocks.

### Quick Add (⌘K)
Natural-language capture with a live interpretation preview:

| You type | You get |
|---|---|
| `Deep work 9-11am` | 2-hour block today at 9:00 |
| `Standup tmr 9:15 15m` | 15-minute block tomorrow |
| `Gym next fri 6pm 1h` | 1-hour block next Friday |
| `Review PRD` | block in your next free slot |
| `todo Buy milk tomorrow !!` | medium-priority reminder due tomorrow |
| `t Send invoice fri 5pm ~30m` | reminder with due time + 30m estimate |

### Tasks
Full Reminders client: Today / Upcoming / Anytime / Done filters, search, natural-language quick entry, priorities, due dates with optional times, estimates, list management, and one-tap "schedule next free slot today/tomorrow".

### Insights
Weekly review — hours timeblocked, blocks created, tasks completed, completion rate for tasks due this week, hours per day, time by calendar, average/longest block, and how much of your calendar was task-linked.

### Power-user details
- Full menu-bar + keyboard control on macOS: ⌘K quick add, ⌘N new block, ⇧⌘N new task, ⌘1–4 view switching, ⌘T today, ⌘[ / ⌘] navigation, ⇧⌘P plan my day.
- Per-calendar and per-list visibility toggles, mini-month navigation, timeline zoom.
- Configurable working hours, snap increment, default durations, default calendar/list, six accent colors, dim-past-blocks.
- Elegant pure-dark theme throughout, tuned for long planning sessions.

## Requirements

- **Xcode 16+** (the project uses filesystem-synchronized groups)
- **iOS 17+ / macOS 14+** (EventKit full-access APIs)

## Building

1. Open `Chronos.xcodeproj` in Xcode.
2. Select your development team under *Signing & Capabilities* (the project ships with automatic signing and no team).
3. Pick the *Chronos* scheme and an iOS or macOS destination, then run.
4. On first launch, grant Calendar and Reminders access — Chronos is inert without it (there's nothing else to show; the Apple stores *are* the database).

The macOS build is sandboxed with the calendars/reminders entitlements (`Chronos.entitlements`); the iOS build needs only the usage descriptions, which are generated from build settings.

## Architecture

```
Chronos/
├── App/            ChronosApp (scenes, macOS commands), AppModel (UI state), Theme
├── Models/         TimeBlock, TaskItem, CalendarInfo, drafts, recurrence/alarm options
├── Services/
│   ├── EventKitService   the single source of truth — snapshots EKEvents/EKReminders
│   │                     for the UI, caches live objects for mutation, refreshes on
│   │                     EKEventStoreChanged (two-way sync for free)
│   ├── AutoScheduler     pure gap-filling engine behind Plan My Day / next-free-slot
│   └── QuickAddParser    pure natural-language parser behind ⌘K and quick entry
├── Utilities/      date helpers, overlap-lane layout
└── Views/          RootView (split view / tabs), Sidebar, Timeline (day/week canvas,
                    draggable block cards), Tasks, Editors, QuickAdd, PlanDay,
                    Insights, Settings
```

Design decisions worth knowing:

- **Value-type snapshots, cached live objects.** Views render immutable `TimeBlock`/`TaskItem` structs; `EventKitService` keeps the matching `EKEvent`/`EKReminder` instances keyed by occurrence id so edits hit the exact occurrence (recurring events included).
- **No hidden state.** Everything Chronos writes is visible and editable in Apple's own apps; deleting Chronos loses nothing.
- **Pure logic where it counts.** The scheduler, parser, and lane-layout engine are dependency-free functions, easy to test and reason about.
