import {makeHandler} from './handler.mjs';
const supabaseUrl=Deno.env.get('SUPABASE_URL')!;
const serviceKey=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const service=async(op:string,actor:string|null,data:unknown)=>{
 const r=await fetch(supabaseUrl+'/rest/v1/rpc/workspace_mail_service',{method:'POST',headers:{apikey:serviceKey,Authorization:'Bearer '+serviceKey,'Content-Type':'application/json'},body:JSON.stringify({p_op:op,p_actor:actor,p_data:data})});
 if(!r.ok){const e=await r.json();throw new Error(e.message||'Mail operation unavailable');}return r.json();
};
const authenticate=async(authorization:string)=>{
 if(!authorization.startsWith('Bearer '))return null;
 const r=await fetch(supabaseUrl+'/auth/v1/user',{headers:{apikey:serviceKey,Authorization:authorization}});
 if(!r.ok)return null;const u=await r.json();return u.id||null;
};
Deno.serve(async(req:Request)=>{
 const r=await fetch(supabaseUrl+'/rest/v1/rpc/workspace_mail_configuration',{method:'POST',headers:{apikey:serviceKey,Authorization:'Bearer '+serviceKey,'Content-Type':'application/json'},body:'{}'});
 if(!r.ok)return new Response(JSON.stringify({error:'Mailbox configuration unavailable'}),{status:503,headers:{'Content-Type':'application/json','Access-Control-Allow-Origin':'https://whizkidal.github.io'}});
 const config=await r.json();
 return makeHandler({config:{...config,supabaseUrl},service,authenticate})(req);
});
