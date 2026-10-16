# Stall native app: rebuild plan

Status: **Phase 1 in progress.** Phase 0 is done (16 Oct 2026). Phase 1a (browsing) and 1b (accounts) are in the app; buying (1c) is next.

## Why

Stall is on Google Play today as a Trusted Web Activity (`android/`): an official Play Store app that runs the web app full screen. This plan replaces it with a **fully native app**, for smoother screens, better behaviour on low-end phones and offline, and a path to the iPhone App Store, while keeping everything that already works.

## Decisions

1. **Flutter** (in `mobile/`). One codebase builds the Android app now and the iPhone app later. It's fast on low-end Android, and GitHub builds it, so no Android Studio is needed.
2. **Keep the backend.** The native app uses the same API (`functions/api/[[path]].js`), so the business rules stay in one place: escrow, timers, strikes, fees, verification, schools, emails. Server switches (Close the app, short break message, Students can sell, school launch states) apply to the native app automatically.
3. **Admin stays on the web** (`stall.com.ng/staff`). About a third of the API is Admin and only staff use it; rebuilding it natively isn't worth it.
4. **Same Play Store listing.** The native app ships as `ng.com.stall.app`, the same package as the Trusted Web Activity, so users get it as an ordinary update with the same listing and reviews. Both must be signed with the same upload key.

## Phases

Estimates assume Claude writes most of the code and you test on a phone for a few hours a week.

| Phase | Scope | Time |
|---|---|---|
| **0. Groundwork** | Server: sign-in tokens for the app (alongside web cookies); Firebase Cloud Messaging push (alongside web push). App: Flutter project, Stall design system (colours, Bricolage Grotesque + Figtree, components), API client with secure token storage, splash, sign-in, signed-in shell. CI: GitHub builds and tests every change. | 2 weeks |
| **1. Buying** | Sign-up (school, matric, email code, student ID); home feed; search, filters, voice search; item and store pages; bag; Paystack checkout; orders with handover code, release and timers | 3 weeks |
| **2. Selling** | List item (photos, price hints, bulk add); my listings; open store (fee or free code); store management (items, logo, delivery); selling orders and stages; bank details and payouts; weekly statement | 3 weeks |
| **3. Trust and talk** | Chat; native notifications; report a problem with photo evidence; disputes; ratings and replies; strikes; live delivery tracking map | 2 weeks |
| **4. Everything else** | Collections; badges and milestones; receipt images; store QR cards; invites and referrals; how-to videos; partner banners; account settings and delete account; waitlist / Coming soon; break and closed screens; Students-can't-sell handling | 2 weeks |
| **5. Launch** | Testing on low-end phones; closed test (12 testers, 14 days); release as an update over the Trusted Web Activity | 2 weeks |
| **Later: iPhone** | Same Flutter code built on GitHub's macOS runners; Apple Developer account ($99/year) | about 2 weeks |

## Feature checklist (parity with the web app)

Tick each one only when it works in the native app against the live API.

- **Accounts:**
  - [x] Sign in and sign out
  - [x] Sign up: school pick, matric, email code
  - [x] Student verification: ID upload or school email
  - [x] Password reset flow (via support)
  - [ ] Delete account
- **Browse:**
  - [x] Home feed (school, state, everywhere)
  - [x] Categories
  - [x] Search with filters and sort
  - [x] Recent searches
  - [ ] Voice search
  - [x] Store search hits
- **Items and stores:**
  - [x] Item page and photos
  - [x] Seller rating
  - [x] Delivery info
  - [x] Store page, logo and items
  - [x] Founding Seller badge
  - [x] Share links
- **Buying:**
  - [ ] Bag
  - [ ] Checkout (pickup or delivery)
  - [ ] Consent
  - [ ] Paystack payment and return
  - [ ] Credit and fee display
- **Orders:**
  - [ ] Order list and detail
  - [ ] Timers
  - [ ] Release code / "I've got it"
  - [ ] Cancel
  - [ ] Report a problem with evidence
  - [ ] Ratings and buyer ratings
  - [ ] Receipts
- **Selling:**
  - [ ] List an item (photos, compression, price hint)
  - [ ] Bulk add
  - [ ] Stock
  - [ ] Mark sold
  - [ ] Delete
  - [ ] Seller rules consent and school-rules tick
- **Stores:**
  - [ ] Open a store (fee or free code)
  - [ ] Logo and icon
  - [ ] Items
  - [ ] Open/closed toggle
  - [ ] Delivery settings
  - [ ] Reach
  - [ ] Featured
  - [ ] Store QR card
- **Seller orders:**
  - [ ] Stages (packed, on the way, ready)
  - [ ] "I handed it over"
  - [ ] Pins and ETA
  - [ ] Live tracking
  - [ ] Payouts and bank details
  - [ ] Weekly statement
- **Chat:**
  - [ ] Threads
  - [ ] Messages
  - [ ] Report and block
- **Notifications:**
  - [ ] Native push (FCM)
  - [ ] In-app news dots
- **Collections:**
  - [ ] Create
  - [ ] Share link
  - [ ] Pay
  - [ ] Paid list
  - [ ] Close
  - [ ] No-fee accounts
- **Extras:**
  - [ ] Milestone badges and share images
  - [ ] Invite and referrals
  - [ ] How-to videos
  - [ ] Partner banners and reach stats
  - [ ] Guide
  - [ ] Help and support links
- **School states:**
  - [ ] Coming soon and waitlist
  - [ ] Sellers-only stage
  - [ ] Students-can't-sell
  - [x] Short break message
  - [x] Closed screen
- **Admin:** stays on the web (opened from the app for staff)

## Costs and trade-offs

- **Money:** Google Play $25 once. Firebase Cloud Messaging free. GitHub Actions free within the monthly allowance. Apple $99/year for iPhone.
- **Updates go through store review** (usually hours to a day), unlike the web app's instant updates.
- **New features are built twice:** native app and website (which stays for computers and Admin).

## Phase 0 setup you'll need to do (once)

1. **Firebase project** (free): <https://console.firebase.google.com>
   1. Add project "Stall".
   2. Add an Android app with package `ng.com.stall.app`, and download `google-services.json`.
   3. In Project settings → Service accounts → **Generate new private key**.
   4. In Cloudflare, add that JSON as a **Secret** called `FCM_SERVICE_ACCOUNT`.
   5. In GitHub, add the content of `google-services.json` as a repository secret called `GOOGLE_SERVICES_JSON`.
2. The upload key secrets from `android/README.md` are shared by both apps, so the native app can replace the Trusted Web Activity on Google Play.
