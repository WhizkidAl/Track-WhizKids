const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
function setup(overrides={}){
 const elements=Object.fromEntries(['authEmail','authOtp','sendLinkBtn','verifyOtpBtn','otpField','otpActions'].map(id=>[id,{value:'',style:{},disabled:false,focus(){},reportValidity(){return this.value.includes('@')}}]));
 elements.authEmail.value='staff@example.com';
 const calls=[]; let status='';
 const auth={signInWithOtp:async args=>{calls.push(['send',args]);return {error:null}},verifyOtp:async args=>{calls.push(['verify',args]);return {error:null}},...overrides};
 const context={window:{location:{origin:'https://example.com',pathname:'/tracker/'}},document:{getElementById:id=>elements[id]},Date};
 vm.runInNewContext(fs.readFileSync('email-code-auth.js','utf8'),context);
 const controller=context.window.createEmailCodeAuth({auth},s=>status=s);
 return {elements,calls,controller,status:()=>status};
}
test('request preserves pending-user signup and throttles duplicate sends',async()=>{
 const s=setup(); await s.controller.send(); await s.controller.send();
 assert.equal(s.calls.length,1); assert.equal(s.calls[0][1].options.shouldCreateUser,true);
 assert.equal(s.calls[0][1].email,'staff@example.com'); assert.match(s.status(),/wait/);
});
test('six digits including leading zero verify as email OTP',async()=>{
 const s=setup(); s.elements.authOtp.value='012345'; await s.controller.verify();
 assert.equal(s.calls[0][1].token,'012345'); assert.equal(s.calls[0][1].type,'email');
 assert.equal(s.elements.authOtp.value,''); assert.equal(s.elements.verifyOtpBtn.disabled,false);
});
test('reject malformed codes and invalid email before network call',async()=>{
 const s=setup(); for(const code of ['','12345','1234567','abcdef','12 345']){s.elements.authOtp.value=code;await s.controller.verify()}
 s.elements.authEmail.value='invalid'; await s.controller.send(); assert.equal(s.calls.length,0);
});
test('network and expired-code errors restore controls without leaking response',async()=>{
 for(const method of ['send','verify']){
 const s=setup({signInWithOtp:async()=>{throw Error('network')},verifyOtp:async()=>({error:{message:'expired'}})});
 s.elements.authOtp.value='123456'; await s.controller[method]();
 assert.equal(s.elements.sendLinkBtn.disabled,false); assert.equal(s.elements.verifyOtpBtn.disabled,false);
 assert.match(s.status(),/not completed/);
 }
});
test('in-flight duplicate clicks issue only one request',async()=>{
 let release;let count=0; const s=setup({signInWithOtp:()=>{count++;return new Promise(r=>release=r)}});
 const pending=s.controller.send(); await s.controller.send(); await s.controller.verify();
 assert.equal(count,1);release({error:null});await pending;
});
test('signed-in rendering clears and hides OTP, signed-out restores it',()=>{
 const s=setup();s.elements.authOtp.value='123456';s.controller.render(true);
 assert.equal(s.elements.otpField.style.display,'none');assert.equal(s.elements.authOtp.value,'');
 s.controller.render(false);assert.equal(s.elements.otpField.style.display,'');
});
test('both pages include shared controller and valid inline JavaScript',()=>{
 for(const name of ['index.html','action-plan.html']){
 const html=fs.readFileSync(name,'utf8');
 assert.match(html,/src="\.\/email-code-auth.js"/);
 for(const id of ['authOtp','otpField','otpActions','verifyOtpBtn'])assert.equal(html.split('id="'+id+'"').length,2);
 for(const script of html.matchAll(/<script>([\s\S]*?)<\/script>/g))new vm.Script(script[1]);
 assert.match(html,/emailCodeAuth.render\(!!currentUser\)/);
 }
});
test('auth callbacks release the auth lock before loading participants',async()=>{
 for(const [page,fn] of [['index.html','initialiseAuth'],['action-plan.html','init']]){
  const html=fs.readFileSync(page,'utf8');
  const start=html.indexOf('async function '+fn+'(){');
  const code=html.slice(start,html.indexOf('\n'+fn+'();',start));
  let callback,locked=false,loads=0; const timers=[];
  const ctx={db:{auth:{getSession:async()=>({data:{session:null}}),onAuthStateChange:cb=>callback=cb}},
   document:{getElementById:()=>({addEventListener(){}})},currentUser:null,
   buildCheckpoints(){},toggleIncident(){},renderAll(){},clearForm(){},loadRecords(){},loadPlan(){},
   renderAuth(session){ctx.currentUser=session?.user||null},
   async loadParticipants(){assert.equal(locked,false);loads++},setAuthStatus(){},setTimeout:f=>timers.push(f)};
  vm.createContext(ctx);vm.runInContext(code,ctx);await vm.runInContext(fn+'()',ctx);
  locked=true;const result=callback('SIGNED_IN',{user:{id:'test'}});
  assert.equal(result,undefined);assert.equal(loads,0);locked=false;
  for(const timer of timers)timer();assert.equal(loads,1);
 }
});
