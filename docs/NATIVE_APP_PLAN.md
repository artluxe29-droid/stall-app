# Stall native app: rebuild plan

Status: **Phase 5 (launch) next.** Phase 4 is done except voice search, bulk add and the how-to videos. Phase 3 (chat, problem reports, review replies, strikes notice, live map, push notifications) is in the app; Phase 4 is next. Phases 0, 1 and 2 are done: browsing, accounts, buying, selling items, selling orders and payouts, and opening and running a store. The app also has "open to everyone": personal and business sign-up with state and area, an optional student tick, the My area feed, and the My area and Student settings. Updates can reach phones automatically through Google Play internal testing (docs/AUTO_UPDATES.md).

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
  - [x] Delete account
  - [x] Email updates on/off
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
  - [x] Bag
  - [x] Checkout (pickup or delivery)
  - [x] Consent
  - [x] Paystack payment and return
  - [x] Credit and fee display
- **Orders:**
  - [x] Order list and detail
  - [x] Timers
  - [x] Release code / "I've got it"
  - [x] Cancel
  - [x] Report a problem with evidence
  - [x] Ratings and buyer ratings
  - [x] Answer a problem report, see both sides, object to a no-show
  - [x] Receipts
- **Selling:**
  - [x] List an item (photos, compression, price hint)
  - [ ] Bulk add
  - [x] Stock
  - [x] Mark sold
  - [x] Delete
  - [x] Seller rules consent and school-rules tick
- **Stores:**
  - [x] Open a store (fee or free code)
  - [x] Logo and icon
  - [x] Items (add, stock, sold out, delete)
  - [x] Open/closed toggle
  - [x] Delivery settings
  - [x] Reach
  - [x] Featured
  - [x] Share link
  - [x] Store QR card
  - [x] Pay part with Stall credit
- **Seller orders:**
  - [x] Stages (packed, on the way, ready)
  - [x] "I handed it over"
  - [x] Arrival time ("10 min away", "I'm here")
  - [x] Meeting-spot pins
  - [x] Live tracking (map, share location while the screen is open)
  - [x] Payouts and bank details
  - [x] Weekly statement
  - [x] Answer a problem report: accept and refund, or give your side with a photo
- **Chat:**
  - [x] Threads
  - [x] Messages
  - [x] Report and block
- **Trust:**
  - [x] Review replies
  - [x] Paused-for-strikes notice
- **Notifications:**
  - [x] Native push (FCM): on once the Firebase setup below is done
  - [ ] In-app news dots
- **Collections:**
  - [x] Create
  - [x] Share link
  - [x] Pay
  - [x] Paid list (and tick off who collected)
  - [x] Close
  - [x] No-fee accounts (the server leaves out the charge)
- **Extras:**
  - [x] Milestone badges (shared as text; the website's badge picture comes later)
  - [x] Invite and referrals (code at sign-up, credit)
  - [ ] How-to videos
  - [x] Partner banners and reach stats
  - [x] Payments to Stall, with receipts
  - [x] Guide
  - [x] Help and support links
- **School states:**
  - [x] Coming soon and waitlist (retired when Stall opened to everyone)
  - [x] Sellers-only stage (retired)
  - [x] Students-can't-sell (the server's message shows when selling)
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
   5. In GitHub, add the content of `google-services.json` as a repository secret called `GOOGLE_SERVICES_JSON`. The next app build then has push notifications (the build log says so if the secret is missing).
2. The upload key secrets from `android/README.md` are shared by both apps, so the native app can replace the Trusted Web Activity on Google Play.
