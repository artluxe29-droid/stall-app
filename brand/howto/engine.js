// Stall how-to engine: every movement is a Web Animation on one timeline, paused, so a renderer can step to any time.
const ICO = window.ICONS || {};
const ico = (k, s = 18) => `<svg viewBox="0 0 24 24" width="${s}" height="${s}" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">${ICO[k] || ''}</svg>`;
const $ = s => document.querySelector(s);
const EASE = 'cubic-bezier(.2,.8,.2,1)', POP = 'cubic-bezier(.3,1.5,.5,1)', SLIDE = 'cubic-bezier(.7,0,.2,1)';
// A(el, keyframes, start s, duration s, easing). Initial looks come from CSS; animations hold their end state.
function A(el, kf, at, dur, ease = EASE) { if (typeof el === 'string') el = $(el); if (!el) throw new Error('missing ' + kf); el.animate(kf, { duration: dur * 1000, delay: at * 1000, fill: 'forwards', easing: ease }) }
const show = (el, at, dur = .45, y = 14) => A(el, [{ opacity: 0, transform: `translateY(${y}px)` }, { opacity: 1, transform: 'none' }], at, dur);
const hide = (el, at, dur = .3) => A(el, [{ opacity: 1 }, { opacity: 0 }], at, dur);
const pop = (el, at, dur = .5) => A(el, [{ opacity: 0, transform: 'scale(.4)' }, { opacity: 1, transform: 'scale(1)' }], at, dur, POP);
// Screens inside the phone: the new one slides in from the right, the old one drifts left.
function go(from, to, at, dir = 'x') {
  const k = dir === 'up' ? ['translateY(100%)', 'none'] : ['translateX(100%)', 'none'];
  A(to, [{ transform: k[0], opacity: 1 }, { transform: k[1], opacity: 1 }], at, .55, SLIDE);
  if (from && dir !== 'up') A(from, [{ transform: 'none' }, { transform: 'translateX(-28%)', filter: 'brightness(.92)' }], at, .55, SLIDE);
}
// A finger tap: a dot lands, a ring spreads, the target squeezes.
function tap(x, y, at, target) {
  const d = document.createElement('div'); d.className = 'tap'; d.style.left = x + 'px'; d.style.top = y + 'px'; d.innerHTML = '<i></i><b></b>'; $('#stage').appendChild(d);
  A(d.querySelector('b'), [{ opacity: 0, transform: 'scale(1.6)' }, { opacity: 1, transform: 'scale(1)', offset: .35 }, { opacity: 1, transform: 'scale(.85)', offset: .6 }, { opacity: 0, transform: 'scale(1)' }], at - .25, .9);
  A(d.querySelector('i'), [{ opacity: .9, transform: 'scale(.3)' }, { opacity: 0, transform: 'scale(1.8)' }], at + .05, .6);
  if (target) A(target, [{ transform: 'scale(1)' }, { transform: 'scale(.94)' }, { transform: 'scale(1)' }], at, .3);
}
// Typing: each letter appears in turn.
// Typing: the text is revealed letter by letter (stepped width), with the cursor right behind it.
function type(el, text, at, per = .07) { el = typeof el === 'string' ? $(el) : el; el.innerHTML = `<span class="tw">${text.replace(/&/g, '&amp;').replace(/</g, '&lt;')}</span><i class="caret"></i>`;
  const tw = el.querySelector('.tw'), w = tw.scrollWidth + 1; A(tw, [{ width: '0px' }, { width: w + 'px' }], at, text.length * per, `steps(${text.length}, end)`);
  A(el.querySelector('.caret'), [{ opacity: 0 }, { opacity: 1 }], at, .01, 'linear') }
function caption(n, text, at, end) { const c = document.createElement('div'); c.className = 'cap'; c.innerHTML = `<span class="num">${n}</span><span class="ct">${text}</span>`; $('#caps').appendChild(c);
  A(c, [{ opacity: 0, transform: 'translateY(18px)' }, { opacity: 1, transform: 'none' }], at, .5); A(c.querySelector('.num'), [{ transform: 'scale(0) rotate(-40deg)' }, { transform: 'none' }], at + .1, .5, POP);
  A(c, [{ opacity: 1, transform: 'none' }, { opacity: 0, transform: 'translateY(-14px)' }], end - .35, .35) }
function ring(el, at, dur = 1.4) { A(el, [{ boxShadow: '0 0 0 0 rgba(200,240,60,0)' }, { boxShadow: '0 0 0 4px #C8F03C', offset: .2 }, { boxShadow: '0 0 0 4px #C8F03C', offset: .8 }, { boxShadow: '0 0 0 0 rgba(200,240,60,0)' }], at, dur) }
window.DURATION = 0;
window.setT = t => { document.getAnimations().forEach(a => { a.pause(); a.currentTime = t * 1000 }) };
// Voiced episodes: TIMES[i] = [start, length] of each spoken line (from voice.py). Line 0 plays over the title;
// each later line gets its numbered caption, and acts[i-1](start, length, nextStart) moves the phone in step with the words.
function run(acts) {
  const B = TIMES, ph = B[0][0] + B[0][1] + .15;
  A('.awn.top', [{ transform: 'scaleY(0)' }, { transform: 'scaleY(1)' }], 0, .7, POP); pop('#intro .pill', .3);
  document.querySelectorAll('#intro .w').forEach((w, i) => A(w, [{ opacity: 0, transform: 'translateY(26px) rotate(4deg)' }, { opacity: 1, transform: 'none' }], .5 + i * .11, .55, POP));
  show('#intro p', 1.3);
  A('#intro', [{ opacity: 1, transform: 'none' }, { opacity: 0, transform: 'translateY(-40px)' }], ph - .35, .4);
  A('#phone', [{ transform: 'translateY(560px)' }, { transform: 'none' }], ph, .9, 'cubic-bezier(.2,.9,.25,1.08)'); show('#foot', ph + .4, .4, 0);
  acts.forEach((f, i) => { const [t, d] = B[i + 1], s = SCRIPT[i + 1], nx = B[i + 2] ? B[i + 2][0] : OUT; if (s.cap) caption(i + 1, s.cap, t - .3, nx - .2); f(t, d, nx) });
  A('#phone', [{ transform: 'none' }, { transform: 'translateY(640px)' }], OUT, .7, SLIDE); hide('#foot', OUT);
  A('#outro', [{ opacity: 0, transform: 'scale(.9)' }, { opacity: 1, transform: 'none' }], OUT + .5, .6, POP);
  setT(0);
}
// Scroll a long screen: moves its content up by px.
const scroll = (el, px, at, dur = .8) => { el = typeof el === 'string' ? $(el) : el; const cur = +(el.dataset.y || 0); A(el, [{ transform: `translateY(${-cur}px)` }, { transform: `translateY(${-px}px)` }], at, dur, 'cubic-bezier(.45,0,.2,1)'); el.dataset.y = px };
// A little label that points at something, for tours.
function tip(text, x, y, at, dur = 1.4, up) { const d = document.createElement('div'); d.className = 'tip' + (up ? ' up' : ''); d.textContent = text; d.style.left = x + 'px'; d.style.top = y + 'px'; $('#stage').appendChild(d);
  A(d, [{ opacity: 0, transform: 'translate(-50%,6px) scale(.8)' }, { opacity: 1, transform: 'translate(-50%,0) scale(1)' }], at, .35, POP); A(d, [{ opacity: 1 }, { opacity: 0 }], at + dur, .3) }
// Where an element sits on the stage when everything is in its final place (taps and tips use this).
function where(sel, fix = '#phone,.s,.sheet,.acsheet{transform:none!important}') { const st = document.createElement('style'); st.textContent = fix; document.head.appendChild(st);
  const S = $('#stage').getBoundingClientRect(), r = (typeof sel === 'string' ? $(sel) : sel).getBoundingClientRect(); st.remove(); return [r.left - S.left + r.width / 2, r.top - S.top + r.height / 2, r] }
