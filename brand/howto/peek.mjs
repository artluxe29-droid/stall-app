import pw from '/opt/node22/lib/node_modules/playwright/index.js';
const [ep,...ts]=process.argv.slice(2);const b=await pw.chromium.launch({executablePath:'/opt/pw-browsers/chromium'});const p=await b.newPage({viewport:{width:360,height:640},deviceScaleFactor:1});
const errs=[];p.on('pageerror',e=>errs.push(String(e)));await p.goto('file://'+process.cwd()+'/'+ep+'.built.html');await p.waitForTimeout(800);
for(const t of ts){await p.evaluate(t=>setT(t),+t);await p.screenshot({path:`peek-${t}.png`})}console.log(errs);await b.close();
