# Stall – ACU campus marketplace

Single-page marketplace (`index.html`) with a Paystack checkout backend running as a Cloudflare Pages Function.

## Structure
- `index.html` – the app
- `manifest.webmanifest`, `sw.js`, `icons/` – PWA install + offline shell
- `functions/api/[[path]].js` – `/api/checkout` and `/api/verify` (Paystack)

## Deploy (Cloudflare Pages)
1. Connect this repo in Cloudflare Pages (no build command, output directory `/`).
2. Add the environment secret `PAYSTACK_SECRET` (`sk_test_...` first, `sk_live_...` when going live).

Never commit secret keys to this repo.
