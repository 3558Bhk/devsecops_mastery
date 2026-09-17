# 🔨 JENKINS — THE COMPLETE COURSE
### Eight files, one tool, end to end: install Jenkins on Kubernetes, then build all three scenarios for all six projects — including MERN — with folder-scoped credentials that make "CI cannot deploy" a filesystem fact rather than a policy.

> **Jenkins LTS 2.568.3** · Java 21 minimum · Kubernetes plugin dynamic agents · Kaniko (no Docker socket) · Groovy shared libraries
>
> ⭐ **Why start here if you have a choice:** Jenkins is the only one of the three where **you own everything**. That makes it the most work — and the only one that teaches you what a CI system actually *is*, because nothing is hidden behind a SaaS abstraction. Everything you learn here transfers; almost nothing you learn on a hosted CI teaches you Jenkins.

---

## 📂 The eight files

| # | File | What you will be able to do after it | Time |
|---|---|---|---|
| **0** | [`00-INSTALL-AND-FUNDAMENTALS.md`](./00-INSTALL-AND-FUNDAMENTALS.md) | Install Jenkins on Kubernetes with JCasC, understand the **8 concepts** (controller/agent/executor/job/pipeline/stage/step/credential), run a dynamic pod agent, and scope credentials to folders | 4–5 h |
| **1** | [`01-SCENARIO-1-CI-ONLY.md`](./01-SCENARIO-1-CI-ONLY.md) | ① Build, test, scan, sign and publish a **digest** for all six projects — and **prove** the pipeline cannot deploy (5-point CI-only proof) | 5–6 h |
| **2** | [`02-SCENARIO-2-CASE-1-DELIVERY.md`](./02-SCENARIO-2-CASE-1-DELIVERY.md) | ②🔒 Deploy an existing digest with a **human** `input` gate, `lock`, `milestone`, and an audit record that outlives the build log | 4–5 h |
| **3** | [`03-SCENARIO-2-CASE-2-DEPLOYMENT.md`](./03-SCENARIO-2-CASE-2-DEPLOYMENT.md) | ②🤖 Deploy **fully automatically** with smoke gates, canary analysis against Prometheus, `abort`, auto-rollback and a circuit breaker | 5–6 h |
| **4** | [`04-SCENARIO-3-CI-PLUS-CD.md`](./04-SCENARIO-3-CI-PLUS-CD.md) | ③ Commit → production, in **two folders**, chained by `build job:`, with the shared library that holds both halves | 5–6 h |
| **5** | [`05-PROJECT-DEPLOYMENTS.md`](./05-PROJECT-DEPLOYMENTS.md) | Deploy each of the six projects: FE, BE (Java/Go/Python), FE+BE, polyglot, and ⭐ **MERN** — with the Jenkins-specific wrinkle for each | 6–8 h |
| **6** | [`06-TASKS-AND-INTERVIEW.md`](./06-TASKS-AND-INTERVIEW.md) | ⭐ 20 tasks with **full answers at the END**, plus the Jenkins interview questions that separate 3 YOE from 6 | 4–6 h |

**Read them in order.** Each file assumes the previous one, and `00` is not optional — the credential-scoping model in `00` §7 is what makes files `01`–`04` mean anything.

**Total: ~35 hours to be genuinely dangerous in Jenkins.**

---

## 🎯 What "done" looks like

```
✅ Jenkins 2.568.3 running on Kubernetes, configured ENTIRELY from git (JCasC)
   — no setting was ever clicked in the UI and then lost
✅ Dynamic pod agents that appear per build and disappear after, with
   per-language images sized correctly (Maven 8Gi, Go 2Gi, Node 6Gi)
✅ ⛔ NO Docker socket mounted anywhere — images built with Kaniko
✅ TWO folders, /shop-ci and /shop-cd, with DISJOINT credentials:
     /shop-ci can push images and CANNOT touch the cluster
     /shop-cd can deploy and CANNOT publish an image
✅ A shared library holding buildAndPushImage, deployDigest, readBack
✅ All six projects building: React/nginx, Java/Spring, Go×2, Python, MERN×3
✅ Scenario 1: a 5-point PROOF that CI cannot deploy
✅ Scenario 2 Case 1: a human input gate, a lock, a milestone, a JSONL audit trail
✅ Scenario 2 Case 2: canary + Prometheus analysis + abort + auto-rollback +
   a circuit breaker that stops promotion after N consecutive failures
✅ Scenario 3: commit → production, with the four-check artifact contract
✅ MERN: a real mongod replica set in CI, a migration ledger, a verified backup
✅ A rollback tested, on purpose, in under 60 seconds
✅ Answers to the 20 tasks, and to the interview questions, from memory
```

---

## ⭐ The five Jenkins-specific things that decide whether this works

Everything else is YAML-vs-Groovy translation. These five are *only* true in Jenkins:

### 1 · ⭐⭐ The folder IS the security boundary

```
Jenkins has NO built-in concept of "an environment you may not deploy to".
GitHub has environments. Azure DevOps has Environments + Approvals + Checks.
Jenkins has… folders. And that is enough, IF you use them as a boundary:

   /shop-ci   ← holds ONLY the registry-push credential
              ← the service account has NO Kubernetes RBAC at all
   /shop-cd   ← holds ONLY the cluster credential
              ← the service account CANNOT push an image

⭐ Credentials in Jenkins are SCOPED: global, or per-folder, or per-job.
   A job in /shop-ci physically cannot see a credential defined in /shop-cd.
   That is not a policy someone could widen by mistake — it is a lookup fact.

⛔ THE ANTI-PATTERN: one folder, one job, both credentials.
   Now "CI cannot deploy" is a comment in a Jenkinsfile that a developer
   with write access can delete. Which is exactly the person who would.
```

### 2 · ⛔ There is no Docker socket, and you must not add one

```
The Kubernetes plugin runs your build IN A POD. Mounting /var/run/docker.sock
into that pod gives the build ROOT ON THE NODE — and the build runs your
dependency tree.

⛔ docker.sock = a root shell, from a container executing npm install.

✅ KANIKO: builds an OCI image with no daemon at all.
   --destination=… --digest-file=… --cache=true --cache-repo=…
   --reproducible --image-name-with-digest-file=/workspace/digest.txt
   ⭐ that last flag is how the digest leaves the build without a parse.
```

### 3 · ⭐ `build job:` needs an ABSOLUTE path, plus four guards

```groovy
// ⛔ build job: 'cd-shop-api'          → resolves RELATIVE to the current
//                                          folder; breaks when you move the job
// ✅ build job: '/shop-cd/cd-shop-api'  → absolute from the Jenkins root

// AND the four guards, without which chaining is unsafe:
build job: '/shop-cd/cd-shop-api',
      wait: true,           // ⭐ know whether it succeeded
      propagate: true,      // ⭐ fail THIS build if that one fails
      parameters: [string(name: 'IMAGE_REF', value: env.DIGEST)]
// ⛔ and NEVER rely on the downstream job's "build when upstream finishes"
//   trigger as well — you get two CD runs per commit, racing each other.
```

### 4 · ⭐ Shared libraries beat inline Groovy, and it is not a style preference

```
vars/deployDigest.groovy  ← ONE implementation of the four-check contract
vars/readBack.groovy      ← ONE implementation of the JSONPath name filter
vars/buildAndPushImage.groovy ← ONE Kaniko invocation

WHY IT MATTERS (not cosmetics):
   • inline Groovy in a Jenkinsfile is compiled in the SANDBOX, with the
     script-security plugin rejecting method calls — so you hit
     "RejectedAccessException" and either approve signatures one by one
     (⛔ an admin action per pipeline) or move the code into a library,
     where it is TRUSTED and unrestricted.
   • a library is versioned, reviewed, and used by every job. A fix to
     readBack is one commit, not forty.
   ⭐ In Jenkins, "put it in the shared library" is the answer to a
     SECURITY problem, not just a DRY one.
```

### 5 · ⭐ `readBack` must use the JSONPath NAME FILTER

```groovy
// ⛔ '{.spec.template.spec.containers[0].image}'
//   Index 0 is whichever container the API server returned first. Add a
//   sidecar (Istio, Vault, a logger) and index 0 becomes the SIDECAR.
//   The read-back then verifies the wrong container — and passes.

// ✅ "{.spec.template.spec.containers[?(@.name=='${svc}')].image}"
//   Filter by NAME. Correct with zero containers, one, or five.

⭐ This is CHECK 4 of the artifact contract, and it is the check that catches
  the most common silent CD failure: `kubectl set image` with a mistyped
  container name SUCCEEDS and changes nothing.
```

---

## 🧰 What you need before file `00`

| Need | Check | Note |
|---|---|---|
| Kubernetes cluster | `kubectl cluster-info` | `kind create cluster --name cicd` is enough |
| Helm 3 | `helm version` | Jenkins is installed with a chart |
| Java 21 (**locally, only if you run the controller bare-metal**) | `java -version` | ⭐ LTS 2.568.3 requires Java 21; Java 17 support was dropped in April 2026 |
| `kubectl`, `kind`, `docker` | `kind version` | |
| A container registry | `docker login ghcr.io` | GHCR with a PAT, or ACR, or a local `registry:2` |
| ⭐ 16 GB RAM, 8 CPUs | | the controller + 3 concurrent Maven agents is the real floor |
| `cosign` | `cosign version` | signing, keyless where possible |
| `trivy` | `trivy --version` | image scanning |
| The `shop` repo | | from the Docker/K8s paths — nothing new to write |

**No cloud account needed.** Everything in this folder runs on `kind` with GHCR (free) or a local registry. The AKS/Azure-specific parts are marked and have a local equivalent.

---

## 🗺️ How this folder relates to the rest

| If you want… | Go to |
|---|---|
| The same three scenarios in **GitHub Actions** | [`../github-actions/`](../github-actions/) |
| The same three scenarios in **Azure DevOps** | [`../azure-devops/`](../azure-devops/) |
| The three tools **compared side by side**, scenario by scenario | [`../../08-SCENARIO-DEPLOYMENTS/`](../../08-SCENARIO-DEPLOYMENTS/) |
| The **MERN project spec** this folder deploys | [`../../08-SCENARIO-DEPLOYMENTS/01-MERN-STACK-PROJECT.md`](../../08-SCENARIO-DEPLOYMENTS/01-MERN-STACK-PROJECT.md) |
| ⭐ **Delivery vs Deployment**, and the five prerequisites for Case 2 | [`../../08-SCENARIO-DEPLOYMENTS/scenario-2-cd-only/00-delivery-vs-deployment.md`](../../08-SCENARIO-DEPLOYMENTS/scenario-2-cd-only/00-delivery-vs-deployment.md) |
| The **GitOps end state** (Argo CD), whatever tool you chose | [`../../08-SCENARIO-DEPLOYMENTS/scenario-3-ci-plus-cd/08-gitops-argocd.md`](../../08-SCENARIO-DEPLOYMENTS/scenario-3-ci-plus-cd/08-gitops-argocd.md) |
| The Jenkins deep-dive from the **core CI/CD path** | [`../../04-CASE-3-jenkins.md`](../../04-CASE-3-jenkins.md) |
| CI/CD concepts **from absolute zero** | [`../../01-CICD-GUIDE.md`](../../01-CICD-GUIDE.md) |

⭐ **This folder and `../../04-CASE-3-jenkins.md` are not duplicates.** That file teaches *Jenkins*; this folder teaches *deploying your six projects with Jenkins, in all three scenarios*. Read that one for the tool, this one for the pipelines.

---

## 📐 The conventions used in every file here

```bash
# commands you type
✅ expected output you must see — if it differs, stop and fix it
⛔ the failure mode, and what it means when you see it
⭐ the thing worth remembering — the interview sentence
⭐⭐ the thing worth remembering that will also save you an incident
⚠️ the gotcha that will cost you an hour
🔒 Case 1 — Continuous Delivery, a human decides
🤖 Case 2 — Continuous Deployment, the pipeline decides
```

**Every file ends with tasks, and the answers are at the END** — not inline, not in a separate file, and never before you have tried.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish_Kumar_Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn: https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260
🔗 GitHub: https://github.com/3558Bhk

*Jenkins has no built-in idea of an environment you may not deploy to. So you build one out of folders — and then "CI cannot deploy" is a fact, not an intention.*

</div>
