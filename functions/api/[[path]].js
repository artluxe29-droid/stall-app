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
const SCHEMA_V='11';
const ensure=async env=>{if(ready)return;try{const r=await env.DB.prepare("SELECT v FROM settings WHERE k='schema_v'").first();if(r&&r.v===SCHEMA_V){ready=true;return}}catch(e){}await env.DB.batch(['CREATE TABLE IF NOT EXISTS admin_log(id INTEGER PRIMARY KEY AUTOINCREMENT,t INTEGER NOT NULL,uid INTEGER,who TEXT,kind TEXT,action TEXT,oid INTEGER,target TEXT,detail TEXT)','CREATE INDEX IF NOT EXISTS admin_log_oid ON admin_log(oid)','CREATE INDEX IF NOT EXISTS admin_log_t ON admin_log(t)','CREATE TABLE IF NOT EXISTS settings(k TEXT PRIMARY KEY,v TEXT)',
  'CREATE TABLE IF NOT EXISTS payments(ref TEXT PRIMARY KEY,uid INTEGER,kind TEXT,target TEXT,label TEXT,days INTEGER,amount INTEGER,created INTEGER)','CREATE INDEX IF NOT EXISTS payments_created ON payments(created)',
  'CREATE TABLE IF NOT EXISTS verify_requests(uid INTEGER PRIMARY KEY,note TEXT,photo TEXT,status TEXT,reason TEXT,created INTEGER,updated INTEGER)'].map(q=>env.DB.prepare(q)));
  for(const q of ['ALTER TABLE listings ADD COLUMN featured_until INTEGER','ALTER TABLE stores ADD COLUMN featured_until INTEGER','ALTER TABLE users ADD COLUMN verified INTEGER NOT NULL DEFAULT 0',
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
// Stall's cut of each order paid through Paystack: 5%, never more than ₦2,000. Stall pays Paystack's own fee out of it.
const COMMISSION={rate:.05,cap:2000},feeOf=a=>Math.min(Math.round(a*COMMISSION.rate),COMMISSION.cap);
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
async function recipFor(env,code,acct,name){const k=code+':'+acct,had=await env.DB.prepare('SELECT code FROM ps_recips WHERE k=?').bind(k).first();if(had)return{code:had.code};
  const r=await ps(env,'/transferrecipient',{method:'POST',body:JSON.stringify({type:'nuban',name:String(name||'Stall seller').slice(0,100),account_number:acct,bank_code:code,currency:'NGN'})}).catch(e=>({status:false,message:String(e&&e.message||e)}));
  if(!r.status||!r.data||!r.data.recipient_code){await setK(env,'payout_last',JSON.stringify({t:Date.now(),ok:false,err:String(r.message||'No recipient returned').slice(0,200)}));return{error:r.message||'Paystack could not set up this seller.'}}
  await env.DB.prepare('INSERT OR IGNORE INTO ps_recips(k,code,created) VALUES(?,?,?)').bind(k,r.data.recipient_code,Date.now()).run();return{code:r.data.recipient_code}}
// Sends the seller their share (order total minus Stall's fee). Safe to call again: a paid or in-flight payout is left alone.
async function payOut(env,oid){const o=await env.DB.prepare('SELECT * FROM orders WHERE id=?').bind(oid).first();if(!o||o.status!=='released'||o.paid_via!=='paystack')return null;const now=Date.now();
  await env.DB.prepare("INSERT OR IGNORE INTO payouts(oid,seller,amount,status,tries,created,updated) VALUES(?,?,?,'queued',0,?,?)").bind(o.id,o.seller,o.amount-(o.fee||0),now,now).run();
  const p=await env.DB.prepare('SELECT * FROM payouts WHERE oid=?').bind(o.id).first();if(['paid','processing'].includes(p.status))return p;
  const set=async(st,err,ref)=>{await env.DB.batch([env.DB.prepare('UPDATE payouts SET status=?,err=?,ref=IFNULL(?,ref),tries=tries+?,updated=? WHERE oid=?').bind(st,err||null,ref||null,ref?1:0,Date.now(),o.id),env.DB.prepare('UPDATE orders SET payout=? WHERE id=?').bind(st,o.id)]);
    await setK(env,'payout_last',JSON.stringify({t:Date.now(),ok:st!=='failed',err:err||null}));if(st==='failed')await tg(env,'Seller payout failed for order #'+o.id+' ('+o.seller_name+', ₦'+p.amount+'): '+err+'\nRetry it in Admin → Seller pay.');return{...p,status:st,err}};
  const rc=await recipFor(env,o.bank_code,o.acct_no,o.acct_name);if(rc.error)return set('failed','Paystack would not accept the seller\'s bank account: '+rc.error);
  const ref='stallpay-'+o.id+'-'+(p.tries+1),r=await ps(env,'/transfer',{method:'POST',body:JSON.stringify({source:'balance',amount:p.amount*100,recipient:rc.code,reference:ref,reason:'Stall order #'+o.id})}).catch(e=>({status:false,message:String(e&&e.message||e)}));
  const st=r.data&&r.data.status;
  if(r.status&&st==='success')return set('paid',null,ref);
  if(r.status&&['pending','received','queued'].includes(st))return set('processing',null,ref);
  if(r.status&&st==='otp')return set('failed','Paystack is asking for an OTP. In Paystack go to Settings → Preferences and turn off "Confirm transfers before sending", then retry.',ref);
  return set('failed',String(r.message||'Transfer failed').slice(0,200),ref)}
// Releases a held order to the seller. Only a paid (or disputed) order can be released, and only once.
async function release(env,o,how){const now=Date.now();
  const ch=(await env.DB.prepare("UPDATE orders SET status='released',code_used=?,dstage='done',track=?,updated=? WHERE id=? AND status IN ('verified','disputed')").bind(how==='code'?1:0,track(o,'done',now),now,o.id).run()).meta.changes;
  if(ch)await payOut(env,o.id);return!!ch}
// Gives the buyer their money back and puts the stock back. Orders not paid through Paystack are just cancelled.
async function refund(env,o,why){if(!['verified','disputed','under_review'].includes(o.status))return{error:'This order can no longer be refunded.'};
  if(o.paid_via==='paystack'&&o.r_ref){const r=await ps(env,'/refund',{method:'POST',body:JSON.stringify({transaction:o.r_ref})}).catch(e=>({status:false,message:String(e&&e.message||e)}));
    if(!r.status)return{error:'Paystack could not start the refund: '+(r.message||'unknown error')}}
  const ch=(await env.DB.prepare("UPDATE orders SET status='refunded',note=?,dstage=NULL,updated=? WHERE id=? AND status IN ('verified','disputed','under_review')").bind(why,Date.now(),o.id).run()).meta.changes;
  if(ch)await restock(env,[o.id]);await bumpVer(env);return{ok:true}}
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
  await env.DB.prepare('DELETE FROM sessions WHERE exp<?').bind(now).run();await env.DB.prepare('DELETE FROM attempts WHERE t<?').bind(now-D).run();
  await setK(env,'cleanup_at',now);const res={receipts:rc,listings:old.length,orphans:orph};
  if(a||rc||old.length||orph)await logA(env,a,'other','cleaned up storage','Storage',{detail:`Removed ${rc} old receipt photos, ${old.length} old sold listings, ${orph} unused photos`});
  return res}
const dailyCleanup=async env=>{try{const t=+(await getK(env,'cleanup_at'))||0;if(Date.now()-t>864e5){await setK(env,'cleanup_at',Date.now());await cleanup(env,null)}}catch(e){}};

const phoneN=p=>{let d=String(p||'').replace(/\D/g,'');if(d.startsWith('234')&&d.length===13)d='0'+d.slice(3);return d};
const pub=u=>({...pubBase(u),uid:u.id,school:u.school_id||null,deliv:dlv(u),rating:rat(u)});
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
  if(manual)await tg(env,'Payout details need confirming (store)\n'+clean(d.name,40)+' - '+u.phone+'\nBank: '+BANKS[d.bank_code]+'\nAccount: '+d.acct+'\nName given: '+clean(d.acctName,60));
  await bumpVer(env);return r.meta.last_row_id}
// Finishes a Paystack payment exactly once, however it arrives: the return page, the webhook, or both.
async function fulfil(env,ref){await ensure(env);const p=await env.DB.prepare('SELECT * FROM pending_pay WHERE ref=?').bind(ref).first();if(!p)return{error:'Unknown payment reference.'};
  if(p.done===1)return{ok:true,already:true,kind:p.kind,...JSON.parse(p.result||'{}')};if(p.done===2)return{ok:true,processing:true,kind:p.kind};
  const v=(await ps(env,'/transaction/verify/'+ref)).data||{};
  if(v.status!=='success')return{error:'Payment not completed. You were not charged.',notPaid:true};
  if(v.amount!==p.amount*100)return{error:'Payment amount did not match. Contact Stall support with reference '+ref};
  if(!(await env.DB.prepare('UPDATE pending_pay SET done=2 WHERE ref=? AND done=0').bind(ref).run()).meta.changes)return{ok:true,processing:true,kind:p.kind};
  const u=await env.DB.prepare('SELECT * FROM users WHERE id=?').bind(p.uid).first(),d=JSON.parse(p.data||'{}'),now=Date.now();let res={},label=p.label,act='';
  try{
    if(p.kind==='store'){const has=await env.DB.prepare('SELECT id FROM stores WHERE uid=?').bind(u.id).first();
      if(has){res={id:'S'+has.id,note:'You already had a store, so no new one was made. Contact Stall support for a refund with reference '+ref};act='paid store fee but already had a store (refund due)';await tg(env,'Refund due: '+u.name+' paid a store fee but already has a store. Ref '+ref)}
      else{res={id:'S'+await makeStore(env,u,d.d||{},ref)};act='opened a store'}}
    else if(p.kind==='order'){const o=await env.DB.prepare('SELECT * FROM orders WHERE id=?').bind(+d.oid).first(),fee=d.fee!=null?d.fee:feeOf(p.amount);
      if(!o)throw new Error('order missing');let st='verified',note=null;
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
      res={oid:o.id,fee,status:st};act='paid order #'+o.id+' through Paystack (Stall fee ₦'+fee+')';label=o.title}
    else if(p.kind==='verify'){await env.DB.prepare('UPDATE users SET verified=1 WHERE id=?').bind(u.id).run();await env.DB.prepare("UPDATE verify_requests SET status='paid',updated=? WHERE uid=?").bind(now,u.id).run();act='paid for verified badge'}
    else if(p.kind==='reach'){const id=+String(d.target).slice(1),cur=await env.DB.prepare('SELECT reach,reach_until FROM stores WHERE id=?').bind(id).first()||{};
      const until=(cur.reach===d.level&&(cur.reach_until||0)>now?cur.reach_until:now)+REACH_DAYS*864e5;await env.DB.prepare('UPDATE stores SET reach=?,reach_until=? WHERE id=?').bind(d.level,until,id).run();res={until};act='upgraded store reach ('+d.level+', '+REACH_DAYS+' days)'}
    else if(p.kind==='boost'){const tbl=String(d.target)[0]==='L'?'listings':'stores',id=+String(d.target).slice(1),cur=(await env.DB.prepare('SELECT featured_until f FROM '+tbl+' WHERE id=?').bind(id).first()||{}).f||0;
      const until=Math.max(cur,now)+d.days*864e5;await env.DB.prepare('UPDATE '+tbl+' SET featured_until=? WHERE id=?').bind(until,id).run();res={until};act='featured '+(tbl==='listings'?'listing':'store')+' for '+d.days+' days'}
    await bumpVer(env);
    const got=p.kind==='order'?res.fee:p.amount;
    await env.DB.prepare('INSERT OR IGNORE INTO payments(ref,uid,kind,target,label,days,amount,created) VALUES(?,?,?,?,?,?,?,?)').bind(ref,u.id,p.kind==='order'?'commission':p.kind,res.id||(p.kind==='order'?'O'+res.oid:d.target)||null,label,p.kind==='reach'?REACH_DAYS:(d.days||null),got,now).run();
    await env.DB.prepare('UPDATE pending_pay SET done=1,result=? WHERE ref=?').bind(JSON.stringify(res),ref).run();
    await logA(env,u,'money',act,label+' · ₦'+got,{who:u.name+' ('+(u.biz||u.phone)+')'});return{ok:true,kind:p.kind,...res}}
  catch(e){await env.DB.prepare('UPDATE pending_pay SET done=0 WHERE ref=?').bind(ref).run();return{error:'Could not finish this payment yet. It will be retried. Reference '+ref}}}
export async function onRequest({request,env,params,waitUntil}){
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
      if(vendor&&!t('code'))waitUntil(tg(env,'New vendor waiting for approval\n'+biz+' ('+name+')\n'+phone+' - '+t('where').slice(0,40)+'\nApprove it in Admin: '+url.origin));
      const u=await env.DB.prepare('SELECT * FROM users WHERE id=?').bind(r.meta.last_row_id).first();
      return J({user:pub(u)},200,{'set-cookie':await start(env,u.id)});
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
    return J({user:pub(u)},200,{'set-cookie':await start(env,u.id)});
  }
  if(path==='password'&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Sign in first.'},401);
    const b=await request.json().catch(()=>({})),pw=String(b.password||'');
    if(!await allow(env,'pw:'+u.id,8,36e5))return slow();
    if(await pbk(String(b.old||''),u.salt)!==u.pw)return J({error:'Your current password is wrong.'},400);
    if(pw.length<8||pw.length>100)return J({error:'Use at least 8 characters.'},400);
    const salt=rnd(16),t=cookie(request,'stall_s');await env.DB.prepare('UPDATE users SET salt=?,pw=? WHERE id=?').bind(salt,await pbk(pw,salt),u.id).run();
    await env.DB.prepare('DELETE FROM sessions WHERE uid=? AND h!=?').bind(u.id,await sha(t)).run();return J({ok:true})}
  if(path==='logout'){const t=cookie(request,'stall_s');if(t)await env.DB.prepare('DELETE FROM sessions WHERE h=?').bind(await sha(t)).run();return J({ok:true},200,{'set-cookie':'stall_s=; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=0'})}
  if(path==='config')return J({name:(await getK(env,'biz_name'))||'Stall',phone:(await getK(env,'support_phone'))||'',email:(await getK(env,'support_email'))||'',states:STATES},200,{'cache-control':'public, max-age=60'});
  if(path==='schools'&&request.method==='GET'){await ensure(env);return J({schools:(await env.DB.prepare('SELECT id,name,short,state,kind FROM schools WHERE active=1 ORDER BY name').all()).results,states:STATES},200,{'cache-control':'public, max-age=3600'})}
  if(path==='me/delivery'&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Sign in first.'},401);await ensure(env);
    const d=dlvIn(await request.json().catch(()=>({})));if(d.error)return J(d,400);
    await env.DB.prepare('UPDATE users SET deliv_on=?,deliv_fee=?,deliv_note=? WHERE id=?').bind(d.on,d.fee,d.note,u.id).run();await bumpVer(env);return J({ok:true,deliv:dlv({deliv_on:d.on,deliv_fee:d.fee,deliv_note:d.note})})}
  if(path==='me/school'&&request.method==='POST'){const u=await me(env,request);if(!u)return J({error:'Sign in first.'},401);await ensure(env);const b=await request.json().catch(()=>({})),sc=await pickSchool(env,b);if(sc.error)return J(sc,400);
    await env.DB.prepare('UPDATE users SET school_id=?,state=? WHERE id=?').bind(sc.id,sc.state,u.id).run();return J({ok:true,school:sc})}
  if(path==='me'){const u=await me(env,request);if(!u)return J({error:'Not signed in'},401);await ensure(env);
    const v=await env.DB.prepare('SELECT status,reason FROM verify_requests WHERE uid=?').bind(u.id).first();return J({user:{...pub(u),schoolInfo:await schoolOf(env,u.school_id),verify:v?v.status:null,verifyReason:v&&v.reason}})}
  if(path==='listings'&&request.method==='GET'){const u=await me(env,request);if(!u)return J({error:'Not signed in'},401);await sweep(env);await ensure(env);const NOW=Math.floor(Date.now()/6e4)*6e4;waitUntil(dailyCleanup(env));
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
      if(sp.get('dl')==='1')w.push('u.deliv_on=1');if(sp.get('vf')==='1')w.push('u.verified=1');if(sp.get('r4')==='1')w.push('u.rating_n>0 AND u.rating_sum>=4*u.rating_n')}
    const wh=' FROM listings l JOIN users u ON u.id=l.uid LEFT JOIN schools sc ON sc.id=l.school_id WHERE '+w.join(' AND '),srt={lo:'l.price ASC,l.id DESC',hi:'l.price DESC,l.id DESC',top:'(u.rating_sum+6.0)/(u.rating_n+2) DESC,u.rating_n DESC,l.created DESC'}[sp.get('sort')]||`(IFNULL(l.featured_until,0)>${NOW}) DESC,l.created DESC,l.id DESC`;
    const feed=!ids.length&&!sp.get('mine'),run=async()=>{const total=feed?(await env.DB.prepare('SELECT COUNT(*) c'+wh).bind(...v).first()).c:undefined;
      const rs=(await env.DB.prepare('SELECT l.*,u.verified AS sv,u.deliv_on,u.deliv_fee,u.deliv_note,u.rating_sum,u.rating_n,sc.short AS ssh,sc.name AS snm'+wh+' ORDER BY '+srt+' LIMIT ? OFFSET ?').bind(...v,lim,off).all()).results;
      // Searches also look in open stores, so "jollof" finds food stalls as well as listings.
      const sq=(sp.get('q')||'').trim().slice(0,60),words=sq.split(/\s+/).filter(Boolean).slice(0,5),sc2=sp.get('scope')||'school';let storeHits=[];
      if(feed&&words.length&&!off){const ww=["i.review='live'",'i.avail=1','s.isopen=1',LIVE],vv=[];for(const word of words){ww.push('(i.title LIKE ? OR i.descr LIKE ?)');vv.push('%'+word+'%','%'+word+'%')}
        if(sc2==='school'&&u.school_id){ww.push('s.school_id=?');vv.push(u.school_id)}else if(sc2==='state'&&u.state){ww.push('s.state=?');vv.push(u.state)}
        storeHits=(await env.DB.prepare('SELECT i.id,i.title,i.price,s.id sid,s.name sname,s.cat,s.emoji FROM store_items i JOIN stores s ON s.id=i.sid JOIN users u ON u.id=s.uid WHERE '+ww.join(' AND ')+' ORDER BY i.created DESC LIMIT 8').bind(...vv).all()).results
          .map(r=>({id:'I'+r.id,title:r.title,price:r.price,store:'S'+r.sid,storeName:r.sname,cat:r.cat,emoji:r.emoji}))}
      return{total,storeHits,listings:rs.map(r=>({sid:r.uid,id:'L'+r.id,deliv:dlv(r),rating:rat(r),title:r.title,price:r.price,cat:r.cat,cond:r.cond,spot:r.spot,desc:r.descr,seller:r.seller,phone:r.phone,imgs:Array.from({length:r.n},(_,i)=>'/api/photo/'+r.id+'/'+i),t:r.created,sold:r.sold,featured:(r.featured_until||0)>NOW,featuredUntil:r.featured_until||0,verified:!!r.sv,qty:r.qty||1,qtyLeft:r.qty_left==null?(r.sold?0:1):r.qty_left,school:r.ssh||r.snm||'',state:r.state||'',review:r.review,reviewNote:feed?null:r.review_note}))}};
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
    if(t('title').length<3||t('title').length>80)return J({error:'Enter a title of 3 to 80 characters.'},400);
    if(!(price>=1&&price<=10000000))return J({error:'Enter a valid price.'},400);
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
    const ss=(await env.DB.prepare('SELECT s.*,u.role,u.phone AS up,u.matric,u.verified AS ov,u.rating_sum,u.rating_n,sc.short AS ssh,sc.name AS snm FROM stores s JOIN users u ON u.id=s.uid LEFT JOIN schools sc ON sc.id=s.school_id WHERE '+w.join(' AND ')+' ORDER BY (IFNULL(s.featured_until,0)>'+NOW+') DESC,(s.school_id=?) DESC,s.created DESC LIMIT 300').bind(...v,u.school_id||0).all()).results;
    const sids=ss.map(x=>x.id),its=sids.length?(await env.DB.prepare('SELECT * FROM store_items WHERE sid IN ('+sids.map(()=>'?').join(',')+")"+(mine?'':" AND review='live'")+" ORDER BY created DESC").bind(...sids).all()).results:[];
    return{stores:ss.map(s=>({id:'S'+s.id,deliv:dlv(s),rating:rat(s),uid:s.uid,owner:s.role==='vendor'?'V-'+s.up:s.matric,name:s.name,emoji:s.emoji,cat:s.cat,desc:s.descr,spot:s.spot,phone:s.phone,open:!!s.isopen,vendor:!!s.vendor,featured:(s.featured_until||0)>NOW,featuredUntil:s.featured_until||0,verified:!!s.ov,school:s.ssh||s.snm||'',state:s.state||'',reach:(s.reach_until||0)>NOW?s.reach:'school',reachUntil:(s.reach_until||0)>NOW?s.reach_until:0,items:its.filter(i=>i.sid===s.id).map(i=>({id:'I'+i.id,title:i.title,price:i.price,desc:i.descr,avail:!!i.avail&&i.qty_left!==0,qtyLeft:i.qty_left,review:i.review,reviewNote:mine?i.review_note:null,imgs:Array.from({length:i.n},(_,k)=>'/api/photo/-'+i.id+'/'+k)}))}))}};
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
    if(path==='stores/delivery'){const d=dlvIn(b);if(d.error)return J(d,400);await env.DB.prepare('UPDATE stores SET deliv_on=?,deliv_fee=?,deliv_note=? WHERE id=?').bind(d.on,d.fee,d.note,mine.id).run();return ok()}
    if(path==='stores/toggle'){await env.DB.prepare('UPDATE stores SET isopen=1-isopen WHERE id=?').bind(mine.id).run();return ok()}
    if(path==='stores/item'){const t=k=>String(b[k]||'').trim(),price=Math.round(+b.price),imgs=Array.isArray(b.imgs)?b.imgs:[];
      if(t('title').length<3||t('title').length>80)return J({error:'Enter a title of 3 to 80 characters.'},400);
      if(!(price>=1&&price<=10000000))return J({error:'Enter a valid price.'},400);
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
      else{const I=await env.DB.prepare('SELECT i.*,s.id sid,s.name sname,s.phone sphone,s.isopen,s.acct_no,s.acct,s.acct_name,s.bank,s.bank_code bcode,s.bank_verified bok,s.deliv_on,s.deliv_fee,s.deliv_note,s.spot sspot FROM store_items i JOIN stores s ON s.id=i.sid JOIN users u ON u.id=s.uid WHERE i.id=? AND '+LIVE).bind(rid).first();
        if(!I||!I.avail||!I.isopen||I.review!=='live')return fail('An item in your bag is no longer available.');
        const acctNo=I.acct_no||I.acct;if(!acctNo||!I.acct_name)return fail('The store for "'+I.title+'" has not set up payment details yet.');
        if(I.qty_left!=null){const tk=await env.DB.prepare('UPDATE store_items SET qty_left=qty_left-? WHERE id=? AND qty_left>=?').bind(q,rid,q).run();
          if(!tk.meta.changes)return fail(I.qty_left>0?'Only '+I.qty_left+' of "'+I.title+'" left. Reduce the quantity in your bag.':'"'+I.title+'" just sold out.');taken.push(['item',rid,q])}
        const gk='S'+I.sid;(groups[gk]=groups[gk]||{seller:0,sname:I.sname,sphone:I.sphone,bank:I.bank,acct:acctNo,acctName:I.acct_name,bcode:I.bcode,bok:I.bok,dl:dlv(I),pickup:I.sspot||'',items:[]}).items.push({kind:'item',ref_id:I.id,title:I.title,price:I.price,q})}}
    for(const gk in groups)if(groups[gk].seller===0){const s=await env.DB.prepare('SELECT uid FROM stores WHERE id=?').bind(+gk.slice(1)).first();groups[gk].seller=s.uid;if(s.uid===u.id)return fail("You can't buy from your own store.")}
    // Every order is paid through Paystack, so the seller needs a payout account Paystack can pay into: a known bank, 10 digits, and a name that was checked.
    const now=Date.now(),made=[],okCard=g=>!!(BANKS[g.bcode]&&/^\d{10}$/.test(g.acct||'')&&g.bok);
    if(!env.PAYSTACK_SECRET)return fail('Payments are not set up yet. Please try again later.');
    for(const gk in groups){const g=groups[gk];if(!okCard(g)){waitUntil(tg(env,'A buyer could not pay '+g.sname+' ('+(g.sphone||'')+'): their payout account is not confirmed yet. Check Payouts in Admin.'));
      return fail('"'+g.items[0].title+'" can\'t be bought yet. The seller\'s bank account is still being checked. Remove it from your bag or try again later.')}}
    for(const gk in groups){const g=groups[gk],amount=g.items.reduce((s,i)=>s+i.price*i.q,0);
      const title=g.items.length===1?(g.items[0].q>1?g.items[0].q+' × ':'')+g.items[0].title:g.items.length+' items';
      const r=await env.DB.prepare('INSERT INTO orders(buyer,seller,buyer_name,buyer_phone,seller_name,seller_phone,title,amount,bank_name,acct_no,acct_name,status,deadline,created,updated,bank_code,bank_ok,fee,sub,d_on,d_fee,d_note,pickup) VALUES(?,?,?,?,?,?,?,?,?,?,?,\'pending\',?,?,?,?,?,?,?,?,?,?,?)')
        .bind(u.id,g.seller,u.name,u.phone,g.sname,g.sphone||'',title,amount,g.bank,g.acct,g.acctName,now+PAY_WINDOW,now,now,BANKS[g.bcode]?g.bcode:null,okCard(g)?1:0,feeOf(amount),amount,g.dl.on?1:0,g.dl.fee,g.dl.note||null,clean(g.pickup,60)||null).run();
      const oid=r.meta.last_row_id;
      await env.DB.batch(g.items.map(i=>env.DB.prepare('INSERT INTO order_items(oid,kind,ref_id,title,price,q) VALUES(?,?,?,?,?,?)').bind(oid,i.kind,i.ref_id,i.title,i.price,i.q)));
      made.push({id:oid,title,amount,bank:g.bank,acct:g.acct,acctName:g.acctName,sellerName:g.sname,sellerPhone:g.sphone||'',status:'pending',deadline:now+PAY_WINDOW,card:okCard(g)&&!!env.PAYSTACK_SECRET,fee:feeOf(amount),sub:amount,deliv:g.dl,pickup:clean(g.pickup,60),method:null,stage:null,track:[]})}
    await bump();return J({orders:made})}
  if(path==='orders/mine'&&request.method==='GET'){const u=await me(env,request);if(!u)return J({error:'Not signed in'},401);await sweep(env);
    const rs=(await env.DB.prepare('SELECT * FROM orders WHERE buyer=? ORDER BY created DESC LIMIT 100').bind(u.id).all()).results;
    return J({orders:rs.map(oRow)})}
  if(path==='orders/selling'&&request.method==='GET'){const u=await me(env,request);if(!u)return J({error:'Not signed in'},401);await sweep(env);
    const rs=(await env.DB.prepare('SELECT * FROM orders WHERE seller=? ORDER BY created DESC LIMIT 100').bind(u.id).all()).results;
    return J({orders:rs.map(oRow)})}
  if(path==='orders/news'&&request.method==='GET'){const u=await me(env,request);if(!u)return J({error:'Not signed in'},401);
    const sb=+url.searchParams.get('sb')||Date.now(),ss=+url.searchParams.get('ss')||Date.now();
    const rs=(await env.DB.prepare("SELECT id,title,amount,status,note,buyer,buyer_name,seller_name,updated,method,dstage,pickup FROM orders WHERE (buyer=? AND updated>? AND status IN ('verified','rejected','expired','refunded','released')) OR (seller=? AND updated>? AND (status IN ('released','disputed','refunded') OR (status='verified' AND IFNULL(dstage,'paid')='paid'))) ORDER BY updated DESC LIMIT 20").bind(u.id,sb,u.id,ss).all()).results;
    return J({news:rs.map(r=>({id:r.id,title:r.title,amount:r.amount,status:r.status,note:r.note,side:r.buyer===u.id?'buy':'sell',buyerName:r.buyer_name,sellerName:r.seller_name,updated:r.updated,method:r.method,stage:r.dstage,pickup:r.pickup}))},200,{'cache-control':'no-store'})}
  // Receipts are no longer used: every order is paid through Paystack.
  if(path==='orders/receipt')return J({error:'Pay for this order through Paystack from your Orders page.'},410);
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
    const now=Date.now();await env.DB.prepare('UPDATE orders SET dstage=?,track=?,updated=? WHERE id=?').bind(nx,track(o,nx,now),now,o.id).run();return J({ok:true,stage:nx})}
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
    if(path==='admin/summary'){await sweep(env);waitUntil(dailyCleanup(env));const c=s=>env.DB.prepare('SELECT COUNT(*) c FROM '+s),mid=new Date();mid.setUTCHours(-1,0,0,0);
      const r=(await env.DB.batch([c("orders WHERE status IN ('under_review','disputed')"),c("orders WHERE status='verified'"),c("users WHERE role='vendor' AND status='pending'"),c('users WHERE bank_verified=0'),c('stores WHERE bank_verified=0'),c("users WHERE role='student'"),c("users WHERE role='vendor'"),c('stores'),c("orders WHERE status='released'"),c('orders WHERE created>=?').bind(+mid)])).map(x=>x.results[0].c);
      if(!a.is_admin)return J({review:r[0]});
      const ai=JSON.parse(await getK(env,'ai_last')||'null'),mo=new Date();mo.setUTCDate(1);mo.setUTCHours(-1,0,0,0);
      const m=(await env.DB.batch([env.DB.prepare("SELECT COUNT(*) c FROM verify_requests WHERE status='pending'"),env.DB.prepare('SELECT IFNULL(SUM(amount),0) c FROM payments'),env.DB.prepare('SELECT IFNULL(SUM(amount),0) c FROM payments WHERE created>=?').bind(+mo),env.DB.prepare('SELECT (SELECT COUNT(*) FROM listings WHERE featured_until>?)+(SELECT COUNT(*) FROM stores WHERE featured_until>?) c').bind(Date.now(),Date.now()),env.DB.prepare('SELECT COUNT(*) c FROM users WHERE verified=1')])).map(x=>x.results[0].c);
      const q2=(await env.DB.batch([env.DB.prepare("SELECT (SELECT COUNT(*) FROM listings WHERE review IN ('review','checking'))+(SELECT COUNT(*) FROM store_items WHERE review IN ('review','checking')) c"),env.DB.prepare('SELECT COUNT(*) c FROM schools WHERE active=0')])).map(x=>x.results[0].c);
      return J({itemsReview:q2[0],schoolsPending:q2[1],verifyPending:m[0],earned:m[1],earnedMonth:m[2],boosts:m[3],verifiedCount:m[4],review:r[0],delivery:r[1],vendorsPending:r[2],banks:r[3]+r[4],students:r[5],vendors:r[6],stores:r[7],released:r[8],today:r[9],aiOn:!!env.AI,r2On:!!env.PHOTOS,webhook:!!(await getK(env,'webhook_seen')),aiLast:ai,psMode:!env.PAYSTACK_SECRET?'none':/^sk_live_/.test(env.PAYSTACK_SECRET)?'live':'test',bankLast:JSON.parse(await getK(env,'bank_last')||'null'),payoutLast:JSON.parse(await getK(env,'payout_last')||'null'),payoutsFailed:(await env.DB.prepare("SELECT COUNT(*) c FROM payouts WHERE status='failed'").first()).c,held:(await env.DB.prepare("SELECT IFNULL(SUM(amount-IFNULL(fee,0)),0) c FROM orders WHERE status IN ('verified','disputed') AND paid_via='paystack'").first()).c,cleanupAt:+(await getK(env,'cleanup_at'))||0},200,{'cache-control':'no-store'})}
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
    if(path==='admin/sellerpay'&&request.method==='GET'){const f=url.searchParams.get('f')||'failed',w=[],v=[];if(['failed','processing','paid','queued'].includes(f)){w.push('p.status=?');v.push(f)}
      if(/^#?\d+$/.test(q)){w.push('p.oid=?');v.push(+q.replace('#',''))}else if(q){w.push('(o.seller_name LIKE ? OR o.title LIKE ?)');v.push(like,like)}
      return list('payouts p JOIN orders o ON o.id=p.oid','p.*,o.title,o.seller_name,o.seller_phone,o.bank_name,o.acct_no,o.acct_name',w,v,'p.updated DESC',
        r=>({oid:r.oid,amount:r.amount,status:r.status,err:r.err,tries:r.tries,how:r.how,ref:r.ref,updated:r.updated,title:r.title,sellerName:r.seller_name,sellerPhone:r.seller_phone,bank:r.bank_name,acct:r.acct_no,acctName:r.acct_name}))}
    if(path==='admin/sellerpay/retry'&&request.method==='POST'){if(!a.is_admin)return J({error:'Only admins can do this.'},403);const p=await env.DB.prepare('SELECT * FROM payouts WHERE oid=?').bind(+b.id).first();if(!p||p.status!=='failed')return J({error:'Only failed payouts can be retried.'},400);
      if(b.manual){await env.DB.batch([env.DB.prepare("UPDATE payouts SET status='paid',how='manual',err=NULL,updated=? WHERE oid=?").bind(Date.now(),p.oid),env.DB.prepare("UPDATE orders SET payout='paid' WHERE id=?").bind(p.oid)]);await logA(env,a,'money','marked a seller payout as paid by hand','Order #'+p.oid+' · ₦'+p.amount,{oid:p.oid});return J({ok:true,status:'paid'})}
      await env.DB.prepare("UPDATE payouts SET status='queued' WHERE oid=?").bind(p.oid).run();const r=await payOut(env,p.oid);await logA(env,a,'money','retried a seller payout','Order #'+p.oid+' · ₦'+p.amount,{oid:p.oid,detail:r&&r.status});return J({ok:true,status:r&&r.status,err:r&&r.err})}
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
    if(path==='admin/settings'&&request.method==='POST'){for(const k of ['biz_name','support_phone','support_email'])if(k in b)await setK(env,k,String(b[k]||'').trim().slice(0,120));await logA(env,a,'other','updated settings','Business and support details');return J({ok:true})}
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
        const total=base+(method==='delivery'?o.d_fee||0:0),fee=feeOf(base);
        w={amount:total,label:o.title};data={oid:o.id,method,addr:method==='delivery'?addr:null,dphone:method==='delivery'?dphone:null,fee}}
      else if(kind==='store'){const d=b.d||{},bad=storeBad(d);if(bad)return J({error:bad},400);if(await env.DB.prepare('SELECT 1 FROM stores WHERE uid=?').bind(u.id).first())return J({error:'You already have a store.'},409);
        if(u.role==='vendor'&&u.status!=='active')return J({error:'Your shop is not approved yet.'},403);w={amount:STORE_FEE,label:'Store: '+clean(d.name,40)};data={d}}
      else{w=await what(kind,target,days);if(w.error)return J(w,400);data.level=w.level||null}
      const r=await ps(env,'/transaction/initialize',{method:'POST',body:JSON.stringify({email:u.email||('user'+u.phone+'@stall.app'),amount:w.amount*100,currency:'NGN',callback_url:url.origin+'/',metadata:{kind,target,days,uid:u.id,level:w.level||null}})});
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
      const p=await env.DB.prepare('SELECT * FROM payouts WHERE ref=?').bind(ref).first();if(!p||p.status==='paid')return;const err=ok?null:'Paystack: transfer '+ev.event.split('.')[1]+(ev.data.reason?' ('+String(ev.data.reason).slice(0,120)+')':'');
      await env.DB.batch([env.DB.prepare('UPDATE payouts SET status=?,err=?,updated=? WHERE oid=?').bind(ok?'paid':'failed',err,Date.now(),p.oid),env.DB.prepare('UPDATE orders SET payout=? WHERE id=?').bind(ok?'paid':'failed',p.oid)]);
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
