const P = k => where(k), tapE = (sel, at, dy = 0) => { const [x, y] = P(sel); tap(x, y - dy, at, sel) };
// type over a placeholder: the grey hint disappears, then the letters appear
const fill = (sel, text, at, per = .055) => { const el = $(sel), ph = el.querySelector('.ph'); if (ph) A(ph, [{ opacity: 1 }, { opacity: 0 }], at - .05, .05); const s = document.createElement('span'); el.appendChild(s); type(s, text, at, per); A(s.querySelector('.caret'), [{ opacity: 1 }, { opacity: 0 }], at + text.length * per + .4, .05) };
const pos = { next: P('#obNext'), skip: P('#skip'), segS: P('#segS'), sch: P('#fSch'), pick: P('#ddPick'), cb: P('#cb'), create: P('#create') };
run([
 (t, d) => { A('#ob1', [{ width: '0%' }, { width: '100%' }], t - 1, d * .45, 'linear'); tap(...pos.next.slice(0, 2), t + d * .45, '#obNext');
   A('#obt1', [{ opacity: 1 }, { opacity: 0, transform: 'translateX(-30px)' }], t + d * .5, .3); A('#obt2', [{ opacity: 0, transform: 'translateX(30px)' }, { opacity: 1, transform: 'none' }], t + d * .55, .4);
   A('#ob2', [{ width: '0%' }, { width: '60%' }], t + d * .5, d * .4, 'linear'); tap(...pos.skip.slice(0, 2), t + d * .9, '#skip'); go('#s-ob', '#s-reg', t + d * .95) },
 (t, d) => { ring('#segS', t + d * .35, 1.4); tap(...pos.segS.slice(0, 2), t + d * .4, '#segS'); A('#segV', [{ background: 'transparent' }, { background: '#fff' }, { background: 'transparent' }], t + d * .7, 1.1) },
 (t, d) => { tap(...pos.sch.slice(0, 2), t + d * .15, '#fSch'); fill('#fSch', 'UNILAG', t + d * .25, .1); A('#dd', [{ opacity: 0, transform: 'translateY(-6px)' }, { opacity: 1, transform: 'none' }], t + d * .45, .3);
   tap(...pos.pick.slice(0, 2), t + d * .75, '#ddPick'); A('#dd', [{ opacity: 1 }, { opacity: 0 }], t + d * .8, .2);
   const s2 = document.createElement('span'); s2.textContent = 'University of Lagos (UNILAG)'; s2.style.position = 'absolute'; s2.style.background = '#fff'; s2.style.left = '9px'; s2.style.right = '9px'; $('#fSch').style.position = 'relative'; $('#fSch').appendChild(s2); A(s2, [{ opacity: 0 }, { opacity: 1 }], t + d * .82, .2); s2.style.opacity = 0 },
 (t, d) => { scroll('#regIn', 70, t + d * .02, .7); fill('#fName', 'Kemi Adeyemi', t + d * .12); fill('#fMat', '190401234', t + d * .38); fill('#fEm', 'kemi.adeyemi@gmail.com', t + d * .55, .035); fill('#fPh', '0803 123 4567', t + d * .78, .045) },
 (t, d) => { scroll('#regIn', 150, t, .7); fill('#fPw', '••••••••••', t + d * .2, .07); fill('#fHo', 'Moremi Hall, Room 12', t + d * .6, .05) },
 (t, d) => { tap(pos.cb[0], pos.cb[1] - 150, t + d * .35, '#cb'); A('#cb', [{ background: '#fff' }, { background: '#C8F03C' }], t + d * .37, .2); A('#cb s', [{ opacity: 0, transform: 'scale(.3)' }, { opacity: 1, transform: 'none' }], t + d * .37, .35, POP);
   tap(pos.create[0], pos.create[1] - 150, t + d * .85, '#create') },
 (t, d) => { go('#s-reg', '#s-home', t - .15); A('#toast', [{ opacity: 0, transform: 'translateY(16px)' }, { opacity: 1, transform: 'none' }], t + .5, .45, POP); A('#toast', [{ opacity: 1 }, { opacity: 0 }], t + d * .85, .4) }]);
