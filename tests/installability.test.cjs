const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..');
const manifest=JSON.parse(fs.readFileSync(path.join(root,'portable-practice.webmanifest'),'utf8').replace(/^\uFEFF/,''));
assert.equal(manifest.display,'standalone');
assert(manifest.name&&manifest.short_name);
const page=new URL('https://whizkidal.github.io/Track-WhizKids/portable-practice.webmanifest');
const start=new URL(manifest.start_url,page),scope=new URL(manifest.scope,page);
assert(start.href.startsWith(scope.href));
assert.equal(new URL(manifest.id,page).href,start.href);
for(const size of [192,512])assert(manifest.icons.some(i=>i.sizes===`${size}x${size}`&&i.purpose==='any'));
assert(manifest.icons.some(i=>i.purpose==='maskable'));
for(const icon of manifest.icons){
 const data=fs.readFileSync(path.join(root,icon.src));
 assert.equal(data.subarray(1,4).toString(),'PNG');
 const dimensions=`${data.readUInt32BE(16)}x${data.readUInt32BE(20)}`;
 assert.equal(dimensions,icon.sizes);
 assert.equal(new URL(icon.src,page).origin,page.origin);
}
const worker=fs.readFileSync(path.join(root,'portable-practice-sw.js'),'utf8');
for(const icon of manifest.icons)assert(worker.includes(icon.src));
console.log('PASS install manifest, icon dimensions, app scope and cached icon paths');

