// Website at stall.ng/, app at /app.
// - "/" with no query shows the website (welcome.html) when it's switched on in Admin -> Settings, otherwise the app.
//   Any query string (?go=, ?reference=, ?collect=, ?l=, …) is a deep link or payment return, so it always opens the app.
// - "/app" is always the app; "/welcome" is always the website (a private preview while it's switched off).
// - "/install" goes to the website's install section when the website is on (posters and old links keep working).
// Only these paths run this code (see _routes.json), so photos, scripts and styles are served directly.
let ON = null, AT = 0;
async function siteOn(env) {
  if (ON !== null && Date.now() - AT < 30e3) return ON;
  try { const r = await env.DB.prepare("SELECT v FROM settings WHERE k='site_on'").first(); ON = !!r && r.v === '1' } catch (e) { ON = false }
  AT = Date.now(); return ON;
}
const asset = (ctx, path) => ctx.env.ASSETS.fetch(new Request(new URL(path, ctx.request.url), ctx.request));
// Cloudflare doesn't apply _headers to pages that go through a Function, so the app and website pages get the same security headers here.
// Keep these in step with the /* block in _headers.
const SEC = {
  'X-Content-Type-Options': 'nosniff', 'X-Frame-Options': 'DENY', 'Referrer-Policy': 'strict-origin-when-cross-origin',
  'Strict-Transport-Security': 'max-age=31536000; includeSubDomains',
  'Permissions-Policy': 'camera=(), microphone=(self), geolocation=(self), payment=(), usb=(), interest-cohort=()',
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Content-Security-Policy': "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; font-src 'self'; img-src 'self' data: blob: https://tile.openstreetmap.org; connect-src 'self'; manifest-src 'self'; worker-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'; object-src 'none'; upgrade-insecure-requests"
};
const sec = async r => { r = await r; if (!/text\/html/.test(r.headers.get('content-type') || '')) return r;
  const out = new Response(r.body, r); for (const [k, v] of Object.entries(SEC)) if (!out.headers.has(k)) out.headers.set(k, v); return out };

export async function onRequest(ctx) {
  const u = new URL(ctx.request.url), p = u.pathname;
  if (ctx.request.method !== 'GET' && ctx.request.method !== 'HEAD') return ctx.next();
  if (p === '/app' || p === '/app/') return sec(asset(ctx, '/'));
  if (p === '/' && !u.search) return sec((await siteOn(ctx.env)) ? asset(ctx, '/welcome') : ctx.next());
  if (p === '/install' && !u.search && await siteOn(ctx.env)) return Response.redirect(new URL('/#get', u), 302);
  return sec(ctx.next());
}
