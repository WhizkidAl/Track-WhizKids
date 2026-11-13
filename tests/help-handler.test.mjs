import assert from 'node:assert/strict';
import {handle} from '../supabase/functions/pat-help/help-handler.mjs';
const id='11111111-1111-4111-8111-111111111111',body={participantId:id,requestId:id,kind:'show',activity:'Speech practice',recipient:'wrong@example.invalid'};
let sent=[],mode='ok',secret=true;
const env=n=>({SUPABASE_URL:'https://project.example',SUPABASE_PUBLISHABLE_KEYS:'{"default":"public"}',SUPABASE_SECRET_KEYS:'{"default":"secret"}',RESEND_API_KEY:secret?'mail-key':undefined})[n];
const fetch=async(url,opt={})=>{sent.push({url,opt});if(url.endsWith('/user'))return Response.json({id});if(url.endsWith('/pat_prepare_help'))return mode==='denied'?Response.json({},{status:403}):Response.json(mode==='limited'?{rate_limited:true}:{id,recipient:'parent@example.invalid',participant_label:'Test child',kind:'show',activity:'Speech practice',status:mode==='duplicate'?'sent':'queued'});if(url.includes('resend.com'))return mode==='failed'?Response.json({},{status:500}):Response.json({id:'mail-id'});return Response.json(null)};
async function run(data=body,headers={Authorization:'Bearer test',Origin:'https://whizkidal.github.io'}){sent=[];return handle(new Request('https://function.example',{method:'POST',headers,body:JSON.stringify(data)}),{env,fetch})}
assert.equal((await run(body,{})).status,401);assert.equal((await run({...body,kind:'unknown'})).status,400);assert.equal((await run(null)).status,400);
secret=false;assert.equal((await run()).status,503);assert(!sent.some(x=>x.url.includes('resend')));secret=true;
mode='denied';assert.equal((await run()).status,403);mode='limited';assert.equal((await run()).status,429);
mode='duplicate';assert.equal((await run()).status,200);assert(!sent.some(x=>x.url.includes('resend')));
mode='ok';assert.equal((await run()).status,200);let email=sent.find(x=>x.url.includes('resend'));assert.deepEqual(JSON.parse(email.opt.body).to,['parent@example.invalid']);assert(JSON.parse(email.opt.body).text.includes('Please show me.'));assert.equal(email.opt.headers['Idempotency-Key'],'mybase-help/'+id);
mode='failed';assert.equal((await run()).status,502);assert.equal(JSON.parse(sent.at(-1).opt.body).p_sent,false);
assert.equal((await run(body,{Authorization:'Bearer test',Origin:'https://untrusted.example'})).status,403);
console.log('PASS authenticated help email, recipient protection, rate limit, retry and honest failure handling');
