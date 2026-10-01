# Stall – student marketplace for schools across Nigeria

Single-page web app (`index.html`) with an API running as a Cloudflare Pages Function (`functions/api/[[path]].js`).

## Structure
- `index.html` – the app; `install.html` – install page with QR code and poster (`qr.js`)
- `rules.html`, `terms.html`, `privacy.html` (+ `policy.css`, `policy.js`) – policies
- `functions/api/[[path]].js` – all API routes; `lib/schools.js` – starter list of Nigerian schools
- `manifest.webmanifest`, `sw.js`, `icons/` – installable app
- `_headers` – security headers for every page
- `schema.sql` – full database schema (the app also creates missing tables/columns itself); `indexes.sql` – extra indexes

## Cloudflare Pages setup (Settings → Bindings / Variables, Production)
| Name | Type | Needed for |
|---|---|---|
| `DB` | D1 database | everything |
| `PAYSTACK_SECRET` | Secret | payments and bank account-name checks (`sk_live_...` for real money) |
| `AI` | Workers AI | automatic listing-photo and verification checks |
| `PHOTOS` | R2 bucket | photo storage (recommended; without it photos stay in D1) |
| `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID` | Secrets | admin alerts (optional) |

Paystack dashboard → Settings → API Keys & Webhooks → Webhook URL: `https://<your-domain>/api/paystack/webhook`

Order payments are held by Stall: the buyer pays the full amount into Stall's Paystack balance, and the seller is paid by Paystack Transfer (total minus 5% of the items, max ₦2,000) when the order is released — release code, buyer taps "I've got it", or automatically after `HOLD_DAYS` (7) with no problem reported. Buyers can report a problem (money stays on hold until an admin pays the seller or refunds), and sellers can cancel (buyer refunded via the Paystack Refund API). Failed payouts show in Admin → Seller pay with Retry / "I paid by hand".

Paystack setup for this: enable **Transfers**, set settlements to stay in your **Paystack balance** (so there is money to pay sellers from), turn off **OTP for transfers** (Settings → Preferences), and add the webhook URL above — it also reports transfer results (`transfer.success`, `transfer.failed`, `transfer.reversed`).

For heavy traffic use the Workers Paid plan (the free plan allows 100,000 requests a day) and a custom domain
(Cloudflare's edge cache, used for photos and shop pages, works on custom domains).

Never commit secret keys to this repo.

## Google Play

See [PLAYSTORE.md](PLAYSTORE.md) for packaging Stall as an Android app (PWABuilder), the Play Console checklist, store listing text and Data safety answers. Store graphics are in `store-assets/`.
