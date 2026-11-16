(function(root){
 'use strict';
 const checkpoints={mid_morning:'Mid-morning',pre_lunch:'Before lunch',end_of_day:'End of day'};
 const participation={independent:'Independent',with_support:'With support',modified_preferred:'Modified / preferred activity',not_meaningfully_participating:'Not meaningfully participating'};
 const regulation={settled:'Settled',some_difficulty:'Some difficulty',significant_difficulty:'Significant difficulty'};
 const homeFields=['sleep','breakfast','home_morning','medication_status'];
 const nonempty=v=>typeof v==='string'?!!v.trim():v!==null&&v!==undefined;
 function periodOn(periods,date){return periods.find(p=>date>=p.start_date&&date<=p.end_date);}
 function scheduled(p,date){return !!p&&p.weekdays.includes(new Date(date+'T12:00:00Z').getUTCDay()||7)&&!p.excluded_dates.includes(date);}
 function sectionState(section,row){
  if(!row)return 'empty';
  if(section==='home'){const n=homeFields.filter(k=>nonempty(row[k])).length;return n===4?'complete':n||nonempty(row.parent_comment)||nonempty(row.morning_completed_by)?'partial':'empty';}
  return participation[row.participation]&&regulation[row.regulation]?'complete':participation[row.participation]||regulation[row.regulation]||nonempty(row.comment)||nonempty(row.support_note)||row.context_factors?.length||row.support_strategies?.length?'partial':'empty';
 }
 function analyse(data,from,to,today){
  const days=data.days.filter(d=>d.tracking_date>=from&&d.tracking_date<=to), periods=data.periods||[],map=new Map(days.map(d=>[d.tracking_date,d]));
  const dates=new Set(map.keys());for(let d=new Date(from+'T12:00:00Z');d.toISOString().slice(0,10)<=to;d.setUTCDate(d.getUTCDate()+1)){const date=d.toISOString().slice(0,10);if(scheduled(periodOn(periods,date),date))dates.add(date);}
  let expected=0,complete=0,partial=0,missing=0;
  const rows=[...dates].sort().map(date=>{const d=map.get(date),p=periodOn(periods,date),on=scheduled(p,date);const cells=['home',...Object.keys(checkpoints)].map(section=>{const value=section==='home'?d:d?.checkpoints.find(c=>c.checkpoint===section);const state=sectionState(section,value);const required=on&&(section==='home'?p.home_expected:p.checkpoints.includes(section));if(required&&date<today){expected++;if(state==='complete')complete++;else if(state==='partial')partial++;else missing++;}const status=state==='complete'?'Complete':state==='partial'?'Partial':required?(date>today?'Not yet due':date===today?'Not yet recorded today':'Missing'):p?'Not scheduled':'Not recorded — schedule unset';return {section,value,state,required,status};});return {date,period:p,scheduled:on,cells,day:d};});
  const cpStats=Object.keys(checkpoints).map(key=>{const samples=days.flatMap(d=>d.checkpoints.filter(c=>c.checkpoint===key));const p=Object.fromEntries(Object.keys(participation).map(k=>[k,samples.filter(c=>c.participation===k).length]));const r=Object.fromEntries(Object.keys(regulation).map(k=>[k,samples.filter(c=>c.regulation===k).length]));return {key,p,r,participationN:Object.values(p).reduce((a,b)=>a+b,0),regulationN:Object.values(r).reduce((a,b)=>a+b,0)};});
  const rated=days.filter(d=>d.checkpoints.some(c=>participation[c.participation]||regulation[c.regulation]));
  const difficulty=d=>d.checkpoints.some(c=>c.participation==='not_meaningfully_participating'||['some_difficulty','significant_difficulty'].includes(c.regulation));
  const contexts=homeFields.map(field=>({field,values:[...new Set(rated.map(d=>d[field]).filter(nonempty))].sort().map(value=>{const sample=rated.filter(d=>d[field]===value);return {value,n:sample.length,difficulty:sample.filter(difficulty).length};})}));
  const samples=days.flatMap(d=>d.checkpoints),strategyKeys=[...new Set(samples.flatMap(c=>c.support_strategies||[]))];
  const strategies=strategyKeys.map(key=>{const sample=samples.filter(c=>c.support_strategies?.includes(key));const known=sample.filter(c=>['helped_clearly','helped_somewhat','no_clear_change','increased_difficulty'].includes(c.support_effect));return {key,uses:sample.length,known:known.length,helped:known.filter(c=>['helped_clearly','helped_somewhat'].includes(c.support_effect)).length,worse:known.filter(c=>c.support_effect==='increased_difficulty').length,uncertain:sample.length-known.length};});
  const weeks=new Map();for(const d of days){const date=new Date(d.tracking_date+'T12:00:00Z');date.setUTCDate(date.getUTCDate()-((date.getUTCDay()+6)%7));const key=date.toISOString().slice(0,10);const w=weeks.get(key)||{week:key,n:0,settled:0,significant:0};for(const c of d.checkpoints)if(regulation[c.regulation]){w.n++;if(c.regulation==='settled')w.settled++;if(c.regulation==='significant_difficulty')w.significant++;}weeks.set(key,w);}
  return {rows,expected,complete,partial,missing,days:days.length,ratedDays:rated.length,cpStats,contexts,strategies,weeks:[...weeks.values()].sort((a,b)=>a.week.localeCompare(b.week)),incidentDays:days.filter(d=>d.incidents.some(i=>i.occurred===true)).length,incidentAnswered:days.filter(d=>d.incidents.length).length};
 }
 function csvCell(value){let s=String(value??'');if(/^[=+\-@\t\r]/.test(s))s="'"+s;return '"'+s.replaceAll('"','""')+'"';}
 function csv(result){const rows=[['Date','Section','Status','Scheduled','Named by contributor','Last saved account','Saved at','Participation','Regulation']];for(const r of result.rows)for(const c of r.cells){const v=c.value||{};rows.push([r.date,c.section,c.status,c.required?'Yes':'No',c.section==='home'?v.morning_completed_by:v.completed_by,v.saved_by,v.updated_at,v.participation,v.regulation]);}return rows.map(r=>r.map(csvCell).join(',')).join('\r\n');}
 const api={checkpoints,participation,regulation,homeFields,periodOn,scheduled,sectionState,analyse,csv};
 if(typeof module==='object'&&module.exports)module.exports=api;else root.TrackerAnalysis=api;
})(typeof window==='undefined'?globalThis:window);
