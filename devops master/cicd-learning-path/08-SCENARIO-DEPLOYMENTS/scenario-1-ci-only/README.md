# ① SCENARIO 1 — CI ONLY
### Build it, test it, publish it, **stop.** No deployment step of any kind.

> **This is not a half-built pipeline.** For a meaningful fraction of real repositories, CI-only is the *correct and complete* answer — and knowing when that is true is a senior judgement, not a gap in your work.
>
> **Tool files are parallel, not sequential.** Read the one for the tool you have: 🐙 [`01-github-actions-ci.md`](./01-github-actions-ci.md) · 🔷 [`02-azure-devops-ci.md`](./02-azure-devops-ci.md) · 🔨 [`03-jenkins-ci.md`](./03-jenkins-ci.md). Then read [`04-app-shapes-fe-be-fullstack.md`](./04-app-shapes-fe-be-fullstack.md), which is tool-independent.

---

## 📇 Files in this folder

| File | One line |
|---|---|
| [`README.md`](./README.md) | What CI-only is, when it is the right answer, and the five checks that prove your pipeline really is CI-only |
| [`01-github-actions-ci.md`](./01-github-actions-ci.md) | 🐙 GitHub Actions — path filters, matrix, caching, OIDC push to GHCR, digest output, least-privilege `permissions:` |
| [`02-azure-devops-ci.md`](./02-azure-devops-ci.md) | 🔷 Azure DevOps — reusable templates, cache tasks, Workload Identity Federation to ACR, digest as a pipeline artifact |
| [`03-jenkins-ci.md`](./03-jenkins-ci.md) | 🔨 Jenkins — declarative Jenkinsfile, dynamic Kubernetes agents, per-language tool containers, credential scoping |
| [`04-app-shapes-fe-be-fullstack.md`](./04-app-shapes-fe-be-fullstack.md) | ⭐ The four application shapes side by side, and the CI differences that actually matter for each |

---

## 1 · What "CI only" means, precisely

**Continuous Integration** = every change is **built and verified automatically, and the result is a published artifact.** It ends there.

```
   git push / pull_request
            │
            ▼
   ┌────────────────────────────────────────────────────────────┐
   │  1. CHECKOUT          the exact commit                     │
   │  2. RESTORE CACHE     dependencies, keyed on the lockfile  │
   │  3. BUILD             language-specific                    │
   │  4. TEST              unit → integration → contract        │
   │  5. STATIC ANALYSIS   lint, type check, SAST               │
   │  6. PACKAGE           ⭐ a multi-stage Docker image        │
   │  7. SCAN              ⭐ the IMAGE, not just the source    │
   │  8. SIGN              ⭐ provenance: who built what, when  │
   │  9. PUBLISH           push to a registry                   │
   │ 10. ⭐⭐ EMIT THE DIGEST   the handoff artifact            │
   └────────────────────────────────────────────────────────────┘
            │
            ▼
        ⛔ STOP.
        Nothing below this line exists in Scenario 1.
        ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
        no kubectl        no helm upgrade
        no compose up     no ssh
        no `set image`    no Argo CD sync
        no environment    no approval gate
```

⭐ **Step 10 is the whole point.** A CI-only pipeline that does not emit the digest is a pipeline that built something and threw it away. The digest is what makes Scenario 2 possible *later*, without changing Scenario 1 at all.

---

## 2 · When CI-only is the **right** answer

| Situation | Why CI-only is correct |
|---|---|
| ⭐ **A library, SDK or CLI** | There is nothing to deploy. You publish a package/image; *consumers* deploy it. Docker P4's `shopctl` is exactly this — see [`../00-PROJECT-INVENTORY.md`](../00-PROJECT-INVENTORY.md) §6.6 |
| ⭐ **A shared base image** | `shop-base:21-jre` is consumed by other builds. Deploying it means nothing |
| **Deployment is another team's pipeline** | Very common at scale: the app team owns CI, the platform team owns CD. The **contract between them is the digest** |
| **Deployment is GitOps** | ⭐ CI writes a digest into a config repo; **Argo CD** does the deploying. Your CI pipeline legitimately has no deploy step — see [`../scenario-3-ci-plus-cd/08-gitops-argocd.md`](../scenario-3-ci-plus-cd/08-gitops-argocd.md) |
| **A monorepo where services deploy independently** | per-service CI + a separate release-train CD |
| **You are still earning the right to automate** | ⭐ honest and common: tests are flaky, coverage is 30%, there are no staging environments. Automating deployment now would automate incidents |
| **A regulated change window** | the deploy is a *scheduled, approved event*. CI runs on every commit; CD runs on Wednesdays |

⛔ **When CI-only is a smell instead:**

| Smell | What it actually means |
|---|---|
| "We deploy manually from a laptop" | you have no CD, and your artifact contract is a person's memory |
| "CI builds the image and CD **rebuilds** it" | ⛔ you do not have CI+CD, you have two CIs and a hope |
| "CI pushes `:latest` and CD pulls `:latest`" | ⛔ the artifact is mutable. You cannot roll back, cannot audit, cannot reproduce |
| "CI passes but nobody looks" | the build is not actually gating anything |

---

## 3 · ⭐ The five checks that prove your pipeline really is CI-only

Run all five. If any fails, you are in Scenario 3 whether you intended to be or not.

| # | Check | How |
|---|---|---|
| **1** | **No deployment verb anywhere** | grep the pipeline definition for `kubectl`, `helm`, `compose up`, `ssh`, `scp`, `az webapp`, `aws ecs`, `argocd`, `set image`, `apply -f`. ⭐ If *any* appear, it is not CI-only |
| **2** | **No cluster/host credentials are reachable** | ⭐⭐ the real test. A pipeline that *could* deploy is a pipeline that *can be made to* deploy by anyone who can edit it. Check the secrets in scope |
| **3** | **It emits a digest, not just a tag** | the output must contain `sha256:…`. A tag alone is not a handoff |
| **4** | **Pull requests and main behave differently, but neither deploys** | PR: build + test, ⛔ do **not** push. Main: build + test + push + sign |
| **5** | **It is reproducible from the digest alone** | `docker pull <img>@sha256:…` on a clean machine gives you the tested artifact |

### Check 2, in detail — because it is the one people skip

⭐⭐ **A CI pipeline that can read a production credential can deploy to production, whether or not it does.** The YAML is not the security boundary; the *credential scope* is.

```
🐙 GitHub Actions
   • the DEFAULT token is read/write to everything in the repo.
     ⭐ Set `permissions: contents: read` at the workflow level, and grant
        `packages: write` ONLY on the job that pushes.
   • Environment secrets are scoped per environment. A CI workflow must not
     reference the `production` environment at all.
   • ⛔ A fork PR must never receive secrets. Check
     `if: github.event.pull_request.head.repo.full_name == github.repository`
     before anything privileged, and rely on `pull_request` (not
     `pull_request_target`, which runs with BASE repo secrets).

🔷 Azure DevOps
   • Service connections are scoped to the pipeline / project.
     ⭐ A CI pipeline should have NO service connection to a cluster.
   • Variable groups linked to a pipeline expose every secret in them.
     Link the *build* group, not the *deploy* group.
   • Environments + checks protect deployments — but only if the pipeline
     cannot reach the credential by another route.

🔨 Jenkins
   • ⛔ GLOBAL credentials are visible to EVERY job, including multibranch
     jobs created from forks' PRs. This is the classic Jenkins breach path.
   • ✅ Use FOLDER-scoped credentials, and `withCredentials` inside the
     narrowest possible block.
   • ⭐ Check: Manage Jenkins → Credentials → look at the SCOPE column.
     Then check the multibranch job's "Discover branches" setting — if it
     discovers forks, anything global is exposed to untrusted code.
```

---

## 4 · The universal CI-only skeleton (tool-independent)

Every tool file in this folder instantiates this same ten-step shape. Learn it once.

```
┌─── TRIGGER ───────────────────────────────────────────────────────────┐
│ push to main  ·  pull_request to main  ·  (manual) workflow_dispatch  │
│ ⭐ PATH FILTERS: only run for the service that changed                │
└───────────────────────────────────────────────────────────────────────┘
        │
┌─── JOB: build-and-test ───────────────────────────────────────────────┐
│ 1 checkout          ⭐ pin the action by SHA, fetch-depth: 0 for tags │
│ 2 setup toolchain   pinned version, NOT `latest`                      │
│ 3 restore cache     key = hash of the LOCKFILE, not the source        │
│ 4 install deps      `npm ci` / `mvnw dependency:go-offline` /         │
│                     `go mod download` / `uv sync --frozen`            │
│ 5 unit tests                                                          │
│ 6 ⭐ integration    Testcontainers (Java) / real Postgres service     │
│ 7 lint + type check + SAST                                            │
│ 8 ⭐ publish test results & coverage as artifacts — visible on the PR │
└───────────────────────────────────────────────────────────────────────┘
        │  needs: build-and-test   ← ⛔ never `if: always()`
┌─── JOB: package-and-publish ──────────────────────────────────────────┐
│ 9  docker build     ⭐ multi-stage, with --cache-from (registry cache)│
│10  scan the IMAGE    Trivy / Grype — the source scan is not enough    │
│11  sign + attest     cosign / notation — ⭐ provenance                │
│12  push             tags: the SHA, the branch, `latest` (main only)   │
│13  ⭐⭐ EMIT DIGEST  write `sha256:…` to the job output AND to a file  │
│14  save cache                                                        │
└───────────────────────────────────────────────────────────────────────┘
        │
        ▼
   ⛔ STOP — Scenario 1 ends here.
```

⭐⭐ **The two structural rules that matter most:**

1. **`package-and-publish` must `needs: build-and-test`.** Not run in parallel, not `if: always()`. If tests fail, no image is published — otherwise your registry fills with untested artifacts and someone eventually deploys one.
2. **Do not push images on pull requests.** Fork PRs from untrusted contributors would write to your registry. Build them, scan them, *maybe* push to a quarantine repository — but do not push to the canonical path.

---

## 5 · What each tool file gives you

Each of the three tool files covers **all five applications** (`shop-ui`, `shop-api`, `checkout`, `order-worker`, `payment-mock`) with:

| Section | Content |
|---|---|
| The complete pipeline definition | real, runnable YAML/Groovy — commented line by line |
| Caching | ⭐ the correct cache key per language, and the mistake that makes the cache useless |
| Registry auth | ⭐⭐ **federated identity where possible** (OIDC / Workload Identity) — no long-lived secret at all |
| The digest handoff | exactly how the digest leaves the pipeline in a form CD can consume |
| Least privilege | the specific settings for that tool, and what breaks if you skip them |
| Fork/PR safety | the tool-specific untrusted-code hazard |
| Verification | ⭐ commands to prove it worked, run from your own laptop |
| Troubleshooting | the errors you will actually hit, with causes |

---

## 6 · Which file to open

| You have… | Open |
|---|---|
| GitHub | ⭐ [`01-github-actions-ci.md`](./01-github-actions-ci.md) |
| Azure DevOps | [`02-azure-devops-ci.md`](./02-azure-devops-ci.md) |
| Jenkins | [`03-jenkins-ci.md`](./03-jenkins-ci.md) |
| Any tool, and you want the **shape** differences between FE / BE / fullstack / polyglot | ⭐ [`04-app-shapes-fe-be-fullstack.md`](./04-app-shapes-fe-be-fullstack.md) |
| All three, because you're prepping for the migration interview question | all three tool files, then [`../06-CHEATSHEET.md`](../../06-CHEATSHEET.md) |

---

## 7 · Done means

You are finished with Scenario 1 when **all five** are true:

- [ ] `git push` to main produces a **signed image in the registry**, with no human involvement
- [ ] a **pull request** produces test results and a coverage report **but no published image**
- [ ] the pipeline **emits a `sha256:` digest** you can find without reading the logs
- [ ] `docker pull <image>@<that digest>` works from a clean machine
- [ ] ⭐⭐ the pipeline holds **no credential that could deploy anything**

Then go to [`../scenario-2-cd-only/`](../scenario-2-cd-only/) and consume that digest — **without changing a single line of Scenario 1.** That is the test of whether you built it properly.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*CI ends with a digest. If it ends with anything else, CD will have to rebuild — and then you have two artifacts and no guarantee.*

</div>
