# Chronos+ — turning on the paid-account features

Chronos+ is the set of features that ride on Apple capabilities available only
to a **paid Apple Developer account**: iCloud sync, Game Center leaderboards,
Friends presence, and the live Home/Lock Screen widgets.

**Everything is already built.** The code compiles and ships today on the free
account — it just stays dormant. Chronos auto-detects the capabilities at
runtime (by reading its own entitlements) and never touches CloudKit, GameKit,
or the App Group unless they're actually present. Nothing nags, nothing breaks.

When you upgrade, turning it on is: **add three capabilities in Xcode, tap one
switch in the app.** This document is the click-by-click.

---

## What lights up

| Feature | Apple capability | Where it shows |
|---|---|---|
| **iCloud Sync** — Grow data, momentum, planner profile, connected schools & focus log across all your devices | iCloud → CloudKit | Automatic; status in Settings › Chronos+ |
| **Leaderboards** — weekly focus minutes & all-time momentum, ranked with friends | Game Center | Chronos+ › Leaderboard |
| **Friends** — a shareable code and live presence (what a friend is focusing on, how busy) | iCloud → CloudKit (public DB) | Chronos+ › Friends |
| **Live Widgets** — Home & Lock Screen widgets that update through the day | App Groups | Add widgets from the Home Screen |

Blocks and tasks are **not** part of iCloud Sync — they already live in Apple
Calendar & Reminders, which iCloud syncs natively. Chronos+ only carries the
extra data Apple's apps can't hold.

---

## Prerequisites

- A paid **Apple Developer Program** membership ($99/yr).
- You're signed into Xcode with that team (Xcode › Settings › Accounts).

---

## Step 1 — Add the capabilities in Xcode

Open `Chronos.xcodeproj`, select the **Chronos** target → **Signing &
Capabilities**, set your paid **Team**, then click **+ Capability** and add:

### iCloud
1. Tick **CloudKit**.
2. Under Containers, click **+** and create `iCloud.app.chronos.planner`
   (or accept the default `iCloud.<bundle-id>`).
3. That's it — `CloudSyncService` and the Friends backend find the default
   container automatically.

### App Groups
1. Click **+** under App Groups and add **`group.app.chronos.planner`**.
2. Select the **ChronosWidgetExtension** target and add the **same** App Group
   there too (both targets must share it). See `docs/WIDGETS_SETUP.md` for the
   widget target itself.

### Game Center
1. Just add the **Game Center** capability (no options to configure here).
2. In **App Store Connect** → your app → **Features › Game Center**, create two
   leaderboards with these exact IDs:
   - `chronos.focus.weekly` — *Weekly Focus Minutes* (higher is better, integer)
   - `chronos.momentum.alltime` — *All-Time Momentum* (higher is better, integer)

Xcode writes these into `Chronos.entitlements` for you. For reference, the
finished file contains:

```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array><string>iCloud.app.chronos.planner</string></array>
<key>com.apple.developer.icloud-services</key>
<array><string>CloudKit</string></array>
<key>com.apple.security.application-groups</key>
<array><string>group.app.chronos.planner</string></array>
<key>com.apple.developer.game-center</key>
<true/>
```

## Step 2 — Flip on the code path

The app only reaches CloudKit/GameKit when the build is compiled with the
**`CHRONOS_PLUS`** flag. This is a safety interlock: without it, the free
account's binary can never touch a paid framework (which would crash without the
matching entitlement).

In the **Chronos** target → **Build Settings** → **Active Compilation
Conditions**, add **`CHRONOS_PLUS`** (to Debug and Release).

> Add this flag **only after** all three capabilities above are in place — it
> tells the app every paid capability is present.

## Step 3 — Turn it on in the app

1. Build & run on your device.
2. **Settings › Chronos+** — the master switch now appears (it's hidden until a
   capability is entitled).
3. Flip **Turn on Chronos+**. Sync starts, Game Center signs in, and the
   per-feature toggles become live.

That's the one tap. If you pre-enabled the switch on the free account, it's
already on and everything activates the moment the entitled build launches.

---

## How the graceful degradation works (for maintainers)

Every paid path gates on `PaidFeatures.shared.isReady(_:)`, which is true only
when **all three** hold:

1. **Entitled** — `AppEntitlements.chronosPlusBuild` is the `CHRONOS_PLUS`
   compile flag. On the free build it's false, so the CloudKit/GameKit APIs are
   never called (constructing a `CKContainer` without the entitlement would
   otherwise crash — this is why we gate *before* touching it).
2. **Account available** — for iCloud features, `CKContainer.accountStatus`
   reports `.available`.
3. **User opted in** — the `Prefs.chronosPlusEnabled` master toggle (plus the
   per-feature toggle) is on.

This mirrors how App Groups and Apple Foundation Models already degrade: compile
everywhere, run only when available, otherwise no-op with a clear message. See:

- `Chronos/Services/PaidFeatures.swift` — availability + entitlement detection
- `Chronos/Services/CloudSyncService.swift` — CloudKit mirror of the local blobs
- `Chronos/Services/SocialService.swift` — Game Center + Friends (CloudKit) 
- `Chronos/Views/Social/` — the Chronos+ hub, Leaderboard, Friends UI

Nothing here requires an upgrade to keep building green on the free account.
