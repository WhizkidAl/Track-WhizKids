# Reusable Action Plan: architecture and evidence review

Reviewed 15 November 2026. Proposal, not an implemented replacement for the current plan.

## Recommendation

Keep one participant-aware tracker and one Action Plan engine. Give each plan a small compulsory core plus optional modules selected by Alex. A school participation plan is one preset, not the universal template. Home routines, communication access, learning, independence and community participation can use the same structure.

The working cycle is: identify a meaningful participation question → record what is known and uncertain → agree a support or assessment → assign responsibility → trial → review benefit, burden and unintended effects. Tracking is optional: a referral or resource build need not generate daily data collection.

## What exists, and what does not

Source reviewed: `index.html`, `action-plan.html`, `supabase/001_tracker_incident_alignment.sql`; live database policy metadata read without retrieving participant records.

| Area | Current architecture | Required direction |
|---|---|---|
| Identity | Tracker and plan share Supabase project and participant selector; access uses participant_access can_view/can_write | Reuse identity; add separate tracker/plan scopes and explicit admin/contributor/viewer capabilities |
| Tracker | tracker_days with school_checkpoints, incidents and tracker_reflections; separate section saves use upsert | Preserve brief core measures; introduce explicit section-level draft/submitted lifecycle |
| Locking | Live UPDATE policies allow can_write users to update days, checkpoints and incidents; UI offers editing | Enforce submitted immutability in the database, not merely by hiding buttons; corrections append original/new values, actor, timestamp and reason |
| Schedule | Three hard-coded checkpoints and a 15-school-day progress target | Versioned monitoring periods, 1–3 named checkpoints, school calendar/exclusions, pause/resume and date filters |
| Plan | One shared_action_plans row per participant, JSON answers keyed by data-key | Versioned template, plan instances, repeatable actions and module instances |
| History | Plan save and history insert are separate requests | Atomic server-side save plus audit snapshot; server timestamp and actor |
| Concurrent editing | Client reads updated_at, compares it, then upserts | Atomic expected-version check: current approach has a race between check and write |
| Plan status | Working/ready/agreed dropdown available to writers | Only Alex can approve/publish; contributors propose changes or complete assigned inputs |
| Generality | Afternoon focus, fixed three-week review, visual-kit and named-practitioner assumptions | Configurable setting, routine, owner, review date and optional resources |

No participant data, access grants or database policies were changed by this review. The repository does not contain the complete original tracker/plan schema, so migration work must begin with a full schema/trigger inspection. Policy review alone is not a complete security audit.

## Core and optional modules

Every plan has: participant/family priorities and voice; strengths/preferences; meaningful goal and setting; baseline evidence with source/date; agreed actions with owner/due date; review date and decision. Record consent to share, preferred communication/access needs, and how the participant's views or assent were sought. Distinguish observation, family/staff report and clinical hypothesis.

| Optional module | Questions and outputs |
|---|---|
| Communication and self-advocacy | What does the participant understand and express, using which modes? How can they ask for help, refuse, request a break or make a choice? AAC access, partner modelling and comprehension supports where indicated. |
| Environment and task access | Which sensory, language, social, physical or task demands create barriers? Specify a feasible adjustment, when it is available and who implements it. |
| Routines, transitions and participation | Arrival, learning, play, meals, self-care, community or transitions. Define a meaningful outcome in the selected context rather than assuming afternoon difficulty. |
| Visuals and social narratives | Existing resources and actual use; intended purpose; comprehension/accessibility; creator, teaching plan, location and review. Trial a specific tool rather than automatically building a large kit. |
| Regulation and wellbeing | Early signs, preferences, proactive support, co-regulation and recovery. Consider health/discomfort questions for appropriate clinicians; do not infer medication causation from a tracker association. |
| Incident understanding and safety | Observable sequence, context, communication, adult responses and recovery; competing hypotheses. Link to existing school safety/incident processes. A quick tracker is not a functional behaviour assessment. |
| Assessment and specialist consultation | Exact functional question, why it matters, existing information, assessor/discipline, consent, referral owner, priority, due date and how results will change the plan. Options may include hearing, communication/AAC, learning, motor/access, adaptive functioning or medical review when clinically indicated. |
| Resource build and team coaching | Resource specification, owner, delivery date, staff/family coaching, implementation check and maintenance. A finished resource is not evidence of benefit. |
| Monitoring and review | Question to answer, minimum useful measure, operational definitions, observer, opportunities/denominator, dates and decision rule. Team suggestions go to Alex for approval rather than changing live forms. |

Each repeatable action stores: linked goal/module, proposed/agreed status, action, rationale, owner, setting, start/due/review dates, expected change, measure, feasibility/burden, stop/adapt criteria and review outcome (keep/adapt/stop/seek assessment). Separate referral status from support-trial status.

Example: “During a chosen classroom routine, trial an accessible help/break choice board. Teacher models its use and honours the response. Record opportunities, spontaneous/supported requests and whether support was received. Review whether access and comfort improved, with participant/family input.” The team sets frequency and criteria from baseline; no universal target is implied.

## Evidence informing the design

These sources support planning principles; they do not validate this software or establish that a particular tool will help every child.

* **Function in context:** WHO's ICF includes activities, participation and environmental factors. Design implication: organise around what the person wants to do and barriers/supports in context, rather than diagnosis alone. [WHO ICF](https://www.who.int/classifications/international-classification-of-functioning-disability-and-health).
* **Broad paediatric functional assessment:** Autism CRC's national strengths-and-supports framework covers children aged 0–12 across diagnoses and service settings. Design implication: a functional-question/referral module should document strengths, support needs and the purpose of assessment. Its age scope should not be silently extended. [Framework](https://www.autismcrc.com.au/best-practice/strengths-and-supports).
* **Individualised, collaborative support:** Autism CRC's supporting-children guideline combines research, practice expertise, lived experience and family preferences; it covers goal setting, planning, delivery, monitoring and safeguarding. It contains consensus-based recommendations and targets autistic children aged 0–12. Design implication: participant/family priorities, feasibility and review are core fields; the proposed generic structure is our synthesis, not a recommendation to apply autism-specific interventions to everyone. [Guideline summary](https://www.autismcrc.com.au/best-practice/supporting-children/guideline/summaries).
* **Context before assumed cause:** NICE CG170 considers communication, physical/mental health and environmental factors, and functional assessment when indicated in autistic under-19s. Design implication: record competing explanations and referral questions before choosing a response. [NICE recommendations](https://www.nice.org.uk/guidance/cg170/chapter/Recommendations).
* **Tools selected for a defined purpose:** UNC's resources include visual supports and social narratives to support understanding. Keep these as optional, individually taught and reviewed tools; do not promise benefit from a generic story or treat all social narratives as equivalent to a specific branded protocol. [UNC support-understanding resource](https://afirm.fpg.unc.edu/sites/afirm.fpg.unc.edu/files/covid-resources/Support%20Understanding%20Strategy%20Packet.pdf).

## Monitoring design

Create monitoring_periods linked to participant and optionally plan/action. Store label, local timezone (Australia/Perth by default), start/end, status, checkpoint definitions, expected weekdays/excluded dates and measure version. Preserve all previous periods and submissions. Pause/resume changes expected opportunities; it must not erase observations. Prevent accidental overlapping schedules or define which period owns an entry.

Offer last 7 days, last 3 calendar months, selected period and custom dates. Clearly label whether today is included. Completion is submitted expected sections / sections due so far, excluding future checkpoints, holidays and pauses. Display absent/not observed/missing separately from low participation. Show the last submission and who submitted it only to authorised viewers.

Show counts alongside percentages; preserve the existing warning that associations do not establish cause. Compare periods only when definitions and opportunities are compatible. If a scale or checkpoint changes, show a version boundary rather than combining unlike data. Additional measures require an observable definition, response type, context and review purpose; avoid collecting everything just because it is possible.

## Suggested implementation order and acceptance checks

1. **Sign-in:** shared six- or eight-digit email-code flow and recovery instructions. Check actual email templates, first-time authorised access and school devices before distributing instructions.
2. **Integrity and permissions:** inventory existing schema, grant separate roles/scopes, add atomic submit/correct operations and append-only audit. Verify contributors cannot alter submitted rows or templates by direct API calls, viewers cannot write, and unassigned users cannot read records. Preserve existing records as legacy saves rather than pretending they were locked submissions.
3. **Periods and results:** add schedule/version model and filters. Test holidays, pauses, time boundaries, 1/2/3 checkpoints, missing data and term comparisons.
4. **Modular plan:** template versions → plan instances → module instances → actions → approved revisions. Migrate existing JSON keys without rewriting old answers or assigning them invented meaning. Preserve the current afternoon plan as a legacy preset/version. Test simultaneous edits and atomic history.
5. **Participant release:** pilot with an authorised school user and a family user; verify instructions against actual permissions and device behaviour. Publish a final agreed plan plus a short action list, with formal clinical records retained in the appropriate record system.

Proposed entities: plan_templates/template_versions (admin only), plans/plan_revisions, plan_modules, plan_actions, monitoring_periods/measure_versions, submissions and corrections. Keep protected clinical content in Supabase or the approved document store; public GitHub holds code and generic documentation only.
