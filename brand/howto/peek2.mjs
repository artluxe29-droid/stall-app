import pw from '/opt/node22/lib/node_modules/playwright/index.js';import {execFileSync} from 'child_process';
const [ep,frac0]=process.argv.slice(2),frac=+frac0||.6;const b=await pw.chromium.launch({executablePath:'/opt/pw-browsers/chromium'});const p=await b.newPage({viewport:{width:360,height:640}});
const errs=[];p.on('pageerror',e=>errs.push(String(e)));await p.goto('file://'+process.cwd()+'/'+ep+'.built.html');await p.waitForTimeout(800);
const ts=await p.evaluate(f=>[1.6,...TIMES.slice(1).map(([s,d])=>s+d*f),OUT+2],frac);const files=[];
for(const [i,t] of ts.entries()){await p.evaluate(t=>setT(t),t);const f=`pk-${ep}-${i}.png`;await p.screenshot({path:f});files.push(f)}
console.log(ep,errs);await b.close();
execFileSync('python3',['-c',`
from PIL import Image
fs=${JSON.stringify(files)};ims=[Image.open(f) for f in fs];o=Image.new('RGB',(360*min(5,len(ims)),640*((len(ims)+4)//5)),'white')
for i,im in enumerate(ims):o.paste(im,((i%5)*360,(i//5)*640))
o.save('pk-${ep}.png')`]);
