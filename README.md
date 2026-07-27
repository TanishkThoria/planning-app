# Chronos

[![CI](https://github.com/tanishkthoria/planning-app/actions/workflows/ci.yml/badge.svg)](https://github.com/tanishkthoria/planning-app/actions/workflows/ci.yml)

> **Proprietary — © 2026 Tanishk Thoria. All rights reserved.** The source is
> publicly visible for CI and reference only; no use, copying, or
> redistribution is permitted without written permission. See [LICENSE](LICENSE).

A minimalist, dark-mode timeblocking planner for iOS and macOS that uses **Apple Calendar and Apple Reminders as its only data store** — no separate database, no import/export, no sync conflicts. Every time block you draw is a real calendar event; every task is a real reminder. Edit anything in the Apple apps (or via Siri, or on another device) and it shows up in Chronos instantly, and vice-versa.

Built for power users and serious planners: fast, keyboard-driven, and designed around the daily ritual of turning a task list into a realistic schedule.

**Chronos 2.0 — a Personal Growth Operating System.** On top of the planner, Chronos now helps you close the gap between who you are and who you want to become: identity **pillars** that fill with real **evidence** of who you're becoming, a **Future Self** with 1/5/10-year visions, daily **modes** and a **minimum-viable day**, an **action ratio** that catches planning-as-procrastination, a **recovery** score that rewards returning over never falling behind, a personal **operating manual**, an **aspiration vault**, and an identity-aware coach. See [`docs/GROWTH_OS.md`](docs/GROWTH_OS.md) and [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Navigation

- **macOS / iPad** — a sidebar with Today, Calendar, Tasks, Matrix, Insights, Settings, a mini-month for jumping around, and per-calendar/list visibility toggles. Full menu-bar keyboard control.
- **iPhone** — five primary tabs (Today, Calendar, Tasks, Matrix, Insights) with nothing hidden behind an overflow menu; Settings opens from a gear on the home screen. The **Calendar** tab carries a segmented **Day / Week / Agenda** switch so all three planner modes live in one place. Pinch the day timeline to zoom.

The app ships a minimal, memorable app icon — a single indigo time block crossed by the red "now" line on a faint hour grid — with dedicated dark and tinted variants for iOS icon theming.

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

### Today
A focused "finish by end of day" command center, separate from the timeline: overdue at the top, then what's still ahead today (upcoming blocks + tasks due today), then what's already done. One tap to start a focus timer on any upcoming block, open morning planning, or run the end-of-day review.

### Morning planning & end-of-day review
- **Plan Today** (⇧⌘M) — a guided start-of-day ritual: brain-dump what you want to accomplish, tag rough effort, then let Chronos lay out the whole day around your routines and focus window.
- **Review Day** (⇧⌘R) — walk each finished, task-linked block and answer *did you do it / needs more time / reschedule / skip*. Answers write back to Reminders and reschedule what slipped into your next free slot. A banner on the Day view nudges you when blocks are waiting to be reviewed.

### Focus timer
A Pomodoro / stopwatch that floats app-wide as a pill and survives navigation. Start it from any block or task ("Focus on This"), and completed focus time is logged for the Insights stats. Configurable focus/break lengths, pause/resume/skip.

### Notifications & check-ins
Opt-in local notifications fire when a task-linked block ends ("How did it go?"); opening the app surfaces the review flow so nothing slips silently. Toggle in Settings → Notifications.

### Agenda
A rolling two-week list view — each day's all-day events, time blocks, and due tasks interleaved chronologically, with overdue tasks pinned to the top of today. Complete tasks inline, jump into any day's planner.

### Eisenhower matrix
Live urgent/important quadrants over your Reminders (urgency from due dates, importance from priority). Drag a task to a different quadrant and its real due date and priority are rewritten in Apple Reminders.

### Granular tasks, effort & chunking
- **Estimates** from 5 minutes to 12 hours, with a fine stepper and quick presets.
- **Effort tags** — mark a task *Deep* or *Shallow*; deep work is steered into your focus window by the scheduler, and the split shows up in Insights.
- **Chunking** — give a big project a session length (e.g. 90 min) and Chronos splits it into multiple sessions, spreading them across days as earlier days fill up.
- **List control** — move any task or subtask between Reminders lists from the editor.

### Subtasks
Break any reminder into subtasks (EventKit doesn't expose the Reminders app's native subtasks, so Chronos subtasks are real reminders carrying a `[sub:<parent-id>]` link token — they sync everywhere). Subtasks nest under their parent in the task list, show x/y progress, and are individually draggable onto the timeline. Plan My Day schedules the subtasks rather than the parent umbrella. Deleting a parent cascades to its subtasks.

### Week auto-planning
**Plan My Week** (⇧⌘W) distributes your open tasks and chunked-project sessions across the visible week, filling each day around existing blocks and protected routines, and shows the whole proposed week before you commit.

### The Coach
The Insights screen ends with prioritized, plain-language suggestions derived entirely on-device from your real stats and calibration profile — plan adherence, on-time rate, overdue backlog, deep-work placement, over-packed days, streaks. Fully offline; the engine is structured so a richer language model could be layered on later without changing the app.

### Calibration — the personal assistant layer
On first launch (and anytime from Settings → Recalibrate or the Plan menu), Chronos interviews you:

- **Sleep** — wake time and bedtime become the hard bounds of every plan.
- **Meals** — protected windows the scheduler won't book over; optionally auto-blocked onto the calendar by Plan My Day.
- **Standing routines** — gym, commute, anything recurring, with per-weekday schedules.
- **Focus period** — morning/afternoon/evening; Plan My Day steers your high-priority tasks into it.
- **Flexibility** — Strict / Balanced / Flexible controls whether routines are untouchable, how much breathing room goes between blocks, and whether scheduling may spill beyond work hours into the full waking day.

The profile lives on-device (UserDefaults) and every "next free slot" button, quick-add placement, and Plan My Day run respects it.

### Insights
A deep weekly review: headline tiles (timeblocked, focused, done, streak), three behavioural rings (task completion, on-time rate, plan adherence), a planned-vs-focused day strip, deep/shallow split, time by calendar, the Coach's suggestions, and texture stats (average/longest block, task-linked ratio, focus sessions, overdue backlog).

### Power-user details
- Full menu-bar + keyboard control on macOS: ⌘K quick add, ⌘N new block, ⇧⌘N new task, ⌘1–4 view switching, ⌘T today, ⌘[ / ⌘] navigation, ⇧⌘P plan my day.
- Per-calendar and per-list visibility toggles, mini-month navigation, timeline zoom.
- Configurable working hours, snap increment, default durations, default calendar/list, six accent colors, dim-past-blocks.
- Elegant pure-dark theme throughout, tuned for long planning sessions.

## Requirements

- **Xcode 16+** (the project uses filesystem-synchronized groups)
- **iOS 17+ / macOS 14+** (EventKit full-access APIs)

## Continuous integration

Every push runs [`.github/workflows/ci.yml`](.github/workflows/ci.yml) on free
GitHub-hosted runners (standard runners are free on public repos):

- **Build · iOS Simulator** and **Build · macOS** — compile the full app on the
  real Apple SDKs (`xcodebuild`, code signing disabled, no secrets required).
- **Core logic tests · Linux** — `swift test` runs the platform-agnostic
  `ChronosCore` package (date math today; more as logic is decoupled from
  SwiftUI) inside the official `swift` container.

Locally, the pure logic can be tested without Xcode:

```bash
./scripts/setup-swift.sh   # one-time, Linux only
swift test
```

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
