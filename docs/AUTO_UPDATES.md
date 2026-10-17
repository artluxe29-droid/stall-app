# Automatic app updates

Today every new build of the native app is a file you download and install by hand. Each test build is signed with a different throwaway key, so the phone won't let one replace the last, and you have to uninstall first.

Once the steps below are done, it works like any Play Store app:

1. A change to the app is merged into `main`.
2. GitHub builds it, signs it with Stall's upload key, and sends it to **Google Play internal testing** by itself (the "Send to Google Play" step in `.github/workflows/mobile.yml`).
3. Within minutes to a few hours, Google Play updates the app on every tester's phone. Nobody downloads anything.

Internal testing goes live without a Google review and allows up to 100 testers. When you're ready for the public, promote a build to Production in Play Console, or set the repository variable `PLAY_TRACK` to `production`.

## One-time setup (about an hour, mostly waiting for Google)

You do these steps yourself: they involve payments, passwords and keys, which should never pass through chat.

### 1. Google Play developer account
- Go to play.google.com/console and sign up as an **organisation** (Stall Technologies Limited). It's a one-off **$25**. Google checks your identity and your D-U-N-S number. This can take a few days.

### 2. The upload key (if you haven't already)
- GitHub → **Actions** → **Android upload key** → **Run workflow**. It creates the key and tells you which 4 secrets to add.
- Add them under GitHub → **Settings** → **Secrets and variables** → **Actions**: `STALL_KEYSTORE_BASE64`, `STALL_KEYSTORE_PASSWORD`, `STALL_KEY_ALIAS`, `STALL_KEY_PASSWORD`.
- Keep a copy of the key file and its passwords somewhere safe offline. If you lose it, you can ask Google to reset it, but that takes days.

### 3. Create the app and upload the first build by hand
Google only accepts automatic uploads after the app exists and has one build.
- In Play Console: **Create app** → name "Stall", app, free. Fill in the store listing from `PLAYSTORE.md`.
- GitHub → **Actions** → **Native app** → open the latest run on `main` → download `stall-native-…` → unzip it → `app-release.aab`.
- Play Console → **Testing** → **Internal testing** → **Create new release** → upload `app-release.aab` → **Save** → **Review release** → **Start rollout**.
- Choose **Let Google manage and protect your app signing key** when it asks (the recommended option).

### 4. Add testers
- **Internal testing** → **Testers** → create an email list (your Gmail and the team's) → save.
- Copy the **opt-in link**, open it on each phone with that Gmail signed in to the Play Store, tap **Become a tester**, then install Stall from the Play Store.
- If the old test APK is on the phone, uninstall it first. This is the last time you'll need to.

### 5. Let GitHub upload for you
- In Google Cloud Console (console.cloud.google.com), with the project Play Console linked: **IAM & Admin** → **Service accounts** → **Create service account** (e.g. `github-uploads`) → open it → **Keys** → **Add key** → **JSON**. A `.json` file downloads.
- Play Console → **Users and permissions** → **Invite new users** → paste the service account's email → under **App permissions** add Stall with **Release apps to testing tracks** → **Invite user**.
- GitHub → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**: name `PLAY_SERVICE_ACCOUNT_JSON`, value: the whole contents of the `.json` file. Then delete the file from your computer.

That's it. The next change to the app merged into `main` reaches testers' phones by itself.

### If an upload fails
- **"Only releases with status draft may be created on draft app"**: Google hasn't finished reviewing the app's first release yet. Add the repository **variable** (not secret) `PLAY_RELEASE_STATUS` = `draft` until it has, then delete it.
- **"The caller does not have permission"**: the service account's invite in step 5 isn't accepted yet, or it's missing the release permission. It can take up to a day to start working.
- **"Version code … has already been used"**: someone uploaded a build by hand with a higher number. Automatic builds use 1000 plus the run number. Run **Native app** by hand once with a higher version code.

## Another option: Firebase App Distribution

This is free, with no Play account. Testers install the Firebase "App Tester" app, which shows a notification for each new build. They still tap to install each update, so it isn't fully automatic. Google Play internal testing is better because updates really are automatic, and it's the same listing you'll launch on.
