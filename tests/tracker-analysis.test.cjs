const {test}=require('node:test'),assert=require('node:assert/strict'),A=require('../tracker-analysis.js');
const period={id:'p',label:'Trial',start_date:'2026-11-02',end_date:'2026-11-08',checkpoints:['end_of_day'],home_expected:true,weekdays:[1,2,3,4,5],excluded_dates:['2026-11-04']};
const day=(date,extra={})=>({tracking_date:date,checkpoints:[],incidents:[],...extra});
test('missing days follow configured school days, exclusions and past dates; partial is not complete',()=>{
 const data={periods:[period],days:[day('2026-11-02',{sleep:'Slept through',checkpoints:[{checkpoint:'end_of_day',participation:'independent',regulation:'settled'}]}),day('2026-11-03')]};
 const r=A.analyse(data,'2026-11-02','2026-11-08','2026-11-06');assert.equal(r.rows.length,5-1);assert.equal(r.expected,6);assert.equal(r.complete,1);assert.equal(r.partial,1);assert.equal(r.missing,4);assert.equal(r.rows.at(-1).cells[0].status,'Not yet recorded today');assert.equal(r.rows[0].cells[1].status,'Not scheduled');
});
test('no schedule means no invented missing-day denominator; blank checkpoint is not complete',()=>{
 const r=A.analyse({periods:[],days:[day('2026-11-02',{checkpoints:[{checkpoint:'end_of_day'}]})]},'2026-11-01','2026-11-05','2026-11-06');assert.equal(r.expected,0);assert.equal(r.rows.length,1);assert.equal(r.cpStats[2].regulationN,0);assert.match(r.rows[0].cells[0].status,/schedule unset/);
});
test('analysis excludes absent school ratings and unknown effects, while keeping real zero rates',()=>{
 const days=[day('2026-11-02',{sleep:'Slept through',checkpoints:[{checkpoint:'end_of_day',regulation:'settled',support_strategies:['quiet_break'],support_effect:'helped_clearly'}]}),day('2026-11-03',{sleep:'Slept through'}),day('2026-11-05',{sleep:'Woke often',checkpoints:[{checkpoint:'end_of_day',regulation:'significant_difficulty',support_strategies:['quiet_break'],support_effect:'not_sure'}]})];
 const r=A.analyse({periods:[],days},'2026-11-01','2026-11-07','2026-11-08');assert.equal(r.ratedDays,2);assert.equal(r.cpStats[2].participationN,0);assert.equal(r.cpStats[2].regulationN,2);assert.deepEqual(r.contexts[0].values[0],{value:'Slept through',n:1,difficulty:0});assert.equal(r.strategies[0].known,1);assert.equal(r.strategies[0].uncertain,1);assert.equal(r.weeks[0].n,2);assert.equal(r.weeks[0].settled,1);
});
test('two periods retain different schedules and pause gaps; historic unscheduled data remain visible',()=>{
 const p2={...period,id:'p2',start_date:'2026-11-16',end_date:'2026-11-20',checkpoints:['pre_lunch','end_of_day'],excluded_dates:[]};const r=A.analyse({periods:[period,p2],days:[day('2026-11-10')]},'2026-11-02','2026-11-20','2026-11-21');assert.equal(r.rows.length,10);assert.equal(r.expected,8+15);assert.equal(r.rows.find(x=>x.date==='2026-11-10').cells[0].status,'Not recorded — schedule unset');
});
test('CSV protects against spreadsheet formulas and quotes names safely',()=>{
 const r=A.analyse({periods:[],days:[day('2026-11-02',{sleep:'fine',morning_completed_by:'=HYPERLINK("bad")'})]},'2026-11-02','2026-11-02','2026-11-03');assert.match(A.csv(r),/'=HYPERLINK\(""bad""\)/);
});

test('optional medication is not counted as a missing home answer',()=>{const r=A.analyse({periods:[{...period,home_fields:['sleep','breakfast']}],days:[day('2026-11-02',{sleep:'Slept through',breakfast:'Ate well'})]},'2026-11-02','2026-11-02','2026-11-03');assert.equal(r.rows[0].cells[0].state,'complete');});
