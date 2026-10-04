# Stall brand

## Logo
- **Icon:** the awning (Stall's roof) over a dot (your money, held safely). Thin gaps between the three scallops keep it readable in one colour.
- **Lockup (icon + wordmark together):** use the plain wordmark, "stall." in Bricolage Grotesque. Don't repeat the awning on the l's.
- **Wordmark on its own:** use the Posts wordmark, where the two l's are the stall's posts holding up the awning.
- **One colour, always.** The icon and wordmark are a single colour: indigo, cream, white or black. Never mix colours inside the logo.
- **Boxed icon** (icon on an indigo tile) is only for the phone app icon and favicon.

## Files (`icons/`)
- Icon: `stall-mark.svg` (indigo), `stall-mark-cream.svg`, `stall-mark-white.svg`, `stall-mark-black.svg`
- Posts wordmark: `wordmark-{indigo,cream,white,black}.svg`, and `wordmark-indigo-lime.svg` (lime full stop)
- Plain wordmark (for lockups): `wordmark-plain-{indigo,cream,white,black}.svg`

## Colours
Indigo `#26306E` (main), Lime `#C8F03C` (spark for buttons and highlights, not for the logo), Cream `#F6F1E7`, Night `#141A3D`, Ink `#161A33`, Slate `#5B6077`, Mist `#E4E7F7`, Coral `#D93F3F` (problems).

## Fonts
Bricolage Grotesque (headlines, prices) and Figtree (everything else), self-hosted in `brand/fonts` under the SIL Open Font License.

## Icons
Rounded 2px line on a 24px grid with one signature dot. Used in the app's icon set, tab bar and the website.

## Receipts
Built once on the server (`receiptFor` and `rcHtml` in `functions/api/[[path]].js`) and used in both the receipt emails and the app's receipt sheet, from email-safe tables and the PNGs in `icons/receipt/`.
- **Awning stripe**: buyer receipts by day, and every seller payout. The awning sits on top, the icon below it, the Posts wordmark at the foot.
- **Night**: buyer receipts for orders paid between 7pm and 6am (Lagos time).
- **Full stops**: refunds.
- **Weekly statement**: sellers. It shows in Orders to fulfil and is emailed every Monday for the week before.
- Admin → Email → **Send sample receipts** sends one of each.
- **Payments to Stall** (featuring, store reach, verified badge, store fee) and class collections also get an Awning stripe (or Night) receipt. You can find them again in Account → Payments.
