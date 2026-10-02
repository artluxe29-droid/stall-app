// Cloudflare Pages Function. Secret: PAYSTACK_SECRET. D1 binding: DB.
import {SCHOOLS,STATES} from '../../lib/schools.js';
const J=(d,s=200,h={})=>new Response(JSON.stringify(d),{status:s,headers:{'content-type':'application/json; charset=utf-8','cache-control':'no-store','x-content-type-options':'nosniff','referrer-policy':'strict-origin-when-cross-origin',...h}});
const ps=(env,p,o={})=>fetch('https://api.paystack.co'+p,{...o,headers:{Authorization:'Bearer '+env.PAYSTACK_SECRET,'content-type':'application/json'}}).then(r=>r.json());
const E=new TextEncoder(),hex=b=>[...new Uint8Array(b)].map(x=>x.toString(16).padStart(2,'0')).join('');
const sha=async s=>hex(await crypto.subtle.digest('SHA-256',E.encode(s)));
const pbk=async(pw,salt)=>{const k=await crypto.subtle.importKey('raw',E.encode(pw),'PBKDF2',false,['deriveBits']);return hex(await crypto.subtle.deriveBits({name:'PBKDF2',hash:'SHA-256',salt:E.encode(salt),iterations:100000},k,256))};
const rnd=n=>hex(crypto.getRandomValues(new Uint8Array(n)));
const ipOf=r=>r.headers.get('cf-connecting-ip')||r.headers.get('x-forwarded-for')||'0';
// Allows `max` actions per `win` ms for a key (user, IP or order). Returns false when the limit is reached.
const allow=async(env,key,max,win)=>{const now=Date.now();if((await env.DB.prepare('SELECT COUNT(*) c FROM attempts WHERE k=? AND t>?').bind(key,now-win).first()).c>=max)return false;
  await env.DB.prepare('INSERT INTO attempts(k,t) VALUES(?,?)').bind(key,now).run();return true};
// Built fresh for each request: Cloudflare doesn't allow creating responses when the Worker starts, and a response can only be sent once.
const slow=()=>J({error:'Too many tries. Please wait a little and try again.'},429);
// A photo must be a real JPEG, PNG or WebP data URL under ~330 KB, not just text claiming to be one.
const imgOk=x=>{if(typeof x!=='string'||x.length>450000)return false;const m=x.match(/^data:image\/(jpeg|png|webp);base64,([A-Za-z0-9+/=]{16})/);if(!m)return false;
  let h;try{h=atob(m[2].slice(0,16))}catch(e){return false}const c=i=>h.charCodeAt(i);
  return m[1]==='jpeg'?c(0)===0xFF&&c(1)===0xD8:m[1]==='png'?c(0)===0x89&&h.slice(1,4)==='PNG':h.slice(0,4)==='RIFF'&&h.slice(8,12)==='WEBP'};
// Edge cache (Cloudflare's Cache API). Does nothing where the Cache API isn't available.
const edge=async(key,ttl,make)=>{let c=null;try{c=typeof caches!=='undefined'&&caches.default}catch(e){}const k=c&&new Request('https://edge.stall/'+key);
  if(c){try{const hit=await c.match(k);if(hit)return new Response(hit.body,{headers:{'content-type':'application/json; charset=utf-8','cache-control':'no-store','x-cache':'HIT'}})}catch(e){}}
  const body=JSON.stringify(await make());if(c){try{await c.put(k,new Response(body,{headers:{'content-type':'application/json','cache-control':'public, max-age='+ttl}}))}catch(e){}}
  return new Response(body,{headers:{'content-type':'application/json; charset=utf-8','cache-control':'no-store','x-cache':'MISS'}})};
let VER={n:0,t:0};const bumpVer=env=>{VER.t=0;return env.DB.prepare('UPDATE ver SET n=n+1 WHERE id=1').run()};const ver=async env=>{if(Date.now()-VER.t<3000)return VER.n;const r=await env.DB.prepare('SELECT n FROM ver WHERE id=1').first();VER={n:r?r.n:0,t:Date.now()};return VER.n};
// Photos go to R2 (binding PHOTOS) when it's connected; otherwise they stay in the database as before.
const b64bytes=x=>{const m=x.match(/^data:(image\/[a-z]+);base64,(.*)$/s);return{type:m[1],bytes:Uint8Array.from(atob(m[2]),c=>c.charCodeAt(0))}};
async function savePhotos(env,lid,imgs){if(env.PHOTOS){for(let i=0;i<imgs.length;i++){const{type,bytes}=b64bytes(imgs[i]);await env.PHOTOS.put('p/'+lid+'/'+i,bytes,{httpMetadata:{contentType:type}})}
    await env.DB.batch(imgs.map((x,i)=>env.DB.prepare('INSERT INTO photos(lid,n,data) VALUES(?,?,?)').bind(lid,i,'r2:'+b64bytes(x).type)))}
  else await env.DB.batch(imgs.map((x,i)=>env.DB.prepare('INSERT INTO photos(lid,n,data) VALUES(?,?,?)').bind(lid,i,x)))}
async function delPhotos(env,lids){if(!lids.length)return 0;const ph=lids.map(()=>'?').join(',');
  if(env.PHOTOS){const rs=(await env.DB.prepare(`SELECT lid,n FROM photos WHERE lid IN (${ph}) AND data LIKE 'r2:%'`).bind(...lids).all()).results;if(rs.length)await env.PHOTOS.delete(rs.map(r=>'p/'+r.lid+'/'+r.n))}
  return(await env.DB.prepare(`DELETE FROM photos WHERE lid IN (${ph})`).bind(...lids).run()).meta.changes}
const clean=(v,n)=>String(v||'').replace(/[<>]/g,'').trim().slice(0,n);
const hmac512=async(key,msg)=>{const k=await crypto.subtle.importKey('raw',E.encode(key),{name:'HMAC',hash:'SHA-512'},false,['sign']);return hex(await crypto.subtle.sign('HMAC',k,E.encode(msg)))};
const PAY_WINDOW=20*60*1000;
const BANKS={'044':'Access Bank','070':'Fidelity Bank','011':'First Bank','214':'FCMB','058':'GTBank','50211':'Kuda','50515':'Moniepoint','999992':'OPay','999991':'PalmPay','221':'Stanbic IBTC','232':'Sterling Bank','033':'UBA','032':'Union Bank','035':'Wema Bank','057':'Zenith Bank'};
const relCode=()=>{const A='ABCDEFGHJKLMNPQRSTUVWXYZ23456789';return 'STALL-'+[...crypto.getRandomValues(new Uint8Array(6))].map(x=>A[x%32]).join('')};
// Put stock back for cancelled orders (expired or rejected).
async function restock(env,ids){if(!ids.length)return;const ph=ids.map(()=>'?').join(',');
  const its=(await env.DB.prepare(`SELECT kind,ref_id,IFNULL(q,1) q FROM order_items WHERE oid IN (${ph})`).bind(...ids).all()).results;
  const st=its.map(i=>i.kind==='listing'?env.DB.prepare('UPDATE listings SET qty_left=IFNULL(qty_left,0)+?,sold=0 WHERE id=?').bind(i.q,i.ref_id):env.DB.prepare('UPDATE store_items SET qty_left=qty_left+? WHERE id=? AND qty_left IS NOT NULL').bind(i.q,i.ref_id));
  if(st.length)await env.DB.batch(st)}
let SWEPT=0;
async function sweep(env){await ensure(env);const now=Date.now();if(now-SWEPT<3e4)return;SWEPT=now;
  // Paid orders nobody reported a problem with are released to the seller after HOLD_DAYS.
  const due=(await env.DB.prepare("SELECT * FROM orders WHERE status='verified' AND paid_at IS NOT NULL AND paid_at<? LIMIT 5").bind(now-HOLD_DAYS*864e5).all()).results;
  for(const o of due)await release(env,o,'auto').catch(()=>{});
  const stale=(await env.DB.prepare("SELECT id FROM orders WHERE status='pending' AND deadline<?").bind(now).all()).results;
  if(!stale.length)return;const ids=stale.map(s=>s.id);
  await env.DB.batch(ids.map(id=>env.DB.prepare("UPDATE orders SET status='expired',updated=? WHERE id=? AND status='pending'").bind(now,id)));
  await restock(env,ids)}
let ready=false;
const SCHEMA_V='19';
const ensure=async env=>{if(ready)return;try{const r=await env.DB.prepare("SELECT v FROM settings WHERE k='schema_v'").first();if(r&&r.v===SCHEMA_V){ready=true;return}}catch(e){}await env.DB.batch(['CREATE TABLE IF NOT EXISTS admin_log(id INTEGER PRIMARY KEY AUTOINCREMENT,t INTEGER NOT NULL,uid INTEGER,who TEXT,kind TEXT,action TEXT,oid INTEGER,target TEXT,detail TEXT)','CREATE INDEX IF NOT EXISTS admin_log_oid ON admin_log(oid)','CREATE INDEX IF NOT EXISTS admin_log_t ON admin_log(t)','CREATE TABLE IF NOT EXISTS settings(k TEXT PRIMARY KEY,v TEXT)',
  'CREATE TABLE IF NOT EXISTS payments(ref TEXT PRIMARY KEY,uid INTEGER,kind TEXT,target TEXT,label TEXT,days INTEGER,amount INTEGER,created INTEGER)','CREATE INDEX IF NOT EXISTS payments_created ON payments(created)',
  'CREATE TABLE IF NOT EXISTS verify_requests(uid INTEGER PRIMARY KEY,note TEXT,photo TEXT,status TEXT,reason TEXT,created INTEGER,updated INTEGER)'].map(q=>env.DB.prepare(q)));
  for(const q of ['CREATE TABLE IF NOT EXISTS collections(id INTEGER PRIMARY KEY AUTOINCREMENT,code TEXT NOT NULL UNIQUE,uid INTEGER NOT NULL,title TEXT NOT NULL,cls TEXT,descr TEXT,amount INTEGER NOT NULL,expected INTEGER,deadline INTEGER,status TEXT NOT NULL DEFAULT \'open\',created INTEGER NOT NULL)',
    'CREATE INDEX IF NOT EXISTS collections_uid ON collections(uid)','CREATE TABLE IF NOT EXISTS collect_pays(id INTEGER PRIMARY KEY AUTOINCREMENT,cid INTEGER NOT NULL,uid INTEGER NOT NULL,name TEXT,matric TEXT,amount INTEGER NOT NULL,fee INTEGER NOT NULL DEFAULT 0,ref TEXT UNIQUE,ticked INTEGER NOT NULL DEFAULT 0,created INTEGER NOT NULL,UNIQUE(cid,uid))',
    'CREATE TABLE IF NOT EXISTS ps_subs(k TEXT PRIMARY KEY,code TEXT NOT NULL,created INTEGER)','ALTER TABLE payouts ADD COLUMN auto INTEGER NOT NULL DEFAULT 0','ALTER TABLE stores ADD COLUMN bank_code TEXT','ALTER TABLE stores ADD COLUMN acct_name TEXT','ALTER TABLE stores ADD COLUMN bank_verified INTEGER','ALTER TABLE listings ADD COLUMN featured_until INTEGER','ALTER TABLE stores ADD COLUMN featured_until INTEGER','ALTER TABLE users ADD COLUMN verified INTEGER NOT NULL DEFAULT 0',
    'CREATE TABLE IF NOT EXISTS schools(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL UNIQUE,short TEXT,state TEXT NOT NULL,kind TEXT,active INTEGER NOT NULL DEFAULT 1,created INTEGER)','CREATE INDEX IF NOT EXISTS schools_state ON schools(state)',
    'ALTER TABLE users ADD COLUMN school_id INTEGER','ALTER TABLE users ADD COLUMN state TEXT',
    'ALTER TABLE listings ADD COLUMN school_id INTEGER','ALTER TABLE listings ADD COLUMN state TEXT','ALTER TABLE listings ADD COLUMN qty INTEGER NOT NULL DEFAULT 1','ALTER TABLE listings ADD COLUMN qty_left INTEGER',
    "ALTER TABLE listings ADD COLUMN review TEXT NOT NULL DEFAULT 'live'",'ALTER TABLE listings ADD COLUMN review_note TEXT',
    'ALTER TABLE stores ADD COLUMN school_id INTEGER','ALTER TABLE stores ADD COLUMN state TEXT',"ALTER TABLE stores ADD COLUMN reach TEXT NOT NULL DEFAULT 'school'",'ALTER TABLE stores ADD COLUMN reach_until INTEGER',
    'ALTER TABLE store_items ADD COLUMN qty_left INTEGER',"ALTER TABLE store_items ADD COLUMN review TEXT NOT NULL DEFAULT 'live'",'ALTER TABLE store_items ADD COLUMN review_note TEXT',
    'ALTER TABLE order_items ADD COLUMN q INTEGER NOT NULL DEFAULT 1',
    'CREATE TABLE IF NOT EXISTS pending_pay(ref TEXT PRIMARY KEY,uid INTEGER NOT NULL,kind TEXT NOT NULL,data TEXT,amount INTEGER NOT NULL,label TEXT,created INTEGER NOT NULL,done INTEGER NOT NULL DEFAULT 0,result TEXT)','CREATE INDEX IF NOT EXISTS pending_pay_uid ON pending_pay(uid,created)',
    'CREATE INDEX IF NOT EXISTS attempts_k ON attempts(k,t)',
    'ALTER TABLE orders ADD COLUMN bank_code TEXT','ALTER TABLE orders ADD COLUMN bank_ok INTEGER NOT NULL DEFAULT 0','ALTER TABLE orders ADD COLUMN fee INTEGER','ALTER TABLE orders ADD COLUMN paid_via TEXT',
    'CREATE TABLE IF NOT EXISTS ps_subs(k TEXT PRIMARY KEY,code TEXT NOT NULL,name TEXT,created INTEGER)',
    'ALTER TABLE users ADD COLUMN deliv_on INTEGER NOT NULL DEFAULT 0','ALTER TABLE users ADD COLUMN deliv_fee INTEGER NOT NULL DEFAULT 0','ALTER TABLE users ADD COLUMN deliv_note TEXT',
    'ALTER TABLE stores ADD COLUMN deliv_on INTEGER NOT NULL DEFAULT 0','ALTER TABLE stores ADD COLUMN deliv_fee INTEGER NOT NULL DEFAULT 0','ALTER TABLE stores ADD COLUMN deliv_note TEXT',
    'ALTER TABLE orders ADD COLUMN sub INTEGER','ALTER TABLE orders ADD COLUMN d_on INTEGER NOT NULL DEFAULT 0','ALTER TABLE orders ADD COLUMN d_fee INTEGER NOT NULL DEFAULT 0','ALTER TABLE orders ADD COLUMN d_note TEXT','ALTER TABLE orders ADD COLUMN pickup TEXT',
    'ALTER TABLE users ADD COLUMN rating_sum INTEGER NOT NULL DEFAULT 0','ALTER TABLE users ADD COLUMN rating_n INTEGER NOT NULL DEFAULT 0','ALTER TABLE orders ADD COLUMN rated INTEGER',
    'CREATE TABLE IF NOT EXISTS reviews(id INTEGER PRIMARY KEY AUTOINCREMENT,oid INTEGER NOT NULL UNIQUE,seller INTEGER NOT NULL,buyer INTEGER NOT NULL,buyer_name TEXT,title TEXT,stars INTEGER NOT NULL,body TEXT,created INTEGER NOT NULL)','CREATE INDEX IF NOT EXISTS reviews_seller ON reviews(seller,created)',
    'ALTER TABLE orders ADD COLUMN paid_at INTEGER','ALTER TABLE orders ADD COLUMN payout TEXT',
    'CREATE TABLE IF NOT EXISTS ps_recips(k TEXT PRIMARY KEY,code TEXT NOT NULL,created INTEGER)',
    'CREATE TABLE IF NOT EXISTS payouts(oid INTEGER PRIMARY KEY,seller INTEGER NOT NULL,amount INTEGER NOT NULL,ref TEXT,status TEXT NOT NULL,err TEXT,tries INTEGER NOT NULL DEFAULT 0,how TEXT,created INTEGER NOT NULL,updated INTEGER NOT NULL)','CREATE INDEX IF NOT EXISTS payouts_status ON payouts(status,updated)','CREATE INDEX IF NOT EXISTS payouts_ref ON payouts(ref)',
    'CREATE TABLE IF NOT EXISTS threads(id INTEGER PRIMARY KEY AUTOINCREMENT,buyer INTEGER NOT NULL,seller INTEGER NOT NULL,ref TEXT NOT NULL,title TEXT,last TEXT,last_at INTEGER,last_by INTEGER,b_seen INTEGER NOT NULL DEFAULT 0,s_seen INTEGER NOT NULL DEFAULT 0,created INTEGER NOT NULL,UNIQUE(buyer,seller,ref))',
    'CREATE INDEX IF NOT EXISTS threads_buyer ON threads(buyer,last_at)','CREATE INDEX IF NOT EXISTS threads_seller ON threads(seller,last_at)',
    'CREATE TABLE IF NOT EXISTS msgs(id INTEGER PRIMARY KEY AUTOINCREMENT,tid INTEGER NOT NULL,uid INTEGER NOT NULL,body TEXT NOT NULL,t INTEGER NOT NULL)','CREATE INDEX IF NOT EXISTS msgs_tid ON msgs(tid,id)',
    'ALTER TABLE users ADD COLUMN email_verified INTEGER NOT NULL DEFAULT 0','ALTER TABLE users ADD COLUMN email_notify INTEGER NOT NULL DEFAULT 1','ALTER TABLE users ADD COLUMN vlevel INTEGER NOT NULL DEFAULT 0',
    'CREATE TABLE IF NOT EXISTS codes(k TEXT PRIMARY KEY,h TEXT NOT NULL,data TEXT,exp INTEGER NOT NULL,tries INTEGER NOT NULL DEFAULT 0)',
    'CREATE TABLE IF NOT EXISTS id_checks(uid INTEGER PRIMARY KEY,kind TEXT,photo TEXT,status TEXT NOT NULL,ai TEXT,reason TEXT,created INTEGER NOT NULL,updated INTEGER NOT NULL)','CREATE INDEX IF NOT EXISTS id_checks_status ON id_checks(status,updated)',
    'CREATE TABLE IF NOT EXISTS push_subs(endpoint TEXT PRIMARY KEY,uid INTEGER NOT NULL,created INTEGER NOT NULL)','CREATE INDEX IF NOT EXISTS push_subs_uid ON push_subs(uid)',
    'CREATE TABLE IF NOT EXISTS notes(id INTEGER PRIMARY KEY AUTOINCREMENT,uid INTEGER NOT NULL,title TEXT NOT NULL,body TEXT,url TEXT,tag TEXT,t INTEGER NOT NULL,sent INTEGER NOT NULL DEFAULT 0)','CREATE INDEX IF NOT EXISTS notes_uid ON notes(uid,sent,t)',
    'ALTER TABLE users ADD COLUMN ref_code TEXT','ALTER TABLE users ADD COLUMN referred_by INTEGER','ALTER TABLE users ADD COLUMN ref_paid INTEGER NOT NULL DEFAULT 0','ALTER TABLE users ADD COLUMN credit INTEGER NOT NULL DEFAULT 0',
    'CREATE UNIQUE INDEX IF NOT EXISTS users_ref_code ON users(ref_code)','CREATE INDEX IF NOT EXISTS users_referred_by ON users(referred_by)',
    'CREATE TABLE IF NOT EXISTS credit_log(id INTEGER PRIMARY KEY AUTOINCREMENT,uid INTEGER NOT NULL,amt INTEGER NOT NULL,why TEXT,t INTEGER NOT NULL)','CREATE INDEX IF NOT EXISTS credit_log_uid ON credit_log(uid,t)',
    'ALTER TABLE stores ADD COLUMN logo TEXT','ALTER TABLE stores ADD COLUMN logo_v INTEGER',
    'ALTER TABLE orders ADD COLUMN method TEXT','ALTER TABLE orders ADD COLUMN addr TEXT','ALTER TABLE orders ADD COLUMN dphone TEXT','ALTER TABLE orders ADD COLUMN dstage TEXT','ALTER TABLE orders ADD COLUMN track TEXT',
    'CREATE INDEX IF NOT EXISTS listings_school ON listings(school_id,created)','CREATE INDEX IF NOT EXISTS listings_state ON listings(state,created)','CREATE INDEX IF NOT EXISTS listings_review ON listings(review)','CREATE INDEX IF NOT EXISTS stores_school ON stores(school_id)'])await env.DB.prepare(q).run().catch(()=>{});
  if(!(await env.DB.prepare("SELECT v FROM settings WHERE k='mig_nationwide'").first())){
    await env.DB.batch(SCHOOLS.map(([n,sh,st,k])=>env.DB.prepare('INSERT OR IGNORE INTO schools(name,short,state,kind,active,created) VALUES(?,?,?,?,1,?)').bind(n,sh,st,k,Date.now())));
    // Everything created before going nationwide belonged to Ajayi Crowther University.
    const acu=await env.DB.prepare("SELECT id,state FROM schools WHERE short='ACU'").first();
    await env.DB.batch([env.DB.prepare('UPDATE users SET school_id=?,state=? WHERE school_id IS NULL').bind(acu.id,acu.state),env.DB.prepare('UPDATE listings SET school_id=?,state=? WHERE school_id IS NULL').bind(acu.id,acu.state),
      env.DB.prepare('UPDATE stores SET school_id=?,state=? WHERE school_id IS NULL').bind(acu.id,acu.state),env.DB.prepare('UPDATE listings SET qty_left=CASE WHEN sold=1 THEN 0 ELSE 1 END WHERE qty_left IS NULL'),
      env.DB.prepare("INSERT OR REPLACE INTO settings(k,v) VALUES('mig_nationwide','1')")])}
  await env.DB.prepare("INSERT OR REPLACE INTO settings(k,v) VALUES('schema_v',?)").bind(SCHEMA_V).run();ready=true};
const schoolOf=async(env,id)=>id?env.DB.prepare('SELECT id,name,short,state FROM schools WHERE id=?').bind(id).first():null;
// Checks a new listing's first photo against its title and description. Returns {ok:true}, {ok:false,why} or {ok:null,why}.
const aiCheckListing=async(env,dataUrl,title,cat,desc)=>{
  if(!env.AI)return{ok:null,why:'Automatic photo check is not connected.'};
  try{const m=dataUrl.match(/^data:image\/[a-z]+;base64,(.*)$/s);if(!m)return{ok:null,why:'Could not read the photo.'};
    const bytes=Uint8Array.from(atob(m[1]),c=>c.charCodeAt(0));
    const prompt='You check product photos for a Nigerian student marketplace. The seller says this photo shows: "'+title+'" (category: '+cat+'). Description: "'+String(desc||'').slice(0,300)+'". '
      +'Reply with exactly one word. YES if the photo clearly shows that item (or the service being offered). '
      +'NO if it shows something different, is a blank/unrelated/meme/screenshot image, or shows weapons, drugs, alcohol for sale, explicit or adult content, or exam papers. UNSURE if you cannot tell.';
    const M='@cf/meta/llama-3.2-11b-vision-instruct',go=()=>env.AI.run(M,{image:[...bytes],prompt,max_tokens:6});
    let r;try{r=await go()}catch(e){if(!/agree|licen[cs]e|5016/i.test(String(e&&e.message)))throw e;await env.AI.run(M,{prompt:'agree'}).catch(()=>{});r=await go()}
    const txt=String(r&&(r.response||r.description)||'').toUpperCase();await setK(env,'ai_last',JSON.stringify({t:Date.now(),ok:true}));
    if(txt.includes('YES'))return{ok:true};if(txt.includes('NO'))return{ok:false,why:"The photo doesn't seem to match the title, or shows something not allowed."};
    return{ok:null,why:'The photo check could not decide.'}}catch(e){await setK(env,'ai_last',JSON.stringify({t:Date.now(),ok:false,err:String(e&&e.message||e).slice(0,200)})).catch(()=>{});return{ok:null,why:'The photo check was unavailable.'}}};
// Runs after a listing or store item is saved. Clear matches go live; anything else waits for an admin.
const reviewItem=async(env,tbl,id,dataUrl,title,cat,desc)=>{const r=await aiCheckListing(env,dataUrl,title,cat,desc);
  await env.DB.prepare('UPDATE '+tbl+' SET review=?,review_note=? WHERE id=?').bind(r.ok===true?'live':'review',r.ok===true?null:r.why,id).run();
  if(r.ok!==true)await tg(env,'Listing needs a look\n'+title+'\n'+r.why);await bumpVer(env)};
// Prices in naira. Change them here.
const PRICE={listing:{3:300,7:500},store:{3:500,7:1000},verify:1000,reach:{state:2000,national:5000}},REACH_DAYS=30;
// Stall's cut of each order paid through Paystack: rate% of the item price, at least min and never more than cap (Admin > Settings > Sale fee;
// defaults 5%, ₦150, ₦2,000). Stall pays Paystack's own fee out of it. It never takes more than half of an order (older listings under MIN_PRICE).
const FEE_DEF={rate:5,min:150,cap:2000},MIN_PRICE=500,feeOf=(a,c=FEE_DEF)=>Math.min(Math.max(Math.round(a*c.rate/100),c.min),c.cap,Math.floor(a/2));
const feeCfg=async env=>{const g=async(k,d)=>{const v=await getK(env,k);return v==null||v===''?d:+v};return{rate:await g('fee_rate',FEE_DEF.rate),min:await g('fee_min',FEE_DEF.min),cap:await g('fee_cap',FEE_DEF.cap)}};
// Delivery: sellers deliver themselves for a fee they set (couriers can be added later as another method).
// After payment the seller moves the order along these steps; the buyer's release code marks it delivered.
const DFEE_MAX=20000,STAGES={delivery:['paid','packed','on_way'],pickup:['paid','ready']};
const rat=r=>({avg:r.rating_n?Math.round(r.rating_sum/r.rating_n*10)/10:0,n:r.rating_n||0});
const dlv=r=>({on:!!r.deliv_on,fee:r.deliv_on?r.deliv_fee||0:0,note:r.deliv_on?r.deliv_note||'':''});
const dlvIn=b=>{const on=!!b.on,fee=Math.round(+b.fee||0);if(on&&!(fee>=0&&fee<=DFEE_MAX))return{error:'Enter a delivery fee from ₦0 to ₦'+DFEE_MAX.toLocaleString('en-NG')+'.'};return{on:on?1:0,fee:on?fee:0,note:on?clean(b.note,80):null}};
const track=(r,st,t)=>JSON.stringify([...JSON.parse(r.track||'[]'),{s:st,t}]);
// Stall holds every order payment in its Paystack balance. The seller is paid by Paystack Transfer when the order is released
// (release code, buyer confirms, or HOLD_DAYS after payment with no problem reported). Refunds go back to the buyer's card or account.
const HOLD_DAYS=7;
// Referrals: everyone gets a short code. When someone who signed up with it completes their first order (buying or selling),
// both of them get Stall credit (Admin -> Settings, default N300). Credit pays for featuring and store reach, never cash.
// Only a real order counts: at least REF_MIN in items, so a cheap fake order between two accounts can't farm credit.
// Kept small on purpose so featuring keeps its value: a modest reward, a monthly cap on what anyone can earn,
// and credit can only cover part of a featuring or reach payment (the rest is paid by card). All three are in Admin -> Settings.
const REF_DEFAULT=100,REF_MIN=2000,CAP_DEFAULT=500,PCT_DEFAULT=50;
const refReward=async env=>{const v=await getK(env,'ref_reward');return v==null?REF_DEFAULT:Math.max(0,+v||0)};
const refCap=async env=>{const v=await getK(env,'ref_cap');return v==null?CAP_DEFAULT:Math.max(0,+v||0)};
// Launch offer: no Stall fee on each seller's first few paid sales (admin setting free_sales, 0 turns it off).
const FREE_DEFAULT=3,freeSales=async env=>{const v=await getK(env,'free_sales');return v==null?FREE_DEFAULT:Math.min(20,Math.max(0,+v||0))};
const freeLeft=async(env,seller)=>{const n=await freeSales(env);if(!n)return 0;
  const r=await env.DB.prepare("SELECT COUNT(*) c FROM orders WHERE seller=? AND paid_at IS NOT NULL AND status NOT IN ('refunded','under_review')").bind(seller).first();return Math.max(0,n-(r.c||0))};
const creditPct=async env=>{const v=await getK(env,'credit_pct');return v==null?PCT_DEFAULT:Math.min(100,Math.max(0,+v||0))};
const monthStart=()=>{const d=new Date();d.setUTCDate(1);d.setUTCHours(0,0,0,0);return+d};
// Adds credit, but never more than the monthly cap for that person. Returns what was actually given.
async function giveCredit(env,uid,amt,why){const cap=await refCap(env),got=(await env.DB.prepare('SELECT IFNULL(SUM(amt),0) s FROM credit_log WHERE uid=? AND amt>0 AND t>=?').bind(uid,monthStart()).first()).s,give=Math.max(0,Math.min(amt,cap-got));
  if(give)await env.DB.batch([env.DB.prepare('UPDATE users SET credit=credit+? WHERE id=?').bind(give,uid),env.DB.prepare('INSERT INTO credit_log(uid,amt,why,t) VALUES(?,?,?,?)').bind(uid,give,why,Date.now())]);return give}
async function refCode(env,u){if(u.ref_code)return u.ref_code;const A='ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  for(let i=0;i<5;i++){const c=[...crypto.getRandomValues(new Uint8Array(6))].map(x=>A[x%32]).join('');
    if((await env.DB.prepare('UPDATE users SET ref_code=? WHERE id=? AND ref_code IS NULL').bind(c,u.id).run().catch(()=>({meta:{changes:0}}))).meta.changes)return c}
  return(await env.DB.prepare('SELECT ref_code FROM users WHERE id=?').bind(u.id).first()||{}).ref_code}
async function refPay(env,uid){const amt=await refReward(env);if(!amt)return;const x=await env.DB.prepare('SELECT id,name,referred_by FROM users WHERE id=?').bind(uid).first();if(!x||!x.referred_by)return;
  if(!(await env.DB.prepare('UPDATE users SET ref_paid=1 WHERE id=? AND ref_paid=0').bind(uid).run()).meta.changes)return;
  const a1=await giveCredit(env,x.referred_by,amt,'invite: user #'+uid),a2=await giveCredit(env,uid,amt,'invited by user #'+x.referred_by),first=String(x.name||'Your friend').split(' ')[0],N=v=>'₦'+v.toLocaleString('en-NG');
  if(a1)await notify(env,x.referred_by,'You earned '+N(a1)+' Stall credit','You earned '+N(a1)+' credit',[esc(first)+' just completed their first order on Stall.','Use your credit to pay part of featuring your items or store.'],'Invite more friends',SITE(env)+'/?go=invite');
  if(a2)await notify(env,uid,'You earned '+N(a2)+' Stall credit','Welcome bonus: '+N(a2)+' credit',['Thanks for your first order. Use your credit to pay part of featuring your items or store.'],'Open Stall',SITE(env)+'/')}
async function recipFor(env,code,acct,name){const k=code+':'+acct,had=await env.DB.prepare('SELECT code FROM ps_recips WHERE k=?').bind(k).first();if(had)return{code:had.code};
  const r=await ps(env,'/transferrecipient',{method:'POST',body:JSON.stringify({type:'nuban',name:String(name||'Stall seller').slice(0,100),account_number:acct,bank_code:code,currency:'NGN'})}).catch(e=>({status:false,message:String(e&&e.message||e)}));
  if(!r.status||!r.data||!r.data.recipient_code){await setK(env,'payout_last',JSON.stringify({t:Date.now(),ok:false,err:String(r.message||'No recipient returned').slice(0,200)}));return{error:r.message||'Paystack could not set up this seller.'}}
  await env.DB.prepare('INSERT OR IGNORE INTO ps_recips(k,code,created) VALUES(?,?,?)').bind(k,r.data.recipient_code,Date.now()).run();return{code:r.data.recipient_code}}
// Asks Paystack what became of each earlier transfer attempt for an order (references stallpay-<order>-1, -2, ...).
// Returns the first one that went through or is still in flight, so a retry can never pay a seller twice; null if none did.
const LIVE_X=['success','pending','processing','received','queued','otp'];
async function prevXfer(env,oid,n){for(let i=n;i>=1;i--){const ref='stallpay-'+oid+'-'+i;let h=0,r;
    try{const x=await fetch('https://api.paystack.co/transfer/verify/'+encodeURIComponent(ref),{headers:{Authorization:'Bearer '+env.PAYSTACK_SECRET}});h=x.status;r=await x.json().catch(()=>({}))}catch(e){return{ref,st:'unknown',err:String(e&&e.message||e)}}
    if(r&&r.status&&r.data){if(LIVE_X.includes(r.data.status))return{ref,st:r.data.status}}
    else if(!(h>=400&&h<500))return{ref,st:'unknown',err:r&&r.message||'HTTP '+h}}// a 4xx means Paystack never created that transfer
  return null}
// Sends the seller their share (order total minus Stall's fee). Safe to call again: a paid or in-flight payout is left alone,
// and before any retry Stall checks the earlier attempts with Paystack and never sends a second transfer while one went through or is pending.
async function payOut(env,oid,opt={}){const o=await env.DB.prepare('SELECT * FROM orders WHERE id=?').bind(oid).first();if(!o||o.status!=='released'||o.paid_via!=='paystack')return null;const now=Date.now();
  await env.DB.prepare("INSERT OR IGNORE INTO payouts(oid,seller,amount,status,tries,created,updated) VALUES(?,?,?,'queued',0,?,?)").bind(o.id,o.seller,o.amount-(o.fee||0),now,now).run();
  const p=await env.DB.prepare('SELECT * FROM payouts WHERE oid=?').bind(o.id).first();if(['paid','processing'].includes(p.status))return p;
  const set=async(st,err,ref,old)=>{await env.DB.batch([env.DB.prepare('UPDATE payouts SET status=?,err=?,ref=IFNULL(?,ref),tries=tries+?,updated=? WHERE oid=?').bind(st,err||null,ref||null,ref&&!old?1:0,Date.now(),o.id),env.DB.prepare('UPDATE orders SET payout=? WHERE id=?').bind(st,o.id)]);
    await setK(env,'payout_last',JSON.stringify({t:Date.now(),ok:st!=='failed',err:err||null}));if(st==='failed'&&!opt.quiet)await tg(env,'Seller payout failed for order #'+o.id+' ('+o.seller_name+', ₦'+p.amount+'): '+err+'\nStall will retry it automatically every hour, or retry it now in Admin → Seller pay.');return{...p,status:st,err}};
  if(p.tries>0){const pv=await prevXfer(env,o.id,p.tries);
    if(pv&&pv.st==='success')return set('paid',null,pv.ref,1);
    if(pv&&pv.st==='otp')return set('failed','An earlier transfer for this order ('+pv.ref+') is still waiting for an OTP in Paystack, so Stall did not send another. Approve that one in Paystack → Transfers (the order then shows as paid), or ask Paystack to cancel it and retry.',pv.ref,1);
    if(pv&&pv.st==='unknown')return set('failed','Stall could not check the earlier transfer ('+pv.ref+') with Paystack, so it did not send another. Try again in a few minutes.',null);
    if(pv)return set('processing',null,pv.ref,1)}
  const rc=await recipFor(env,o.bank_code,o.acct_no,o.acct_name);if(rc.error)return set('failed','Paystack would not accept the seller\'s bank account: '+rc.error);
  const ref='stallpay-'+o.id+'-'+(p.tries+1),r=await ps(env,'/transfer',{method:'POST',body:JSON.stringify({source:'balance',amount:p.amount*100,recipient:rc.code,reference:ref,reason:'Stall order #'+o.id})}).catch(e=>({status:false,message:String(e&&e.message||e)}));
  const st=r.data&&r.data.status;
  if(r.status&&st==='success')return set('paid',null,ref);
  if(r.status&&['pending','received','queued'].includes(st))return set('processing',null,ref);
  if(r.status&&st==='otp')return set('failed','Paystack is asking for an OTP. In Paystack go to Settings → Preferences and turn off "Confirm transfers before sending", then retry.',ref);
  return set('failed',String(r.message||'Transfer failed').slice(0,200),ref)}
// What Stall owes right now: buyers' money held for orders not yet released (all of it could be refunded), plus released
// orders whose payout hasn't gone out yet. The Paystack balance must cover this, or payouts and refunds fail.
async function owedNow(env){const r=await env.DB.prepare("SELECT (SELECT IFNULL(SUM(amount),0) FROM orders WHERE paid_via='paystack' AND status IN ('verified','disputed','under_review')) h,(SELECT IFNULL(SUM(amount),0) FROM payouts WHERE status IN ('queued','failed','processing')) p").first();
  return{held:r.h,unpaid:r.p,total:r.h+r.p}}
async function psBalance(env){if(!env.PAYSTACK_SECRET)return null;const r=await ps(env,'/balance').catch(()=>null);const n=r&&r.status&&Array.isArray(r.data)?r.data.find(x=>x.currency==='NGN'):null;return n?Math.round((+n.balance||0)/100):null}
// Checks the Paystack balance against what Stall owes (and warns on Telegram, at most every 6 hours, if it's short).
async function balanceCheck(env){const bal=await psBalance(env),owed=await owedNow(env),now=Date.now(),v={t:now,bal,owed:owed.total,held:owed.held,unpaid:owed.unpaid,ok:bal==null?null:bal>=owed.total};
  await setK(env,'bal_last',JSON.stringify(v));
  if(v.ok===false&&now-(+(await getK(env,'bal_warned'))||0)>6*36e5){await setK(env,'bal_warned',now);
    await tg(env,'Paystack balance is low: ₦'+bal.toLocaleString('en-NG')+', but Stall owes ₦'+owed.total.toLocaleString('en-NG')+' (₦'+owed.held.toLocaleString('en-NG')+' held for open orders, ₦'+owed.unpaid.toLocaleString('en-NG')+' waiting to be paid to sellers).\nTop up at least ₦'+(owed.total-bal).toLocaleString('en-NG')+' in Paystack so payouts and refunds don\'t fail.')}
  return v}
// Hourly money jobs, run in the background on normal traffic: check the balance, then retry failed payouts (up to AUTO_MAX times
// each). Retries are safe: payOut checks earlier attempts with Paystack first, so a seller is never paid twice.
const AUTO_MAX=6;
async function payJobs(env){await ensure(env);const now=Date.now();if(now-(+(await getK(env,'payjob_at'))||0)<55*6e4)return;await setK(env,'payjob_at',now);
  const v=await balanceCheck(env).catch(()=>null),bal=v&&v.bal;
  const due=(await env.DB.prepare("SELECT oid,amount,auto FROM payouts WHERE status='failed' AND auto<? AND updated<? ORDER BY updated LIMIT 5").bind(AUTO_MAX,now-50*6e4).all()).results;
  for(const p of due){if(bal!=null&&bal<p.amount)continue;// not enough money yet: wait, without using up a try
    await env.DB.prepare("UPDATE payouts SET status='queued',auto=auto+1 WHERE oid=? AND status='failed'").bind(p.oid).run();const r=await payOut(env,p.oid,{quiet:true}).catch(()=>null);
    if(r&&r.status==='failed'&&p.auto+1>=AUTO_MAX)await tg(env,'Seller payout for order #'+p.oid+' (₦'+p.amount+') still failed after '+AUTO_MAX+' automatic retries: '+(r.err||'')+'\nCheck it in Admin → Seller pay.')}}
// Earnings for the dashboard and accounting. Days and months are in Nigerian time (WAT, UTC+1). A sale fee on an order that
// was later refunded counts as a negative entry on the refund date, so totals match what Stall actually kept.
const WAT=36e5,dayK=t=>new Date(t+WAT).toISOString().slice(0,10),watMs=(y,m,d)=>Date.UTC(y,m,d)-WAT;
const EARN_CATS=[['commission','Sale fees'],['store','Store openings'],['boostL','Featured listings'],['boostS','Featured stores'],['reach','Store reach'],['verify','Verified badges'],['collect','Class collection fees'],['refund','Refunded sale fees']];
async function earnRows(env,from,to){
  const pays=(await env.DB.prepare('SELECT p.ref,p.kind,p.target,p.label,p.amount,p.created t,u.name,u.phone FROM payments p LEFT JOIN users u ON u.id=p.uid WHERE p.created>=? AND p.created<? AND p.amount>0 ORDER BY p.created').bind(from,to).all()).results;
  const back=(await env.DB.prepare("SELECT o.id,o.title,o.updated t,o.buyer_name,p.ref,p.amount FROM orders o JOIN payments p ON p.kind='commission' AND p.target='O'||o.id WHERE o.status='refunded' AND o.updated>=? AND o.updated<? AND p.amount>0").bind(from,to).all()).results;
  return[...pays.map(r=>({t:r.t,ref:r.ref,cat:r.kind==='boost'?(String(r.target||'')[0]==='S'?'boostS':'boostL'):r.kind,label:r.kind==='commission'?'Sale fee: '+(r.label||r.target||''):r.label||r.kind,who:r.name?r.name+' ('+r.phone+')':'',amount:r.amount})),
    ...back.map(r=>({t:r.t,ref:r.ref+'-R',cat:'refund',label:'Refunded order #'+r.id+': '+r.title,who:r.buyer_name||'',amount:-r.amount}))].sort((a,b)=>a.t-b.t)}
const sumCats=rows=>EARN_CATS.map(([k,l])=>{const x=rows.filter(r=>r.cat===k);return{key:k,label:l,n:x.length,amt:x.reduce((a,r)=>a+r.amount,0)}}).filter(c=>c.n||c.key!=='refund');
const csvCell=v=>{const t=String(v==null?'':v);return /[",\n]/.test(t)?'"'+t.replace(/"/g,'""')+'"':t};
// Words that identify an item for price matching ("iPhone 11 Pro Max 128GB" → iphone, 11, pro, max, 128gb); filler words are dropped.
const P_STOP=new Set('the and for with new used like fairly neat very good brand original clean sale selling sell one set of in on a an my is it this that uk tokunbo nigerian quality cheap available'.split(' '));
const priceWords=t=>[...new Set(String(t||'').toLowerCase().replace(/[^a-z0-9 ]/g,' ').split(/\s+/).filter(w=>(w.length>=2||/^\d$/.test(w))&&!P_STOP.has(w)))].slice(0,6);
// Class collections: a class rep collects dues, handout or trip money from classmates. Each payment goes straight to the rep's
// verified bank account through a Paystack subaccount (Stall never holds it); Stall's small fee per payment is split off by Paystack.
const COLLECT_FEE_DEFAULT=50,collectFee=async env=>{const v=await getK(env,'collect_fee');return v==null?COLLECT_FEE_DEFAULT:Math.min(1000,Math.max(0,+v||0))};
// What the payer pays on top so the rep receives the full amount: Stall's fee plus Paystack's charge on the total.
const collectCharge=(a,st)=>{let t=a+st;for(let i=0;i<5;i++)t=a+st+Math.min(Math.round(t*.015)+(t>=2500?100:0),2000);return t-a};
async function subFor(env,u){if(!u.bank_verified||!u.acct_no||!u.bank_code)return{error:'Add and verify the bank account the class money should go to.'};
  const k=u.bank_code+':'+u.acct_no,c=await env.DB.prepare('SELECT code FROM ps_subs WHERE k=?').bind(k).first();if(c)return{code:c.code};
  const r=await ps(env,'/subaccount',{method:'POST',body:JSON.stringify({business_name:String(u.name||'Class rep').slice(0,80)+' (Stall class collections)',settlement_bank:u.bank_code,account_number:u.acct_no,percentage_charge:0})}).catch(e=>({status:false,message:String(e&&e.message||e)}));
  if(!r.status||!r.data||!r.data.subaccount_code)return{error:'Paystack could not set up payments to that account: '+(r.message||'unknown error')};
  await env.DB.prepare('INSERT OR IGNORE INTO ps_subs(k,code,created) VALUES(?,?,?)').bind(k,r.data.subaccount_code,Date.now()).run();return{code:r.data.subaccount_code}}
const collOpen=c=>c&&c.status==='open'&&!(c.deadline&&Date.now()>c.deadline);
const mask=m=>{m=String(m||'');return m.length>4?'•••'+m.slice(-4):m};
// Releases a held order to the seller. Only a paid (or disputed) order can be released, and only once.
async function release(env,o,how){const now=Date.now();
  const ch=(await env.DB.prepare("UPDATE orders SET status='released',code_used=?,dstage='done',track=?,updated=? WHERE id=? AND status IN ('verified','disputed')").bind(how==='code'?1:0,track(o,'done',now),now,o.id).run()).meta.changes;
  if(ch){if((o.sub!=null?o.sub:o.amount)>=REF_MIN){await refPay(env,o.buyer).catch(()=>{});await refPay(env,o.seller).catch(()=>{})}await payOut(env,o.id);await notify(env,o.seller,'Order complete: '+o.title,'Order complete',['<b>'+esc(o.title)+'</b> has been handed over. We\'re sending <b>₦'+Number(o.amount-(o.fee||0)).toLocaleString('en-NG')+'</b> to your bank now.'],'See your orders',SITE(env)+'/?go=orders')}return!!ch}
// Gives the buyer their money back and puts the stock back. Orders not paid through Paystack are just cancelled.
async function refund(env,o,why){if(!['verified','disputed','under_review'].includes(o.status))return{error:'This order can no longer be refunded.'};
  if(o.paid_via==='paystack'&&o.r_ref){const r=await ps(env,'/refund',{method:'POST',body:JSON.stringify({transaction:o.r_ref})}).catch(e=>({status:false,message:String(e&&e.message||e)}));
    if(!r.status)return{error:'Paystack could not start the refund: '+(r.message||'unknown error')}}
  const ch=(await env.DB.prepare("UPDATE orders SET status='refunded',note=?,dstage=NULL,updated=? WHERE id=? AND status IN ('verified','disputed','under_review')").bind(why,Date.now(),o.id).run()).meta.changes;
  if(ch){await restock(env,[o.id]);await notify(env,o.buyer,'Refund on its way: '+o.title,'You\'re being refunded',['Your order for <b>'+esc(o.title)+'</b> was cancelled. '+esc(why),'Your <b>₦'+Number(o.amount).toLocaleString('en-NG')+'</b> is going back to the card or account you paid with. It can take a few working days to show.'],'See your orders',SITE(env)+'/?go=orders')}await bumpVer(env);return{ok:true}}
// ---- Email (Resend). Secrets: RESEND_API_KEY, and EMAIL_FROM like "Stall <hello@yourdomain.ng>" once your domain is verified in Resend.
const esc=s=>String(s==null?'':s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));
const mailHtml=(title,lines,btn,url)=>`<div style="font-family:Arial,Helvetica,sans-serif;background:#F5F6FA;padding:24px"><div style="max-width:480px;margin:auto;background:#fff;border-radius:16px;padding:28px">
  <div style="font-size:24px;font-weight:800;color:#0F172A">Stall<span style="color:#FF9F1C">.</span></div><h1 style="font-size:20px;color:#0F172A;margin:18px 0 10px">${esc(title)}</h1>
  ${lines.map(l=>`<p style="font-size:15px;line-height:1.5;color:#334155;margin:0 0 10px">${l}</p>`).join('')}
  ${btn?`<p style="margin:18px 0 6px"><a href="${url}" style="background:#0F172A;color:#fff;text-decoration:none;padding:12px 20px;border-radius:12px;font-weight:700;display:inline-block">${esc(btn)}</a></p>`:''}
  <p style="font-size:12px;color:#94A3B8;margin-top:22px">You get this because you have an account on Stall. Turn off order emails in Account → Email updates.</p></div></div>`;
async function sendEmail(env,to,subject,html){if(!env.RESEND_API_KEY||!to)return{skipped:true};
  try{const r=await fetch('https://api.resend.com/emails',{method:'POST',headers:{Authorization:'Bearer '+env.RESEND_API_KEY,'content-type':'application/json'},body:JSON.stringify({from:env.EMAIL_FROM||'Stall <onboarding@resend.dev>',to:[to],subject,html})});
    const j=await r.json().catch(()=>({}));const ok=r.ok&&!!j.id;await setK(env,'email_last',JSON.stringify({t:Date.now(),ok,err:ok?null:String(j.message||j.name||('HTTP '+r.status)).slice(0,200)}));return ok?{ok:true}:{error:j.message||'Email failed'}}
  catch(e){await setK(env,'email_last',JSON.stringify({t:Date.now(),ok:false,err:String(e&&e.message||e).slice(0,200)})).catch(()=>{});return{error:'Email failed'}}}
// Order emails go only to confirmed email addresses, and only if the person hasn't turned them off.
async function notify(env,uid,subject,title,lines,btn,url){try{await ping(env,uid,title,String(lines[0]||'').replace(/<[^>]+>/g,'').replace(/&amp;/g,'&').slice(0,180),url?new URL(url).pathname+new URL(url).search:'/');
  const u=await env.DB.prepare('SELECT email,email_verified,email_notify FROM users WHERE id=?').bind(uid).first();
  if(!u||!u.email_verified||!u.email_notify||!u.email)return;await sendEmail(env,u.email,subject,mailHtml(title,lines,btn,url))}catch(e){}}
// ---- Push notifications (Web Push). Keys are made on first use and kept in settings (or set VAPID_PUBLIC / VAPID_PRIVATE_JWK).
// The push itself carries no data: the phone wakes up and fetches /api/push/inbox, so nothing private goes through the push service.
const b64u=b=>btoa(String.fromCharCode(...new Uint8Array(b))).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'');
const PUSH_HOSTS=/^(fcm\.googleapis\.com|android\.googleapis\.com|updates\.push\.services\.mozilla\.com|[a-z0-9.-]+\.push\.apple\.com|[a-z0-9.-]+\.notify\.windows\.com)$/;
async function vapid(env){if(env.VAPID_PUBLIC&&env.VAPID_PRIVATE_JWK)return{pub:env.VAPID_PUBLIC,jwk:JSON.parse(env.VAPID_PRIVATE_JWK)};
  const had=await getK(env,'vapid');if(had)return JSON.parse(had);
  const k=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify']),v={pub:b64u(await crypto.subtle.exportKey('raw',k.publicKey)),jwk:await crypto.subtle.exportKey('jwk',k.privateKey)};
  await env.DB.prepare('INSERT OR IGNORE INTO settings(k,v) VALUES(?,?)').bind('vapid',JSON.stringify(v)).run();return JSON.parse(await getK(env,'vapid'))}
async function vapidJwt(env,aud){const v=await vapid(env),enc=o=>b64u(E.encode(JSON.stringify(o))),head=enc({typ:'JWT',alg:'ES256'}),body=enc({aud,exp:Math.floor(Date.now()/1000)+12*3600,sub:'mailto:'+((await getK(env,'support_email'))||'hello@stall.app')});
  const key=await crypto.subtle.importKey('jwk',v.jwk,{name:'ECDSA',namedCurve:'P-256'},false,['sign']);
  return{jwt:head+'.'+body+'.'+b64u(await crypto.subtle.sign({name:'ECDSA',hash:'SHA-256'},key,E.encode(head+'.'+body))),pub:v.pub}}
async function ping(env,uid,title,body,url,tag){try{const subs=(await env.DB.prepare('SELECT endpoint FROM push_subs WHERE uid=?').bind(uid).all()).results;if(!subs.length)return;
  await env.DB.prepare('INSERT INTO notes(uid,title,body,url,tag,t) VALUES(?,?,?,?,?,?)').bind(uid,String(title).slice(0,80),String(body||'').slice(0,180),url||'/',tag||null,Date.now()).run();
  for(const{endpoint}of subs){const{jwt,pub}=await vapidJwt(env,new URL(endpoint).origin);
    const r=await fetch(endpoint,{method:'POST',headers:{TTL:'86400',Urgency:'high','content-length':'0',Authorization:'vapid t='+jwt+', k='+pub}}).catch(()=>null);
    if(r&&(r.status===404||r.status===410))await env.DB.prepare('DELETE FROM push_subs WHERE endpoint=?').bind(endpoint).run();
    await setK(env,'push_last',JSON.stringify({t:Date.now(),ok:!!r&&r.status<300,err:r&&r.status>=300?'Push service said '+r.status:r?null:'Could not reach the push service'}))}}catch(e){}}
const SITE=env=>env.SITE_URL||'https://stall-app.pages.dev';
// One-time 6-digit codes (email check, password reset). Stored hashed, 15 minutes, 5 tries.
const newCode=async(env,k,data)=>{const c=String(100000+crypto.getRandomValues(new Uint32Array(1))[0]%900000);await env.DB.prepare('INSERT OR REPLACE INTO codes(k,h,data,exp,tries) VALUES(?,?,?,?,0)').bind(k,await sha(k+':'+c),data||null,Date.now()+9e5).run();return c};
const useCode=async(env,k,c)=>{const r=await env.DB.prepare('SELECT * FROM codes WHERE k=?').bind(k).first();if(!r||r.exp<Date.now())return{error:'That code has expired. Ask for a new one.'};
  if(r.tries>=5)return{error:'Too many wrong codes. Ask for a new one.'};if(r.h!==await sha(k+':'+String(c||'').trim())){await env.DB.prepare('UPDATE codes SET tries=tries+1 WHERE k=?').bind(k).run();return{error:'That code is not right.'}}
  await env.DB.prepare('DELETE FROM codes WHERE k=?').bind(k).run();return{ok:true,data:r.data}};
// A school email: ends in .edu.ng (e.g. name@live.unilag.edu.ng), or a domain an admin added in Settings.
const schoolMail=async(env,e)=>{const d=String(e).split('@')[1]||'';if(/\.edu\.ng$/.test(d))return true;const extra=String((await getK(env,'school_domains'))||'').split(/[\s,]+/).filter(Boolean);return extra.some(x=>d===x||d.endsWith('.'+x))};
// School documents a student can show. Any of them proves they study there, whatever their email looks like.
const DOCS={id:'student ID card',admission:'admission letter',courseform:'course registration form',fees:'school fees receipt or payment slip'};
// Reads a student ID card or admission letter. YES only if it looks real and the name matches the account.
async function aiCheckId(env,dataUrl,name,school,kind){if(!env.AI)return{ok:null,why:'Automatic check is not connected.'};
  try{const m=dataUrl.match(/^data:image\/[a-z]+;base64,(.*)$/s);if(!m)return{ok:null,why:'Could not read the photo.'};const bytes=Uint8Array.from(atob(m[1]),c=>c.charCodeAt(0));
    const prompt='You check documents for a Nigerian student marketplace. This photo should be a '+(DOCS[kind]||DOCS.id)+' from "'+school+'" for a student named "'+name+'". '
      +'Reply with exactly one word. YES if it clearly is that kind of document, it looks genuine (not a screenshot of a template, not edited), and the name on it matches "'+name+'" (allow different order or a middle name). '
      +'NO if it is a different kind of image, the name clearly does not match, or it looks fake or edited. UNSURE if you cannot tell.';
    const M='@cf/meta/llama-3.2-11b-vision-instruct',go=()=>env.AI.run(M,{image:[...bytes],prompt,max_tokens:6});
    let r;try{r=await go()}catch(e){if(!/agree|licen[cs]e|5016/i.test(String(e&&e.message)))throw e;await env.AI.run(M,{prompt:'agree'}).catch(()=>{});r=await go()}
    const t=String(r&&(r.response||r.description)||'').toUpperCase();return t.includes('YES')?{ok:true}:t.includes('NO')?{ok:false,why:"The document doesn't look right, or the name doesn't match your account."}:{ok:null,why:'The automatic check could not decide.'}}
  catch(e){return{ok:null,why:'The automatic check was unavailable.'}}}
const getK=async(env,k)=>{await ensure(env);const r=await env.DB.prepare('SELECT v FROM settings WHERE k=?').bind(k).first();return r?r.v:null};
const setK=async(env,k,v)=>{await ensure(env);await env.DB.prepare('INSERT INTO settings(k,v) VALUES(?,?) ON CONFLICT(k) DO UPDATE SET v=excluded.v').bind(k,String(v)).run()};
const logA=async(env,a,kind,action,target,o={})=>{await ensure(env);await env.DB.prepare('INSERT INTO admin_log(t,uid,who,kind,action,oid,target,detail) VALUES(?,?,?,?,?,?,?,?)').bind(Date.now(),a?a.id:null,o.who||(a?a.name+(a.is_admin?' (admin)':' (reviewer)'):'Automatic'),kind,action,o.oid||null,String(target||'').slice(0,120),o.detail?String(o.detail).slice(0,300):null).run()};
// Frees space: receipts 60 days after an order closes, sold listings older than 30 days, orphaned photos, old sessions.
const RECEIPT_DAYS=60,SOLD_DAYS=30;
async function cleanup(env,a){const now=Date.now(),D=864e5;
  const rc=(await env.DB.prepare("UPDATE orders SET receipt=NULL WHERE receipt IS NOT NULL AND status IN ('released','rejected','expired','refunded') AND updated<?").bind(now-RECEIPT_DAYS*D).run()).meta.changes;
  const old=(await env.DB.prepare("SELECT id FROM listings WHERE sold=1 AND created<? AND id NOT IN (SELECT i.ref_id FROM order_items i JOIN orders o ON o.id=i.oid WHERE i.kind='listing' AND o.status IN ('pending','under_review','verified')) LIMIT 500").bind(now-SOLD_DAYS*D).all()).results.map(r=>r.id);
  if(old.length){const ph=old.map(()=>'?').join(',');await delPhotos(env,old);await env.DB.prepare(`DELETE FROM listings WHERE id IN (${ph})`).bind(...old).run()}
  const ol=(await env.DB.prepare('SELECT DISTINCT lid FROM photos WHERE (lid>0 AND lid NOT IN (SELECT id FROM listings)) OR (lid<0 AND -lid NOT IN (SELECT id FROM store_items)) LIMIT 500').all()).results.map(r=>r.lid),orph=await delPhotos(env,ol);
  await env.DB.prepare('DELETE FROM sessions WHERE exp<?').bind(now).run();await env.DB.prepare('DELETE FROM notes WHERE t<?').bind(now-7*D).run().catch(()=>{});await env.DB.prepare('DELETE FROM attempts WHERE t<?').bind(now-D).run();
  await setK(env,'cleanup_at',now);const res={receipts:rc,listings:old.length,orphans:orph};
  if(a||rc||old.length||orph)await logA(env,a,'other','cleaned up storage','Storage',{detail:`Removed ${rc} old receipt photos, ${old.length} old sold listings, ${orph} unused photos`});
  return res}
const dailyCleanup=async env=>{try{const t=+(await getK(env,'cleanup_at'))||0;if(Date.now()-t>864e5){await setK(env,'cleanup_at',Date.now());await cleanup(env,null)}}catch(e){}};

const phoneN=p=>{let d=String(p||'').replace(/\D/g,'');if(d.startsWith('234')&&d.length===13)d='0'+d.slice(3);return d};
const pub=u=>({...pubBase(u),uid:u.id,school:u.school_id||null,deliv:dlv(u),rating:rat(u),email:u.email||'',emailVerified:!!u.email_verified,emailNotify:!!u.email_notify,vlevel:u.vlevel||0,credit:u.credit||0});
const pubBase=u=>u.role==='vendor'?{role:'vendor',id:'V-'+u.phone,name:u.name,biz:u.biz,phone:u.phone,where:u.place||'',cat:u.cat,status:u.status,admin:!!u.is_admin,reviewer:!!u.reviewer,verified:!!u.verified,acctSet:!!(u.acct_no&&u.acct_name)}:{role:'student',id:u.matric,name:u.name,matric:u.matric,email:u.email,phone:u.phone,where:u.place||'',status:u.status,admin:!!u.is_admin,reviewer:!!u.reviewer,verified:!!u.verified,acctSet:!!(u.acct_no&&u.acct_name)};
const cookie=(r,n)=>((r.headers.get('cookie')||'').match(new RegExp('(?:^|; )'+n+'=([^;]*)'))||[])[1];
const me=async(env,r)=>{const t=cookie(r,'stall_s');return t?env.DB.prepare("SELECT u.* FROM sessions s JOIN users u ON u.id=s.uid WHERE s.h=? AND s.exp>? AND IFNULL(u.status,'active')!='suspended'").bind(await sha(t),Date.now()).first():null};
const LIVE="IFNULL(u.status,'active')!='suspended'";
// {school_id} picks a listed school; {school_name,school_state} asks for a new one (hidden until an admin approves it).
const pickSchool=async(env,b)=>{const id=+b.school_id||0;
  if(id){const sc=await env.DB.prepare('SELECT id,name,short,state FROM schools WHERE id=?').bind(id).first();return sc||{error:'Choose your school from the list.'}}
  const n=String(b.school_name||'').trim().replace(/\s+/g,' ').slice(0,90),st=String(b.school_state||'');
  if(n.length<4)return{error:'Choose your school, or type its full name.'};if(!STATES.includes(st))return{error:'Choose the state your school is in.'};
  const ex=await env.DB.prepare('SELECT id,name,short,state FROM schools WHERE name=? COLLATE NOCASE').bind(n).first();if(ex)return ex;
  const r=await env.DB.prepare('INSERT INTO schools(name,short,state,kind,active,created) VALUES(?,?,?,?,0,?)').bind(n,null,st,'other',Date.now()).run();
  return{id:r.meta.last_row_id,name:n,short:null,state:st}};
const start=async(env,uid)=>{const t=rnd(32);await env.DB.prepare('INSERT INTO sessions(h,uid,exp) VALUES(?,?,?)').bind(await sha(t),uid,Date.now()+2592e6).run();return 'stall_s='+t+'; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=2592000'};
const tg=async(env,text)=>{if(!env.TELEGRAM_BOT_TOKEN||!env.TELEGRAM_CHAT_ID)return;try{await fetch('https://api.telegram.org/bot'+env.TELEGRAM_BOT_TOKEN+'/sendMessage',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({chat_id:env.TELEGRAM_CHAT_ID,text})})}catch(e){}};
const STORE_FEE=5000;
const storeBad=d=>{const t=k=>String(d[k]||'').trim();if(t('name').length<2||t('name').length>40)return 'Enter a store name.';if(!BANKS[d.bank_code||''])return 'Choose a payout bank.';
  if(!/^\d{10}$/.test(t('acct')))return 'Enter your 10-digit account number.';if(!t('acctName'))return 'Verify your store account number first.';if(t('spot').length<2)return 'Where can buyers find you?';return ''};
async function makeStore(env,u,d,ref){const manual=!!d.bank_manual;
  const r=await env.DB.prepare('INSERT INTO stores(uid,name,emoji,cat,descr,spot,phone,bank,acct,bank_code,acct_name,bank_verified,isopen,vendor,ref,created,school_id,state) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,1,?,?,?,?,?)')
    .bind(u.id,clean(d.name,40),clean(d.emoji,12),clean(d.cat,20),clean(d.desc,200),clean(d.spot,60),clean(d.phone,20)||u.phone,BANKS[d.bank_code],String(d.acct||'').replace(/\D/g,'').slice(0,10),d.bank_code,clean(d.acctName,60),manual?0:1,u.role==='vendor'?1:0,ref,Date.now(),u.school_id,u.state).run();
  const sid=r.meta.last_row_id;if(d.logo&&imgOk(d.logo)){if(env.PHOTOS){const{type,bytes}=b64bytes(d.logo);await env.PHOTOS.put('logo/'+sid,bytes,{httpMetadata:{contentType:type}});await env.DB.prepare('UPDATE stores SET logo=?,logo_v=? WHERE id=?').bind('r2:'+type,Date.now(),sid).run()}else await env.DB.prepare('UPDATE stores SET logo=?,logo_v=? WHERE id=?').bind(d.logo,Date.now(),sid).run()}
  if(manual)await tg(env,'Payout details need confirming (store)\n'+clean(d.name,40)+' - '+u.phone+'\nBank: '+BANKS[d.bank_code]+'\nAccount: '+d.acct+'\nName given: '+clean(d.acctName,60));
  await bumpVer(env);return r.meta.last_row_id}
// Finishes a Paystack payment exactly once, however it arrives: the return page, the webhook, or both.
async function fulfil(env,ref,opt={}){await ensure(env);const p=await env.DB.prepare('SELECT * FROM pending_pay WHERE ref=?').bind(ref).first();if(!p)return{error:'Unknown payment reference.'};
  if(p.done===1)return{ok:true,already:true,kind:p.kind,...JSON.parse(p.result||'{}')};if(p.done===2)return{ok:true,processing:true,kind:p.kind};
  // Paid with Stall credit: already taken from the balance, nothing to check with Paystack.
  if(!opt.credit){const v=(await ps(env,'/transaction/verify/'+ref)).data||{};
  if(v.status!=='success')return{error:'Payment not completed. You were not charged.',notPaid:true};
  if(v.amount!==p.amount*100)return{error:'Payment amount did not match. Contact Stall support with reference '+ref}}
  if(!(await env.DB.prepare('UPDATE pending_pay SET done=2 WHERE ref=? AND done=0').bind(ref).run()).meta.changes)return{ok:true,processing:true,kind:p.kind};
  const u=await env.DB.prepare('SELECT * FROM users WHERE id=?').bind(p.uid).first(),d=JSON.parse(p.data||'{}'),now=Date.now();let res={},label=p.label,act='';
  try{
    if(p.kind==='store'){const has=await env.DB.prepare('SELECT id FROM stores WHERE uid=?').bind(u.id).first();
      if(has){res={id:'S'+has.id,note:'You already had a store, so no new one was made. Contact Stall support for a refund with reference '+ref};act='paid store fee but already had a store (refund due)';await tg(env,'Refund due: '+u.name+' paid a store fee but already has a store. Ref '+ref)}
      else{res={id:'S'+await makeStore(env,u,d.d||{},ref)};act='opened a store'}}
    else if(p.kind==='order'){const o=await env.DB.prepare('SELECT * FROM orders WHERE id=?').bind(+d.oid).first(),fee0=d.fee!=null?d.fee:feeOf(p.amount,await feeCfg(env));
      if(!o)throw new Error('order missing');
      // An order already paid keeps its fee; a new sale within the seller's launch offer has none.
      const fee=o.paid_at?(o.fee!=null?o.fee:fee0):(await freeLeft(env,o.seller))>0?0:fee0;let st='verified',note=null;
      if(o.status==='expired'){// Paid after the window closed: take the stock back if it's still there, otherwise flag for a refund.
        const its=(await env.DB.prepare('SELECT kind,ref_id,IFNULL(q,1) q FROM order_items WHERE oid=?').bind(o.id).all()).results,got=[];
        for(const i of its){const ch=(await (i.kind==='listing'?env.DB.prepare('UPDATE listings SET qty_left=qty_left-?,sold=CASE WHEN qty_left-?<=0 THEN 1 ELSE 0 END WHERE id=? AND qty_left>=?').bind(i.q,i.q,i.ref_id,i.q)
          :env.DB.prepare('UPDATE store_items SET qty_left=CASE WHEN qty_left IS NULL THEN NULL ELSE qty_left-? END WHERE id=? AND (qty_left IS NULL OR qty_left>=?)').bind(i.q,i.ref_id,i.q)).run()).meta.changes;if(!ch)break;got.push(i)}
        if(got.length<its.length){if(got.length)await env.DB.batch(got.map(i=>i.kind==='listing'?env.DB.prepare('UPDATE listings SET qty_left=qty_left+?,sold=0 WHERE id=?').bind(i.q,i.ref_id):env.DB.prepare('UPDATE store_items SET qty_left=qty_left+? WHERE id=? AND qty_left IS NOT NULL').bind(i.q,i.ref_id)));
          st='under_review';note='Paid through Paystack after the order expired, and the item is no longer available. Refund the buyer (reference '+ref+').'}}
      else if(o.status!=='pending'){st=o.status;note=(o.note?o.note+' ':'')+'Also paid through Paystack (reference '+ref+'), so the buyer may have paid twice. Check and refund.'}
      const code=st==='verified'?o.code||relCode():o.code;
      // The order records exactly what was paid for: total, pickup or delivery, and where to.
      await env.DB.prepare('UPDATE orders SET status=?,code=?,note=?,paid_via=?,fee=?,r_amount=?,r_ref=?,amount=?,method=?,addr=?,dphone=?,dstage=?,track=?,updated=?,paid_at=IFNULL(paid_at,?) WHERE id=?')
        .bind(st,code,note,'paystack',fee,p.amount,ref,p.amount,d.method||'pickup',d.addr||null,d.dphone||null,st==='verified'&&o.status!=='verified'?'paid':o.dstage,st==='verified'&&o.status!=='verified'?track(o,'paid',now):o.track,now,now,o.id).run();
      if(note)await tg(env,'Order needs a look\n'+o.title+' - ₦'+p.amount+'\n'+note+'\nOrder #'+o.id);
      if(st==='verified'&&o.status!=='verified')await notify(env,o.seller,'New paid order: '+o.title,'You have a new order',[esc(o.buyer_name)+' paid <b>₦'+Number(p.amount).toLocaleString('en-NG')+'</b> for <b>'+esc(o.title)+'</b>'+(d.method==='delivery'?', to be delivered to '+esc(d.addr||''):', for pickup')+'.','Stall is holding the money. You\'re paid as soon as the buyer gives you their release code.'],'Open your orders',SITE(env)+'/?go=orders');
      res={oid:o.id,fee,status:st};act='paid order #'+o.id+' through Paystack (Stall fee ₦'+fee+')';label=o.title}
    else if(p.kind==='collect'){const c=await env.DB.prepare('SELECT * FROM collections WHERE id=?').bind(d.cid).first();if(!c)throw new Error('collection missing');
      const ins=await env.DB.prepare('INSERT OR IGNORE INTO collect_pays(cid,uid,name,matric,amount,fee,ref,created) VALUES(?,?,?,?,?,?,?,?)').bind(c.id,u.id,u.name,u.matric||u.phone,d.amount,d.fee||0,ref,now).run();
      if(!ins.meta.changes)await tg(env,'Paid twice for a class collection: '+u.name+' ('+u.phone+') paid again for "'+c.title+'" (reference '+ref+'). The money went to the class rep; ask them to refund it.');
      res={code:c.code,title:c.title};act='paid into a class collection';label='Class: '+c.title}
    else if(p.kind==='verify'){await env.DB.prepare('UPDATE users SET verified=1 WHERE id=?').bind(u.id).run();await env.DB.prepare("UPDATE verify_requests SET status='paid',updated=? WHERE uid=?").bind(now,u.id).run();act='paid for verified badge'}
    else if(p.kind==='reach'){const id=+String(d.target).slice(1),cur=await env.DB.prepare('SELECT reach,reach_until FROM stores WHERE id=?').bind(id).first()||{};
      const until=(cur.reach===d.level&&(cur.reach_until||0)>now?cur.reach_until:now)+REACH_DAYS*864e5;await env.DB.prepare('UPDATE stores SET reach=?,reach_until=? WHERE id=?').bind(d.level,until,id).run();res={until};act='upgraded store reach ('+d.level+', '+REACH_DAYS+' days)'}
    else if(p.kind==='boost'){const tbl=String(d.target)[0]==='L'?'listings':'stores',id=+String(d.target).slice(1),cur=(await env.DB.prepare('SELECT featured_until f FROM '+tbl+' WHERE id=?').bind(id).first()||{}).f||0;
      const until=Math.max(cur,now)+d.days*864e5;await env.DB.prepare('UPDATE '+tbl+' SET featured_until=? WHERE id=?').bind(until,id).run();res={until};act='featured '+(tbl==='listings'?'listing':'store')+' for '+d.days+' days'}
    if(d.credit>0){await env.DB.prepare('UPDATE users SET credit=MAX(0,credit-?) WHERE id=?').bind(d.credit,u.id).run();await env.DB.prepare('INSERT INTO credit_log(uid,amt,why,t) VALUES(?,?,?,?)').bind(u.id,-d.credit,label,now).run()}
    await bumpVer(env);
    const got=opt.credit?0:p.kind==='order'?res.fee:p.kind==='collect'?(d.fee||0):p.amount;if(opt.credit)label=label+' (paid with credit)';
    await env.DB.prepare('INSERT OR IGNORE INTO payments(ref,uid,kind,target,label,days,amount,created) VALUES(?,?,?,?,?,?,?,?)').bind(ref,u.id,p.kind==='order'?'commission':p.kind,res.id||(p.kind==='order'?'O'+res.oid:p.kind==='collect'?'C'+d.cid:d.target)||null,label,p.kind==='reach'?REACH_DAYS:(d.days||null),got,now).run();
    await env.DB.prepare('UPDATE pending_pay SET done=1,result=? WHERE ref=?').bind(JSON.stringify(res),ref).run();
    await logA(env,u,'money',act,label+' · ₦'+got,{who:u.name+' ('+(u.biz||u.phone)+')'});return{ok:true,kind:p.kind,...res}}
  catch(e){await env.DB.prepare('UPDATE pending_pay SET done=0 WHERE ref=?').bind(ref).run();return{error:'Could not finish this payment yet. It will be retried. Reference '+ref}}}
// Any unexpected error comes back as a clear JSON message (not Cloudflare's error page, which the app would read as a lost
// connection), and the Stall team gets the details on Telegram.
export async function onRequest(ctx){try{return await route(ctx)}catch(e){
  const id=Math.random().toString(36).slice(2,8).toUpperCase(),path=[].concat(ctx.params.path||[]).join('/'),msg=String(e&&e.message||e).slice(0,300);
  console.error('api error',id,path,e&&e.stack||e);try{ctx.waitUntil(tg(ctx.env,'Stall server error '+id+' on /api/'+path+' ('+ctx.request.method+'):\n'+msg))}catch(x){}
  return new Response(JSON.stringify({error:'Something went wrong on Stall\'s side. The team has been alerted. Please try again in a moment (error '+id+').',errorId:id}),{status:500,headers:{'content-type':'application/json; charset=utf-8','cache-control':'no-store'}})}}
async function route({request,env,params,waitUntil}){
  const path=[].concat(params.path||[]).join('/'),url=new URL(request.url);
  const bump=()=>bumpVer(env);
  if(request.method!=='GET'&&request.method!=='HEAD'&&path!=='paystack/webhook'){const o=request.headers.get('origin');if(o&&o!==url.origin)return J({error:'Request blocked.'},403)}
  if(!env.DB&&(['register','login','logout','me'].includes(path)||path.startsWith('admin/')||path.startsWith('listings')||path.startsWith('stores')||path.startsWith('orders')||path.startsWith('bank')||path==='banks'||path.startsWith('photo/')))return J({error:'Accounts are not set up yet.'},500);
  if(path==='register'&&request.method==='POST'){await ensure(env);if(!await allow(env,'reg:'+ipOf(request),120,36e5))return slow(); // generous: many students share one mobile-network or campus address
    const b=await request.json().catch(()=>({})),t=k=>String(b[k]||'').trim(),bad=(field,error)=>J({error,field},400);
    const sc=await pickSchool(env,b);if(sc.error)return bad('school',sc.error);
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
    try{const r=await env.DB.prepare('INSERT INTO users(role,name,matric,email,phone,place,biz,cat,salt,pw,created,status,school_id,state) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)').bind(vendor?'vendor':'student',name,matric,email,phone,t('where').slice(0,40),biz,cat,salt,await pbk(pass,salt),Date.now(),vendor&&!t('code')?'pending':'active',sc.id,sc.state).run();
      if(vendor&&t('code'))await env.DB.prepare('UPDATE vendor_codes SET used_by=? WHERE code=?').bind(r.meta.last_row_id,t('code').toUpperCase()).run();
      if(t('ref')){const rf=await env.DB.prepare("SELECT id FROM users WHERE ref_code=? AND status!='deleted'").bind(t('ref').toUpperCase().slice(0,12)).first();if(rf&&rf.id!==r.meta.last_row_id)await env.DB.prepare('UPDATE users SET referred_by=? WHERE id=?').bind(rf.id,r.meta.last_row_id).run()}
      if(vendor&&!t('code'))waitUntil(tg(env,'New vendor waiting for approval\n'+biz+' ('+name+')\n'+phone+' - '+t('where').slice(0,40)+'\nApprove it in Admin: '+url.origin));
      const u=await env.DB.prepare('SELECT * FROM users WHERE id=?').bind(r.meta.last_row_id).first();
      return J({user:{...pub(u),freeLeft:await freeLeft(env,u.id)}},200,{'set-cookie':await start(env,u.id)});
    }catch(e){return /UNIQUE/i.test(String(e.message))?J({error:'An account with this '+(vendor?'phone number':'matric number or phone number')+' already exists. Try signing in.',field:vendor?'phone':'matric'},409):J({error:'Could not create account. Try again.'},500)}
  }
  if(path==='login'&&request.method==='POST'){
    const b=await request.json().catch(()=>({})),raw=String(b.id||'').trim(),m=raw.toUpperCase(),p=phoneN(raw),k='l:'+(m||p),now=Date.now();
    if((await env.DB.prepare('SELECT COUNT(*) c FROM attempts WHERE k=? AND t>?').bind(k,now-9e5).first()).c>=8)return J({error:'Too many attempts. Try again in 15 minutes.'},429);
    if(!await allow(env,'lip:'+ipOf(request),300,9e5))return slow();
    const u=await env.DB.prepare('SELECT * FROM users WHERE matric=? OR phone=?').bind(m,p).first();
    if(!u||await pbk(String(b.password||''),u.salt)!==u.pw){await env.DB.prepare('INSERT INTO attempts(k,t) VALUES(?,?)').bind(k,now).run();return J({error:'Wrong matric number, phone or password.'},401)}
    await env.DB.prepare('DELETE FROM attempts WHERE t<?').bind(now-9e5).run();
    if(u.status==='suspended')return J({error:'This account has been suspended. Contact the Stall team if you think this is a mistake.'},403);
    return J({user:{...pub(u),freeLeft:await freeLeft(env,u.id)}},200,{'set-cookie':await start(env,u.id)});
  }
  // ---- Student verification. Level 1: confirmed school email. Level 2: student ID or admission letter checked. Campus vendors don't need it.
  if(path==='verify/email/start'&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Sign in first.'},401);await ensure(env);
    const b=await request.json().catch(()=>({})),email=String(b.email||'').trim().toLowerCase();if(!/^[^@\s]+@[^@\s]+\.[^@\s]{2,}$/.test(email))return J({error:'Enter a valid email address.'},400);
    if(!env.RESEND_API_KEY)return J({error:'Email is not set up yet. Upload your student ID instead.'},503);
    if(!await allow(env,'vem:'+u.id,5,36e5))return slow();
    const taken=await env.DB.prepare('SELECT 1 FROM users WHERE email=? AND email_verified=1 AND id!=?').bind(email,u.id).first();if(taken)return J({error:'That email is already confirmed on another account.'},409);
    const code=await newCode(env,'em:'+u.id,email),r=await sendEmail(env,email,'Your Stall code: '+code,mailHtml('Confirm your email',['Your code is:','<b style="font-size:28px;letter-spacing:4px;color:#0F172A">'+code+'</b>','It expires in 15 minutes. If you didn\'t ask for this, ignore this email.']));
    if(r.error)return J({error:'We could not send the email. Check the address and try again.'},502);return J({ok:true,school:await schoolMail(env,email)})}
  if(path==='verify/email/confirm'&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Sign in first.'},401);await ensure(env);
    const b=await request.json().catch(()=>({})),r=await useCode(env,'em:'+u.id,b.code);if(r.error)return J(r,400);const email=r.data,sch=await schoolMail(env,email),lvl=sch&&u.role==='student'?Math.max(u.vlevel||0,1):(u.vlevel||0);
    await env.DB.prepare('UPDATE users SET email=?,email_verified=1,vlevel=? WHERE id=?').bind(email,lvl,u.id).run();if(lvl!==(u.vlevel||0))await bumpVer(env);
    return J({ok:true,vlevel:lvl,school:sch})}
  if(path==='verify/id'&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Sign in first.'},401);await ensure(env);
    const b=await request.json().catch(()=>({})),kind=DOCS[b.kind]?b.kind:'id',photo=String(b.photo||'');
    if((u.vlevel||0)>=2)return J({error:'You are already verified.'},400);if(!imgOk(photo))return J({error:'Add a clear photo of your school document.'},400);
    if(!await allow(env,'vid:'+u.id,5,864e5))return slow();
    const sc=await schoolOf(env,u.school_id),ai=await aiCheckId(env,photo,u.name,sc?sc.name:'your school',kind),now=Date.now();
    const st=ai.ok===true?'approved':'pending';
    await env.DB.prepare("INSERT INTO id_checks(uid,kind,photo,status,ai,reason,created,updated) VALUES(?,?,?,?,?,NULL,?,?) ON CONFLICT(uid) DO UPDATE SET kind=excluded.kind,photo=excluded.photo,status=excluded.status,ai=excluded.ai,reason=NULL,updated=excluded.updated").bind(u.id,kind,photo,st,ai.ok===true?'yes':ai.why||'',now,now).run();
    if(st==='approved'){await env.DB.prepare('UPDATE users SET vlevel=2 WHERE id=?').bind(u.id).run();await bumpVer(env);return J({ok:true,status:'approved'})}
    waitUntil(tg(env,'Student ID to check\n'+u.name+' ('+(sc?sc.short||sc.name:'')+') - '+u.phone+'\n'+(ai.why||'')+'\nReview it in Admin → Student IDs.'));return J({ok:true,status:'pending'})}
  if(path==='me/referral'){const u=await me(env,request);if(!u)return J({error:'Sign in first.'},401);await ensure(env);
    const code=await refCode(env,u),c=await env.DB.prepare('SELECT COUNT(*) n,SUM(ref_paid) p FROM users WHERE referred_by=?').bind(u.id).first();
    const cap=await refCap(env),month=(await env.DB.prepare('SELECT IFNULL(SUM(amt),0) s FROM credit_log WHERE uid=? AND amt>0 AND t>=?').bind(u.id,monthStart()).first()).s;
    return J({code,link:url.origin+'/?r='+code,invited:c.n||0,rewarded:c.p||0,credit:u.credit||0,reward:await refReward(env),minOrder:REF_MIN,cap,earnedMonth:month,pct:await creditPct(env)})}
  if(path==='me/notify'&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Sign in first.'},401);const b=await request.json().catch(()=>({}));
    await env.DB.prepare('UPDATE users SET email_notify=? WHERE id=?').bind(b.on?1:0,u.id).run();return J({ok:true})}
  // Forgotten password: a code goes to the account's confirmed email. The reply is the same whether or not the account exists.
  if(path==='auth/forgot'&&request.method==='POST'){await ensure(env);const b=await request.json().catch(()=>({})),raw=String(b.id||'').trim();
    if(!await allow(env,'fgt:'+ipOf(request),20,36e5))return slow();
    const u=await env.DB.prepare("SELECT * FROM users WHERE (matric=? OR phone=?) AND status!='deleted'").bind(raw.toUpperCase(),phoneN(raw)).first();
    const generic=J({ok:true,message:'If that account has a confirmed email, we have sent it a code.'});
    if(!u||!u.email_verified||!u.email||!await allow(env,'fgtu:'+u.id,4,36e5))return generic;
    const code=await newCode(env,'pw:'+u.id);await sendEmail(env,u.email,'Reset your Stall password',mailHtml('Reset your password',['Your code is:','<b style="font-size:28px;letter-spacing:4px;color:#0F172A">'+code+'</b>','It expires in 15 minutes. If you didn\'t ask to reset your password, ignore this email. Your password stays the same.']));
    return generic}
  if(path==='auth/reset'&&request.method==='POST'){await ensure(env);const b=await request.json().catch(()=>({})),raw=String(b.id||'').trim(),pw=String(b.password||'');
    if(!await allow(env,'rst:'+ipOf(request),30,36e5))return slow();
    const u=await env.DB.prepare("SELECT * FROM users WHERE (matric=? OR phone=?) AND status!='deleted'").bind(raw.toUpperCase(),phoneN(raw)).first();if(!u)return J({error:'That code is not right.'},400);
    if(pw.length<8||pw.length>100)return J({error:'Use at least 8 characters.'},400);
    const r=await useCode(env,'pw:'+u.id,b.code);if(r.error)return J(r,400);const salt=rnd(16);
    await env.DB.batch([env.DB.prepare('UPDATE users SET salt=?,pw=? WHERE id=?').bind(salt,await pbk(pw,salt),u.id),env.DB.prepare('DELETE FROM sessions WHERE uid=?').bind(u.id)]);
    return J({ok:true})}
  // Deletes the signed-in account (required by Google Play). Order and payment records stay for accounting, with the person's details removed.
  if(path==='me/delete'&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Sign in first.'},401);await ensure(env);
    const b=await request.json().catch(()=>({}));if(!await allow(env,'del:'+u.id,5,36e5))return slow();
    if(await pbk(String(b.password||''),u.salt)!==u.pw)return J({error:'That password is wrong.'},400);
    if(u.is_admin)return J({error:'Admins can\'t delete their account here. Ask another admin to remove your admin access first.'},400);
    const open=(await env.DB.prepare("SELECT COUNT(*) c FROM orders WHERE (buyer=? OR seller=?) AND status IN ('verified','disputed','under_review')").bind(u.id,u.id).first()).c;
    if(open)return J({error:'You have '+open+' order'+(open>1?'s':'')+' still in progress. Finish or cancel '+(open>1?'them':'it')+' first, so nobody loses money.'},400);
    const pend=(await env.DB.prepare("SELECT id FROM orders WHERE (buyer=? OR seller=?) AND status='pending'").bind(u.id,u.id).all()).results.map(r=>r.id);
    if(pend.length){await env.DB.batch(pend.map(id=>env.DB.prepare("UPDATE orders SET status='expired',updated=? WHERE id=?").bind(Date.now(),id)));await restock(env,pend)}
    const lids=(await env.DB.prepare('SELECT id FROM listings WHERE uid=?').bind(u.id).all()).results.map(r=>r.id),st=await env.DB.prepare('SELECT id FROM stores WHERE uid=?').bind(u.id).first();
    const iids=st?(await env.DB.prepare('SELECT id FROM store_items WHERE sid=?').bind(st.id).all()).results.map(r=>-r.id):[];
    await delPhotos(env,[...lids,...iids]);
    await env.DB.batch([env.DB.prepare('DELETE FROM listings WHERE uid=?').bind(u.id),...(st?[env.DB.prepare('DELETE FROM store_items WHERE sid=?').bind(st.id),env.DB.prepare('DELETE FROM stores WHERE id=?').bind(st.id)]:[]),
      env.DB.prepare('DELETE FROM sessions WHERE uid=?').bind(u.id),env.DB.prepare('DELETE FROM verify_requests WHERE uid=?').bind(u.id),
      env.DB.prepare("UPDATE reviews SET buyer_name='Deleted user' WHERE buyer=?").bind(u.id),
      env.DB.prepare("UPDATE orders SET buyer_name='Deleted user',buyer_phone='',addr=NULL,dphone=NULL WHERE buyer=?").bind(u.id),env.DB.prepare("UPDATE orders SET seller_name='Deleted user',seller_phone='' WHERE seller=?").bind(u.id),
      env.DB.prepare("UPDATE users SET name='Deleted user',matric=NULL,email=NULL,phone=?,place=NULL,biz=NULL,bank_code=NULL,bank_name=NULL,acct_no=NULL,acct_name=NULL,deliv_on=0,deliv_note=NULL,pw=?,salt=?,status='deleted',verified=0 WHERE id=?").bind('deleted-'+u.id,rnd(16),rnd(8),u.id)]);
    await bumpVer(env);await logA(env,null,'account','deleted their account','#'+u.id,{who:'Deleted user #'+u.id});
    return J({ok:true},200,{'set-cookie':'stall_s=; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=0'})}
  if(path==='password'&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Sign in first.'},401);
    const b=await request.json().catch(()=>({})),pw=String(b.password||'');
    if(!await allow(env,'pw:'+u.id,8,36e5))return slow();
    if(await pbk(String(b.old||''),u.salt)!==u.pw)return J({error:'Your current password is wrong.'},400);
    if(pw.length<8||pw.length>100)return J({error:'Use at least 8 characters.'},400);
    const salt=rnd(16),t=cookie(request,'stall_s');await env.DB.prepare('UPDATE users SET salt=?,pw=? WHERE id=?').bind(salt,await pbk(pw,salt),u.id).run();
    await env.DB.prepare('DELETE FROM sessions WHERE uid=? AND h!=?').bind(u.id,await sha(t)).run();return J({ok:true})}
  if(path==='logout'){const t=cookie(request,'stall_s');if(t)await env.DB.prepare('DELETE FROM sessions WHERE h=?').bind(await sha(t)).run();return J({ok:true},200,{'set-cookie':'stall_s=; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=0'})}
  if(path.startsWith('collect/')){const u=await me(env,request);if(!u)return J({error:'Sign in first.'},401);await ensure(env);const b=request.method==='POST'?await request.json().catch(()=>({})):{};
    const own=async code=>{const c=await env.DB.prepare('SELECT * FROM collections WHERE code=?').bind(String(code||'')).first();return c&&c.uid===u.id?c:null};
    if(path==='collect/create'&&request.method==='POST'){
      if(!(u.vlevel>=1||u.is_admin))return J({error:'Verify that you\'re a student first (Account → Verify you\'re a student), so your classmates know the collection is genuine.',verify:true},403);
      if(!await allow(env,'coll:'+u.id,10,864e5))return slow();
      const title=clean(b.title,80),cls=clean(b.cls,60),descr=clean(b.descr,300),amount=Math.round(+b.amount),expected=b.expected?Math.round(+b.expected):null;
      if(title.length<3)return J({error:'Give the collection a name, e.g. "CSC 301 handout".'},400);if(!(amount>=100&&amount<=500000))return J({error:'Enter an amount from ₦100 to ₦500,000 per person.'},400);
      if(expected!=null&&!(expected>=1&&expected<=3000))return J({error:'Enter how many people should pay (1 to 3,000), or leave it empty.'},400);
      let deadline=null;if(b.deadline){const m=/^(\d{4})-(\d{2})-(\d{2})$/.exec(b.deadline);if(!m)return J({error:'Pick a valid closing date.'},400);deadline=watMs(+m[1],+m[2]-1,+m[3]+1)-1;if(deadline<Date.now())return J({error:'The closing date has already passed.'},400)}
      if(b.bank_code){const code=String(b.bank_code),acct=String(b.acct_no||'').replace(/\D/g,'');if(!BANKS[code]||acct.length!==10)return J({error:'Choose a bank and enter a 10-digit account number.'},400);
        const r=await ps(env,'/bank/resolve?account_number='+acct+'&bank_code='+code).catch(()=>({status:false}));if(!r.status||!r.data||!r.data.account_name)return J({error:'Could not verify that account. Check the number and bank.'},400);
        await env.DB.prepare('UPDATE users SET bank_code=?,bank_name=?,acct_no=?,acct_name=?,bank_verified=1 WHERE id=?').bind(code,BANKS[code],acct,r.data.account_name,u.id).run();Object.assign(u,{bank_code:code,bank_name:BANKS[code],acct_no:acct,acct_name:r.data.account_name,bank_verified:1})}
      const sub=await subFor(env,u);if(sub.error)return J({error:sub.error,bank:true},400);
      let code;for(let i=0;i<5;i++){code=Array.from(crypto.getRandomValues(new Uint8Array(6)),x=>'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'[x%32]).join('');if(!await env.DB.prepare('SELECT 1 FROM collections WHERE code=?').bind(code).first())break}
      await env.DB.prepare('INSERT INTO collections(code,uid,title,cls,descr,amount,expected,deadline,status,created) VALUES(?,?,?,?,?,?,?,?,?,?)').bind(code,u.id,title,cls||null,descr||null,amount,expected,deadline,'open',Date.now()).run();
      await logA(env,u,'money','created a class collection',title+' · ₦'+amount+' each',{who:u.name+' ('+u.phone+')'});return J({ok:true,code,link:url.origin+'/?collect='+code})}
    if(path==='collect/mine'){const rs=(await env.DB.prepare('SELECT c.*,(SELECT COUNT(*) FROM collect_pays p WHERE p.cid=c.id) n,(SELECT IFNULL(SUM(amount),0) FROM collect_pays p WHERE p.cid=c.id) total FROM collections c WHERE c.uid=? ORDER BY c.created DESC LIMIT 100').bind(u.id).all()).results;
      return J({items:rs.map(c=>({code:c.code,title:c.title,cls:c.cls,amount:c.amount,expected:c.expected,deadline:c.deadline,open:collOpen(c),status:c.status,n:c.n,total:c.total,created:c.created})),bank:u.bank_verified&&u.acct_no?{bank:u.bank_name,acct:'••••'+String(u.acct_no).slice(-4),name:u.acct_name}:null})}
    if(path==='collect/view'){const c=await env.DB.prepare('SELECT c.*,r.name rname,r.vlevel rv,r.school_id rs FROM collections c JOIN users r ON r.id=c.uid WHERE c.code=?').bind(String(url.searchParams.get('code')||'').toUpperCase()).first();
      if(!c)return J({error:'This collection doesn\'t exist. Check the link with your class rep.'},404);const owner=c.uid===u.id||!!u.is_admin,st=await collectFee(env),ch=collectCharge(c.amount,st);
      const ps0=(await env.DB.prepare('SELECT id,uid,name,matric,amount,ref,ticked,created FROM collect_pays WHERE cid=? ORDER BY created DESC').bind(c.id).all()).results,mine=ps0.find(p=>p.uid===u.id),sch=c.rs?await schoolOf(env,c.rs):null;
      return J({c:{code:c.code,title:c.title,cls:c.cls,descr:c.descr,amount:c.amount,charge:ch,total:c.amount+ch,expected:c.expected,deadline:c.deadline,open:collOpen(c),status:c.status,rep:c.rname,repVerified:(c.rv||0)>=1,school:sch&&sch.short||sch&&sch.name||null},
        owner,mine:mine?{t:mine.created,ref:owner||mine?mine.ref:null}:null,n:ps0.length,total:ps0.reduce((a,p)=>a+p.amount,0),
        paid:ps0.map(p=>owner?{id:p.id,name:p.name,matric:p.matric,t:p.created,ref:p.ref,ticked:!!p.ticked}:{name:p.name,matric:mask(p.matric),t:p.created})})}
    if(path==='collect/status'&&request.method==='POST'){const c=await own(b.code);if(!c)return J({error:'Collection not found.'},404);
      await env.DB.prepare('UPDATE collections SET status=? WHERE id=?').bind(b.open?'open':'closed',c.id).run();return J({ok:true})}
    if(path==='collect/tick'&&request.method==='POST'){const c=await own(b.code);if(!c)return J({error:'Collection not found.'},404);
      await env.DB.prepare('UPDATE collect_pays SET ticked=? WHERE id=? AND cid=?').bind(b.on?1:0,+b.id,c.id).run();return J({ok:true})}
    if(path==='collect/csv'){const c=await own(url.searchParams.get('code'));if(!c)return J({error:'Collection not found.'},404);
      const rs=(await env.DB.prepare('SELECT name,matric,amount,ref,ticked,created FROM collect_pays WHERE cid=? ORDER BY created').bind(c.id).all()).results,L=[[c.title+(c.cls?' · '+c.cls:'')],['Amount per person (NGN)',c.amount],['Paid',rs.length+(c.expected?' of '+c.expected:'')],['Total collected (NGN)',rs.reduce((a,r)=>a+r.amount,0)],[],['#','Name','Matric number','Amount (NGN)','Date','Time (WAT)','Paystack reference','Received / collected']];
      rs.forEach((r,i)=>L.push([i+1,r.name,r.matric,r.amount,dayK(r.created),new Date(r.created+WAT).toISOString().slice(11,16),r.ref,r.ticked?'Yes':'']));
      return new Response('\ufeff'+L.map(r=>r.map(csvCell).join(',')).join('\r\n'),{headers:{'content-type':'text/csv; charset=utf-8','content-disposition':'attachment; filename="stall-collection-'+c.code+'.csv"','cache-control':'no-store'}})}
    return J({error:'Not found'},404)}
  // Suggested price for a new listing: what similar items on Stall (last 6 months) are listed or sold for.
  if(path==='price-hint'&&request.method==='GET'){const u=await me(env,request);if(!u)return J({error:'Not signed in'},401);await ensure(env);
    const ws=priceWords(url.searchParams.get('t')),cond=String(url.searchParams.get('cond')||'');if(!ws.length)return J({n:0});
    const key=ws.slice(0,4),since=Date.now()-180*864e5,lk=key.map(w=>'%'+w+'%'),or=key.map(()=>'LOWER(title) LIKE ?').join(' OR ');
    const L=(await env.DB.prepare("SELECT title,price,cond,sold,uid FROM listings WHERE review='live' AND created>? AND ("+or+") ORDER BY created DESC LIMIT 200").bind(since,...lk).all()).results;
    const I=(await env.DB.prepare("SELECT i.title,i.price,s.uid FROM store_items i JOIN stores s ON s.id=i.sid WHERE i.review='live' AND i.created>? AND ("+or.replace(/title/g,'i.title')+") ORDER BY i.created DESC LIMIT 100").bind(since,...lk).all()).results;
    const need=Math.max(1,Math.ceil(ws.length*.6)),hit=r=>{const t=' '+String(r.title).toLowerCase().replace(/[^a-z0-9 ]/g,' ')+' ';return ws.filter(w=>t.includes(' '+w+' ')).length>=need};
    let m=[...L,...I].filter(r=>r.uid!==u.id&&r.price>0&&hit(r));const same=m.filter(r=>r.cond&&r.cond===cond);if(cond&&same.length>=3)m=same;
    // Drop outliers (an "iPhone 11 case" among iPhone 11s): keep prices within a third and three times the middle one.
    if(m.length>=3){const md=m.map(r=>r.price).sort((a,b)=>a-b)[m.length>>1];m=m.filter(r=>r.price>=md/3&&r.price<=md*3)}
    if(m.length<3)return J({n:m.length});const p=m.map(r=>r.price).sort((a,b)=>a-b),q=x=>{const v=p[Math.min(p.length-1,Math.round(x*(p.length-1)))];return v>=1000?Math.round(v/100)*100:Math.round(v/50)*50};
    return J({n:m.length,sold:m.filter(r=>r.sold).length,low:q(.25),mid:q(.5),high:q(.75),cond:cond&&same.length>=3?cond:null})}
  if(path==='config')return J({creditPct:await creditPct(env),collectFee:await collectFee(env),fee:await feeCfg(env),freeSales:await freeSales(env),androidPkg:(await getK(env,'android_pkg'))||'',androidSha:(await getK(env,'android_sha'))||'',name:(await getK(env,'biz_name'))||'Stall',phone:(await getK(env,'support_phone'))||'',email:(await getK(env,'support_email'))||'',states:STATES},200,{'cache-control':'public, max-age=60'});
  if(path==='schools'&&request.method==='GET'){await ensure(env);return J({schools:(await env.DB.prepare('SELECT id,name,short,state,kind FROM schools WHERE active=1 ORDER BY name').all()).results,states:STATES},200,{'cache-control':'public, max-age=3600'})}
  if(path==='me/delivery'&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Sign in first.'},401);await ensure(env);
    const d=dlvIn(await request.json().catch(()=>({})));if(d.error)return J(d,400);
    await env.DB.prepare('UPDATE users SET deliv_on=?,deliv_fee=?,deliv_note=? WHERE id=?').bind(d.on,d.fee,d.note,u.id).run();await bumpVer(env);return J({ok:true,deliv:dlv({deliv_on:d.on,deliv_fee:d.fee,deliv_note:d.note})})}
  if(path==='me/school'&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Sign in first.'},401);await ensure(env);const b=await request.json().catch(()=>({})),sc=await pickSchool(env,b);if(sc.error)return J(sc,400);
    await env.DB.prepare('UPDATE users SET school_id=?,state=? WHERE id=?').bind(sc.id,sc.state,u.id).run();return J({ok:true,school:sc})}
  if(path==='me'){const u=await me(env,request);if(!u)return J({error:'Not signed in'},401);await ensure(env);
    const v=await env.DB.prepare('SELECT status,reason FROM verify_requests WHERE uid=?').bind(u.id).first(),ic=await env.DB.prepare('SELECT status,reason FROM id_checks WHERE uid=?').bind(u.id).first();
    return J({user:{...pub(u),schoolInfo:await schoolOf(env,u.school_id),verify:v?v.status:null,verifyReason:v&&v.reason,idCheck:ic?ic.status:null,idReason:ic&&ic.reason,mustVerify:(await getK(env,'require_verified'))==='1',freeLeft:await freeLeft(env,u.id)}})}
  if(path==='listings'&&request.method==='GET'){const u=await me(env,request);if(!u)return J({error:'Not signed in'},401);await sweep(env);await ensure(env);const NOW=Math.floor(Date.now()/6e4)*6e4;waitUntil(dailyCleanup(env));waitUntil(payJobs(env).catch(()=>{}));
    const sp=url.searchParams,ids=(sp.get('ids')||'').split(',').map(x=>+x.slice(1)).filter(x=>x>0).slice(0,60),w=[LIVE],v=[];let lim=Math.min(96,Math.max(1,+sp.get('n')||24)),off=Math.max(0,+sp.get('off')||0),total;
    const cut=Math.floor((NOW-2*864e5)/6e5)*6e5;
    if(sp.get('mine')){w.push('l.uid=?',"(l.review!='live' OR (l.sold=1 AND l.created<=?))");v.push(u.id,cut);lim=50;off=0}
    else if(ids.length){w.push("(l.review='live' OR l.uid=?)",`l.id IN (${ids.map(()=>'?').join(',')})`);v.push(u.id,...ids);lim=60;off=0}
    else{w.push("l.review='live'",'(l.sold=0 OR l.created>?)');v.push(cut);
      const q=(sp.get('q')||'').trim().slice(0,60),cat=sp.get('cat')||'all',scope=sp.get('scope')||'school';if(cat!=='all'){w.push('l.cat=?');v.push(cat)}
      if(scope==='school'&&u.school_id){w.push('l.school_id=?');v.push(u.school_id)}else if(scope==='state'&&u.state){w.push('l.state=?');v.push(u.state)}
      // Every word must appear somewhere in the title, description or meeting spot.
      for(const word of q.split(/\s+/).filter(Boolean).slice(0,5)){const k='%'+word+'%';w.push('(l.title LIKE ? OR l.descr LIKE ? OR l.spot LIKE ?)');v.push(k,k,k)}
      const mn=Math.round(+sp.get('min')||0),mx=Math.round(+sp.get('max')||0),cond=sp.get('cond');
      if(mn>0){w.push('l.price>=?');v.push(mn)}if(mx>0){w.push('l.price<=?');v.push(mx)}if(['New','Like new','Used'].includes(cond)){w.push('l.cond=?');v.push(cond)}
      if(sp.get('dl')==='1')w.push('u.deliv_on=1');if(sp.get('vf')==='1')w.push('(u.verified=1 OR u.vlevel>=1)');if(sp.get('r4')==='1')w.push('u.rating_n>0 AND u.rating_sum>=4*u.rating_n')}
    const wh=' FROM listings l JOIN users u ON u.id=l.uid LEFT JOIN schools sc ON sc.id=l.school_id WHERE '+w.join(' AND '),srt={lo:'l.price ASC,l.id DESC',hi:'l.price DESC,l.id DESC',top:'(u.rating_sum+6.0)/(u.rating_n+2) DESC,u.rating_n DESC,l.created DESC'}[sp.get('sort')]||`(IFNULL(l.featured_until,0)>${NOW}) DESC,l.created DESC,l.id DESC`;
    const feed=!ids.length&&!sp.get('mine'),run=async()=>{const total=feed?(await env.DB.prepare('SELECT COUNT(*) c'+wh).bind(...v).first()).c:undefined;
      const rs=(await env.DB.prepare('SELECT l.*,u.verified AS sv,u.vlevel AS svl,u.role AS srole,u.deliv_on,u.deliv_fee,u.deliv_note,u.rating_sum,u.rating_n,sc.short AS ssh,sc.name AS snm'+wh+' ORDER BY '+srt+' LIMIT ? OFFSET ?').bind(...v,lim,off).all()).results;
      // Searches also look in open stores, so "jollof" finds food stalls as well as listings.
      const sq=(sp.get('q')||'').trim().slice(0,60),words=sq.split(/\s+/).filter(Boolean).slice(0,5),sc2=sp.get('scope')||'school';let storeHits=[];
      if(feed&&words.length&&!off){const ww=["i.review='live'",'i.avail=1','s.isopen=1',LIVE],vv=[];for(const word of words){ww.push('(i.title LIKE ? OR i.descr LIKE ?)');vv.push('%'+word+'%','%'+word+'%')}
        if(sc2==='school'&&u.school_id){ww.push('s.school_id=?');vv.push(u.school_id)}else if(sc2==='state'&&u.state){ww.push('s.state=?');vv.push(u.state)}
        storeHits=(await env.DB.prepare('SELECT i.id,i.title,i.price,s.id sid,s.name sname,s.cat,s.emoji FROM store_items i JOIN stores s ON s.id=i.sid JOIN users u ON u.id=s.uid WHERE '+ww.join(' AND ')+' ORDER BY i.created DESC LIMIT 8').bind(...vv).all()).results
          .map(r=>({id:'I'+r.id,title:r.title,price:r.price,store:'S'+r.sid,storeName:r.sname,cat:r.cat,emoji:r.emoji}))}
      return{total,storeHits,listings:rs.map(r=>({sid:r.uid,id:'L'+r.id,deliv:dlv(r),rating:rat(r),vlevel:r.srole==='vendor'?0:r.svl||0,title:r.title,price:r.price,cat:r.cat,cond:r.cond,spot:r.spot,desc:r.descr,seller:r.seller,phone:r.phone,imgs:Array.from({length:r.n},(_,i)=>'/api/photo/'+r.id+'/'+i),t:r.created,sold:r.sold,featured:(r.featured_until||0)>NOW,featuredUntil:r.featured_until||0,verified:!!r.sv,qty:r.qty||1,qtyLeft:r.qty_left==null?(r.sold?0:1):r.qty_left,school:r.ssh||r.snm||'',state:r.state||'',review:r.review,reviewNote:feed?null:r.review_note}))}};
    if(!feed){const o=await run();o.listings.forEach(x=>{x.mine=x.sid===u.id;if(!x.mine)x.reviewNote=null});return J(o)}
    // Everyone at the same school (or state, or nationwide) with the same filters shares one cached copy, refreshed on any change.
    return edge('feed/'+(await ver(env))+'/'+encodeURIComponent(w.join('&')+'|'+v.join('|')+'|'+srt+'|'+lim+'|'+off),30,run)}
  if(path==='listings'&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Sign in first.'},401);
    if(u.role==='vendor'&&u.status!=='active')return J({error:'Your shop is not approved yet.'},403);
    const b=await request.json().catch(()=>({})),t=k=>String(b[k]||'').trim(),price=Math.round(+b.price),imgs=Array.isArray(b.imgs)?b.imgs:[];
    if(b.bank_code){if(!BANKS[b.bank_code])return J({error:'Choose a valid bank.'},400);
      const manual=!!b.bank_manual;
      await env.DB.prepare('UPDATE users SET bank_code=?,bank_name=?,acct_no=?,acct_name=?,bank_verified=? WHERE id=?').bind(b.bank_code,BANKS[b.bank_code],String(b.acct_no||'').replace(/\D/g,''),String(b.acct_name||'').trim(),manual?0:1,u.id).run();
      u.acct_no=b.acct_no;u.acct_name=b.acct_name;
      if(manual)waitUntil(tg(env,'Payout details need confirming\n'+u.name+' - '+u.phone+'\nBank: '+BANKS[b.bank_code]+'\nAccount: '+b.acct_no+'\nName given: '+b.acct_name))}
    if(!u.acct_no||!u.acct_name)return J({error:'Add and verify your payout bank details first.'},400);
    if(u.role==='student'&&!(u.vlevel>=1)&&(await getK(env,'require_verified'))==='1')return J({error:'Verify that you\'re a student before you sell: confirm your school email or upload your student ID in Account → Verify.',verify:true},403);
    if(t('title').length<3||t('title').length>80)return J({error:'Enter a title of 3 to 80 characters.'},400);
    if(!(price>=MIN_PRICE&&price<=10000000))return J({error:price>=1&&price<MIN_PRICE?'The minimum price is ₦500.':'Enter a valid price.'},400);
    if(imgs.length<1||imgs.length>8||!imgs.every(imgOk))return J({error:'Add 1 to 8 photos (JPEG, PNG or WebP).'},400);
    if(!await allow(env,'post:'+u.id,40,36e5))return slow();
    const qty=Math.round(+b.qty||1);if(!(qty>=1&&qty<=100000))return J({error:'Enter how many you have (1 or more).'},400);
    if(!u.school_id)return J({error:'Choose your school first.'},400);await ensure(env);
    const r=await env.DB.prepare("INSERT INTO listings(uid,title,price,cat,cond,spot,descr,seller,phone,n,created,school_id,state,qty,qty_left,review) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,'checking')").bind(u.id,t('title'),price,t('cat').slice(0,20),t('cond').slice(0,20),t('spot').slice(0,60),t('desc').slice(0,500),t('seller').slice(0,50)||u.name,t('phone').slice(0,20)||u.phone,imgs.length,Date.now(),u.school_id,u.state,qty,qty).run();
    const id=r.meta.last_row_id;
    await savePhotos(env,id,imgs);
    waitUntil(reviewItem(env,'listings',id,imgs[0],t('title'),t('cat'),t('desc')));
    await bump();return J({ok:true,id:'L'+id,checking:true})}
  if(path==='listings/stock'&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Sign in first.'},401);const b=await request.json().catch(()=>({})),id=+String(b.id||'').slice(1),n=Math.round(+b.qty);
    if(!(n>=0&&n<=100000))return J({error:'Enter a number from 0 up.'},400);
    const r=await env.DB.prepare('UPDATE listings SET qty_left=?,qty=MAX(qty,?),sold=? WHERE id=? AND uid=?').bind(n,n,n>0?0:1,id,u.id).run();if(!r.meta.changes)return J({error:'Listing not found.'},404);await bump();return J({ok:true})}
  if(path==='listings/delete'&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Sign in first.'},401);
    const b=await request.json().catch(()=>({})),id=+String(b.id||'').slice(1);
    const r=await env.DB.prepare('DELETE FROM listings WHERE id=? AND (uid=? OR ?=1)').bind(id,u.id,u.is_admin?1:0).run();
    if(r.meta.changes){await delPhotos(env,[id]);await bump()}return J({ok:true})}
  if(path==='listings/sold'&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Sign in first.'},401);const b=await request.json().catch(()=>({})),id=+String(b.id||'').slice(1);
    await env.DB.prepare('UPDATE listings SET sold=?,qty_left=CASE WHEN ? THEN 0 WHEN IFNULL(qty_left,0)>0 THEN qty_left ELSE 1 END WHERE id=? AND uid=?').bind(b.sold?1:0,b.sold?1:0,id,u.id).run();await bump();return J({ok:true})}
  if(path==='listings/ver')return edge('ver',10,async()=>({v:await ver(env)}));
  // Store logos: one small image per store, cached (the feed adds ?v= so a new logo shows straight away).
  if(path.startsWith('store-logo/')){const id=+path.split('/')[1],r=await env.DB.prepare('SELECT logo FROM stores WHERE id=?').bind(id).first();if(!r||!r.logo)return new Response('Not found',{status:404});
    const H={'cache-control':'public, max-age=86400','x-content-type-options':'nosniff'};
    if(r.logo.startsWith('r2:')){const o=env.PHOTOS&&await env.PHOTOS.get('logo/'+id);if(!o)return new Response('Not found',{status:404});return new Response(o.body,{headers:{...H,'content-type':r.logo.slice(3)}})}
    const{type,bytes}=b64bytes(r.logo);return new Response(bytes,{headers:{...H,'content-type':type}})}
  if(path.startsWith('photo/')){const [,l,n]=path.split('/'),H={'cache-control':'public, max-age=31536000, immutable','x-content-type-options':'nosniff'};let c=null;try{c=caches.default}catch(e){}
    if(c){const hit=await c.match(request).catch(()=>null);if(hit)return hit}
    const r=await env.DB.prepare('SELECT data FROM photos WHERE lid=? AND n=?').bind(+l,+n).first();if(!r)return new Response('Not found',{status:404});let res;
    if(r.data.startsWith('r2:')){const o=env.PHOTOS&&await env.PHOTOS.get('p/'+(+l)+'/'+(+n));if(!o)return new Response('Not found',{status:404});res=new Response(o.body,{headers:{...H,'content-type':r.data.slice(3)}})}
    else{const{type,bytes}=b64bytes(r.data);res=new Response(bytes,{headers:{...H,'content-type':type}})}
    if(c)waitUntil(c.put(request,res.clone()).catch(()=>{}));return res}
  if(path==='stores'&&request.method==='GET'){const u=await me(env,request);if(!u)return J({error:'Not signed in'},401);await ensure(env);const NOW=Math.floor(Date.now()/6e4)*6e4;
    const scope=url.searchParams.get('scope')||'school',mine=!!url.searchParams.get('mine'),w=[LIVE],v=[],up='(IFNULL(s.reach_until,0)>'+NOW+')';
    if(mine){w.push('s.uid=?');v.push(u.id)}
    else if(scope==='school'&&u.school_id){w.push("(s.school_id=? OR ("+up+" AND (s.reach='national' OR (s.reach='state' AND s.state=?))))");v.push(u.school_id,u.state)}
    else if(scope==='state'&&u.state){w.push("(s.state=? OR ("+up+" AND s.reach='national'))");v.push(u.state)}
    const run=async()=>{
    const ss=(await env.DB.prepare('SELECT s.*,u.role,u.phone AS up,u.matric,u.verified AS ov,u.vlevel AS svl,u.rating_sum,u.rating_n,sc.short AS ssh,sc.name AS snm FROM stores s JOIN users u ON u.id=s.uid LEFT JOIN schools sc ON sc.id=s.school_id WHERE '+w.join(' AND ')+' ORDER BY (IFNULL(s.featured_until,0)>'+NOW+') DESC,(s.school_id=?) DESC,s.created DESC LIMIT 300').bind(...v,u.school_id||0).all()).results;
    const sids=ss.map(x=>x.id),its=sids.length?(await env.DB.prepare('SELECT * FROM store_items WHERE sid IN ('+sids.map(()=>'?').join(',')+")"+(mine?'':" AND review='live'")+" ORDER BY created DESC").bind(...sids).all()).results:[];
    return{stores:ss.map(s=>({id:'S'+s.id,logo:s.logo?'/api/store-logo/'+s.id+'?v='+(s.logo_v||0):null,deliv:dlv(s),rating:rat(s),uid:s.uid,vlevel:s.role==='vendor'?0:s.svl||0,owner:s.role==='vendor'?'V-'+s.up:s.matric,name:s.name,emoji:s.emoji,cat:s.cat,desc:s.descr,spot:s.spot,phone:s.phone,open:!!s.isopen,vendor:!!s.vendor,featured:(s.featured_until||0)>NOW,featuredUntil:s.featured_until||0,verified:!!s.ov,school:s.ssh||s.snm||'',state:s.state||'',reach:(s.reach_until||0)>NOW?s.reach:'school',reachUntil:(s.reach_until||0)>NOW?s.reach_until:0,items:its.filter(i=>i.sid===s.id).map(i=>({id:'I'+i.id,title:i.title,price:i.price,desc:i.descr,avail:!!i.avail&&i.qty_left!==0,qtyLeft:i.qty_left,review:i.review,reviewNote:mine?i.review_note:null,imgs:Array.from({length:i.n},(_,k)=>'/api/photo/-'+i.id+'/'+k)}))}))}};
    return mine?J(await run()):edge('stores/'+(await ver(env))+'/'+encodeURIComponent(v.join('|')),30,run)}
  if(path.startsWith('stores/')&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Sign in first.'},401);await ensure(env);
    if(u.role==='vendor'&&u.status!=='active')return J({error:'Your shop is not approved yet.'},403);
    const b=await request.json().catch(()=>({})),mine=await env.DB.prepare('SELECT id FROM stores WHERE uid=?').bind(u.id).first(),ok=()=>bump().then(()=>J({ok:true}));
    if(path==='stores/create'){const d=b.d||{},ref=String(b.reference||'');
      if(!/^[\w-]{6,80}$/.test(ref))return J({error:'Invalid payment reference.'},400);
      // Older app versions: payment is checked here; newer ones go through pay/start and pay/confirm.
      if(await env.DB.prepare('SELECT 1 FROM pending_pay WHERE ref=?').bind(ref).first()){const f=await fulfil(env,ref);return f.error?J(f,400):J({ok:true,id:f.id})}
      if(mine||await env.DB.prepare('SELECT 1 FROM stores WHERE ref=?').bind(ref).first())return J({error:'You already have a store.'},409);
      const v=(await ps(env,'/transaction/verify/'+ref)).data||{};
      if(v.status!=='success'||v.amount!==500000||(v.metadata||{}).kind!=='store')return J({error:'Payment could not be confirmed. Contact Stall support with reference '+ref},402);
      const bad=storeBad(d);if(bad)return J({error:bad},400);const id=await makeStore(env,u,d,ref);
      await env.DB.prepare('INSERT OR IGNORE INTO payments(ref,uid,kind,target,label,days,amount,created) VALUES(?,?,?,?,?,?,?,?)').bind(ref,u.id,'store','S'+id,'Store: '+clean(d.name,40),null,STORE_FEE,Date.now()).run();
      await logA(env,u,'money','opened a store','Store: '+clean(d.name,40)+' · ₦'+STORE_FEE,{who:u.name+' ('+(u.biz||u.phone)+')'});return J({ok:true,id:'S'+id})}
    if(!mine)return J({error:'Open a store first.'},400);
    if(path==='stores/look'){const up={};if(b.emoji!=null)up.emoji=clean(b.emoji,12);
      if(b.removeLogo){up.logo=null;if(env.PHOTOS)await env.PHOTOS.delete('logo/'+mine.id).catch(()=>{})}
      else if(b.logo!=null){if(!imgOk(b.logo))return J({error:'Use a JPEG, PNG or WebP image.'},400);if(!await allow(env,'logo:'+u.id,10,36e5))return slow();
        if(env.PHOTOS){const{type,bytes}=b64bytes(b.logo);await env.PHOTOS.put('logo/'+mine.id,bytes,{httpMetadata:{contentType:type}});up.logo='r2:'+type}else up.logo=b.logo}
      const ks=Object.keys(up);if(!ks.length)return J({error:'Nothing to change.'},400);
      await env.DB.prepare('UPDATE stores SET '+ks.map(k=>k+'=?').join(',')+',logo_v=? WHERE id=?').bind(...ks.map(k=>up[k]),Date.now(),mine.id).run();return ok()}
    if(path==='stores/delivery'){const d=dlvIn(b);if(d.error)return J(d,400);await env.DB.prepare('UPDATE stores SET deliv_on=?,deliv_fee=?,deliv_note=? WHERE id=?').bind(d.on,d.fee,d.note,mine.id).run();return ok()}
    if(path==='stores/toggle'){await env.DB.prepare('UPDATE stores SET isopen=1-isopen WHERE id=?').bind(mine.id).run();return ok()}
    if(path==='stores/item'){const t=k=>String(b[k]||'').trim(),price=Math.round(+b.price),imgs=Array.isArray(b.imgs)?b.imgs:[];
      if(t('title').length<3||t('title').length>80)return J({error:'Enter a title of 3 to 80 characters.'},400);
      if(!(price>=MIN_PRICE&&price<=10000000))return J({error:price>=1&&price<MIN_PRICE?'The minimum price is ₦500.':'Enter a valid price.'},400);
      if(imgs.length<1||imgs.length>8||!imgs.every(imgOk))return J({error:'Add 1 to 8 photos (JPEG, PNG or WebP).'},400);
      if(!await allow(env,'post:'+u.id,60,36e5))return slow();
      const qs=b.qty===''||b.qty==null?null:Math.round(+b.qty);if(qs!==null&&!(qs>=0&&qs<=100000))return J({error:'Enter how many you have, or leave it empty for no limit.'},400);
      await ensure(env);const cat=(await env.DB.prepare('SELECT cat FROM stores WHERE id=?').bind(mine.id).first()||{}).cat||'';
      const r=await env.DB.prepare("INSERT INTO store_items(sid,title,price,descr,avail,n,created,qty_left,review) VALUES(?,?,?,?,1,?,?,?,'checking')").bind(mine.id,t('title'),price,t('desc').slice(0,300),imgs.length,Date.now(),qs).run(),id=r.meta.last_row_id;
      await savePhotos(env,-id,imgs);waitUntil(reviewItem(env,'store_items',id,imgs[0],t('title'),cat,t('desc')));return ok()}
    if(path==='stores/item/stock'){const n=b.qty===''||b.qty==null?null:Math.round(+b.qty);if(n!==null&&!(n>=0&&n<=100000))return J({error:'Enter a number from 0 up, or leave it empty for no limit.'},400);
      await env.DB.prepare('UPDATE store_items SET qty_left=? WHERE id=? AND sid=?').bind(n,+String(b.id||'').slice(1),mine.id).run();return ok()}
    const iid=+String(b.id||'').slice(1);
    if(path==='stores/item/avail'){await env.DB.prepare('UPDATE store_items SET avail=1-avail WHERE id=? AND sid=?').bind(iid,mine.id).run();return ok()}
    if(path==='stores/item/delete'){const r=await env.DB.prepare('DELETE FROM store_items WHERE id=? AND sid=?').bind(iid,mine.id).run();if(r.meta.changes)await delPhotos(env,[-iid]);return ok()}
    if(path==='stores/delete'){const its=(await env.DB.prepare('SELECT id FROM store_items WHERE sid=?').bind(mine.id).all()).results;
      await delPhotos(env,its.map(i=>-i.id));
      await env.DB.prepare('DELETE FROM store_items WHERE sid=?').bind(mine.id).run();await env.DB.prepare('DELETE FROM stores WHERE id=?').bind(mine.id).run();return ok()}
  }
const naira=n=>'₦'+Number(n||0).toLocaleString('en-NG');
const oRow=r=>({id:r.id,title:r.title,amount:r.amount,bank:r.bank_name,acct:r.acct_no,acctName:r.acct_name,status:r.status,deadline:r.deadline,code:r.status==='verified'?r.code:null,note:r.note,updated:r.updated,buyerName:r.buyer_name,buyerPhone:r.buyer_phone,sellerName:r.seller_name,sellerPhone:r.seller_phone,card:!!r.bank_ok&&!!env.PAYSTACK_SECRET,fee:r.fee!=null?r.fee:feeOf(r.amount),paidVia:r.paid_via||null,
  sub:r.sub!=null?r.sub:r.amount,deliv:{on:!!r.d_on,fee:r.d_fee||0,note:r.d_note||''},pickup:r.pickup||'',method:r.method||null,addr:r.addr||'',dphone:r.dphone||'',stage:r.dstage||null,track:JSON.parse(r.track||'[]'),rated:r.rated||null,payout:r.payout||null,paidAt:r.paid_at||null,holdUntil:r.paid_at?r.paid_at+HOLD_DAYS*864e5:null});
  if(path==='orders/create'&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Sign in first.'},401);if(!await allow(env,'ord:'+u.id,30,36e5))return slow();
    await sweep(env);
    const b=await request.json().catch(()=>({})),ids=Array.isArray(b.items)?b.items.slice(0,60):[];
    if(!ids.length)return J({error:'Your bag is empty.'},400);
    const counts={};ids.forEach(id=>counts[id]=(counts[id]||0)+1);
    const groups={},taken=[],undo=()=>taken.length?env.DB.batch(taken.map(([k,id,q])=>k==='listing'?env.DB.prepare('UPDATE listings SET qty_left=qty_left+?,sold=0 WHERE id=?').bind(q,id):env.DB.prepare('UPDATE store_items SET qty_left=qty_left+? WHERE id=?').bind(q,id))):null,
      fail=async(m)=>{await undo();return J({error:m},400)};
    for(const id of Object.keys(counts)){const q=counts[id],kind=id[0]==='L'?'listing':id[0]==='I'?'item':null,rid=+id.slice(1);
      if(!kind||!rid)return fail('Invalid item in bag.');
      if(kind==='listing'){const L=await env.DB.prepare("SELECT l.*,u.name un,u.phone up,u.acct_no,u.acct_name,u.bank_name,u.bank_code bcode,u.bank_verified bok,u.deliv_on,u.deliv_fee,u.deliv_note FROM listings l JOIN users u ON u.id=l.uid WHERE l.id=? AND l.review='live' AND "+LIVE).bind(rid).first();
        if(L&&L.uid===u.id)return fail("You can't buy your own item.");
        if(!L||L.sold)return fail('An item in your bag is no longer available.');
        if(!L.acct_no||!L.acct_name)return fail('The seller for "'+L.title+'" has not set up payment details yet.');
        const tk=await env.DB.prepare('UPDATE listings SET qty_left=qty_left-?,sold=CASE WHEN qty_left-?<=0 THEN 1 ELSE 0 END WHERE id=? AND qty_left>=?').bind(q,q,rid,q).run();
        if(!tk.meta.changes)return fail(L.qty_left>0?'Only '+L.qty_left+' of "'+L.title+'" left. Reduce the quantity in your bag.':'"'+L.title+'" just sold out.');taken.push(['listing',rid,q]);
        const gk='U'+L.uid;(groups[gk]=groups[gk]||{seller:L.uid,sname:L.un,sphone:L.up,bank:L.bank_name,acct:L.acct_no,acctName:L.acct_name,bcode:L.bcode,bok:L.bok,dl:dlv(L),pickup:L.spot||'',items:[]}).items.push({kind:'listing',ref_id:L.id,title:L.title,price:L.price,q,unique:true})}
      else{const I=await env.DB.prepare('SELECT i.*,s.id sid,s.name sname,s.phone sphone,s.isopen,s.acct,s.acct_name,s.bank,s.bank_code bcode,s.bank_verified bok,s.deliv_on,s.deliv_fee,s.deliv_note,s.spot sspot FROM store_items i JOIN stores s ON s.id=i.sid JOIN users u ON u.id=s.uid WHERE i.id=? AND '+LIVE).bind(rid).first();
        if(!I||!I.avail||!I.isopen||I.review!=='live')return fail('An item in your bag is no longer available.');
        const acctNo=I.acct;if(!acctNo||!I.acct_name)return fail('The store for "'+I.title+'" has not set up payment details yet.');
        if(I.qty_left!=null){const tk=await env.DB.prepare('UPDATE store_items SET qty_left=qty_left-? WHERE id=? AND qty_left>=?').bind(q,rid,q).run();
          if(!tk.meta.changes)return fail(I.qty_left>0?'Only '+I.qty_left+' of "'+I.title+'" left. Reduce the quantity in your bag.':'"'+I.title+'" just sold out.');taken.push(['item',rid,q])}
        const gk='S'+I.sid;(groups[gk]=groups[gk]||{seller:0,sname:I.sname,sphone:I.sphone,bank:I.bank,acct:acctNo,acctName:I.acct_name,bcode:I.bcode,bok:I.bok,dl:dlv(I),pickup:I.sspot||'',items:[]}).items.push({kind:'item',ref_id:I.id,title:I.title,price:I.price,q})}}
    for(const gk in groups)if(groups[gk].seller===0){const s=await env.DB.prepare('SELECT uid FROM stores WHERE id=?').bind(+gk.slice(1)).first();groups[gk].seller=s.uid;if(s.uid===u.id)return fail("You can't buy from your own store.")}
    // Every order is paid through Paystack, so the seller needs a payout account Paystack can pay into: a known bank, 10 digits, and a name that was checked.
    const now=Date.now(),made=[],okCard=g=>!!(BANKS[g.bcode]&&/^\d{10}$/.test(g.acct||'')&&g.bok);
    if(!env.PAYSTACK_SECRET)return fail('Payments are not set up yet. Please try again later.');
    for(const gk in groups){const g=groups[gk];if(!okCard(g)){waitUntil(tg(env,'A buyer could not pay '+g.sname+' ('+(g.sphone||'')+'): their payout account is not confirmed yet. Check Payouts in Admin.'));
      return fail('"'+g.items[0].title+'" can\'t be bought yet. The seller\'s bank account is still being checked. Remove it from your bag or try again later.')}}
    const fc=await feeCfg(env);
    for(const gk in groups){const g=groups[gk],amount=g.items.reduce((s,i)=>s+i.price*i.q,0);
      const title=g.items.length===1?(g.items[0].q>1?g.items[0].q+' × ':'')+g.items[0].title:g.items.length+' items';
      const r=await env.DB.prepare('INSERT INTO orders(buyer,seller,buyer_name,buyer_phone,seller_name,seller_phone,title,amount,bank_name,acct_no,acct_name,status,deadline,created,updated,bank_code,bank_ok,fee,sub,d_on,d_fee,d_note,pickup) VALUES(?,?,?,?,?,?,?,?,?,?,?,\'pending\',?,?,?,?,?,?,?,?,?,?,?)')
        .bind(u.id,g.seller,u.name,u.phone,g.sname,g.sphone||'',title,amount,g.bank,g.acct,g.acctName,now+PAY_WINDOW,now,now,BANKS[g.bcode]?g.bcode:null,okCard(g)?1:0,feeOf(amount,fc),amount,g.dl.on?1:0,g.dl.fee,g.dl.note||null,clean(g.pickup,60)||null).run();
      const oid=r.meta.last_row_id;
      await env.DB.batch(g.items.map(i=>env.DB.prepare('INSERT INTO order_items(oid,kind,ref_id,title,price,q) VALUES(?,?,?,?,?,?)').bind(oid,i.kind,i.ref_id,i.title,i.price,i.q)));
      made.push({id:oid,title,amount,bank:g.bank,acct:g.acct,acctName:g.acctName,sellerName:g.sname,sellerPhone:g.sphone||'',status:'pending',deadline:now+PAY_WINDOW,card:okCard(g)&&!!env.PAYSTACK_SECRET,fee:feeOf(amount,fc),sub:amount,deliv:g.dl,pickup:clean(g.pickup,60),method:null,stage:null,track:[]})}
    await bump();return J({orders:made})}
  if(path==='orders/mine'&&request.method==='GET'){const u=await me(env,request);if(!u)return J({error:'Not signed in'},401);await sweep(env);
    const rs=(await env.DB.prepare('SELECT * FROM orders WHERE buyer=? ORDER BY created DESC LIMIT 100').bind(u.id).all()).results;
    return J({orders:rs.map(oRow)})}
  if(path==='orders/selling'&&request.method==='GET'){const u=await me(env,request);if(!u)return J({error:'Not signed in'},401);await sweep(env);
    const rs=(await env.DB.prepare('SELECT * FROM orders WHERE seller=? ORDER BY created DESC LIMIT 100').bind(u.id).all()).results;
    return J({orders:rs.map(oRow)})}
  if(path==='orders/news'&&request.method==='GET'){const u=await me(env,request);if(!u)return J({error:'Not signed in'},401);await ensure(env);
    const sb=+url.searchParams.get('sb')||Date.now(),ss=+url.searchParams.get('ss')||Date.now();
    const rs=(await env.DB.prepare("SELECT id,title,amount,status,note,buyer,buyer_name,seller_name,updated,method,dstage,pickup FROM orders WHERE (buyer=? AND updated>? AND status IN ('verified','rejected','expired','refunded','released')) OR (seller=? AND updated>? AND (status IN ('released','disputed','refunded') OR (status='verified' AND IFNULL(dstage,'paid')='paid'))) ORDER BY updated DESC LIMIT 20").bind(u.id,sb,u.id,ss).all()).results;
    const cu=(await env.DB.prepare('SELECT COUNT(*) c FROM threads WHERE ((buyer=? AND last_at>b_seen) OR (seller=? AND last_at>s_seen)) AND last_by!=?').bind(u.id,u.id,u.id).first()).c;
    return J({chats:cu,news:rs.map(r=>({id:r.id,title:r.title,amount:r.amount,status:r.status,note:r.note,side:r.buyer===u.id?'buy':'sell',buyerName:r.buyer_name,sellerName:r.seller_name,updated:r.updated,method:r.method,stage:r.dstage,pickup:r.pickup}))},200,{'cache-control':'no-store'})}
  // Receipts are no longer used: every order is paid through Paystack.
  if(path==='orders/receipt')return J({error:'Pay for this order through Paystack from your Orders page.'},410);
  if(path.startsWith('push/')){await ensure(env);
    if(path==='push/key')return J({key:(await vapid(env)).pub});
    const u=await me(env,request);if(!u)return J({error:'Sign in first.'},401);const b=request.method==='POST'?await request.json().catch(()=>({})):{};
    if(path==='push/subscribe'&&request.method==='POST'){let ep;try{ep=new URL(String(b.endpoint||''))}catch(e){}
      if(!ep||ep.protocol!=='https:'||!PUSH_HOSTS.test(ep.hostname))return J({error:'That notification service is not supported.'},400);if(!await allow(env,'psub:'+u.id,20,36e5))return slow();
      await env.DB.prepare('INSERT INTO push_subs(endpoint,uid,created) VALUES(?,?,?) ON CONFLICT(endpoint) DO UPDATE SET uid=excluded.uid').bind(ep.href,u.id,Date.now()).run();return J({ok:true})}
    if(path==='push/unsubscribe'&&request.method==='POST'){await env.DB.prepare('DELETE FROM push_subs WHERE endpoint=? AND uid=?').bind(String(b.endpoint||''),u.id).run();return J({ok:true})}
    // Called by the service worker when a push arrives: hands over what to show, once.
    if(path==='push/inbox'){const rs=(await env.DB.prepare('SELECT id,title,body,url,tag FROM notes WHERE uid=? AND sent=0 AND t>? ORDER BY id DESC LIMIT 5').bind(u.id,Date.now()-2*864e5).all()).results;
      if(rs.length)await env.DB.prepare('UPDATE notes SET sent=1 WHERE uid=? AND id<=?').bind(u.id,rs[0].id).run();return J({notes:rs})}
    if(path==='push/test'&&request.method==='POST'){await ping(env,u.id,'Notifications are on','You\'ll hear from Stall when you sell something, get a message, or your order moves.','/');return J({ok:true})}
    return J({error:'Not found'},404)}
  // Chat between a buyer and a seller about one listing, store or order. Clients poll chat/msgs while a chat is open.
  if(path.startsWith('chat/')){const u=await me(env,request);if(!u)return J({error:'Sign in first.'},401);await ensure(env);
    const b=request.method==='POST'?await request.json().catch(()=>({})):{},now=Date.now();
    const mine=async id=>{const t=await env.DB.prepare('SELECT * FROM threads WHERE id=?').bind(+id).first();return t&&(t.buyer===u.id||t.seller===u.id)?t:null};
    if(path==='chat/open'&&request.method==='POST'){const ref=String(b.ref||''),k=ref[0],id=+ref.slice(1);let seller=0,buyer=u.id,title='';
      if(k==='L'){const l=await env.DB.prepare('SELECT uid,title FROM listings WHERE id=?').bind(id).first();if(l){seller=l.uid;title=l.title}}
      else if(k==='S'){const st=await env.DB.prepare('SELECT uid,name FROM stores WHERE id=?').bind(id).first();if(st){seller=st.uid;title=st.name}}
      else if(k==='O'){const o=await env.DB.prepare('SELECT buyer,seller,title FROM orders WHERE id=? AND (buyer=? OR seller=?)').bind(id,u.id,u.id).first();if(o){seller=o.seller;buyer=o.buyer;title='Order #'+id+' · '+o.title}}
      if(!seller)return J({error:'Not found.'},404);if(seller===buyer)return J({error:"That's your own."},400);
      if(!await allow(env,'chato:'+u.id,60,36e5))return slow();
      await env.DB.prepare('INSERT OR IGNORE INTO threads(buyer,seller,ref,title,created) VALUES(?,?,?,?,?)').bind(buyer,seller,ref,clean(title,90),now).run();
      const t=await env.DB.prepare('SELECT id FROM threads WHERE buyer=? AND seller=? AND ref=?').bind(buyer,seller,ref).first();return J({id:t.id})}
    if(path==='chat/list'){const rs=(await env.DB.prepare('SELECT t.*,ub.name bn,us.name sn,us.biz sbiz FROM threads t JOIN users ub ON ub.id=t.buyer JOIN users us ON us.id=t.seller WHERE (t.buyer=? OR t.seller=?) AND t.last_at IS NOT NULL ORDER BY t.last_at DESC LIMIT 60').bind(u.id,u.id).all()).results;
      return J({threads:rs.map(t=>{const b2=t.buyer===u.id;return{id:t.id,ref:t.ref,title:t.title,with:b2?(t.sbiz||t.sn):t.bn,role:b2?'buyer':'seller',last:t.last,lastAt:t.last_at,unread:t.last_by!==u.id&&(t.last_at||0)>(b2?t.b_seen:t.s_seen)}})})}
    if(path==='chat/msgs'){const t=await mine(url.searchParams.get('tid'));if(!t)return J({error:'Chat not found.'},404);const after=+url.searchParams.get('after')||0;
      const rs=(await env.DB.prepare('SELECT id,uid,body,t FROM msgs WHERE tid=? AND id>? ORDER BY id LIMIT 200').bind(t.id,after).all()).results;
      if(rs.length||!after)await env.DB.prepare('UPDATE threads SET '+(t.buyer===u.id?'b_seen':'s_seen')+'=? WHERE id=?').bind(now,t.id).run();
      const other=await env.DB.prepare('SELECT name,biz FROM users WHERE id=?').bind(t.buyer===u.id?t.seller:t.buyer).first();
      return J({thread:{id:t.id,ref:t.ref,title:t.title,with:other?(t.buyer===u.id?other.biz||other.name:other.name):''},msgs:rs.map(m=>({id:m.id,mine:m.uid===u.id,body:m.body,t:m.t}))})}
    if(path==='chat/send'&&request.method==='POST'){const t=await mine(b.tid);if(!t)return J({error:'Chat not found.'},404);
      const body=String(b.body||'').replace(/[<>]/g,'').trim().slice(0,1000);if(!body)return J({error:'Type a message.'},400);
      if(!await allow(env,'chat:'+u.id,40,6e5))return J({error:"You're sending messages too fast. Wait a moment."},429);
      const r=await env.DB.prepare('INSERT INTO msgs(tid,uid,body,t) VALUES(?,?,?,?)').bind(t.id,u.id,body,now).run();
      await env.DB.prepare('UPDATE threads SET last=?,last_at=?,last_by=?,'+(t.buyer===u.id?'b_seen':'s_seen')+'=? WHERE id=?').bind(body.slice(0,120),now,u.id,now,t.id).run();
      // Account numbers or talk of paying outside Stall: warn both sides, since those payments aren't protected.
      waitUntil(ping(env,t.buyer===u.id?t.seller:t.buyer,'New message from '+(u.biz||u.name.split(' ')[0]),body.slice(0,140),'/?go=messages&t='+t.id,'chat-'+t.id));
      const warn=/(^|\D)\d(?:[\s-]?\d){9}(\D|$)/.test(body)||/(pay|send|transfer).{0,20}(direct|outside|my account|acct)/i.test(body);
      return J({ok:true,id:r.meta.last_row_id,warn})}
    if(path==='chat/report'&&request.method==='POST'){const t=await mine(b.tid);if(!t)return J({error:'Chat not found.'},404);
      if(!await allow(env,'chatr:'+u.id,10,864e5))return slow();
      const last=(await env.DB.prepare('SELECT m.body,us.name FROM msgs m JOIN users us ON us.id=m.uid WHERE m.tid=? ORDER BY m.id DESC LIMIT 10').bind(t.id).all()).results.reverse().map(m=>m.name+': '+m.body).join('\n');
      await logA(env,u,'other','reported a chat',t.title||t.ref,{who:u.name+' ('+u.phone+')',detail:clean(b.reason,200)||'No reason given'});
      waitUntil(tg(env,'Chat reported by '+u.name+' ('+u.phone+')\n'+(t.title||t.ref)+'\nReason: '+(clean(b.reason,200)||'none')+'\n---\n'+last.slice(0,3000)));return J({ok:true})}
    return J({error:'Not found'},404)}
  if(path==='orders/rate'&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Not signed in'},401);await ensure(env);
    const b=await request.json().catch(()=>({})),stars=Math.round(+b.stars),body=clean(b.text,300);
    if(!(stars>=1&&stars<=5))return J({error:'Choose 1 to 5 stars.'},400);
    const o=await env.DB.prepare('SELECT * FROM orders WHERE id=? AND buyer=?').bind(+b.id,u.id).first();if(!o)return J({error:'Order not found.'},404);
    if(o.status!=='released')return J({error:'You can rate once you have your order.'},400);
    // Only the first rating counts: the update succeeds once per order.
    if(!(await env.DB.prepare('UPDATE orders SET rated=? WHERE id=? AND rated IS NULL').bind(stars,o.id).run()).meta.changes)return J({error:'You already rated this order.'},400);
    await env.DB.batch([env.DB.prepare('INSERT INTO reviews(oid,seller,buyer,buyer_name,title,stars,body,created) VALUES(?,?,?,?,?,?,?,?)').bind(o.id,o.seller,u.id,u.name,o.title,stars,body||null,Date.now()),
      env.DB.prepare('UPDATE users SET rating_sum=rating_sum+?,rating_n=rating_n+1 WHERE id=?').bind(stars,o.seller)]);
    await bumpVer(env);return J({ok:true})}
  if(path==='reviews'&&request.method==='GET'){const u=await me(env,request);if(!u)return J({error:'Not signed in'},401);await ensure(env);
    const sid=+url.searchParams.get('uid')||0,s=await env.DB.prepare('SELECT rating_sum,rating_n FROM users WHERE id=?').bind(sid).first();if(!s)return J({error:'Seller not found.'},404);
    const rs=(await env.DB.prepare('SELECT id,buyer_name,title,stars,body,created FROM reviews WHERE seller=? ORDER BY created DESC LIMIT 30').bind(sid).all()).results;
    // First name and initial only, so buyers aren't exposed.
    return J({rating:rat(s),reviews:rs.map(r=>({id:r.id,who:String(r.buyer_name||'Buyer').split(' ')[0]+(String(r.buyer_name||'').split(' ')[1]?' '+String(r.buyer_name).split(' ')[1][0]+'.':''),title:r.title,stars:r.stars,text:r.body||'',t:r.created}))})}
  if(path==='orders/stage'&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Not signed in'},401);
    const b=await request.json().catch(()=>({})),o=await env.DB.prepare('SELECT * FROM orders WHERE id=? AND seller=?').bind(+b.id,u.id).first();
    if(!o)return J({error:'Order not found.'},404);if(o.status!=='verified')return J({error:'Only paid orders can be updated.'},400);
    const steps=STAGES[o.method==='delivery'?'delivery':'pickup'],nx=steps[steps.indexOf(o.dstage||'paid')+1];
    if(!nx||b.stage!==nx)return J({error:'This order is already at that step.'},400);
    const now=Date.now();await env.DB.prepare('UPDATE orders SET dstage=?,track=?,updated=? WHERE id=?').bind(nx,track(o,nx,now),now,o.id).run();
    const msg={packed:['Your order is packed','is packed and will be on its way soon.'],on_way:['Your order is on the way','is on the way to you. Have your release code ready, and only give it once you have the item.'],ready:['Ready for pickup','is ready for pickup'+(o.pickup?' at '+esc(o.pickup):'')+'. Bring your release code.']}[nx];
    if(msg)waitUntil(notify(env,o.buyer,msg[0]+': '+o.title,msg[0],['<b>'+esc(o.title)+'</b> '+msg[1]],'Track your order',SITE(env)+'/?go=orders'));return J({ok:true,stage:nx})}
  if(path==='orders/code'&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Not signed in'},401);
    const b=await request.json().catch(()=>({})),id=+b.id,code=String(b.code||'').trim().toUpperCase();
    const o=await env.DB.prepare('SELECT * FROM orders WHERE id=? AND seller=?').bind(id,u.id).first();
    if(!o)return J({error:'Order not found.'},404);
    if(o.status!=='verified')return J({error:'This order has no active release code.'},400);
    if(!await allow(env,'code:'+id,6,36e5))return J({error:'Too many wrong codes for this order. Try again in an hour.'},429);
    if(o.code!==code)return J({error:'That code does not match this order.'},400);
    await release(env,o,'code');return J({ok:true})}
  if(path==='orders/received'&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Not signed in'},401);
    const b=await request.json().catch(()=>({})),o=await env.DB.prepare('SELECT * FROM orders WHERE id=? AND buyer=?').bind(+b.id,u.id).first();
    if(!o)return J({error:'Order not found.'},404);if(o.status!=='verified')return J({error:'This order is not waiting for you.'},400);
    await release(env,o,'buyer');return J({ok:true})}
  if(path==='orders/report'&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Not signed in'},401);
    const b=await request.json().catch(()=>({})),why=clean(b.reason,300),o=await env.DB.prepare('SELECT * FROM orders WHERE id=? AND buyer=?').bind(+b.id,u.id).first();
    if(!o)return J({error:'Order not found.'},404);if(o.status!=='verified')return J({error:'You can only report a problem before the order is complete.'},400);
    if(why.length<5)return J({error:'Tell us briefly what went wrong.'},400);
    await env.DB.prepare("UPDATE orders SET status='disputed',note=?,updated=? WHERE id=? AND status='verified'").bind('Buyer reported: '+why,Date.now(),o.id).run();
    waitUntil(notify(env,o.seller,'Problem reported: '+o.title,'A buyer reported a problem',['The buyer of <b>'+esc(o.title)+'</b> said: “'+esc(why)+'”.','The money stays on hold while the Stall team looks into it. Reply to the buyer in the app chat.'],'Open your orders',SITE(env)+'/?go=orders'));
    waitUntil(tg(env,'Problem reported on order #'+o.id+'\n'+o.title+' - ₦'+o.amount+'\nBuyer: '+o.buyer_name+' · Seller: '+o.seller_name+'\n'+why+'\nThe money is on hold. Decide in Admin → Flagged.'));return J({ok:true})}
  if(path==='orders/cancel'&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Not signed in'},401);
    const b=await request.json().catch(()=>({})),o=await env.DB.prepare('SELECT * FROM orders WHERE id=? AND seller=?').bind(+b.id,u.id).first();
    if(!o)return J({error:'Order not found.'},404);if(o.status!=='verified')return J({error:'Only paid orders waiting for delivery can be cancelled.'},400);
    const r=await refund(env,o,'Cancelled by the seller'+(clean(b.reason,120)?': '+clean(b.reason,120):'')+'. Your money is being refunded.');if(r.error)return J(r,502);
    waitUntil(tg(env,'Seller cancelled order #'+o.id+' ('+o.title+', ₦'+o.amount+'). Buyer refunded.'));return J({ok:true})}
  if(path.startsWith('admin/')){
    const a=await me(env,request);if(!a||(!a.is_admin&&!a.reviewer))return J({error:'Not allowed'},403);await ensure(env);
    const b=request.method==='POST'?await request.json().catch(()=>({})):{};
    const PS=20,pg=Math.max(0,Math.floor(+url.searchParams.get('page')||0)),q=(url.searchParams.get('q')||'').trim().slice(0,60),like='%'+q+'%';
    const list=async(from,cols,w,v,order,map=x=>x)=>{const wh=w.length?' WHERE '+w.join(' AND '):'';
      const total=(await env.DB.prepare('SELECT COUNT(*) c FROM '+from+wh).bind(...v).first()).c;
      const rs=(await env.DB.prepare('SELECT '+cols+' FROM '+from+wh+' ORDER BY '+order+' LIMIT ? OFFSET ?').bind(...v,PS,pg*PS).all()).results;
      return J({items:rs.map(map),total,ps:PS},200,{'cache-control':'no-store'})};
    if(path==='admin/summary'){await sweep(env);waitUntil(dailyCleanup(env));waitUntil(payJobs(env).catch(()=>{}));const c=s=>env.DB.prepare('SELECT COUNT(*) c FROM '+s),mid=new Date();mid.setUTCHours(-1,0,0,0);
      const r=(await env.DB.batch([c("orders WHERE status IN ('under_review','disputed')"),c("orders WHERE status='verified'"),c("users WHERE role='vendor' AND status='pending'"),c('users WHERE bank_verified=0'),c('stores WHERE bank_verified=0'),c("users WHERE role='student'"),c("users WHERE role='vendor'"),c('stores'),c("orders WHERE status='released'"),c('orders WHERE created>=?').bind(+mid)])).map(x=>x.results[0].c);
      if(!a.is_admin)return J({review:r[0]});
      const ai=JSON.parse(await getK(env,'ai_last')||'null'),mo=new Date();mo.setUTCDate(1);mo.setUTCHours(-1,0,0,0);
      const m=(await env.DB.batch([env.DB.prepare("SELECT COUNT(*) c FROM verify_requests WHERE status='pending'"),env.DB.prepare('SELECT IFNULL(SUM(amount),0) c FROM payments'),env.DB.prepare('SELECT IFNULL(SUM(amount),0) c FROM payments WHERE created>=?').bind(+mo),env.DB.prepare('SELECT (SELECT COUNT(*) FROM listings WHERE featured_until>?)+(SELECT COUNT(*) FROM stores WHERE featured_until>?) c').bind(Date.now(),Date.now()),env.DB.prepare('SELECT COUNT(*) c FROM users WHERE verified=1')])).map(x=>x.results[0].c);
      const q2=(await env.DB.batch([env.DB.prepare("SELECT (SELECT COUNT(*) FROM listings WHERE review IN ('review','checking'))+(SELECT COUNT(*) FROM store_items WHERE review IN ('review','checking')) c"),env.DB.prepare('SELECT COUNT(*) c FROM schools WHERE active=0')])).map(x=>x.results[0].c);
      return J({itemsReview:q2[0],schoolsPending:q2[1],verifyPending:m[0],earned:m[1],earnedMonth:m[2],boosts:m[3],verifiedCount:m[4],review:r[0],delivery:r[1],vendorsPending:r[2],banks:r[3]+r[4],students:r[5],vendors:r[6],stores:r[7],released:r[8],today:r[9],aiOn:!!env.AI,r2On:!!env.PHOTOS,webhook:!!(await getK(env,'webhook_seen')),aiLast:ai,psMode:!env.PAYSTACK_SECRET?'none':/^sk_live_/.test(env.PAYSTACK_SECRET)?'live':'test',bankLast:JSON.parse(await getK(env,'bank_last')||'null'),payoutLast:JSON.parse(await getK(env,'payout_last')||'null'),pushLast:JSON.parse(await getK(env,'push_last')||'null'),pushSubs:(await env.DB.prepare('SELECT COUNT(DISTINCT uid) c FROM push_subs').first()).c,emailOn:!!env.RESEND_API_KEY,emailFrom:env.EMAIL_FROM||'',emailLast:JSON.parse(await getK(env,'email_last')||'null'),idsPending:(await env.DB.prepare("SELECT COUNT(*) c FROM id_checks WHERE status='pending'").first()).c,requireVerified:(await getK(env,'require_verified'))==='1',refReward:await refReward(env),refCap:await refCap(env),creditPct:await creditPct(env),creditOut:(await env.DB.prepare('SELECT IFNULL(SUM(credit),0) c FROM users').first()).c,referrals:(await env.DB.prepare('SELECT COUNT(*) n,IFNULL(SUM(ref_paid),0) p FROM users WHERE referred_by IS NOT NULL').first()),schoolDomains:(await getK(env,'school_domains'))||'',studentsVerified:(await env.DB.prepare('SELECT COUNT(*) c FROM users WHERE vlevel>=1').first()).c,payoutsFailed:(await env.DB.prepare("SELECT COUNT(*) c FROM payouts WHERE status='failed'").first()).c,bal:await (async()=>{const v=JSON.parse(await getK(env,'bal_last')||'null');return v&&Date.now()-v.t<10*6e4?v:await balanceCheck(env).catch(()=>v)})(),autoMax:AUTO_MAX,held:(await env.DB.prepare("SELECT IFNULL(SUM(amount-IFNULL(fee,0)),0) c FROM orders WHERE status IN ('verified','disputed') AND paid_via='paystack'").first()).c,cleanupAt:+(await getK(env,'cleanup_at'))||0},200,{'cache-control':'no-store'})}
    if(path==='admin/orders'&&request.method==='GET'){await sweep(env);
      let st=a.is_admin?url.searchParams.get('status')||'flagged':'flagged';const w=[],v=[];
      if(st==='flagged')w.push("status IN ('under_review','disputed')");
      else if(st!=='all'){if(!['pending','under_review','disputed','verified','released','expired','rejected','refunded'].includes(st))st='under_review';w.push('status=?');v.push(st)}
      if(/^#?\d+$/.test(q)){w.push('id=?');v.push(+q.replace('#',''))}
      else if(q){w.push('(buyer_name LIKE ? OR seller_name LIKE ? OR title LIKE ? OR r_ref LIKE ? OR buyer_phone LIKE ? OR seller_phone LIKE ?)');v.push(like,like,like,like,like,like)}
      return list("orders LEFT JOIN (SELECT oid,who,action AS dact,t AS dt,MAX(id) AS mid FROM admin_log WHERE oid IS NOT NULL AND kind='payment' GROUP BY oid) d ON d.oid=orders.id",'id,title,amount,bank_name,acct_no,acct_name,status,deadline,note,buyer_name,buyer_phone,seller_name,seller_phone,r_amount,r_ref,created,updated,receipt IS NOT NULL AS has_r,r_amount IS NOT NULL AS sent,who,dact,dt,method,addr,dphone,dstage',w,v,st==='under_review'?'created ASC':'updated DESC',
        r=>({decidedBy:r.who,decision:r.dact,decidedAt:r.dt,sent:!!r.sent,id:r.id,title:r.title,amount:r.amount,bank:r.bank_name,acct:r.acct_no,acctName:r.acct_name,status:r.status,deadline:r.deadline,note:r.note,buyerName:r.buyer_name,buyerPhone:r.buyer_phone,sellerName:r.seller_name,sellerPhone:r.seller_phone,rAmount:r.r_amount,rRef:r.r_ref,created:r.created,updated:r.updated,hasReceipt:!!r.has_r,method:r.method,addr:r.addr,dphone:r.dphone,stage:r.dstage}))}
    if(path.startsWith('admin/receipt/')){const r=await env.DB.prepare('SELECT receipt FROM orders WHERE id=?').bind(+path.split('/')[2]).first(),m=r&&r.receipt&&r.receipt.match(/^data:(image\/[a-z]+);base64,(.*)$/s);
      if(!m)return new Response('Not found',{status:404});
      return new Response(Uint8Array.from(atob(m[2]),c=>c.charCodeAt(0)),{headers:{'content-type':m[1],'cache-control':'private, max-age=86400'}})}
    if(path==='admin/orders/decide'&&request.method==='POST'){const o=await env.DB.prepare("SELECT * FROM orders WHERE id=? AND status IN ('under_review','disputed')").bind(+b.id).first();if(!o)return J({error:'This order was already handled or has expired.'},404);
      const tgt='#'+o.id+' '+o.title+' ('+o.buyer_name+' → '+o.seller_name+', ₦'+o.amount+')';
      // Approve: a flagged payment gets its release code; a disputed order is released and the seller paid. Reject: the buyer is refunded.
      if(b.approve){if(o.status==='disputed'){await release(env,o,'admin');await logA(env,a,'payment','approved',tgt,{oid:o.id,detail:'Dispute closed, seller paid'})}
        else{const code=o.code||relCode();await env.DB.prepare("UPDATE orders SET status='verified',code=?,paid_at=IFNULL(paid_at,?),updated=? WHERE id=?").bind(code,Date.now(),Date.now(),o.id).run();await logA(env,a,'payment','approved',tgt,{oid:o.id})}}
      else{const why=String(b.reason||'Cancelled by Stall').slice(0,200);
        if(o.paid_via==='paystack'){const r=await refund(env,o,why+'. Your money is being refunded.');if(r.error)return J(r,502)}
        else{await env.DB.prepare("UPDATE orders SET status='rejected',note=?,updated=? WHERE id=?").bind(why,Date.now(),o.id).run();await restock(env,[o.id]);await bump()}
        await logA(env,a,'payment','rejected',tgt,{oid:o.id,detail:why})}
      return J({ok:true})}
    if(!a.is_admin)return J({error:'Not allowed'},403);
    if(path==='admin/users'&&request.method==='GET'){const role=url.searchParams.get('role'),w=[],v=[];
      if(role==='student'||role==='vendor'){w.push('role=?');v.push(role)}else if(role==='reviewer')w.push('reviewer=1');
      if(q){w.push('(name LIKE ? OR matric LIKE ? OR phone LIKE ? OR email LIKE ? OR biz LIKE ?)');v.push(like,like,like,like,like)}
      if(role==='verified')w.push('verified=1');
      return list('users','id,role,name,matric,email,phone,biz,place,status,created,is_admin,reviewer,verified',w,v,'created DESC')}
    if(path==='admin/reviewers'&&request.method==='GET')return J({reviewers:(await env.DB.prepare('SELECT name,phone FROM users WHERE reviewer=1').all()).results});
    if(path==='admin/reviewers'&&request.method==='POST'){const ph=phoneN(b.phone);const r=await env.DB.prepare('UPDATE users SET reviewer=? WHERE phone=?').bind(b.add?1:0,ph).run();
      if(!r.meta.changes)return J({error:'No account found with that phone number.'},404);
      const t=await env.DB.prepare('SELECT name FROM users WHERE phone=?').bind(ph).first();await logA(env,a,'account',b.add?'made reviewer':'removed reviewer',t.name+' · '+ph);return J({ok:true})}
    if(path==='admin/codes'&&request.method==='GET'){const f=url.searchParams.get('f'),w=[],v=[];
      if(f==='unused')w.push('c.active=1 AND c.used_by IS NULL');else if(f==='used')w.push('c.used_by IS NOT NULL');else if(f==='off')w.push('c.active=0 AND c.used_by IS NULL');
      if(q){w.push('(c.code LIKE ? OR c.label LIKE ? OR u.biz LIKE ?)');v.push(like,like,like)}
      return list('vendor_codes c LEFT JOIN users u ON u.id=c.used_by','c.code,c.label,c.active,c.created,u.biz',w,v,'c.created DESC')}
    if(path==='admin/codes'&&request.method==='POST'){const label=String(b.label||'').trim().slice(0,40);if(label.length<2)return J({error:'Enter the vendor or shop name.'},400);
      const A='ABCDEFGHJKLMNPQRSTUVWXYZ23456789',code='STALL-'+[...crypto.getRandomValues(new Uint8Array(6))].map(x=>A[x%32]).join('');
      await env.DB.prepare('INSERT INTO vendor_codes(code,active,label,created) VALUES(?,1,?,?)').bind(code,label,Date.now()).run();await logA(env,a,'other','created code',label+' · '+code);return J({code,label})}
    if(path==='admin/code-off'){const r=await env.DB.prepare('UPDATE vendor_codes SET active=0 WHERE code=? AND used_by IS NULL').bind(String(b.code||'')).run();if(r.meta.changes)await logA(env,a,'other','turned off code',String(b.code));return J({ok:true})}
    if(path==='admin/banks'&&request.method==='GET'){
      const uu=(await env.DB.prepare("SELECT id,name,phone,bank_name,acct_no,acct_name FROM users WHERE bank_verified=0 LIMIT 200").all()).results.map(x=>({kind:'user',...x}));
      const ss=(await env.DB.prepare("SELECT id,name,phone,bank,acct,acct_name FROM stores WHERE bank_verified=0 LIMIT 200").all()).results.map(x=>({kind:'store',...x}));
      const items=[...uu,...ss];return J({items,total:items.length,ps:items.length},200,{'cache-control':'no-store'})}
    if(path==='admin/ids'&&request.method==='GET'){const f=url.searchParams.get('f')||'pending',w=[],v=[];if(['pending','approved','rejected'].includes(f)){w.push('c.status=?');v.push(f)}
      if(q){w.push('(u.name LIKE ? OR u.phone LIKE ? OR u.matric LIKE ?)');v.push(like,like,like)}
      return list('id_checks c JOIN users u ON u.id=c.uid LEFT JOIN schools sc ON sc.id=u.school_id','c.uid,c.kind,c.status,c.ai,c.reason,c.updated,u.name,u.phone,u.matric,u.email,u.email_verified,sc.name AS school',w,v,"c.status='pending' DESC,c.updated DESC")}
    if(path.startsWith('admin/id-photo/')){const r=await env.DB.prepare('SELECT photo FROM id_checks WHERE uid=?').bind(+path.split('/')[2]).first(),m=r&&r.photo&&r.photo.match(/^data:(image\/[a-z]+);base64,(.*)$/s);
      if(!m)return new Response('Not found',{status:404});return new Response(Uint8Array.from(atob(m[2]),c=>c.charCodeAt(0)),{headers:{'content-type':m[1],'cache-control':'private, no-store'}})}
    if(path==='admin/ids/decide'&&request.method==='POST'){const c=await env.DB.prepare("SELECT c.*,u.name FROM id_checks c JOIN users u ON u.id=c.uid WHERE c.uid=? AND c.status='pending'").bind(+b.uid).first();if(!c)return J({error:'Already handled.'},404);
      const why=String(b.reason||'').slice(0,200);await env.DB.prepare('UPDATE id_checks SET status=?,reason=?,updated=? WHERE uid=?').bind(b.approve?'approved':'rejected',b.approve?null:why||'Not accepted',Date.now(),c.uid).run();
      if(b.approve){await env.DB.prepare('UPDATE users SET vlevel=MAX(vlevel,2) WHERE id=?').bind(c.uid).run();await bumpVer(env)}
      await logA(env,a,'account',b.approve?'approved a student ID':'rejected a student ID',c.name,{detail:why||null});return J({ok:true})}
    if(path==='admin/email-test'&&request.method==='POST'){const to=String(b.to||'').trim();if(!/^[^@\s]+@[^@\s]+\.[^@\s]{2,}$/.test(to))return J({error:'Enter an email address.'},400);
      if(!env.RESEND_API_KEY)return J({error:'RESEND_API_KEY is not set in Cloudflare yet.'},400);const r=await sendEmail(env,to,'Stall test email',mailHtml('It works',['This is a test email from your Stall admin. Order emails and codes will look like this.']));return r.error?J({error:'Resend said: '+r.error},502):J({ok:true})}
    if(path==='admin/sellerpay'&&request.method==='GET'){const f=url.searchParams.get('f')||'failed',w=[],v=[];if(['failed','processing','paid','queued'].includes(f)){w.push('p.status=?');v.push(f)}
      if(/^#?\d+$/.test(q)){w.push('p.oid=?');v.push(+q.replace('#',''))}else if(q){w.push('(o.seller_name LIKE ? OR o.title LIKE ?)');v.push(like,like)}
      return list('payouts p JOIN orders o ON o.id=p.oid','p.*,o.title,o.seller_name,o.seller_phone,o.bank_name,o.acct_no,o.acct_name',w,v,'p.updated DESC',
        r=>({oid:r.oid,amount:r.amount,status:r.status,err:r.err,tries:r.tries,how:r.how,ref:r.ref,updated:r.updated,title:r.title,sellerName:r.seller_name,sellerPhone:r.seller_phone,bank:r.bank_name,acct:r.acct_no,acctName:r.acct_name}))}
    if(path==='admin/sellerpay/retry'&&request.method==='POST'){if(!a.is_admin)return J({error:'Only admins can do this.'},403);const p=await env.DB.prepare('SELECT * FROM payouts WHERE oid=?').bind(+b.id).first();if(!p||p.status!=='failed')return J({error:'Only failed payouts can be retried.'},400);
      if(b.manual&&p.tries>0){const pv=await prevXfer(env,p.oid,p.tries);
        if(pv&&pv.st==='success'){await env.DB.batch([env.DB.prepare("UPDATE payouts SET status='paid',err=NULL,ref=?,updated=? WHERE oid=?").bind(pv.ref,Date.now(),p.oid),env.DB.prepare("UPDATE orders SET payout='paid' WHERE id=?").bind(p.oid)]);return J({error:'Paystack already paid this seller (transfer '+pv.ref+'). Don\'t pay them by hand. The order now shows as paid.'},409)}
        if(pv&&pv.st==='unknown')return J({error:'Stall could not check with Paystack whether this seller was already paid. Try again in a few minutes before paying by hand.'},503);
        if(pv)return J({error:'Paystack still has a transfer for this seller in progress ('+pv.ref+(pv.st==='otp'?', waiting for an OTP':'')+'). Approve it or ask Paystack to cancel it before paying by hand, so the seller isn\'t paid twice.'},409)}
      if(b.manual){await env.DB.batch([env.DB.prepare("UPDATE payouts SET status='paid',how='manual',err=NULL,updated=? WHERE oid=?").bind(Date.now(),p.oid),env.DB.prepare("UPDATE orders SET payout='paid' WHERE id=?").bind(p.oid)]);await logA(env,a,'money','marked a seller payout as paid by hand','Order #'+p.oid+' · ₦'+p.amount,{oid:p.oid});return J({ok:true,status:'paid'})}
      await env.DB.prepare("UPDATE payouts SET status='queued',auto=0 WHERE oid=?").bind(p.oid).run();const r=await payOut(env,p.oid);await logA(env,a,'money','retried a seller payout','Order #'+p.oid+' · ₦'+p.amount,{oid:p.oid,detail:r&&r.status});return J({ok:true,status:r&&r.status,err:r&&r.err})}
    if(path==='admin/review/delete'&&request.method==='POST'){if(!a.is_admin)return J({error:'Only admins can remove reviews.'},403);const r=await env.DB.prepare('SELECT * FROM reviews WHERE id=?').bind(+b.id).first();if(!r)return J({error:'Review not found.'},404);
      await env.DB.batch([env.DB.prepare('DELETE FROM reviews WHERE id=?').bind(r.id),env.DB.prepare('UPDATE users SET rating_sum=MAX(0,rating_sum-?),rating_n=MAX(0,rating_n-1) WHERE id=?').bind(r.stars,r.seller)]);
      await bumpVer(env);await logA(env,a,'other','removed a review',r.stars+'★ on '+(r.title||'order #'+r.oid),{detail:r.body||''});return J({ok:true})}
    if(path==='admin/bank-confirm'&&request.method==='POST'){const tbl=b.kind==='store'?'stores':'users';
      await env.DB.prepare('UPDATE '+tbl+' SET bank_verified=1 WHERE id=?').bind(+b.id).run();
      const t=await env.DB.prepare('SELECT name,acct_name FROM '+tbl+' WHERE id=?').bind(+b.id).first();await logA(env,a,'account','confirmed payout details',t?t.name+' · '+t.acct_name:'#'+b.id);return J({ok:true})}
    if(path==='admin/vendors'&&request.method==='GET'){const st=url.searchParams.get('status'),w=["role='vendor'"],v=[];
      if(['pending','active','suspended'].includes(st)){w.push('status=?');v.push(st)}
      if(q){w.push('(name LIKE ? OR biz LIKE ? OR phone LIKE ? OR place LIKE ?)');v.push(like,like,like,like)}
      return list('users','id,name,biz,phone,place,cat,status,created',w,v,"status='pending' DESC,created DESC")}
    if(path==='admin/status'&&['active','suspended'].includes(b.status)){const t=await env.DB.prepare('SELECT id,name,phone,biz,role,status,is_admin FROM users WHERE id=?').bind(+b.id).first();
      if(!t)return J({error:'Account not found.'},404);if(t.is_admin)return J({error:'Admins cannot be suspended.'},400);
      await env.DB.prepare('UPDATE users SET status=? WHERE id=?').bind(b.status,t.id).run();
      if(b.status==='suspended')await env.DB.prepare('DELETE FROM sessions WHERE uid=?').bind(t.id).run();await bump();
      await logA(env,a,'account',b.status==='suspended'?'suspended':t.status==='pending'?'approved vendor':'reactivated',(t.biz?t.biz+' ('+t.name+')':t.name)+' · '+t.phone,{detail:b.reason});return J({ok:true})}
    if(path==='admin/reset-password'&&request.method==='POST'){const t=await env.DB.prepare('SELECT id,name,phone,is_admin FROM users WHERE id=?').bind(+b.id).first();
      if(!t)return J({error:'Account not found.'},404);if(t.is_admin)return J({error:"Admin passwords can't be reset here."},400);
      const A='abcdefghjkmnpqrstuvwxyz23456789',pw=[...crypto.getRandomValues(new Uint8Array(10))].map(x=>A[x%31]).join(''),salt=rnd(16);
      await env.DB.prepare('UPDATE users SET salt=?,pw=? WHERE id=?').bind(salt,await pbk(pw,salt),t.id).run();await env.DB.prepare('DELETE FROM sessions WHERE uid=?').bind(t.id).run();
      await logA(env,a,'account','reset password',t.name+' · '+t.phone);return J({ok:true,password:pw,name:t.name})}
    if(path==='admin/verify'&&request.method==='GET'){const f=url.searchParams.get('f'),w=[],v=[];if(['pending','approved','paid','rejected'].includes(f)){w.push('r.status=?');v.push(f)}
      if(q){w.push('(u.name LIKE ? OR u.phone LIKE ? OR u.biz LIKE ? OR u.matric LIKE ?)');v.push(like,like,like,like)}
      return list('verify_requests r JOIN users u ON u.id=r.uid','r.uid,r.note,r.status,r.reason,r.created,r.updated,u.name,u.phone,u.role,u.biz,u.matric,u.email',w,v,"r.status='pending' DESC,r.updated DESC")}
    if(path.startsWith('admin/verify-photo/')){const r=await env.DB.prepare('SELECT photo FROM verify_requests WHERE uid=?').bind(+path.split('/')[2]).first(),m=r&&r.photo&&r.photo.match(/^data:(image\/[a-z]+);base64,(.*)$/s);
      if(!m)return new Response('Not found',{status:404});return new Response(Uint8Array.from(atob(m[2]),c=>c.charCodeAt(0)),{headers:{'content-type':m[1],'cache-control':'private, max-age=3600'}})}
    if(path==='admin/verify/decide'&&request.method==='POST'){const t=await env.DB.prepare("SELECT u.name,u.phone,u.biz FROM verify_requests r JOIN users u ON u.id=r.uid WHERE r.uid=? AND r.status='pending'").bind(+b.uid).first();
      if(!t)return J({error:'This request was already handled.'},404);const why=b.approve?null:String(b.reason||'Could not confirm who you are').slice(0,200);
      await env.DB.prepare('UPDATE verify_requests SET status=?,reason=?,updated=? WHERE uid=?').bind(b.approve?'approved':'rejected',why,Date.now(),+b.uid).run();
      await logA(env,a,'account',b.approve?'approved verification':'rejected verification',(t.biz?t.biz+' ('+t.name+')':t.name)+' · '+t.phone,{detail:why});return J({ok:true})}
    if(path==='admin/unverify'&&request.method==='POST'){const t=await env.DB.prepare('SELECT name,phone FROM users WHERE id=?').bind(+b.id).first();if(!t)return J({error:'Account not found.'},404);
      await env.DB.prepare('UPDATE users SET verified=0 WHERE id=?').bind(+b.id).run();await env.DB.prepare("UPDATE verify_requests SET status='rejected',reason=?,updated=? WHERE uid=?").bind('Badge removed by Stall',Date.now(),+b.id).run();await bump();
      await logA(env,a,'account','removed verified badge',t.name+' · '+t.phone);return J({ok:true})}
    if(path==='admin/items'&&request.method==='GET'){const f=url.searchParams.get('f')||'review',st=f==='rejected'?"('rejected')":f==='live'?"('live')":"('review','checking')";
      const qq=q?' AND (x.title LIKE ? OR x.who LIKE ?)':'',vv=q?[like,like]:[];
      const base="SELECT 'L'||l.id AS id,l.id AS rid,'listing' AS kind,l.title,l.price,l.descr,l.cat,l.review,l.review_note,l.created,l.qty_left,u.name||' · '||u.phone AS who,sc.short AS school FROM listings l JOIN users u ON u.id=l.uid LEFT JOIN schools sc ON sc.id=l.school_id WHERE l.review IN "+st
        +" UNION ALL SELECT 'I'||i.id,i.id,'item',i.title,i.price,i.descr,s.cat,i.review,i.review_note,i.created,i.qty_left,s.name||' · '||s.phone,sc.short FROM store_items i JOIN stores s ON s.id=i.sid LEFT JOIN schools sc ON sc.id=s.school_id WHERE i.review IN "+st;
      const total=(await env.DB.prepare('SELECT COUNT(*) c FROM ('+base+') x WHERE 1'+qq).bind(...vv).first()).c;
      const items=(await env.DB.prepare('SELECT * FROM ('+base+') x WHERE 1'+qq+' ORDER BY created DESC LIMIT ? OFFSET ?').bind(...vv,PS,pg*PS).all()).results.map(x=>({...x,photo:x.kind==='listing'?'/api/photo/'+x.rid+'/0':'/api/photo/-'+x.rid+'/0'}));
      return J({items,total,ps:PS},200,{'cache-control':'no-store'})}
    if(path==='admin/items/decide'&&request.method==='POST'){const k=String(b.id||''),tbl=k[0]==='L'?'listings':'store_items',id=+k.slice(1),t=await env.DB.prepare('SELECT title FROM '+tbl+' WHERE id=?').bind(id).first();
      if(!t)return J({error:'Not found.'},404);const why=b.approve?null:String(b.reason||'Photo does not match the description').slice(0,200);
      await env.DB.prepare('UPDATE '+tbl+' SET review=?,review_note=? WHERE id=?').bind(b.approve?'live':'rejected',why,id).run();await bump();
      await logA(env,a,'account',b.approve?'approved listing':'rejected listing',t.title+' ('+k+')',{detail:why});return J({ok:true})}
    if(path==='admin/schools'&&request.method==='GET'){const f=url.searchParams.get('f')||'pending',w=[f==='pending'?'s.active=0':'s.active=1'],v=[];
      if(q){w.push('(s.name LIKE ? OR s.short LIKE ? OR s.state LIKE ?)');v.push(like,like,like)}
      return list('schools s','s.id,s.name,s.short,s.state,s.kind,s.active,s.created,(SELECT COUNT(*) FROM users WHERE school_id=s.id) AS users',w,v,'s.name')}
    if(path==='admin/schools/save'&&request.method==='POST'){const n=String(b.name||'').trim().slice(0,90),sh=String(b.short||'').trim().toUpperCase().slice(0,16)||null,st=String(b.state||'');
      if(n.length<4||!STATES.includes(st))return J({error:'Enter the full name and choose a state.'},400);
      if(b.id){await env.DB.prepare('UPDATE schools SET name=?,short=?,state=?,active=1 WHERE id=?').bind(n,sh,st,+b.id).run();await env.DB.batch(['users','listings','stores'].map(tb=>env.DB.prepare('UPDATE '+tb+' SET state=? WHERE school_id=?').bind(st,+b.id)))}
      else await env.DB.prepare('INSERT INTO schools(name,short,state,kind,active,created) VALUES(?,?,?,?,1,?)').bind(n,sh,st,String(b.kind||'university'),Date.now()).run();
      await logA(env,a,'other',b.id?'approved/updated school':'added school',n+' · '+st);return J({ok:true})}
    if(path==='admin/settings'&&request.method==='POST'){for(const k of ['biz_name','support_phone','support_email'])if(k in b)await setK(env,k,String(b[k]||'').trim().slice(0,120));
      if('ref_reward' in b){const v=Math.round(+b.ref_reward);if(!(v>=0&&v<=5000))return J({error:'Enter a referral reward from ₦0 to ₦5,000.'},400);await setK(env,'ref_reward',v)}
      if('ref_cap' in b){const v=Math.round(+b.ref_cap);if(!(v>=0&&v<=50000))return J({error:'Enter a monthly cap from ₦0 to ₦50,000.'},400);await setK(env,'ref_cap',v)}
      if('fee_rate' in b||'fee_min' in b||'fee_cap' in b){const c=await feeCfg(env),r='fee_rate' in b?Math.round(+b.fee_rate*10)/10:c.rate,mn='fee_min' in b?Math.round(+b.fee_min):c.min,cp='fee_cap' in b?Math.round(+b.fee_cap):c.cap;
        if(!(r>=0&&r<=20))return J({error:'Enter a fee rate from 0% to 20%.'},400);if(!(mn>=0&&mn<=5000))return J({error:'Enter a minimum fee from ₦0 to ₦5,000.'},400);
        if(!(cp>=0&&cp<=50000))return J({error:'Enter a maximum fee from ₦0 to ₦50,000.'},400);if(cp<mn)return J({error:'The maximum fee can\'t be lower than the minimum.'},400);
        await setK(env,'fee_rate',r);await setK(env,'fee_min',mn);await setK(env,'fee_cap',cp);await logA(env,a,'other','changed the sale fee',r+'%, min ₦'+mn+', max ₦'+cp)}
      if('collect_fee' in b){const v=Math.round(+b.collect_fee);if(!(v>=0&&v<=1000))return J({error:'Enter a class collection fee from ₦0 to ₦1,000.'},400);await setK(env,'collect_fee',v)}
      if('free_sales' in b){const v=Math.round(+b.free_sales);if(!(v>=0&&v<=20))return J({error:'Enter a number of sales from 0 to 20.'},400);await setK(env,'free_sales',v)}
      if('credit_pct' in b){const v=Math.round(+b.credit_pct);if(!(v>=0&&v<=100))return J({error:'Enter a percentage from 0 to 100.'},400);await setK(env,'credit_pct',v)}
      if('require_verified' in b)await setK(env,'require_verified',b.require_verified?'1':'0');
      if('school_domains' in b){const ds=String(b.school_domains||'').toLowerCase().split(/[\s,]+/).filter(Boolean);if(ds.some(x=>!/^[a-z0-9-]+(\.[a-z0-9-]+)+$/.test(x)))return J({error:'Enter domains like unilag.edu.ng, separated by commas.'},400);await setK(env,'school_domains',ds.join(','))}
      if('android_pkg' in b){const pk=String(b.android_pkg||'').trim(),sh=String(b.android_sha||'').toUpperCase().split(/[\s,]+/).filter(Boolean);
        if(pk&&!/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$/.test(pk))return J({error:'Enter the package name like app.stall.twa'},400);if(sh.some(x=>!/^([0-9A-F]{2}:){31}[0-9A-F]{2}$/.test(x)))return J({error:'Each fingerprint must look like AB:CD:… (32 pairs).'},400);
        await setK(env,'android_pkg',pk);await setK(env,'android_sha',sh.join(','))}await logA(env,a,'other','updated settings','Business and support details');return J({ok:true})}
    if(path==='admin/earnings'&&request.method==='GET'){if(!a.is_admin)return J({error:'Only admins can see earnings.'},403);
      const now=Date.now(),[Y,M,D]=dayK(now).split('-').map(Number),R={'7d':[7,'day'],'30d':[30,'day'],'90d':[90,'day'],'6m':[6,'month'],'12m':[12,'month'],'all':[0,'month']}[url.searchParams.get('range')]||[30,'day'];
      let from;if(R[1]==='day')from=watMs(Y,M-1,D-R[0]+1);else if(R[0])from=watMs(Y,M-R[0],1);else{const f=await env.DB.prepare('SELECT MIN(created) t FROM payments').first();const[y0,m0]=dayK(f&&f.t||now).split('-').map(Number);from=watMs(y0,m0-1,1)}
      const rows=await earnRows(env,from,now+1),keys=[];
      if(R[1]==='day')for(let t=from;t<=now;t+=864e5)keys.push(dayK(t));else{const[y0,m0]=dayK(from).split('-').map(Number);for(let y=y0,m=m0;y<Y||(y===Y&&m<=M);m===12?(y++,m=1):m++)keys.push(y+'-'+String(m).padStart(2,'0'))}
      const bk=Object.fromEntries(keys.map(k=>[k,{k,amt:0,n:0}]));for(const r of rows){const b=bk[dayK(r.t).slice(0,R[1]==='day'?10:7)];if(b){b.amt+=r.amount;if(r.amount>0)b.n++}}
      // Quick figures, always the same whatever range is picked.
      const lm=watMs(Y,M-2,1),q=(await earnRows(env,lm,now+1)),tot=(f,t)=>q.filter(r=>r.t>=f&&r.t<t).reduce((a,r)=>a+r.amount,0),d0=watMs(Y,M-1,D);
      return J({range:Object.keys({'7d':1,'30d':1,'90d':1,'6m':1,'12m':1,all:1}).find(k=>k===url.searchParams.get('range'))||'30d',unit:R[1],from:dayK(from),to:dayK(now),buckets:keys.map(k=>bk[k]),cats:sumCats(rows),
        total:rows.reduce((a,r)=>a+r.amount,0),count:rows.filter(r=>r.amount>0).length,
        quick:{today:tot(d0,now+1),yesterday:tot(d0-864e5,d0),week:tot(d0-6*864e5,now+1),month:tot(watMs(Y,M-1,1),now+1),lastMonth:tot(lm,watMs(Y,M-1,1))}})}
    if(path==='admin/earnings.csv'&&request.method==='GET'){if(!a.is_admin)return J({error:'Only admins can download earnings.'},403);
      const pd=x=>/^\d{4}-\d{2}-\d{2}$/.test(x||'')?x.split('-').map(Number):null,f=pd(url.searchParams.get('from')),t=pd(url.searchParams.get('to'));
      if(!f||!t)return J({error:'Pick a start and end date.'},400);const from=watMs(f[0],f[1]-1,f[2]),to=watMs(t[0],t[1]-1,t[2]+1);if(to<=from)return J({error:'The end date must be on or after the start date.'},400);
      const rows=await earnRows(env,from,to),type=url.searchParams.get('type')==='tx'?'tx':'summary',name=(await getK(env,'biz_name'))||'Stall',L=[],tm=r=>new Date(r.t+WAT).toISOString().slice(11,16);
      L.push([name+' earnings '+(type==='tx'?'(all transactions)':'(summary)')],['Period',dayK(from)+' to '+dayK(to-1)],['Generated',dayK(Date.now())+' '+new Date(Date.now()+WAT).toISOString().slice(11,16)+' WAT'],['Currency','NGN (Nigerian naira)'],
        ['Note','Amounts are what Stall kept: sale fees on orders and payments for its services. Money held for or paid to sellers is not included. Paystack charges are not deducted; see your Paystack settlement reports for those.'],[]);
      if(type==='summary'){L.push(['Type','Count','Amount (NGN)']);for(const c of sumCats(rows))L.push([c.label,c.n,c.amt]);L.push(['Total',rows.filter(r=>r.amount>0).length,rows.reduce((a,r)=>a+r.amount,0)],[],['Date','Payments','Amount (NGN)']);
        const by={};for(const r of rows){const k=dayK(r.t);by[k]=by[k]||{n:0,amt:0};by[k].amt+=r.amount;if(r.amount>0)by[k].n++}for(let x=from;x<to;x+=864e5){const k=dayK(x),v=by[k]||{n:0,amt:0};L.push([k,v.n,v.amt])}}
      else{L.push(['Date','Time (WAT)','Reference','Type','Description','Customer','Amount (NGN)']);const lab=Object.fromEntries(EARN_CATS);for(const r of rows)L.push([dayK(r.t),tm(r),r.ref,lab[r.cat]||r.cat,r.label,r.who,r.amount]);L.push([],['Total','','','','','',rows.reduce((a,r)=>a+r.amount,0)])}
      await logA(env,a,'money','downloaded earnings',(type==='tx'?'Transactions':'Summary')+' '+dayK(from)+' to '+dayK(to-1));
      return new Response('\ufeff'+L.map(r=>r.map(csvCell).join(',')).join('\r\n'),{headers:{'content-type':'text/csv; charset=utf-8','content-disposition':'attachment; filename="stall-earnings-'+type+'-'+dayK(from)+'-to-'+dayK(to-1)+'.csv"','cache-control':'no-store'}})}
    if(path==='admin/money'&&request.method==='GET'){const k=url.searchParams.get('kind'),w=[],v=[];if(['boost','verify','store','reach','commission'].includes(k)){w.push('p.kind=?');v.push(k)}
      if(q){w.push('(u.name LIKE ? OR u.phone LIKE ? OR p.label LIKE ? OR p.ref LIKE ?)');v.push(like,like,like,like)}
      return list('payments p LEFT JOIN users u ON u.id=p.uid','p.ref,p.kind,p.target,p.label,p.days,p.amount,p.created,u.name,u.phone',w,v,'p.created DESC')}
    if(path==='admin/log'&&request.method==='GET'){const k=url.searchParams.get('kind'),w=[],v=[];if(['payment','account','other','money'].includes(k)){w.push('kind=?');v.push(k)}
      if(/^#?\d+$/.test(q)){w.push('oid=?');v.push(+q.replace('#',''))}else if(q){w.push('(who LIKE ? OR target LIKE ? OR action LIKE ? OR detail LIKE ?)');v.push(like,like,like,like)}
      return list('admin_log','id,t,who,kind,action,oid,target,detail',w,v,'id DESC')}
    if(path==='admin/storage'&&request.method==='POST'&&b.move){if(!env.PHOTOS)return J({error:'Connect an R2 bucket named PHOTOS first.'},400);
      const rs=(await env.DB.prepare("SELECT rowid,lid,n,data FROM photos WHERE data NOT LIKE 'r2:%' LIMIT 150").all()).results;
      for(const r of rs){const{type,bytes}=b64bytes(r.data);await env.PHOTOS.put('p/'+r.lid+'/'+r.n,bytes,{httpMetadata:{contentType:type}});await env.DB.prepare('UPDATE photos SET data=? WHERE rowid=?').bind('r2:'+type,r.rowid).run()}
      const left=(await env.DB.prepare("SELECT COUNT(*) c FROM photos WHERE data NOT LIKE 'r2:%'").first()).c;if(rs.length)await logA(env,a,'other','moved photos to R2',rs.length+' photos',{detail:left+' left'});return J({moved:rs.length,left})}
    if(path==='admin/storage'){if(request.method==='POST')await cleanup(env,a);
      const r=(await env.DB.batch(["SELECT COUNT(*) c,IFNULL(SUM(LENGTH(data)),0) b,SUM(data LIKE 'r2:%') r2 FROM photos",'SELECT COUNT(*) c,IFNULL(SUM(LENGTH(receipt)),0) b FROM orders WHERE receipt IS NOT NULL'].map(x=>env.DB.prepare(x)))).map(x=>x.results[0]);
      return J({r2:!!env.PHOTOS,photosInR2:r[0].r2||0,photos:r[0].c,photoBytes:r[0].b,receipts:r[1].c,receiptBytes:r[1].b,cleanupAt:+(await getK(env,'cleanup_at'))||0,receiptDays:RECEIPT_DAYS,soldDays:SOLD_DAYS},200,{'cache-control':'no-store'})}
    return J({error:'Not found'},404);
  }
  if(path==='pay/confirm'&&request.method==='POST'&&!cookie(request,'stall_s')){await ensure(env);const b=await request.json().catch(()=>({})),ref=String(b.reference||'');
    if(!/^[\w-]{6,80}$/.test(ref))return J({error:'Invalid payment reference.'},400);const f=await fulfil(env,ref);return f.error?J(f,f.notPaid?402:400):J({...f,signedOut:true})}
  if(path.startsWith('pay/')||path.startsWith('verify/')){const u=await me(env,request);if(!u)return J({error:'Sign in first.'},401);await ensure(env);
    const b=request.method==='POST'?await request.json().catch(()=>({})):{};
    // What is being paid for, checked against the database. Returns {amount,label} or {error}.
    let m0={};const what=async(kind,target,days)=>{
      if(kind==='verify'){const v=await env.DB.prepare('SELECT status FROM verify_requests WHERE uid=?').bind(u.id).first();
        if(u.verified)return{error:'You are already verified.'};if(!v||v.status!=='approved')return{error:'Your verification has not been approved yet.'};return{amount:PRICE.verify,label:'Verified badge'}}
      if(kind==='reach'){const st=await env.DB.prepare('SELECT name FROM stores WHERE id=? AND uid=?').bind(+String(target).slice(1),u.id).first();if(!st)return{error:'Store not found.'};
        const lv=String(b.level||m0.level||'');if(!PRICE.reach[lv])return{error:'Choose state-wide or nationwide.'};return{amount:PRICE.reach[lv],label:st.name+' · '+(lv==='national'?'nationwide':'state-wide'),level:lv}}
      if(kind!=='boost'||![3,7].includes(days))return{error:'Choose 3 or 7 days.'};
      const id=+String(target).slice(1);
      if(target[0]==='L'){const l=await env.DB.prepare('SELECT title,sold FROM listings WHERE id=? AND uid=?').bind(id,u.id).first();if(!l)return{error:'Listing not found.'};if(l.sold)return{error:'This item is already sold.'};return{amount:PRICE.listing[days],label:l.title}}
      if(target[0]==='S'){const st=await env.DB.prepare('SELECT name FROM stores WHERE id=? AND uid=?').bind(id,u.id).first();if(!st)return{error:'Store not found.'};return{amount:PRICE.store[days],label:st.name}}
      return{error:'Nothing to feature.'}};
    if(path==='pay/start'&&request.method==='POST'){const kind=String(b.kind||''),target=String(b.target||''),days=+b.days||0;
      if(!env.PAYSTACK_SECRET)return J({error:'Payments are not set up yet.'},503);if(!await allow(env,'pay:'+u.id,20,36e5))return slow();
      let w,data={target,days};
      if(kind==='order'){const o=await env.DB.prepare('SELECT * FROM orders WHERE id=? AND buyer=?').bind(+target,u.id).first();if(!o)return J({error:'Order not found.'},404);
        if(o.status!=='pending'||Date.now()>o.deadline)return J({error:o.status==='pending'?'Your payment window has expired.':'This order is not waiting for payment.'},400);
        if(!o.bank_ok||!o.bank_code)return J({error:'This seller can\'t take payments yet. Their bank account is still being checked.'},400);
        const sub=await recipFor(env,o.bank_code,o.acct_no,o.acct_name);if(sub.error){waitUntil(tg(env,'Paystack would not set up payouts for '+o.seller_name+' ('+o.seller_phone+'): '+sub.error+'\nOrder #'+o.id+'. Ask them to check their bank details.'));
          return J({error:'This seller can\'t take payments right now. The Stall team has been told. Please try again later.'},502)}
        // Give the buyer time to finish on Paystack before the order can expire.
        await env.DB.prepare('UPDATE orders SET deadline=MAX(deadline,?) WHERE id=?').bind(Date.now()+PAY_WINDOW,o.id).run();
        const base=o.sub!=null?o.sub:o.amount,method=b.method==='delivery'?'delivery':'pickup',addr=clean(b.addr,160),dphone=clean(b.dphone,20)||u.phone;
        if(method==='delivery'){if(!o.d_on)return J({error:'This seller does not deliver. Choose pickup.'},400);if(addr.length<5)return J({error:'Enter where the seller should bring your order (hostel, room, landmark).'},400)}
        // Stall's fee is on the items only, not on the delivery fee.
        const total=base+(method==='delivery'?o.d_fee||0:0),fee=feeOf(base,await feeCfg(env));
        w={amount:total,label:o.title};data={oid:o.id,method,addr:method==='delivery'?addr:null,dphone:method==='delivery'?dphone:null,fee}}
      else if(kind==='collect'){const c=await env.DB.prepare('SELECT c.*,r.bank_code,r.acct_no,r.bank_verified,r.name rname FROM collections c JOIN users r ON r.id=c.uid WHERE c.code=?').bind(target).first();
        if(!c)return J({error:'Collection not found.'},404);if(!collOpen(c))return J({error:'This collection is closed.'},400);if(c.uid===u.id)return J({error:'You can\'t pay into your own collection.'},400);
        if(await env.DB.prepare('SELECT 1 FROM collect_pays WHERE cid=? AND uid=?').bind(c.id,u.id).first())return J({error:'You have already paid for this.'},400);
        const sub=await subFor(env,{name:c.rname,bank_code:c.bank_code,acct_no:c.acct_no,bank_verified:c.bank_verified});if(sub.error)return J({error:'The class rep\'s bank account isn\'t ready for payments yet. Ask them to check it on Stall.'},400);
        const st=await collectFee(env),ch=collectCharge(c.amount,st);w={amount:c.amount+ch,label:'Class: '+c.title,split:{subaccount:sub.code,transaction_charge:st*100,bearer:'subaccount'}};data={cid:c.id,code:c.code,amount:c.amount,fee:st}}
      else if(kind==='store'){if(u.role==='student'&&!(u.vlevel>=1)&&(await getK(env,'require_verified'))==='1')return J({error:'Verify that you\'re a student before you sell: confirm your school email or upload your student ID in Account → Verify.',verify:true},403);const d=b.d||{},bad=storeBad(d);if(bad)return J({error:bad},400);if(await env.DB.prepare('SELECT 1 FROM stores WHERE uid=?').bind(u.id).first())return J({error:'You already have a store.'},409);
        if(u.role==='vendor'&&u.status!=='active')return J({error:'Your shop is not approved yet.'},403);w={amount:STORE_FEE,label:'Store: '+clean(d.name,40)};data={d}}
      else{w=await what(kind,target,days);if(w.error)return J(w,400);data.level=w.level||null}
      // Credit can pay at most creditPct% of featuring or store reach; the rest goes through Paystack as usual.
      let cr=0;if(b.credit&&(kind==='boost'||kind==='reach')){cr=Math.min(u.credit||0,Math.floor(w.amount*(await creditPct(env))/100));if(cr<1)return J({error:'You don\'t have credit to use here.'},400)}
      if(cr&&cr>=w.amount){if(!(await env.DB.prepare('UPDATE users SET credit=credit-? WHERE id=? AND credit>=?').bind(cr,u.id,cr).run()).meta.changes)return J({error:'Not enough credit.'},400);
        await env.DB.prepare('INSERT INTO credit_log(uid,amt,why,t) VALUES(?,?,?,?)').bind(u.id,-cr,w.label||kind,Date.now()).run();
        const cref='CR'+rnd(8);await env.DB.prepare('INSERT INTO pending_pay(ref,uid,kind,data,amount,label,created,done) VALUES(?,?,?,?,?,?,?,0)').bind(cref,u.id,kind,JSON.stringify(data),w.amount,w.label||kind,Date.now()).run();
        const f=await fulfil(env,cref,{credit:true});if(f.error){await env.DB.prepare('UPDATE users SET credit=credit+? WHERE id=?').bind(cr,u.id).run();return J(f,400)}return J({...f,credit:true})}
      if(cr){data.credit=cr;w={...w,amount:w.amount-cr,label:(w.label||kind)+' (₦'+cr+' credit used)'}}
      const r=await ps(env,'/transaction/initialize',{method:'POST',body:JSON.stringify({email:u.email||('user'+u.phone+'@stall.app'),amount:w.amount*100,currency:'NGN',callback_url:url.origin+'/',metadata:{kind,target,days,uid:u.id,level:w.level||null},...(w.split||{})})});
      if(!r.status)return J({error:r.message||'Could not start payment.'},502);
      await env.DB.prepare('INSERT INTO pending_pay(ref,uid,kind,data,amount,label,created,done) VALUES(?,?,?,?,?,?,?,0)').bind(r.data.reference,u.id,kind,JSON.stringify(data),w.amount,w.label||kind,Date.now()).run();
      return J({url:r.data.authorization_url,ref:r.data.reference})}
    if(path==='pay/confirm'&&request.method==='POST'){const ref=String(b.reference||'');if(!/^[\w-]{6,80}$/.test(ref))return J({error:'Invalid payment reference.'},400);
      if(await env.DB.prepare('SELECT 1 FROM pending_pay WHERE ref=?').bind(ref).first()){const f=await fulfil(env,ref);return f.error?J(f,f.notPaid?402:400):J(f)}
      if(await env.DB.prepare('SELECT 1 FROM payments WHERE ref=?').bind(ref).first())return J({ok:true,already:true});
      const v=(await ps(env,'/transaction/verify/'+ref)).data||{},m=v.metadata||{};m0=m;
      if(v.status!=='success'||+m.uid!==u.id)return J({error:'Payment could not be confirmed. Contact Stall support with reference '+ref},402);
      const w=await what(m.kind,String(m.target||''),+m.days||0);if(w.error&&m.kind!=='verify')return J({error:w.error+' Contact Stall support with reference '+ref},400);
      const expect=m.kind==='verify'?PRICE.verify:w.amount;if(v.amount!==expect*100)return J({error:'Payment amount did not match. Contact Stall support with reference '+ref},402);
      const now=Date.now(),days=+m.days||0;let until=0;
      if(m.kind==='verify'){await env.DB.prepare('UPDATE users SET verified=1 WHERE id=?').bind(u.id).run();await env.DB.prepare("UPDATE verify_requests SET status='paid',updated=? WHERE uid=?").bind(now,u.id).run()}
      else if(m.kind==='reach'){const id=+m.target.slice(1),cur=await env.DB.prepare('SELECT reach,reach_until FROM stores WHERE id=?').bind(id).first()||{};
        until=(cur.reach===w.level&&(cur.reach_until||0)>now?cur.reach_until:now)+REACH_DAYS*864e5;await env.DB.prepare('UPDATE stores SET reach=?,reach_until=? WHERE id=?').bind(w.level,until,id).run();await bump()}
      else{const tbl=m.target[0]==='L'?'listings':'stores',id=+m.target.slice(1),cur=(await env.DB.prepare('SELECT featured_until f FROM '+tbl+' WHERE id=?').bind(id).first()||{}).f||0;
        until=Math.max(cur,now)+days*864e5;await env.DB.prepare('UPDATE '+tbl+' SET featured_until=? WHERE id=?').bind(until,id).run();await bump()}
      await env.DB.prepare('INSERT OR IGNORE INTO payments(ref,uid,kind,target,label,days,amount,created) VALUES(?,?,?,?,?,?,?,?)').bind(ref,u.id,m.kind,m.target||null,w.label||'Verified badge',m.kind==='reach'?REACH_DAYS:(days||null),expect,now).run();
      await logA(env,u,'money',m.kind==='verify'?'paid for verified badge':m.kind==='reach'?'upgraded store reach ('+w.level+', '+REACH_DAYS+' days)':'featured '+(m.target[0]==='L'?'listing':'store')+' for '+days+' days',(w.label||u.name)+' · ₦'+expect,{who:u.name+' ('+(u.biz||u.phone)+')'});
      return J({ok:true,kind:m.kind,until})}
    if(path==='verify/apply'&&request.method==='POST'){if(u.verified)return J({error:'You are already verified.'},400);
      const note=String(b.note||'').trim().slice(0,300),photo=String(b.photo||'');
      if(note.length<5)return J({error:'Tell us briefly who you are and what you sell.'},400);
      if(!imgOk(photo))return J({error:'Add a clear photo of your student ID card or shop.'},400);
      if(!await allow(env,'vapp:'+u.id,5,864e5))return slow();
      const cur=await env.DB.prepare('SELECT status FROM verify_requests WHERE uid=?').bind(u.id).first();if(cur&&['pending','approved'].includes(cur.status))return J({error:'Your request is already '+(cur.status==='pending'?'waiting for review.':'approved. Pay to activate your badge.')},400);
      await env.DB.prepare("INSERT INTO verify_requests(uid,note,photo,status,reason,created,updated) VALUES(?,?,?,'pending',NULL,?,?) ON CONFLICT(uid) DO UPDATE SET note=excluded.note,photo=excluded.photo,status='pending',reason=NULL,updated=excluded.updated").bind(u.id,note,photo,Date.now(),Date.now()).run();
      waitUntil(tg(env,'New verification request\n'+u.name+(u.biz?' ('+u.biz+')':'')+' - '+u.phone+'\nReview it in Admin: '+url.origin));return J({ok:true})}
    return J({error:'Not found'},404)}
  // Paystack calls this when a payment succeeds, so payments finish even if the buyer never comes back to Stall.
  if(path==='paystack/webhook'&&request.method==='POST'){const raw=await request.text(),sig=request.headers.get('x-paystack-signature')||'';
    if(!env.PAYSTACK_SECRET||sig!==await hmac512(env.PAYSTACK_SECRET,raw))return new Response('bad signature',{status:401});
    let ev={};try{ev=JSON.parse(raw)}catch(e){}waitUntil(setK(env,'webhook_seen',Date.now()).catch(()=>{}));if(ev.event==='charge.success'&&ev.data&&ev.data.reference)waitUntil(fulfil(env,String(ev.data.reference)).catch(()=>{}));
    // Paystack reports how each seller payout ended.
    if(/^transfer\.(success|failed|reversed)$/.test(ev.event||'')&&ev.data&&ev.data.reference)waitUntil((async()=>{await ensure(env);const ok=ev.event==='transfer.success',ref=String(ev.data.reference);
      const m=/^stallpay-(\d+)-\d+$/.exec(ref),p=await env.DB.prepare('SELECT * FROM payouts WHERE ref=? OR oid=?').bind(ref,m?+m[1]:-1).first();if(!p||p.status==='paid'||(!ok&&p.ref!==ref))return;const err=ok?null:'Paystack: transfer '+ev.event.split('.')[1]+(ev.data.reason?' ('+String(ev.data.reason).slice(0,120)+')':'');
      await env.DB.batch([env.DB.prepare('UPDATE payouts SET status=?,err=?,ref=?,updated=? WHERE oid=?').bind(ok?'paid':'failed',err,ref,Date.now(),p.oid),env.DB.prepare('UPDATE orders SET payout=? WHERE id=?').bind(ok?'paid':'failed',p.oid)]);
      if(!ok)await tg(env,'Seller payout failed for order #'+p.oid+' (₦'+p.amount+'). '+err+'\nRetry it in Admin → Seller pay.')})().catch(()=>{}));
    return new Response('ok')}
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
    if(!await allow(env,'bank:'+u.id,12,36e5))return slow();
    if(!env.PAYSTACK_SECRET){await setK(env,'bank_last',JSON.stringify({t:Date.now(),ok:false,err:'PAYSTACK_SECRET is not set in Cloudflare.'}));return J({error:'Account checking is not set up yet. Type the name on the account below instead.'},503)}
    const r=await ps(env,'/bank/resolve?account_number='+acct+'&bank_code='+code).catch(e=>({status:false,message:'Could not reach Paystack: '+(e&&e.message||e)}));
    if(!r.status||!r.data||!r.data.account_name){await setK(env,'bank_last',JSON.stringify({t:Date.now(),ok:false,err:String(r.message||'No account name returned').slice(0,200),bank:BANKS[code]}));
      return J({error:/limit/i.test(r.message||'')?'Account checking is busy right now. Type the name on the account below instead.':'Could not verify that account. Check the number and bank.'},400)}
    await setK(env,'bank_last',JSON.stringify({t:Date.now(),ok:true}));return J({name:r.data.account_name})}
  if(path==='verify'){
    const ref=url.searchParams.get('ref')||'';if(!/^[\w-]{6,80}$/.test(ref))return J({paid:false},400);
    const d=(await ps(env,'/transaction/verify/'+ref)).data||{};
    return J({paid:d.status==='success',amount:(d.amount||0)/100,kind:(d.metadata||{}).kind});
  }
  return J({error:'Not found'},404);
}
