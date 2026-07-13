# Widgets + Live Activities — Xcode Setup Walkthrough

Everything in code is done. The app-side writer, the shared data layer, and the
entire widget UI (three home-screen widgets + a focus Live Activity) are already
written and verified to compile. What's left is a one-time Xcode step: create the
widget **target** and tick a few boxes so Apple builds the extension alongside
the app.

This takes about 5 minutes. Follow it exactly.

> **Heads-up on cost:** the widgets share data with the app through an **App
> Group**, and App Groups require a **paid Apple Developer account** ($99/yr).
> On a free personal team the app still builds and runs, but the widgets will
> only ever show placeholder data because iOS won't grant the shared container.
> Everything else in Chronos works fine for free. If you're not paying yet, you
> can skip this entirely and come back later — nothing else depends on it.

---

## What's already in the repo

| File | Target it belongs to |
|------|----------------------|
| `Chronos/Shared/SharedData.swift` | **Both** (app + widget) |
| `Chronos/Shared/ChronosActivityAttributes.swift` | **Both** (app + widget) |
| `Chronos/Services/SnapshotWriter.swift` | App only (already in it) |
| `Chronos/Services/LiveActivityController.swift` | App only (already in it) |
| `ChronosWidget/ChronosWidgetBundle.swift` | **Widget only** |
| `ChronosWidget/ChronosWidgets.swift` | **Widget only** |
| `ChronosWidget/ChronosLiveActivity.swift` | **Widget only** |
| `ChronosWidget/ChronosWidget.entitlements` | **Widget only** |
| `ChronosWidget/Info.plist` | **Widget only** |

The two `Shared/` files live inside the app folder (so the app already compiles
them). You'll add them to the widget target's membership in Step 4.

---

## Step 1 — Create the Widget Extension target

1. Open `Chronos.xcodeproj` in Xcode.
2. Menu bar: **File ▸ New ▸ Target…**
3. Pick the **iOS** tab, search for **Widget Extension**, select it, **Next**.
4. Fill in:
   - **Product Name:** `ChronosWidget`  ← must match exactly
   - **Include Live Activity:** ✅ **check this box**
   - **Include Configuration App Intent:** ❌ leave unchecked
   - Team / Organization Identifier: same as the app.
5. **Finish.** When Xcode asks *"Activate 'ChronosWidget' scheme?"* click
   **Activate**.

Xcode just generated a `ChronosWidget/` group with boilerplate files
(`ChronosWidget.swift`, `ChronosWidgetBundle.swift`, `ChronosWidgetLiveActivity.swift`,
an asset catalog, etc.). We're going to replace the code ones with the versions
already in the repo.

---

## Step 2 — Delete Xcode's boilerplate, use ours

In the Project Navigator, inside the new **ChronosWidget** group, **delete**
(Move to Trash) these auto-generated files if they exist:

- `ChronosWidget.swift`
- `ChronosWidgetBundle.swift`
- `ChronosWidgetLiveActivity.swift`
- `ChronosWidgetControl.swift` (if present)
- `AppIntent.swift` (if present)

**Keep** the generated `Assets.xcassets` and the `Info.plist`/entitlements Xcode
made — or delete them and use ours; either works. Simplest is to keep Xcode's.

Now add **our** widget files. Right-click the **ChronosWidget** group ▸ **Add
Files to "Chronos"…**, navigate to the `ChronosWidget/` folder on disk, and add:

- `ChronosWidgetBundle.swift`
- `ChronosWidgets.swift`
- `ChronosLiveActivity.swift`

In the add dialog, under **Add to targets**, tick **ChronosWidget only** (NOT the
app). Click **Add**.

---

## Step 3 — Point the widget at the right deployment target

1. Select the project (top of the navigator) ▸ **ChronosWidget** target ▸
   **General** tab.
2. Set **Minimum Deployments → iOS 17.0** (matches the app).

---

## Step 4 — Share the two model files with the widget

The widget needs to read the same `TodaySnapshot` and `FocusActivityAttributes`
the app writes. Those two files already exist in the app; we just tell Xcode the
widget compiles them too.

1. In the navigator, select **`SharedData.swift`** (under `Chronos/Shared/`).
2. Open the **File Inspector** (right panel, ⌥⌘1).
3. Under **Target Membership**, tick **ChronosWidget** (leave **Chronos** ticked).
4. Repeat for **`ChronosActivityAttributes.swift`**.

Both files should now show **both** targets checked.

---

## Step 5 — Add the App Group to BOTH targets

*(This is the step that needs the paid account.)*

Do this **twice** — once for the **Chronos** app target, once for the
**ChronosWidget** target:

1. Select the target ▸ **Signing & Capabilities** tab.
2. Click **+ Capability** ▸ double-click **App Groups**.
3. Click the **+** under the App Groups list and add:

   ```
   group.app.chronos.planner
   ```

4. Make sure the checkbox next to it is **ticked**.

Both targets must have the **identical** group id. (It already matches the id
hard-coded in `SharedData.swift` and both `.entitlements` files.)

---

## Step 6 — Build & run

1. Select the **Chronos** scheme (not the widget) and a simulator or your device.
2. **⌘R**. The app builds, the widget target builds alongside it.
3. On the device/simulator: long-press the home screen ▸ **+** ▸ search
   **Chronos** ▸ add the **Today**, **Up Next**, or **Habits** widget.
4. Open the app once so it writes a snapshot — the widget fills in within a few
   seconds.

### See the Live Activity

1. In the app, start a focus timer (the Pomodoro/stopwatch).
2. Lock the phone or swipe to the Lock Screen — the focus session shows a live
   countdown. On a device with Dynamic Island it appears there too.

---

## Troubleshooting

- **Widget shows placeholder data forever** → the App Group isn't active. You're
  either on a free team (expected — needs the paid account) or the group id
  doesn't match on both targets. Re-check Step 5 on *both* targets.
- **"No such module 'ActivityKit'" on the macOS build** → shouldn't happen; all
  ActivityKit code is guarded by `#if canImport(ActivityKit)`. If you moved a
  file, make sure the widget files stayed in the widget target only.
- **Duplicate `@main` error** → you left both Xcode's generated
  `ChronosWidgetBundle.swift` and ours in the target. Delete Xcode's (Step 2).
- **Widget doesn't update** → the app refreshes the snapshot when the timeline,
  tasks, or habits change and when it becomes active. Reopen the app to force it.

That's it. Once the target exists, everything else — new widget designs, Live
Activity tweaks — is just editing the files already in `ChronosWidget/`.
