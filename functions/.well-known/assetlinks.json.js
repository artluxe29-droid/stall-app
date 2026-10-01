// Digital Asset Links for the Android app (Google Play). Android checks this file to confirm the app and this
// website belong together, so the app opens without a browser bar. The package name and signing-key fingerprints
// are set in Admin → Settings → Android app (copy the SHA-256 fingerprint from Play Console → App integrity).
export async function onRequest({env}){
  let pkg='',sha='';
  try{const g=k=>env.DB.prepare('SELECT v FROM settings WHERE k=?').bind(k).first();pkg=((await g('android_pkg'))||{}).v||'';sha=((await g('android_sha'))||{}).v||''}catch(e){}
  const body=pkg&&sha?[{relation:['delegate_permission/common.handle_all_urls'],target:{namespace:'android_app',package_name:pkg,sha256_cert_fingerprints:sha.split(',').filter(Boolean)}}]:[];
  return new Response(JSON.stringify(body),{headers:{'content-type':'application/json','cache-control':'public, max-age=300','access-control-allow-origin':'*'}});
}
