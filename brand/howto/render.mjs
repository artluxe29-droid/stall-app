// node render.mjs ep1 [fps] [from] [to]  → frames → mp4 (1080x1920)
import pw from '/opt/node22/lib/node_modules/playwright/index.js';import fs from 'fs';import {execFileSync} from 'child_process';
const [ep,fps0,from0,to0]=process.argv.slice(2),fps=+fps0||30;
const b=await pw.chromium.launch({executablePath:'/opt/pw-browsers/chromium'});const p=await b.newPage({viewport:{width:360,height:640},deviceScaleFactor:3});
const errs=[];p.on('pageerror',e=>errs.push(String(e)));await p.goto('file://'+process.cwd()+'/'+ep+'.built.html');await p.waitForTimeout(800);await p.evaluate(()=>document.fonts.ready);
if(errs.length){console.log(errs);process.exit(1)}
const D=await p.evaluate(()=>DURATION),from=+from0||0,to=to0?+to0:D,dir='frames-'+ep;fs.rmSync(dir,{recursive:true,force:true});fs.mkdirSync(dir);
let n=0;for(let t=from;t<=to;t+=1/fps){await p.evaluate(t=>setT(t),t);await p.screenshot({path:`${dir}/${String(n++).padStart(5,'0')}.jpg`,type:'jpeg',quality:92})}
await b.close();
const au=fs.existsSync(ep+'.wav')?['-i',ep+'.wav','-c:a','aac','-b:a','160k','-ar','48000','-shortest']:[];
if(!from0)execFileSync(process.env.FFMPEG||'ffmpeg',['-y','-loglevel','error','-framerate',String(fps),'-i',`${dir}/%05d.jpg`,...au,'-c:v','libx264','-pix_fmt','yuv420p','-crf','18','-preset','slow','-movflags','+faststart',ep+'.mp4']);
console.log('frames',n,'duration',D);
