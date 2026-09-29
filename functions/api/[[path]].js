// Cloudflare Pages Function. Secret: PAYSTACK_SECRET. D1 binding: DB.
const J=(d,s=200,h={})=>new Response(JSON.stringify(d),{status:s,headers:{'content-type':'application/json',...h}});
const ps=(env,p,o={})=>fetch('https://api.paystack.co'+p,{...o,headers:{Authorization:'Bearer '+env.PAYSTACK_SECRET,'content-type':'application/json'}}).then(r=>r.json());
const E=new TextEncoder(),hex=b=>[...new Uint8Array(b)].map(x=>x.toString(16).padStart(2,'0')).join('');
const sha=async s=>hex(await crypto.subtle.digest('SHA-256',E.encode(s)));
const pbk=async(pw,salt)=>{const k=await crypto.subtle.importKey('raw',E.encode(pw),'PBKDF2',false,['deriveBits']);return hex(await crypto.subtle.deriveBits({name:'PBKDF2',hash:'SHA-256',salt:E.encode(salt),iterations:100000},k,256))};
const rnd=n=>hex(crypto.getRandomValues(new Uint8Array(n)));
const aiCheckReceipt=async(env,dataUrl,amount,ref)=>{
  if(!env.AI)return{ok:null,why:'Photo checking is not connected yet.'};
  try{
    const m=dataUrl.match(/^data:image\/[a-z]+;base64,(.*)$/s);if(!m)return{ok:null,why:'Could not read that photo.'};
    const bytes=Uint8Array.from(atob(m[1]),c=>c.charCodeAt(0));
    const prompt='You are checking a Nigerian bank transfer receipt or alert screenshot, submitted as proof of payment. '
      +'The sender claims they paid NGN '+amount+' with reference or narration "'+ref+'". '
      +'Look only at what is in the image. Reply with exactly one word: '
      +'YES if the image clearly shows a successful bank transfer or payment alert for an amount that reasonably matches NGN '+amount+'. '
      +'NO if the image is not a payment receipt or alert at all (for example a random unrelated photo), or clearly shows a different amount or a failed transaction. '
      +'UNSURE if you cannot tell either way.';
    const r=await env.AI.run('@cf/meta/llama-3.2-11b-vision-instruct',{image:[...bytes],prompt,max_tokens:6});
    const txt=String(r&&(r.response||r.description)||'').toUpperCase();
    if(txt.includes('YES'))return{ok:true};
    if(txt.includes('NO'))return{ok:false,why:"The photo doesn't look like a matching payment receipt."};
    return{ok:null,why:'Could not confidently read the receipt photo.'};
  }catch(e){return{ok:null,why:'Receipt photo check was unavailable.'}}
};
const PAY_WINDOW=20*60*1000;
const BANKS={'044':'Access Bank','070':'Fidelity Bank','011':'First Bank','214':'FCMB','058':'GTBank','50211':'Kuda','50515':'Moniepoint','999992':'OPay','999991':'PalmPay','221':'Stanbic IBTC','232':'Sterling Bank','033':'UBA','032':'Union Bank','035':'Wema Bank','057':'Zenith Bank'};
const relCode=()=>{const A='ABCDEFGHJKLMNPQRSTUVWXYZ23456789';return 'STALL-'+[...crypto.getRandomValues(new Uint8Array(6))].map(x=>A[x%32]).join('')};
async function sweep(env){const now=Date.now();
  const stale=(await env.DB.prepare("SELECT id FROM orders WHERE status IN ('pending','under_review') AND deadline<?").bind(now).all()).results;
  if(!stale.length)return;const ids=stale.map(s=>s.id),ph=ids.map(()=>'?').join(',');
  const lids=(await env.DB.prepare(`SELECT ref_id FROM order_items WHERE kind='listing' AND oid IN (${ph})`).bind(...ids).all()).results.map(r=>r.ref_id);
  await env.DB.batch(ids.map(id=>env.DB.prepare("UPDATE orders SET status='expired',updated=? WHERE id=?").bind(now,id)));
  if(lids.length){const ph2=lids.map(()=>'?').join(',');await env.DB.prepare(`UPDATE listings SET sold=0 WHERE id IN (${ph2})`).bind(...lids).run()}}

const phoneN=p=>{let d=String(p||'').replace(/\D/g,'');if(d.startsWith('234')&&d.length===13)d='0'+d.slice(3);return d};
const pub=u=>u.role==='vendor'?{role:'vendor',id:'V-'+u.phone,name:u.name,biz:u.biz,phone:u.phone,where:u.place||'',cat:u.cat,status:u.status,admin:!!u.is_admin,reviewer:!!u.reviewer,acctSet:!!(u.acct_no&&u.acct_name)}:{role:'student',id:u.matric,name:u.name,matric:u.matric,email:u.email,phone:u.phone,where:u.place||'',status:u.status,admin:!!u.is_admin,reviewer:!!u.reviewer,acctSet:!!(u.acct_no&&u.acct_name)};
const cookie=(r,n)=>((r.headers.get('cookie')||'').match(new RegExp('(?:^|; )'+n+'=([^;]*)'))||[])[1];
const me=async(env,r)=>{const t=cookie(r,'stall_s');return t?env.DB.prepare('SELECT u.* FROM sessions s JOIN users u ON u.id=s.uid WHERE s.h=? AND s.exp>?').bind(await sha(t),Date.now()).first():null};
const start=async(env,uid)=>{const t=rnd(32);await env.DB.prepare('INSERT INTO sessions(h,uid,exp) VALUES(?,?,?)').bind(await sha(t),uid,Date.now()+2592e6).run();return 'stall_s='+t+'; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=2592000'};
const tg=async(env,text)=>{if(!env.TELEGRAM_BOT_TOKEN||!env.TELEGRAM_CHAT_ID)return;try{await fetch('https://api.telegram.org/bot'+env.TELEGRAM_BOT_TOKEN+'/sendMessage',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({chat_id:env.TELEGRAM_CHAT_ID,text})})}catch(e){}};
export async function onRequest({request,env,params,waitUntil}){
  const path=[].concat(params.path||[]).join('/'),url=new URL(request.url);
  const bump=()=>env.DB.prepare('UPDATE ver SET n=n+1 WHERE id=1').run();
  if(!env.DB&&(['register','login','logout','me'].includes(path)||path.startsWith('admin/')||path.startsWith('listings')||path.startsWith('stores')||path.startsWith('orders')||path.startsWith('bank')||path==='banks'||path.startsWith('photo/')))return J({error:'Accounts are not set up yet.'},500);
  if(path==='register'&&request.method==='POST'){
    const b=await request.json().catch(()=>({})),t=k=>String(b[k]||'').trim(),bad=(field,error)=>J({error,field},400);
    const vendor=b.role==='vendor',phone=phoneN(b.phone),name=t('name'),pass=String(b.password||'');
    let matric=null,email=null,biz=null,cat=null;
    if(name.length<3||name.length>50)return bad('name','Enter your full name.');
    if(phone.length<10||phone.length>14)return bad('phone','Enter a valid WhatsApp number.');
    if(pass.length<8||pass.length>100)return bad('pw','Use at least 8 characters.');
    if(vendor){biz=t('biz');cat=t('cat').slice(0,20);
      if(biz.length<2||biz.length>40)return bad('biz','Enter your business name.');
      if(t('code')&&!await env.DB.prepare('SELECT 1 FROM vendor_codes WHERE code=? AND active=1 AND used_by IS NULL').bind(t('code').toUpperCase()).first())return bad('code','That invite code is not valid or was already used. Ask the Stall team for one.');
    }else{matric=t('matric').toUpperCase();email=t('email').toLowerCase();
      if(!/^[A-Z0-9\/\-]{4,16}$/.test(matric))return bad('matric','Enter your matric number as it appears on your student ID.');
      if(!/^[^@\s]+@[^@\s]+\.[^@\s]{2,}$/.test(email))return bad('email','Enter a valid email address.');}
    const salt=rnd(16);
    try{const r=await env.DB.prepare('INSERT INTO users(role,name,matric,email,phone,place,biz,cat,salt,pw,created,status) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)').bind(vendor?'vendor':'student',name,matric,email,phone,t('where').slice(0,40),biz,cat,salt,await pbk(pass,salt),Date.now(),vendor&&!t('code')?'pending':'active').run();
      if(vendor&&t('code'))await env.DB.prepare('UPDATE vendor_codes SET used_by=? WHERE code=?').bind(r.meta.last_row_id,t('code').toUpperCase()).run();
      if(vendor&&!t('code'))waitUntil(tg(env,'New vendor waiting for approval\n'+biz+' ('+name+')\n'+phone+' - '+t('where').slice(0,40)+'\nApprove it in Admin: '+url.origin));
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
  if(path==='listings'&&request.method==='GET'){const u=await me(env,request);if(!u)return J({error:'Not signed in'},401);await sweep(env);
    const rs=(await env.DB.prepare('SELECT * FROM listings ORDER BY created DESC LIMIT 300').all()).results;
    return J({listings:rs.map(r=>({id:'L'+r.id,title:r.title,price:r.price,cat:r.cat,cond:r.cond,spot:r.spot,desc:r.descr,seller:r.seller,phone:r.phone,imgs:Array.from({length:r.n},(_,i)=>'/api/photo/'+r.id+'/'+i),t:r.created,sold:r.sold,mine:r.uid===u.id}))})}
  if(path==='listings'&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Sign in first.'},401);
    if(u.role==='vendor'&&u.status!=='active')return J({error:'Your shop is not approved yet.'},403);
    const b=await request.json().catch(()=>({})),t=k=>String(b[k]||'').trim(),price=Math.round(+b.price),imgs=Array.isArray(b.imgs)?b.imgs:[];
    if(b.bank_code){if(!BANKS[b.bank_code])return J({error:'Choose a valid bank.'},400);
      const manual=!!b.bank_manual;
      await env.DB.prepare('UPDATE users SET bank_code=?,bank_name=?,acct_no=?,acct_name=?,bank_verified=? WHERE id=?').bind(b.bank_code,BANKS[b.bank_code],String(b.acct_no||'').replace(/\D/g,''),String(b.acct_name||'').trim(),manual?0:1,u.id).run();
      u.acct_no=b.acct_no;u.acct_name=b.acct_name;
      if(manual)waitUntil(tg(env,'Payout details need confirming\n'+u.name+' - '+u.phone+'\nBank: '+BANKS[b.bank_code]+'\nAccount: '+b.acct_no+'\nName given: '+b.acct_name))}
    if(!u.acct_no||!u.acct_name)return J({error:'Add and verify your payout bank details first.'},400);
    if(t('title').length<3||t('title').length>80)return J({error:'Enter a title of 3 to 80 characters.'},400);
    if(!(price>=1&&price<=10000000))return J({error:'Enter a valid price.'},400);
    if(imgs.length<1||imgs.length>8||imgs.some(x=>typeof x!=='string'||!/^data:image\/(jpeg|png|webp);base64,/.test(x)||x.length>450000))return J({error:'Add 1 to 8 photos.'},400);
    const r=await env.DB.prepare('INSERT INTO listings(uid,title,price,cat,cond,spot,descr,seller,phone,n,created) VALUES(?,?,?,?,?,?,?,?,?,?,?)').bind(u.id,t('title'),price,t('cat').slice(0,20),t('cond').slice(0,20),t('spot').slice(0,60),t('desc').slice(0,500),t('seller').slice(0,50)||u.name,t('phone').slice(0,20)||u.phone,imgs.length,Date.now()).run();
    const id=r.meta.last_row_id;
    await env.DB.batch(imgs.map((x,i)=>env.DB.prepare('INSERT INTO photos(lid,n,data) VALUES(?,?,?)').bind(id,i,x)));
    await bump();return J({ok:true,id:'L'+id})}
  if(path==='listings/delete'&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Sign in first.'},401);
    const b=await request.json().catch(()=>({})),id=+String(b.id||'').slice(1);
    const r=await env.DB.prepare('DELETE FROM listings WHERE id=? AND (uid=? OR ?=1)').bind(id,u.id,u.is_admin?1:0).run();
    if(r.meta.changes){await env.DB.prepare('DELETE FROM photos WHERE lid=?').bind(id).run();await bump()}return J({ok:true})}
  if(path==='listings/sold'&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Sign in first.'},401);const b=await request.json().catch(()=>({})),id=+String(b.id||'').slice(1);
    await env.DB.prepare('UPDATE listings SET sold=? WHERE id=? AND uid=?').bind(b.sold?1:0,id,u.id).run();await bump();return J({ok:true})}
  if(path==='listings/ver')return J({v:((await env.DB.prepare('SELECT n FROM ver WHERE id=1').first())||{n:0}).n},200,{'cache-control':'no-store'});
  if(path.startsWith('photo/')){const [,l,n]=path.split('/'),r=await env.DB.prepare('SELECT data FROM photos WHERE lid=? AND n=?').bind(+l,+n).first();if(!r)return new Response('Not found',{status:404});
    const m=r.data.match(/^data:(image\/[a-z]+);base64,(.*)$/s);return new Response(Uint8Array.from(atob(m[2]),c=>c.charCodeAt(0)),{headers:{'content-type':m[1],'cache-control':'public, max-age=31536000, immutable'}})}
  if(path==='stores'&&request.method==='GET'){const u=await me(env,request);if(!u)return J({error:'Not signed in'},401);
    const ss=(await env.DB.prepare('SELECT s.*,u.role,u.phone AS up,u.matric FROM stores s JOIN users u ON u.id=s.uid ORDER BY s.created DESC').all()).results,its=(await env.DB.prepare('SELECT * FROM store_items ORDER BY created DESC').all()).results;
    return J({stores:ss.map(s=>({id:'S'+s.id,owner:s.role==='vendor'?'V-'+s.up:s.matric,name:s.name,emoji:s.emoji,cat:s.cat,desc:s.descr,spot:s.spot,phone:s.phone,open:!!s.isopen,vendor:!!s.vendor,items:its.filter(i=>i.sid===s.id).map(i=>({id:'I'+i.id,title:i.title,price:i.price,desc:i.descr,avail:!!i.avail,imgs:Array.from({length:i.n},(_,k)=>'/api/photo/-'+i.id+'/'+k)}))}))})}
  if(path.startsWith('stores/')&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Sign in first.'},401);
    if(u.role==='vendor'&&u.status!=='active')return J({error:'Your shop is not approved yet.'},403);
    const b=await request.json().catch(()=>({})),mine=await env.DB.prepare('SELECT id FROM stores WHERE uid=?').bind(u.id).first(),ok=()=>bump().then(()=>J({ok:true}));
    if(path==='stores/create'){const d=b.d||{},t=k=>String(d[k]||'').trim(),ref=String(b.reference||'');
      if(!/^[\w-]{6,80}$/.test(ref))return J({error:'Invalid payment reference.'},400);
      if(mine||await env.DB.prepare('SELECT 1 FROM stores WHERE ref=?').bind(ref).first())return J({error:'You already have a store.'},409);
      const v=(await ps(env,'/transaction/verify/'+ref)).data||{};
      if(v.status!=='success'||v.amount!==500000||(v.metadata||{}).kind!=='store')return J({error:'Payment could not be confirmed. Contact Stall support with reference '+ref},402);
      if(t('name').length<2||t('name').length>40)return J({error:'Enter a store name.'},400);
      if(!BANKS[d.bank_code||''])return J({error:'Choose a payout bank.'},400);
      if(!t('acctName'))return J({error:'Verify your store account number first.'},400);
      const manual=!!d.bank_manual;
      if(manual)waitUntil(tg(env,'Payout details need confirming (store)\n'+t('name')+' - '+u.phone+'\nBank: '+BANKS[d.bank_code]+'\nAccount: '+t('acct')+'\nName given: '+t('acctName')));
      const r=await env.DB.prepare('INSERT INTO stores(uid,name,emoji,cat,descr,spot,phone,bank,acct,bank_code,acct_name,bank_verified,isopen,vendor,ref,created) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,1,?,?,?)').bind(u.id,t('name'),t('emoji').slice(0,8),t('cat').slice(0,20),t('desc').slice(0,200),t('spot').slice(0,60),t('phone').slice(0,20)||u.phone,BANKS[d.bank_code],t('acct').slice(0,20),d.bank_code,t('acctName').slice(0,60),manual?0:1,u.role==='vendor'?1:0,ref,Date.now()).run();
      await bump();return J({ok:true,id:'S'+r.meta.last_row_id})}
    if(!mine)return J({error:'Open a store first.'},400);
    if(path==='stores/toggle'){await env.DB.prepare('UPDATE stores SET isopen=1-isopen WHERE id=?').bind(mine.id).run();return ok()}
    if(path==='stores/item'){const t=k=>String(b[k]||'').trim(),price=Math.round(+b.price),imgs=Array.isArray(b.imgs)?b.imgs:[];
      if(t('title').length<3||t('title').length>80)return J({error:'Enter a title of 3 to 80 characters.'},400);
      if(!(price>=1&&price<=10000000))return J({error:'Enter a valid price.'},400);
      if(imgs.length<1||imgs.length>8||imgs.some(x=>typeof x!=='string'||!/^data:image\/(jpeg|png|webp);base64,/.test(x)||x.length>450000))return J({error:'Add 1 to 8 photos.'},400);
      const r=await env.DB.prepare('INSERT INTO store_items(sid,title,price,descr,avail,n,created) VALUES(?,?,?,?,1,?,?)').bind(mine.id,t('title'),price,t('desc').slice(0,300),imgs.length,Date.now()).run(),id=r.meta.last_row_id;
      await env.DB.batch(imgs.map((x,i)=>env.DB.prepare('INSERT INTO photos(lid,n,data) VALUES(?,?,?)').bind(-id,i,x)));return ok()}
    const iid=+String(b.id||'').slice(1);
    if(path==='stores/item/avail'){await env.DB.prepare('UPDATE store_items SET avail=1-avail WHERE id=? AND sid=?').bind(iid,mine.id).run();return ok()}
    if(path==='stores/item/delete'){const r=await env.DB.prepare('DELETE FROM store_items WHERE id=? AND sid=?').bind(iid,mine.id).run();if(r.meta.changes)await env.DB.prepare('DELETE FROM photos WHERE lid=?').bind(-iid).run();return ok()}
    if(path==='stores/delete'){const its=(await env.DB.prepare('SELECT id FROM store_items WHERE sid=?').bind(mine.id).all()).results;
      for(const i of its)await env.DB.prepare('DELETE FROM photos WHERE lid=?').bind(-i.id).run();
      await env.DB.prepare('DELETE FROM store_items WHERE sid=?').bind(mine.id).run();await env.DB.prepare('DELETE FROM stores WHERE id=?').bind(mine.id).run();return ok()}
  }
const naira=n=>'₦'+Number(n||0).toLocaleString('en-NG');
const oRow=r=>({id:r.id,title:r.title,amount:r.amount,bank:r.bank_name,acct:r.acct_no,acctName:r.acct_name,status:r.status,deadline:r.deadline,code:r.status==='verified'?r.code:null,note:r.note,buyerName:r.buyer_name,buyerPhone:r.buyer_phone,sellerName:r.seller_name,sellerPhone:r.seller_phone});
  if(path==='orders/create'&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Sign in first.'},401);
    await sweep(env);
    const b=await request.json().catch(()=>({})),ids=Array.isArray(b.items)?b.items.slice(0,60):[];
    if(!ids.length)return J({error:'Your bag is empty.'},400);
    const counts={};ids.forEach(id=>counts[id]=(counts[id]||0)+1);
    const groups={};
    for(const id of Object.keys(counts)){const q=counts[id],kind=id[0]==='L'?'listing':id[0]==='I'?'item':null,rid=+id.slice(1);
      if(!kind||!rid)return J({error:'Invalid item in bag.'},400);
      if(kind==='listing'){const L=await env.DB.prepare('SELECT l.*,u.name un,u.phone up,u.acct_no,u.acct_name,u.bank_name FROM listings l JOIN users u ON u.id=l.uid WHERE l.id=?').bind(rid).first();
        if(!L||L.sold)return J({error:'An item in your bag is no longer available.'},400);
        if(!L.acct_no||!L.acct_name)return J({error:'The seller for "'+L.title+'" has not set up payment details yet.'},400);
        const gk='U'+L.uid;(groups[gk]=groups[gk]||{seller:L.uid,sname:L.un,sphone:L.up,bank:L.bank_name,acct:L.acct_no,acctName:L.acct_name,items:[]}).items.push({kind:'listing',ref_id:L.id,title:L.title,price:L.price,q,unique:true})}
      else{const I=await env.DB.prepare('SELECT i.*,s.id sid,s.name sname,s.phone sphone,s.isopen,s.acct_no,s.acct,s.acct_name,s.bank FROM store_items i JOIN stores s ON s.id=i.sid WHERE i.id=?').bind(rid).first();
        if(!I||!I.avail||!I.isopen)return J({error:'An item in your bag is no longer available.'},400);
        const acctNo=I.acct_no||I.acct;if(!acctNo||!I.acct_name)return J({error:'The store for "'+I.title+'" has not set up payment details yet.'},400);
        const gk='S'+I.sid;(groups[gk]=groups[gk]||{seller:0,sname:I.sname,sphone:I.sphone,bank:I.bank,acct:acctNo,acctName:I.acct_name,items:[]}).items.push({kind:'item',ref_id:I.id,title:I.title,price:I.price,q})}}
    for(const gk in groups)if(groups[gk].seller===0){const s=await env.DB.prepare('SELECT uid FROM stores WHERE id=?').bind(+gk.slice(1)).first();groups[gk].seller=s.uid}
    const now=Date.now(),made=[];
    for(const gk in groups){const g=groups[gk],amount=g.items.reduce((s,i)=>s+i.price*i.q,0);
      const title=g.items.length===1?(g.items[0].q>1?g.items[0].q+' × ':'')+g.items[0].title:g.items.length+' items';
      const r=await env.DB.prepare('INSERT INTO orders(buyer,seller,buyer_name,buyer_phone,seller_name,seller_phone,title,amount,bank_name,acct_no,acct_name,status,deadline,created,updated) VALUES(?,?,?,?,?,?,?,?,?,?,?,\'pending\',?,?,?)')
        .bind(u.id,g.seller,u.name,u.phone,g.sname,g.sphone||'',title,amount,g.bank,g.acct,g.acctName,now+PAY_WINDOW,now,now).run();
      const oid=r.meta.last_row_id;
      await env.DB.batch(g.items.map(i=>env.DB.prepare('INSERT INTO order_items(oid,kind,ref_id,title,price) VALUES(?,?,?,?,?)').bind(oid,i.kind,i.ref_id,i.title,i.price)));
      const lids=g.items.filter(i=>i.kind==='listing').map(i=>i.ref_id);
      if(lids.length)await env.DB.batch(lids.map(id=>env.DB.prepare('UPDATE listings SET sold=1 WHERE id=?').bind(id)));
      made.push({id:oid,title,amount,bank:g.bank,acct:g.acct,acctName:g.acctName,sellerName:g.sname,sellerPhone:g.sphone||'',status:'pending',deadline:now+PAY_WINDOW})}
    await bump();return J({orders:made})}
  if(path==='orders/mine'&&request.method==='GET'){const u=await me(env,request);if(!u)return J({error:'Not signed in'},401);await sweep(env);
    const rs=(await env.DB.prepare('SELECT * FROM orders WHERE buyer=? ORDER BY created DESC LIMIT 100').bind(u.id).all()).results;
    return J({orders:rs.map(oRow)})}
  if(path==='orders/selling'&&request.method==='GET'){const u=await me(env,request);if(!u)return J({error:'Not signed in'},401);await sweep(env);
    const rs=(await env.DB.prepare('SELECT * FROM orders WHERE seller=? ORDER BY created DESC LIMIT 100').bind(u.id).all()).results;
    return J({orders:rs.map(oRow)})}
  if(path==='orders/receipt'&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Not signed in'},401);await sweep(env);
    const b=await request.json().catch(()=>({})),id=+b.id,amt=Math.round(+b.amount),ref=String(b.ref||'').trim(),img=String(b.receipt||'');
    const o=await env.DB.prepare('SELECT * FROM orders WHERE id=? AND buyer=?').bind(id,u.id).first();
    if(!o)return J({error:'Order not found.'},404);
    if(o.status!=='pending')return J({error:'This order is not awaiting a receipt.'},400);
    if(Date.now()>o.deadline)return J({error:'Your payment window has expired.'},400);
    if(!(amt>0))return J({error:'Enter the amount you sent.'},400);
    if(ref.length<3||ref.length>60)return J({error:'Enter the transaction reference from your bank app.'},400);
    if(!/^data:image\/(jpeg|png|webp);base64,/.test(img)||img.length>450000)return J({error:'Add a photo of your receipt.'},400);
    const dup=await env.DB.prepare("SELECT 1 FROM orders WHERE r_ref=? AND id!=? AND status IN ('verified','released')").bind(ref,id).first();
    const reasons=[];if(amt!==o.amount)reasons.push('Amount does not match the order.');if(dup)reasons.push('This reference has already been used.');
    if(!reasons.length){const ai=await aiCheckReceipt(env,img,amt,ref);if(ai.ok!==true)reasons.push(ai.why||'The receipt photo could not be confirmed automatically.')}
    const now=Date.now();
    if(!reasons.length){const code=relCode();
      await env.DB.prepare("UPDATE orders SET receipt=?,r_amount=?,r_ref=?,status='verified',code=?,updated=? WHERE id=?").bind(img,amt,ref,code,now,id).run();
      return J({ok:true,verified:true,code})}
    await env.DB.prepare("UPDATE orders SET receipt=?,r_amount=?,r_ref=?,status='under_review',note=?,updated=? WHERE id=?").bind(img,amt,ref,reasons.join(' '),now,id).run();
    waitUntil(tg(env,'Order needs review\n'+o.title+' - '+naira(o.amount)+'\nBuyer: '+o.buyer_name+'\n'+reasons.join(' ')+'\nOrder #'+id));
    return J({ok:true,verified:false})}
  if(path==='orders/code'&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Not signed in'},401);
    const b=await request.json().catch(()=>({})),id=+b.id,code=String(b.code||'').trim().toUpperCase();
    const o=await env.DB.prepare('SELECT * FROM orders WHERE id=? AND seller=?').bind(id,u.id).first();
    if(!o)return J({error:'Order not found.'},404);
    if(o.status!=='verified')return J({error:'This order has no active release code.'},400);
    if(o.code!==code)return J({error:'That code does not match this order.'},400);
    await env.DB.prepare("UPDATE orders SET status='released',code_used=1,updated=? WHERE id=?").bind(Date.now(),id).run();
    return J({ok:true})}
  if(path.startsWith('admin/')){
    const a=await me(env,request);if(!a||(!a.is_admin&&!a.reviewer))return J({error:'Not allowed'},403);
    const b=request.method==='POST'?await request.json().catch(()=>({})):{};
    if(path==='admin/orders'&&request.method==='GET')return J({orders:(await env.DB.prepare("SELECT * FROM orders WHERE status='under_review' ORDER BY created ASC LIMIT 100").all()).results.map(r=>({...oRow(r),receipt:r.receipt,rAmount:r.r_amount,rRef:r.r_ref}))});
    if(path==='admin/orders/decide'&&request.method==='POST'){const o=await env.DB.prepare("SELECT * FROM orders WHERE id=? AND status='under_review'").bind(+b.id).first();if(!o)return J({error:'Order not found.'},404);
      if(b.approve){const code=relCode();await env.DB.prepare("UPDATE orders SET status='verified',code=?,updated=? WHERE id=?").bind(code,Date.now(),o.id).run()}
      else await env.DB.prepare("UPDATE orders SET status='rejected',note=?,updated=? WHERE id=?").bind(String(b.reason||'Rejected by admin').slice(0,200),Date.now(),o.id).run();
      return J({ok:true})}
    if(!a.is_admin)return J({error:'Not allowed'},403);
    if(path==='admin/reviewers'&&request.method==='GET')return J({reviewers:(await env.DB.prepare('SELECT name,phone FROM users WHERE reviewer=1').all()).results});
    if(path==='admin/reviewers'&&request.method==='POST'){const ph=phoneN(b.phone);const r=await env.DB.prepare('UPDATE users SET reviewer=? WHERE phone=?').bind(b.add?1:0,ph).run();
      return r.meta.changes?J({ok:true}):J({error:'No account found with that phone number.'},404)}
    if(path==='admin/codes'&&request.method==='GET')return J({codes:(await env.DB.prepare('SELECT c.code,c.label,c.active,u.biz FROM vendor_codes c LEFT JOIN users u ON u.id=c.used_by ORDER BY c.created DESC').all()).results});
    if(path==='admin/codes'&&request.method==='POST'){const label=String(b.label||'').trim().slice(0,40);if(label.length<2)return J({error:'Enter the vendor or shop name.'},400);
      const A='ABCDEFGHJKLMNPQRSTUVWXYZ23456789',code='STALL-'+[...crypto.getRandomValues(new Uint8Array(6))].map(x=>A[x%32]).join('');
      await env.DB.prepare('INSERT INTO vendor_codes(code,active,label,created) VALUES(?,1,?,?)').bind(code,label,Date.now()).run();return J({code,label})}
    if(path==='admin/code-off'){await env.DB.prepare('UPDATE vendor_codes SET active=0 WHERE code=? AND used_by IS NULL').bind(String(b.code||'')).run();return J({ok:true})}
    if(path==='admin/banks'&&request.method==='GET'){
      const uu=(await env.DB.prepare("SELECT id,name,phone,bank_name,acct_no,acct_name FROM users WHERE bank_verified=0").all()).results.map(x=>({kind:'user',...x}));
      const ss=(await env.DB.prepare("SELECT id,name,bank,acct,acct_name FROM stores WHERE bank_verified=0").all()).results.map(x=>({kind:'store',...x}));
      return J({items:[...uu,...ss]})}
    if(path==='admin/bank-confirm'&&request.method==='POST'){const tbl=b.kind==='store'?'stores':'users';
      await env.DB.prepare('UPDATE '+tbl+' SET bank_verified=1 WHERE id=?').bind(+b.id).run();return J({ok:true})}
    if(path==='admin/vendors')return J({vendors:(await env.DB.prepare("SELECT id,name,biz,phone,place,cat,status FROM users WHERE role='vendor' ORDER BY created DESC").all()).results});
    if(path==='admin/status'&&['active','suspended'].includes(b.status)){await env.DB.prepare("UPDATE users SET status=? WHERE id=? AND role='vendor'").bind(b.status,+b.id).run();return J({ok:true})}
    return J({error:'Not found'},404);
  }
  if(path==='checkout'&&request.method==='POST'){
    const b=await request.json().catch(()=>({}));
    if(b.kind!=='store')return J({error:'Invalid order'},400);
    const r=await ps(env,'/transaction/initialize',{method:'POST',body:JSON.stringify({email:b.email,amount:500000,currency:'NGN',callback_url:url.origin+'/',metadata:{kind:'store'}})});
    return r.status?J({url:r.data.authorization_url,ref:r.data.reference}):J({error:r.message},502);
  }
  if(path==='banks')return J({banks:Object.entries(BANKS).map(([code,name])=>({code,name}))});
  if(path==='bank/resolve'&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Not signed in'},401);
    const b=await request.json().catch(()=>({})),code=String(b.bank_code||''),acct=String(b.acct_no||'').replace(/\D/g,'');
    if(!BANKS[code]||acct.length!==10)return J({error:'Choose a bank and enter a 10-digit account number.'},400);
    const r=await ps(env,'/bank/resolve?account_number='+acct+'&bank_code='+code);
    if(!r.status||!r.data||!r.data.account_name)return J({error:'Could not verify that account. Check the number and bank.'},400);
    return J({name:r.data.account_name})}
  if(path==='verify'){
    const ref=url.searchParams.get('ref')||'';if(!/^[\w-]{6,80}$/.test(ref))return J({paid:false},400);
    const d=(await ps(env,'/transaction/verify/'+ref)).data||{};
    return J({paid:d.status==='success',amount:(d.amount||0)/100,kind:(d.metadata||{}).kind});
  }
  return J({error:'Not found'},404);
}
