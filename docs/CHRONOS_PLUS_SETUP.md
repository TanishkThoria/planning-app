# Chronos+ — turning on the paid-account features

Chronos+ is the set of features that ride on Apple capabilities available only
to a **paid Apple Developer account**: live Home/Lock Screen widgets, Game
Center leaderboards, iCloud sync, and Friends presence.

**Everything is already built.** The code compiles and ships today on the free
account — it just stays dormant. Chronos auto-detects each capability and never
touches the App Group, GameKit, or CloudKit unless it's actually present.
Nothing nags, nothing breaks.

The important part for a launch you'll want to **transfer to your own account
later**: these features are **not** all-or-nothing. They split into three
independent switches with different transfer characteristics, so you can turn on
the transfer-safe ones **now** and add iCloud **after** the transfer.

---

## The three switches (turn on what you can, when you can)

| Feature | Apple capability | Compile flag | Transfer-safe? | When |
|---|---|---|---|---|
| **Live Widgets** — Home & Lock Screen widgets that update through the day | App Groups | *none* (runtime-detected) | ✅ Yes | **Ship now** |
| **Leaderboards** — weekly focus minutes & all-time momentum on Apple's global Game Center | Game Center | `CHRONOS_GAMECENTER` | ✅ Yes | **Ship now (Option C)** |
| **iCloud Sync** — Grow data, momentum, planner profile, connected schools & focus log across your devices | iCloud → CloudKit | `CHRONOS_CLOUD` | ⚠️ No — see below | **After transfer** |
| **Friends** — shareable code + live presence (what a friend is focusing on) | iCloud → CloudKit | `CHRONOS_CLOUD` | ⚠️ No | **After transfer** |

The umbrella flag **`CHRONOS_PLUS`** turns on *all* of the above at once — use it
post-transfer when everything is in place. `CHRONOS_GAMECENTER` and
`CHRONOS_CLOUD` are the à-la-carte flags for the Option C path.

> **Why iCloud waits (the transfer catch):** a CloudKit container is bound to
> the developer account that created it, and App Transfer moves the app but the
> data-migration story for a public CloudKit database is messy. Game Center and
> App Groups carry over cleanly. So the recommended launch — **Option C** — is:
> ship **Live Widgets + Game Center** on the family account now, then add
> **iCloud Sync + Friends** once the app is on your own account (no user data to
> migrate, because there was never any CloudKit data yet).

Blocks and tasks are **never** part of iCloud Sync — they already live in Apple
Calendar & Reminders, which iCloud syncs natively.

---

## Prerequisites

- A paid **Apple Developer Program** membership ($99/yr) on the account that
  will sign the build.
- You're signed into Xcode with that team (Xcode › Settings › Accounts).

---

## Recommended: the Option C launch (now)

This is everything transfer-safe. Do this before the first submission.

### A. Live Widgets — App Group (no compile flag)

1. Xcode → **Chronos** target → **Signing & Capabilities** → **+ Capability** →
   **App Groups** → add **`group.app.chronos.planner`**.
2. Select the **ChronosWidgetExtension** target and add the **same** App Group
   there too (both targets must share it). See `docs/WIDGETS_SETUP.md`.

That's it — no flag. Live Widgets are detected purely at runtime by
`AppEntitlements.appGroupConfigured` (it just checks whether the shared
container exists), so they light up the moment the App Group is present.

### B. Game Center leaderboards — `CHRONOS_GAMECENTER`

1. **+ Capability** → **Game Center** (nothing to configure in the sheet).
2. **Build Settings** → **Active Compilation Conditions** → add
   **`CHRONOS_GAMECENTER`** (Debug **and** Release).
3. In **App Store Connect** → your app → **Features › Game Center**, create two
   leaderboards with these exact IDs:
   - `chronos.focus.weekly` — *Weekly Focus Minutes* (higher is better, integer)
   - `chronos.momentum.alltime` — *All-Time Momentum* (higher is better, integer)

> Add `CHRONOS_GAMECENTER` **only after** the Game Center capability is in place.
> Without the flag, the binary can never call GameKit (which would crash without
> the entitlement); with it, the app knows Game Center is present.

After A + B your entitlements file contains:

```xml
<key>com.apple.security.application-groups</key>
<array><string>group.app.chronos.planner</string></array>
<key>com.apple.developer.game-center</key>
<true/>
```

No iCloud keys yet — which is exactly what keeps the app easy to transfer.

---

## After the transfer: add iCloud Sync + Friends — `CHRONOS_CLOUD`

Once the app is on **your own** paid account (App Transfer complete):

1. **+ Capability** → **iCloud** → tick **CloudKit** → under Containers, **+** →
   create `iCloud.app.chronos.planner` (or accept the default `iCloud.<bundle-id>`).
2. **Build Settings** → **Active Compilation Conditions** → add
   **`CHRONOS_CLOUD`** (Debug and Release). (Or swap both à-la-carte flags for
   the single **`CHRONOS_PLUS`** umbrella, which implies both.)

The finished entitlements file then also contains:

```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array><string>iCloud.app.chronos.planner</string></array>
<key>com.apple.developer.icloud-services</key>
<array><string>CloudKit</string></array>
```

Because you had no CloudKit data before the transfer, there is nothing to
migrate — friends and sync simply begin working for everyone on the next update.

---

## Turn it on in the app

1. Build & run on your device.
2. **Settings › Chronos+** — the master switch appears (it's hidden until at
   least one capability is entitled).
3. Flip **Turn on Chronos+**. The per-feature toggles for whatever you've
   enabled become live; anything not in this build simply isn't listed.

If you pre-enabled the switch earlier, it's already on and each capability
activates the moment an entitled build launches.

---

## How the graceful degradation works (for maintainers)

Every paid path gates on `PaidFeatures.shared.isReady(_:)`, and each capability
is entitled **independently** via `isEntitled(_:)` in
`Chronos/Services/PaidFeatures.swift`:

- `.liveWidgets` → `AppEntitlements.appGroupConfigured` — a **runtime** check
  (does the App Group container exist?). No compile flag.
- `.leaderboards` → `AppEntitlements.gameCenterBuild` — the `CHRONOS_GAMECENTER`
  (or `CHRONOS_PLUS`) compile flag.
- `.cloudSync`, `.friends` → `AppEntitlements.cloudBuild` — the `CHRONOS_CLOUD`
  (or `CHRONOS_PLUS`) compile flag.

`isReady` additionally requires the account to be available (for iCloud) and the
user's master + per-feature toggles to be on. On the free build every
`isEntitled` is false, so the CloudKit/GameKit APIs are never called
(constructing a `CKContainer` without the entitlement would otherwise crash —
this is why we gate *before* touching it).

This mirrors how App Groups and Apple Foundation Models already degrade: compile
everywhere, run only when available, otherwise no-op with a clear message. See:

- `Chronos/Services/PaidFeatures.swift` — per-capability entitlement detection
- `Chronos/Services/CloudSyncService.swift` — CloudKit mirror of the local blobs
- `Chronos/Services/SocialService.swift` — Game Center + Friends (CloudKit)
- `Chronos/Views/Social/` — the Chronos+ hub, Leaderboard, Friends UI

Nothing here requires an upgrade to keep building green on the free account.
