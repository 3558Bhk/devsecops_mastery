# Behavioral & Leadership - SDE3

## STAR Method (Must Use)

- **S**ituation: Context, 1-2 lines
- **T**ask: Your responsibility
- **A**ction: What you did (focus here, use I not we, but credit team)
- **R**esult: Impact with numbers

Example structure for all answers.

## Common Behavioral Questions & Sample Answers

### 1. Tell me about yourself (2 min pitch)

```
"I'm a Software Engineer with 4+ years experience building scalable backend systems.
Currently at [Company] as SDE2, working on e-commerce platform handling 10k RPS, microservices in Java Spring Boot + Node.js, AWS EKS, Kafka.
Key achievements:
- Led migration from monolith to microservices reducing deployment time 70% and improving availability from 99.5% to 99.95%
- Designed notification system handling 5M notifications/day with 99.9% delivery
- Mentored 3 juniors, improved team velocity 30%
Tech stack: Java 17, Spring Boot 3, Node 20, K8s, Kafka, PG, Redis, AWS.
Looking for SDE3 role to own larger systems, drive architecture, mentor more, impact bigger.
Outside work, I contribute to open source and write tech blogs."
```

### 2. Challenging bug / Incident

**Q: Tell about a challenging bug you solved**

```
S: Prod outage, P99 latency spiked from 200ms to 5 sec, error rate 20% during peak sale, payment service down.
T: I was on-call, need to mitigate and find root cause.
A:
- Checked dashboards: DB CPU 100%, slow queries, connection pool exhausted
- Checked logs: Many "Too many connections" and deadlock errors
- Recent deployment? Yes, new feature added N+1 query in order service fetching user for each order in loop
- Mitigated: Scaled DB read replica, increased connection pool temporarily, rolled back deployment via Argo Rollouts
- Root cause: N+1 + missing index on user_id, plus connection leak not closing in finally
- Fixed: JOIN FETCH + index + try-with-resources + added integration test with Testcontainers to catch N+1
- Added: Slow query alerting, connection pool metrics, PR template checklist for N+1
R: MTTR 30 min, latency back to 200ms, error 0.1%, prevented recurrence, shared post-mortem blameless, action items completed.
```

### 3. Conflict with teammate / product

**Q: Conflict with product manager or teammate**

```
S: Product wanted to release feature in 1 week that I estimated 3 weeks due to need for SAGA pattern for distributed transaction, risk of data inconsistency if rushed.
T: Need to balance business urgency and technical risk.
A:
- Listened to product urgency: Competitor launching, business impact $X
- Explained technical risk with data: Without SAGA, 5% orders may have inconsistency, support tickets, revenue loss, showed past incident
- Proposed alternatives: Phase 1 with simpler solution but with manual reconciliation job + feature flag for limited users (10%), Phase 2 full SAGA next sprint, or add 2 engineers to parallelize
- Data driven: Created design doc with options, pros/cons, timeline, risk matrix
- Aligned with engineering manager for support
- Collaborated: Daily sync with product, transparent progress
R: Agreed on phased approach, released Phase 1 to 10% users in 1 week with monitoring, no major issues, Phase 2 in 2 weeks full rollout, product happy, tech debt managed, trust built.
Lesson: Communication + data + alternatives not just saying no.
```

### 4. Leadership / Mentoring

**Q: How do you mentor juniors?**

```
- Code reviews: Not just LGTM, explain why, suggest alternatives, share articles, focus on learning not criticizing
- Pair programming: Weekly 1 hour with each junior on complex task
- Design docs: Involve them in HLD, ask them to write LLD for small feature and review
- Goals: Set clear growth goals, e.g. "In 3 months own notification service end-to-end"
- Knowledge sharing: Bi-weekly tech talks (I gave talk on Kafka, they gave on Redis)
- Result: 2 juniors promoted from SDE1 to SDE2 in 1 year, team velocity improved, I learned leadership and delegation
```

### 5. Failure / Mistake

**Q: Tell about a failure**

```
S: I deployed config change to prod without testing in staging, caused 30 min downtime for 10% users, missed to update feature flag.
T: Fix and prevent recurrence.
A:
- Immediately rolled back config via GitOps revert
- Apologized to team, took ownership, no blame
- Wrote post-mortem: Root cause - bypassed CI pipeline manually, no peer review for config
- Action items: Made config changes via PR mandatory, added validation in pipeline, added pre-prod env that mirrors prod, added checklist
- Shared learning in team meeting
R: No similar incident after, improved process, showed accountability and learning from failure. Interviewers want to see ownership and growth not perfection.
```

### 6. Why SDE3? Why this company?

```
"As SDE2 I owned services, but SDE3 is about owning systems, cross-team impact, architecture decisions, mentoring. I've been doing that informally - led migration, mentored, drove design docs. Want formal SDE3 role to have bigger scope.
Why [Company]? I admire [Company]'s scale [e.g. handling 1M RPS, 100M users], tech challenges [e.g. real-time, low latency], culture [e.g. ownership, customer obsession, engineering excellence], and I can contribute with my experience in [relevant stack]. Also growth opportunities."
```

### 7. Disagreement with manager / tech decision

- Similar to conflict, show data, propose alternatives, respectful, align on goals, escalate via design doc if needed, disagree and commit once decision made

### 8. Tight deadline / Pressure

- Prioritize: Must-have vs nice-to-have, MVP, negotiate scope not quality, communicate early if at risk, ask for help, manage time, avoid burnout, automate

### 9. Ownership / Going beyond

- Example: Not just assigned task but improved monitoring, fixed flaky tests, improved docs, on-call improvements, cost optimization saving $X

## Leadership Principles (Amazon style but useful for all)

- **Customer Obsession**: Start with customer need
- **Ownership**: Never say "not my job", take responsibility end-to-end
- **Invent and Simplify**: Innovate + simple
- **Are Right, A Lot**: Good judgment, data driven
- **Learn and Be Curious**: Never stop learning
- **Hire and Develop the Best**: Mentoring, bar raising
- **Insist on Highest Standards**: Code review, design, testing
- **Think Big**: Scale, long term
- **Bias for Action**: Calculated risk, not analysis paralysis
- **Frugality**: Cost optimization
- **Earn Trust**: Honest, transparent
- **Dive Deep**: Details matter, don't just delegate
- **Have Backbone; Disagree and Commit**: Respectful challenge, then commit
- **Deliver Results**: Impact with numbers

- Prepare 2 stories per principle with STAR

## Questions to Ask Interviewer (At end)

- What does SDE3 own vs SDE2 in your org?
- How is on-call and error budget handled?
- Biggest tech challenge team facing now?
- How does team handle tech debt vs features?
- Growth path SDE3 -> Staff?
- Team culture, how decisions made?

- Don't ask: Salary in first round, work-life balance directly (ask "how does team handle tight deadlines"), negative about company

## Do's and Don'ts

Do:
- Use STAR
- Quantify impact: Reduced latency 70%, saved $50k/year, handled 10k RPS
- Show ownership, collaboration, learning
- Be honest about failure and learning
- Credit team but highlight your role

Don't:
- Blame others
- Say "we" only, use "I" for actions
- Negative about previous company
- Lie, interviewers cross-question deep
- Be too humble, showcase impact
