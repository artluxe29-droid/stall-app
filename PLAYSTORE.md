# Putting Stall on Google Play

Stall goes on Google Play as a **Trusted Web Activity**: a small Android app that opens stall-app.pages.dev full screen, with no browser bar. Every update you make to the website shows up in the app straight away, so you only upload a new app build when Google requires it (about once a year).

The app is already prepared:
- the app manifest has a description, categories, shortcuts and screenshots
- `/.well-known/assetlinks.json` proves the app and the website belong together; you fill it in from **Admin → Settings → Android app**
- in-app account deletion (**Account → Delete my account**), which Google requires, plus a public page at `/delete-account`
- store graphics in [`store-assets/`](store-assets): six 1080×1920 phone screenshots and the 1024×500 feature graphic. The 512×512 icon is `icons/icon-512-v2.png`.

> **Decide your domain first.** The Android app is tied to one web address. If you plan to move from `stall-app.pages.dev` to your own domain (e.g. `stall.ng`), do that **before** packaging; otherwise you'll have to publish a new app later.

---

## 1. Create a Google Play developer account (once)

1. Go to <https://play.google.com/console/signup> and sign in with the Google account you want to own the app.
2. Choose **Personal** (just you) or **Organisation** (a registered business; needs a free D-U-N-S number).
3. Pay the one-time **$25** fee and complete identity verification (a Nigerian passport, driver's licence or NIN slip works).

**Important for new personal accounts:** before you can publish to everyone, Google requires a **closed test with at least 12 testers who stay opted in for 14 days in a row**. Line up 12+ friends or classmates with Android phones and Gmail addresses now.

## 2. Build the app with PWABuilder (free, in your browser)

1. Open <https://www.pwabuilder.com>, enter `https://stall-app.pages.dev` (or your own domain) and click **Start**.
2. Click **Package for stores**, then **Android → Generate package**.
3. Fill in:
   - **Package ID:** `app.stall.twa` (or `ng.stall.app`). This can never be changed later.
   - **App name:** `Stall – student marketplace` · **Launcher name:** `Stall`
   - **App version:** `1.0.0` · **Version code:** `1`
   - **Signing key:** *Create new*. Enter your name and a strong password, and keep it safe.
4. Download the zip. It contains:
   - `*.aab` — the file you upload to Google Play
   - `signing.keystore` and `signing-key-info.txt` — **your upload key and its passwords**
   - `assetlinks.json` — contains your package name and key fingerprint

> **Back up `signing.keystore` and `signing-key-info.txt` in two safe places** (e.g. Google Drive and a USB stick). You need them for every future update. **Never commit them to this GitHub repo**, and never send them to anyone.

## 3. Create the app in Play Console

1. **Create app:** name `Stall – student marketplace`, language English (United Kingdom or United States), **App**, **Free**. Accept the declarations.
2. Work through **Dashboard → Set up your app**:
   - **Privacy policy:** `https://stall-app.pages.dev/privacy`
   - **App access:** *All or some functionality is restricted* → add a test account the reviewers can sign in with: create a normal student account on Stall (e.g. phone `08000000000`, password of your choice) and give them those details plus "Sign in with the phone number and password".
   - **Ads:** No.
   - **Content rating:** fill in the questionnaire. Category **Shopping / marketplace**; users can interact and exchange messages; no violence or adult content.
   - **Target audience:** 18 and over (and 16–17 if you accept younger students). Not designed for children.
   - **News app:** No. **Government app:** No.
   - **Financial features:** the app takes payments for goods through a third-party processor (Paystack); it is not a bank, loan or crypto app.
   - **Data safety:** see the answers below.
   - **Data deletion:** *Yes, users can request deletion* → URL `https://stall-app.pages.dev/delete-account`. In-app deletion: Account → Delete my account.
3. **Store listing:** paste the text below, upload `icons/icon-512-v2.png` as the app icon, `store-assets/feature-graphic.png` as the feature graphic, and the six `store-assets/phone-*.png` files as phone screenshots. Category: **Shopping**. Contact email: your support email.

## 4. Upload, then link the app to the website

1. Go to **Test and release → Testing → Closed testing → Create track**, upload the `.aab`, add your testers' Gmail addresses, and roll it out.
2. Go to **Test and release → App integrity → App signing**. Copy the **SHA-256 certificate fingerprint** under *App signing key certificate*.
3. In Stall, open **Admin → Settings → Android app**:
   - **Package name:** the Package ID from step 2 (e.g. `app.stall.twa`)
   - **SHA-256 fingerprint(s):** paste the App signing fingerprint, then a comma, then the fingerprint from PWABuilder's `assetlinks.json` (your upload key) so test installs work too.
   - Save, then open the link under the form, `/.well-known/assetlinks.json`, and check it shows your package name.
4. Install the app from the closed-testing link. It should open full screen with **no address bar**. If you see an address bar, the fingerprint or package name doesn't match: check step 3.

## 5. Go live

After 14 days with 12+ testers opted in, Play Console unlocks **Apply for production**. Answer the short questions about your test, submit, and Google usually reviews within a few days.

**Updating later:** website changes appear in the app instantly. You only rebuild in PWABuilder (with the **same** signing key and a higher version code) when Google asks you to target a newer Android version, or if you change the app name or icon.

---

## If testers see "Unsafe app blocked" (Google Play Protect)

This message means someone installed the app **from a file you sent them** (an `.apk`), not from Google Play, and that file was built to target an older Android version. Since 2024, Play Protect blocks sideloaded apps that target old Android versions (below Android 13 / API 33 today, and the bar rises every year). It is not a virus warning about Stall.

How to fix it:

1. **Rebuild in PWABuilder** (section 2) with its current Android settings. They target the latest Android version automatically. Use the **same package ID and the same `signing.keystore`**, and a **higher version code** (e.g. `2`).
2. **Stop sending APK files.** Upload the new `.aab` to your **Closed testing** track and share the Play opt-in link with testers. Apps installed from Google Play are never blocked like this, and testers get updates automatically.
3. Testers who already have the old version should uninstall it first, then install from the Play link.
4. Until the Play test link is ready, testers can use the website instead: open the site in Chrome, then tap **⋮ → Install app** (or **Add to Home screen**). This doesn't trigger Play Protect.

Each year in August, Google raises the minimum Android version that apps must target. When Play Console warns you about it, rebuild in PWABuilder (same key, higher version code) and upload.

## Store listing text (ready to paste)

**App name (30 max):** `Stall – student marketplace`

**Short description (80 max):**
`Buy and sell on campus. Payments held until you get your item. Students only.`

**Full description:**

```
Stall is the marketplace for Nigerian students. Buy and sell textbooks, gadgets, fashion, hostel gear, food and services with students and campus shops at your school, across your state, or anywhere in Nigeria.

YOUR MONEY IS PROTECTED
• Pay by card, bank transfer or USSD through Paystack.
• Stall holds your money until you have your order. The seller is only paid when you hand over your release code or tap "I've got it".
• Something wrong? Report a problem and your money stays on hold while we sort it out, with a full refund if the item never came or wasn't as described.

SHOP YOUR CAMPUS
• See what students at your school are selling, or switch to your state or all of Nigeria.
• Search with filters for price, condition, verified sellers, sellers who deliver and 4★ ratings.
• Seller ratings and reviews from real buyers.
• Pick up on campus for free, or get it delivered to your hall.
• Track your order: paid, packed, on the way, delivered.

SELL IN A MINUTE
• Snap a photo, set a price, done. Listing single items is free.
• Open a store for your campus business and reach your whole state or the country.
• Get paid straight to your bank when the buyer gets their order.

SAFE BY DESIGN
• Chat with sellers inside Stall, so there's a record if anything goes wrong.
• Every new listing photo is checked before it goes live.
• Verified-seller badges and buyer reviews help you shop with confidence.

Stall is for students and campus vendors in Nigeria.
```

## Data safety answers

Data is **encrypted in transit** (HTTPS) and users **can request deletion** (in-app and at `/delete-account`). Stall does **not** sell data or share it for advertising.

| Data type | Collected | Shared | Why |
|---|---|---|---|
| Name | Yes | No | Account management |
| Email address | Yes | No | Account management |
| Phone number | Yes | No | Account management, sign-in |
| Address (delivery address) | Yes, optional | No | App functionality (delivery) |
| Other info (matric number, school) | Yes | No | Account management, fraud prevention |
| Financial info → purchase history | Yes | No | App functionality |
| Financial info → other (seller's bank account for payouts) | Yes, sellers only | Yes, with Paystack | App functionality (paying sellers) |
| Messages → other in-app messages (chats) | Yes | No | App functionality, fraud prevention |
| Photos (listing photos, ID card for verification) | Yes | No | App functionality, fraud prevention |
| App activity (orders, listings) | Yes | No | App functionality |

Card details are entered on Paystack's page and **never reach Stall**, so you don't declare card numbers. Paystack is a "service provider", which Google doesn't count as sharing.
