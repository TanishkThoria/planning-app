# Chronos — Hand-held guide to shipping on the App Store

This is the **do-it-in-order, don't-skip-a-step** guide to publishing Chronos —
including the special case you asked about: **enrolling under a family member's
name now and transferring the app to your own account later.**

Read the whole "Strategy" section first (it saves you real pain), then follow the
numbered steps top to bottom. Every step tells you exactly where to click.

> **Time & money:** Plan for one focused afternoon of setup + ~1–2 days of
> waiting (developer-account approval, then app review). Cost: **$99/year per
> Apple Developer account.** Because you're transferring later, you will
> ultimately need **two** paid accounts (the family member's now, and yours
> later) — see Strategy.

---

## Strategy — read this before you touch anything

**Your situation:** you want to launch now, but the paid developer account has to
be in a family member's name, and you'll move ownership to your own account
later.

Three things make this smooth:

1. **The family member is the legal "developer of record" until transfer.**
   Whoever enrolls in the Apple Developer Program is the legal account holder and
   agrees to Apple's contracts. It must be an **adult (18+)** using **their** real
   legal name and a payment method. (If the real reason is that you're under 18,
   this is the normal, Apple-sanctioned path: a parent/guardian enrolls now, you
   enroll and receive the transfer once you have your own account.)

2. **Ship the FREE build first. Add "Chronos+" only AFTER the transfer.**
   Chronos has an optional paid-feature layer (iCloud sync, friends,
   leaderboards) that uses **CloudKit**. Apps that use CloudKit are **harder to
   transfer** between accounts. The app is built so the entire Chronos+ layer is
   **hidden and inert unless you deliberately turn on those capabilities** — so
   your first release can ship **without CloudKit at all**, which keeps the app
   **transfer-eligible**. After you transfer it to your own account, follow
   `docs/CHRONOS_PLUS_SETUP.md` to light up Chronos+ in an update. **Don't enable
   iCloud/CloudKit before the transfer.**

3. **You'll need your own paid account to *receive* the app.** A transfer moves
   an app from one paid account to another paid account. So when you're ready,
   *you* enroll your own account ($99) and the family member transfers the app to
   you. Until then, everything lives under their account.

**Net plan:**
`Family member enrolls → you build & submit the free build under their account →
release → (later) you enroll your own account → they transfer the app to you →
you add Chronos+ in an update.`

---

## 0. What you need

- A **Mac** on the latest macOS.
- **Xcode** (latest stable) — free in the Mac App Store. Open it once and let it
  install components.
- The **family member present** (or their cooperation) for enrollment: their
  legal name, Apple ID, a payment method, and their agreement to Apple's terms.
  Enrollment identity-verification may ask for a government ID.
- **Two-factor authentication** enabled on the Apple ID that will enroll (Apple
  requires it).
- ~1 hour for setup + waiting time for approvals.

Chronos already builds and runs on a **free** Apple ID (personal team, 7-day
sideload) so you can test on your own device today. Everything below is about
**distribution** on the App Store.

---

## 1. Enroll the family member in the Apple Developer Program ($99/yr)

Do this **on the family member's Apple ID** (or a new Apple ID created in their
name).

1. On any browser go to **developer.apple.com/programs/** and click **Enroll**.
2. Click **Start Your Enrollment** and **sign in** with the family member's Apple
   ID (enable 2FA if prompted).
3. **Entity type:**
   - Choose **Individual / Sole Proprietor**. This is fastest and the seller name
     shown on the App Store will be the **family member's legal name**.
   - (Skip "Company/Organization" — it needs a D-U-N-S number and can take days.
     You don't need it, and it doesn't help the transfer.)
4. Confirm the personal details **exactly** as on their ID. Complete any identity
   verification Apple asks for (sometimes an ID scan via the Apple Developer app).
5. **Review the license agreement**, agree, and **pay the $99 USD** membership.
6. **Wait for the "Welcome" email.** Individual approval is often minutes to
   ~48 hours.

When it's active, sign in at **appstoreconnect.apple.com** with that same Apple
ID — you'll manage the app there.

> Everything from here on you can do yourself on the Mac while signed in to
> Xcode/App Store Connect with the **family member's** developer Apple ID.

---

## 2. Sign in to Xcode with the developer account

1. Open **Xcode → Settings (⌘,) → Accounts**.
2. Click **+** → **Apple ID** → sign in with the **family member's developer
   Apple ID**.
3. You should now see their **Team** (e.g., "Firstname Lastname (Individual)").

---

## 3. Set the Team + bundle identifiers on both targets

Open `Chronos.xcodeproj` in Xcode. Do this for **both** targets — the **Chronos**
app and the **ChronosWidgetExtension**:

1. Select the **project** in the sidebar → pick the target → **Signing &
   Capabilities** tab.
2. **Team:** choose the family member's team.
3. **Bundle Identifier:** set a unique reverse-DNS ID. Use a domain-like prefix
   you'll keep, e.g.:
   - App: `com.<familyname>.chronos`
   - Widget: `com.<familyname>.chronos.widget` **(must start with the app's ID)**
4. Keep **Automatically manage signing** checked. Xcode creates the signing
   certificate and provisioning profiles for you.
5. Fix any red signing errors before continuing (usually just picking the Team).

> **Do NOT add the iCloud/CloudKit/App Groups/Game Center capabilities yet** —
> per the Strategy, the first release ships without them so the app stays
> transfer-eligible. The app already hides all Chronos+ UI when they're absent.

**Sanity check the app builds:** set the run destination to your iPhone (or a
Simulator) and press **⌘R**. It should launch and run.

---

## 4. Confirm the permission usage strings

App Review rejects vague permission prompts. Chronos already ships clear ones —
verify them (target → **Info** tab, or the target's Info.plist):

- **NSCalendarsFullAccessUsageDescription** — e.g. "Chronos shows and edits your
  time blocks as events in your Apple Calendar."
- **NSRemindersFullAccessUsageDescription** — e.g. "Chronos shows and edits your
  tasks as items in your Apple Reminders."
- (If present) the notifications usage is requested at runtime — no string
  needed, but the purpose is explained in-app.

If any are missing or generic, make them specific about **what** and **why**.

---

## 5. App icon & screenshots

**Icon:**
- You need a **1024×1024 px** PNG, no transparency, no rounded corners (Apple
  rounds it). Put it in the asset catalog's **AppIcon** (Xcode 15+ accepts a
  single 1024 and generates the rest).

**Screenshots (required to submit):**
- Minimum required: **6.7" iPhone** portrait (e.g., iPhone 15 Pro Max sizes,
  1290×2796). Providing the 6.5" set too is nice but the 6.7" set is what's
  enforced.
- Easiest capture: run Chronos in the **iPhone 15 Pro Max Simulator**, arrange a
  nice day, and press **⌘S** to save each screenshot to the Desktop. Grab 3–6:
  Today, the day timeline, Tasks, Grow/Insights. Capture a couple in **dark mode**
  and a couple in **light mode** to show the theming.
- Optional but recommended: add a short caption to each in App Store Connect.

---

## 6. Publish your Privacy Policy (required — takes 5 minutes)

App Review **requires a Privacy Policy URL**. A ready-to-use policy is in
`docs/PRIVACY_POLICY.md` (Chronos is zero-server, so it's short and honest). Host
it for free with **GitHub Pages**:

1. In a GitHub repo (can be a new public repo, e.g. `chronos-privacy`), add the
   contents of `docs/PRIVACY_POLICY.md` as `index.md`. Fill in the date and a
   support email at the placeholders.
2. Repo **Settings → Pages → Source: Deploy from branch → main → /(root) →
   Save.**
3. After a minute you'll get a URL like
   `https://<user>.github.io/chronos-privacy/`. **That's your Privacy Policy
   URL.** Open it to confirm it renders.

(Any public URL works — a Notion page, a personal site, etc. It just has to be
reachable and describe the app's data handling.)

---

## 7. Create the app record in App Store Connect

1. Go to **appstoreconnect.apple.com** → **Apps** → the blue **＋** → **New App**.
2. Fill in:
   - **Platforms:** iOS. (Add macOS later if you want a Mac version.)
   - **Name:** your public app name. It must be **globally unique** on the App
     Store — have a backup ready (e.g., "Chronos: Plan & Focus") in case
     "Chronos" is taken.
   - **Primary Language.**
   - **Bundle ID:** pick the app bundle ID from step 3 (it should appear in the
     dropdown once Xcode has registered it; if not, register it at
     developer.apple.com → Certificates, IDs & Profiles → Identifiers → ＋).
   - **SKU:** any private string, e.g. `chronos-ios-001`.
   - **User Access:** Full.
3. Click **Create**.

---

## 8. Fill in the version metadata

In the new app → the **1.0 version** page (left sidebar) and the **App
Information** / **Pricing** pages:

- **Screenshots:** upload the 6.7" set from step 5.
- **Promotional text / Description:** what Chronos is and does. Be accurate — don't
  mention features the shipped build doesn't have (Chronos+ is hidden in this
  build, so **don't** advertise leaderboards/friends/iCloud sync in 1.0).
- **Keywords:** comma-separated, e.g.
  `planner,time block,calendar,tasks,focus,pomodoro,habits,agenda,schedule,productivity`.
- **Support URL:** a reachable page (can be the same GitHub Pages site, or a
  mailto page). **Required.**
- **Marketing URL:** optional.
- **Privacy Policy URL:** paste the URL from step 6. **Required.**
- **App Store icon:** it comes from the build you upload (step 11), not here.
- **Category:** Primary **Productivity** (Secondary optional, e.g. Lifestyle).
- **Age Rating:** click **Edit**, answer the questionnaire honestly. Chronos has
  no objectionable content → it lands at **4+**. (No user-generated content is
  shown to strangers in the free build, so those answers are "None.")
- **Pricing:** set **Free** (or a price) on the **Pricing and Availability** page,
  and pick territories (default: all).
- **App Privacy:** click **Get Started** and fill the **privacy "nutrition
  label"** — see step 9. This is separate from your Privacy Policy URL.

---

## 9. App Privacy "nutrition label" — exact answers for the free build

On the **App Privacy** page, Apple asks what data you collect. For the **free
build** (no Chronos+/CloudKit, no analytics, no accounts), the honest answers are
essentially **"Data Not Collected."** Walk it like this:

- **"Do you or your third-party partners collect data from this app?"**
  Chronos has no servers, no analytics SDKs, and no ad SDKs. Your Calendar and
  Reminders data stays in Apple's own stores on the user's device/iCloud and is
  **not collected by you**. So you can answer **"No, we do not collect data from
  this app."**
- If you're cautious and prefer to over-disclose, you may list Calendar and
  Reminders as data that is **used but not linked to the user and not used for
  tracking, and not collected by you** — but since it never leaves Apple's
  frameworks to a server you control, "Data Not Collected" is the accurate,
  common choice for an app like this.
- **Tracking:** **No** (no ATT prompt, no cross-app tracking).

> When you later add **Chronos+** (after the transfer), you'll revisit this and
> disclose the friend-presence data shared via CloudKit. For 1.0 it's clean.

**Export compliance:** Chronos uses only Apple's standard HTTPS encryption. On
upload you'll be asked about encryption — answer that it uses only
**exempt/standard encryption** (no custom crypto). To avoid being asked every
upload, you can add `ITSAppUsesNonExemptEncryption = NO` to Info.plist.

---

## 10. (Optional but smart) do a private build check

Before archiving, in Xcode: **Product → Scheme → Edit Scheme → Run → Build
Configuration** is Debug for running; archives use **Release** automatically.
Just make sure the app runs cleanly on a real device via ⌘R first.

---

## 11. Archive and upload the build

1. In Xcode's toolbar, set the run destination to **Any iOS Device (arm64)**
   (top bar, next to the scheme — **not** a Simulator).
2. **Product → Archive.** Wait for it to build; the **Organizer** window opens
   with your archive.
3. Select the archive → **Distribute App** → **App Store Connect** → **Upload** →
   keep the default signing options (automatic) → **Upload**.
   - Xcode validates, signs with the family member's team, and uploads.
4. Go to App Store Connect → your app → **TestFlight** tab. The build shows as
   **"Processing"** for a few minutes. When it finishes you may get an email
   about "Missing Compliance" — answer the export-compliance question there
   (standard encryption) if you didn't set the Info.plist key.

---

## 12. Test it on TestFlight (don't skip this)

1. In **TestFlight**, under **Internal Testing**, add yourself (and the family
   member) as testers and enable the build.
2. Install **TestFlight** from the App Store on your iPhone, sign in, and install
   Chronos.
3. Run the **real first-launch**: onboarding → grant Calendar & Reminders → the
   guided tour → calibration. Confirm it all flows, blocks/tasks save to your
   real Calendar/Reminders, notifications fire, and the Live Activity for the
   current block appears and **disappears on its own** when the block ends.
4. Fix anything, bump the **build number** (not the version), re-archive, re-upload.

---

## 13. Submit for review

1. App Store Connect → your app → the **1.0** version page.
2. Under **Build**, click **＋** (or "Add Build") and select the processed build.
3. Fill any remaining required fields (they're flagged).
4. **App Review Information:** add your contact email/phone. Chronos needs **no
   login**, so you can note "No account required" in the notes — reviewers like
   that.
5. **Version Release:** choose **Automatically release** after approval, or
   **Manually release** so you press the button.
6. Click **Add for Review** → **Submit for Review**.

**What to expect:** status goes *Waiting for Review → In Review → Approved* (or
*Rejected* with a note). Typically ~24–48 hours.

**Common rejection reasons to pre-empt (all already handled in this build):**
- Vague permission strings → yours are specific (step 4).
- Advertising features that don't work → Chronos+ is hidden in this build (step
  8: don't mention it in the description).
- Missing privacy policy → you hosted one (step 6).
- Broken links / placeholder content → none; support & privacy URLs resolve.
- Crash on launch → you verified via TestFlight (step 12).

If rejected, read the message in the **Resolution Center**, fix, and resubmit —
it's normal and usually quick the second time.

---

## 14. Release 🎉

- If you chose manual release, press **Release** on the version page once
  approved. The app appears on the App Store within a few hours.
- **Updates later:** bump the **Version** (e.g., 1.0 → 1.1) and **Build**, archive,
  upload, and submit again — same as steps 11–13.

---

## 15. LATER — transfer the app to your own account

Do this once **you** have your **own** paid Apple Developer account and the app
has been **released** (transfers require a released app and both sides on paid
memberships).

**A. Enroll your own account** (repeat step 1 under your own Apple ID + payment).

**B. Check transfer eligibility.** In the family member's App Store Connect →
your app → **App Information** → scroll to **Additional Information** →
**Transfer App**. Apple shows a **checklist of blockers**. Make sure:
   - The app has at least one **released** version.
   - No **CloudKit** is in use (you kept Chronos+ off — good; if you had enabled
     it, CloudKit containers complicate/block transfers).
   - No unresolved agreements, and you're not using capabilities that block
     transfer (Apple Pay merchant IDs, etc. — Chronos uses none).

**C. Start the transfer.** Click **Transfer App**. You'll enter the **recipient's
Team ID** (find yours in your own account: developer.apple.com → Membership →
Team ID) and the recipient Apple ID. Confirm.

**D. Accept on your side.** Sign in to **your** App Store Connect → **Agreements**
/ the pending transfer request → **Accept**, agree to the Paid/Free Apps
agreements (set up banking/tax if the app is paid; not needed for free). The app,
its versions, TestFlight, ratings, and bundle ID move to your account.

**E. Re-sign future updates from your account.** In Xcode, switch the targets'
**Team** to your own team, and future archives upload under you.

**F. Now add Chronos+ (optional).** Follow **`docs/CHRONOS_PLUS_SETUP.md`**: add
iCloud/CloudKit + App Groups + Game Center capabilities under **your** team, add
the `CHRONOS_PLUS` build flag, create the two Game Center leaderboards, and ship
an update. The previously-hidden Chronos+ UI switches on automatically, and you'll
update the App Privacy label (step 9) to disclose friend presence.

> **Timing tip:** transfers can take a little while to complete and the app stays
> live throughout. Don't start a transfer mid-review (finish/withdraw any pending
> submission first).

---

## 16. Quick FAQ

- **Do both people need to pay $99?** Yes, ultimately — the family member's
  account now, and your account to receive the transfer later. Each is
  $99/year.
- **Can I skip the family member and enroll myself?** Only if you're an adult
  enrolling under your own real identity. If the family-member requirement is
  about age/identity, use the transfer path above.
- **Will the app's reviews/downloads survive the transfer?** Yes — ratings,
  reviews, and history move with the app.
- **Can I enable Chronos+ before transferring?** You *can*, but **don't** — its
  CloudKit usage can make the app ineligible to transfer. Add it after.
- **What if "Chronos" is taken?** Use a distinct App Store **Name** (e.g.,
  "Chronos: Plan & Focus"); the on-device app name and bundle ID are separate.

---

## TL;DR checklist

1. Family member enrolls in the Apple Developer Program ($99). Wait for approval.
2. Xcode → sign in with their account → set Team + bundle IDs on both targets
   (no CloudKit yet).
3. Icon (1024²) + screenshots (6.7").
4. Host `docs/PRIVACY_POLICY.md` on GitHub Pages → get the URL.
5. App Store Connect → New App → fill metadata, age rating (4+), **App Privacy =
   Data Not Collected**, Privacy Policy URL.
6. Archive → Distribute → Upload → TestFlight → test the real first launch.
7. Submit for Review → Release.
8. **Later:** enroll your own account → Transfer App to yourself → add Chronos+ in
   an update (`docs/CHRONOS_PLUS_SETUP.md`).

Related: `docs/CHRONOS_PLUS_SETUP.md` (turning on the paid layer after transfer),
`docs/WIDGETS_SETUP.md` (widgets), `docs/PRIVACY_POLICY.md` (host this).
