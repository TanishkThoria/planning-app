# Chronos — Screenshots & App Preview video

**Honest note:** the actual screenshot PNGs and the App Preview video have to be
captured from Chronos **running** (Simulator or your device) — they can't be
generated without the live app. This is the exact, do-it-in-order plan so it
takes ~30–45 minutes: what to shoot, in what order, the captions to overlay, and
the precise sizes Apple requires.

---

## Before you shoot: seed a good-looking day

A demo day sells the app. Spend 5 minutes setting one up (in the Simulator or on
your device) so every screen looks alive, not empty:

1. Add ~5–6 time blocks across the day with varied **categories** (e.g. Class,
   Deep Work, Gym, Lunch, Study, Social) so the timeline shows colour.
2. Add ~6 tasks with a mix of priorities, estimates, and a couple due today.
3. Complete a habit or two in **Grow** so streaks show.
4. Run a short **focus** session so the Insights/momentum screens aren't zero.
5. Pick a nice **accent** (Settings → Appearance) — the default blue photographs
   well; teal or indigo also look great.

---

## Required sizes (Apple)

You **must** provide the **6.7" iPhone** set; everything else is optional but nice.

| Display | Device to use in Simulator | Portrait pixels |
|---|---|---|
| **6.7" (required)** | iPhone 15 Pro Max / 16 Pro Max | **1290 × 2796** |
| 6.5" (optional) | iPhone 11 Pro Max / XS Max | 1242 × 2688 |
| 6.1" (optional) | iPhone 15 / 16 | 1179 × 2556 |
| 12.9" iPad (only if you ship iPad) | iPad Pro 12.9" | 2048 × 2732 |

You can upload **up to 10** screenshots per size. Ship **6–8**. Apple can scale
one large set down, but providing the 6.7" set is what's enforced.

**Capture:** run Chronos in the chosen Simulator, get the screen looking right,
then **File → Save Screen (⌘S)** — it saves a correctly-sized PNG to your Desktop.
Do the whole set in **dark mode**, then switch the Simulator to **light mode**
(Settings app → Developer, or `xcrun simctl ui booted appearance light`) and
reshoot the 2–3 hero shots so your gallery shows both.

---

## The shot list (order matters — first two carry the whole gallery)

Shoot these screens, in this order. The **caption** is the marketing text you
overlay at the top (see "Framing" below).

1. **Today** — the home screen with "now / next / what's left."
   Caption: **"Your whole day, at a glance"**
2. **Day timeline** — a colourful day with several category-coloured blocks.
   Caption: **"Time-block by dragging"**
3. **Plan My Day** (the sheet mid-plan, or a freshly auto-planned day).
   Caption: **"Auto-schedule around your life"**
4. **Tasks** — with the Eisenhower matrix toggled on (or a rich task list).
   Caption: **"Triage what actually matters"**
5. **Focus timer** running (bonus: show the Live Activity on the Lock Screen as a
   separate shot if you can).
   Caption: **"Focus when it counts"**
6. **Grow** — habits with streaks + a goal.
   Caption: **"Build the habits behind the plan"**
7. **Insights** — momentum + stats.
   Caption: **"Watch your momentum grow"**
8. **Coach** (only if your capture device supports Apple Intelligence).
   Caption: **"A private, on-device coach"**

Pick 6–8 of these. If you can only do 6: 1, 2, 3, 4, 6, 7.

---

## Framing (optional but makes it look pro)

Bare screenshots are allowed and fine. To make them "App Store nice," put each
screenshot on a coloured background with the caption above it:

- **Easiest, free, automated:** [Fastlane `frameit`](https://docs.fastlane.tools/actions/frameit/)
  wraps screenshots in device bezels and adds captions from a text file.
- **Design tools:** Figma (free), Screenshot.rocks, or Apple's own template — a
  1290×2796 canvas, a soft brand-blue gradient background, the caption in bold
  ~90pt SF Pro at the top, and the screenshot inset ~80% with a subtle shadow.
- **Keep it consistent:** same background, same caption font/size/position on
  every frame. That consistency is what reads as "polished."

Brand palette to match the app: accent **#0A84FF**, deep background **#000000**
(dark) / **#F2F2F7** (light), text **#1C1C1E / #F5F5F7**.

---

## App Preview video (optional, 15–30 seconds)

An App Preview is a short screen-recording. It's optional but boosts conversion.
Apple requires it to be **captured on-device** (real screen recording), portrait,
15–30s, same resolutions as screenshots.

### How to record
1. On your iPhone: **Settings → Control Center → add Screen Recording.**
2. Open Chronos, start a **Screen Recording** from Control Center, perform the
   script below smoothly (rehearse once), stop recording.
3. Trim to 15–30s in Photos, or edit in iMovie/CapCut. Add short text overlays
   matching the beats. Keep music optional/royalty-free (or none — Apple mutes
   previews until tapped anyway).
   - Apple also accepts previews captured via QuickTime from a connected device
     (File → New Movie Recording → select iPhone).

### 25-second script / storyboard
| Time | On screen | Text overlay |
|---|---|---|
| 0–3s | Today screen, scroll gently | "Plan your day" |
| 3–8s | Drag a task onto the timeline; it becomes a block | "Drag to time-block" |
| 8–13s | Tap **Plan My Day**; blocks fill the day | "Auto-schedule around your life" |
| 13–18s | Start the **focus timer**; show it counting | "Focus when it counts" |
| 18–22s | Open **Insights**; momentum ring animates | "Build real momentum" |
| 22–25s | Back to Today; app icon / name card | "Chronos" |

Keep motion calm and deliberate — no frantic tapping. One smooth take per beat.

---

## Upload

In **App Store Connect → your app → the 1.0 version → Previews and Screenshots**:
drag the 6.7" screenshots in your chosen order (the first is the most important),
add captions if you didn't bake them into the images, and drop the App Preview
into the same section. Save.
