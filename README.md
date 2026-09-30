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

Orders are paid only through Paystack split payments: each seller's checked payout account gets a Paystack subaccount, Stall keeps 5% of the order (max ₦2,000, set in `COMMISSION`) and pays Paystack's fee from it, and Paystack settles the rest to the seller. There is no bank-transfer or receipt option. Sellers whose account name was typed by hand can't be bought from until an admin confirms them in Payouts.

For heavy traffic use the Workers Paid plan (the free plan allows 100,000 requests a day) and a custom domain
(Cloudflare's edge cache, used for photos and shop pages, works on custom domains).

Never commit secret keys to this repo.
