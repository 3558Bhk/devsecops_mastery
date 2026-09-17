# 🔄 SCENARIO 3 — CI + CD, END TO END
### One pipeline (or one pipeline *pair*) from `git push` to production traffic — for each app shape, in each tool.

> **The definition of this scenario:** commit → build → test → publish a digest → deploy → verify → **running in production**, with no manual step between the commit and the release decision (except where the shape's risk profile requires one).
>
> **The tension this scenario exists to resolve:** CI wants to be **one pipeline** (simple, atomic). CD wants to be **separate** (different credentials, different blast radius, different permissions). ⭐ §2 of each tool file is that argument.

---

## 📂 This scenario

| # | File | What it covers |
|---|---|---|
| **1** | ⭐ [`01-github-actions-full.md`](./01-github-actions-full.md) | One repo, two workflows chained by `workflow_run`; OIDC to GHCR **and** to the cluster; environments for secret scoping; the full `shop-api` path |
| **2** | ⭐ [`02-azure-devops-full.md`](./02-azure-devops-full.md) | A CI pipeline + a CD pipeline linked by `resources.pipelines.trigger`; Workload Identity Federation to ACR and AKS; multi-stage with gates |
| **3** | ⭐ [`03-jenkins-full.md`](./03-jenkins-full.md) | One repo, two jobs in **separate folders with separate permissions**; `build job:` chaining; Kaniko build → `kubectl` deploy; the shared library that holds both halves |
| **4** | 🔵 [`04-fe-only.md`](./04-fe-only.md) | **Frontend only** — `shop-ui` (Docker/K8s P8) and the static site (P2). Runtime config, bundle gates, cache headers, and why this is the easiest full path |
| **5** | 🟢 [`05-be-only.md`](./05-be-only.md) | **Backend only** — `shop-api` (P9), `checkout`, `order-worker`, `payment-mock`. Testcontainers in CI, the migration Job in CD, per-language differences |
| **6** | 🟡 [`06-fe-plus-be-same-stack.md`](./06-fe-plus-be-same-stack.md) | **FE + BE, one stack** — P10 React + Java. The release manifest, expand/contract, backend-first ordering, and the contract test that makes it safe |
| **7** | 🟠 [`07-fe-plus-be-different-langs.md`](./07-fe-plus-be-different-langs.md) | **FE + BE, different languages** — P11 React+Python, P12 React+Go. The matrix pattern, four toolchains, four caches, one manifest |
| **8** | ⭐⭐ [`08-gitops-argocd.md`](./08-gitops-argocd.md) | **The end state.** CI writes a digest to a **manifests repo**; **Argo CD** syncs it. Why this is the correct architecture for Scenarios 2 and 3 at scale |

---

## 🧭 The full path, in one picture

```
   git push
      │
══════╪══════════════════════════ CI ═══════════════════════════════════
      ▼
   checkout → setup toolchain → restore cache → install → test
      │
      ├─ static analysis · SAST · dependency CVE scan
      ▼
   build IMAGE (multi-stage) → scan the IMAGE → SIGN (cosign)
      │
      ▼
   push → ⭐⭐ EMIT THE DIGEST  ────────────┐
                                            │  the artifact contract
════════════════════════════════════════════╪════════════ CD ═══════════
                                            ▼
                              resolve + validate the digest
                                            │
                              verify provenance (cosign)
                                            │
                              ┌─────────────┴─────────────┐
                              ▼                           ▼
                      🤖 automatic                🔒 human gate
                     (Case 2 path)               (Case 1 path)
                              │                           │
                              └─────────────┬─────────────┘
                                            ▼
                        deploy dev → verify → staging → verify
                                            │
                              ⭐ canary / blue-green (Case 2)
                                            │
                                     production
                                            │
                                 verify · record · rollback?
```

⭐ **The one thing that holds it together:** the digest emitted by CI is the *exact* string CD deploys, and it is verified at both ends — signed by CI, checked by CD, and **read back from the cluster** after the deploy.

---

## 🔀 Which Case does Scenario 3 use?

**Both — and that is the point.** Scenario 3 is not a third deployment policy; it is *CI and CD in one chain*, and the chain's production stage can be either case:

| App shape | Service | ⭐ Production stage | Why |
|---|---|---|---|
| 🔵 FE only | `shop-ui` | 🤖 **Case 2** | no state, no schema, rollback in seconds |
| 🟢 BE stateless | `payment-mock`, `checkout` | 🤖 **Case 2** | the pilot — lowest consequence |
| 🟢 BE stateful | `shop-api` | 🔒 **Case 1** | the migration is the irreversible part |
| 🟢 BE worker | `order-worker` | 🔒 **Case 1** | cannot be canaried ([Case 2 · targets §7.1](../scenario-2-cd-only/case-2-continuous-deployment/04-docker-and-k8s-targets.md)) |
| 🟡 FE + BE | P10 | ⭐ **split** | FE → Case 2, BE → Case 1 |
| 🟠 Polyglot | P11/P12 | per service | each service gets its own policy |
| 🗄️ Data tier | P13 | 🔒 **Case 1, always** | not reversible |

---

## ⭐ The one architectural decision: one pipeline or two?

| | **One pipeline** (CI+CD in one file) | ⭐ **Two pipelines** (CI, then CD) |
|---|---|---|
| Simplicity | ✅ one thing to read | two things, chained |
| ⭐ Credentials | ⛔ **the same runner holds registry push AND cluster access** | ✅ CI can push but cannot deploy; CD can deploy but cannot push |
| ⭐ Blast radius | ⛔ a compromised dependency in `npm ci` can reach production | ✅ contained to the registry |
| Re-deploy without rebuild | ⛔ must re-run the whole thing | ✅ CD takes a digest input |
| Rollback | ⛔ awkward | ✅ a separate, ungated job |
| Fork/PR safety | ⚠️ one `if:` to get right | ✅ CD simply never triggers on a PR |
| Auditability | one log | ⭐ two clean logs: "was it built?" / "was it shipped?" |

⭐⭐ **The recommendation, and it is not close: two pipelines.** The credential separation alone decides it — in a single pipeline, the moment your build runs `npm ci`, a malicious postinstall script has your production kubeconfig in its environment. Every tool file in this folder therefore shows **two chained pipelines**, and explains the chaining mechanism for that tool.

**The exception:** a personal project, a homelab, or a single-service demo where the credential risk is genuinely nil and one file is easier to follow. That is a legitimate choice — say it out loud as one, rather than letting it become the production architecture by accident.

---

## 🧪 Try it locally — the full path in one afternoon

| Step | Command |
|---|---|
| 1 · cluster | `kind create cluster --name cicd --config kind-cicd.yaml` |
| 2 · registry | `docker run -d -p 5000:5000 --name registry registry:2` (or GHCR) |
| 3 · the app | [Docker P10](../../../docker-learning-path/) — React + Java |
| 4 · the manifests | [K8s P10](../../../kubernetes-learning-path/) |
| 5 · CI | [`../scenario-1-ci-only/`](../scenario-1-ci-only/README.md) — publish a digest |
| 6 · CD | [`../scenario-2-cd-only/`](../scenario-2-cd-only/README.md) — deploy that digest |
| 7 · chain them | ⭐ this folder's tool file |
| 8 · the end state | [`08-gitops-argocd.md`](./08-gitops-argocd.md) |

---

## 🗣️ Interview framing

> **"CI and CD in one pipeline is a tempting shortcut, and the reason not to take it is credentials. In a single pipeline the runner that executes `npm ci` also holds your production kubeconfig — so a compromised transitive dependency has a path to production. Two chained pipelines let you give CI registry-push and CD cluster-access, and neither can do the other's job.**
>
> **The thing that makes two pipelines safe rather than fragile is the artifact contract: CI emits a digest, CD consumes a digest, CD verifies its signature, and CD reads the image back from the cluster after deploying. Four checks, and together they answer 'is what is running what we built and approved?'**
>
> **And the end state worth describing is GitOps: CI's last step is a commit to a manifests repo, and Argo CD syncs it. Then the CD pipeline disappears entirely — the cluster pulls rather than being pushed to — and `git log` becomes both the audit trail and the rollback mechanism."**

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Two pipelines, one digest. CI proves it can be deployed; CD decides when — and neither holds the other's keys.*

</div>
