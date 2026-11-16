const origin='https://whizkidal.github.io';
const home=origin+'/Track-WhizKids/tracker-admin.html';
const scopes='openid profile offline_access User.Read Mail.Send';
const encode=bytes=>btoa(String.fromCharCode(...bytes)).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'');
const random=()=>encode(crypto.getRandomValues(new Uint8Array(32)));
export function makeHandler({config,service,authenticate,request=fetch}){
 const configured=()=>!!(config.clientId&&(config.clientSecret||(config.privateKey&&config.thumbprint))&&config.tenantId);
 const callback=config.supabaseUrl+'/functions/v1/workspace-mail/callback';
 const authority=()=>`https://login.microsoftonline.com/${encodeURIComponent(config.tenantId)}/oauth2/v2.0`;
 const headers={'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Access-Control-Allow-Methods':'POST,OPTIONS','Cache-Control':'no-store','Content-Type':'application/json'};
 const json=(value,status=200)=>new Response(JSON.stringify(value),{status,headers});
 async function token(form){
  const credentials=config.privateKey?{client_assertion_type:'urn:ietf:params:oauth:client-assertion-type:jwt-bearer',client_assertion:await certificateAssertion(config,authority()+'/token')}:{client_secret:config.clientSecret};
  const r=await request(authority()+'/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({client_id:config.clientId,...credentials,scope:scopes,...form}),signal:AbortSignal.timeout(20000)});
  if(!r.ok)throw new Error('Microsoft connection needs attention. Reconnect your mailbox.');
  const data=await r.json();if(!data.access_token)throw new Error('Microsoft did not return access.');return data;
 }
 async function refresh(actor){const saved=await service('token',actor,{});if(!saved?.refresh_token)throw new Error('Mailbox is not connected.');const t=await token({grant_type:'refresh_token',refresh_token:saved.refresh_token});if(t.refresh_token)await service('connect',actor,{email:saved.email,refresh_token:t.refresh_token});return t.access_token;}
 async function deliver(job){
  // A timeout after dispatch is ambiguous: do not automatically retry a clinical invitation.
  let dispatched=false;
  try{
   const valid=await service('validate_job',null,{id:job.id});if(!valid.valid)throw new Error('Client ownership or recipient access changed. Review the invitation before sending.');
   const access=await refresh(job.user_id);
   dispatched=true;
   const r=await request('https://graph.microsoft.com/v1.0/me/sendMail',{method:'POST',headers:{Authorization:'Bearer '+access,'Content-Type':'application/json'},body:JSON.stringify({message:{subject:job.subject,body:{contentType:'Text',content:job.body},toRecipients:job.recipients.map(address=>({emailAddress:{address}}))},saveToSentItems:true}),signal:AbortSignal.timeout(20000)});
   if(r.status===202){await service('finish',null,{id:job.id,status:'accepted',detail:'Microsoft accepted this email for sending. See Sent Items for the message; acceptance is not delivery confirmation.'});return;}
   await service('finish',null,{id:job.id,status:r.status>=500?'uncertain':'failed',detail:r.status>=500?'Microsoft returned an uncertain result. Check Sent Items before sending again.':'Microsoft did not accept this email (HTTP '+r.status+'). Review the mailbox connection and recipients.'});
  }catch(e){await service('finish',null,{id:job.id,status:dispatched?'uncertain':'failed',detail:dispatched?'The send result could not be confirmed. Check Sent Items before sending again.':e.message});}
 }
 return async function handle(req){
  const url=new URL(req.url),route=url.pathname.split('/').at(-1);
  if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
  try{
   if(route==='worker'){
    if(req.method!=='POST')return json({error:'Method not allowed'},405);
    const expected=await service('worker_secret',null,{}),supplied=req.headers.get('x-worker-secret')||'';
    if(!expected?.secret||supplied!==expected.secret)return json({error:'Not authorised'},401);
    if(!configured())return json({error:'Microsoft connection is not configured'},503);
    const jobs=await service('claim',null,{});for(const job of jobs)await deliver(job);
    return json({processed:jobs.length});
   }
   if(route==='callback'){
    if(req.method!=='GET'||!configured())return json({error:'Microsoft connection is not configured'},503);
    const state=await service('take_state',null,{state:url.searchParams.get('state')||''});
    if(!state?.user_id)throw new Error('Connection request expired. Return to Invitations and try again.');
    if(url.searchParams.has('error'))throw new Error('Microsoft connection was not approved.');
    const t=await token({grant_type:'authorization_code',code:url.searchParams.get('code')||'',redirect_uri:callback,code_verifier:state.verifier});
    const profile=await request('https://graph.microsoft.com/v1.0/me?$select=mail,userPrincipalName',{headers:{Authorization:'Bearer '+t.access_token},signal:AbortSignal.timeout(15000)});
    if(!profile.ok)throw new Error('Microsoft mailbox could not be verified.');const me=await profile.json();
    await service('connect',state.user_id,{email:me.mail||me.userPrincipalName,refresh_token:t.refresh_token});
    return new Response(null,{status:303,headers:{Location:home+'?mail=connected','Cache-Control':'no-store'}});
   }
   if(req.method!=='POST')return json({error:'Method not allowed'},405);
   if(req.headers.get('origin')&&req.headers.get('origin')!==origin)return json({error:'Origin not allowed'},403);
   const actor=await authenticate(req.headers.get('authorization')||'');if(!actor)return json({error:'Please sign in again'},401);
   const body=await req.json();
   if(route==='status'){const status=await service('status',actor,{});return json({...status,configured:configured()});}
   if(route==='connect'){
    if(!configured())return json({error:'The Microsoft application still needs to be configured'},503);
    const status=await service('status',actor,{}),state=random(),verifier=random();await service('state',actor,{state,verifier});
    const challenge=encode(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(verifier))));
    const params=new URLSearchParams({client_id:config.clientId,response_type:'code',redirect_uri:callback,response_mode:'query',scope:scopes,state,code_challenge:challenge,code_challenge_method:'S256',login_hint:status.email,prompt:'select_account'});
    return json({url:authority()+'/authorize?'+params});
   }
   if(!['queue','list','cancel'].includes(route))return json({error:'Unknown operation'},404);
   if(route==='queue'&&!configured())return json({error:'Microsoft sending is not configured'},503);
   return json(await service(route,actor,body));
  }catch(e){return json({error:e.message||'The mail operation could not be completed'},400);}
 };
}
export async function certificateAssertion(config,audience){
 const bytes=Uint8Array.from(atob(config.privateKey.replace(/-----[^-]+-----/g,'').replace(/\s/g,'')),x=>x.charCodeAt(0));
 const key=await crypto.subtle.importKey('pkcs8',bytes,{name:'RSA-PSS',hash:'SHA-256'},false,['sign']);
 const now=Math.floor(Date.now()/1000),pack=o=>encode(new TextEncoder().encode(JSON.stringify(o)));
 const body=pack({alg:'PS256',typ:'JWT','x5t#S256':config.thumbprint})+'.'+pack({aud:audience,iss:config.clientId,sub:config.clientId,jti:crypto.randomUUID(),nbf:now-30,iat:now,exp:now+300});
 return body+'.'+encode(new Uint8Array(await crypto.subtle.sign({name:'RSA-PSS',saltLength:32},key,new TextEncoder().encode(body))));
}
