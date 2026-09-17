# 00 · How To Use This Folder

## What the level actually means

**SDE III / Senior** is not "SDE II but knows more." It's a different job. Across the roles you're targeting:

| Role | What "senior" means in the interview |
|---|---|
| **SDE III** | Owns ambiguous problems end to end; designs systems that survive contact with reality; raises the level of engineers around them |
| **Senior SRE** | Owns reliability as a *property*, not a ticket queue; can run an incident; designs for failure; makes velocity/reliability trade-offs explicit |
| **Senior DevOps** | Owns the delivery pipeline as a product; measures flow (DORA); removes toil systematically, not one-off |
| **DevSecOps** | Embeds security controls in the pipeline so the secure path is the easy path; can reason about threat models, not just tool output |
| **Platform Engineering** | Treats internal developers as *customers*; builds golden paths; measures platform adoption and time-to-first-deploy |
| **Cloud Engineer** | Designs for cost, resilience and security together; knows the failure modes of managed services, not just their features |

The common thread: **you are evaluated on decisions under uncertainty, not recall.**

---

## The three things interviewers score

1. **Signal-to-noise in your reasoning.** Do you narrow a problem before solving it?
2. **Trade-off fluency.** Can you name the cost of your own recommendation?
3. **Ownership.** Do you say "I did X" with evidence, or "we kind of…" ?

Everything in this folder is calibrated to those three.

---

## Framework 1 — The trade-off answer

Use for every "why X instead of Y" question.

```
1. Name what X buys you.              "Kafka gives durable replay and fan-out to
                                        N consumers with independent offsets."
2. Name what X costs.                 "It costs a stateful cluster to operate —
                                        ZooKeeper/KRaft, partitions, rebalances,
                                        disk sizing, and a whole failure taxonomy."
3. State the decision rule.           "I'd take it when ≥2 consumers need replay
                                        or throughput > ~10k msg/s. Below that,
                                        SQS/SNS is a tenth of the ops burden."
4. Anchor in experience.              "We moved off Kafka to SQS for our webhook
                                        fan-out for exactly that reason and cut
                                        incident count on that path to zero."
```

**Never** answer "it depends" and stop. Answer "it depends on X, Y, and Z — here's my rule."

---

## Framework 2 — The design answer

For "design Twitter / a rate limiter / a CI system".

```
1. Clarify (3-5 questions, 2-3 min)     functional scope, non-functional priorities
2. Size it                              QPS, storage/day, read:write, peak factor
3. API surface                          3-5 endpoints with request/response
4. Data model                           entities, keys, indexes, hotspots
5. High-level boxes                     client → LB → service → cache → DB → queue
6. Walk ONE request end to end          this is where interviewers probe
7. Find the bottleneck                  state it before they ask
8. Scale that component                 shard / cache / partition / async
9. Failure modes                        what breaks, how you detect it, how it degrades
10. Ops & evolution                     observability, migration, v2 concerns
```

Time-box: 40 minutes. Spend 5 on requirements, 10 on the single-node design, 20 on scale, 5 on failures. **A correct simple design that you can defend beats a fancy one you can't.**

---

## Framework 3 — The incident answer

For "the site is down / slow / users are reporting errors".

```
1. STABILISE FIRST.  "Before I diagnose, I'd ask: is there a mitigation available
                      right now — rollback, failover, scale out, feature flag off?
                      A 2-minute rollback beats a 2-hour root cause at 3am."
2. Establish scope.  All users or some? Which region/tenant/version? When did it
                      start, and what changed at that time?
3. Check the change. "Most incidents are a change. Deploy, config, infra, dependency,
                      traffic pattern, or a certificate/expiry."
4. Look at symptoms, then causes.  Golden signals at the edge first, then resources.
5. Form 2-3 hypotheses, test the CHEAPEST one first.
6. Communicate on a clock.  Updates every 15-30 min even when there's no news.
7. Resolve, then verify with a real user path (not just green dashboards).
8. Postmortem: blameless, action items with owners and dates.
9. Systemic fix: "why did three layers of defence all miss this?"
```

**Say step 1 out loud, explicitly.** Juniors dive into diagnosis; seniors stabilise. That single sentence is the most reliable level signal in an SRE interview.

---

## Framework 4 — Behavioural (STAR-L)

```
Situation  2 sentences, set the stakes and the constraint
Task       what YOU were responsible for
Action     60% of your answer. "I" not "we". Specific: what you said, decided, built
Result     numbers. Latency, cost, incidents, adoption, time saved
Learning   what you'd do differently — this is what makes it senior
```

**Prepare exactly 8 stories** and map them to the questions in [`18-Behavioral-and-Leadership`](../18-Behavioral-and-Leadership/README.md):

1. A technically hard problem you solved (depth)
2. A disagreement with a senior person / your manager (influence)
3. A mistake you made in production (accountability)
4. A time you had to act with incomplete information (ambiguity)
5. A time you mentored someone who then grew (leadership)
6. A time you killed or simplified something (judgement)
7. A time you had to say no to a stakeholder (backbone)
8. A cross-team initiative you drove without authority (scope)

Write each in ≤ 200 words, then practise saying each in 90 seconds.

---

## How to practise with these files

| Method | How | Best for |
|---|---|---|
| **Cover-and-recall** | Hide the answer, say yours aloud, then compare | Basic tier |
| **Trade-off drill** | For every answer, force yourself to add "…and the downside is" | Advanced tier |
| **Timed whiteboard** | 40 min, no notes, one design out loud, recorded | System design |
| **Peer mock** | Someone reads questions, interrupts, asks "why?" three times | Everything |
| **Reverse teaching** | Explain a topic to a junior in 10 min with no jargon | Reveals the gaps fastest |

The **"why?" three times** drill is the most valuable one. Interviewers at this level rarely accept your first answer — they push to find where your understanding actually ends. Practise being pushed.

---

## Scoring yourself

After each topic, rate honestly:

| Score | Meaning |
|---|---|
| **3** | Answered fluently with trade-offs and a real example, unprompted |
| **2** | Knew it but needed a nudge, or gave a correct but shallow answer |
| **1** | Recognised it, couldn't produce it |
| **0** | Unknown |

Anything below 3 in the 🔵 Advanced tier is your actual study list. Don't re-read what you already know — that feels productive and isn't.

---

## The night before

Only these, in this order:

1. [`20-Rapid-Fire-One-Liners`](../20-Rapid-Fire-One-Liners/README.md) — skim, don't memorise
2. Your 8 behavioural stories, out loud, once each
3. The 4 frameworks above
4. [`21-Questions-To-Ask-Them`](../21-Questions-To-Ask-Them/README.md) — pick 4
5. Sleep. Recall degrades faster than knowledge; a tired senior answers like a junior.

---

## Red flags that cost candidates the level

| Red flag | What the interviewer hears |
|---|---|
| Jumping to a solution before clarifying | "Will build the wrong thing expensively" |
| Naming a technology without a reason | "Resume-driven development" |
| No numbers, ever | "Doesn't measure their own work" |
| Can't say what's wrong with their own design | "No self-critique → won't improve" |
| Blaming a previous team/manager | "Won't own failures here either" |
| "We" for everything | "Can't tell what YOU did" |
| Over-engineering a small problem | "Cost-blind" |
| Never asking questions | "Not curious / not evaluating us" |

---

→ Start with [`01-CS-Fundamentals`](../01-CS-Fundamentals/README.md)
