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

export async function onRequest(ctx) {
  const u = new URL(ctx.request.url), p = u.pathname;
  if (ctx.request.method !== 'GET' && ctx.request.method !== 'HEAD') return ctx.next();
  if (p === '/app' || p === '/app/') return asset(ctx, '/');
  if (p === '/' && !u.search) return (await siteOn(ctx.env)) ? asset(ctx, '/welcome') : ctx.next();
  if (p === '/install' && !u.search && await siteOn(ctx.env)) return Response.redirect(new URL('/#get', u), 302);
  return ctx.next();
}
