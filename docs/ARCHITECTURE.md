# Chronos — Architecture, Features & Product Overview

> **Purpose of this document.** This is the single, complete context brief for
> Chronos: what it is, what it's trying to accomplish, how every part works, and
> where it can go next. Read this and you should understand the app well enough
> to extend it, hand it to a new engineer, pitch it, or pivot it — without
> reading the source first. It reflects the codebase as of the current branch
> (`claude/ios-macos-timeblocking-app-87vgpo`): ~135 Swift files, ~34k lines,
> plus a widget extension.
>
> **Chronos 2.0 note.** The app has evolved from a pure planner into a
> *Personal Growth Operating System* built on top of the planner. The new
> identity/evidence layer — pillars, the Future Self, daily modes, the action
> ratio, recovery, the personal manual, and the aspiration vault — is documented
> in full in [`docs/GROWTH_OS.md`](./GROWTH_OS.md). This file covers the planner
> foundation everything sits on; read both for the complete picture.

---

## 1. What Chronos is (in one breath)

Chronos is a minimalist, friendly, power-user timeblocking planner for **iOS 17+
and macOS 14+**, built natively in **SwiftUI**. Its defining architectural
choice: **it has no database of its own.** Every time block is a real event in
**Apple Calendar**; every task is a real reminder in **Apple Reminders**. Chronos
is a beautiful, intelligent lens over data you already own — so there's no
account, no server, no import/export, no sync to break. Edit anything in Apple's
own apps (or via Siri, or on another device) and it appears in Chronos instantly,
and vice-versa.

On top of that calendar/reminders substrate it layers a full productivity and
personal-development suite: automatic day/week planning, a focus timer, habits,
goals, long-term projects, routines/rituals, journaling, a momentum score with
achievements and challenges, deep statistics, an on-device AI coach, school
(LMS) deadline import, and an optional social layer — all while keeping the
"delete the app and lose nothing" guarantee intact.

---

## 2. What it hopes to accomplish

**The 2.0 thesis.** Chronos helps users **close the gap between who they are and
who they want to become.** The fundamental problem was never time management —
it's identity alignment. People have ambitions and ideal selves but lack
systems, feedback loops, awareness, and *evidence* of progress. Chronos is the
bridge, on the belief that you don't become an identity through goals — you
become it through evidence, measured as momentum, never as worth. (See
[`docs/GROWTH_OS.md`](./GROWTH_OS.md) for the full growth layer.)

**The planner thesis it's built on.** Most people don't fail to be productive
for lack of a to-do list — they fail at the translation step: turning a list of
intentions into a *realistic plan for a real day* and then actually following it.
Chronos is built around that daily ritual. It wants to move a user from
*reacting* to their day to *designing* it, and to make the design effortless
enough that they'll do it every morning.

**Design values, in priority order:**

1. **Own nothing, respect everything.** The user's data stays in Apple's stores.
   Chronos never becomes a silo you're locked into. This is both a privacy
   stance and a trust stance.
2. **Approachable on the surface, powerful underneath.** The most recent product
   direction (a deliberate colorful redesign) makes the app look like a simple,
   friendly consumer app, while every power-user capability — keyboard control,
   auto-scheduling, chunking, calibration — stays one layer down.
3. **Honesty in gamification.** The momentum score, streaks, and achievements are
   *derived from real behavior*, never manually checked in, and only ratchet up
   within a day. The app rewards genuinely planning, doing, focusing, and
   reflecting — it can't be gamed by tapping a button.
4. **Private by default.** No servers, no analytics, no tracking, no ads. The AI
   coach runs on-device. Even the optional social layer runs on the user's own
   private iCloud.

**Who it's for.** Busy students (the LMS integration is a direct bet on this),
professionals and "serious planners" who live in their calendar, and anyone who
wants structure without a heavy new system to learn. It scales from "I just want
to see today" to "auto-plan my whole week around my sleep, meals, and standing
commitments."

**The business shape.** The app ships **free** with everything above working on a
free Apple Developer account. A paid tier, **Chronos+**, is fully built but
dormant, lighting up Apple-capability-gated features (iCloud sync, friends,
leaderboards, live widgets) when the entitlements are present. See §16.

---

## 3. Architecture at a glance

```
┌──────────────────────────────────────────────────────────────────────┐
│  Apple Calendar (EKEvent)          Apple Reminders (EKReminder)        │
│  = time blocks                     = tasks / subtasks / assignments    │
│           ▲  two-way sync (EKEventStoreChanged)  ▲                     │
└───────────┼──────────────────────────────────────┼────────────────────┘
            │                                       │
     ┌──────┴───────────────────────────────────────┴──────┐
     │  EventKitService  (the single source of truth)       │
     │  • value-type snapshots for the UI (TimeBlock/Task)  │
     │  • cached live EK objects for mutation               │
     │  • metadata smuggled into notes/URL fields           │
     └──────────────────────────┬───────────────────────────┘
                                │  @EnvironmentObject
     ┌──────────────────────────┴───────────────────────────┐
     │  SwiftUI view tree (RootView → screens → sheets)      │
     └──┬───────────────┬───────────────┬───────────────┬────┘
        │               │               │               │
  Pure engines    Local stores    Gamification     Platform
  (stateless)     (UserDefaults    (derived)        integration
  AutoScheduler   JSON, on-device) MomentumStore    Widgets / App Group
  QuickAddParser  LifeStore        AchievementStore Live Activities
  StatsEngine     ProfileStore     ChallengeStore   AppIntents / Siri
  BlockLayout     RoutineStore     FocusLog         Notifications (local)
  DayLoad         TagStore         WrappedEngine    On-device AI (Foundation
  PlannerBrief    (all reload on   EventOutcomeStore  Models)
  Coach (rules)    iCloud pull)                     RoutineSpeaker (TTS)
                                                    ─────────────────────
                                            Chronos+ (gated, dormant):
                                            CloudSyncService (CloudKit)
                                            SocialService (friends/duels/
                                              leaderboards, Game Center)
                                            CloudKeyValueBackup (iCloud KV)
```

**Tech stack.** Pure SwiftUI (multiplatform, no UIKit/AppKit except tiny
platform shims). EventKit for calendar/reminders. `@AppStorage` / `UserDefaults`
for preferences and Chronos-only data. Combine `ObservableObject`s for state.
Apple **FoundationModels** for the optional on-device LLM. CloudKit + GameKit +
App Groups for the dormant paid tier. No third-party dependencies.

**Two build systems.** The real app is an **Xcode project**
(`Chronos.xcodeproj`) built on macOS. A tiny **Swift Package** (`Package.swift`,
target `ChronosCore`) exposes only the platform-agnostic logic (today just
`Utilities/DateUtils.swift`) so it can be unit-tested on Linux in CI without the
Apple SDKs. Xcode ignores the package file.

**Three CI jobs** (`.github/workflows/ci.yml`, free GitHub runners): Build ·
macOS, Build · iOS Simulator (both compile the full app with signing disabled),
and Core logic tests · Linux (`swift test` on `ChronosCore`).

---

## 4. The core data model & the EventKit bridge

This is the heart of the app; understand this section and the rest follows.

### 4.1 The "notes/URL as sidecar database" trick

Chronos needs to store metadata Apple's stores have no field for (a block's
custom color, whether Chronos created it, a task's time estimate, subtask links).
Rather than a separate database — which would break the "no silo" guarantee and
wouldn't sync — Chronos **smuggles bracket-tokens into the notes field** and uses
the **event URL field** for task links. Because notes and URLs sync through iCloud
like everything else, all Chronos metadata round-trips across devices and even
survives edits in Apple's own apps for free.

- **Block tokens** (`BlockMetadata`, in `TimeBlock.swift`): `[color:RRGGBB]` and
  the origin marker `[chronos:tb]`. `encode`/`strippingTokens` are the codec pair
  (tokens are stripped before the notes are shown to the user).
- **Task tokens** (`TaskMetadata`, in `TaskItem.swift`): `[est:Nm]` (estimate),
  `[chunk:Nm]` (preferred session length), `[energy:deep|shallow]`,
  `[sub:<parent-id>]` (subtask link), `[punt:N]` (times rescheduled).
- **Task↔block link**: the event's `url` is set to `chronos://task/<id>`. On
  snapshot, a block with that URL scheme yields `linkedTaskID`. Ticking a linked
  block's checkbox completes the underlying reminder.

### 4.2 Value-type snapshots, cached live objects

`EventKitService` (`@MainActor final class … ObservableObject`) is the single
data hub. The pattern (stated in its own header comment):

- Views render **immutable value snapshots**: `TimeBlock`, `TaskItem`,
  `CalendarInfo` structs — cheap to diff, safe to pass around.
- The service separately keeps the **mutable EventKit objects** in caches
  (`eventCache: [String: EKEvent]` keyed by *occurrence id*, `reminderCache:
  [String: EKReminder]` keyed by reminder id) so edits hit the exact object —
  including the exact *occurrence* of a recurring event.
- **Occurrence vs series identity**: `TimeBlock.id` is an occurrence id
  (`"<eventID>#<startTimeInterval>"`) so repeating occurrences are individually
  addressable; `TimeBlock.eventID` is the series id, used to key category
  overrides and linked-block lookups.

### 4.3 Two-way sync for free

`init` subscribes to `.EKEventStoreChanged`. Any change made in Apple Calendar,
Apple Reminders, Siri, or another device fires that notification → `refresh()` →
new snapshots → the UI updates. That's the inbound half of two-way sync with no
sync engine to maintain. The outbound half is ordinary EventKit writes.

**Loading window.** The service holds events for a rolling window (today − 45d …
today + 90d); `ensureWindow(around:)` widens it as the user navigates near an
edge. Reminders load *incomplete* items plus *completed in the last 14 days*.
Special queries (`blocks(from:to:)`) escape the window for the Time Report and
Year-in-Review.

### 4.4 The public API surface (what views call)

- **Blocks:** `createBlock`, `updateBlock(id:with:span:)`, `moveBlock` (drag,
  keep duration), `resizeBlock`, `deleteBlock(span:)`, `duplicateBlock`,
  `startBlockNow`, `editorContext(for:)`.
- **Tasks:** `createTask`, `updateTask`, `toggleTaskCompletion`, `deleteTask`
  (cascades to subtasks), `rollOverdueToToday` (Sunsama-style carry-over),
  `bumpPuntCount`, `scheduleTask(_:at:minutes:)` (creates a linked block).
- **Subtasks:** `subtasks(of:)`, `createSubtask` (real reminders with a `[sub:]`
  token, because EventKit doesn't expose the Reminders app's native subtasks).
- **Routines/templates/LMS:** `scheduleRoutine`, `applyTemplate`,
  `createAssignmentReminder`, `setHiddenEventIDs`, `subscribedCalendars`.

### 4.5 Mapping to Calendar/Reminders (the careful parts)

- **Recurrence & alarms are only rewritten when the user actually changed them.**
  Editors snapshot the "before" state (`originalRecurrence`, `originalAlarm`, …)
  and diff against it on save, so exotic rules authored in Apple Calendar (e.g.
  "3rd Tuesday") survive a Chronos round-trip untouched. `RecurrenceOption` maps
  the common rules (daily / weekdays / weekly / biweekly / monthly / yearly) and
  reverse-maps anything else to a display-only `.custom`.
- **Date-only vs timed due dates**: represented by whether the reminder's
  `dueDateComponents` include hour/minute.
- **Travel buffers**: because EventKit has no travel-time field, a "Travel to X"
  event marked `.busy` is created *separately* before the block.
- **Overlap layout** (`BlockLayout.place`): Apple-Calendar-style column packing —
  sweep blocks in start order into overlap *clusters*, assign each the lowest free
  column, and give every block in a cluster the cluster's peak width so conflicts
  tile side-by-side. This is cached in view state so it doesn't recompute on every
  drag frame.

### 4.6 Categories & auto-classification (`TagStore`)

Every block/task is auto-tagged with one of 14 `ActivityCategory` values (work,
school, study, fitness, meal, rest, …). Resolution order in `TagStore.resolve`:

1. **Explicit user override** (keyed by *series* eventID for blocks, reminder id
   for tasks — so tagging one occurrence tags the whole series, and it works even
   for read-only external calendars because nothing is written back).
2. **Learned guess** — a word→category vote table taught whenever the user sets a
   category by hand (needs 2 votes to be trusted; votes capped at 50).
3. **Keyword heuristic** (`ActivityCategory.guess`) — an ordered cascade, specific
   phrases first ("dinner with" → social before "dinner" → meal).
4. Fallback `.other`.

A non-`@Published` `resolveCache` memoizes results (keyed by id + title) so the
keyword scan doesn't re-run for every visible block on every render — important
on the scroll/drag hot path.

### 4.7 Natural-language capture (`QuickAddParser`)

A pure, stateless parser behind ⌘K Quick Add and every quick-entry field. It runs
a destructive pipeline (each matcher removes what it matched; the remainder is the
title) recognizing: kind prefixes (`todo`/`task`/`t`/`-`), priority (`!`/`!!`/
`!!!`), recurrence (`every weekday`, `biweekly`, …), list tags (`#School`),
estimates (`~30m`), day words (`tmr`, `next fri`, `in 3 days`, `jan 5`, `9/5`),
time ranges (`9-11am`), single times (`3pm`, `at 15:30`), durations (`45m`,
`1.5h`), and trailing locations (`@Cafe`, `at <place>`). Blocks get a live
interpretation preview as you type.

---

## 5. App shell, navigation & state

- **`ChronosApp`** injects seven root `@StateObject`s as environment objects:
  `AppModel` (UI state), `EventKitService` (data), `ProfileStore` (calibration),
  `FocusLog`, `FocusTimerController`, `NotificationService`, `LifeStore`.
  Singletons (`.shared`) handle the rest (TagStore, RoutineStore, MomentumStore,
  AchievementStore, ChallengeStore, SocialService, CloudSyncService, …).
- **`AppModel`** holds the current screen, selected date, planner mode, and a
  large set of `@Published` boolean sheet flags — sheet-driven navigation is the
  app's primary modal pattern. It also owns "eat the frog" (today's one avoided
  task, auto-reset daily) and per-calendar/list visibility sets, and it routes
  `chronos://` deep links from widgets/Live Activities/Shortcuts.
- **`RootView`** is the wiring hub. It gates on permission, chooses the layout
  (split view on macOS/iPad, tab bar on iPhone), hosts *all* sheets, and — most
  importantly — contains the lifecycle glue: it reschedules notifications on data
  change, refreshes the widget snapshot, syncs Live Activities, publishes social
  presence, drives LMS auto-sync, runs `checkGamification()` after every relevant
  change, and wires `timer.onSessionComplete` to log focus time (and auto-complete
  a tagged habit / auto-log a tagged project's minutes).
- **Screens**: Today, Calendar (Day/Week/Month/Agenda), Tasks (with an Eisenhower
  Matrix mode), Grow, Insights, Coach, Settings. On iPhone the five primary tabs
  are Today/Calendar/Tasks/Grow/Insights; Coach is reached from Today and the
  command bar; Settings is a gear. Nothing hides behind a "More" overflow.
- **Full keyboard control on macOS**: ⌘K command bar, ⇧⌘K quick add, ⌘N/⇧⌘N new
  block/task, ⌘1–6 screens, ⌘T today, ⌘[ / ⌘] navigation, and a whole **Plan**
  menu (⇧⌘M plan today, ⇧⌘P plan my day, ⇧⌘W plan my week, ⇧⌘R review, ⌥⌘R reflow,
  ⇧⌘J journal, …).

---

## 6. The design system

- **One adaptive palette** (`Theme`): every surface, hairline, and text tone is
  a `Theme.dynamic(light:dark:)` color, so the whole app is light/dark aware from
  one place. Backgrounds mirror Apple's grouped-background convention (soft gray
  by day, true black by night; cards float above).
- **Seven user-selectable accents** (Apple system tints). `Theme.accentColor`
  resolves the user's pick live; the root re-keys on the accent so the entire tree
  recolors instantly when it changes.
- **SF Pro Rounded everywhere.** `ChronosAppearance` applies `.fontDesign(.rounded)`
  app-wide (monospaced digits keep their design). This is the single biggest
  "friendly" lever.
- **`IconChip`** is the signature accent: a bold white SF Symbol on a colored
  gradient rounded square, used on card headers, heroes, and nav/entry rows.
  Functional glyphs (chevrons, checkboxes, search, warnings, toggles)
  intentionally stay plain glyphs — that contrast is the style.
- **Metrics**: generous spacing, big soft corner radius (26pt house radius, 16pt
  for chips), `.panel()` modifier for the standard card treatment. `Theme.onAccent
  = white` gives crisp text on every colored button in both themes.
- Shared components (`SharedComponents.swift`): `SectionHeader`, `EmptyStateView`
  (with optional action button), `ChronosPrimaryButton`/`ChronosSecondaryButton`,
  `HeaderIconButton`, `PressableButtonStyle`, `IconChip`, and `ChipPalette` (a
  stable djb2-hash color picker — deliberately not Swift's per-launch-randomized
  `hashValue`).

---

## 7. Timeblocking & the calendar

- **Day planner**: a zoomable (pinch) 24-hour timeline with a live red "now" line,
  all-day event chips, an "Up Next" strip, and a **backlog rail** of the day's
  unscheduled tasks beside it — drag one onto the canvas to timeblock it, or hit ⚡
  to drop it into the next free slot.
- **Interactions**: drag to move, drag an edge to resize (snapping to the
  configured 5/10/15/30-min increment with live time feedback), double-tap an
  empty slot to create a block there.
- **Week planner**: seven columns, same interactions.
- **Month & Agenda**: a month grid, and a rolling two-week agenda that interleaves
  each day's all-day events, blocks, and due tasks chronologically with overdue
  tasks pinned to today's top.
- **Overlap handling, recurrence, alarms, meeting links**: conflicting events
  split into side-by-side lanes; recurrence/alarms are edited with "this vs future
  occurrences" semantics; a one-tap **Join** button appears for blocks whose
  notes/URL/location contain a recognized meeting link (Zoom, Meet, Teams, Webex,
  and ~9 others, detected via `NSDataDetector` + a provider table).

---

## 8. Tasks & the task↔calendar bridge

Chronos is a full Apple Reminders client: Today / Upcoming / Anytime / Done
filters, search, natural-language entry, priorities, due dates (with optional
times), estimates, energy tags, and list management.

- **The bridge (the core idea)**: schedule any reminder as a linked time block;
  complete it from the block; time estimates (`~30m`) round-trip as `[est:]`
  tokens.
- **Effort & chunking**: mark a task **Deep** or **Shallow** (deep work is steered
  into your focus window by the scheduler); give a big task a **session length**
  and Chronos splits it into multiple sessions spread across days.
- **Subtasks**: nest under a parent, show x/y progress, are individually
  draggable onto the timeline, and are what Plan My Day schedules (rather than the
  umbrella parent).
- **Eisenhower Matrix**: live urgent/important quadrants over your reminders
  (urgency from due dates, importance from priority). Drag a task to a new quadrant
  and its real due date + priority are rewritten in Apple Reminders.

---

## 9. Planning & scheduling engines

All planners compose the same pure, stateless primitives in `AutoScheduler`
(a namespace of `static` functions — deterministic, testable, no hidden state).

- **`freeGaps`** finds open gaps in a day, respecting the scheduling window,
  existing blocks, and — when calibrated and not in Flexible mode — protected
  meal/routine windows. Gaps under 10 minutes are dropped.
- **`plan`** (Plan My Day): orders tasks by priority → due date, expands them into
  work units (chunking), and first-fits them into gaps. It applies **breathing
  room** between blocks (Strict 10 / Balanced 5 / Flexible 0 min) and **focus
  steering** — High-priority or Deep-energy units prefer a gap overlapping your
  focus window, with a plain first-fit fallback so placement never fails.
- **`planWeek`** (Plan My Week): fills each day in turn, carrying earlier days'
  proposals forward as synthetic busy blocks and re-inserting partially-scheduled
  chunked tasks with their remaining minutes, so sessions spread naturally as days
  fill.
- **`planDeadlines`** (Deadline work-back planner): schedules backward from due
  dates with two safety rails — never place a session past its deadline, and a
  humane per-day minute cap (2/3/4h).
- **`nextFreeSlot`**: the engine behind every "schedule in next free slot" button,
  Review's reschedule, and Reflow.

**End-to-end flows** built on these:

- **Plan My Day** — opt-in Routine / Tasks / Projects sections; creates ritual
  blocks, project work blocks, and linked task blocks on confirm; reports how many
  didn't fit.
- **Morning planning ("Plan Today")** — a guided brain-dump (each item becomes a
  due-today task with a rough energy tag) → auto-layout preview → schedule.
- **Review Day** — walk each past, task-linked block: Did it / More time /
  Reschedule / Skip. Answers write back to Reminders and reschedule what slipped.
  Past real (non-Chronos) events are assumed attended (toggleable).
- **Reflow Day** — one tap re-slots everything that slipped, reserving each new
  slot so moves don't collide.
- **`DayLoad`** — a Sunsama-style overcommit guardrail: committed minutes (sum of
  due-today task estimates) vs free minutes left in the workday; surfaces an
  "overcommitted / you have earned downtime" signal to Today, Coach, and
  Nice-to-Haves.

---

## 10. Calibration — the personalization layer (`PlannerProfile`)

On first launch (and anytime via Recalibrate), Chronos interviews the user and
stores a `PlannerProfile` (Codable JSON in UserDefaults, **on-device only**):

- **Sleep** — wake/bed minutes become the hard outer bounds of every plan.
- **Meals** — protected windows (name, start, duration, `autoBlock`) the scheduler
  won't book over.
- **Standing routines** — recurring commitments with **per-weekday** schedules.
- **Focus period** — morning / afternoon / evening; steers high-priority and deep
  work into that window.
- **Flexibility** — one dial (Strict / Balanced / Flexible) that simultaneously
  controls window width (work-hours vs full waking day), whether routines are
  untouchable, and how much breathing room goes between blocks.

Every "next free slot," quick-add placement, and Plan run respects this. The
profile reloads on iCloud pull so it stays consistent across devices.

---

## 11. Focus timer

- **Pomodoro or stopwatch**, with an app-wide **floating pill** that survives
  navigation and a tap-to-open sheet. Presets: Quick 5/5, Classic 25/5, Deep
  50/10, Flow 90/15.
- **Wall-clock derived timing** (from epoch timestamps) so the timer survives
  backgrounding and relaunch.
- **Tagging & auto-logging**: a session can be tagged with a category, habit,
  goal, or **project**. On completion the session is logged to `FocusLog`; a
  tagged habit is auto-marked done for the day; a tagged project's minutes are
  auto-banked (`life.logTime`). `FocusSession.actualMinutes` (from elapsed epoch
  time) is the value all scoring reads.
- **Soft "focus integrity"** (not a punitive score): a Forest-style sprout grows
  🌱→🌳 with progress and **wilts** 🥀 if you leave the app mid-focus, with a
  non-punitive "replant" to resume. A **Park-a-thought** field turns a stray
  distraction into an inbox task without leaving the session.
- **Live Activity / Dynamic Island**: one activity mirrors the running session;
  a second mirrors the current calendar block (self-dismissing at block end).
  Countdowns use `Text(timerInterval:)` so there's no per-second push, and flip to
  a calm "Done" rather than a frozen 0:00.

---

## 12. Grow — the personal-development suite

Owned mostly by `LifeStore` (one `LifeData` Codable struct → UserDefaults key
`chronos.lifeData`), plus `RoutineStore`. All on-device; reloads on iCloud pull;
has portable `exportJSON`/`importJSON`.

- **Goals** (`.time` / `.milestone` / `.habitLink`): weekly-hours targets computed
  live from calendar minutes, a manual milestone slider, or a linked habit's
  streak.
- **Projects** — the richest model, for long-horizon work, concrete *and* fuzzy:
  - **Milestones** (with target dates), **updates/logs** (edit/delete, optional
    progress stamping), **time tracking** (`ProjectTimeEntry`, quick +15/+30/+60
    chips, focus-timer auto-logging, "schedule a work session" into a free gap).
  - **Custom progress stamping**: a manual 0–100% slider that overrides milestone
    math (or reverts to it).
  - **Week-by-week goals** (`ProjectWeeklyGoal`, one aim per ISO week) for
    open-ended projects where the final deliverable isn't known.
  - **Time targets** (`targetHours`) drive a progress ring for effort-based work.
  - **Links** to goals, habits, and tasks; a cadence nudge ("update due") per
    daily/weekly check-in.
- **Habits**: daily / weekdays / weekly cadence, weekly targets, streaks with a
  Duolingo-style **freeze** (2/month), reminders, optional time-anchoring (place
  on the timeline), and an 11-week heatmap.
- **Routines / rituals**: ordered steps (timed or check-off), a **guided runner**
  with per-step countdown ring and optional **voice narration** (on-device TTS),
  streak tracking, and **calendar placement** (one block or step-by-step
  back-to-back events).
- **Journal**: one entry/day — morning intentions (implementation-intention
  framing), mood/energy check-ins, evening wins/improve/gratitude, a journaling
  streak, and an **"On this day"** memory resurfacing feature.
- **Morning & evening rituals**: research-cited guided flows (Gollwitzer, Clear,
  Seligman, Emmons & McCullough) that hand off to planning / habit-closing.
- **Personal growth**: **start/stop commitments** (with a days-held badge) and a
  **self-mirror** (things you like about yourself vs things you're working on,
  with a "turned it around" move that flips a trait to the like side).
- **Nice-to-haves**: a downtime/reward list; when `DayLoad` shows earned free
  time, drop one into the next free slot.
- **Templates**: save a day's blocks as a reusable template (shareable via a
  `chronos-tpl:` code) and apply it to any day.
- **Weekly Review**: a GTD-style look-back (tasks done, planned/focus minutes,
  on-plan %, per-goal progress, habit completion) that hands off to the evening
  ritual and next-week planning.

---

## 13. Gamification (honest, derived, ratcheting)

Single wiring point: `RootView.checkGamification()`, run on launch, foreground,
and after any task/habit/focus change. Everything is derived from real behavior;
first-run **baselining** suppresses a flood of retroactive celebrations.

- **Momentum** (`MomentumEngine` / `MomentumStore`): a 0–100 daily score from six
  weighted components — plan (max 20), complete (20), **focus (25, the largest)**,
  habits (20), reflect (10), frog (5). The score **only ratchets up within a day**.
  `nextBestAction` surfaces the incomplete component with the biggest remaining
  gain. **Levels** every 500 lifetime points (with titles from "Getting Started"
  to "Legendary"), a 14-day sparkline, **streaks** (with earned freezes bridging
  missed days), and an honest freeze-free `bestStreak`.
- **Achievements** (`AchievementEngine` / `AchievementStore`): 18 bronze/silver/
  gold badges across consistency, focus, reliability, habits/routines, reflection,
  and momentum — computed live, never stored, celebrated one at a time
  (bronze→gold order) via a full-screen overlay, deduped so nothing re-fires.
- **Challenges** (`ChallengeStore`): 3 daily + 3 weekly, deterministically rotated
  (djb2 seed of the day/week key, so everyone sees the same set that day; progress
  is on-device). Completing one banks bonus XP (which counts toward momentum
  levels) and fires a celebration. Includes project-minutes challenges.

---

## 14. Insights & reporting

- **`StatsEngine`** (pure, the single source for Insights and the Coach) computes,
  over any set of days: planned minutes, block count, avg/longest block, linked
  ratio; task completion / on-time / plan-adherence rates (the three behavioral
  rings); focus minutes and deep/shallow split; time-by-calendar; and a completion
  streak. Attended real (non-Chronos) events auto-count as focused time unless
  marked skipped in Day Review (`EventOutcomeStore`).
- **Statistics screen**: headline tiles, the three rings, planned-vs-focused day
  bars, deep/shallow split, time-by-calendar, budgets, projects, the achievements
  grid, and "texture" facts.
- **Time Report** ("where did my time go"): allocation by category / calendar /
  energy with previous-period deltas over a week or month.
- **Trends**: long-horizon mood / habit / goal / reflection trends.
- **Wrapped** (`WrappedEngine`): an on-device "Year in Review" — focus hours,
  scheduled hours, top calendars, best habit streak, most productive weekday,
  deep hours, a "Your Year in Projects" card, and a shareable recap.

---

## 15. The Coach & on-device AI

- **Fully local heuristic engine** (`Coach.swift`): turns real signals (stats,
  calibration profile, lifestyle signals like habit consistency and observed vs
  declared focus window, plus project nudges) into weighted, plain-language
  suggestions, each with a one-tap action (plan, reflow, recalibrate, add habit,
  open projects, …). This always works, offline, on every device.
- **`PlannerBrief`** is the shared source of truth for briefing content, so the
  non-AI briefing cards and the AI chat's fallback answers say the same thing.
- **On-device LLM** (`AssistantService`): on iOS/macOS 26 eligible hardware,
  Chronos uses Apple's **FoundationModels** `SystemLanguageModel` for a chat
  companion — **free, private, offline, no API key, no network call ever**. It's
  seeded with a warm/concise/grounded persona and a rich live context block
  (current/next block, load, pressing tasks, habits, momentum, category mix,
  friends focusing now, calibration). Where the model is unavailable it reports an
  honest reason and the Coach **degrades gracefully** to the heuristics.

> **Key point for anyone evaluating the AI story:** there is *no* server-side LLM
> anywhere in the app. The only model is Apple's on-device one; the heuristic
> engine is authoritative and the LLM is an optional enhancement.

---

## 16. School / LMS integration

A direct bet on the student audience. Rather than a fragile per-LMS API,
Chronos uses the school's **public `.ics` calendar feed**:

1. The user subscribes to their Canvas/Schoology feed via the system Calendar
   (Chronos rewrites the pasted URL to `webcal://` and gives step-by-step help).
2. Chronos reads that subscribed calendar via EventKit and **classifies** each
   entry (`LMSClassifier`): a real timed span ≥20 min or an all-day event matching
   class/exam keywords stays on the calendar as an event; everything else becomes
   a **deadline reminder**, and the original calendar entry is hidden so it doesn't
   double up.
3. Assignments become dated Reminders the general planners (Deadline work-back,
   Plan My Day) can then schedule. Auto-sync runs on a 6h staleness cadence
   (30 min on calendar change), deduped, so daily openers always get fresh
   imports.

---

## 17. Platform integration

- **Widgets** (App Group `group.app.chronos.planner`): Home-screen Today, Up Next,
  Habits, Momentum; Lock-screen Momentum gauge and Next-up inline. Fed by a
  `TodaySnapshot` written by `SnapshotWriter` on every relevant change; re-renders
  every 15 min; carries the app's accent; renders placeholders gracefully if the
  App Group isn't configured.
- **Live Activities / Dynamic Island**: focus session + current block (see §11).
- **Siri / Shortcuts** (`AppIntents`, in-process, no extension): Timeblock, Add
  Reminder, Plan Today, Eat the Frog — registered as App Shortcuts with Siri
  phrases.
- **Notifications** (all **local**, no push server): block-start heads-ups and
  end-of-block "how did it go?" check-ins (task-linked blocks only), daily
  morning/evening ritual nudges, and habit/routine reminders — all capped to stay
  under the 64-pending limit, with tap-routing back into the right flow.
- **Voice** (`RoutineSpeaker`): on-device TTS that ducks (not stops) music.
- **Interactive tour** (`TourController`): a 10-step guided tour that navigates the
  *real* app and can fire actual features, offered on first run after calibration.

---

## 18. Chronos+ — the dormant paid tier

Everything below is **fully built and compiles/ships on the free account**, but
stays **dormant** until the matching Apple capability is present. This is a
deliberate design so the free binary can never reach a CloudKit/GameKit call that
would crash without the entitlement, while still building green in CI.

Gating funnels through `PaidFeatures.isReady(_:)`:

- **`isEntitled`** = does this *build* ship the capability (a compile flag —
  `CHRONOS_PLUS` / `CHRONOS_CLOUD` / `CHRONOS_GAMECENTER` — or, for widgets, a
  runtime App-Group check). **All false on the free build.**
- **`isReady`** = entitled + user toggles on + account available.

| Capability | Apple tech | Flag | Transfer-safe | What it unlocks |
|---|---|---|---|---|
| Live Widgets | App Groups | *(runtime)* | ✅ | Home/Lock widgets update live |
| Leaderboards | Game Center | `CHRONOS_GAMECENTER` | ✅ | Global weekly-focus & momentum boards |
| iCloud Sync | CloudKit | `CHRONOS_CLOUD` | ⚠️ post-transfer | Grow/momentum/profile/etc. across devices |
| Friends | CloudKit | `CHRONOS_CLOUD` | ⚠️ post-transfer | Friend codes, presence, cheers, duels |

- **`CloudSyncService`** mirrors *only* Chronos's own UserDefaults JSON blobs
  (Grow data, momentum, profile, LMS, focus log, tags, routines) to the user's
  **private** CloudKit DB — blocks/tasks are excluded because Calendar/Reminders
  already sync them. Last-writer-wins by content hash + timestamp; posts
  `.chronosCloudDidPull` so in-memory stores reload.
- **`SocialService`** runs friends/leaderboards/duels over a server-free **public**
  CloudKit database (each user reads/writes their own presence record, looks up
  friends by a shareable `XXX-XXX` code, appends cheers/duels to per-user inbox
  lists). Local leaderboard math works without Game Center (you're always on it);
  Game Center is an optional global extra. On the free build a
  `DisabledFriendsBackend` no-ops everything and presence never publishes.
- The recommended launch is **Option C**: ship Live Widgets + Game Center now
  (both transfer cleanly), add iCloud Sync + Friends after transferring the app to
  a permanent account (no CloudKit data to migrate because there wasn't any).

---

## 19. Data portability & backup

- **`ChronosBackup`** — a portable `.chronosbackup` file (a self-describing binary
  plist) capturing *everything Chronos keeps that Apple apps don't sync* — goals,
  projects, habits, routines, journals, momentum, achievements, challenges, tags,
  and every setting — selected by key prefix (`chronos.`, `pref.`, `state.`) so
  any store added later is captured automatically. Export via `ShareLink`, import
  via file picker.
- **`CloudKeyValueBackup`** — the automatic safety net (gated on the iCloud
  entitlement): keeps a single compact snapshot in `NSUbiquitousKeyValueStore`, the
  one place data **survives delete-and-reinstall or a brand-new phone with no
  manual export**. This is specifically what stops **dev-build reinstalls in Xcode
  from wiping your saved data**. On a fresh install it silently restores
  everything. Last-writer-wins on the whole snapshot by timestamp.

---

## 20. Persistence map (where every kind of data lives)

| Data | Store | Syncs via |
|---|---|---|
| Time blocks | Apple Calendar (EKEvent) | iCloud Calendar (native) |
| Tasks, subtasks, assignments | Apple Reminders (EKReminder) | iCloud Reminders (native) |
| Chronos metadata (color, links, estimates) | notes/URL tokens on the above | rides the native sync |
| Preferences | `UserDefaults` (`pref.*`) | ChronosBackup / iCloud KV |
| Calibration profile | `UserDefaults` `chronos.plannerProfile` | Chronos+ CloudKit / KV |
| Grow data (goals/habits/projects/journal/…) | `UserDefaults` `chronos.lifeData` | Chronos+ CloudKit / KV |
| Routines | `UserDefaults` `chronos.routines.v1` | Chronos+ CloudKit / KV |
| Momentum + XP | `chronos.momentum.v1` / `.bonusxp` | Chronos+ CloudKit / KV |
| Focus sessions | `chronos.focusSessions` (cap 500) | Chronos+ CloudKit / KV |
| Tags (overrides + learned) | `chronos.tags.v1` / `.catlearn` | Chronos+ CloudKit / KV |
| LMS sources | `chronos.lms.v2` | Chronos+ CloudKit / KV |
| Achievements/challenges celebrated | `chronos.achv.*` / `chronos.challenges.*` | ChronosBackup / KV |
| Widget snapshot | App Group `UserDefaults` | — (device-local) |

Every in-memory store observes `.chronosCloudDidPull` and reloads, so a sync or
restore updates the live UI without a relaunch.

---

## 21. Privacy posture

No servers of Chronos's own. No analytics, no ads, no tracking, no accounts.
Calendar/tasks never leave Apple's frameworks; everything else stays on-device.
The AI coach is on-device. The optional social layer runs on the user's *own*
private/public iCloud, never a Chronos-operated backend. App Store privacy label:
"Data is not collected" for the free build (updated only to disclose CloudKit
friend presence when the full Chronos+ ships).

---

## 22. Repository layout

```
Chronos/
├── App/            ChronosApp (scenes, ⌘ commands), AppModel (UI state), Theme
├── Models/         TimeBlock, TaskItem, CalendarInfo, Category, Profile,
│                   Growth (projects/goals/growth items), Lifestyle (LifeStore),
│                   Routine, FocusSession, LMSSource
├── Services/       EventKitService (data hub), AutoScheduler, DayLoad,
│                   QuickAddParser, StatsEngine, WrappedEngine, Momentum,
│                   Achievements(+Store), Challenges, Coach(+Store, Inputs),
│                   AssistantService (on-device LLM), PlannerBrief, TagStore,
│                   FocusTimerController, NotificationService, LiveActivityController,
│                   RoutineSpeaker, SnapshotWriter, TourController, LMSStore,
│                   EventOutcomeStore, PaidFeatures, CloudSyncService, SocialService,
│                   ChronosBackup, CloudKeyValueBackup
├── AppIntents/     Siri/Shortcuts intents
├── Shared/         App-Group snapshot types, Live Activity attributes (in both targets)
├── Utilities/      DateUtils (+ cached formatters), BlockLayout, MeetingLink, Haptics, QRCode
└── Views/          RootView + one folder per screen/feature (Today, Calendar,
                    Tasks, Grow, Insights, Coach, Timer, Social, LMS, Onboarding,
                    Settings, Editors, Components, …)
ChronosWidget/      Widget bundle, Home/Lock widgets, Live Activity UI
docs/               This file + App Store listing, publishing guide, Chronos+ setup,
                    widgets setup, privacy policy, screenshots guide
Package.swift       ChronosCore (Linux-testable logic) — Xcode ignores this
Tests/              ChronosCoreTests
```

---

## 23. Current stage — what's shipping vs. dormant

**Shipping and working today on a free account:**

- The full planner: Day/Week/Month/Agenda, drag-to-plan, Plan My Day/Week,
  Deadline planner, Morning planning, Review, Reflow, calibration.
- Tasks, subtasks, matrix, chunking, quick add, command bar, search.
- Focus timer + Live Activity/Dynamic Island (widgets render if App Group set up).
- The entire Grow suite (goals, projects, habits, routines, journal, rituals,
  personal growth, nice-to-haves, templates, weekly review).
- Momentum, achievements, challenges, all of Insights (stats, time report, trends,
  Wrapped).
- Coach heuristics + briefing everywhere; on-device AI chat on eligible hardware.
- LMS import, Siri/Shortcuts, local notifications, voice narration, tour.
- Manual `.chronosbackup` export/import.
- The recent **colorful, friendly UI redesign** across every screen.

**Built but dormant** (needs Apple entitlements, mostly post-account-transfer):
iCloud sync, friends/presence/cheers/duels, Game Center leaderboards, automatic
iCloud key-value backup. All no-op cleanly until switched on.

**Product/go-to-market assets ready:** App Store listing copy, keywords, privacy
policy, publishing guide, Chronos+ setup guide, widgets setup, screenshots guide.
Targeting Productivity (secondary Lifestyle), 4+, Free.

---

## 24. How to build on top (extension points)

The architecture is deliberately modular. Concrete places to extend:

- **New task/block metadata** → add a token to `TaskMetadata`/`BlockMetadata`; it
  round-trips through iCloud automatically and needs no schema migration.
- **New scheduling behavior** → the planners are pure functions over `freeGaps` +
  `schedulingWindow`; add a new `plan*` variant or a new profile lever without
  touching the UI. Everything is unit-testable in isolation (and the
  platform-agnostic parts can be pulled into `ChronosCore` for Linux CI tests).
- **New Grow object type** → add a Codable struct + a collection on `LifeData`
  (make its fields optional so old blobs decode), expose CRUD on `LifeStore`, and
  it's automatically captured by ChronosBackup (prefix-based) and CloudKit sync
  (add its UserDefaults key to `mirroredKeys`).
- **New gamification signal** → add a field to `MomentumEngine.Input` /
  `AchievementEngine.Inputs` / a challenge pool entry; `checkGamification()` is the
  one call site.
- **Richer AI** → `AssistantService` already isolates the model behind a
  `reply(to:context:)` that returns `nil` on absence. Swapping in a different
  on-device model (or, if the privacy stance ever changed, a remote one) is a
  single-file change; `PlannerBrief` remains the grounded fallback.
- **New quick-add grammar** → add a matcher to the `QuickAddParser` pipeline.
- **New surface (widget/complication/intent)** → the App-Group `TodaySnapshot` and
  `AppIntents` are the seams; `SnapshotWriter` already publishes live state.
- **Turning on Chronos+** → follow `docs/CHRONOS_PLUS_SETUP.md`; flip compile flags
  + add capabilities. No app-logic changes needed — the gates are already there.

---

## 25. How it could pivot

Because the substrate (Apple Calendar/Reminders) and the engines (scheduling,
stats, gamification, AI) are cleanly separated from the presentation, Chronos can
be repointed with surprisingly little churn:

- **Student planner** — the LMS import + deadline work-back + focus timer already
  form a complete "study OS." Lean the onboarding, tabs, and marketing at students
  and the rest is largely reframing.
- **Deep-work / focus app** — promote the focus timer, integrity sprout, momentum,
  and Now mode to the center; demote the calendar to a supporting view.
- **Habit / self-improvement app** — the Grow suite (habits, routines, journal,
  personal growth, rituals, trends, Wrapped) is a standalone product; the calendar
  becomes optional scaffolding.
- **Team / body-doubling social app** — the built-but-dormant SocialService
  (presence, duels, leaderboards, cheers) is the seed of a social productivity
  product; turning on the CloudKit layer and elevating the social surfaces is the
  pivot.
- **B2B / white-label calendar intelligence** — the pure `AutoScheduler` +
  `StatsEngine` + `Coach` engines could be extracted from EventKit behind a small
  protocol and repurposed as a scheduling/insights layer over a different backend.
- **Paid-first** — the free/dormant split is already a clean freemium seam;
  Chronos+ could become the monetized tier the moment the account/entitlements are
  in place.

---

## 26. Known constraints & risks worth knowing

- **EventKit is the ceiling.** No native Reminders subtasks (worked around with
  `[sub:]` tokens), no travel-time field (worked around with a separate event),
  and some recurrence rules are display-only. Anything Apple doesn't model,
  Chronos either smuggles into notes or approximates.
- **The app is inert without Calendar + Reminders access** — by design; the Apple
  stores *are* the database. A denied permission shows a dedicated gate screen.
- **On-device AI is hardware/OS gated** (iOS/macOS 26, eligible chips). The Coach
  is fully functional without it, but the chat companion only appears on supported
  devices.
- **iCloud sync's transfer catch**: a CloudKit container is bound to the account
  that created it, so iCloud Sync + Friends are intended to be enabled *after* the
  app is transferred to a permanent account (hence the Option C launch).
- **Local-notification limits** (64 pending) mean check-ins/reminders are
  windowed and capped rather than exhaustive.
- **iCloud KV backup ceiling** (~1 MB) — the automatic snapshot falls back to
  manual file backup if a user's data ever exceeds ~900 KB.

---

*This document is intended to be kept current. When you add a store, an engine, a
gate, or a screen, update the relevant section (and the persistence map in §20) so
it remains the one place that explains the whole app.*
