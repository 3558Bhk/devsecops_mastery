# Interview Prep — SDE3 · DevOps · Cloud · SRE · Platform Engineering

Real interview questions, scenario-based questions, and basic/advanced levels — **separate file per topic**.

## Files

| File | Role it prepares you for | Questions | ⏱️ Prep time |
|---|---|---|---|
| `sde3.md` | Senior Software Engineer (SDE III / L6) | ~60 | ~2 hrs |
| `devops.md` | DevOps / Infrastructure Engineer | ~60 | ~2 hrs |
| `cloud.md` | Cloud Engineer (AWS + Azure) | ~65 | ~2 hrs |
| `sre.md` | Site Reliability Engineer | ~60 | ~2 hrs |
| `platform-engineering.md` | Platform / Internal Developer Platform Engineer | ~55 | ~2 hrs |
| `case-1-basic.md` | **Terraform/IaC basics** — bullet Q&A, spaced for quick drilling | 13 Q | ~45 min |
| `case-2-general.md` | **Terraform/IaC general** — the questions mid-level interviews actually ask | 12 Q | ~1 hr |
| `case-3-scenario-based.md` | **Terraform/IaC scenarios** — "in your last project…" with step flows | 8 scenarios | ~1 hr |

## How the parts map to real interview rounds

| Part in each file | Which round asks it |
|---|---|
| **Part 1 — Basic Level** | Recruiter screen / phone screen / first on-site. Quick-fire, must be instant. |
| **Part 2 — Real Job-Specific Questions** | Technical interview round 1–2. The "real time" questions companies actually ask about your day job. |
| **Part 3 — Advanced Level** | Deep-dive / system design round. Trade-offs, scale, "what if it's 100x bigger". |
| **Part 4 — Scenario-Based (Real-Time)** | "War story" / on-call / behavioral round. No single right answer — they grade your *process*. |
| **Part 5 — Questions to ask them** | Every interview, last 5 minutes. Signals seniority. |

## How to answer scenario questions (use this framework every time)

**For incident/on-call scenarios — the "5 steps":**
1. **Stabilize first** — stop the bleeding (rollback, scale, failover, disable feature).
2. **Diagnose** — look at metrics/logs/traces, form a hypothesis, verify.
3. **Communicate** — status updates on the incident channel every 15–30 min. Who is affected? What's the ETA?
4. **Fix** — smallest change that restores service; verify with metrics.
5. **After** — postmortem (blameless), action items with owners, SLO/process change.

**For design scenarios — LACE:**
- **L**isten (parrot back what you heard)
- **A**cknowledge trade-offs out loud ("I'll optimize for latency over consistency because...")
- **C**larify (ask: scale? read/write ratio? consistency needs? team size?)
- **E**xecute (API → components → data → scale → failure modes → improvements)

**For behavioral questions — STAR:** Situation → Task → Action → Result (with a number if possible).

## How to use this pack

1. Read a file, cover the answers, **answer out loud** (record yourself on the hard ones).
2. Basic part: you should answer in < 30 seconds. If not, re-learn that concept.
3. Scenario part: say the framework out loud *before* the content — structure is half the grade.
4. Revisit the part matching your next round 1 day before the interview.

## Pair with the rest of the workspace

- Theory: `../terraform-mastery/` (Terraform + AWS + Azure, basic → advanced)
- Hands-on proof: `../terraform-hands-on/` (22 runnable projects — mention these in interviews: "I built X")
