# Chronos 2.0 — the Personal Growth Operating System

> **The pivot.** Chronos began as a timeblocking planner. Version 2.0 reframes
> it around a bigger thesis: **help users close the gap between who they are and
> who they want to become.** The planner is still the engine — but the point is
> no longer "plan your day," it's *identity alignment*. This document maps the
> 12-phase evolution plan to exactly what shipped, and where to find it.

## New product thesis

- **Old:** "Chronos helps you plan your days."
- **New:** "Chronos helps you close the gap between who you are and who you want
  to become."

The fundamental problem was never time management — it's identity alignment.
People have ambitions and ideal selves but lack systems, feedback loops,
awareness, and *evidence* of progress. Chronos 2.0 is the bridge, built on one
core belief the whole layer repeats out loud:

> **You don't become an identity through goals. You become it through evidence.
> And the metric is never worth — only momentum.**

Everything is on-device, private, and rides the existing backup + Chronos+
iCloud sync (it all lives in the `chronos.lifeData` blob).

---

## Phase-by-phase: plan → implementation

### Phase 1 — Identity architecture
**Shipped.** `IdentityPillar` (Health, Career, Learning, Relationships,
Creativity, Discipline, Financial, Style — 8 seedable presets, fully editable),
`IdentityEvidence` (source: habit/task/focus/milestone/journal/reflection/manual,
with a 1–3 strength), and `EvidenceEngine` — a pure, on-device engine that
computes a live per-pillar **"becoming" reading** (0–100%) plus a trend
(fresh/rising/steady/quiet) from the real things the user already did. Auto-evidence
is computed live and never stored, so the number can't be inflated. The
`FutureSelfView` screen shows the pillars, an evidence feed per pillar, and an
overall "you are becoming" bar — captioned explicitly as *momentum, not worth*.
- `Chronos/Models/Identity.swift`, `Chronos/Services/EvidenceEngine.swift`,
  `Chronos/Views/Grow/FutureSelfView.swift`, `IdentityPillarEditorView.swift`.

### Phase 2 — Replace motivation with momentum
**Shipped.** `DailyMode` (Build / Maintain / Recover) sets the day's tone, and
the **Minimum Viable Day** (`DayIntent` + must-wins/bonuses) asks "what's the
minimum version of today that keeps you moving?" — naming the floor, not the
ceiling, so a hard day still counts. A compact, tappable intent card on Today
shows the mode and must-win progress and celebrates a cleared floor.
- `Chronos/Models/GrowthOS.swift`, `Chronos/Views/Today/MinimumViableDayView.swift`,
  intent card in `TodayView.swift`.

### Phase 3 — Destroy planning addiction
**Shipped.** `PlanningMeter` samples how long the planning surfaces stay open;
`ActionRatioEngine` compares that to focus (execution) minutes and to repeated
rescheduling (task punts). When planning tilts too high or work keeps slipping,
an Insights card says **"you've designed enough — time to build"** and offers a
one-tap focus block. The same signal feeds the coach.
- `Chronos/Services/PlanningMeter.swift`, action-ratio card in `InsightsView.swift`,
  meter hooks in `RootView.swift` planning sheets.

### Phase 4 — Future self visualization
**Shipped.** `FutureSelf` carries a name, summary, attributes, and **1/5/10-year
visions** plus "what that person does today." The Future Self screen renders the
vision timeline and today's identity actions; the editor captures it all.
- `FutureSelf`/`VisionHorizon` in `Identity.swift`, `FutureSelfEditorView.swift`.

### Phase 5 — The reflection engine
**Shipped.** The evening ritual now reframes wins as *"where did you act like
your future self?"* and improvements as *"where did you drift?"*, and adds an
**evidence composer** that logs a proof straight to a pillar (source:
`reflection`) — turning reflection into evidence.
- `MorningRitualView` / `EveningRitualView` in `Chronos/Views/Grow/RitualsView.swift`.

### Phase 6 — Anti-perfectionism / recovery score
**Shipped.** `RecoveryEngine` measures **how fast you return after a gap**, not
whether you never fell behind. It surfaces comebacks and softens gaps
("consistency is returning"), shown contextually in Insights and folded into the
coach's reframes.
- `Chronos/Services/RecoveryEngine.swift`, recovery card in `InsightsView.swift`.

### Phase 7 — The personal operating manual
**Shipped.** "My Manual" — a living document of the user's **principles, rules,
patterns, and solutions**. The coach reads it to give advice that fits the
person (e.g. surfacing a self-noted pattern when work is stuck).
- `ManualNote`/`ManualCategory` in `GrowthOS.swift`, `Chronos/Views/Grow/MyManualView.swift`.

### Phase 8 — Improve the AI coach (reactive → reflective)
**Shipped.** `GrowthCoach` — the identity half of the coach. It nudges quiet
pillars, catches over-planning, reframes a miss ("you kept this 24 of 28 days —
one miss won't undo it"), celebrates returns, and surfaces the user's own noted
patterns. It merges into the briefing suggestions, and the on-device AI chat's
grounding now includes the future-self definition, live pillar readings,
self-noted patterns/rules, and the planning-vs-doing ratio — so replies fit the
person, framed as evidence, never worth.
- `Chronos/Services/GrowthCoach.swift`, merge in `BriefingContent.swift`,
  grounding in `CoachView.swift`.

### Phase 9 — The "Day Zero" problem
**Shipped.** Returning after 3+ days away opens a no-guilt `WelcomeBackView` —
level, best streak, and pillars are all still here, and the only ask is the
smallest next step ("start with 10 minutes"). Detected once per launch, never
during onboarding/calibration/tour.
- `Chronos/Views/Today/WelcomeBackView.swift`, detection in `RootView.checkDayZero()`.

### Phase 10 — Shopping / desire management
**Shipped.** The **Aspiration Vault** saves things the user wants — but only
alongside *what version of themselves each represents* and *which pillar/goal it
depends on*, turning a distraction into a symbol of growth. Items are marked
"earned" when the evidence adds up.
- `Aspiration` in `GrowthOS.swift`, `AspirationVaultView.swift`, `AspirationEditorView.swift`.

### Phase 11 — Weekly life review + gap analysis
**Shipped.** The Weekly Review gained a **"gap this week"** card: which pillars
closed the gap (rising) vs went quiet, plus the three review questions (where did
you close it, where did you widen it, what system needs changing).
- Gap analysis in `Chronos/Views/Grow/WeeklyReviewView.swift`.

### Phase 12 — Beautifully simple
**Shipped.** A **Simple mode** (Settings → Experience) pares Today down to the
essentials — your mode, momentum, and what's left — while every power-user
surface stays one tap away. The default experience is morning (mode + minimum) →
day (execute) → evening (reflect), and everything else is depth.
- `Prefs.simpleMode`, gating in `TodayView.swift`, toggle in `SettingsView.swift`.

---

## The product philosophy, enforced in code

- **Never "you failed" — always "here's the next step."** The recovery engine,
  Day Zero screen, and coach reframes all default to the next small action.
- **Evidence, not shame.** Pillar readings are momentum over a trailing window,
  captioned as *not a measure of worth*; a quiet pillar is "the next place to put
  a small win," not a failure.
- **Return to reality, don't escape into planning.** The action ratio actively
  pushes back on planning-as-procrastination.
- **The real metric** is none of hours scheduled, tasks completed, or streaks —
  it's *"do I feel more like the person I want to become?"* The becoming bars are
  the app's answer to that question.

---

## Where it all lives

Everything new is persisted in `LifeStore` (the `chronos.lifeData` UserDefaults
blob) as optional fields, so old saved data decodes unchanged and the new layer
is automatically captured by `ChronosBackup` and mirrored by `CloudSyncService`
on Chronos+. New pure engines (`EvidenceEngine`, `PlanningMeter` /
`ActionRatioEngine`, `RecoveryEngine`, `GrowthCoach`) follow the app's existing
"pure, testable, on-device" pattern. No new servers, no new accounts, no
tracking — the growth layer is as private as the planner underneath it.
