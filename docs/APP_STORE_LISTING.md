# Chronos — App Store listing (copy-paste ready)

Everything you paste into App Store Connect for the **1.0 build**.

The **base copy below** is for the safest possible launch — it describes only
what ships in the plain build and never mentions anything that isn't there, so
there's no 2.3.1 ("advertising features not in the app") risk.

Two optional add-on blocks are at the bottom, matched to how far along you are:

- **Option C (pre-transfer, transfer-safe):** if you turn on **Game Center**
  in the build you submit, paste the *"Compete on Game Center"* block so the
  global leaderboards are advertised. Game Center transfers cleanly with the
  app, so this is safe to ship before moving the app to your own account.
- **Full Chronos+ (post-transfer):** once the app is on your own paid account
  and you add the iCloud capability, paste the *iCloud sync + friends* block.

**Golden rule:** only paste an add-on block if that capability is actually
enabled in the binary you upload. When in doubt, ship the base copy.

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
- **If you enable Game Center (Option C):** it stays **"Data is not
  collected"** for *your* privacy label — Game Center is Apple's own service, so
  the score you submit is handled under Apple's privacy policy, not yours. You
  are not running a server or collecting the data. (Tracking is still **No**.)
- (When you ship the full Chronos+ later, update this to disclose friend
  presence shared via CloudKit — see the note in PUBLISHING_GUIDE.md.)

Export compliance: uses only standard/exempt encryption (HTTPS/Apple frameworks).
Set `ITSAppUsesNonExemptEncryption = NO` in Info.plist to skip the per-upload
prompt.

---

## App Review notes  _(paste into "App Review Information → Notes")_
```
Chronos requires no account or login.

On first launch the app requests access to Apple Calendar and Reminders — these are required for core functionality (time blocks are calendar events; tasks are reminders). Please grant both when prompted so the app is fully testable. If a prompt is missed, it can be re-enabled in Settings → Privacy, and the app shows an in-app screen to do so.

There is no server backend; all data stays in the user's Apple Calendar/Reminders and on device. There are no in-app purchases or subscriptions.

The on-device AI "Coach" uses Apple Intelligence and only appears on supported devices/OS; it is optional and not required to review the app.
```

**If Game Center is enabled in the build (Option C),** add this line to the notes:
```
Game Center is optional: the app shows global focus/momentum leaderboards via Apple's Game Center. It is free, requires no account of ours, and the app is fully functional without signing in to Game Center.
```

---

## Add-on block A — "Compete on Game Center" (Option C, pre-transfer)

Use this **only if you turn on the Game Center capability** in the build you
upload (see `docs/CHRONOS_PLUS_SETUP.md` → the `CHRONOS_GAMECENTER` flag). Game
Center is transfer-safe, so this ships before you move the app to your own
account. Append to the Description:
```
COMPETE ON GAME CENTER (optional)
• Rank your weekly focus minutes and all-time momentum on Apple's global Game Center leaderboards
• Totally optional and free — the whole app works without ever signing in
• Nothing new to sign up for; it's the Game Center you already have
```
Optional keyword swap-in (only if enabled): replace a lower-value keyword with
`leaderboard`. Keep the keyword field at/under 100 chars.

Everything else — the App Privacy label ("Data is not collected"), the 4+
rating, and the free price — is unchanged. Game Center does **not** require an
in-app purchase and adds no server of yours.

---

## Add-on block B — full Chronos+ (use ONLY post-transfer, once iCloud is enabled)

When the app is on your own paid account and you've added the iCloud capability
(`CHRONOS_CLOUD` / `CHRONOS_PLUS`), append this block to the Description **and**
update the App Privacy label to disclose friend presence shared via CloudKit:
```
CHRONOS+ (optional)
• Sync your Chronos data across your Apple devices via your own private iCloud
• Add friends with a shareable code, see what they're focusing on, and cheer each other on
• Climb weekly focus and momentum leaderboards with friends
Everything stays in your private iCloud; you choose what your friends can see.
```
And add keywords like: `icloud sync,friends,body doubling`.
