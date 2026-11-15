const CACHE='pats-auto-shell-2026-11-16.3';
const FILES=['parent-guide.html','portable-practice.html','portable-practice-cloud.js','portable-practice-app.html','portable-practice-updates.js','portable-practice.webmanifest','icons/my-base-snake-192.png','icons/my-base-snake-512.png','icons/my-base-snake-maskable-512.png'];
const LOCAL_ROOT=new URL('./',self.location.href);
const APP_ROOT=new URL(self.location.hostname==='whizkidal.github.io'?'/PAT-WhizKids/':'./',self.location.href);
function assetURL(name){return new URL(name,name==='portable-practice.html'||name==='portable-practice.webmanifest'?LOCAL_ROOT:APP_ROOT).href}
self.addEventListener('install',event=>event.waitUntil((async()=>{const cache=await caches.open(CACHE);await Promise.all(FILES.map(async name=>{const url=assetURL(name),response=await fetch(url,{cache:'no-store'});if(!response.ok)throw Error('Incomplete app release');await cache.put(url,response)}));await self.skipWaiting()})()));
self.addEventListener('activate',event=>event.waitUntil(self.clients.claim()));
self.addEventListener('fetch',event=>{
 const url=new URL(event.request.url);if(event.request.method!=='GET'||url.origin!==self.location.origin)return;
 const name=FILES.find(name=>url.pathname===new URL(name,LOCAL_ROOT).pathname||url.pathname===new URL(name,APP_ROOT).pathname);if(!name)return;
 const canonical=assetURL(name);
 event.respondWith((async()=>{try{const response=await fetch(canonical+url.search,{cache:'no-store',signal:AbortSignal.timeout(6000)});if(!response.ok)throw Error('App file unavailable');const cache=await caches.open(CACHE);await cache.put(canonical,response.clone());return response}catch(error){const cached=await caches.match(canonical);if(cached)return cached;throw error}})());
});
