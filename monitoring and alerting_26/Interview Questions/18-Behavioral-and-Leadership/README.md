# 18 · Behavioral & Leadership

For SDE III / Staff / senior DevOps–Platform–SRE roles, **this is often the round that decides the offer**. Technical bars are assumed; the questions test judgement, influence, conflict, ambiguity, failure and mentorship.

---

## 🟢 The mechanics — get these right first

### 1. STAR-L: the answer structure (and why the "L" matters)
| Part | Content | Time |
|---|---|---|
| **S**ituation | One or two sentences of context. Company size, team, stakes. **Don't spend 2 minutes here** | 10% |
| **T**ask | What *you* were responsible for. Not "the team needed" — "**I** was asked to / **I** owned" | 10% |
| **A**ction | **The bulk.** What *you* specifically did, in what order, and **why**. Include the alternatives you considered and rejected | 60% |
| **R**esult | Quantified outcome. Numbers, or a specific observable change | 15% |
| **L**earning | What you'd do differently, what you now do as a result. **This is what turns a story into evidence of growth** | 5% |

**The three rules that most affect your score:**
1. **"I", not "we".** Interviewers are hiring *you*. "We decided X" tells them nothing about your role. Say "I proposed X, I convinced Y, I wrote Z" — and give the team credit where it's due ("Priya did the data analysis; I made the call"). **A candidate who says only "we" leaves the interviewer unable to assess them; a candidate who says only "I" sounds like they can't work in a team. Aim for 80/20.**
2. **Quantify.** "Reduced deploy time from 2 hours to 12 minutes", "cut on-call pages 70%", "saved $40k/month", "3 incidents → 0 in two quarters". If you don't remember exactly, give a defensible estimate and say it's an estimate.
3. **Have a *specific* story, not a philosophy.** "I believe in blameless post-mortems" is a value; "**here's the outage where I ran one and what changed**" is evidence.

**Length:** 90 seconds to 3 minutes. **Practise out loud with a timer.** Most candidates' biggest problem is a 7-minute story with 5 minutes of context and 30 seconds of action.

### 2. The 8–10 stories you should have prepared
One story can serve 4–6 questions if you know its shape. Prepare these, each with numbers:

| # | Story | Serves questions about |
|---|---|---|
| 1 | **A major incident you led** (SEV1, high stakes, ambiguity) | Incident management, pressure, prioritisation, communication, technical depth |
| 2 | **A project you drove end-to-end** with measurable impact | Ownership, execution, delivering results, planning |
| 3 | **A technical disagreement you resolved** (with a peer, a senior, or a team) | Conflict, influence without authority, engineering judgement, ego |
| 4 | **A time you disagreed with your manager / pushed back on a decision** | Integrity, courage, communication up, "disagree and commit" |
| 5 | **A failure or mistake you made** — a real one with real consequences | Self-awareness, accountability, learning, honesty |
| 6 | **A time you mentored/levelled-up someone** (or a team) | Leadership, teaching, delegation, growing others |
| 7 | **A time you influenced without authority** (another team, leadership, a vendor) | Stakeholder management, persuasion, building coalitions |
| 8 | **A time you made a decision with incomplete information** | Judgement under ambiguity, risk assessment, reversibility |
| 9 | **A time you said no / killed something / dropped a commitment** | Prioritisation, scope management, honesty about capacity |
| 10 | **A time you improved something nobody asked you to** | Initiative, ownership, business acumen |

**Bonus stories that are gold for infra roles:** a migration you led, a cost reduction with a number, a security/compliance fix, a platform adoption win (and one that failed), a time you automated yourself out of toil, and a time you had to make an unpopular reliability/velocity trade-off.

**Preparation method:** write each as 6–8 bullet points (not a script — scripts sound rehearsed and collapse under follow-ups), record yourself answering, and **anticipate 3 follow-up questions per story** ("what would you do differently?", "what if they'd said no?", "how did you measure it?").

### 3. What interviewers are actually scoring
| Axis | What good looks like | What bad looks like |
|---|---|---|
| **Impact & scope** | Org-level or multi-team; outcomes measured; lasted beyond you | Task-level; "I fixed a bug"; no numbers |
| **Ownership** | "I owned it, I drove it, I followed up" | "The team decided", "my manager told me to", passive voice |
| **Influence** | Persuaded with data/prototypes/pilots; built coalitions; changed minds without authority | Escalated immediately; gave up; or steamrolled |
| **Judgement** | Weighed trade-offs explicitly; considered reversibility; knew when to decide with 70% information | Binary thinking; decided only on gut; or analysis paralysis |
| **Self-awareness** | Names your own contribution to the problem; specific learnings you still apply | Everyone else was the problem; no learnings |
| **Communication** | Structured, concise, calibrated to the audience; listens and answers the question asked | Rambling; jargon-dumping; answering a different question |
| **Collaboration & empathy** | Describes other people as competent people with real constraints | Others are obstacles or idiots |
| **Growth** | Later stories show skills the earlier ones lacked | Same story at every level for 8 years |

---

## 🟢 The questions, with model answers

### 4. "Tell me about yourself." (The opener — it's a real question)
**What they want:** can you summarise your career with a narrative and a point of view, in 90 seconds, and does it connect to *this* role?

**Structure:** Present → Past → Future.
> "I'm currently a senior DevOps engineer at [X], where I own the platform for ~40 services and 8 product teams — Kubernetes, GitOps, observability, and the CI/CD pipeline. My focus for the last two years has been turning deployment from a manual, risky event into a self-service paved road: we went from a 2-hour, three-system deploy to a 12-minute GitOps deploy with automated canary rollback, and change failure rate dropped from about 30% to under 10%.
> Before that I was an SRE at [Y], where I got my grounding in incident command and SLOs — I ran the on-call rotation and built the burn-rate alerting that replaced about 200 noisy threshold alerts.
> I started as a backend engineer, which is why I care about the developer experience side of platform work — I've been the person waiting on a broken pipeline.
> What draws me to this role is [specific thing about the company/team] — and specifically the chance to [their actual problem, e.g. build the platform function from scratch / take multi-region reliability seriously]."

**Rules:** keep it under 2 minutes, end with why *this* role, don't recite your résumé chronologically from 2012, and **don't include personal details they didn't ask for**.

### 5. "Why are you leaving?" / "Why this company?"
**Never badmouth.** The interviewer is asking: are you running *from* something (a risk) or *toward* something (a signal)?

**Good frame:** "I've had a great run at X — I built [specific thing] and it's now in a steady state where the remaining work is maintenance rather than building. I'm looking for [specific challenge: scale, greenfield, a domain, a leadership scope] and this role is exactly that because [specific, researched reason]."

**Show you researched them:** reference a specific product, engineering blog post, architecture, or challenge. "I read your post on migrating to Karpenter" beats "you're a great company". **This is the cheapest possible way to stand out, and almost nobody does it.**

**If you were laid off or left badly:** be brief, factual and forward-looking. "My team was affected by a reorganisation in March. I'm looking for a role where [X]." **Do not editorialise.**

### 6. "Tell me about a time you had a conflict with a colleague."
**What they're really asking:** are you safe to work with? Can you disagree without damaging the relationship or the work?

**Model answer shape:**
> **S/T:** "When we were designing the new deploy pipeline, the tech lead of the payments team and I disagreed fundamentally. I wanted GitOps with automated sync; he wanted CI-driven push deploys, because his team had been burned by a GitOps tool three years earlier and because he didn't trust that the config repo could express their migration requirements."
> **A:** "Three things. First, I made sure I actually understood his position before arguing mine — I asked him to walk me through the incident that burned them, and it turned out the real problem was that they had no way to run database migrations declaratively. That wasn't a GitOps problem, it was a gap in my design. Second, I built a small prototype for his specific case: a PreSync hook running their migration job, with a rollback path, deployed to a throwaway namespace. That took a day and it moved the conversation from opinions to evidence. Third, I conceded the part he was right about — we added a documented, audited push-deploy escape hatch for the migration cases that genuinely couldn't be expressed declaratively, rather than pretending 100% GitOps was achievable."
> **R:** "His team adopted GitOps and became one of the strongest advocates — partly because the escape hatch meant they never felt cornered. We rolled it to all eight teams over two quarters with no forced migrations."
> **L:** "What I took away is that most technical disagreements are actually **unshared context or an unmet requirement**, not a difference of opinion. Since then my first move in a disagreement is 'show me the case where this breaks for you' — because if I can't handle their hardest case, they're right."

**Key moves:** you sought to understand first; you used **evidence, not seniority or volume**; you **conceded something real**; the relationship survived; there was a measurable outcome.

**Anti-patterns:** "We disagreed but I was right and eventually he came around" (no self-awareness); "I escalated to my manager" (no influence skills); "I just went with his approach to keep the peace" (no backbone); a story where the other person is described as incompetent or political.

### 7. "Tell me about a time you failed / made a mistake."
**This is the highest-risk question.** They're testing honesty, accountability, and whether you learn. **A "failure" that's actually a humblebrag ("I work too hard", "I care too much") is an instant credibility loss.**

**Choose a real failure with real consequences and a real lesson.**

**Model answer shape:**
> **S/T:** "Early in my senior role I designed and rolled out a new alerting configuration for our Kubernetes clusters. I replaced about 150 threshold alerts with SLO burn-rate alerts, and I was proud of it — the noise dropped 80%."
> **A (the mistake):** "What I didn't do was validate the new alerts against real failure modes. Three weeks later we had a production outage: a database connection pool exhausted, requests queued, and latency went to 30 seconds. But our success-rate SLI counted a queued-then-succeeded request as a success, so **the SLO alert never fired**. A customer reported it 22 minutes in. I'd built an alerting system that was quiet because it was blind, and I'd removed the noisy alerts that would have caught it."
> **A (the response):** "I owned it publicly in the incident review — not 'the alerting missed it' but 'I designed it and this was my error'. Then I did three things: added a latency SLI alongside the availability SLI, added saturation alerts for the leading indicators (pool utilisation, queue age) that I'd dismissed as 'cause-based noise', and — the important one — I built an **alert validation process**: for every alert, we now simulate the failure it's meant to catch, in staging, and confirm it fires within the expected time. I made that a checklist item for every alert change, and I wrote it up so it outlived me."
> **R:** "We've had four incidents since; all four were detected by monitoring before a customer reported, and detection time went from ~20 minutes to under 3. The validation process caught two more blind spots before they became incidents."
> **L:** "The lesson I still apply: **a quiet system isn't necessarily a healthy system, and reducing noise without validating coverage is how you build a blind spot.** Now, whenever I remove or replace a detection mechanism, I ask 'what failure would this have caught that the new one won't?' — and I test the answer."

**Key moves:** real consequences; **unambiguous ownership in the first person**; the fix was systemic, not personal; the learning is a rule you still apply; **you mention the customer/business impact, not just the technical impact.**

### 8. "Tell me about a time you influenced without authority."
**What they want:** how do you get people who don't report to you to change what they're doing?

**Model answer shape:**
> **S/T:** "I wanted to standardise how our 8 teams did observability — every service had different metrics names, different dashboards, and no SLOs. Nobody reported to me, and every team had more urgent work."
> **A:** "Four things. First, I made it **cheaper to comply than to resist**: I wrote a shared instrumentation library so a team got RED metrics, trace propagation, structured logging and a standard dashboard by importing one package and adding two annotations — about an hour of work instead of a week. Second, I **piloted with one team that had a real problem** — the team with the worst on-call load — and I did the work *for* them. Within a month their pages dropped from ~40 a week to ~8. Third, I **published the numbers**, not the mandate: a short write-up with the before/after and the on-call feedback, shared in the engineering all-hands. Two more teams asked to be next. Fourth, I got the **policy** adopted only once adoption was voluntary and obvious — a new-service template that includes observability, so it became the default rather than an ask."
> **R:** "All 40 services instrumented within two quarters, with one team opting out for a legitimate reason (a legacy service being decommissioned) which I documented rather than fought. Aggregate on-call pages fell 60%, and the time-to-diagnose in incidents dropped noticeably — we measured it in the post-mortems."
> **L:** "What I learned is that influence without authority is mostly **removing friction and manufacturing evidence**. Mandates work if you have authority; if you don't, you have to make the right thing the easy thing and let other people's results do the persuading. The mistake I'd avoided — and had made earlier in my career — is writing a standards document and expecting adoption."

### 9. "How do you handle working with a difficult person?"
**Trap:** the question invites you to complain. **Never take the bait.**

**Frame:** describe the *behaviour* and its *impact*, not the person's character. Then describe what you did, and what you'd do differently.

> "I worked with a senior engineer whose reviews were thorough but came back after three or four days, which was blocking a time-sensitive project. I assumed at first he was deprioritising us. Instead of escalating, I asked him directly how his review load was going — and it turned out he was the designated reviewer for four teams and had no visibility into which reviews were blocking. So we made two changes: I started flagging blocking PRs explicitly with the deadline in the description and pinging him with context rather than just a link, and he agreed to a same-day pass on flagged PRs, giving 'approve with comments' rather than a full deep review when time was short. I also raised the structural issue with his manager — not as a complaint but as a resourcing observation, and it led to two more people being trained as reviewers for his area.
> What I'd do differently now: I'd have asked about his load on day one instead of day four. **Most 'difficult' behaviour is a constraint you can't see**, and asking is faster than assuming."

**Key moves:** you assumed good faith; you talked to the person directly first; you distinguished the person from the systemic problem; you escalated the *system*, not the *person*; you have a learning.

### 10. "Tell me about a time you had to make a decision with incomplete information."
**What they want:** judgement, and whether you understand reversibility.

**Model answer shape:**
> **S/T:** "We were choosing between adopting a service mesh or building a shared client library for mTLS and retry standardisation across 40 services. We had three weeks before a compliance deadline that required encrypted service-to-service traffic, and no way to know in that time whether a mesh would perform acceptably at our scale."
> **A:** "I framed it as a reversibility question, which changed the analysis. A shared library is hard to reverse — it's in 40 codebases, and removing it means 40 migrations. A mesh is comparatively reversible — it's infrastructure, and if it fails we can remove the sidecars without touching application code. So I optimised for **learning fast on the less reversible decision**. I ran a two-day experiment: deployed Linkerd to three representative services, measured the latency overhead (about 0.8ms p50, 3ms p99 — acceptable), measured the resource cost (~40MB per pod, which at our scale was fine), and — the decisive finding — discovered that two of our services used a custom TCP protocol that the mesh couldn't proxy at all.
> That last finding reframed the decision: the mesh couldn't cover everything, so we'd need a fallback regardless. I recommended a **hybrid**: the mesh for the HTTP/gRPC services (which got us compliance coverage for ~85% of traffic in days, with no application changes) and the shared library for the two custom-protocol services (which had a longer timeline but were only two teams). I presented it with the measured data and the explicit statement of what we didn't know yet — the operational cost of running the mesh long-term, which we'd learn in the first quarter."
> **R:** "We hit the compliance deadline with two days to spare. The mesh ran for 18 months and we later removed it when a Cilium upgrade gave us sidecar-less mTLS — which was cheap precisely because it was reversible. The library is still in use for the two custom services."
> **L:** "The habit I took from it: when I can't get enough information to decide, I ask **which option is more reversible**, and I spend my limited time de-risking the *irreversible* one. And I now always state explicitly what I don't know and how I'll find out — it makes the decision reviewable later instead of looking like a guess that happened to work."

### 11. "Tell me about a time you mentored someone."
**What they want:** do you multiply your impact through others, and do you actually know how?

**Model answer shape — make it specific and include the *method*:**
> "A mid-level engineer joined my team and was strong technically but stuck: every PR he submitted came back with the same three review comments, and he was losing confidence and starting to ask for approval before writing anything.
> I did four things. First, I **stopped giving him answers in reviews** and started asking questions — 'what happens to this if the deployment is rolled back mid-way?' — which was slower and more annoying for both of us, but it made him do the analysis instead of me. Second, I **paired on the hard parts, driving from his keyboard**, so he saw my process out loud: how I read an unfamiliar codebase, how I form hypotheses, how I decide what to test. Third, I **gave him a scoped piece of real ownership** — the migration of our alerting rules to the new format — with me as a reviewer rather than a co-author, so it was genuinely his. Fourth, I gave **specific, immediate feedback both ways**: not 'good job' but 'the way you structured that rollout so it could be paused and resumed is exactly the thinking that was missing two months ago'.
> Six months later he was reviewing other people's PRs and ran a production incident as IC without me in the channel. He's since been promoted.
> What I learned: **mentoring isn't teaching, it's removing the blockers to someone's own learning** — and the hardest part is restraining yourself from fixing the thing, because fixing it is faster and makes you feel useful but doesn't help them at all. The other thing I learned is to give ownership early and scope it carefully; a person grows from being responsible for something real, not from being supervised well."

### 12. "Tell me about a time you disagreed with your manager or a senior decision."
**What they want:** integrity and backbone, plus the ability to commit once decided.

**Model answer shape:**
> "My manager decided we'd skip a database migration rehearsal before a major version upgrade, because the window was tight and he judged the risk acceptable. I disagreed — we were upgrading Postgres across two major versions on a 400GB database with a custom extension, and I thought an untested upgrade was the bigger risk.
> I raised it once privately with data rather than opinion: I showed him the extension's changelog with two breaking changes, and I estimated the rehearsal at four hours using a restored snapshot in a scratch account. He still said no — the deadline was contractual and he owned that trade-off.
> So I did two things. I **committed to the decision** — I didn't re-litigate it in the team meeting or undermine it. And I **reduced the risk within it**: I wrote and tested a rollback procedure, took a verified snapshot immediately before the window, scheduled the upgrade in the lowest-traffic period, had the extension vendor on standby, and set explicit abort criteria with times so we weren't deciding under pressure at 2am.
> The upgrade succeeded. But the rehearsal would have caught something: two weeks later, in staging, we hit exactly the extension incompatibility I'd flagged, and it took a day to work around. If that had happened during the production window we'd have missed the abort time.
> What I learned is that **'disagree and commit' doesn't mean 'disagree and do nothing'**. Once the decision is made, your job shifts to making the decision as safe as possible — and to making sure the information you had gets recorded, so the next decision is better informed. I did write it up afterwards, without any 'I told you so', and we added upgrade rehearsals to the checklist for anything over 100GB. That was the durable outcome."

### 13. "How do you prioritise when everything is urgent?"
> "Three filters, in order. First, **reversibility and blast radius**: something that becomes much harder or more expensive later goes first (a schema change before a dependent feature; a security fix before a refactor). Second, **who is blocked**: work that unblocks five people beats work that unblocks me, and work blocking a customer-facing date beats internal work. Third, **expected value against effort** — but I deliberately apply that last, because it's the filter that makes everything feel equally reasonable.
> Then I make the trade-off **visible and explicit** rather than absorbing it silently. I'd tell my manager and the stakeholders: 'here are the six things; I can do two well this week; here's my ranking and here's what slips if you disagree.' That converts an impossible private judgement into a shared, reviewable decision — and about half the time, someone says 'actually, number four doesn't matter', which is information I couldn't have had.
> The one thing I don't do is work longer to avoid the conversation. **A queue that only I can see isn't prioritisation, it's a hidden debt**, and it eventually surfaces as a missed deadline with no warning."

### 14. "How do you handle pressure / tight deadlines?"
Be concrete, not heroic. **The "I worked nights and it was fine" answer is a red flag** (it says you don't manage scope or risk).

> "I separate **scope, quality and time**, and I make the trade-off explicit rather than absorbing it. Under a hard deadline I'd: cut scope to the smallest thing that meets the actual requirement — and go find out what the requirement really is, because 'the deadline' is often a proxy for something negotiable; keep the non-negotiable quality bars (tests on the risky paths, rollback capability, observability, security) and consciously accept shortcuts elsewhere **with them written down as debt and dated**; communicate the risk early rather than at the deadline; and protect the team from context-switching, which is what actually kills deadline work.
> For example, [short specific story: a two-week deadline where I cut scope, kept the rollback path, and shipped on time with two documented follow-ups that were done the next sprint].
> What I've learned is that the biggest risk under pressure isn't speed, it's **silent quality reduction** — the thing you skipped that nobody knows you skipped. So I always write down what I deferred. It takes five minutes and it's the difference between a deadline met and an incident three weeks later."

---

## 🔵 Leadership and staff-level questions

### 15. "How do you handle a project that's failing / off track?"
> "First I establish whether it's off track on **scope, time or value** — they need different responses. A project late but delivering the right thing needs a scope cut or a date change. A project on time but building the wrong thing needs to stop.
> Then I get honest about the state, publicly. The most common failure I've seen is a project that's quietly three months behind because everyone reports the optimistic view upward. So I'd re-baseline: what's actually done, what's left, what are the real unknowns, and what's the earliest credible completion. That's an uncomfortable conversation and it's much cheaper than the one in three months.
> Then I look for the **constraint** — usually one of: an unresolved technical unknown, a dependency on another team that isn't committed, unclear requirements, or too many people coordinating. Each has a different fix: spike the unknown, escalate the dependency to a written agreement with a date, get the requirement decided by whoever owns it, or **reduce the team and increase the focus**.
> And I'd consider stopping. Killing a project is a legitimate and often correct outcome, and the earlier you do it the more you save. I'd want the decision made on evidence and recorded — 'we spent X, we learned Y, the value case no longer holds' — so it doesn't get restarted in six months by someone who doesn't know the history.
> [Then a specific story.]"

### 16. "How would you improve a team/process that's dysfunctional?"
> "I'd start by diagnosing rather than prescribing, because 'dysfunctional' usually describes a symptom. I'd look at the artifacts first — deploy frequency, change failure rate, incident counts and MTTR, on-call page volume, PR cycle time, ticket age — because they're hard to argue with and they tell you whether the problem is delivery, reliability, or coordination. Then I'd talk to everyone individually for 30 minutes with the same three questions: what's the most frustrating part of your week, what would you fix first if you could, and what are we doing that we should stop? **The pattern across those answers is almost always the diagnosis**, and people support what they helped identify.
> Then I'd pick **one** thing — the highest-frequency complaint with the cheapest fix — and fix it visibly and fast. Not the most important thing; the most *credible* thing. A team that's been promised transformation before needs evidence that change happens. Usually that's something like a 40-minute pipeline, a broken test suite, or a pointless recurring meeting.
> After that I'd tackle the structural issue with the team, not for them — and I'd accept that some dysfunctions are management or staffing problems that I can't fix from inside, in which case my job is to document them clearly and escalate with evidence, not to absorb them.
> [Specific story with numbers.]"

### 17. "Describe your approach to technical debt."
> "I treat it as **debt, not dirt** — it's a financial instrument with an interest rate, and the question is whether the interest exceeds the cost of paying it down. Some debt is deliberate and good: we shipped the feature three weeks early by hardcoding a config, and we paid it back in an hour last month. Some is accidental and expensive: a service with no tests where every change causes an incident — that one has a high interest rate and I'd pay it down.
> So my approach is: **make the interest visible.** I'd attach a cost to each item — incidents caused, hours spent working around it, features blocked, on-call pages, engineer attrition — and rank by that, not by aesthetic offensiveness. Then I'd fold repayment into normal delivery rather than asking for a 'tech debt quarter', which never gets approved and never works: a fixed proportion of each sprint (I'd argue 15–20%), plus opportunistic repayment (you're in that code anyway), plus paying down anything implicated in an incident as a post-mortem action item.
> And I'd stop the bleeding, which matters more than repayment: define the standard for new code, put the guardrails in CI so the debt can't be re-created silently, and make the *next* person's path easier. A team that pays down 10% and creates 20% is losing; the rate of creation is the number to manage.
> The one thing I push back on is 'we'll refactor it properly later'. Later doesn't exist. Either it's worth doing now, in scope, or it's worth doing incrementally, or it isn't worth doing."

### 18. "How do you make a technical decision that's expensive or unpopular?"
> "I separate the **decision** from the **communication**, and I invest heavily in both.
> For the decision: I write it down. A short document — the problem, the constraints, three options with their real trade-offs (including the cost of doing nothing), my recommendation, and explicitly what I'd need to see to change my mind. Writing forces precision, and it makes the decision reviewable later, which is how an organisation learns. For anything significant I'd also define the **reversibility** and the **exit criteria** up front: what would tell us in three months that this was wrong?
> For the communication: I'd go to the people most affected **before** the announcement, individually, and genuinely listen — not to sell. Half the time they raise something I missed, and the other half they still disagree but they know they were heard, which changes everything about adoption. Then I'd present it with the trade-offs visible, including the costs — an all-upside proposal makes people suspicious, correctly.
> And I'd commit: once decided, I'd fund it properly, measure it against the criteria I set, and say so publicly if it isn't working. **The thing that destroys credibility isn't a wrong decision, it's a decision that's quietly abandoned or defended past the evidence.**
> [Specific story — ideally one where you were wrong and handled it well, which is more impressive than one where you were right.]"

### 19. "How do you balance technical excellence with business needs?"
> "I start from the position that they're usually the same thing on a long enough timeline, and where they genuinely conflict, the conflict is about **time horizon**, not values.
> So I make the horizon explicit. If the business needs something in two weeks, I'll take the shortcut — but I'll say which shortcut, what it costs later, and I'll write it down with a date. That converts an invisible compromise into a visible, owned decision. Most 'engineering vs business' fights are actually engineers making silent compromises that surface as incidents six months later, or business people asking for speed without knowing the price.
> I also translate. 'We need to refactor the auth service' loses every time. 'Auth is implicated in 4 of our last 6 incidents, each costing about 3 engineer-days plus customer impact; the fix is 2 weeks and would remove that class' wins. **Business stakeholders aren't anti-quality, they're anti-unclear-proposals.**
> The line I hold is the one where the compromise creates an unbounded or unacceptable risk — security holes, data loss, compliance breaches, or things that can't be reversed. Those I push back on hard, with the risk quantified, and if I lose I escalate and document, because I don't want to be the only record of the decision.
> And I look for the third option, because it usually exists: ship the risky 20% behind a flag to 5% of users, do the migration in two phases, build the temporary thing on the right foundation so it can be extended rather than replaced."

### 20. "Where do you see yourself in 3–5 years?" / "What are your career goals?"
**They're checking:** will you stay, do you have direction, and does this role fit it?

> "I want to be doing [individual-contributor leadership / platform ownership / architecture] at a scope where my work affects multiple teams rather than one service — specifically I want to keep going deeper on [reliability and platform engineering], because that's where I've had the most impact and where I still find the problems interesting.
> In three years I'd like to be the person who owns the platform or reliability strategy for an engineering org — meaning I'm setting the direction, growing the people doing the work, and accountable for the outcomes rather than writing most of the code myself.
> This role fits that because [specific reason tied to the job description and what you know about the company].
> I'm not aiming for a management title specifically — I'd rather grow into whatever has the most leverage, and I'd want that conversation to be evidence-based rather than calendar-based."

**Avoid:** "in your seat" (cute, rarely lands), "running my own company" (signals you'll leave), a title-only answer, or "I haven't thought about it".

### 21. "What are your salary expectations?"
- **Research first**: levels.fyi, Glassdoor, Blind, peers. Know the band for the level and location.
- **Defer if possible**: "I'd like to understand the full scope and the level first — could you share the band for this role?" **Many places now disclose it legally; ask.**
- **Give a range, anchored high, tied to total comp**: "Based on the scope and my experience, I'd be looking at [X–Y] total compensation, though I'm flexible on the mix of base, equity and bonus, and the level matters to me as much as the number."
- **Never give a number below your floor**, and never say "whatever you think is fair".
- **Know your alternatives** — a competing offer or a strong current position is the only real negotiating leverage, and you should be honest about it without bluffing.

---

## 🔴 Scenario

### 22. "You inherit a team with terrible on-call, no documentation, and low morale. First 90 days?"
**Days 1–14: Listen and measure. Change nothing structural.**
- **1:1s with every team member** (30–45 min, same three questions: what's most frustrating, what would you fix first, what should we stop doing). Take notes; look for the pattern.
- **Read the artifacts**: last 6 months of incidents and post-mortems (are action items done?), the on-call rotation and page history, the deploy frequency and failure rate, the ticket queue age, the attrition history.
- **Shadow an on-call shift** without intervening. **Nothing teaches you the truth about a team faster than one night on their pager.**
- **Establish the baseline numbers** so any improvement is measurable: pages/shift, % actionable, MTTR, incident count, deploy lead time, change failure rate, and a **team pulse survey** (5 questions, anonymous).
- **Explicitly commit to not making big changes yet**, and say why. Trust is the prerequisite for everything else, and a new senior person who reorganises things in week one loses it.

**Days 15–45: Fix the loudest thing, and make one win visible.**
- **Pick the highest-frequency, lowest-cost pain** from the 1:1s — usually the on-call load, a 40-minute pipeline, or a broken test suite. Fix it, fast, visibly, and tell people you fixed it *because they told you to*.
- **On-call specifically** (the highest-leverage thing for morale):
  - Triage every alert: **delete or demote** anything that produced no action in the last 6 months. This alone often halves page volume in a week.
  - Add a runbook to every remaining page, starting with the top 5 by frequency.
  - Fix the top 3 *causes* (not symptoms) as engineering work.
  - Check the basics: is the rotation sustainable (≥ 6 people)? Are people compensated? Is there a secondary and an escalation path? Is there a handover ritual?
  - Set a target: **≤ 2 pages per shift, > 80% actionable** — and track it weekly, publicly.
- **Start a weekly alert/incident triage ritual** — 30 minutes, the whole team, reviewing every page and every incident action item. **This single meeting changes a team's relationship with its own reliability**, and it makes the invisible work visible.
- **Document as you go, not as a project.** Every fix produces a runbook entry; every incident produces a post-mortem; every recurring question produces a doc. **A "documentation project" never finishes; documentation as a byproduct does.**

**Days 46–90: Build the system, and set direction.**
- **Blameless post-mortems for every SEV1/2**, with owned, dated action items and a **completion-rate metric** reported monthly. If completion is under ~70%, that's the real problem to solve.
- **SLOs on the 3–5 most important services**, with burn-rate alerting replacing more threshold noise, and error-budget policy agreed with product/leadership.
- **A reliability roadmap** with the top 10 systemic fixes ranked by incidents-caused and effort, funded as a fixed proportion of capacity (I'd argue 20%).
- **Golden paths / self-service** for the most common toil: a deploy template, an environment template, an onboarding doc that actually works.
- **Set the team's operating agreements explicitly**: how we review, how we deploy, how we handle incidents, how we make decisions, how we disagree. Written, one page, agreed together.
- **Deliver the results report**: baseline vs now, with numbers, shared with the team and their leadership. **This is what gets you the credibility and the funding for the next 90 days.**
- **Individual growth**: for each person, one specific growth goal and one piece of real ownership. Morale is mostly about **agency and progress**, not perks.

**What I would not do:** reorganise the team, change the tech stack, criticise the previous lead or the existing systems in public, promise things I can't fund, or make the first 90 days about my ideas. **The 90-day test is whether the team trusts me and whether the on-call load and incident count went down. Everything else is second-order.**

### 23. "A senior engineer on your team is brilliant but toxic. Handle it."
**First, be precise about what "toxic" means** — the response differs radically:
| Behaviour | Response |
|---|---|
| **Blunt but correct and well-intentioned** (harsh code reviews, direct disagreement) | Coaching on communication style; often a *strength* mis-deployed. Don't punish directness — you'll lose the honesty along with it |
| **Dismissive/condescending** (interrupts, mocks, "that's obviously wrong", takes credit) | Direct feedback with specific examples, a behaviour change expectation, and a follow-up date |
| **Obstructive/political** (blocks others' work, hoards information, forms factions, undermines decisions) | Serious; involves the manager; needs a documented expectation and consequences |
| **Bullying, harassment, discrimination** | **Not a performance conversation.** Escalate immediately to management/HR, protect the affected people, and do not attempt to mediate it yourself |

**The approach for the middle two (the hard, common case):**
> "I'd start with **direct, specific, private feedback** — and I mean specific instances, not characterisation. 'You're toxic' is undefendable and unfalsifiable; 'in Tuesday's review you told Sam his design was amateur, in front of four people, and he hasn't proposed anything since' is a fact we can both look at. I'd explain the **impact** in terms they care about: 'you're the best engineer here, and right now the team's output is lower than it would be without you, because two people have stopped contributing ideas. That's not a soft problem, it's the thing you're being measured on at this level.'
> Then I'd make it **concrete and bidirectional**: what specifically changes (review language, letting others finish, giving credit by name, disagreeing in private before public), what support they get (I'll pair on reviews for a month; I'll give you feedback in the moment rather than accumulating it), and **when we'll review it** — 30 days, with an explicit statement of what success looks like.
> I'd also **check my own read**: I'd ask two or three people who work with them, privately, whether my perception matches theirs, and whether there's context I'm missing. Sometimes the 'toxic' person is the only one raising real problems and the team is shooting the messenger. Sometimes they're burned out, or have an undiagnosed health issue, or are being undermined by someone else. **Getting this wrong in either direction is expensive.**
> Then I'd **follow through**, which is where most of these fail. If it improves, I'd say so explicitly and keep reinforcing. If it doesn't, I'd escalate to their manager with documented specifics and a recommendation — and I'd accept that the outcome might be that this person leaves.
> The thing I hold onto is that **keeping a brilliant jerk is a choice with a price, and the price is paid by everyone else**: the two engineers who stopped speaking up, the three who leave over a year, the ideas that never get proposed, and the standard you've set about what's tolerated. When I've seen teams make that trade consciously, they almost always decide differently than when they make it by drift. **And if management chooses to keep them anyway, that's information about the organisation that I'd take seriously.**"

### 24. "You and another senior engineer have opposite technical opinions and the team is split. Resolve it."
> "First I'd check whether it's actually a technical disagreement, because usually it isn't — it's a difference in **which risk we're more afraid of**, or in **what timeframe we're optimising for**, or in **unshared context**. 'Microservices vs modular monolith' is almost always 'I've been burned by distributed systems' vs 'I've been burned by a codebase nobody can change'. Naming that out loud resolves a surprising number of these.
> Then I'd **make the decision criteria explicit before arguing about the answer**. We'd agree, together and in writing, on what we're optimising for: delivery speed now, operational cost in 18 months, team size, hiring, the compliance regime, the expected scale. **Once the criteria are agreed, the disagreement usually narrows to two or three specific, checkable claims.** That's a tractable conversation; 'you're wrong about architecture' isn't.
> Then I'd **get evidence instead of opinions**, sized to the decision. For a big irreversible choice, a time-boxed spike or prototype answering the one question the decision hinges on — which is usually 'does this actually work at our scale / with our team / with our data?'. A day or two of measurement beats a week of debate. And I'd look for **external evidence**: what have comparable teams reported, what does the vendor's own guidance say, what are the known failure modes?
> If evidence doesn't settle it, I'd apply **reversibility**: pick the option that's cheaper to be wrong about, and set explicit exit criteria — 'we'll do X, and if in three months we see Y, we switch to Z.' That converts a fight into an experiment with a review date, and it lets the other person be right later without having been wrong now. **Which is often what the disagreement was really about.**
> Then I'd make sure the decision is **recorded** — a short ADR with the context, the options, the criteria, the decision, and the review date — and I'd **commit publicly**, including in the forums where I argued the other side. A senior person who loses an argument and then undermines the decision does more damage than the wrong decision would have.
> And the thing I've learned is that **being right isn't the goal; the team being able to execute is.** If my option wins and half the team is disengaged, we'll do it badly and I'll have been wrong in the way that matters. So I'd rather have a 70% solution the whole team owns than a 95% solution half of them resent — and I'd tell the other engineer, sincerely, that I expect them to hold me to the exit criteria if the evidence turns their way."

---

## Red flags

| Saying / doing this | Costs you |
|---|---|
| "We" for everything | The interviewer can't assess *you* |
| "I" for everything | Sounds like you can't collaborate |
| A 7-minute story with 5 minutes of context | You ran out of time before the interesting part |
| No numbers anywhere | Unverifiable, and suggests you didn't measure |
| A fake failure ("I work too hard") | Instant credibility loss |
| Blaming the other person in a conflict story | You're the risk, not them |
| Describing colleagues as incompetent or political | You'll describe the interviewer that way later |
| "I escalated to my manager" as the resolution | No influence skills demonstrated |
| A story with no learning | No growth signal |
| Answering a different question than was asked | Not listening — the most common fatal error |
| Jargon-dumping instead of explaining | Can't communicate with non-specialists |
| "I just worked nights until it was done" | No scope/risk management |
| Vague on your own contribution to a team success | Did you do it, or were you there? |
| Every story from 6 years ago | No recent growth |
| Badmouthing a previous employer | You'll badmouth this one |
| "I don't have any weaknesses/questions" | No self-awareness / no interest |
| A leadership story where you did all the work yourself | You don't multiply through others |
| Claiming credit for a decision someone else made | Reference checks exist |

## Rapid recall

**Structure:** STAR-**L** (Situation 10%, Task 10%, **Action 60%**, Result 15%, Learning 5%). 90s–3min. **"I" not "we"** (80/20). Quantify everything. Anticipate 3 follow-ups per story.

**Prepare 10 stories:** a SEV1 you led · a project you drove end-to-end · a conflict resolved · disagreeing with your manager · a real failure · mentoring someone · influencing without authority · deciding with incomplete information · saying no / killing something · improving something unasked. Plus: a migration, a cost win, a security fix, a platform adoption (and one that failed), and a time you automated away toil.

**Scoring axes:** impact/scope · ownership · influence · judgement · self-awareness · communication · collaboration · growth.

**The universal answer patterns:**
- **Conflict** → seek to understand first → **evidence, not seniority** (a prototype/data) → **concede something real** → relationship survives → measurable outcome.
- **Failure** → real consequences → **first-person ownership immediately** → systemic fix (not personal resolve) → a rule you still apply → mention business/customer impact.
- **Influence without authority** → make it **cheaper to comply than resist** → pilot with a team that has a real problem and do the work for them → **publish the numbers, not the mandate** → make it the default via a template/policy once adoption is obvious.
- **Difficult person** → behaviour + impact, never character → assume good faith → talk to them first → escalate the **system**, not the person → learning.
- **Incomplete information** → **which option is more reversible?** → spend limited time de-risking the irreversible one → run a small experiment to get the decisive fact → state explicitly what you don't know and how you'll learn it.
- **Mentoring** → ask questions instead of giving answers → pair with them driving → **scoped real ownership** → specific two-way feedback → the lesson is restraint.
- **Disagreeing upward** → data not opinion, once, privately → **commit publicly** → then **de-risk the decision** (rollback, abort criteria, staging, timing) → write up the learning without "I told you so".
- **Prioritisation** → reversibility/blast radius → who's blocked → value/effort last → **make the trade-off visible** rather than absorbing it silently.
- **Pressure** → scope/quality/time trade made **explicit**, non-negotiables kept, **deferred work written down and dated**, communicate risk early, protect the team from context-switching.
- **Tech debt** → it's debt with an interest rate → **make the interest visible** (incidents, hours, blocked features) → fold repayment into delivery (15–20%) → **stop the bleeding with CI guardrails** → manage the rate of creation.
- **Expensive/unpopular decisions** → write it down (problem, constraints, 3 options, recommendation, what would change my mind, **exit criteria**) → talk to affected people individually **before** the announcement → show the costs → commit and measure publicly.
- **Toxic brilliant engineer** → classify precisely (blunt ≠ obstructive ≠ harassment) → **specific incidents, not character** → impact in terms they care about → concrete bidirectional expectations with a 30-day review → verify your read with others → follow through → **keeping them is a choice whose price is paid by everyone else**. Harassment is not a performance conversation — escalate immediately.
- **Split technical opinion** → find the real disagreement (risk appetite / timeframe / unshared context) → **agree the decision criteria first** → evidence via a time-boxed spike → **reversibility + exit criteria** → record an ADR → commit publicly, including where you argued the other side → **team execution beats being right**.

**90-day turnaround:** listen + measure (1:1s with 3 questions, read the artifacts, **shadow an on-call shift**, baseline numbers, change nothing structural) → fix the loudest cheap thing visibly (**delete/demote non-actionable alerts**, runbooks for the top 5, weekly triage ritual, docs as a byproduct) → build the system (blameless post-mortems with completion-rate tracking, SLOs on 3–5 services, a funded reliability roadmap, golden paths, written team agreements) → **report baseline-vs-now numbers** to the team and leadership.

**Also prepare:** "tell me about yourself" (Present → Past → Future, < 2 min, end with why *this* role) · "why leaving / why us" (toward, not away; cite something specific you researched) · "3–5 years" (scope, not title; tie to the role) · salary (research, defer if you can, give an anchored range on **total comp**, know your floor and your alternatives).

→ Next: [`19-Scenario-War-Rooms`](../19-Scenario-War-Rooms/README.md)
