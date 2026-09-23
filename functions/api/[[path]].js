// Cloudflare Pages Function. Set PAYSTACK_SECRET (sk_test_... then sk_live_...) as an environment secret.
const J=(d,s=200)=>new Response(JSON.stringify(d),{status:s,headers:{'content-type':'application/json'}});
const ps=(env,p,o={})=>fetch('https://api.paystack.co'+p,{...o,headers:{Authorization:'Bearer '+env.PAYSTACK_SECRET,'content-type':'application/json'}}).then(r=>r.json());
export async function onRequest({request,env,params}){
  const path=[].concat(params.path||[]).join('/'),url=new URL(request.url);
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
