# Quiet Cast iOS — Ship checklist

A native SwiftUI app (no webview) for Quiet Cast, in `ios/` alongside `studio/`. It talks to the
**same** backends as the web app — Sanity CDN (read-only content) and Supabase (auth + RLS) — and
streams audio with `AVPlayer` for real background playback. The project is generated from
`project.yml` by **XcodeGen**; build/verify headlessly with `xcodebuild` + `xcrun simctl`.

```
cd ios
xcodegen generate            # regenerate QuietCast.xcodeproj from project.yml
open QuietCast.xcodeproj      # or build headlessly (see below)
```

Bundle id: **`art.quietcast.app`** · Display name: **Quiet Cast** · iPhone-only, portrait, iOS 17+.

---

## Status (verified 2026-06-12)

- ✅ **Builds clean headlessly** — `xcodebuild … -destination 'generic/platform=iOS Simulator'` →
  `** BUILD SUCCEEDED **`, zero warnings of note. supabase-swift 2.47.0 resolves via SPM.
- ✅ **Boots in the simulator** (iPhone 16 Pro, iOS 26.5) and renders the full Cold Ember system —
  Cormorant Garamond display caps, Spectral body, IBM Plex Mono labels, fog + grain, the rationed
  ember accent.
- ✅ **Screenshots in BOTH themes with real data** — `ios/screenshots/` (sign-in, every tab, show
  detail, and the now-playing player; dark + light). Light correctly flips canvas→bone, ink→#26231b,
  ember→#84592e with the on-ember bone flip, and honors the one-warm-accent law. The now-playing view
  is identical in both app themes, confirming the theme-invariant over-art surface.
- ✅ **Anonymous reads + audio playback exercised against the real backends, in the simulator** —
  the broadcast grid, archive ledger ("13 shows · 2020–2021 · 162 tracks"), interviews list (QC-003
  correctly excluded — no Q&A), and a show detail all render live Sanity content, and a real episode
  streams (the now-playing pause state is live audio from `cdn.sanity.io`). Supabase REST responds
  with the anon key.
- ℹ️ **Simulator-trust note (this dev box only).** The machine routes HTTPS through a Cloudflare
  Gateway MITM proxy; the iOS simulator's separate trust store had to be told to trust that proxy
  root (`xcrun simctl keychain <sim> add-root-cert <gateway-ca.pem>`) before in-sim requests
  succeeded. This is a **verification-only** step — **nothing is shipped to work around it**: the app
  uses standard ATS (no exceptions, no disabled validation). On a real device / in production (no
  MITM proxy) requests succeed normally. (`.certs/ca.pem` is a 250 KB *bundle*; `add-root-cert` only
  installs its first cert, so the actual Gateway root must be extracted from the served chain.)
- ⛔ **Authenticated flows not exercised end-to-end** — sign-in needs a real inbox to receive the
  6-digit OTP. The sign-in UI, settings, wall, favorites, listen-sync, report/block, and account
  deletion are implemented against the documented RLS contract (`ios/spec/*.md`) and the anonymous
  read paths are verified, but the signed-in paths have not been run against a live session. Exercise
  them on a device with your email + the email-template fix below.

---

## Human steps to ship (in your hands)

### 1. Signing
Open `QuietCast.xcodeproj` in Xcode → target **QuietCast** → Signing & Capabilities → select your
**Team**; automatic signing is on. Confirm the bundle id `art.quietcast.app` is registered to your
account (or change it in `project.yml` and re-run `xcodegen generate`).

### 2. Supabase email template — add the OTP token
The iOS sign-in is **email OTP** (`signInWithOTP` → `verifyOTP(type: .email)`): the user types a
6-digit code, not a magic link. Supabase's default "Magic Link" template only contains
`{{ .ConfirmationURL }}`. In the Supabase dashboard → **Authentication → Email Templates → Magic
Link**, add the code, e.g.:

> Your Quiet Cast code is `{{ .Token }}`

Without `{{ .Token }}` in the template, no code arrives and OTP sign-in can't complete.

### 3. Deploy the account-deletion endpoint
A new Astro route `src/pages/api/account/delete.ts` is added for **in-app account deletion**
(App Store 5.1.1(v)). It validates an `Authorization: Bearer <supabase access token>` with
`auth.getUser(jwt)`, requires `{"confirm":"DELETE"}`, then runs the same service-role
`admin.deleteUser()` + DB cascade as the web settings flow. It does **not** weaken RLS.
- `npm run check` passes (0 errors) and the web app is unaffected.
- **Deploy the web app** so the endpoint is live at `https://quietcast.art/api/account/delete`
  before submitting the iOS app. The iOS client targets that host (`Config.webAppBase`, overridable
  with the `QC_WEB_BASE` env var for testing).
- Ensure `SUPABASE_SERVICE_ROLE_KEY` is set in the Cloudflare Worker env (already required by the
  web settings delete flow). R2 objects under `user/<uid>/` are intentionally **not** deleted (same
  as web — fold into the pending R2 cleanup pass).

### 4. App Store Connect — listing
- Create the app record with bundle id `art.quietcast.app`, name **Quiet Cast**.
- **Category:** Music.
- **Age rating questionnaire — answer for UGC** (the app shows user-generated mixes, posts, lists,
  photos, profiles, and a comment wall):
  - "Does your app contain user-generated content?" → **Yes**.
  - Declare the moderation methods present (see review notes): a method to report content, a method
    to block abusive users, and the ability to remove content. This typically lands the app at a
    **12+** rating; answer the violence/sexual/etc. content questions **None** unless your community
    guidelines say otherwise.
- **App Privacy ("nutrition labels"):** the bundled `PrivacyInfo.xcprivacy` already declares
  Email address, Other user content, and User ID — all *linked to identity*, *not used for
  tracking*, purpose *App Functionality*. Mirror these in App Store Connect → App Privacy. No
  tracking, no third-party SDKs beyond Supabase.

### 5. Review notes (paste into "Notes for Review")
- **Not a repackaged website (4.2):** native SwiftUI; the reason it exists as an app is real
  background audio (lock-screen / Control Center transport, interruption + route-change handling).
- **UGC moderation (1.2), all present in-app:**
  - *Report content* — every community detail screen (mix/post/list/album) and every wall note has
    a Report action that files into the `reports` table.
  - *Block users* — the "…" menu on others' content and profiles blocks the author (`blocks` table;
    gates messaging and wall posts both directions).
  - *Remove content* — wall-note authors and wall owners can delete notes; piece authors can take
    their own pieces private.
- **Account deletion (5.1.1(v)):** Settings → **Delete account** (type `DELETE` to confirm) →
  `POST /api/account/delete`. Permanently removes the account and all owned rows.
- **Sign-in (4.8 N/A):** first-party email OTP only — no third-party/social login, so Sign in with
  Apple is not required. **Provide the reviewer a demo email** they can receive the 6-digit code at,
  or a pre-provisioned account, since there's no password.

### 6. TestFlight → submit
Archive (Product → Archive) → upload to App Store Connect → TestFlight internal test (verify
background audio, OTP sign-in with the template fix, account deletion) → submit for review.

---

## Headless build / verify reference

```bash
cd ios
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodegen generate
xcodebuild -project QuietCast.xcodeproj -scheme QuietCast \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build build
# boot + run:
xcrun simctl boot "iPhone 16 Pro"            # any iOS 26.5 iPhone sim
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/QuietCast.app
xcrun simctl launch booted art.quietcast.app
# screenshot args (for QA): -qc-theme dark|light  -qc-tab listen|archive|interviews|community|you
```

Note on this machine: Xcode 26.5 ships only the iOS 26.5 SDK; the old iOS 17.x simulator runtimes
were removed (incompatible) and the iOS 26.5 simulator runtime was downloaded via
`xcodebuild -downloadPlatform iOS`. Deployment target stays iOS 17.0.

---

## In the build already (compliance)

- `PrivacyInfo.xcprivacy` — required-reason API declarations (UserDefaults `CA92.1`, file-timestamp
  `C617.1`) + collected-data types.
- `ITSAppUsesNonExemptEncryption = NO` (Info.plist) — no export-compliance prompt.
- `UIBackgroundModes: [audio]`, `AVAudioSession.playback` — real background playback.
- Cold Ember app icon (generated, `ios/tools/make_icon.py`), launch screen (`LaunchBackground`
  color), portrait-only, iPhone-only.
- Fonts bundled under `Resources/Fonts/` with OFL licenses: Cormorant Garamond, Spectral, IBM Plex
  Mono (PostScript names verified to match `QCFont`).

---

## v1 scope delivered

- **Listen** — broadcasts grid, show detail (tracklist + Q&A), favorites, listen-state overlay,
  full background playback with now-playing/lock-screen transport, resume + progress sync.
- **Archive** — chronological day-grid ledger (air-date coalesce quirk honored).
- **Interviews** — Q&A episodes (cat asc).
- **Community** — published mixes (playable), posts (tiny-markdown subset → AttributedString),
  lists, photo albums; report + visibility toggle per piece.
- **Profiles** — public `/u/[id]` + own dashboard, read-only rotation grid (snapshot listener
  pins), comment wall (read/post/delete/report), profile song, site news, activity feed.
- **Account** — email-OTP sign-in, settings (display name, status, bio, public/private, theme
  sync), block users, sign out, in-app account deletion.
- **Design** — Cold Ember tokens ported 1:1 (dark default + light opt-in + theme-invariant over-art
  palette for the now-playing surface).

## Deferred to v1.1 (do not build now)

Uploads (mix/cover/photo presign is cookie-session-only — needs an iOS-facing presign endpoint),
playlist management, rotation reordering / pinning / unpinning from iOS, DMs, admin moderation
(stays on web). The rotation grid ships **read-only** in v1.

## Known data caveats (from the content contract)

- The Sanity studio schema file is **stale** vs. the live dataset (the app reads `artist`/`cover`/
  `audio`/`tracklist` which exist live but not in the checked-in schema). Content is isolated behind
  one `SanityService` for the planned Phase-3 document remodel.
- Episode `airDate` falls back to `_createdAt` (GROQ `coalesce`); the back catalog clusters on
  2020-12-30/31 import days until real air dates are backfilled. The archive groups by exact day and
  tolerates multiple shows per day.
- `cdn.quietcast.art` (R2 custom domain for UGC audio/images) was answering a Vercel 404 on
  2026-06-12 — confirm it points at the R2 bucket before community mixes will play.
