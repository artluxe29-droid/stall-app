// Episode 1: How to buy safely on Stall. Times in seconds.
// Tap positions are measured with everything in its final place, so they stay right if the layout changes.
const pt = (() => { const st = document.createElement('style'); st.textContent = '#phone,.s,.sheet{transform:none!important}'; document.head.appendChild(st);
  const S = $('#stage').getBoundingClientRect(), m = {};
  for (const [k, sel] of Object.entries({ search: '#hSearch', row: '#res .row', seller: '#seller', add: '#addBag', cb: '#cb', cont: '#cont', pay: '#payBtn', ps: '#psBtn', got: '#got i' })) {
    const r = $(sel).getBoundingClientRect(); m[k] = [r.left - S.left + r.width / 2, r.top - S.top + r.height / 2] }
  st.remove(); return m })();
const T = (k, at, el) => tap(pt[k][0], pt[k][1], at, el);
// intro
A('.awn.top', [{ transform: 'scaleY(0)' }, { transform: 'scaleY(1)' }], 0, .7, POP);
pop('#intro .pill', .3);
document.querySelectorAll('#intro .w').forEach((w, i) => A(w, [{ opacity: 0, transform: 'translateY(26px) rotate(4deg)' }, { opacity: 1, transform: 'none' }], .55 + i * .12, .55, POP));
show('#intro p', 1.5);
A('#intro', [{ opacity: 1, transform: 'none' }, { opacity: 0, transform: 'translateY(-40px)' }], 2.75, .4);
A('#phone', [{ transform: 'translateY(560px)' }, { transform: 'none' }], 2.85, .9, 'cubic-bezier(.2,.9,.25,1.08)');
show('#foot', 3.3, .4, 0);
// 1 find
caption(1, 'Find what you need', 3.5, 8.1);
T('search', 4.7, '#hSearch'); go('#s-home', '#s-search', 5.0);
type('#typed', 'calculator', 5.5, .08);
show('#s-search .lbl', 6.5, .3, 6);
document.querySelectorAll('#res .row').forEach((r, i) => A(r, [{ opacity: 0, transform: 'translateX(40px)' }, { opacity: 1, transform: 'none' }], 6.65 + i * .13, .45, POP));
// 2 check
caption(2, 'Check the item and the seller', 8.1, 12.7);
T('row', 8.7, '#res .row'); go('#s-search', '#s-item', 9.0);
ring('#seller', 10.2, 1.7);
T('add', 12.0, '#addBag');
// 3 bag
caption(3, 'Check out from your bag', 12.7, 17.3);
A('#dim', [{ opacity: 0 }, { opacity: .45 }], 12.3, .4); A('#sheet', [{ transform: 'translateY(100%)' }, { transform: 'none' }], 12.3, .55, SLIDE);
T('cb', 13.9, '#cb'); A('#cb', [{ background: '#fff', borderColor: '#8A8778' }, { background: '#C8F03C', borderColor: '#26306E' }], 14.0, .2); A('#cb s', [{ opacity: 0, transform: 'scale(.3)' }, { opacity: 1, transform: 'none' }], 14.0, .35, POP);
T('cont', 15.2, '#cont');
A('#sheet', [{ transform: 'none' }, { transform: 'translateY(100%)' }], 15.5, .45, SLIDE); A('#dim', [{ opacity: .45 }, { opacity: 0 }], 15.5, .4);
go('#s-item', '#s-pay', 15.6);
// 4 pay
caption(4, 'Pay safely through Stall', 17.3, 22.1);
T('pay', 18.0, '#payBtn'); go('#s-pay', '#s-ps', 18.3);
T('ps', 19.6, '#psBtn');
A('#spin', [{ opacity: 0 }, { opacity: 1 }], 19.85, .25); A('#spin i', [{ transform: 'rotate(0)' }, { transform: 'rotate(720deg)' }], 19.85, 1.4, 'linear');
go('#s-ps', '#s-code', 21.2);
// 5 code
caption(5, 'Get your release code', 22.1, 27.1);
A('.ok circle', [{ strokeDashoffset: 190 }, { strokeDashoffset: 0 }], 21.7, .7); A('.ok path', [{ strokeDashoffset: 40 }, { strokeDashoffset: 0 }], 22.3, .35);
document.querySelectorAll('#code span').forEach((c, i) => A(c, [{ opacity: 0, transform: 'rotateX(90deg) translateY(-6px)' }, { opacity: 1, transform: 'none' }], 22.7 + i * .07, .4, POP));
pop('#held', 24.2); ring('#code', 25.2, 1.5);
// 6 handover
caption(6, 'Give the code once it\'s in your hands', 27.1, 33.5);
go('#s-code', '#s-hand', 27.3);
A('#got', [{ opacity: 0, transform: 'translateX(60px) rotate(4deg)' }, { opacity: 1, transform: 'none' }], 28.1, .6, POP);
A('#got i', [{ transform: 'scale(0)' }, { transform: 'scale(1)' }], 28.8, .4, POP);
A('#fly', [{ opacity: 0, transform: 'translateY(20px) scale(.6)' }, { opacity: 1, transform: 'none' }], 29.4, .4, POP);
A('#fly', [{ opacity: 1, transform: 'none' }, { opacity: 1, transform: 'translateY(-250px) scale(.8)', offset: .85 }, { opacity: 0, transform: 'translateY(-262px) scale(.5)' }], 30.0, 1.0, 'cubic-bezier(.6,0,.3,1)');
A('#sst', [{ opacity: 1 }, { opacity: 0 }], 30.9, .2); pop('#paid', 31.0); ring('#sellerC', 31.0, 1.4);
A('#done', [{ opacity: 0, transform: 'translateY(16px)' }, { opacity: 1, transform: 'none' }], 31.9, .45, POP);
// outro
A('#phone', [{ transform: 'none' }, { transform: 'translateY(640px)' }], 33.5, .7, SLIDE); hide('#foot', 33.5);
A('#outro', [{ opacity: 0, transform: 'scale(.9)' }, { opacity: 1, transform: 'none' }], 34.0, .6, POP);
window.DURATION = 38.5;
setT(0);
