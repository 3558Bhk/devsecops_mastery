# 21 · Questions To Ask Them

**"Do you have any questions for us?" is a scored part of the interview.** Good questions do three things at once: they extract information you actually need to make the decision, they signal seniority (only experienced people ask about on-call load, action-item completion rates, and platform funding), and they start the working relationship.

**Rules of engagement:**
- **Have 6–8 prepared; ask 3–4.** Asking all of them turns the interview into a deposition.
- **Match the person.** Ask the recruiter about process and comp; the hiring manager about team and priorities; peers about the day-to-day reality; an exec about strategy and why the role exists.
- **Ask the question you genuinely don't know the answer to.** Questions whose answers you can find on the website waste the slot.
- **Take notes.** What people say in response to an uncomfortable question is the most informative part of the interview.
- **Never ask about salary/benefits to the technical interviewer** in the first round — ask the recruiter. (Exception: if a seniority mismatch is possible, clarifying the level and band early saves everyone months.)
- **Watch for non-answers.** "We're a family", "it depends on the quarter", "we don't really measure that" — those *are* answers.

---

## 1 · Questions that reveal the most (ask these first)

These five have the highest information-per-minute ratio. If you only ask three questions, ask three of these.

| Question | What a good answer sounds like | What to worry about |
|---|---|---|
| **"What does success look like in this role at 6 months and at 12 months?"** | Specific, observable outcomes — "checkout deploys go from weekly to daily", "on-call pages drop below 3 a shift", "the golden path covers 70% of services" | "Just hit your targets", or a list of projects rather than outcomes — means there's no real plan, and you'll be judged on vibes |
| **"What's the biggest problem the team has right now that isn't being solved?"** | A concrete, honest answer with the reasons it's stuck | "Nothing major" (either untrue, or they don't see their problems), or a problem that is *obviously* the role's job and they're framing it as someone else's |
| **"Why is this role open? Is it new or a backfill?"** | Growth, a new initiative, a promotion, or an honest description of a departure | High churn ("the last three people left"), or a role that's been re-posted several times. **If it's a backfill, ask what the previous person did well and what they struggled with** — extremely revealing |
| **"What would make you say, a year from now, that hiring me was a mistake?"** | A thoughtful answer about a real risk (scope, ambiguity, politics, technical debt) | Defensiveness, or a generic "if you didn't work hard". A good answer here tells you exactly what to avoid |
| **"What's the hardest thing about working here?"** | Named and specific — "the two legacy systems nobody wants to touch", "decisions get revisited often", "we're in three timezones" | "We work hard and play hard", "nothing really". **An inability to name a difficulty usually means they've normalised it** |

---

## 2 · For the hiring manager

### Scope, authority and how decisions get made
1. **"How much authority comes with this role? Can I say no to a project, or do I have to persuade someone?"** — Establishes whether you'll be an owner or an executor. For a senior role this is the single most important question.
2. **"Who do you report to, and who else reports to them?"** — Reveals the org shape and where platform/SRE/security sits relative to product. **If platform reports to a product manager, expect to be a service desk.**
3. **"Walk me through a recent significant technical decision. Who made it, and how?"** — Tells you whether decisions are made by the person doing the work, by consensus, or by the highest-paid opinion.
4. **"What happens when engineering and product disagree about scope?"** — A good answer describes an escalation path and a decision owner. A bad answer is "we always find a way".
5. **"Is there a design-review or RFC process? Can I see an example?"** — Asks for evidence rather than a claim. The quality of the artefact tells you a lot about engineering culture.
6. **"How do you handle an engineer who disagrees with a decision that's already been made?"** — Tests whether dissent survives the decision.

### Priorities and reality
7. **"What are the team's top three priorities this quarter, and what did you drop to make room for them?"** — The "what did you drop" part is the real question. A team with ten priorities has none.
8. **"What's the ratio of new features to maintenance, reliability, and platform work?"** — Get a number. Under 20% on the non-feature side usually means the platform is decaying.
9. **"How much of the team's time goes to on-call, escalations and unplanned work?"** — If they can't answer, it's a lot.
10. **"What technical debt do you know about and aren't paying down? Why?"** — Every honest manager has an answer. It also shows whether they can name and defend a trade-off.
11. **"What's the roadmap for the next 12 months, and how confident are you in it?"** — Confidence calibration reveals planning maturity.
12. **"Is this role expected to build, or to operate what's built?"** — The most common senior-level mismatch. Platform/SRE roles are often advertised as "build the platform" and turn out to be "answer tickets".

### People and management style
13. **"How do you run 1:1s, and what do they usually cover?"** — Weekly and substantive, or "as needed" and status updates.
14. **"How do you give feedback? Tell me about the last piece of critical feedback you gave someone."** — Asking for a specific instance defeats rehearsed answers.
15. **"How do you handle someone who's struggling?"** — Look for a process (clear expectations, a plan, support) rather than "we manage them out" or "we hope they improve".
16. **"How do you promote people? What did the last promotion here look like?"** — If nobody has been promoted in two years, ask why. Also: **"Is there a written promotion rubric I can see?"**
17. **"How many people report to you directly?"** — Above 8–10 means you'll get less of them; below 3 for a manager can mean a role that exists mainly to justify a title.
18. **"What do your best engineers do that others don't?"** — Reveals what's actually valued, which often differs from the stated values.
19. **"How long have you been here, and what keeps you here?"** — A manager's tenure is a strong predictor of stability. A manager who's been there 18 months with three departed reports is a warning.

---

## 3 · For peers / the team

These get you closer to the truth, because peers have less to sell.

20. **"What does a normal week look like for you?"** — The best general-purpose question. Listen for how much is meetings, tickets, firefighting versus building.
21. **"How many pages did you get on your last on-call shift, and how many needed action?"** — A number, and the ratio. **This is the single most diagnostic question in a whole interview process for SRE/platform/infra roles.**
22. **"Who's on call, how big is the rotation, and is it compensated?"** — Under 5 people, or uncompensated, or "everyone is always on call" are all real problems.
23. **"What happens when something goes wrong at 3am? Walk me through the last one."** — Reveals whether runbooks exist, whether escalation works, and whether the aftermath was blameless in practice.
24. **"How often do you deploy, and what does it take?"** — Ask for the last time *they* deployed. Twice a week by hand, or several times a day by pushing a button?
25. **"How long does it take a new engineer to make their first production change?"** — A proxy for onboarding quality and environment friction.
26. **"Can you run the whole system locally? How?"** — If not, or if it takes a day, that's a real daily cost and a sign of accumulated complexity.
27. **"What breaks most often?"** — You'll hear the same answer from three different people if it's true.
28. **"What do you use that you wish you didn't?"** — Reveals the tooling regrets, and how candid the team is.
29. **"How much of your work is defined for you versus chosen by you?"** — Autonomy, in practice.
30. **"What was the last thing the team decided not to do?"** — A team that never says no has no priorities.
31. **"How are post-mortems run, and how many of their action items actually get done?"** — **Ask for the completion rate.** Teams with real learning cultures know this number and it's high (>70%). Teams that write reports nobody acts on will hesitate.
32. **"What did the last person who left say when they left?"** — Slightly bold; extremely informative when you get an answer.
33. **"How does the team handle disagreements about technical direction?"** — Look for evidence, RFCs, and a decision owner, not seniority or volume.
34. **"What's the one thing you'd change about how this team works, if you could?"** — A safe way to hear the real complaint.
35. **"What's something you've learned here that you didn't know before?"** — Reveals whether the team is growing people or grinding them.

---

## 4 · For the SRE / DevOps / platform-specific interview

If you're interviewing for infrastructure, reliability, security, or platform roles, these are the questions that separate real practices from aspirations.

### Reliability
36. **"What are your SLOs, and where are they published?"** — If there are none, ask what determines "is this reliable enough?" The answer tells you how reliability decisions get made.
37. **"Have you ever used an error budget to stop shipping? What happened?"** — A yes with a story means the policy is real. A theoretical answer means it's decoration.
38. **"What's your availability over the last 12 months, measured how?"** — Ask how it's measured. A number without a definition is marketing.
39. **"How many SEV1 incidents did you have last year? What were the top three causes?"** — And: **"Did any of them repeat a previous cause?"** Repeats mean the action items weren't done.
40. **"What's your MTTR, and what's the biggest component of it?"** — A team that knows its MTTR decomposition is a team that's actively improving it.
41. **"How do you test your disaster recovery?"** — "We have a DR plan" is not an answer. Look for a schedule, a scope, and a last-test date with findings.
42. **"When did you last restore a backup, and how did you know it worked?"** — The most underrated question in the entire list. A surprising number of teams have never done it.
43. **"Do you run chaos experiments or game days? What did the last one find?"** — And whether the findings were fixed.
44. **"How do you handle capacity planning — is there a process, or do you react?"** — Look for quota tracking, growth modelling, and pre-emptive scaling.
45. **"What's your biggest single point of failure that you know about?"** — Candour test plus genuine information.

### Observability and operations
46. **"What's your alert volume, and how do you keep it sane?"** — Ask for a per-week number and the deletion policy.
47. **"What's your observability stack, and what do you wish it did?"** — Reveals maturity and honest limitations.
48. **"Do you have tracing? What percentage of requests, and how is it sampled?"** — No tracing at all is a significant gap for a distributed system.
49. **"How much does observability cost you, and does anyone own that?"** — Cost ownership is a maturity signal.
50. **"How do you debug something that only happens in production?"** — Look for feature flags, log-level controls, profiling, tracing, and safe read access — not "we reproduce it locally".

### Platform and developer experience
51. **"Is there a platform team, and is it product-owned or ticket-driven?"** — Ticket-driven platform teams are cost centres that fall behind.
52. **"How do teams onboard a new service? What does the golden path actually cover?"** — Ask for a concrete walkthrough.
53. **"What's the adoption of your internal platform, and how do you measure it?"** — If they can't measure adoption, they can't tell whether it's useful.
54. **"Do teams self-serve, or do they file tickets? What's the most common ticket?"** — The most common ticket is the roadmap.
55. **"How is the platform team funded, and is headcount growing?"** — A platform team that can't get headcount is a team that's expected to fail.
56. **"What's the developer satisfaction score, and when did you last measure it?"** — A team that measures DevEx takes it seriously.
57. **"Who owns the build system and CI, and how long does a typical build take?"** — Build times correlate strongly with engineering velocity and morale.

### Security and compliance
58. **"Is there a dedicated security team, or is security a shared responsibility? How is it actually done?"** — "Shared responsibility" without a team usually means nobody does it.
59. **"How do you handle vulnerabilities — what's the SLA for criticals, and do you meet it?"** — And: **"What happens when you can't meet it?"**
60. **"How do you manage secrets today?"** — Look for a secret manager, workload identity, and rotation. "Environment variables" alone is a gap.
61. **"Do you have SOC 2 / ISO 27001, and is the evidence automated or manual?"** — Manual evidence collection is a permanent tax on engineering.
62. **"What's your supply-chain security posture — signed builds, SBOMs, provenance?"** — Reveals whether they're current.
63. **"Has there been a security incident? What changed afterwards?"** — Almost every company has had one. The interesting answer is about the systemic change.

### Cloud and cost
64. **"What does the cloud bill look like, and who owns it?"** — Cost ownership with a named person is a maturity signal.
65. **"Are you multi-cloud by strategy or by acquisition?"** — Changes everything about what you'll be asked to do.
66. **"What's your biggest cloud cost driver, and are you doing anything about it?"** — Reveals both the problem and the appetite to fix it.
67. **"Is infrastructure all in code? What percentage, and what's not?"** — Honest teams know the percentage. "Mostly" is a red flag.

---

## 5 · For an executive / skip-level (director, VP, CTO)

Aim at strategy, investment, and what they actually worry about.

68. **"What are the company's two or three biggest technical risks right now?"** — An exec who can name them has a real view; one who can't is disconnected from the system.
69. **"What's the technology strategy for the next 18 months, and what would change it?"** — Look for a strategy tied to business outcomes, not a technology shopping list.
70. **"How does engineering capacity get allocated between features, reliability, security, and platform?"** — Ask for the split. If features get 90% and nobody has questioned it, that's your answer about long-term health.
71. **"What's your view on technical debt — is it a cost you manage or something to eliminate?"** — A sophisticated answer treats it as a portfolio decision. An unsophisticated one treats it as a failure.
72. **"Where does this team sit in the company's priorities, and how would I know if that changed?"** — Tells you about job security and funding honestly.
73. **"What's the biggest organisational challenge the engineering org is facing?"** — Hiring, retention, coordination, quality, speed? And what's being done about it.
74. **"How do you think about build vs buy vs assemble?"** — Especially relevant for platform roles.
75. **"What have you changed your mind about in the last year?"** — A superb question. Leaders who have changed their mind recently are learning; those who haven't are calcifying.
76. **"How do you measure whether engineering is healthy?"** — DORA, DevEx, incident metrics, delivery predictability — or headcount and lines of code. Reveals the whole management philosophy.
77. **"If I join and the business has a bad quarter, what happens to platform/reliability investment?"** — A direct question about whether your work is durable. Honest answers are valuable even when they're uncomfortable.
78. **"What do you need from someone in this role that you're not getting today?"** — Reframes the role as a gap they're feeling. Very useful for understanding the real expectation.

---

## 6 · For the recruiter / HR

79. **"What's the interview process from here, how many rounds, and who will I meet?"** — Ask for names and roles; you can research them.
80. **"What's the level for this role, and what's the compensation band?"** — In many jurisdictions they're legally required to disclose. **Asking early prevents months of wasted time on a level mismatch.**
81. **"What's the total compensation structure — base, bonus, equity, and how does equity vest?"** — Ask for the equity as a percentage of the company *and* the current valuation basis. Ask about refresh grants and whether there are any.
82. **"Is there a sign-on bonus or relocation support?"** — Often available and rarely offered proactively.
83. **"What's the promotion cadence, and can I see the level rubric?"** — Companies with public rubrics are usually well-run.
84. **"What's the performance review process, and how often?"** — Semiannual or annual; calibration-based or manager-only.
85. **"What's the remote/hybrid policy in writing, and does it apply to this team?"** — Get it in writing. "Flexible" means nothing until you have an email.
86. **"What's the attrition rate for this team, and for the company?"** — They may not answer precisely; the hesitation is informative.
87. **"What's the on-call expectation and compensation?"** — Some companies pay, some give time off in lieu, some do neither.
88. **"What's the notice period, and is there a non-compete or IP-assignment clause I should review?"** — Read the IP assignment carefully if you have side projects; ask for it before signing.
89. **"How quickly do you typically make a decision, and when will I hear back?"** — Sets an expectation you can hold them to.
90. **"Is this role backfilling someone, and can you tell me about the transition?"** — Recruiters are sometimes more candid than hiring managers about churn.

---

## 7 · Questions that reveal red flags (ask them when you're suspicious)

These are diagnostic. Ask them when an earlier answer felt evasive.

| If you suspect... | Ask |
|---|---|
| **Churn** | "How long has the average person on this team been here?" / "How many people have left this team in the last year, and where did they go?" |
| **Crunch** | "What were your working hours like during the last big launch?" / "When was the last weekend anyone worked, and why?" |
| **Unfunded mandates** | "What headcount does this team have approved for the next year?" / "When did you last hire, and how long did it take?" |
| **A disempowered role** | "What's the last thing this team decided that leadership disagreed with, and what happened?" |
| **No reliability practice** | "When was the last SEV1, and how long did it take to detect?" — a team with real practice knows both numbers instantly |
| **Blame culture** | "Tell me about a mistake someone made recently. What happened afterwards?" — listen for whether the person's name comes up and how it's said |
| **Vague tech** | "Can you describe your production architecture in a few sentences?" — inability to do this coherently is a serious signal |
| **The role isn't what it seems** | "What percentage of this role is building new things versus operating and supporting what exists?" |
| **A struggling product** | "How has the customer/user count changed in the last 12 months?" / "What's the biggest competitive threat?" |
| **Runway risk (startup)** | "What's the runway, and what milestone gets you to the next round?" — legitimate and expected at a startup |

---

## 8 · Questions to avoid (and better replacements)

| Don't ask | Why | Ask instead |
|---|---|---|
| "What does your company do?" | You should already know — it reads as unprepared | "How does this team's work connect to the company's main revenue driver?" |
| "How fast can I be promoted?" | Signals you're not interested in the job you're interviewing for | "What does growth look like in this role, and what did the last promotion here involve?" |
| "Do you work hard?" | Vague, and invites a rehearsed answer | "What does a typical week look like, including hours during a launch?" |
| "What's the culture like?" | Everyone says "great" | Ask for specifics: "How do post-mortems run here?" / "What did the last team offsite involve?" |
| "Can I work from home?" (first round, to a technical interviewer) | Frames you as negotiating before contributing | Ask the recruiter about the written policy |
| Anything easily found on their website or blog | Wastes your limited slot | Ask about the *implications* of what you read |
| "Did I do well in this interview?" | Puts them in an awkward position | "Is there anything about my background you'd like me to clarify or expand on?" |

---

## 9 · The closing sequence (how to end the interview well)

The last two minutes shape the impression more than most candidates realise.

1. **Ask your prepared questions** (3–4, matched to the person).
2. **Close the loop on any weak moment:** *"Earlier I described X — I want to add that in the follow-up we also did Y, which I think is the more relevant part."* Recovering a fumbled answer is a real skill and it works.
3. **Ask directly:** *"Is there anything about my experience that makes you hesitant? I'd like to address it now."* Bold, but it surfaces objections you can actually answer, and it signals confidence. About half the time you get a real concern — and addressing it changes outcomes.
4. **Signal genuine interest, specifically:** *"The part that interests me most is X, because I did something similar at Y and I'd like to go deeper on it here."* Generic enthusiasm is worthless; specific enthusiasm is memorable.
5. **Ask about the process:** *"What are the next steps and when should I expect to hear?"*
6. **Send a short follow-up within 24 hours** — two or three sentences, referencing something specific discussed, and adding one thing you thought of afterwards. Almost nobody does this. It works.

---

## 10 · Evaluating their answers

Collect evidence across rounds; don't decide from one conversation.

### Signals of a healthy engineering organisation
- **Specific numbers** offered unprompted: pages per shift, deploy frequency, MTTR, action-item completion, cost, adoption percentages. Teams with real practice know their numbers.
- **Candidly naming a problem** without being asked, and describing what's being done about it.
- **Written artefacts** they can share: RFCs, design docs, post-mortems, runbooks, level rubrics, an SLO dashboard.
- **A blameless post-mortem culture that's actually practised** — verified by asking what happened after a recent mistake.
- **Engineers who disagree openly in front of each other** (in a panel or team round) — that's psychological safety, not dysfunction.
- **A platform/reliability function with headcount and a roadmap**, not a hero.
- **People who've been there 3+ years and are still enthusiastic.**
- **The manager can describe what their reports are working on** — without checking notes.
- **They ask you hard questions.** A rigorous process usually means rigorous engineering.

### Signals to worry about
- **No numbers for anything**, or numbers that change between interviewers.
- **"We're like a family"** — usually precedes boundary problems, unpaid overtime, and guilt-based management.
- **"We wear many hats"** — sometimes healthy at an early startup; often means understaffing and no ownership.
- **"Move fast and break things"** applied to production systems without a reliability function.
- **A role described as both a builder and a 24/7 operator, with one person's salary.**
- **Nobody can explain how decisions get made**, or the answer is "the CEO decides".
- **The interviewer can't describe the architecture** they'd have you operate.
- **Repeatedly re-posted reqs, or three people who left in a year.**
- **Reluctance to let you talk to peers** without a manager present.
- **A long process with slow, uncommunicative scheduling** — that's a preview of how they work.
- **Pressure to decide quickly without letting you meet the team.** Occasionally real (a competing offer), often a manipulation. Ask for the reason.
- **Answers that contradict between rounds.** Note them; ask the third person the same question.

### The scoring sheet

Fill this in the day of the final round, before you get an offer — you'll be far more honest then than afterwards.

| Dimension | Evidence | Score (1–5) |
|---|---|---|
| Will I work on problems I find meaningful? | | |
| Will I learn / grow here? (What will I be better at in 2 years?) | | |
| Are the people I'd work with strong, and do I want to work with them? | | |
| Is my manager someone I'd want to work for? (feedback, delegation, credibility) | | |
| Is the on-call / operational load sustainable? | | |
| Is the role scoped so I can succeed — authority matching responsibility? | | |
| Is the company financially and strategically viable? | | |
| Is the compensation fair for the level and market? | | |
| Do I trust what I was told? (consistency across rounds) | | |
| Would I recommend a friend apply? | | |

**The last row is the useful one.** If you'd hesitate to recommend a friend apply, that hesitation is data — write down why, and decide whether the reason is something you personally can live with. Sometimes it's fine (a hard problem, a demanding standard); sometimes it's the thing that will make you miserable.

---

## 11 · Negotiation notes (because you'll need them)

Not strictly a "question to ask", but the moment right after the offer is when these matter.

- **Never accept in the call.** "Thank you — I'm excited. Can I have this in writing and a few days to review?" This is standard and expected.
- **Get the number first, then talk.** Revealing your expectation before they reveal their band costs you. Ask: *"What's the band for this level?"*
- **Negotiate on total compensation and level, not just base.** Level affects everything: equity, bonus percentage, promotion timeline, and scope. **A higher level at a lower base is usually the better deal.**
- **Have a written competing offer if you can** — but don't invent one. If you don't have one, negotiate from scope and market data instead.
- **Ask for what's real**: base, equity (and the valuation basis + refresh policy), signing bonus, level, start date, remote arrangement in writing, and any specific commitment (e.g. "a second platform engineer in Q2") — **get commitments in the offer email, not in a conversation.**
- **Know your walk-away number before you start.** Deciding under the influence of an offer and excitement produces bad decisions.
- **Remember the asymmetry**: they've spent weeks and chosen you. Your leverage is highest at exactly the moment you feel least entitled to use it. A reasonable, well-evidenced counter almost never costs an offer.

---

## Red flags (in how you ask)

| Doing this | Costs you |
|---|---|
| "No questions" | Reads as low interest or low curiosity — and forfeits real information |
| Asking only about compensation/benefits to a technical interviewer | Signals misplaced priorities for the round |
| Asking things answered on their website | Signals you didn't prepare |
| Asking 10 questions and running over time | Signals poor judgement about other people's time |
| Aggressive or gotcha framing | Curiosity reads as strength; hostility reads as a colleague problem |
| Asking nothing about the actual work | The biggest missed opportunity |
| Not taking notes | You'll forget the contradictions between rounds, which are the most valuable data |
| Not following up in writing | Leaves the process, and your own recall, to chance |

## Rapid recall

**The five highest-value questions:**
1. **"What does success look like at 6 and 12 months?"** — reveals whether there's a plan.
2. **"What's the biggest unsolved problem the team has?"** — reveals candour and reality.
3. **"Why is this role open — new or backfill?"** — reveals churn and expectations.
4. **"What would make you say hiring me was a mistake?"** — reveals the real risk they're worried about.
5. **"What's the hardest thing about working here?"** — reveals what they've normalised.

**For infra/SRE/platform roles, add these three:**
- **"How many pages did your last on-call shift produce, and how many needed action?"** — the single most diagnostic question.
- **"When did you last restore a backup, and how did you know it worked?"** — separates practice from policy.
- **"What percentage of post-mortem action items get completed?"** — separates learning from reporting.

**Match the person:** recruiter → process, level, band, benefits, policy in writing. Manager → scope, authority, priorities, what was dropped, how decisions are made, promotion history. Peers → a normal week, on-call reality, deploy friction, what breaks, what they'd change. Exec → technical risk, capacity allocation, technical-debt philosophy, what they changed their mind about.

**The strongest red-flag detectors:** no numbers for anything; "we're a family"; three departures in a year; nobody can describe the architecture; a role that's both builder and 24/7 operator; contradictions between rounds; reluctance to let you meet peers alone.

**Close well:** address a weak moment explicitly → ask "is there anything that makes you hesitant?" → give *specific* enthusiasm → ask about next steps → **follow up in writing within 24 hours.**

**Then, before you have an offer:** fill in the scoring sheet, especially *"would I recommend a friend apply?"* — and write down why if the answer is anything less than an immediate yes.

---

← Back to the [`README` index](../README.md) · Start over at [`00-How-To-Use`](../00-How-To-Use/README.md)

**Good luck. Go in prepared, be curious, name the trade-offs, and remember: you're evaluating them too.**
