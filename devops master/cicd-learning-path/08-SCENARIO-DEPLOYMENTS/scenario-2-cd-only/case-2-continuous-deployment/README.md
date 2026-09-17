# 🤖 CASE 2 — CONTINUOUS DEPLOYMENT
### Nothing is manual. The pipeline decides, because the human's judgement was encoded as gates first.

> **The guarantee:** every change that passes CI **and** the automated promotion gates reaches production, with no human in the path.
> **The price:** all five prerequisites in [`../00-delivery-vs-deployment.md`](../00-delivery-vs-deployment.md) §6 must already be true — and automated rollback is **mandatory**, not optional.

---

## 📂 Files in this case

| # | File | What it covers |
|---|---|---|
| **1** | ⭐ [`01-github-actions-deployment.md`](./01-github-actions-deployment.md) | Auto-promotion on CI success via `workflow_run`, `deployment_status`, smoke gates, canary via a second environment, and automatic rollback |
| **2** | ⭐ [`02-azure-devops-deployment.md`](./02-azure-devops-deployment.md) | Chained pipelines via `resources: pipelines`, **deployment gates** (Azure Monitor, REST, Query Work Items), a canary stage, and `on: failure` rollback |
| **3** | ⭐ [`03-jenkins-deployment.md`](./03-jenkins-deployment.md) | Upstream triggers, `waitUntil` smoke loops, the promotion-decision function, and replacing the approver with a threshold |
| **4** | ⭐ [`04-docker-and-k8s-targets.md`](./04-docker-and-k8s-targets.md) | ⭐⭐ **Argo Rollouts** — canary and blue-green for the K8s projects, `AnalysisTemplate`, progressive steps, and the rollback that actually works |

---

## 🎯 What replaces the human

In Case 1 a person answered four questions. In Case 2 **each becomes a check**:

| The human's question | ⭐ The automated equivalent | Where |
|---|---|---|
| *"Does this look safe?"* | post-deploy **smoke tests** against real endpoints, in the target environment | every tool file |
| *"Are the metrics normal?"* | ⭐ **baseline-aware analysis** — 5xx ratio, p99 latency, saturation, compared against the same-hour 7-day baseline | Argo Rollouts `AnalysisTemplate`, Azure Monitor gate |
| *"Is anyone else mid-release?"* | a **concurrency lock** — `concurrency:` / `ExclusiveLock` / `lock()` | every tool file |
| *"If this breaks, can we get back?"* | ⭐⭐ **automatic rollback**, triggered by a failed check, with no human | every tool file |
| *"Should we ship at all, right now?"* | a **freeze calendar** / business-hours check | Azure REST check, a Jenkins `when` |

⭐⭐ **The fifth row is the one people forget.** Case 1's human also decided *whether now is a good time*. Encoding that means a freeze-calendar check — during a code freeze, Black Friday, or an active incident, the pipeline must refuse to promote. Without it, Case 2 will happily deploy into an incident and make it worse.

---

## 🧭 The Case 2 pipeline shape

```
CI green ──▶ deploy dev ──▶ verify dev (MUST PASS)
                                  │
                            deploy staging ──▶ verify staging (MUST PASS)
                                  │                    ⛔ fail → STOP + alert
                                  ▼
                        ⭐ deploy CANARY (5–10% traffic)
                                  │
                        analyse for N minutes
                        (errors · latency · saturation · business metrics)
                                  │
                    ┌─────────────┴─────────────┐
                    ▼                           ▼
              thresholds OK              ⛔ thresholds breached
                    │                           │
              promote to 100%            ⭐⭐ AUTOMATIC ROLLBACK
              in steps (25→50→100)              + page + freeze further
                    │                           releases
              verify production
                    │
              record + unfreeze
```

| Stage | ⛔ If it is missing |
|---|---|
| verify dev / staging **as a gate** | you promote untested changes |
| **canary** | a bad release hits 100% of users immediately |
| **baseline-aware** analysis | Monday-morning traffic looks like an incident; a real regression at 3 a.m. looks normal |
| ⭐⭐ **automatic rollback** | Case 2 without it is strictly worse than Case 1 |
| **halt further releases** after a rollback | the next commit re-triggers the same failure |

---

## ✅ The five prerequisites — restate them before you build

From [`../00-delivery-vs-deployment.md`](../00-delivery-vs-deployment.md) §6. **All five, not four:**

| # | Prerequisite | The one-line test |
|---|---|---|
| 1 | ⭐ Fast, boring, **reversible** deploys | you have rolled back production **deliberately**, and it took < 15 min |
| 2 | Tests that catch what matters | ⭐ **zero flaky tests** — a 2%-flaky gate randomly blocks *and* randomly passes |
| 3 | Observability that can say "this is worse" | a written SLO, a 7-day baseline, alerts in < 5 min, **enough traffic volume** to be meaningful in the canary window |
| 4 | Immutable artifacts by **digest** | rollback = re-point at the previous digest, one command |
| 5 | Decoupled, backward-compatible migrations | expand/contract; the old image runs against the new schema |

⭐⭐ **If any of these is false, do not build Case 2 — build the missing prerequisite.** That work improves your delivery whether or not you ever automate the approval, and it is the only honest path to Case 2.

---

## 🚦 The honest "should we?" table

| Your situation | ⭐ Verdict |
|---|---|
| All five prerequisites green, frequent releases, low-risk services | 🤖 **Case 2 — do it** |
| Prerequisites green, but you release twice a month | 🔒 Case 1 — Case 2 will never pay back its maintenance cost |
| Regulated sign-off required for production changes | 🔒 **Case 1, permanently** — no gate quality substitutes for a documented human approval |
| Data tier (Postgres, Kafka, Elastic) | 🔒 **Case 1, permanently** — a data directory upgrade is not reversible |
| 🔵 Frontend only | 🤖 **Case 2 — start here.** Lowest risk, highest change frequency, trivial rollback |
| 🟢 Stateless backend (`payment-mock`, `checkout`) | 🤖 **Case 2 — the pilot.** Prove the machinery where being wrong costs nothing |
| 🟢 Stateful backend (`shop-api`) | 🔒 Case 1 until prerequisite 5 is real |
| ⭐ Not sure | **Pattern 3** — canary deploys automatically, then pauses for a click ([`../00-delivery-vs-deployment.md`](../00-delivery-vs-deployment.md) §7) |

---

## 🗣️ Interview framing

> **"Continuous Deployment means the pipeline decides. So the work is not removing an approval step — it is encoding everything that step was doing: smoke tests against real endpoints in the target environment, baseline-aware metric analysis rather than fixed thresholds, an explicit concurrency lock, a freeze-calendar check, and automatic rollback.**
>
> **Two details separate people who have run it. First, the analysis has to be baseline-aware — a fixed error-rate threshold either pages on Monday morning traffic or sleeps through a 3 a.m. regression. Second, automatic rollback must also halt further releases; otherwise the next commit re-triggers the same failure and you page yourself in a loop.**
>
> **And the honest part: Case 2 is a capital investment that pays off in operating cost, so it only pays back if you release often. For a service that ships twice a month, or a database whose upgrade is not reversible, Case 1 with a fast human is the correct engineering choice, not a compromise."**

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Removing the approver is one line. Rebuilding what the approver knew is the project.*

</div>
