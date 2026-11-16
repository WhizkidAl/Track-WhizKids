/* Per-client schedules apply to the existing tracker without discarding historic data. */
'use strict';
let trackerPeriods=[],workspaceOpen=false,scheduleReady=false,scheduleParticipant=null,scheduleVersion=0;
const scheduleChecks=['mid_morning','pre_lunch','end_of_day'];
function currentSchedule(){const date=document.getElementById('date').value,p=trackerPeriods.find(p=>date>=p.start_date&&date<=p.end_date);const active=!!p&&p.weekdays.includes(new Date(date+'T12:00:00Z').getUTCDay()||7)&&!p.excluded_dates.includes(date);return {p,active,legacy:!trackerPeriods.length};}
function scheduledSection(section){const s=currentSchedule();return scheduleReady&&workspaceOpen&&(s.legacy||(s.active&&(section==='home'?s.p.home_expected:section==='incident'?true:s.p.checkpoints.includes(section))));}
const originalTrackerAccess=renderTrackerAccess;
renderTrackerAccess=function(){originalTrackerAccess();
 const s=currentSchedule();let note=document.getElementById('scheduleNote');if(!note){note=document.createElement('p');note.id='scheduleNote';note.setAttribute('role','status');document.getElementById('date').closest('section').append(note);}
 note.textContent=!currentUser?'':!scheduleReady?'Checking monitoring schedule…':!workspaceOpen?'The setup is being reviewed. Contributions will open when the coordinator confirms it.':s.legacy?'No monitoring period configured. All three school checkpoints are available; missing-day expectations have not been set.':s.active?s.p.label+' · '+s.p.checkpoints.length+' school checks · '+(s.p.home_expected?'home morning expected':'home morning not expected'):'No tracking is scheduled for this date. Existing records remain available below.';
 document.querySelectorAll('button[onclick^="save"]').forEach(b=>{const action=b.getAttribute('onclick');let allowed=scheduleReady&&workspaceOpen&&(s.legacy||s.active);if(action.startsWith('saveMorning'))allowed=scheduledSection('home');if(action.startsWith('saveCheckpoint')){const key=action.match(/saveCheckpoint\('([^']+)'/)[1];allowed=scheduledSection(checkpoints.find(c=>c.key===key).dbKey);}b.disabled=!trackerCanWrite||!allowed;});
 for(const cp of checkpoints){const card=document.getElementById(cp.key+'_comment')?.closest('article');if(card){card.hidden=scheduleReady&&!s.legacy&&!s.p?.checkpoints.includes(cp.dbKey);card.querySelectorAll('input,textarea').forEach(x=>x.disabled=!trackerCanWrite||!scheduledSection(cp.dbKey));}}
 const morning=document.getElementById('sleep')?.closest('section');if(morning)morning.querySelectorAll('input,select,textarea').forEach(x=>x.disabled=!trackerCanWrite||!scheduledSection('home'));
 const homeIds={sleep:'sleep',breakfast:'breakfast',home_morning:'homeMorning',medication_status:'medication'};
 for(const [key,id] of Object.entries(homeIds)){const field=document.getElementById(id);field.closest('.mini-field').hidden=!!s.p?.home_fields&&!s.p.home_fields.includes(key);}
 if(morning)morning.querySelector('.section-copy').textContent='Complete the home questions agreed for this period. Add a comment when useful.';
 // The fixed 15-day target was not configured per client; avoid presenting it as a goal.
 const progress=document.querySelector('.progress-card');if(progress)progress.hidden=true;
 const how=document.querySelectorAll('.how-step')[1];if(how){how.querySelector('b').textContent='2 · Scheduled school checks';how.querySelector('p').textContent='Complete the school checkpoints shown for this client and date. Choose the closest participation and regulation options, then save each checkpoint. Extra detail is optional.';}
};
const originalLoadRecords=loadRecords;
loadRecords=async function(){const version=++scheduleVersion;trackerPeriods=[];workspaceOpen=false;scheduleReady=false;scheduleParticipant=document.getElementById('participant').value;renderTrackerAccess();await originalLoadRecords();if(version!==scheduleVersion||!currentUser||!scheduleParticipant)return;const pid=scheduleParticipant;const [r,state]=await Promise.all([db.rpc('tracker_schedule',{p_participant:pid}),db.rpc('workspace_status',{p_participant:pid})]);if(version!==scheduleVersion||pid!==document.getElementById('participant').value||!currentUser)return;if(r.error||state.error){document.getElementById('scheduleNote').textContent='The monitoring schedule could not load. Refresh before entering data.';return;}trackerPeriods=r.data||[];workspaceOpen=state.data?.opened===true;scheduleReady=true;renderTrackerAccess();};
function requireSchedule(section){if(!scheduledSection(section)){alert('This section is not scheduled for the selected date, or its schedule has not loaded.');return false;}return true;}
const originalMorning=saveMorning,originalCheckpoint=saveCheckpoint,originalIncident=saveIncident;
saveMorning=async function(reload=true){
 if(!requireSchedule('home')||!requireSession())return false;
 const ids={sleep:'sleep',breakfast:'breakfast',home_morning:'homeMorning',medication_status:'medication'};
 const fields=currentSchedule().p?.home_fields||Object.keys(ids);
 const row={participant_id:document.getElementById('participant').value,tracking_date:document.getElementById('date').value,parent_comment:document.getElementById('parentComment').value.trim()||null,morning_completed_by:document.getElementById('morningCompletedBy').value.trim()||null};
 for(const k of fields)row[k]=document.getElementById(ids[k]).value||null;
 const r=await db.from('tracker_days').upsert(row,{onConflict:'participant_id,tracking_date'});
 if(r.error){alert('Morning handover could not be saved: '+r.error.message);return false;}
 if(reload){await loadRecords();showToast('Morning saved');}return true;
};
saveCheckpoint=async function(key,reload=true){const cp=checkpoints.find(c=>c.key===key);if(!cp||!requireSchedule(cp.dbKey))return false;return originalCheckpoint(key,reload);};
saveIncident=async function(reload=true){if(!requireSchedule('incident'))return false;return originalIncident(reload);};
saveRecord=async function(){if(!requireSession()||!requireSchedule('incident'))return;if(scheduledSection('home')&&!await saveMorning(false))return;for(const cp of checkpoints)if(scheduledSection(cp.dbKey)&&!await saveCheckpoint(cp.key,false))return;if(getRadio('incident')&&!await saveIncident(false))return;await loadRecords();showToast('Scheduled sections saved');};
document.getElementById('date').addEventListener('change',renderTrackerAccess);
const originalEditRecord=editRecord;editRecord=function(date){originalEditRecord(date);renderTrackerAccess();};
renderTrackerAccess();

loadParticipants=async function(){
 const uid=currentUser?.id;if(!uid)return;
 const select=document.getElementById('participant'),previous=select.value;
 const r=await db.rpc('tracker_assigned_clients');if(currentUser?.id!==uid)return;
 if(r.error){select.innerHTML='<option value="">Unable to load assigned trackers</option>';setAuthStatus('Could not load your assigned trackers. Refresh to try again.');return;}
 participantMap=new Map(r.data.map(p=>[p.id,p.display_name]));
 select.innerHTML='<option value="">Select participant…</option>'+r.data.map(p=>'<option value="'+escapeHTML(p.id)+'">'+escapeHTML(p.display_name)+'</option>').join('');
 if(r.data.length===1)select.value=r.data[0].id;else if(participantMap.has(previous))select.value=previous;
 if(select.value)await loadRecords();
};
document.getElementById('date').value=new Intl.DateTimeFormat('en-CA',{timeZone:'Australia/Perth',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
initialiseAuth();
