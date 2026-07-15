# Chronos — from free account to shipped on the App Store

A complete, do-it-in-order guide to getting a paid Apple Developer account,
setting up the project, turning on the paid features, and publishing Chronos to
the App Store. It also lists exactly **what lights up the moment you upgrade**.

> Chronos is a SwiftUI app built entirely on Apple Calendar (EventKit) +
> Reminders, $0/zero-server. It builds today on a free account; everything below
> is about distribution + the paid "Chronos+" capabilities.

---

## 0. What you need first

- **A Mac** running the latest macOS.
- **Xcode** (latest stable, free from the Mac App Store).
- **An Apple ID** (ideally one you'll dedicate to your developer identity).
- **A payment method** for the $99/yr membership.
- Optional but recommended: 2-factor auth already enabled on the Apple ID.

Chronos already compiles/runs on the free account (personal team, 7-day sideload).
Everything below unlocks real distribution + the Chronos+ features.

---

## 1. Enroll in the Apple Developer Program ($99/year)

1. Go to **developer.apple.com/programs** → **Enroll**.
2. Sign in with your Apple ID.
3. Choose an **entity type**:
   - **Individual / Sole Proprietor** — fastest, your legal name is the seller.
   - **Organization** — needs a legal entity + a **D-U-N-S number** (free, but can
     take days to get). Only pick this if you want a company name as the seller.
   - *Recommendation: start as an Individual — you can migrate later.*
4. Pay the **$99 USD/year**. 
5. **Wait for approval.** Individual is often minutes–48 h; org can take longer.
   You'll get an email when your membership is active.

Once active you have access to **App Store Connect**, distribution certificates,
push/iCloud/Game Center capabilities, and TestFlight.

---

## 2. Create the app record in App Store Connect

1. Go to **appstoreconnect.apple.com** → **My Apps** → **+** → **New App**.
2. Fill in:
   - **Platform:** iOS (add macOS later if you want a Mac build).
   - **Name:** `Chronos` (must be globally unique on the App Store — have a
     backup like "Chronos: Plan & Focus" ready in case it's taken).
   - **Primary language**, **Bundle ID** (create one — see §3), **SKU** (any
     internal string, e.g. `chronos-ios`).
3. Leave the rest for now; you'll fill metadata in §7.

---

## 3. Configure signing & bundle identifiers in Xcode

Open `Chronos.xcodeproj`. For **each** target (the **Chronos** app and the
**ChronosWidgetExtension**):

1. Select the target → **Signing & Capabilities**.
2. Set **Team** to your paid team.
3. Set a unique **Bundle Identifier** in reverse-DNS, e.g.:
   - App: `com.yourname.chronos`
   - Widget: `com.yourname.chronos.widget` (must be a child of the app's ID)
4. Leave **Automatically manage signing** on — Xcode creates the certificates &
   provisioning profiles for you.

> The bundle ID you invent here is the one you register in App Store Connect (§2).

---

## 4. Turn on the Chronos+ capabilities (the one-time unlock)

This is the payoff of upgrading. Follow **`docs/CHRONOS_PLUS_SETUP.md`** for the
click-by-click; in short, on the **Chronos** target → **Signing & Capabilities**
→ **+ Capability**, add:

| Capability | Unlocks |
|---|---|
| **iCloud → CloudKit** (+ a container, e.g. `iCloud.com.yourname.chronos`) | Cross-device sync of your Chronos data; Friends presence, activity feed, cheers, and the friends leaderboard |
| **App Groups** (`group.app.chronos.planner`, on **both** app + widget targets) | Live Home/Lock-Screen widgets |
| **Game Center** | Global focus/momentum leaderboards (in addition to the friend leaderboard) |

Then add **`CHRONOS_PLUS`** to the Chronos target's **Build Settings → Active
Compilation Conditions** (Debug + Release). This is the safety interlock that lets
the app actually call CloudKit/GameKit — see the setup doc for why.

Finally, in **App Store Connect → your app → Features → Game Center**, create two
leaderboards with these exact IDs:
- `chronos.focus.weekly`
- `chronos.momentum.alltime`

---

## 5. What you can enable *instantly* once you're paid

The moment your build is signed with the paid team **and** has the capabilities +
`CHRONOS_PLUS` flag above, all of this is already written and switches on from
**Settings → Chronos+** (or auto-detects):

- **iCloud Sync** — your Grow data (goals, habits, journal, templates, budgets),
  momentum history, planner profile, connected schools, focus log, and routines
  sync across all your Apple devices via your **private** iCloud. (Blocks & tasks
  already sync natively through Apple Calendar/Reminders.)
- **Friends & live presence** — a shareable friend code, custom status
  (emoji + line), and seeing what friends are focusing on right now.
- **Activity feed & cheers** — friends' streaks/focus moments, and 👏🔥💪 reactions
  via a CloudKit public inbox.
- **Friends leaderboard** — Focus / Momentum / Streak boards with a podium.
- **Focus Together (body doubling)** — see friends focusing now and start a
  session alongside them.
- **Game Center leaderboards** — global focus-minutes & momentum ranking.
- **Live widgets** — Home & Lock-Screen widgets that update through the day
  (needs the App Group; see `docs/WIDGETS_SETUP.md`).

Everything degrades gracefully: on the free account these show a clear
"available on Chronos+" state and never crash or nag.

### Optional: features that need an *extra* Apple entitlement (request separately)

- **Hard app/website blocking** during focus (like Opal/Freedom) needs Apple's
  **Family Controls / Screen Time entitlement** (`FamilyControls`,
  `ManagedSettings`, `DeviceActivity`). This must be **requested from Apple** via
  a form (developer.apple.com/contact/request/family-controls-distribution) and
  approved before you can ship it. Chronos ships the **soft** version today (the
  focus timer's sprout wilts if you leave the app) which needs no entitlement.

---

## 6. App icon & assets

- Add a **1024×1024** App Icon (no transparency, no rounded corners — Apple rounds
  it) to the asset catalog; provide the other required sizes (Xcode 15+ can
  generate from the single 1024 with a "Single Size" icon).
- Prepare **screenshots** for required device sizes (at minimum 6.7" iPhone).
  Capture from the Simulator (`Cmd+S`) in both light and dark mode to show off
  the new theming.

---

## 7. Fill in App Store metadata (App Store Connect)

For the app version:
- **Description**, **keywords**, **support URL**, **marketing URL** (optional).
- **Category** (Productivity), **content rating** (answer the questionnaire — 4+).
- **Privacy Policy URL** (required). Chronos stores data in the user's own Apple
  Calendar/Reminders + on-device + their private iCloud, and (with Chronos+) a
  public CloudKit record for friend presence — reflect that honestly.
- **App Privacy "nutrition label":** declare what you collect. Chronos is
  unusually clean here — calendar/reminder data stays in Apple's stores, momentum
  etc. are on-device/private iCloud. With Chronos+, friend **presence** (name you
  choose, status, current block title, coarse stats) is shared with friends via
  public CloudKit — disclose it as "User Content / linked to identity" if you
  enable it.
- **Export compliance:** Chronos uses only standard Apple encryption (HTTPS/
  CloudKit) — you'll typically answer "uses exempt encryption."

---

## 8. Archive, upload, and submit

1. In Xcode, set the run destination to **Any iOS Device (arm64)** (not a
   simulator).
2. **Product → Archive.** When it finishes, the **Organizer** opens.
3. Select the archive → **Distribute App → App Store Connect → Upload.** Xcode
   validates, signs, and uploads the build.
   - CLI alternative: `xcodebuild -scheme Chronos -archivePath build/Chronos.xcarchive archive` then `xcodebuild -exportArchive …`.
4. In App Store Connect, wait a few minutes for the build to finish **processing**.
5. **TestFlight (recommended):** add the build to TestFlight, install on your own
   device, and test the real signed app (this is also where you first verify the
   Chronos+ features against real iCloud/Game Center).
6. When happy, on the app version page: select the build, complete any remaining
   metadata, and **Submit for Review**.

---

## 9. Review, and after

- **Review** typically takes ~24–48 h. Common snags to pre-empt:
  - **Permission purpose strings:** make sure `NSCalendarsFullAccessUsageDescription`,
    `NSRemindersFullAccessUsageDescription` (and notifications) clearly explain
    *why* — Apple rejects vague ones.
  - **Sign-in / account:** Chronos needs no account, which reviewers like; if you
    ship Chronos+, ensure the free path works without iCloud so review can test it.
  - **Completeness:** no placeholder text, working links, screenshots match the app.
- After approval you can **release** immediately or on a date. Future updates =
  bump the **version/build**, archive, upload, submit again.

---

## TL;DR sequence

1. Enroll in the Apple Developer Program ($99) → wait for approval.
2. Create the app + bundle ID in App Store Connect.
3. In Xcode: set your Team + bundle IDs on both targets.
4. Add iCloud/App Groups/Game Center + the `CHRONOS_PLUS` flag → flip
   **Settings → Chronos+** on (see `docs/CHRONOS_PLUS_SETUP.md`).
5. Icon + screenshots + metadata + privacy labels.
6. Archive → upload → TestFlight → Submit for Review → Release.

Related docs: `docs/CHRONOS_PLUS_SETUP.md` (capabilities), `docs/WIDGETS_SETUP.md`
(widgets).
