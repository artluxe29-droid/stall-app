const pt = (() => { const m = {}; for (const [k, sel] of Object.entries({ search: '#hSearch', row: '#res .row', seller: '#seller', add: '#addBag', cb: '#cb', cont: '#cont', pay: '#payBtn', ps: '#psBtn', opt: '#s-pay .opt' })) m[k] = where(sel); return m })();
const T = (k, at, el) => tap(pt[k][0], pt[k][1], at, el);
run([
 (t, d) => { T('search', t + d * .12, '#hSearch'); go('#s-home', '#s-search', t + d * .2); type('#typed', 'calculator', t + d * .32, .07); show('#s-search .lbl', t + d * .62, .3, 6);
   document.querySelectorAll('#res .row').forEach((r, i) => A(r, [{ opacity: 0, transform: 'translateX(40px)' }, { opacity: 1, transform: 'none' }], t + d * .68 + i * .13, .45, POP)) },
 (t, d) => { T('row', t + d * .05, '#res .row'); go('#s-search', '#s-item', t + d * .1); ring('#seller', t + d * .38, 2.2); T('add', t + d * .9, '#addBag') },
 (t, d) => { A('#dim', [{ opacity: 0 }, { opacity: .45 }], t - .2, .4); A('#sheet', [{ transform: 'translateY(100%)' }, { transform: 'none' }], t - .2, .55, SLIDE);
   T('cb', t + d * .4, '#cb'); A('#cb', [{ background: '#fff' }, { background: '#C8F03C' }], t + d * .42, .2); A('#cb s', [{ opacity: 0, transform: 'scale(.3)' }, { opacity: 1, transform: 'none' }], t + d * .42, .35, POP);
   T('cont', t + d * .85, '#cont'); A('#sheet', [{ transform: 'none' }, { transform: 'translateY(100%)' }], t + d * .9, .45, SLIDE); A('#dim', [{ opacity: .45 }, { opacity: 0 }], t + d * .9, .4); go('#s-item', '#s-pay', t + d * .95) },
 (t, d) => { T('opt', t + d * .12, '#s-pay .opt'); T('pay', t + d * .42, '#payBtn'); go('#s-pay', '#s-ps', t + d * .48); document.querySelectorAll('#s-ps .way').forEach((w, i) => ring(w, t + d * (.62 + i * .1), .9));
   T('ps', t + d * .97, '#psBtn'); A('#spin', [{ opacity: 0 }, { opacity: 1 }], t + d * .99, .25); A('#spin i', [{ transform: 'rotate(0)' }, { transform: 'rotate(720deg)' }], t + d * .99, 1.6, 'linear') },
 (t, d) => { go('#s-ps', '#s-code', t - .1); A('.ok circle', [{ strokeDashoffset: 190 }, { strokeDashoffset: 0 }], t + .3, .7); A('.ok path', [{ strokeDashoffset: 40 }, { strokeDashoffset: 0 }], t + .9, .35);
   document.querySelectorAll('#code span').forEach((c, i) => A(c, [{ opacity: 0, transform: 'rotateX(90deg) translateY(-6px)' }, { opacity: 1, transform: 'none' }], t + d * .25 + i * .06, .4, POP)); pop('#held', t + d * .6); ring('#code', t + d * .62, 1.6) },
 (t, d) => { go('#s-code', '#s-hand', t - .1); A('#got', [{ opacity: 0, transform: 'translateX(60px) rotate(4deg)' }, { opacity: 1, transform: 'none' }], t + d * .2, .6, POP); A('#got i', [{ transform: 'scale(0)' }, { transform: 'scale(1)' }], t + d * .3, .4, POP);
   A('#fly', [{ opacity: 0, transform: 'translateY(20px) scale(.6)' }, { opacity: 1, transform: 'none' }], t + d * .45, .4, POP);
   A('#fly', [{ opacity: 1, transform: 'none' }, { opacity: 1, transform: 'translateY(-250px) scale(.8)', offset: .85 }, { opacity: 0, transform: 'translateY(-262px) scale(.5)' }], t + d * .55, 1.0, 'cubic-bezier(.6,0,.3,1)');
   A('#sst', [{ opacity: 1 }, { opacity: 0 }], t + d * .7, .2); pop('#paid', t + d * .72); ring('#sellerC', t + d * .72, 1.4); A('#done', [{ opacity: 0, transform: 'translateY(16px)' }, { opacity: 1, transform: 'none' }], t + d * .9, .45, POP) },
 (t, d) => { ring('#done', t + .2, 2) }]);
