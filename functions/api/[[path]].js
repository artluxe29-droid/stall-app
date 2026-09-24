// Cloudflare Pages Function. Secret: PAYSTACK_SECRET. D1 binding: DB.
const J=(d,s=200,h={})=>new Response(JSON.stringify(d),{status:s,headers:{'content-type':'application/json',...h}});
const ps=(env,p,o={})=>fetch('https://api.paystack.co'+p,{...o,headers:{Authorization:'Bearer '+env.PAYSTACK_SECRET,'content-type':'application/json'}}).then(r=>r.json());
const E=new TextEncoder(),hex=b=>[...new Uint8Array(b)].map(x=>x.toString(16).padStart(2,'0')).join('');
const sha=async s=>hex(await crypto.subtle.digest('SHA-256',E.encode(s)));
const pbk=async(pw,salt)=>{const k=await crypto.subtle.importKey('raw',E.encode(pw),'PBKDF2',false,['deriveBits']);return hex(await crypto.subtle.deriveBits({name:'PBKDF2',hash:'SHA-256',salt:E.encode(salt),iterations:100000},k,256))};
const rnd=n=>hex(crypto.getRandomValues(new Uint8Array(n)));
const phoneN=p=>{let d=String(p||'').replace(/\D/g,'');if(d.startsWith('234')&&d.length===13)d='0'+d.slice(3);return d};
const pub=u=>u.role==='vendor'?{role:'vendor',id:'V-'+u.phone,name:u.name,biz:u.biz,phone:u.phone,where:u.place||'',cat:u.cat}:{role:'student',id:u.matric,name:u.name,matric:u.matric,email:u.email,phone:u.phone,where:u.place||''};
const cookie=(r,n)=>((r.headers.get('cookie')||'').match(new RegExp('(?:^|; )'+n+'=([^;]*)'))||[])[1];
const me=async(env,r)=>{const t=cookie(r,'stall_s');return t?env.DB.prepare('SELECT u.* FROM sessions s JOIN users u ON u.id=s.uid WHERE s.h=? AND s.exp>?').bind(await sha(t),Date.now()).first():null};
const start=async(env,uid)=>{const t=rnd(32);await env.DB.prepare('INSERT INTO sessions(h,uid,exp) VALUES(?,?,?)').bind(await sha(t),uid,Date.now()+2592e6).run();return 'stall_s='+t+'; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=2592000'};
export async function onRequest({request,env,params}){
  const path=[].concat(params.path||[]).join('/'),url=new URL(request.url);
  if(!env.DB&&['register','login','logout','me'].includes(path))return J({error:'Accounts are not set up yet.'},500);
  if(path==='register'&&request.method==='POST'){
    const b=await request.json().catch(()=>({})),t=k=>String(b[k]||'').trim(),bad=(field,error)=>J({error,field},400);
    const vendor=b.role==='vendor',phone=phoneN(b.phone),name=t('name'),pass=String(b.password||'');
    let matric=null,email=null,biz=null,cat=null;
    if(name.length<3||name.length>50)return bad('name','Enter your full name.');
    if(phone.length<10||phone.length>14)return bad('phone','Enter a valid WhatsApp number.');
    if(pass.length<8||pass.length>100)return bad('pw','Use at least 8 characters.');
    if(vendor){biz=t('biz');cat=t('cat').slice(0,20);
      if(biz.length<2||biz.length>40)return bad('biz','Enter your business name.');
      if(!await env.DB.prepare('SELECT 1 FROM vendor_codes WHERE code=? AND active=1').bind(t('code').toUpperCase()).first())return bad('code','That invite code is not valid. Ask the Stall team for one.');
    }else{matric=t('matric').toUpperCase();email=t('email').toLowerCase();
      if(!/^[A-Z0-9\/\-]{4,16}$/.test(matric))return bad('matric','Enter your matric number as it appears on your student ID.');
      if(!/^[^@\s]+@[^@\s]+\.[^@\s]{2,}$/.test(email))return bad('email','Enter a valid email address.');}
    const salt=rnd(16);
    try{const r=await env.DB.prepare('INSERT INTO users(role,name,matric,email,phone,place,biz,cat,salt,pw,created) VALUES(?,?,?,?,?,?,?,?,?,?,?)').bind(vendor?'vendor':'student',name,matric,email,phone,t('where').slice(0,40),biz,cat,salt,await pbk(pass,salt),Date.now()).run();
      const u=await env.DB.prepare('SELECT * FROM users WHERE id=?').bind(r.meta.last_row_id).first();
      return J({user:pub(u)},200,{'set-cookie':await start(env,u.id)});
    }catch(e){return /UNIQUE/i.test(String(e.message))?J({error:'An account with this '+(vendor?'phone number':'matric number or phone number')+' already exists. Try signing in.',field:vendor?'phone':'matric'},409):J({error:'Could not create account. Try again.'},500)}
  }
  if(path==='login'&&request.method==='POST'){
    const b=await request.json().catch(()=>({})),raw=String(b.id||'').trim(),m=raw.toUpperCase(),p=phoneN(raw),k='l:'+(m||p),now=Date.now();
    if((await env.DB.prepare('SELECT COUNT(*) c FROM attempts WHERE k=? AND t>?').bind(k,now-9e5).first()).c>=8)return J({error:'Too many attempts. Try again in 15 minutes.'},429);
    const u=await env.DB.prepare('SELECT * FROM users WHERE matric=? OR phone=?').bind(m,p).first();
    if(!u||await pbk(String(b.password||''),u.salt)!==u.pw){await env.DB.prepare('INSERT INTO attempts(k,t) VALUES(?,?)').bind(k,now).run();return J({error:'Wrong matric number, phone or password.'},401)}
    await env.DB.prepare('DELETE FROM attempts WHERE t<?').bind(now-9e5).run();
    return J({user:pub(u)},200,{'set-cookie':await start(env,u.id)});
  }
  if(path==='logout'){const t=cookie(request,'stall_s');if(t)await env.DB.prepare('DELETE FROM sessions WHERE h=?').bind(await sha(t)).run();return J({ok:true},200,{'set-cookie':'stall_s=; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=0'})}
  if(path==='me'){const u=await me(env,request);return u?J({user:pub(u)}):J({error:'Not signed in'},401)}
  if(path==='checkout'&&request.method==='POST'){
    const b=await request.json().catch(()=>({}));let amt=0;
    if(b.kind==='store')amt=5000;
    else if(Array.isArray(b.items)&&b.items.length&&b.items.length<=40)amt=b.items.reduce((s,i)=>s+Math.round(+i.price)*Math.round(+i.q),0);
    if(!(amt>=100&&amt<=2000000)||!/^\S+@\S+\.\S+$/.test(b.email||''))return J({error:'Invalid order'},400);
    const r=await ps(env,'/transaction/initialize',{method:'POST',body:JSON.stringify({email:b.email,amount:amt*100,currency:'NGN',callback_url:url.origin+'/',metadata:{kind:b.kind==='store'?'store':'order'}})});
    return r.status?J({url:r.data.authorization_url,ref:r.data.reference}):J({error:r.message},502);
  }
  if(path==='verify'){
    const ref=url.searchParams.get('ref')||'';if(!/^[\w-]{6,80}$/.test(ref))return J({paid:false},400);
    const d=(await ps(env,'/transaction/verify/'+ref)).data||{};
    return J({paid:d.status==='success',amount:(d.amount||0)/100,kind:(d.metadata||{}).kind});
  }
  return J({error:'Not found'},404);
}
