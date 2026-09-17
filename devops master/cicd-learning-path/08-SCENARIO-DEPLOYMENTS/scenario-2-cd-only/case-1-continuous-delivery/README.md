# 🔒 CASE 1 — CONTINUOUS DELIVERY
### Every change is deployable; a human decides when. The approval gate in all three tools, and how to stop it from becoming theatre.

> **The guarantee:** at any moment, a reviewed, tested, digest-pinned artifact is **one click** from production.
> **The constraint:** that click is made by a **person**, and the person's decision is **audited**.

---

## 📂 Files in this case

| # | File | What it covers |
|---|---|---|
| **1** | ⭐ [`01-github-actions-delivery.md`](./01-github-actions-delivery.md) | `workflow_dispatch` with a digest input, `environment:` protection rules, required reviewers, manual approval, deployment history, and the "don't build here" rule |
| **2** | ⭐ [`02-azure-devops-delivery.md`](./02-azure-devops-delivery.md) | Classic **release pipelines** vs YAML + **Environments → Approvals and checks**, multi-stage with a gated production stage, deployment groups |
| **3** | ⭐ [`03-jenkins-delivery.md`](./03-jenkins-delivery.md) | The `input` step, `submitter`, `ok`, `parameters`, `timeout`, plus `lock` and `milestone`; a separate promotion job; the audit trail |
| **4** | ⭐ [`04-docker-and-k8s-targets.md`](./04-docker-and-k8s-targets.md) | **The deployment itself** — Compose targets, `kubectl set image`, Helm upgrades, migration Jobs, and a runbook per app shape |

---

## 🎯 What Case 1 actually requires

Four mechanisms. **All four**, in every tool:

| # | Mechanism | Why it is not optional |
|---|---|---|
| **1** | ⭐ **An input** — the digest to deploy | CD must not build. If it can build, it is not CD, and the digest contract is gone |
| **2** | ⭐ **A gate** that stops and waits | without it, the pipeline auto-promotes and you have Case 2 without Case 2's safety |
| **3** | **An identity** — *who* approved | for audit, and so the gate cannot be bypassed by anyone with repo write access |
| **4** | ⭐ **A record** — what was approved, when, by whom, and what happened | the artifact of Case 1. "Who deployed to production last Tuesday?" must have an answer |

```
┌──────────────────────────────────────────────────────────────┐
│  THE CASE 1 PIPELINE                                         │
│                                                              │
│  INPUT: digest  ──▶ deploy dev ──▶ deploy staging            │
│                                          │                   │
│                                     verify staging           │
│                                          │                   │
│                                   ⛔ APPROVAL GATE            │
│                                   (waits; notifies; audits)  │
│                                          │                   │
│                                   deploy production          │
│                                          │                   │
│                                   verify production          │
│                                          │                   │
│                                   RECORD the decision        │
└──────────────────────────────────────────────────────────────┘
```

---

## 🔧 The gate, in each tool — the one-line version

| Tool | The gate | Where the identity comes from |
|---|---|---|
| 🐙 GitHub Actions | `environment: production` + **Required reviewers** | the approving GitHub user, in the deployment log |
| 🔷 Azure DevOps | **Environments → Approvals and checks** (classic release: an approval on the stage) | the approving ADO identity, in the release history |
| 🔨 Jenkins | `input` step with `submitter` + the Authorization Matrix plugin | the `submitter`, plus `BUILD_USER` from the Build User Vars plugin |

⭐ All three do the same three things: **pause**, **notify**, **record**. The differences are configuration, not capability.

---

## ⚠️ The four ways a Case 1 gate rots

| Failure | How it looks | ⭐ Fix |
|---|---|---|
| **1. Rubber-stamping** | the same person approves everything in under 10 seconds, without reading | put the **digest, the diff, the staging verification result and the blast radius** in the approval prompt itself. If the approver has to go looking, they will not look |
| **2. Approver bottleneck** | one person is the only reviewer; releases stop when they are on leave | ⭐ a **team** as reviewer (GH team / ADO group / Jenkins group), with at least three members |
| **3. Gate bypass** | someone with admin rights merges and the pipeline deploys anyway | ⭐ branch protection **and** environment protection. In GitHub, "bypass rules" on the environment is the usual leak |
| **4. Nobody knows what was approved** | the record is a pipeline log nobody can search | ⭐ write the decision somewhere durable — a deployment record, a `git` commit to the manifests repo, a Slack message with a permalink |

⭐⭐ **Failure 1 is the important one.** An approval gate that is clicked without reading is *worse than no gate*, because it adds latency and creates a false sense of control. The remedy is not discipline — it is **making the prompt informative enough that approving is a real decision.** Every tool file in this folder therefore spends significant space on *what the approver sees*.

---

## ✅ The Case 1 acceptance checklist

| # | Check |
|---|---|
| 1 | The CD pipeline contains **no build, no test, no image publish** step |
| 2 | It accepts a **digest** as input and rejects anything that is not one |
| 3 | dev and staging deploy **automatically** — ⭐ the gate is only on production |
| 4 | Production **stops** and waits for a named human or team |
| 5 | The approval prompt shows: digest · source commit/PR · what changed · staging verification result |
| 6 | ⭐ At least **three** people can approve |
| 7 | The decision is recorded durably, with identity and timestamp |
| 8 | Rollback is a **first-class action** — a documented, tested, one-command re-deploy of the previous digest |
| 9 | Deploying the **same digest twice** is safe (idempotent) |
| 10 | ⭐ "What is running in production right now?" has a one-command answer |

---

## 🗣️ Interview framing

> **"Continuous Delivery means the pipeline keeps the software in a state where it *could* be released at any moment, and a human makes the release decision.**
>
> **In practice that is four mechanisms: a digest as the pipeline's input — because CD must not rebuild what CI already built; an approval gate that pauses; an identity attached to the approval; and a durable record.**
>
> **The failure mode worth talking about is rubber-stamping. An approval gate that people click without reading adds latency and a false sense of safety, so the design work is in the prompt: the approver should see the digest, the diff, the staging verification result and the blast radius without leaving the notification. If they have to go looking, they won't look."**

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*A gate nobody reads is latency with a good story. Design the prompt, not just the pause.*

</div>
