const SR = () => $('#stage').getBoundingClientRect();
const P = (s, dy = 0) => { const [x, y, r] = where(s); return [x, y - dy, r] }, TIP = (text, s, at, dur, dy = 0) => { const [x, , r] = P(s); tip(text, x, r.top - SR().top - dy - 26, at, dur) };
const tb4 = P('#tb4');
run([
 (t, d) => { tap(tb4[0], tb4[1], t + d * .18, '#tb4'); A('#dim', [{ opacity: 0 }, { opacity: .45 }], t + d * .22, .4); A('#acs', [{ transform: 'translateY(100%)' }, { transform: 'none' }], t + d * .22, .6, SLIDE); ring('#acHead', t + d * .55, 2) },
 (t, d) => { document.querySelectorAll('#tiles .tile').forEach((el, i) => ring(el, t + d * (.12 + i * .13), 1)) },
 (t, d) => { scroll('#acIn', 200, t - .2); document.querySelectorAll('#rSell .rw').forEach((el, i) => ring(el, t + d * (.25 + i * .22), 1.2)) },
 (t, d) => { scroll('#acIn', 330, t - .2); ring('#rVer', t + d * .15, 2.4); ring('#rEm', t + d * .72, 1.1); ring('#rPw', t + d * .86, 1.1) },
 (t, d) => { scroll('#acIn', 470, t - .2); ring('#rNot', t + d * .08, 1.6); ring('#rThm', t + d * .45, 1.5);
   A('#thA', [{ background: '#26306E', color: '#F6F1E7' }, { background: 'transparent', color: '#1C2457' }], t + d * .52, .2); A('#thD', [{ background: 'transparent', color: '#1C2457' }, { background: '#26306E', color: '#F6F1E7' }], t + d * .52, .2);
   A('#acs', [{ filter: 'none' }, { filter: 'invert(.88) hue-rotate(180deg)' }], t + d * .55, .4);
   A('#acs', [{ filter: 'invert(.88) hue-rotate(180deg)' }, { filter: 'none' }], t + d * .78, .4); ring('#rHow', t + d * .82, 1.3) },
 (t, d) => { scroll('#acIn', 500, t - .2); ring('#rHelp', t + d * .12, 2) }]);
