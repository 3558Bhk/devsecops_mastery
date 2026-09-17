# 🔒🤖 CONTINUOUS DELIVERY vs CONTINUOUS DEPLOYMENT
### The distinction most people state backwards, the decision framework, and the five prerequisites that decide whether Case 2 is safe for you.

> ⭐ **If you read one file in Scenario 2, read this one.** The tool files are *how*. This file is *which* — and getting *which* wrong is the expensive mistake.

---

## 📇 Contents

| § | What |
|---|---|
| [1](#1--the-definitions-stated-precisely) | ⭐ The definitions, stated precisely |
| [2](#2--the-three-sentences-that-settle-it) | The three sentences that settle it |
| [3](#3---the-six-mistakes-everyone-makes) | ⭐ The six mistakes everyone makes |
| [4](#4--what-actually-differs-in-the-pipeline) | What actually differs in the pipeline — one block |
| [5](#5---the-decision-framework--nine-questions) | ⭐⭐ The decision framework — nine questions |
| [6](#6---the-five-prerequisites-for-case-2) | ⭐⭐ The five prerequisites for Case 2 |
| [7](#7--the-four-middle-grounds) | The four middle grounds (most teams actually want one of these) |
| [8](#8--per-app-shape--which-case-fits) | Per app shape — which case fits |
| [9](#9---how-to-move-from-case-1-to-case-2-without-a-big-bang) | ⭐ How to move from Case 1 to Case 2 without a big bang |
| [10](#10--the-economics) | The economics — what each case actually costs |
| [11](#11---tasks--answers-at-the-end) | Tasks and answers — **answers at the END** |

---

## 1 · The definitions, stated precisely

### 🔒 Continuous **Delivery** — Case 1

> **Every change that passes CI is *deployable to production*, and a human decides when to deploy it.**

Two halves, both essential:

| Half | What it means | What breaks it |
|---|---|---|
| ⭐ **"deployable"** | the artifact has been proven against production-*like* conditions: real image, real config shape, real migrations validated | a pipeline that only builds and never deploys to anything |
| ⭐ **"a human decides when"** | there is an explicit, audited approval gate before production | an automated trigger on `main` |

**The property you are buying:** *at any moment, you can ship.* Release is a **business decision** ("ship before the sale", "not during the freeze"), not a technical one.

### 🤖 Continuous **Deployment** — Case 2

> **Every change that passes CI *and* the automated promotion gates goes to production, with no human in the path.**

| Half | What it means |
|---|---|
| ⭐ **"passes the automated promotion gates"** | the judgement a human used to apply is now **encoded as checks**: smoke tests, error-rate thresholds, canary analysis |
| ⭐ **"no human in the path"** | nobody clicks anything. A green pipeline *is* the release |

**The property you are buying:** *lead time collapses.* A bug fix can be in production in minutes, at 3 a.m., without waking anyone.

### ⭐⭐ The sentence that separates them

```
DELIVERY:   the pipeline produces something a human MAY deploy.
DEPLOYMENT: the pipeline produces something that WILL be deployed.

   ⭐ In Delivery, "green" is a PREREQUISITE for release.
   ⭐ In Deployment, "green" IS the release.
```

---

## 2 · The three sentences that settle it

If you remember nothing else:

> **1.** Delivery means **always able** to deploy. Deployment means **always deploying**.
>
> **2.** The only structural difference is **who approves production** — a person, or a set of automated checks.
>
> **3.** ⭐ **Case 2 is not a more advanced Case 1. It is Case 1 with the human's judgement replaced by machinery — and the machinery has to exist before you remove the human.**

That third sentence is the whole discipline. Teams that automate the approval *before* building the gates have not adopted Continuous Deployment; they have adopted **unattended deployment**, which is the same thing minus the safety.

---

## 3 · ⭐ The six mistakes everyone makes

### Mistake 1 — "We deploy every day, so we do Continuous Deployment"

⛔ **No.** Deploying frequently is a *result*. Continuous Deployment is a *property of the pipeline*: no human in the path from green CI to production. If a person clicks "Approve" twenty times a day, you have **Continuous Delivery with a fast human**.

⭐ Why the distinction is not pedantry: the two have **completely different failure modes**. Fast-human Delivery fails when the human is asleep, on leave, or wrong. Case 2 fails when the gates are wrong — and it fails **at machine speed**, which is much faster.

### Mistake 2 — "Continuous Deployment means we deploy continuously"

⛔ It means *every qualifying change* deploys. On a team shipping twice a week, Case 2 deploys twice a week. **The cadence follows the commits, not the other way round.**

### Mistake 3 — Treating the gate as the only difference

⛔ Removing an approval step from a Delivery pipeline does not produce a Deployment pipeline. It produces a Delivery pipeline with no gate.

⭐ The real work of Case 2 is **everything the human was implicitly doing**: "does this look safe?", "is anyone else mid-release?", "are the metrics normal right now?", "if this breaks, can we get back?" Each of those has to become a check, a lock, a threshold, and an automated rollback.

### Mistake 4 — "Case 2 is the goal, so we should aim for it"

⛔ **Neither case is the goal.** The goal is *short, safe lead time from commit to production*. Case 2 is one way to get it. So is Case 1 with a five-minute approval.

⭐ **Counter-example that is very common and completely fine:** a team with an on-call rotation, good tests and solid observability, where a human approves production releases in under two minutes during working hours. That team has near-Case-2 lead time at Case-1 risk. Automating the approval would buy them almost nothing and cost them the gates' maintenance.

### Mistake 5 — Automating production before staging is automated

⭐ The correct order is **always**: automate dev → automate staging → *then* consider automating production. Staging is where you learn what your gates need to catch, at zero user cost. Teams that skip it discover their smoke tests do not work **in production**.

### Mistake 6 — No rollback, because "the pipeline is green"

⛔ The single most common Case 2 incident. Green means *the checks passed*, not *the release is good*. Checks are samples of reality.

⭐ **Case 2 without automated rollback is strictly worse than Case 1**, because a human watching a release often notices the thing the checks missed. If you automate the approval, you must automate the recovery too.

---

## 4 · What actually differs in the pipeline

⭐ **One block.** Everything else is identical.

```yaml
# 🔒 CASE 1 — CONTINUOUS DELIVERY
stages:
  - deploy-dev            # automatic
  - deploy-staging        # automatic
  - approval              # ⛔ STOPS HERE AND WAITS FOR A HUMAN
  - deploy-production     # runs only after the human says yes
  - verify-production     # smoke tests — informational, a human reads them

# 🤖 CASE 2 — CONTINUOUS DEPLOYMENT
stages:
  - deploy-dev            # automatic
  - deploy-staging        # automatic
  - verify-staging        # ⭐ MUST PASS — it is now a gate, not a report
  - deploy-canary         # ⭐ 5–10% of traffic
  - analyse-canary        # ⭐ error rate / latency / saturation, N minutes
  - deploy-production     # automatic, progressive
  - verify-production     # ⭐ MUST PASS
  - rollback-on-failure   # ⭐⭐ AUTOMATIC — this is what replaces the human
```

| Line | Case 1 | Case 2 |
|---|---|---|
| Who moves staging → production | a human | `verify-staging` + `analyse-canary` |
| What a failed smoke test does | informs a human | ⭐ **blocks and rolls back** |
| Is canary required? | nice to have | ⭐ **effectively mandatory** |
| Is automatic rollback required? | no | ⭐⭐ **mandatory** |
| Concurrency control | the human is the lock | ⭐ an explicit `lock` / concurrency group |

---

## 5 · ⭐⭐ The decision framework — nine questions

Answer honestly. **Any single "No" in the first five means Case 1.**

| # | Question | No → |
|---|---|---|
| **1** | ⭐ Can you deploy to production **and roll back** in under ~15 minutes, today, without heroics? | 🔒 Case 1 |
| **2** | ⭐ Do your automated tests catch the **majority** of the defects that currently reach staging? | 🔒 Case 1 |
| **3** | ⭐ Can you detect a production regression from **metrics alone**, within ~5 minutes, without a user telling you? | 🔒 Case 1 |
| **4** | Is every deployable artifact identified by an **immutable digest**? | 🔒 Case 1 |
| **5** | Are **database migrations** decoupled from deploys (expand/contract, backward-compatible, reversible)? | 🔒 Case 1 |
| **6** | Do you deploy at least weekly today? | Case 2 buys you little |
| **7** | Is your release risk **low** — no regulated sign-off, no batch-window constraint? | 🔒 Case 1 |
| **8** | Do you have **progressive delivery** (canary or blue-green) rather than a single big-bang rollout? | Case 2 amplifies blast radius |
| **9** | Is there **one owner** for the promotion gates, who maintains them? | the gates will rot |

### ⭐ The scoring, stated plainly

| Result | Recommendation |
|---|---|
| All five mandatory "Yes" | Case 2 is **available** to you. Questions 6–9 decide whether it is **worth** it |
| Any mandatory "No" | 🔒 **Case 1**, and fix the "No" — that work is valuable regardless of which case you end up in |
| Deploy rarely, or high release risk | 🔒 **Case 1** is not a compromise; it is the correct design |
| Everything green but nobody maintains the gates | 🔒 **Case 1** — an unmaintained automated gate is worse than a human |

⭐⭐ **The meta-point:** questions 1–5 are *the work*. If you answer "No" to any of them, the fix improves your delivery whether or not you ever automate the approval. **Case 2 is a by-product of doing that work, not a project you undertake.**

---

## 6 · ⭐⭐ The five prerequisites for Case 2

These are questions 1–5, expanded. Each one is a real system, not a checkbox.

### Prerequisite 1 — Fast, boring, reversible deploys

| Requirement | Why |
|---|---|
| ⭐ Deploy **and** rollback in < 15 min | Case 2 will deploy something bad eventually. Recovery speed is the only thing that limits the damage |
| Rolling or progressive, never recreate | recreate = a guaranteed outage window on every deploy |
| ⭐ **Rollback is a first-class, tested action** | if you have never rolled back in production, you do not have a rollback plan |
| Readiness probes that actually gate traffic | without them, requests hit pods that cannot serve them |
| Warmup awareness | ⭐ JVM apps, connection pools, JIT, caches — the first 60 s are the slowest |

**Test it:** roll back production, deliberately, right now, in a quiet window. If that is terrifying, you are not ready — and the terror is accurate information.

### Prerequisite 2 — Tests that catch what matters

| Requirement | Why |
|---|---|
| ⭐ Integration tests against **real** infrastructure (Testcontainers, not H2) | unit tests do not catch contract or migration failures |
| ⭐ Smoke tests that run **in the target environment** post-deploy | the only thing that proves *this* deploy works *there* |
| Deterministic — **zero flaky tests** | ⭐⭐ a flaky gate trains everyone to ignore it, then to disable it |
| Fast enough that people do not work around them | > 15 min and developers batch changes, which defeats the purpose |

⭐ **The flakiness rule:** in Case 2, a test that fails 2% of the time is not a minor annoyance — it is a mechanism that **randomly blocks or randomly passes** your releases. Fix or delete flaky tests *before* automating promotion.

### Prerequisite 3 — Observability that can say "this is worse"

| Requirement | Why |
|---|---|
| ⭐ **Golden signals** per service: rate, errors, latency, saturation | the analysis step compares these before/after |
| A **baseline** — what normal looks like at this hour, this day | ⭐ without it, thresholds are guesses, and Monday-morning traffic looks like an incident |
| **Error budget** or SLO, written down | the numeric threshold the gate uses |
| ⭐ Alerting that fires in < 5 min | Case 2's canary window is typically 5–15 min |
| Traces for the cross-service case | a canary can look fine at the edge and be broken downstream |

⭐⭐ **The subtle one:** your metrics need enough **volume** to be statistically meaningful inside the canary window. A service handling 3 requests/minute cannot be canary-analysed in 10 minutes — there is no signal. For low-traffic services, Case 2's automated analysis is not weaker, it is **meaningless**. Use Case 1, or extend the window.

### Prerequisite 4 — Immutable artifacts, referenced by digest

| Requirement | Why |
|---|---|
| ⭐ Deploy by `@sha256:`, never by tag | a tag can be re-pushed; a digest cannot. Without this you cannot answer "what is running?" |
| The **same** digest flows dev → staging → prod | if prod builds separately, you are testing a different artifact than you ship |
| Config supplied at **runtime**, not build time | ⭐ the frontend trap — [Scenario 1 · shape A §2.3](../scenario-1-ci-only/04-app-shapes-fe-be-fullstack.md) |
| Rollback = re-point at the **previous digest** | one command, no rebuild, no "what was the last good version?" |

### Prerequisite 5 — Decoupled, backward-compatible data changes

| Requirement | Why |
|---|---|
| ⭐⭐ **Expand / contract** migrations | the new code must run against the **old** schema and vice versa |
| Migration runs **before** the rollout, as a gated Job | so a failure stops the pipeline instead of leaving a half-migrated fleet |
| No destructive change in the same release as the code that needs it | ⛔ otherwise rollback breaks the database |
| ⭐ Rollback tested **with** the migration applied | the common surprise: the image rolls back fine, the code cannot read the new schema |

```
✅ ROLLBACK-SAFE MIGRATION
   release N   : add column `quantity_new`, dual-write, keep `qty`
   release N+1 : read `quantity_new`, stop writing `qty`
   release N+2 : drop `qty`          ← ⭐ only after N+1 is stable
   ⭐ releases N and N+1 are BOTH rollback-safe.

⛔ NOT ROLLBACK-SAFE
   one release: rename `qty` → `quantity`
   ⭐ rolling back the image leaves code expecting `qty` against a schema
     that has `quantity`. You cannot roll back. You can only roll FORWARD.
```

---

## 7 · The four middle grounds

⭐ **Most teams do not want Case 1 or Case 2. They want one of these.** All are legitimate, and all are more honest than claiming Case 2 you do not have.

| Pattern | How | Use when |
|---|---|---|
| **1. Auto-deploy below production** | dev and staging promote automatically; production has a human gate | ⭐ **the right starting point for almost everyone.** You learn what your gates need to catch at zero user cost |
| **2. Time-boxed auto-approval** | production auto-deploys *during business hours*; a human approves out of hours | you want Case 2's speed but a human awake to notice |
| **3. Progressive + auto-halt** | ⭐ canary deploys automatically, then **pauses**; full rollout needs a click | Case 2's blast-radius control with Case 1's decision point. **Excellent compromise** |
| **4. Auto-deploy with a kill switch** | fully automatic, but one command reverts to the previous digest | you have prerequisites 1, 3 and 4 but not full confidence in 2 |

⭐⭐ **Pattern 3 is underrated.** It gives you the *learning* — the canary runs, real traffic hits it, you see whether your analysis would have caught a problem — while keeping a human at the only point where a mistake is expensive. Many teams run pattern 3 for a year and then find that removing the click was trivial, because the analysis had already been proven.

---

## 8 · Per app shape — which case fits

| Shape | App | ⭐ Recommendation | Why |
|---|---|---|---|
| 🔵 **FE only** | `shop-ui` | Case 2 **is easy here** | no state, no schema, instant rollback. The risk is browser caching, not the server — set `index.html` to `no-cache` and it is genuinely low-risk |
| 🟢 **BE, stateless** | `payment-mock`, `checkout` | ⭐ **Case 2 — start here** | lowest deploy risk in the estate. Prove your canary machinery where being wrong costs nothing |
| 🟢 **BE, stateful** | `shop-api` (Postgres) | 🔒 **Case 1** until migrations are expand/contract | the schema is the thing you cannot roll back |
| 🟢 **BE, worker** | `order-worker` | 🔒 Case 1, or pattern 4 | in-flight messages, no HTTP health endpoint, harder to canary |
| 🟡 **FE + BE** | P10 | ⭐ **Split them**: FE → Case 2, BE → Case 1 | they have different risk profiles. Coupling them forces you to the slower of the two |
| 🟠 **Polyglot** | P11, P12 | per-service, using the rows above | ⭐ the whole point of per-service pipelines |
| 🗄️ **Data tier** | P13 | 🔒 **Case 1, always** | ⭐⭐ databases are stateful, and a bad data deploy is not reversible. No mature team auto-deploys a schema change to production unattended |

⭐⭐ **The row that matters most:** *FE + BE → split them.* Teams that run one pipeline for the whole app are forced to apply their **highest**-risk service's policy to their **lowest**-risk one. That is how a static-file frontend ends up needing a change-approval board.

---

## 9 · ⭐ How to move from Case 1 to Case 2 without a big bang

**Do not flip a switch.** Sequence it:

```
STAGE 0 · TODAY                human approves dev, staging AND production
        │
STAGE 1 · automate dev         human approves staging + production
        │                      ⭐ learn: does the deploy step even work unattended?
STAGE 2 · automate staging     human approves production ONLY
        │                      ⭐ learn: what do the smoke tests miss?
STAGE 3 · add the gates        production still human-approved, but the
        │                      gates RUN and REPORT alongside the human
        │                      ⭐⭐ the key stage: you collect evidence that
        │                         the gate agrees with the human, for weeks
STAGE 4 · canary + auto-halt   pattern 3 — the canary is automatic, the
        │                      full rollout needs a click
STAGE 5 · remove the click     ⭐ only after stage 3 has shown N consecutive
                               releases where the gate and the human agreed
                               and N > 20
```

⭐⭐ **Stage 3 is the one teams skip, and it is the one that makes this safe.** Run the automated gates in **shadow mode**: they compute a verdict, they log it, and a human still decides. After twenty releases, compare. If the gate would have approved everything the human approved **and** flagged nothing the human passed, you have evidence. If it disagrees — you have just found the gap **for free**, before it caused an incident.

**The rollback of the rollback:** keep the human gate one flag away, forever. `AUTO_PROMOTE=false` should be a config change, not a code change, so that during an incident you can put a human back in the loop in seconds.

---

## 10 · The economics

| | 🔒 Case 1 | 🤖 Case 2 |
|---|---|---|
| **Cost to set up** | low — one approval mechanism | ⭐⭐ high — canary, analysis, auto-rollback, observability |
| **Cost per release** | ⭐ a human's attention, every time | ~zero |
| **Cost that scales with release frequency** | ⭐⭐ yes — linearly | no |
| **Lead time** | bounded by human availability | bounded by the pipeline |
| **Out-of-hours releases** | ⛔ blocked or risky | ✅ fine |
| **Failure mode** | slow, cautious, occasionally a wrong "yes" | ⭐ fast, and fast in the wrong direction if the gates are wrong |
| **What rots** | nothing much | ⭐ the gates, if nobody owns them |
| **Best when** | releases are infrequent or high-risk | releases are frequent and low-risk |

⭐ **The honest summary:** Case 2 is a **capital investment** that pays off in **operating cost**. It only pays back if you release often enough. A team deploying twice a month will never recover the cost of building and maintaining a canary analysis pipeline — and should not feel behind for not having one.

---

<a name="tasks--answers"></a>
## 11 · ⭐ TASKS — answers at the END

| # | Task |
|---|---|
| **T1** | State, in one sentence each, what Continuous Delivery and Continuous Deployment guarantee — and what neither guarantees |
| **T2** | Your team deploys to production three times a day, always after a Slack message and a thumbs-up emoji from the tech lead. Which case are you in? What would change to move to the other? |
| **T3** | Run the nine-question framework (§5) against the `shop` estate and record the verdict **per service** |
| **T4** | Write the five prerequisites as concrete, checkable acceptance criteria for `checkout` (Go, stateless) |
| **T5** | Your staging smoke test fails 3% of the time for reasons nobody has investigated. You are planning Case 2. What do you do, and in what order? |
| **T6** | Design the stage-3 shadow-mode gate for `shop-api`: what does it compute, what does it log, and what evidence would justify moving to stage 4? |
| **T7** | ⭐ A migration renames `orders.qty` → `orders.quantity` and the same release updates the Java entity. Explain precisely why this blocks Case 2, and rewrite it as three rollback-safe releases |
| **T8** | Your service handles 4 requests per minute. You want a 10-minute canary with an error-rate gate. Why does this not work, and what are the three options? |
| **T9** | Choose between the four middle grounds (§7) for a team of four engineers, one regulated payment service, and a marketing frontend — and justify it |
| **T10** | ⭐⭐ An interviewer says: "Continuous Deployment is just Continuous Delivery with the approval step removed." Agree or disagree, and defend your answer for two minutes |

---

# ✅ ANSWERS

**T1.** **Continuous Delivery** guarantees that every change passing CI is *proven deployable to production*, and that a human decides when — so release is a business decision, available at any moment. **Continuous Deployment** guarantees that every change passing CI *and* the automated promotion gates reaches production without human intervention — so lead time is bounded by the pipeline, not by anyone's availability. **Neither guarantees the release is good.** ⭐ Both only guarantee that what was *checked* passed; the difference is who bears the residual risk — a person who might notice something the checks missed, or a set of thresholds that will not.

**T2.** 🔒 **Case 1 — Continuous Delivery**, with an informal gate. The definition turns on *who approves*, not on *how formal* the approval is or how often it happens: a human decides, so it is Delivery. Three times a day is a fast human, not automation. **To move to Case 2:** encode the tech lead's implicit judgement as checks (§6) — the smoke tests they trust, the error-rate thresholds they watch, the "is anyone else mid-release" question as an explicit `lock` — then add canary + automatic rollback, then run the gates in shadow mode alongside the human (§9 stage 3) until they agree consistently. ⭐ The interesting observation: this team probably has *better* lead time than many self-described Case 2 teams. The emoji gate costs seconds. What it lacks is out-of-hours coverage and auditability, and those are the real reasons to formalise.

**T3.** Applying §5 and §8 per service:

| Service | Q1 fast rollback | Q2 tests | Q3 metrics | Q4 digest | Q5 migrations | ⭐ Verdict |
|---|---|---|---|---|---|---|
| `shop-ui` (FE) | ✅ static, instant | ✅ | ⚠️ RUM needed | ✅ | ✅ n/a | 🤖 **Case 2** — lowest risk, *after* `index.html` is `no-cache` |
| `payment-mock` | ✅ | ✅ | ✅ | ✅ | ✅ n/a | 🤖 **Case 2 — start here** |
| `checkout` (Go) | ✅ | ✅ | ✅ | ✅ | ✅ n/a | 🤖 **Case 2** |
| `order-worker` | ⚠️ in-flight work | ⚠️ broker needed | ⚠️ no HTTP probe | ✅ | ✅ | 🔒 **Case 1** (or pattern 4) |
| `shop-api` (Java) | ⚠️ | ⭐ needs Testcontainers | ✅ | ✅ | ⛔ **not yet expand/contract** | 🔒 **Case 1** until Q5 passes |
| P13 data tier | ⛔ | ⛔ | ✅ | ✅ | ⛔ | 🔒 **Case 1, permanently** |

⭐ The answer to say out loud: **the estate is not one case.** A single organisation-wide policy forces the highest-risk service's rules onto the lowest-risk one. Per-service is correct, and per-service is only possible because CI is per-service (Scenario 1).

**T4.** For `checkout` — Go, stateless, no schema:
1. **Rollback:** `kubectl set image deploy/checkout checkout=<previous-digest>` returns to green in **< 60 s**, verified by an actual drill, not by assumption. Rollout is `RollingUpdate` with `maxUnavailable: 0` and a working `/readyz`.
2. **Tests:** `go test -race -count=1 ./...` plus an HTTP smoke test hitting `/healthz` and one real endpoint **in the target namespace** post-deploy. ⭐ Zero flaky tests — three consecutive clean runs required.
3. **Metrics:** request rate, 5xx ratio, p99 latency, goroutine count, from Prometheus; a recorded 7-day baseline; an SLO of 99.9% with a 5-minute alert window.
4. **Digest:** deployed by `@sha256:` from the CI manifest; the same digest verified running in staging first (`kubectl get deploy -o jsonpath` matches).
5. **Migrations:** none — ⭐ and that is *why* it qualifies. State this explicitly: the absence of a schema is the reason this service is the correct Case 2 pilot.

**T5.** ⛔ **Do not proceed to Case 2.** Order of work:
1. **Find out why it fails.** "Nobody has investigated" is the actual problem — a 3% failure rate is a signal with a cause. Time-box the investigation; if it is genuinely nondeterministic, go to 2.
2. **Quarantine it.** Mark it non-blocking so it stops teaching people that red is normal. ⭐ A gate that is ignored is worse than no gate: it destroys the credibility of every other gate.
3. **Fix or delete.** A test that cannot be made deterministic should be deleted and replaced with something that can. Coverage lost is recoverable; trust lost is not.
4. **Add a flakiness report** — run the suite N times on an unchanged commit, publish the failure rate, and treat > 0.5% as a build failure in itself.
5. **Then** reconsider Case 2.

⭐ **Why in this order:** in Case 2 a 3%-flaky gate randomly blocks releases (people lose faith in automation) *and* randomly passes real failures (the gate is not a gate). You cannot automate a decision on top of a check you do not trust.

**T6.** **Shadow-mode gate for `shop-api`:**
- **Computes:** for the candidate digest, a verdict from (a) post-deploy smoke tests in staging, (b) a 10-minute comparison of 5xx ratio and p99 latency against the same-hour 7-day baseline, (c) a check that no other release is in flight (`lock`), (d) that the Flyway migration validated against the shadow production schema.
- **Logs:** a structured record per release — `{digest, verdict, each sub-check's value and threshold, timestamp}` — written somewhere queryable, *plus* a comment on the PR/deployment so it is visible at the moment the human decides.
- **The human still decides**, and records their decision in the same place.
- ⭐ **Evidence justifying stage 4:** ≥ 20 consecutive releases where the gate's verdict and the human's decision agreed; **zero** cases where the gate said "ship" and the human said "no" without the gate having a defensible reason; and at least one case where the gate flagged something real. That last one matters — a gate that has never fired has never been tested.

**T7.** ⛔ **Why it blocks Case 2:** the release couples a schema change to a code change, and neither half is backward-compatible. Rolling back the image leaves new-schema code... no — it leaves **old** code expecting `qty` against a schema that now has `quantity`. **Rollback is impossible; you can only roll forward.** Case 2 requires prerequisite 5 (fast, boring, *reversible* deploys), and this migration removes reversibility. It is also unsafe in Case 1 — the difference is that a human might notice.

✅ **Three rollback-safe releases:**
1. **Add** `quantity` (nullable), **dual-write** both columns, keep reading `qty`. Old code still works → **rollback = revert the image, the extra column is harmless.**
2. **Backfill** `quantity` from `qty` (batched, non-locking), add a `NOT NULL` constraint *after* the backfill, then switch reads to `quantity`. Still dual-writing → **rollback = revert to release 1, which still reads `qty` and still writes it.**
3. **Stop** writing `qty`, then in a **later** release drop the column. ⭐ Only after telemetry confirms no reader. Dropping is the single irreversible step, which is why it goes last and alone.

**T8.** ⛔ **4 req/min × 10 min = 40 requests.** An error-rate gate on 40 samples cannot distinguish 0% errors from 5% — one failure is 2.5%, two is 5%. The gate will either never fire or fire on noise. ⭐ The deeper problem: prerequisite 3 requires metrics that can say "this is worse" *inside the canary window*, and low volume means there is no signal to analyse.

**Three options:**
1. ⭐ **Extend the window** — a 60-minute canary gives ~240 requests. Still weak, but usable with a *count*-based rather than *rate*-based gate ("any 5xx in the canary halts").
2. **Use a different signal** — latency percentiles, saturation, goroutines/GC pauses, and *application-level* checks (a synthetic probe, a contract test against the canary) rather than user-traffic error rates.
3. ⭐ **Stay in Case 1** for this service — and say so without embarrassment. Automated analysis on low-volume services is not weaker, it is **meaningless**. A human reading a dashboard is genuinely better here, and prerequisite 3 is a hard "No".

**T9.** ⭐ **Split the estate and use different patterns per service:**
- **Marketing frontend** → 🤖 **Case 2** (or pattern 4). No state, no schema, instant rollback, and it is the service that changes most often — so it is where automated promotion pays back fastest.
- **Regulated payment service** → 🔒 **Case 1, permanently**, and say why: regulation may *require* a documented human approval, which no amount of gate quality substitutes for. Add **pattern 3** (canary auto-deploys, then pauses) if the team wants faster learning without weakening the audit trail.
- **The team of four** → ⭐ **pattern 1 first** (automate dev and staging, gate production), because with four engineers nobody can own a canary analysis pipeline *and* the product. Automate the cheap, high-frequency environments; keep the human where the risk and the regulation are.

**The justification to state:** the choice follows **release risk and change frequency per service**, not an organisational preference. A team that applies one policy everywhere is either over-engineering its frontend or under-protecting its payment service — usually both.

**T10.** ⭐ **Disagree — the statement describes the mechanism but inverts the causality.** Two minutes:

> "Structurally, yes — you delete an approval step. But that framing implies Case 2 is Case 1 minus something, when it is actually Case 1 **plus** a great deal.
>
> That approval step was doing work. The human was implicitly answering: *do the tests cover this? are the metrics normal right now? is anyone else mid-release? if this breaks, can we get back in minutes?* Remove the human and those questions do not disappear — they have to be answered by machinery. Smoke gates, baseline-aware analysis, an explicit concurrency lock, canary with progressive rollout, and automated rollback. That is the actual content of Case 2, and none of it is 'the approval step'.
>
> So the accurate version of the statement is: **Continuous Deployment is Continuous Delivery where the human's judgement has been encoded as automated gates — and the encoding has to exist before you remove the human.** Teams that remove the step first have not adopted Continuous Deployment; they have adopted *unattended* deployment, which is the same pipeline without the safety.
>
> The practical test I would apply: **can you roll back production in under fifteen minutes, automatically, and have you actually done it?** If yes, removing the approval is a small change. If no, removing the approval is the most dangerous change you could make — and it will look like a one-line diff."

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Case 2 is not Case 1 with the click removed. It is Case 1 with the click's judgement rebuilt as machinery — built first.*

</div>
