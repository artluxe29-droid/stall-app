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
  'Content-Security-Policy': "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; font-src 'self'; img-src 'self' data: blob: https://tile.openstreetmap.org https://server.arcgisonline.com; connect-src 'self'; manifest-src 'self'; worker-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'; object-src 'none'; upgrade-insecure-requests"
};
// Link previews need a full address for the picture, so "/icons/…" in og:image gets this site's own address (whatever the domain).
const sec = async (r, o) => { r = await r; if (!/text\/html/.test(r.headers.get('content-type') || '')) return r;
  let body = r.body; if (o) { body = (await r.text()).replace('<meta property="og:image" content="/', '<meta property="og:image" content="' + o + '/') }
  const out = new Response(body, r); if (o) out.headers.delete('content-length'); for (const [k, v] of Object.entries(SEC)) if (!out.headers.has(k)) out.headers.set(k, v); return out };

// Collection links (/c/CODE or /?collect=CODE): the app page, with the link preview (WhatsApp, Telegram, X…) showing
// what is being collected instead of the general Stall card.
const hx = t => String(t).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
async function collectPage(ctx, code) {
  const r = await asset(ctx, '/'); let c = null;
  try { c = await ctx.env.DB.prepare('SELECT c.title,c.cls,c.amount,c.deadline,c.status,sc.short,sc.name sn FROM collections c LEFT JOIN users u ON u.id=c.uid LEFT JOIN schools sc ON sc.id=u.school_id WHERE c.code=?').bind(code).first() } catch (e) {}
  if (!c || !/text\/html/.test(r.headers.get('content-type') || '')) return r;
  const o = new URL(ctx.request.url).origin, amt = '₦' + Number(c.amount || 0).toLocaleString('en-NG');
  const dl = c.deadline ? ' Closes ' + new Date(c.deadline + 36e5).toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', timeZone: 'UTC' }) + '.' : '';
  const title = c.title + ' · ' + amt + ' per person', desc = [c.cls, c.short || c.sn].filter(Boolean).join(' · ') + (c.cls || c.short || c.sn ? '. ' : '') + (c.status === 'open' ? 'Pay safely on Stall and see who has paid.' + dl : 'This collection is closed.');
  const meta = (k, v) => [new RegExp('<meta property="' + k + '" content="[^"]*">'), '<meta property="' + k + '" content="' + hx(v) + '">'];
  let h = await r.text();
  for (const [re, v] of [meta('og:title', title), meta('og:description', desc), meta('og:image', o + '/icons/og-collect.png')]) h = h.replace(re, v);
  h = h.replace(/<title>[^<]*<\/title>/, '<title>' + hx(title) + ' · Stall</title>').replace('<meta property="og:type"', '<meta property="og:url" content="' + hx(o + '/c/' + code) + '"><meta property="og:type"');
  const out = new Response(h, r); out.headers.delete('content-length'); out.headers.set('cache-control', 'no-store'); return out;
}

export async function onRequest(ctx) {
  const u = new URL(ctx.request.url), p = u.pathname;
  if (ctx.request.method !== 'GET' && ctx.request.method !== 'HEAD') return ctx.next();
  if (p === '/app' || p === '/app/') return sec(asset(ctx, '/'), u.origin);
  const cm = p.match(/^\/c\/([A-Za-z0-9]{6})\/?$/), cq = p === '/' && (u.searchParams.get('collect') || '');
  if (cm || /^[A-Za-z0-9]{6}$/.test(cq)) return sec(collectPage(ctx, (cm ? cm[1] : cq).toUpperCase()));
  if (p.startsWith('/c/')) return Response.redirect(new URL('/app', u), 302);
  if (p === '/' && !u.search) return sec((await siteOn(ctx.env)) ? asset(ctx, '/welcome') : ctx.next(), u.origin);
  if (p === '/install' && !u.search && await siteOn(ctx.env)) return Response.redirect(new URL('/#get', u), 302);
  return sec(ctx.next(), p === '/' ? u.origin : null);
}
