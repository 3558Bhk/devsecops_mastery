# 🚚 SCENARIO 2 — CD ONLY
### Continuous Delivery (Case 1) and Continuous Deployment (Case 2), when CI has already run somewhere else.

> **The definition of this scenario:** an artifact **already exists** in a registry. A **separate pipeline** — with **no build steps at all** — takes it from "exists" to "running in an environment".
>
> **The one rule:** CD takes a **digest**, never a tag. ⭐ If your CD pipeline says `:latest` or `:main`, you do not have CD; you have a race condition with a friendly name.

---

## 📂 This scenario

| # | File | What it covers |
|---|---|---|
| **00** | ⭐⭐ [`00-delivery-vs-deployment.md`](./00-delivery-vs-deployment.md) | **Read this first.** The distinction everyone gets wrong, the decision framework, and why "Continuous Deployment" does not mean "deploys continuously" |
| | **`case-1-continuous-delivery/`** | 🔒 **A human approves every production release** |
| 1.0 | [`case-1/README.md`](./case-1-continuous-delivery/README.md) | What Case 1 means, the approval gate in all three tools, and how to stop the gate from becoming theatre |
| 1.1 | [`case-1/01-github-actions-delivery.md`](./case-1-continuous-delivery/01-github-actions-delivery.md) | `workflow_dispatch` + digest input, `environment:` protection rules, required reviewers, manual approval, deployment history |
| 1.2 | [`case-1/02-azure-devops-delivery.md`](./case-1-continuous-delivery/02-azure-devops-delivery.md) | Classic **release pipelines** vs Environments + **Approvals and checks**, multi-stage YAML with a gated production stage |
| 1.3 | [`case-1/03-jenkins-delivery.md`](./case-1-continuous-delivery/03-jenkins-delivery.md) | The `input` step, approver groups via Authorization Matrix, `timeout`, `lock`, `milestone`, and the audit trail |
| 1.4 | [`case-1/04-docker-and-k8s-targets.md`](./case-1-continuous-delivery/04-docker-and-k8s-targets.md) | ⭐ Deploying to the **Docker/K8s projects**: Compose targets, `kubectl set image`, Helm upgrades, per-app-shape runbooks |
| | **`case-2-continuous-deployment/`** | 🤖 **Nothing is manual — the pipeline decides** |
| 2.0 | [`case-2/README.md`](./case-2-continuous-deployment/README.md) | What Case 2 really requires, the five prerequisites, and the honest answer to "should we do this?" |
| 2.1 | [`case-2/01-github-actions-deployment.md`](./case-2-continuous-deployment/01-github-actions-deployment.md) | Auto-promotion on CI success, smoke gates, `deployment_status`, canary via a second environment, auto-rollback |
| 2.2 | [`case-2/02-azure-devops-deployment.md`](./case-2-continuous-deployment/02-azure-devops-deployment.md) | Chained pipelines via resources, **deployment gates** (Query Work Items, Azure Monitor, REST), canary stage |
| 2.3 | [`case-2/03-jenkins-deployment.md`](./case-2-continuous-deployment/03-jenkins-deployment.md) | Upstream triggers, `waitUntil` smoke loops, promotion jobs, and replacing the human with a decision function |
| 2.4 | [`case-2/04-docker-and-k8s-targets.md`](./case-2-continuous-deployment/04-docker-and-k8s-targets.md) | ⭐ **Argo Rollouts** canary/blue-green for the K8s projects, analysis templates, and the rollback that actually works |

---

## 🧭 The two cases, in one picture

```
                    CI publishes a digest
                            │
                            ▼
        ╔═══════════════════════════════════════╗
        ║  CD pipeline — NO build steps at all  ║
        ╚═══════════════════╤═══════════════════╝
                            │
              ┌─────────────┴─────────────┐
              ▼                           ▼
   🔒 CASE 1 · DELIVERY        🤖 CASE 2 · DEPLOYMENT
   dev → staging → ⛔ GATE     dev → staging → ✅ GATE
                  │                              │
             a HUMAN clicks                 a MACHINE decides
                  │                       (smoke + metrics + analysis)
                  ▼                              │
              production                          ▼
                                              production
                                             (auto-rollback on failure)

   ⭐ SAME PIPELINE SHAPE. ONE DIFFERENCE: WHO — OR WHAT — APPROVES.
```

| | 🔒 Case 1 — Continuous **Delivery** | 🤖 Case 2 — Continuous **Deployment** |
|---|---|---|
| Trigger | ⭐ a human | ⭐ CI success |
| Approval gate | a person | an automated analysis |
| Production release frequency | whenever someone clicks | whenever CI is green |
| Can it deploy a bad version? | ⭐ yes — if the human says so | only if the gates are wrong |
| Rollback | manual, or a re-run | ⭐ automatic |
| Requires | an approval mechanism | ⭐ **five prerequisites** ([case-2/README §2](./case-2-continuous-deployment/README.md)) |
| Who is this for | most teams, most of the time | teams with strong tests, good observability, and low release risk |

---

## 🧪 Try it locally — the minimum you need

| Want | Run |
|---|---|
| ⭐ **A cluster** (every CD file needs one) | `kind create cluster --name cicd --config kind-cicd.yaml` — [K8s P1](../../../kubernetes-learning-path/) |
| A registry | GHCR (built in) · ACR (`az acr create`) · `docker run -d -p 5000:5000 --name registry registry:2` |
| An artifact to deploy | ⭐ any digest from [Scenario 1](../scenario-1-ci-only/README.md) — CD never builds |
| The manifests | [Docker P8–P13](../../../docker-learning-path/) · [K8s P8–P14](../../../kubernetes-learning-path/) |
| Progressive delivery (Case 2) | Argo Rollouts: `kubectl argo rollouts version` |
| GitOps (the Case 2 end-state) | Argo CD 3.x — [`../scenario-3-ci-plus-cd/08-gitops-argocd.md`](../scenario-3-ci-plus-cd/08-gitops-argocd.md) |

⭐ **The fastest possible Case 1 demo:** publish one digest in Scenario 1, then run the CD pipeline with `workflow_dispatch` and that digest. You will see the approval prompt, click approve, and watch the pod roll. Twenty minutes, end to end, and it teaches the whole scenario.

---

## 🗣️ Interview framing — the answer that shows seniority

> **"Continuous Delivery means every change is *deployable* — proven by a green pipeline — and a human decides when. Continuous Deployment means the pipeline decides, so the human's judgement has to have been encoded as automated gates first.**
>
> **The common mistake is treating them as points on a maturity ladder you climb. They are two different risk postures. Case 2 is not 'better'; it is only correct when your test coverage, observability, and rollback story can carry the decision the human used to make. If they cannot, automating the approval does not remove the risk — it just removes the last thing standing between it and your users.**
>
> **And the detail that separates people who have done it: the CD pipeline takes a *digest*, never a tag. A tag is a mutable pointer, so 'deploy :latest to production' does not tell you what you deployed — and without that, rollback is guesswork."**

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*CI proves it can be deployed. CD decides when — and Case 2 only earns that decision if the gates were built first.*

</div>
