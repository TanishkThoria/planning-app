# Chronos — App Store listing (copy-paste ready)

Everything you paste into App Store Connect for the **1.0 free build**. It
deliberately does **not** mention Chronos+ (iCloud sync / friends / leaderboards)
because that layer is hidden in this build — advertising it would risk a 2.3.1
rejection. When you enable Chronos+ later, add those lines back (a "Chronos+"
variant is at the bottom).

Character limits are noted so nothing gets truncated.

---

## App Name  _(max 30 chars)_
Primary choice:
```
Chronos: Plan Your Day
```
If "Chronos" as a bare name is taken and you want it shorter, fallbacks:
```
Chronos — Plan & Focus
Chronos: Time Blocking
```
> The App Store **Name** must be globally unique; the on-device app name and the
> bundle ID are separate, so a longer store name is fine.

## Subtitle  _(max 30 chars)_
```
Time-block your day
```
Alternates:
```
Plan, focus, get it done
Calendar + tasks + focus
```

## Promotional Text  _(max 170 chars — editable anytime without review)_
```
Turn your to-do list into a plan you'll actually follow. Drag tasks onto a beautiful timeline, protect your focus, and build momentum — all on your own calendar.
```

---

## Description  _(max 4000 chars)_

```
Chronos turns your intentions into a plan you'll actually follow.

It's a calm, powerful day planner built directly on your Apple Calendar and Reminders — so there's no new account, no separate silo, and nothing to keep in sync. Your time blocks are real calendar events. Your tasks are real reminders. Chronos just makes them beautiful, and makes planning effortless.

TIME-BLOCK YOUR DAY
• Drag tasks onto a gorgeous, gesture-driven timeline
• Double-tap to create a block; drag to move, pull the edge to resize
• Colour-code by category and see your whole day at a glance
• Day, Week, Month, and Agenda views — zoom in or out on your time

PLAN MY DAY, AUTOMATICALLY
• Tell Chronos how you actually live — sleep, meals, standing routines, and when your brain works best
• It auto-schedules your tasks into the free time around your life, protecting meals and routines and aiming hard work at your peak focus window
• Reflow the rest of your day in one tap when plans change

TASKS, DONE RIGHT
• Your Apple Reminders, supercharged with time estimates, energy levels, and priority
• Triage what truly matters with the built-in Eisenhower matrix
• Auto-schedule any task into the next free slot

FOCUS WHEN IT COUNTS
• A built-in Pomodoro & focus timer
• It rides along on your Lock Screen and Dynamic Island as a Live Activity
• "Eat the frog" — knock out the one task you're avoiding

GROW EVERY DAY
• Habits with streaks and gentle nudges
• Goals that connect to your weeks
• A journal, plus research-backed morning and evening rituals

SEE YOUR PROGRESS
• A momentum score that rewards planning, doing, focusing, and reflecting — honestly
• Statistics, a "where did my time go" report, long-term trends, and your own Year in Review

A PRIVATE, ON-DEVICE AI COACH (on supported devices)
• Ask what to focus on; it answers from your real schedule and plans it with a tap
• Runs entirely on-device with Apple Intelligence — nothing leaves your iPhone

WIDGETS & MORE
• Home and Lock Screen widgets for today, up next, habits, and momentum
• Beautiful in light and dark, with a tint you can make your own
• A ⌘K command bar to reach anything instantly

PRIVACY BY DESIGN
Chronos has no servers of its own. Your calendar and tasks stay in Apple's Calendar and Reminders. Everything else stays on your device. No accounts, no ads, no tracking, no analytics. Just your time, beautifully planned.

Chronos works great for busy students, professionals, and anyone who wants to stop reacting to their day and start designing it.
```

_(≈2,050 characters — well under the limit, with room to expand.)_

---

## Keywords  _(max 100 chars, comma-separated, NO spaces after commas)_

Don't repeat words already in the Name/Subtitle (Apple indexes those separately).
This set fills the field efficiently:

```
planner,time block,timeblock,schedule,agenda,pomodoro,focus,habit,tasks,todo,productivity,routine
```
_(exactly 99 characters — verify in App Store Connect's counter before saving)_

Alternate keyword ideas to swap in for your audience:
`student,deep work,calendar blocking,day planner,reminders,goals,journal,streak`

---

## What's New (release notes for 1.0)  _(max 4000 chars)_
```
Welcome to Chronos — the calm, powerful way to plan your day on your own Apple Calendar and Reminders. Time-block by dragging, auto-schedule with Plan My Day, focus with a built-in Pomodoro, build habits, and watch your momentum grow. No account, no tracking — just your time, beautifully planned.
```

---

## Support & marketing URLs
- **Support URL (required):** a reachable page. Simplest: your GitHub Pages site
  (the same repo you host the privacy policy in) with a heading and a support
  email, e.g. `https://<user>.github.io/chronos-support/`. A `mailto:` alone is
  not accepted as a Support URL — it needs to be a web page.
- **Marketing URL (optional):** your landing page if you make one; leave blank
  otherwise.
- **Privacy Policy URL (required):** the hosted `docs/PRIVACY_POLICY.md` page.

---

## Category, rating, pricing
- **Primary category:** Productivity
- **Secondary category (optional):** Lifestyle
- **Age rating:** answer all questionnaire items "None" → **4+**
- **Price:** Free (Tier 0)
- **Availability:** All territories (default)

---

## App Privacy label (for the free build)
- Collection: **"Data is not collected."** (No servers, no analytics, no ads;
  calendar/reminders never leave Apple's frameworks to a server you control.)
- Tracking: **No.**
- (When you ship Chronos+ later, update this to disclose friend presence shared
  via CloudKit — see the note in PUBLISHING_GUIDE.md.)

Export compliance: uses only standard/exempt encryption (HTTPS/Apple frameworks).
Set `ITSAppUsesNonExemptEncryption = NO` in Info.plist to skip the per-upload
prompt.

---

## App Review notes  _(paste into "App Review Information → Notes")_
```
Chronos requires no account or login.

On first launch the app requests access to Apple Calendar and Reminders — these are required for core functionality (time blocks are calendar events; tasks are reminders). Please grant both when prompted so the app is fully testable. If a prompt is missed, it can be re-enabled in Settings → Privacy, and the app shows an in-app screen to do so.

There is no server backend; all data stays in the user's Apple Calendar/Reminders and on device. No paid or subscription features are active in this build.

The on-device AI "Coach" uses Apple Intelligence and only appears on supported devices/OS; it is optional and not required to review the app.
```

---

## Chronos+ variant (use ONLY after you enable the paid capabilities post-transfer)
When Chronos+ ships, append this block to the Description and update the App
Privacy label:
```
CHRONOS+ (optional)
• Sync your Chronos data across your Apple devices via your own private iCloud
• Add friends with a shareable code, see what they're focusing on, and cheer each other on
• Climb weekly focus and momentum leaderboards
Everything stays in your private iCloud; you choose what your friends can see.
```
And add keywords like: `icloud sync,leaderboard,friends,body doubling`.
