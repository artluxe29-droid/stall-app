// Fills in the business name and support contacts set in Admin > Settings.
fetch('/api/config').then(r=>r.json()).then(c=>{const name=c.name||'Stall',w=String(c.phone||'').replace(/\D/g,'').replace(/^0/,'234');
  const contact=[w?'<a href="https://wa.me/'+w+'">WhatsApp '+c.phone+'</a>':'',c.email?'<a href="mailto:'+c.email+'">'+c.email+'</a>':''].filter(Boolean).join(' or ')||'the Help links in the app';
  document.querySelectorAll('[data-name]').forEach(e=>e.textContent=name);document.querySelectorAll('[data-contact]').forEach(e=>e.innerHTML=contact)}).catch(()=>{});
