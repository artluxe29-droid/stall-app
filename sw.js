const C='stall-v21',SHELL=['/app','/manifest.webmanifest','/icons/icon-192-v3.png'];
self.addEventListener('install',e=>{e.waitUntil(caches.open(C).then(c=>c.addAll(SHELL)));self.skipWaiting()});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!==C).map(x=>caches.delete(x)))).then(()=>clients.claim()))});
self.addEventListener('fetch',e=>{const r=e.request,u=new URL(r.url);
  if(r.method!=='GET'||u.origin!==location.origin||u.pathname.startsWith('/api/'))return;
  // Fresh from the network when it answers within 3 seconds; on a slow connection the saved copy shows instead (and is updated in the background).
  e.respondWith((async()=>{const net=fetch(r).then(x=>{if(x.ok){const y=x.clone();caches.open(C).then(c=>c.put(r,y))}return x}),saved=await caches.match(r);
    if(!saved)return net.catch(()=>caches.match('/app'));
    return Promise.race([net.catch(()=>saved),new Promise(z=>setTimeout(()=>z(saved),3000))])})())});
// Push notifications: the push carries no data, so ask Stall what to show. A notification must always be shown.
const show=(t,o)=>self.registration.showNotification(t,{icon:'/icons/icon-192-v3.png',badge:'/icons/badge-96-v3.png',...o});
self.addEventListener('push',e=>{e.waitUntil(fetch('/api/push/inbox',{credentials:'include'}).then(r=>r.ok?r.json():{notes:[]}).then(j=>{const n=j.notes||[];
  if(!n.length)return show('Stall',{body:'You have a new update.',tag:'stall',data:{url:'/app'}});
  return Promise.all(n.reverse().map(x=>show(x.title,{body:x.body||'',tag:x.tag||'n'+x.id,renotify:!!x.tag,data:{url:x.url||'/app'}})))}).catch(()=>show('Stall',{body:'You have a new update.',tag:'stall',data:{url:'/app'}})))});
self.addEventListener('notificationclick',e=>{e.notification.close();const url=new URL((e.notification.data&&e.notification.data.url)||'/app',location.origin).href;
  e.waitUntil(clients.matchAll({type:'window',includeUncontrolled:true}).then(cs=>{for(const c of cs){if(c.url.startsWith(location.origin)&&'focus'in c){return c.navigate(url).then(w=>(w||c).focus()).catch(()=>c.focus())}}return clients.openWindow(url)}))});
