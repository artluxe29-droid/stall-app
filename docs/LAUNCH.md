# Launching the Stall app on Google Play

The native app (`mobile/`) does everything the website app does for buyers and sellers. Admin stays on the website. This is the checklist to get it onto phones through Google Play, in order. Each step says who does it.

The store listing text, graphics and Data safety answers are in [`PLAYSTORE.md`](../PLAYSTORE.md). They were written for the earlier website-in-an-app version, but the answers are kept up to date for the native app.

## 1. Accounts and keys (you, once)

1. **Google Play developer account**, $25 once: <https://play.google.com/console/signup>.
   Register as an **Organisation** (Stall Technologies Limited, with your CAC details and a free D-U-N-S number). Google makes new **personal** accounts run a closed test with 12 testers for 14 days before going public; organisation accounts skip that.
2. **Upload key:** GitHub → Actions → **Android upload key** → Run workflow, then add the 4 secrets it lists (`STALL_KEYSTORE_BASE64`, `STALL_KEYSTORE_PASSWORD`, `STALL_KEY_ALIAS`, `STALL_KEY_PASSWORD`). Keep a copy of the key file and passwords offline.
   - If the old website-in-an-app version (`android/`) is **already on Google Play**, don't make a new key: use the same 4 secrets it was built with. The native app ships as an update to it (same package, `ng.com.stall.app`), and Google only accepts updates signed with the same upload key.
3. **Push notifications (Firebase, free):** follow "Phase 0 setup" in [`NATIVE_APP_PLAN.md`](NATIVE_APP_PLAN.md):
   - `FCM_SERVICE_ACCOUNT` as a **Secret** in Cloudflare;
   - `GOOGLE_SERVICES_JSON` as a secret in GitHub.

After step 2, the next build log no longer says "uses a test key". After step 3, it no longer says "no push notifications".

## 2. First upload (you, once)

1. Make sure a build has run on `main` since the secrets were added: GitHub → Actions → **Native app**, newest green run. Download `stall-native-…` and unzip it.
2. Play Console → **Create app** (if it isn't there yet) → work through **Set up your app** with the answers in `PLAYSTORE.md`:
   - privacy policy `https://stall.com.ng/privacy`;
   - data deletion `https://stall.com.ng/delete-account`;
   - a reviewer test account;
   - content rating, target audience 16+, the financial features answer, and Data safety.
3. **Test and release → Testing → Internal testing → Create new release** → upload `app-release.aab` → roll out. Choose **Let Google manage your app signing key** when asked.
4. **Testers:** add your team's Gmail addresses, open the opt-in link on each phone, and install from the Play Store. Uninstall any test APK first, one last time.
5. **Automatic updates from then on:** add the `PLAY_SERVICE_ACCOUNT_JSON` secret ([`AUTO_UPDATES.md`](AUTO_UPDATES.md)). Every change merged to `main` then reaches testers by itself.

## 3. Test on real phones (you and your testers, about a week)

**Play's pre-launch report** (Play Console → Testing → Pre-launch report) runs every upload on a range of real phones, including cheap ones, for free. Fix anything it lists as a crash or "not responding"; send me the details.

Then try these on the cheapest phone you can borrow (2 GB of memory, Android 8 to 10):

- [ ] Sign up as Personal, then as Business; pick a state and area; tick "I'm a student" and pick a school.
- [ ] Scroll a long Home feed and search, including the mic. It shouldn't stutter or crash.
- [ ] Post an item with photos from the camera; add several at once.
- [ ] Buy something small with a real card on Paystack, then receive it: release code, rating, receipt.
- [ ] As the seller: packed → out for delivery → share location on the map → hand over → get paid.
- [ ] Chat, report a problem with a photo, see both sides.
- [ ] Open a store with a free code; add items; QR card.
- [ ] Turn data off and on mid-way: you should see a clear message, not a crash.
- [ ] Notifications arrive with the app closed, and tapping one opens the right order or chat.
- [ ] Reopen the app on mobile data: photos you've seen load instantly without using data again.

The app runs on Android 7.0 and newer.

## 4. Go live (you)

1. **Production → Create new release** → **Add from library** (the build your testers used) → release notes → **Staged rollout at 20%**. Google reviews it, usually within a few days.
2. Watch **Quality → Android vitals** for crashes for 2 to 3 days, then raise the rollout to 50%, then 100%.
3. Point the website at the store: Stall → **Admin → Settings → Android app → Google Play link**. The website's "Get the app" buttons switch to the Play Store.
4. If the website-in-an-app version was on Google Play, its users get the native app as a normal update. They sign in once in the new app; their account, orders and store are all there.

## After launch

- **Updates:** merge to `main` → testers get it automatically → promote the same build to Production in Play Console when you're happy.
- **Every August** Google raises the Android version apps must target. When Play Console warns you, tell me and I'll update `mobile/`.
- **Not yet in the app:** opening stall.com.ng links straight in the app (they open the website for now), the how-to videos (link them from Help once they're posted), and an iPhone version (same code, needs an Apple Developer account, $99 a year).
