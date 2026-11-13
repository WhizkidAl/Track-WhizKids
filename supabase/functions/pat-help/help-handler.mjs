const choices={help:'I need help.',show:'Please show me.',time:'I need more time.',another:'Can we try another way?',break:'I need a break.'};
const origin='https://whizkidal.github.io';
const uuid=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
export async function handle(req,deps={}){
 const env=deps.env||((name)=>Deno.env.get(name)),send=deps.fetch||fetch;
 const headers={'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Content-Type':'application/json','Vary':'Origin'};
 const reply=(status,data)=>new Response(JSON.stringify(data),{status,headers});
 if(req.headers.get('Origin')&&req.headers.get('Origin')!==origin)return reply(403,{sent:false,message:'Origin not allowed.'});
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(req.method!=='POST')return reply(405,{sent:false,message:'Use POST.'});
 const auth=req.headers.get('Authorization')||'';
 if(!/^Bearer \S+$/.test(auth))return reply(401,{sent:false,message:'Sign in to My Base first.'});
 let body;try{const raw=await req.text();if(raw.length>1500)throw Error();body=JSON.parse(raw)}catch{return reply(400,{sent:false,message:'Invalid request.'})}
 if(!body||typeof body!=='object'||!uuid.test(body.participantId||'')||!uuid.test(body.requestId||'')||!Object.hasOwn(choices,body.kind)||typeof body.activity!=='string'||body.activity.length>180)return reply(400,{sent:false,message:'Invalid help request.'});
 const url=env('SUPABASE_URL');let publishable,admin;
 try{publishable=Object.values(JSON.parse(env('SUPABASE_PUBLISHABLE_KEYS')||'{}'))[0]||env('SUPABASE_ANON_KEY');admin=Object.values(JSON.parse(env('SUPABASE_SECRET_KEYS')||'{}'))[0]||env('SUPABASE_SERVICE_ROLE_KEY')}catch{return reply(503,{sent:false,message:'Help email is not connected yet. Ask your adult in person.'})}
 if(!url||!publishable||!admin)return reply(503,{sent:false,message:'Help email is not connected yet. Ask your adult in person.'});
 let user;try{const r=await send(url+'/auth/v1/user',{headers:{Authorization:auth,apikey:publishable}});if(!r.ok)return reply(401,{sent:false,message:'Please sign in again.'});user=await r.json();if(!uuid.test(user.id||''))return reply(401,{sent:false,message:'Please sign in again.'})}catch{return reply(503,{sent:false,message:'No connection. Email was not sent. Ask your adult in person.'})}
 const key=env('RESEND_API_KEY')||env('PAT Base key');if(!key)return reply(503,{sent:false,message:'Help email is not connected yet. Ask your adult in person.'});
 const rpc=async(name,args)=>{const r=await send(url+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:admin,'Content-Type':'application/json'},body:JSON.stringify(args)});const data=await r.json().catch(()=>null);return {ok:r.ok,data}};
 try{
  const prepared=await rpc('pat_prepare_help',{p_user_id:user.id,p_participant_id:body.participantId,p_request_id:body.requestId,p_kind:body.kind,p_activity:body.activity});
  if(!prepared.ok)return reply(403,{sent:false,message:'This account cannot email a parent for that workspace.'});
  const event=prepared.data;
  if(event.rate_limited)return reply(429,{sent:false,message:'A message was requested recently. Please wait a minute or ask your adult in person.'});
  if(event.status==='sent')return reply(200,{sent:true,requestId:event.id,alreadySent:true});
  const text=[event.participant_label+' has asked for help in My Base.','',choices[event.kind],event.activity?'Activity: '+event.activity:'Activity: My Base','','Open My Base: '+origin+'/Track-WhizKids/portable-practice.html'].join('\n');
  const email=await send('https://api.resend.com/emails',{method:'POST',headers:{Authorization:'Bearer '+key,'Content-Type':'application/json','Idempotency-Key':'mybase-help/'+event.id},body:JSON.stringify({from:'Whiz Kids My Base <no-reply@auth.whizkidstherapy.com>',to:[event.recipient],subject:'My Base help request',text})});
  const result=await email.json().catch(()=>({}));
  if(!email.ok||typeof result.id!=='string'){await rpc('pat_finish_help',{p_request_id:event.id,p_sent:false,p_error_code:'email_service_'+email.status});return reply(502,{sent:false,message:'Email could not be sent. Please ask your adult in person.'})}
  await rpc('pat_finish_help',{p_request_id:event.id,p_sent:true,p_provider_id:result.id});
  return reply(200,{sent:true,requestId:event.id});
 }catch{return reply(503,{sent:false,message:'Email could not be confirmed. Retry this message or ask your adult in person.'})}
}

