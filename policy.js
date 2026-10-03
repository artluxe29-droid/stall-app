// Fills in the business name and support contacts set in Admin > Settings.
fetch('/api/config').then(r=>r.json()).then(c=>{const name=c.name||'Stall',w=String(c.phone||'').replace(/\D/g,'').replace(/^0/,'234');
  const contact=[w?'<a href="https://wa.me/'+w+'">WhatsApp '+c.phone+'</a>':'',c.email?'<a href="mailto:'+c.email+'">'+c.email+'</a>':''].filter(Boolean).join(' or ')||'the Help links in the app';
  document.querySelectorAll('[data-name]').forEach(e=>e.textContent=name);
  // Order timers from Admin > Settings (handover in minutes, the rest in hours).
  const t=c.timers||{},d=(n,m)=>m?(n>=60&&n%60===0?(n===60?'1 hour':n/60+' hours'):n+' minutes'):(n===1?'1 hour':n+' hours');document.querySelectorAll('[data-t]').forEach(e=>{const k=e.dataset.t;if(t[k])e.textContent=d(t[k],k==='hand')});document.querySelectorAll('[data-contact]').forEach(e=>e.innerHTML=contact);
  const f=c.fee;if(f){const x=(f.min?'at least ₦'+f.min.toLocaleString('en-NG')+' and ':'')+'never more than ₦'+f.cap.toLocaleString('en-NG');document.querySelectorAll('[data-fee]').forEach(e=>e.textContent=f.rate+'% of the item price ('+x)}}).catch(()=>{});
