# ☸️ Kubernetes Learning Path — Zero to Production

> **Prerequisite:** you should be comfortable with Docker first. If `docker build`, `docker run -p`, volumes, and `docker compose` are not yet muscle memory, do the sibling folder [`../docker-learning-path/`](../docker-learning-path/README.md) first — Kubernetes schedules *containers*, so container skills are the floor you stand on.
>
> **This path assumes nothing else.** No cluster experience, no cloud account, no YAML fluency. We start at "what even is a Pod" and end at "I deployed a multi-service app with TLS, autoscaling, monitoring and a rollback plan."

---

## ⚡ In a hurry?

| If you have… | Do this |
|---|---|
| **1 day** | [`00-ONE-DAY-MASTER-PLAN.md`](00-ONE-DAY-MASTER-PLAN.md) — hour-by-hour battle plan |
| **30 minutes** | [`03-CHEATSHEET.md`](03-CHEATSHEET.md) — every command on one page |
| **A job interview tomorrow** | [`00`](00-ONE-DAY-MASTER-PLAN.md) Blocks 1–2 + [`19`](19-KUBECTL-COMPLETE-REFERENCE.md) §"Interview workflows" |
| **A real project to ship** | [`02-CAPSTONE-END-TO-END.md`](02-CAPSTONE-END-TO-END.md) |
| **Everything, in order** | Follow the phases below |

---

## 📁 The files

| # | File | What's inside | Time |
|---|---|---|---|
| 00 | [`00-ONE-DAY-MASTER-PLAN.md`](00-ONE-DAY-MASTER-PLAN.md) | ⚡ Hour-by-hour IST plan: cluster up → workloads → networking → storage → observability → blank-page test → 40-question quiz | 12 h |
| 01 | [`01-KUBERNETES-GUIDE.md`](01-KUBERNETES-GUIDE.md) | The foundation: architecture, Pods, Deployments, Services, ConfigMaps/Secrets, storage, networking, probes, RBAC, autoscaling, Helm, troubleshooting | 4–6 h read |
| 02 | [`02-CAPSTONE-END-TO-END.md`](02-CAPSTONE-END-TO-END.md) | 🎓 Full production deployment of a 3-tier app: namespaces, manifests, Ingress+TLS, HPA, PDB, NetworkPolicy, ServiceMonitor, CI/CD, GitOps, runbook | 6–8 h |
| 03 | [`03-CHEATSHEET.md`](03-CHEATSHEET.md) | One-page `kubectl` + YAML reference | 10 min |
| 04 | [`04-PROJECT-1-first-pod.md`](04-PROJECT-1-first-pod.md) | Your first Pod, `kubectl` fundamentals, debugging CrashLoopBackOff | 1.5 h |
| 05 | [`05-PROJECT-2-deployment-service.md`](05-PROJECT-2-deployment-service.md) | Deployments, ReplicaSets, rolling updates, Services, port-forward | 2 h |
| 06 | [`06-PROJECT-3-config-secrets.md`](06-PROJECT-3-config-secrets.md) | ConfigMaps, Secrets, env vs volume mounting, immutable configs | 2 h |
| 07 | [`07-PROJECT-4-jobs-cronjobs-cli.md`](07-PROJECT-4-jobs-cronjobs-cli.md) | Jobs, CronJobs, init containers, sidecars, one-shot tasks & DB migrations | 2 h |
| 08 | [`08-PROJECT-5-storage-statefulset.md`](08-PROJECT-5-storage-statefulset.md) | PV/PVC/StorageClass, StatefulSets, headless Services, backup & restore | 2.5 h |
| 09 | [`09-PROJECT-6-ingress-tls.md`](09-PROJECT-6-ingress-tls.md) | Ingress, ingress-nginx, host/path routing, cert-manager, real TLS | 2.5 h |
| 10 | [`10-PROJECT-7-observability.md`](10-PROJECT-7-observability.md) | metrics-server, `kubectl top`, Prometheus + Grafana, cAdvisor, logging, events | 3 h |
| 11 | [`11-PROJECT-8-react-frontend.md`](11-PROJECT-8-react-frontend.md) | 🔵 React SPA on K8s — Case 1 simple, Case 2 production (nginx tuning, SPA routing, CDN caching) | 2 h |
| 12 | [`12-PROJECT-9-java-backend.md`](12-PROJECT-9-java-backend.md) | 🔵 Spring Boot on K8s — JVM container awareness, Actuator probes, graceful shutdown | 2.5 h |
| 13 | [`13-PROJECT-10-react-java-fullstack.md`](13-PROJECT-10-react-java-fullstack.md) | 🔵 React + Java full-stack, CORS vs Ingress routing, NetworkPolicies | 2 h |
| 14 | [`14-PROJECT-11-react-python-fullstack.md`](14-PROJECT-11-react-python-fullstack.md) | 🔵 React + FastAPI, HPA on custom metrics, KEDA-style scaling | 2 h |
| 15 | [`15-PROJECT-12-react-go-fullstack.md`](15-PROJECT-12-react-go-fullstack.md) | 🔵 React + Go, tiny images, PDBs, topology spread, resource tuning | 2 h |
| 16 | [`16-PROJECT-13-databases.md`](16-PROJECT-13-databases.md) | 🔵 Postgres, MySQL, MongoDB, Redis, Cassandra, Neo4j — each as its own mini-project with StatefulSets, backups, and "should you even do this?" | 5 h |
| 17 | [`17-PROJECT-14-helm-gitops.md`](17-PROJECT-14-helm-gitops.md) | 🔵 Helm charts from scratch, values per environment, Argo CD GitOps, kustomize | 3 h |
| **18** | [`18-PROJECT-15-mern-stack.md`](18-PROJECT-15-mern-stack.md) | 🟣 ⭐ **MERN on Kubernetes** — React + Node/Express + **MongoDB as a replica-set StatefulSet**, the migration as a gated Job, the backup as a verified CronJob, and the three-probe split that stops a mongo election from restart-looping your fleet | 4–5 h |
| 19 | [`19-KUBECTL-COMPLETE-REFERENCE.md`](19-KUBECTL-COMPLETE-REFERENCE.md) | 📖 The complete `kubectl` + real-time troubleshooting reference (interview-grade) | reference |

**Total:** ~19 files, ~35–45 hours of hands-on work if you do every task.

---

## 🧭 The learning order

### Phase 0 — Setup (30 min, do this first, don't skip)

You need **one** local cluster. Pick one:

```bash
# Option A: kind — fastest, cleanest, best for CI (RECOMMENDED to start)
kind create cluster --name k8s --config kind-config.yaml

# Option B: minikube — most addons built in, best driver support
minikube start --cpus=4 --memory=8192 --driver=docker

# Option C: k3d — lightest on RAM, great on laptops
k3d cluster create learn --servers 1 --agents 2
```

Full instructions with troubleshooting → [`01-KUBERNETES-GUIDE.md` § 0](01-KUBERNETES-GUIDE.md).

### Phase 1 — Core objects (Projects 1–4)

`04` → `05` → `06` → `07`. After this phase you can deploy a stateless app, configure it, and run batch work. **This is 70% of daily Kubernetes work.**

### Phase 2 — State and traffic (Projects 5–6)

`08` → `09`. Storage and Ingress are where most people get stuck — the guides include the exact "why is my PVC Pending / why is my EXTERNAL-IP `<pending>`" answers.

### Phase 3 — Operations (Project 7 + CLI reference)

`10` + skim `18`. Now you can *see* what your cluster is doing and debug it under pressure.

### Phase 4 — Real stacks (Projects 8–14)

`11` → `17`. Pick the one matching your job's stack; do all of them if you have time. Every one has **Case 1 (simple)** and **Case 2 (production-grade)**.

### Phase 5 — Capstone

`02`. Deploy everything together the way a real team would, including CI/CD, GitOps, and an on-call runbook.

---

## 🎯 What "done" looks like

You can, without notes:

- [ ] Explain what happens between `kubectl apply -f deploy.yaml` and a Pod serving traffic
- [ ] Create a Deployment, scale it, roll it back, and prove zero downtime
- [ ] Choose correctly between `ClusterIP`, `NodePort`, `LoadBalancer`, `Ingress`, and `port-forward`
- [ ] Mount a ConfigMap as env **and** as files; create a Secret without putting it in Git
- [ ] Make a PVC bind, and debug it when it stays `Pending`
- [ ] Write liveness / readiness / startup probes that are actually correct (and explain why a wrong readiness probe causes an outage)
- [ ] Set requests/limits that don't get your Pod OOMKilled or evicted
- [ ] Read `kubectl describe pod` output and name the root cause in under 60 seconds
- [ ] Build a Helm chart with dev/staging/prod values
- [ ] Explain StatefulSet vs Deployment out loud, with a concrete example of each

If all ten boxes are ticked, you are employable as a Kubernetes-literate engineer. The capstone is the proof.

---

## 🛠 Tools used in this path

| Tool | Version used | Why |
|---|---|---|
| Kubernetes | v1.35 / v1.36 / v1.37 (all manifests compatible) | Current stable line as of Sep 2026 — v1.37 "Garhwal" released 26 Aug 2026 |
| `kubectl` | within ±1 minor of your cluster | The only tool you truly need |
| kind | latest | Fast multi-node clusters from containers |
| minikube | latest | Best addon ecosystem (`ingress`, `metrics-server`) |
| Helm | v3.x | The de-facto package manager |
| ingress-nginx | v1.13+ | The reference Ingress controller |
| cert-manager | v1.18+ | Real TLS certificates, automated |
| Prometheus / Grafana | kube-prometheus-stack | The standard monitoring bundle |
| Argo CD | latest | GitOps continuous delivery |
| k9s | latest | Terminal UI — install it, you'll love it |

> **Version skew rule:** `kubectl` may be ±1 minor version from the API server. `kubelet` may be up to 3 minor versions *older* than the API server, never newer. Keep them close.

---

## ⚠️ Rules of the road

1. **Everything is YAML, and YAML is unforgiving.** Two-space indent, no tabs, ever. If `kubectl apply` says `error converting YAML to JSON`, it's almost always indentation.
2. **Never use `latest` as an image tag in a Deployment.** Kubernetes caches it and you will not get the update you think you pushed. Pin versions.
3. **`kubectl delete` is instant and merciless.** There is no trash can. Use `kubectl apply --dry-run=client -o yaml` first, and keep everything in Git.
4. **Read the events.** `kubectl describe <thing>` and `kubectl get events -A --sort-by=.lastTimestamp` answer ~80% of "why isn't this working".
5. **Requests and limits are not optional in production.** A Pod without requests is a Pod the scheduler places blindly.

---

**Start here → [`00-ONE-DAY-MASTER-PLAN.md`](00-ONE-DAY-MASTER-PLAN.md) if you have one day, or [`01-KUBERNETES-GUIDE.md`](01-KUBERNETES-GUIDE.md) if you want the foundation first.**

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
