# Stall Android app

The Stall Android app is a **Trusted Web Activity (TWA)**: a real Android app, installed from Google Play, that runs the Stall web app (`https://stall.com.ng/app`) full screen, with no browser bar.

- **Every feature of the web app is in the Android app**, because it *is* the web app: shopping, selling, stores, chat, payments, orders, live delivery tracking, collections, Admin, everything.
- **Web updates reach the app instantly.** You only build a new app version when Google requires a newer Android target (about once a year), or to change the app's name or icon.
- **Notifications and location work natively**: order and message notifications show as Android notifications, and live tracking uses the phone's location (the user is asked first).
- **Stall links open in the app**: items, orders, collections and payment returns on `stall.com.ng` open in the app if it's installed.

| | |
|---|---|
| Package name | `ng.com.stall.app` (permanent: it can never change once on Google Play) |
| Opens | `https://stall.com.ng/app` |
| Minimum Android | 6.0 (API 23) |
| Target Android | 16 (API 36) |

You never need Android Studio: **GitHub builds the app for you.**

---

## 1. Create the upload key (once)

The upload key signs the app files you upload to Google Play.

1. On GitHub, open the repo → **Actions** → **Android upload key** → **Run workflow**. Type `MAKE A NEW KEY` and run it.
2. When it finishes (about a minute), open the run and download **stall-upload-key** at the bottom. GitHub deletes it after 1 day.
3. Unzip it and open `README-KEEP-PRIVATE.txt`. **Back up the whole folder in two safe places** (e.g. Google Drive and a USB stick). Never send it to anyone or put it in the repo.
4. Repo → **Settings → Secrets and variables → Actions → New repository secret**. Add these four, exactly as the README file says:
   - `STALL_KEYSTORE_BASE64`: the whole content of `STALL_KEYSTORE_BASE64.txt`
   - `STALL_KEYSTORE_PASSWORD`
   - `STALL_KEY_ALIAS`: `upload`
   - `STALL_KEY_PASSWORD`

> Google Play App Signing keeps the real app key. If you ever lose the upload key, Play Console lets you reset it, so you won't lose the app.

## 2. Build the app

1. Repo → **Actions** → **Android app** → **Run workflow**.
   - **Version code**: `1` for the first upload, then 1 higher every time (2, 3, …).
   - **Version name**: what users see, e.g. `1.0.0`.
2. When it finishes, download **stall-android-1.0.0** at the bottom of the run. It contains:
   - `app-release.aab`: **the file you upload to Google Play**
   - `app-release.apk`: install it straight onto an Android phone to try it
3. The run's log also shows the upload key's **SHA-256 fingerprint** (step "Show the signing fingerprint").

The app is also built automatically whenever anything in `android/` changes, so a broken change shows up straight away.

## 3. Link the app and the website

So the app opens full screen (without a browser bar), stall.com.ng must say it trusts the app:

1. In Stall, open **Admin → Settings → Android app**.
2. **Package name**: `ng.com.stall.app`
3. **SHA-256 fingerprint(s)**: paste the upload key fingerprint. After the first upload to Google Play, also add the **App signing key** fingerprint from Play Console → Test and release → **App integrity** → App signing, separated by a comma.
4. Save, then open `https://stall.com.ng/.well-known/assetlinks.json`. It should show the package name and fingerprints.

If the app shows a browser bar at the top, the package name or a fingerprint doesn't match.

## 4. Publish on Google Play

Follow [`PLAYSTORE.md`](../PLAYSTORE.md) (developer account, store listing, data safety, closed testing with 12 testers for 14 days), uploading `app-release.aab` from step 2.

## 5. Point the website at the store

When the app is live, copy its Play Store link (e.g. `https://play.google.com/store/apps/details?id=ng.com.stall.app`) into **Admin → Settings → Android app → Google Play link**, and save.

From then on:
- the website's **Get the app** section shows **Get it on Google Play** on Android phones (and a QR code plus the button on computers);
- the install page (`/install`) shows the Play button;
- the app's **Get the Stall app** card says "Free on Google Play" and opens the store.

iPhones keep the "Add to Home Screen" steps until you add an **App Store link** in the same place.

## iPhone (later)

Apple doesn't support Trusted Web Activities. When you're ready for the App Store, the usual route is a small iOS wrapper app (for example with Capacitor or PWABuilder's iOS package) that loads the same web app, built on a Mac and published with an Apple Developer account ($99/year). Apple reviews these more strictly: the app must feel like a real app, which Stall's full-screen, app-style design already does. Once it's live, paste the App Store link in Admin and the website switches over automatically.

## Updating the app later

- **Web changes** (features, fixes, design): nothing to do. They appear in the app straight away.
- **New app version** (Google's yearly target-Android requirement, a new icon or name): change what's needed in `android/`, run **Android app** with a version code 1 higher than the last one, and upload the new `.aab` in Play Console.
