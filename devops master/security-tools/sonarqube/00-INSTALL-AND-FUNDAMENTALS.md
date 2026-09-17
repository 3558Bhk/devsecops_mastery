# 🟣 SonarQube 00 · Install and Fundamentals
### The server/scanner architecture, the four internal components, the edition matrix that decides what you can actually do, and a production-shaped install — Docker and Helm — with PostgreSQL, correct JVM sizing, and the upgrade warning that will save your history.

> **WHAT this file is:** the foundation for the SonarQube course. Why SonarQube is a **server** and not a CLI, what an "analysis" actually is, what the four components do, and how to install it so it survives.
>
> **WHY this tool is structurally different from Trivy and Checkov:** those two are **stateless scanners** — run, report, exit. SonarQube is **a database of your code's history** with a scanner attached. That history is the entire product: it is what makes trends, the Quality Gate ratchet, and "is this repo getting better?" possible. It is also what makes installation, upgrades and backups a real engineering problem instead of a `curl`.
>
> **TARGET:** SonarQube running with PostgreSQL, a completed first analysis, and a clear-eyed understanding of which features your edition actually has — before you design a process around a feature you cannot use.
>
> **Time:** 4 hours.

---

## 📇 Contents

| § | What |
|---|---|
| [1](#1--version-anchors--and--the-two-things-that-changed-in-2026) | ⭐ Version anchors, and **the two things that changed in 2026** |
| [2](#2---the-architecture-server--scanner-four-components) | ⭐⭐ The architecture: server + scanner, four components |
| [3](#3---the-edition-matrix--what-you-actually-cannot-do) | ⭐⭐ The edition matrix — **what you actually cannot do** |
| [4](#4--what-an-analysis-is--the-lifecycle-step-by-step) | What an *analysis* is — the lifecycle, step by step |
| [5](#5--install-with-docker) | Install with Docker |
| [6](#6---install-on-kubernetes-with-helm--production-shaped) | ⭐ Install on Kubernetes with Helm — production-shaped |
| [7](#7--first-login-and-first-project) | First login and first project |
| [8](#8--sizing-resources-and-the-heap-numbers-that-matter) | Sizing, resources, and the heap numbers that matter |
| [9](#9---tasks) | 🔨 Tasks — **answers at the END** |

---

## 1 · Version anchors — and ⭐ the two things that changed in 2026

| Component | Version | Verified | Notes |
|---|---|---|---|
| **SonarQube Server** | **2026.4.1** | 2026-08-07 | the commercial line — supportable long term |
| **SonarQube Community Build** | **26.9.0.129388** | 2026-09-02 | ⭐ monthly rolling train |
| **SonarQube Helm chart** | **2026.4.1** | 2026-08-07 | `community.enabled: true` → Community Build |
| **Database** | **PostgreSQL** | — | ⛔ embedded H2 is **not** for production |
| **Server JVM** | **Java 17 or 21** | — | 2026.x dropped older JVMs |
| **Compute-engine heap** | **1536M** (Community/Developer) · **5G** (Enterprise) | — | official production guidance |

### ⛔⛔ Change 1 — "Community Edition" no longer exists

It was replaced by the **SonarQube Community Build**, on a **monthly release train where each version is supported for exactly one month**:

| Release | Released | Support ended |
|---|---|---|
| 26.9 | 2026-09-02 | — *(current)* |
| 26.8 | 2026-08-05 | **2026-09-02** — the day 26.9 shipped |
| 26.7 | 2026-07-08 | 2026-08-05 |
| 26.6 | 2026-06-03 | 2026-07-08 |

⭐ **Three consequences you must plan for, not discover:**

1. **There is no LTS for Community Build.** If you need a version you can sit on for two years, you need **SonarQube Server**. That is a procurement decision, and it is far cheaper to make before you have 40 repositories wired up than after.
2. **You either upgrade monthly or you run unsupported.** A Community Build instance three months behind is running a version whose support ended eight weeks ago. Bugs and CVEs in it will not be patched.
3. **Upgrades are not trivial** — see change 2.

### ⛔⛔ Change 2 — the upgrade path needs intermediate hops, and there is no way back

Documented real paths:

```
25.9.0.x  →  26.3.0.x                                    (direct)
25.9.0.x  →  25.12.0.x  →  26.3.0.x                      (one intermediate)
10.6      →  24.12.0.100206  →  25.4.0.x                 (one intermediate)
9.9 LTA   →  24.12.0.100206  →  25.4.0.x                 (one intermediate)
8.9 LTA   →  9.9 LTA  →  24.12.0.100206  →  25.4.0.x     (two intermediates)
```

And because of **database-migration problems in the December 2025 release (25.12.0.117093)**, **26.1.0.118079** is sometimes required as an additional intermediate step.

> ⭐⭐ **The structural reason this is scary: SonarQube migrates its database schema in place, and there is no down-migration.** Once you start a newer version against a database, that database belongs to the newer version. If the migration fails halfway, you do not roll back — you **restore from backup**.
>
> So the operational rule is not "be careful", it is mechanical:
> - **back up PostgreSQL before every upgrade**, every time, no exceptions;
> - **verify the restore works** before you start — a backup you have never restored is a hypothesis;
> - **use the official update-path calculator**, not a remembered version number;
> - **never skip more than the documented path allows.**
>
> File [`06-PRODUCTION-OPERATION.md`](06-PRODUCTION-OPERATION.md) writes the whole procedure out. This section exists so you do not design a Community Build rollout and only learn about monthly forced migrations in month three.

---

## 2 · ⭐⭐ The architecture: server + scanner, four components

⛔ **The single most common misconception:** people expect SonarQube to be a CLI like Trivy or Checkov — point it at code, get a report. It is not. **There is a long-running server, and the scanner is a client that uploads to it.**

```
        YOUR CI RUNNER                                THE SONARQUBE SERVER
   ┌──────────────────────────────┐            ┌──────────────────────────────────┐
   │  1. build + run tests        │            │  ┌────────────────────────────┐  │
   │     → JaCoCo / lcov report   │            │  │ WEB SERVER  (sonar.web.*)  │  │
   │                              │            │  │ UI + REST API     :9000    │  │
   │  2. the SCANNER              │            │  └──────────┬─────────────────┘  │
   │     ├─ parses source         │            │             │                    │
   │     ├─ runs the analysers    │            │  ┌──────────▼─────────────────┐  │
   │     ├─ computes measures     │            │  │ COMPUTE ENGINE (sonar.ce.*)│  │
   │     └─ ⭐ UPLOADS a report   │──HTTP POST─┼─▶│ processes reports          │  │
   │                              │            │  │ asynchronously, in a QUEUE │  │
   │  3. scanner EXITS            │            │  └──────────┬─────────────────┘  │
   │     ⛔ before the analysis   │            │             │                    │
   │        is even processed     │            │  ┌──────────▼─────────────────┐  │
   └──────────────────────────────┘            │  │ SEARCH SERVER              │  │
                                               │  │ (sonar.search.*)           │  │
        sonar-scanner / mvn sonar:sonar        │  │ Elasticsearch — indexes    │  │
        gradle sonar / dotnet sonarscanner     │  │ issues for fast querying   │  │
        npx sonar-scanner                      │  └──────────┬─────────────────┘  │
                                               │             │                    │
                                               │  ┌──────────▼─────────────────┐  │
                                               │  │ POSTGRESQL                 │  │
                                               │  │ ⭐ the product. history,   │  │
                                               │  │ trends, gates, debt        │  │
                                               │  └────────────────────────────┘  │
                                               └──────────────────────────────────┘
```

### The four components, and what breaks when each one is sick

| Component | Property prefix | What it does | The symptom when it is wrong |
|---|---|---|---|
| **Web server** | `sonar.web.*` | The UI and the **REST API** on `:9000`. Receives scanner reports, serves dashboards | UI slow or 502s; API calls time out; ⛔ but scanners may still "succeed" |
| **Compute Engine (CE)** | `sonar.ce.*` | ⭐ **Processes reports asynchronously.** Takes the uploaded report, computes measures, applies the Quality Gate, writes to the DB and the index. Runs as a **queue of background tasks** | ⭐⭐ **The #1 support problem.** Scanner exits 0, and *nothing changes on the dashboard* — because the task is queued, failed, or stuck. **Administration → Background Tasks** is the page |
| **Search server** | `sonar.search.*` | Embedded **Elasticsearch**. Indexes issues so the UI can query millions of them fast | Issues page is slow or empty while the overview shows correct numbers — DB has the data, the index does not |
| **PostgreSQL** | `sonar.jdbc.*` | ⭐ **The product.** Every analysis, every trend point, every debt record, every gate decision | Everything. And **there is no down-migration**, so a bad upgrade is a restore-from-backup |

> ⭐⭐ **Why the CE queue is the thing to internalise.** The scanner's job ends at *upload*. The verdict you care about — did the Quality Gate pass? — is computed **later**, by a different process, possibly minutes later, possibly never if it fails.
>
> That is why **`sonar.qualitygate.wait=true`** exists (§7) and why it is the single most important scanner flag in CI: it makes the scanner **block until the CE finishes** and then exit non-zero if the gate failed. Without it, your CI step is green while the analysis is still queued, and the gate is decorative.

### Where the scanner lives, per language

| Language / build | Scanner | Command |
|---|---|---|
| **Java, Maven** | Maven plugin | `mvn verify sonar:sonar -Dsonar.token=… -Dsonar.host.url=…` |
| **Java, Gradle** | Gradle plugin | `./gradlew build sonar -Dsonar.token=…` |
| **Generic / Python / Go / JS / PHP / …** | **`sonar-scanner` CLI** | `sonar-scanner -Dsonar.projectKey=… -Dsonar.sources=. …` |
| **JavaScript / TypeScript** | npm wrapper | `npx sonar-scanner` (or the `sonarqube-scanner` package) |
| **.NET / C#** | ⭐ `dotnet sonarscanner` | **three-step**: `begin` → `dotnet build` → `end` |
| **C / C++ / Objective-C** | `build-wrapper` | ⭐ wraps the compiler to capture exact flags |

> ⭐ **The .NET and C/C++ models are different in a way that matters.** Most scanners *parse* source. Those two **wrap your actual build**, because the analysis needs the real compiler invocation — include paths, defines, optimisation flags — to know what the code actually means. Hence `begin` → build → `end` for .NET, and `build-wrapper` for C/C++. If you run the plain CLI on a C# solution you get partial or no results, and the failure is silent.

---

## 3 · ⭐⭐ The edition matrix — what you actually cannot do

⛔ **Read this before you design any process.** The most expensive mistake in this folder is building a workflow around a feature your edition does not have, and discovering it in week six.

| Capability | **Community Build** (free) | **Developer** | **Enterprise** | **Data Center** |
|---|---|---|---|---|
| Core analysis: bugs, smells, vulnerabilities, hotspots, coverage, duplication | ✅ | ✅ | ✅ | ✅ |
| Quality Gate + Quality Profiles | ✅ | ✅ | ✅ | ✅ |
| History & trends on the **main branch** | ✅ | ✅ | ✅ | ✅ |
| ⛔ **Branch analysis** (analyse `feature/x`, not just `main`) | ❌ | ✅ | ✅ | ✅ |
| ⛔ **Pull-request analysis + PR decoration** (findings on the PR diff) | ❌ | ✅ | ✅ | ✅ |
| ⛔ **Taint analysis** (dataflow from source to sink — real injection detection) | ❌ | ✅ | ✅ | ✅ |
| Some language analysers (C/C++, Objective-C, Swift, ABAP, PL/SQL, T-SQL…) | ❌ | ⚠️ partial | ✅ | ✅ |
| **Portfolios**, cross-project rollups | ❌ | ❌ | ✅ | ✅ |
| **High availability** / horizontal scaling | ❌ | ❌ | ❌ | ✅ |
| Support horizon | ⛔ **one month per release** | commercial | commercial | commercial |

### ⭐⭐ The three lines that change your design

**1. Community Build analyses `main` only. There is no branch analysis and no PR analysis.**

> **Consequence:** the workflow *"run SonarQube on the pull request and decorate it with findings on the diff"* — the workflow everyone wants, and the workflow that actually changes developer behaviour — **is not available on the free edition.**
>
> On Community Build your options are:
> - analyse after merge to `main`, and accept that the feedback arrives *after* the code is merged;
> - gate the **CI build** on the Quality Gate result computed from the merge commit — but the analysis still represents `main`, and `sonar.projectKey` stays one key per repo;
> - ⛔ do **not** try to fake it by setting `sonar.branch.name` — the property is rejected or ignored, and you will spend a day discovering why.
>
> ⭐ **This is a budget conversation, not a technical one.** If PR-level feedback is a requirement — and for most teams it should be, because it is the difference between a finding someone fixes and a finding someone reads — then **Developer edition is the entry price of a working SonarQube programme**, and Trivy + Checkov (both free, both PR-capable via SARIF) will carry more of the load than you planned.

**2. Taint analysis is edition-gated.**

Taint analysis is the dataflow engine that follows a value from an untrusted **source** (`request.getParameter`, `req.body`, an environment variable) through **sanitisers** to a dangerous **sink** (`Statement.execute`, `Runtime.exec`, a file path). That is how you find a real SQL injection or command injection rather than a suspicious-looking string.

⛔ **On Community Build you get pattern-based vulnerability detection, not taint tracking.** So "SonarQube found no injection vulnerabilities" on the free edition is **not evidence that there are none** — it is evidence that the engine that looks for them did not run.

**3. One month of support per Community Build release.**

Plan for a monthly upgrade with a database migration, or accept running unsupported. §1.

### How to check what you are actually running

```bash
curl -s -u "$SONAR_TOKEN:" "$SONAR_HOST/api/system/status" | jq
curl -s -u "$SONAR_TOKEN:" "$SONAR_HOST/api/editions/show_details" | jq   # if available
# or: Administration → System, and the footer of any page
```

⭐ Write it down in your runbook. "We have SonarQube" is not a specification.

---

## 4 · What an *analysis* is — the lifecycle, step by step

Understanding this sequence explains almost every confusing behaviour.

```
①  The scanner PARSES your source with the language analysers.
      → an AST per file, per language

②  It runs the RULES from the active Quality Profile over that AST.
      → issues: bug / vulnerability / code smell / security hotspot
      → each with a file, a line, a rule key, a severity

③  It reads your TEST COVERAGE REPORT (JaCoCo XML, lcov, cobertura…)
      ⭐ SonarQube does NOT run your tests. It imports the report your build produced.

④  It computes MEASURES: lines of code, complexity, duplication, coverage %,
      comment %, file count.

⑤  It bundles ②③④ into a REPORT and POSTs it to the server.
      → the scanner's job is now DONE. It exits.

⑥  The COMPUTE ENGINE picks the report off its queue (Administration → Background Tasks).
      → recomputes, resolves, deduplicates, applies "new code" definition

⑦  The QUALITY GATE is evaluated against the computed measures.
      → status: OK | WARN | ERROR | NONE

⑧  Results are written to PostgreSQL and indexed into Elasticsearch.
      → the dashboard now reflects this analysis

⑨  ⭐ Only NOW is there a verdict your CI can act on.
```

### ⭐ The four consequences worth memorising

**1. Coverage is imported, not measured.** If your dashboard says 0% coverage, **the report path is wrong** — it is almost never a SonarQube bug. Check `sonar.coverage.jacoco.xmlReportPaths` (or `sonar.javascript.lcov.reportPaths`) and confirm the file exists at analysis time.

**2. The scanner exiting 0 does not mean the gate passed.** Step ⑤ happens before step ⑦. **`sonar.qualitygate.wait=true`** closes that gap.

**3. "The analysis succeeded but nothing changed" = step ⑥.** Go to **Administration → Background Tasks.** You will find one of: *pending* (queued behind others), *failed* (with a stack trace), or *success* but for a different project key than you think.

**4. Two analyses of the same commit can differ.** If the Quality Profile or the "new code" definition changed between them, the verdict changes even though the code did not. ⭐ Profiles are server-side and versioned — a change there silently rewrites the meaning of every future analysis.

---

## 5 · Install with Docker

The fastest route to a working server. ⛔ **Fine for learning; not for production** — see §6 for that.

```bash
# ⭐ SonarQube needs specific kernel settings for its embedded Elasticsearch.
#    Without these the search server refuses to start and the container crash-loops
#    with a confusing "max virtual memory areas vm.max_map_count [65530] is too low".
sudo sysctl -w vm.max_map_count=524288
sudo sysctl -w fs.file-max=131072
ulimit -n 131072

# make it survive a reboot
echo -e "vm.max_map_count=524288\nfs.file-max=131072" | sudo tee -a /etc/sysctl.d/99-sonarqube.conf

# PostgreSQL — ⛔ never the embedded H2 for anything that matters
docker network create sonar-net

docker run -d --name sonar-db --network sonar-net \
  -e POSTGRES_USER=sonar \
  -e POSTGRES_PASSWORD="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)" \
  -e POSTGRES_DB=sonarqube \
  -v sonar-db-data:/var/lib/postgresql/data \
  postgres:16-alpine

# ⭐ pin by DIGEST, same discipline as every tool in this folder
docker run -d --name sonarqube --network sonar-net -p 9000:9000 \
  -e SONAR_JDBC_URL=jdbc:postgresql://sonar-db:5432/sonarqube \
  -e SONAR_JDBC_USERNAME=sonar \
  -e SONAR_JDBC_PASSWORD=<the password above> \
  -v sonar-data:/opt/sonarqube/data \
  -v sonar-extensions:/opt/sonarqube/extensions \
  -v sonar-logs:/opt/sonarqube/logs \
  sonarqube:community
```

```bash
# watch it come up — the four components start in order
docker logs -f sonarqube
```

```
--> Elasticsearch … started
--> Compute Engine … started
--> Web Server … started
--> SonarQube is operational
```

⭐ **Startup takes 1–3 minutes.** People restart it at 40 seconds and conclude it is broken. Watch the log, not the clock.

| Volume | Why it matters |
|---|---|
| `sonar-data` | ⭐ **contains the Elasticsearch index.** Losing it forces a full reindex |
| `sonar-extensions` | **your plugins.** Losing them silently changes analysis behaviour |
| `sonar-logs` | where you diagnose a failed background task |
| *(the DB)* | ⭐⭐ **the actual product.** Everything else is derivable; this is not |

> ⚠️ **The Community Build image tag moves monthly.** `sonarqube:community` resolves to whatever is current. For anything reproducible, pin a specific build number tag **and** verify the digest — and remember §1: that version stops being supported in a month.

---

## 6 · ⭐ Install on Kubernetes with Helm — production-shaped

This is the form you would actually run. It also exercises [`../../helm-charts-mastery/`](../../helm-charts-mastery/README.md) directly.

```bash
helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube
helm repo update sonarqube

# ⭐ read the defaults for YOUR pinned version before writing any values
helm show chart sonarqube/sonarqube --version 2026.4.1 | grep -E '^(version|appVersion|kubeVersion):'
helm show values sonarqube/sonarqube --version 2026.4.1 > values-default.yaml
wc -l values-default.yaml
```

### 6.1 The external database — ⛔ do not use the bundled one

The chart ships a PostgreSQL **subchart**. It is fine for a trial and wrong for production: its lifecycle is tied to your SonarQube release, so `helm uninstall` takes the database with it, and its defaults are not sized or backed up.

```bash
# provision PostgreSQL yourself — managed (RDS/Cloud SQL) or a properly operated
# StatefulSet with backups. Then point SonarQube at it:
kubectl -n sonarqube create secret generic sonar-jdbc \
  --from-literal=jdbc-url='jdbc:postgresql://sonar-db.internal:5432/sonarqube' \
  --from-literal=jdbc-username='sonar' \
  --from-literal=jdbc-password="$(openssl rand -base64 24 | tr -d '/+=' | head -c 24)"
```

### 6.2 `values.yaml`

```yaml
# ⭐ Community Build, not Server
community:
  enabled: true
  # buildNumber: "26.9.0.129388"    # ⭐ pin explicitly — don't inherit "latest"

# ⛔ disable the bundled database
postgresql:
  enabled: false

# ⭐ use the external one, via the Secret from §6.1 — never plaintext in values
jdbcOverwrite:
  enable: true
  jdbcUrl:      "jdbc:postgresql://sonar-db.internal:5432/sonarqube"
  jdbcUsername: "sonar"
  jdbcSecretName: sonar-jdbc          # ⭐ password from the Secret
  jdbcSecretKey:  jdbc-password

# ── ⭐⭐ Elasticsearch bootstrap checks. LEAVE TRUE IN PRODUCTION ──────────
# false disables ES's own safety checks so it will start on a misconfigured
# host. It "fixes" a crashloop by removing the guardrail. ⛔ Don't.
elasticsearch:
  bootstrapChecks: true
  # ⭐ ES refuses to start unless vm.max_map_count is high enough on the NODE.
  #    That is a node/kernel setting — set it via a DaemonSet or node config,
  #    not here. On GKE/EKS this is the #1 install failure.

# ── JVM sizing. §8 explains every number ──────────────────────────────────
sonarProperties:
  sonar.web.javaAdditionalOpts: "-Xms1g -Xmx1g"
  sonar.ce.javaAdditionalOpts:  "-Xms1536m -Xmx1536m"    # ⭐ official CE guidance
  sonar.search.javaAdditionalOpts: "-Xms1g -Xmx1g"
  # ⭐ force HTTPS-only cookies behind a TLS-terminating ingress
  sonar.web.host: 0.0.0.0
  sonar.forceAuthentication: true

# ── Resources: requests drive scheduling, limits prevent node pressure ────
resources:
  requests: { cpu: 500m, memory: 3Gi }
  limits:   { cpu: "2",  memory: 6Gi }

# ── Persistence — data (ES index), extensions (plugins), logs ─────────────
persistence:
  enabled: true
  size: 20Gi
  # storageClassName: gp3-ssd
  accessMode: ReadWriteOnce
  annotations: {}

# ⭐ A readiness probe that actually reflects readiness. SonarQube takes
#    1–3 minutes to boot; a tight probe restart-loops it forever.
readinessProbe:
  initialDelaySeconds: 90
  periodSeconds: 15
  timeoutSeconds: 5
  failureThreshold: 8
livenessProbe:
  initialDelaySeconds: 120
  periodSeconds: 20
  timeoutSeconds: 5
  failureThreshold: 10
startupProbe:
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 30              # ⭐ 30 × 10s = 5 minutes of boot allowed

# ── ⛔ NO ingress here. SonarQube has no rate limiting and holds tokens.
#    Put it behind your own authenticated proxy. See §6.4
ingress:
  enabled: false

# ⭐ Monitoring SonarQube itself — it exposes Prometheus metrics
prometheusMonitoring:
  podMonitor:
    enabled: true                   # needs kube-prometheus-stack
                                    # → ../../prometheus-in-kubernetes/

account:
  # ⛔ never set adminPassword here. Rotate after first login, or use SSO.
  adminPassword: ""

# ── The init container that sets vm.max_map_count on the node ─────────────
initSysctl:
  enabled: true                     # ⭐ requires privileged init — check your PSP/PSA
  vmMaxMapCount: 524288
```

### 6.3 Install and verify

```bash
kubectl create namespace sonarqube

helm upgrade --install sonarqube sonarqube/sonarqube \
  --version 2026.4.1 \
  --namespace sonarqube \
  -f values.yaml \
  --wait --timeout 15m --atomic

kubectl -n sonarqube get pods,pvc
kubectl -n sonarqube logs deploy/sonarqube-sonarqube --tail=50 | grep -iE 'started|operational|error'
```

```bash
# the health endpoint — what your probe should really be checking
kubectl -n sonarqube port-forward svc/sonarqube-sonarqube 9000:9000
curl -s localhost:9000/api/system/status | jq
```

```json
{ "id": "…", "version": "26.9.0.129388", "status": "UP" }
```

⭐ **`status` transitions:** `STARTING` → `UP`. While `STARTING`, the API is partially available and the scanner will get confusing errors. Wait for `UP`.

### 6.4 ⭐ Two production settings people get wrong

**① `vm.max_map_count` is a NODE setting, not a container setting.**

Elasticsearch will not start below `262144`. The chart's `initSysctl` runs a **privileged** init container to set it — which may be blocked by Pod Security Admission, and which **does not survive a node reboot** unless your node image or a DaemonSet sets it.

```bash
# verify it on the node, not in the pod
kubectl debug node/<node> -it --image=busybox -- sysctl vm.max_map_count
```

The failure looks like: pod `CrashLoopBackOff`, log line `max virtual memory areas vm.max_map_count [65530] is too low, increase to at least [262144]`. ⭐ It names the fix, and people still spend an afternoon on it because they look inside the container.

**② Do not put a bare Ingress in front of SonarQube.**

SonarQube holds **analysis tokens**, **source code excerpts**, and **every issue in your codebase** — a map of where your vulnerabilities are. It has no rate limiting and its default auth is `admin/admin`.

Put it behind an authenticating reverse proxy (OAuth2-proxy, your ingress controller's auth, an identity-aware proxy) and **enforce `sonar.forceAuthentication: true`** so anonymous read access is off. File [`04-KUBERNETES-AND-INFRA.md`](04-KUBERNETES-AND-INFRA.md) does this properly with TLS and SSO.

---

## 7 · First login and first project

### 7.1 Log in and change the password

```
http://localhost:9000    →    admin / admin
                          →    it forces a password change. ✅ good.
```

### 7.2 Create a token — ⭐ the right kind

**My Account → Security → Generate Tokens.** There are several types and the choice matters:

| Token type | Scope | Use for |
|---|---|---|
| **User token** | everything that user can do | ⛔ never in CI — it is a person's full access, and it breaks when they leave |
| **Global Analysis token** | analyse any project | a central CI system with many repos |
| ⭐ **Project Analysis token** | **one project only** | ⭐ **the default choice.** Least privilege, and revoking it affects one repo |
| **Branch Analysis token** | one project's branches | ⚠️ **edition-gated** — §3 |

```bash
export SONAR_TOKEN=sqp_…                       # project analysis token
export SONAR_HOST=http://sonarqube.internal:9000
```

⭐ Store it as a CI **secret**, scoped to the repository. ⛔ Never in `sonar-project.properties` — that file is committed, and a token in git is a leaked credential with a history.

### 7.3 First analysis — generic project

```properties
# sonar-project.properties  ← COMMITTED, no secrets
sonar.projectKey=shop-api
sonar.projectName=shop-api
sonar.projectVersion=1.4.2

sonar.sources=src/main/java
sonar.tests=src/test/java
sonar.java.binaries=target/classes
sonar.sourceEncoding=UTF-8

# ⭐ coverage is IMPORTED (§4 step ③) — point at the report your build produced
sonar.coverage.jacoco.xmlReportPaths=target/site/jacoco/jacoco.xml

# ⛔ do not analyse generated or vendored code
sonar.exclusions=**/generated/**,**/*.min.js,node_modules/**

# ⭐⭐ THE MOST IMPORTANT FLAG IN CI
sonar.qualitygate.wait=true
```

```bash
mvn clean verify sonar:sonar \
  -Dsonar.host.url=$SONAR_HOST \
  -Dsonar.token=$SONAR_TOKEN
```

⭐ **`sonar.qualitygate.wait=true`** makes the scanner **block until the Compute Engine finishes** (§4 step ⑥–⑦) and then **exit non-zero if the gate failed**. Without it, the scanner exits 0 immediately after upload, your CI step is green, and the gate verdict arrives minutes later to an audience of nobody. **This one property is the difference between a Quality Gate that enforces and one that reports.**

### 7.4 Or gate via the API — when `wait` is not enough

```bash
curl -s -u "$SONAR_TOKEN:" \
  "$SONAR_HOST/api/qualitygates/project_status?projectKey=shop-api" \
  | jq -r '.projectStatus.status'
# OK | WARN | ERROR | NONE
```

```bash
STATUS=$(curl -sf -u "$SONAR_TOKEN:" "$SONAR_HOST/api/qualitygates/project_status?projectKey=shop-api" | jq -r '.projectStatus.status')
[ "$STATUS" = "OK" ] || { echo "⛔ Quality Gate: $STATUS"; exit 1; }
```

⭐ Use this when you need the **specific failing conditions** (to post them as a PR comment), or when your scanner cannot block. Both patterns are in [`03-CI-CD-INTEGRATION.md`](03-CI-CD-INTEGRATION.md).

---

## 8 · Sizing, resources, and the heap numbers that matter

### 8.1 The official heap guidance

| Edition | **Sum of `Xmx`** |
|---|---|
| Community Build | **1536M** |
| Developer | **1536M** |
| Enterprise | **5G** |

That number is the **sum across the three JVM components** (web + CE + search), not per-component. Split it deliberately:

```yaml
sonarProperties:
  sonar.web.javaAdditionalOpts:    "-Xms1g    -Xmx1g"
  sonar.ce.javaAdditionalOpts:     "-Xms1536m -Xmx1536m"
  sonar.search.javaAdditionalOpts: "-Xms1g    -Xmx1g"
```

⭐ **Set `-Xms` equal to `-Xmx`.** A JVM that grows its heap at runtime pauses to do it, and those pauses land exactly when a big analysis is running. Fixed heap = predictable latency.

### 8.2 Where to spend, based on the symptom

| Symptom | Component | Move |
|---|---|---|
| **UI slow, API timeouts, many concurrent users** | Web | raise `sonar.web.javaAdditionalOpts`, and `sonar.web.workers` |
| ⭐ **Analyses queue up; "Background Tasks" shows pending** | **Compute Engine** | raise `sonar.ce.javaAdditionalOpts` **and** `sonar.ce.workerCount` |
| **Issues page slow/empty, search errors** | Search (ES) | raise ES heap — ⛔ but never above **50% of container memory**, and never above ~31 GB (compressed-oops limit) |
| **Pod OOMKilled** | container limit | ⭐ the three heaps plus metaspace plus ES off-heap must fit **under** the container limit with headroom |

### 8.3 ⭐ The container-memory arithmetic people get wrong

```
container memory limit  ≥  web heap + CE heap + ES heap
                           + ~500M metaspace/JVM overhead per JVM
                           + ES off-heap (Lucene uses memory OUTSIDE the heap)
                           + headroom
```

With 1 G + 1.5 G + 1 G = **3.5 G of heap**, a `limits.memory: 4Gi` container **will be OOMKilled** under load. That is why §6.2 sets requests 3 Gi / limits 6 Gi. ⛔ Setting the container limit equal to the sum of the heaps is the classic error — it ignores that a JVM uses memory the heap flags do not account for.

```bash
# verify from inside
kubectl -n sonarqube exec deploy/sonarqube-sonarqube -- \
  sh -c 'cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes'
kubectl top pod -n sonarqube
```

### 8.4 Database sizing

| Driver | Rule of thumb |
|---|---|
| **Disk** | ⭐ proportional to **number of analyses × project size**, not to lines of code. A repo analysed on every commit for a year accumulates a lot of rows. Watch it; enable **housekeeping** (`Administration → Housekeeping`) to prune old snapshots |
| **Connections** | one pool per component. `sonar.jdbc.maxActive` × 3 components must stay under Postgres's `max_connections` |
| **Backups** | ⭐⭐ **`pg_dump` on a schedule, restore-tested.** There is no down-migration (§1), so a backup is your only rollback |

---

## 9 · 🔨 Tasks

> **0.1** Install SonarQube Community Build with Docker against PostgreSQL (§5). Record the four "started" log lines in order and explain what each component is responsible for. Then kill the container and explain which of your three volumes you could afford to lose and which one you could not.

> **0.2** Determine, from the running server, exactly which version and edition you have. Then state whether you can (a) analyse a feature branch, (b) decorate a pull request, and (c) run taint analysis — with the reason for each.

> **0.3** Install on Kubernetes with Helm (§6) and deliberately trigger the `vm.max_map_count` failure. Report the exact log line, where the setting actually lives, why the chart's `initSysctl` may not be allowed to fix it, and the two durable solutions.

> **0.4** Run a first analysis **without** `sonar.qualitygate.wait=true`, with a Quality Gate condition you know will fail. Report the CI exit code and the dashboard verdict, and explain the gap between them in terms of §4's numbered steps.

> **0.5** Configure coverage import for a Java/Maven project. Make the dashboard show 0% first, diagnose it, then make it show the real number. Name the two most common reasons for a 0% reading that is not a SonarQube bug.

> **0.6** Compute the correct container memory limit for a Developer-edition install with web 2 G, CE 2 G, and search 2 G heaps. Show your arithmetic and explain the two categories of memory your calculation must cover that the `-Xmx` flags do not.

> **0.7** Create the three token types from §7.2 and demonstrate the difference in blast radius by attempting an analysis of a project you do not own with each.

> **0.8** ⭐⭐ Your organisation has 40 repositories on Community Build. Leadership asks for "SonarQube to block bad pull requests." Write the response: what is actually possible today, what the minimum viable change is, what it costs in budget and in engineering time, and what you would do in the meantime with the two free tools in this folder.

> **0.9** ⭐⭐ It is month three. You are on Community Build 26.7, whose support ended two months ago. Write the upgrade plan to the current release, including every step where a mistake loses data, and name the step that most teams skip.

<details>
<summary>👉 Answers</summary>

**0.1**

```bash
docker logs sonarqube 2>&1 | grep -iE 'started|operational'
```

The four lines, in order, and what each means:

| Order | Log line | Component | Responsible for |
|---|---|---|---|
| 1 | `Elasticsearch … started` | **Search server** (`sonar.search.*`) | The embedded ES instance. **Starts first** because the web server and CE depend on the index being available. Indexes issues so the UI can query millions fast |
| 2 | `Compute Engine … started` | **CE** (`sonar.ce.*`) | ⭐ The report processor. Takes uploaded reports off a queue, computes measures, applies the Quality Gate, writes to DB + index |
| 3 | `Web Server … started` | **Web** (`sonar.web.*`) | UI + REST API on `:9000`. Receives reports, serves dashboards |
| 4 | `SonarQube is operational` | — | Everything is up; `/api/system/status` now returns `UP` |

⭐ **The order is diagnostic information.** A failure at line 1 is almost always `vm.max_map_count` (§6.4) or a data-volume permission problem. A failure at line 2 or 3 is usually the database — check `sonar.jdbc.*` and whether Postgres is reachable. `docker logs` filtered to `error|fatal` around the last successful line tells you which stage died.

**Which volumes you could lose:**

| Volume | Contents | Losable? |
|---|---|---|
| `sonar-logs` | log files | ✅ **Completely.** Diagnostics only, nothing derived from them |
| `sonar-extensions` | ⭐ **your installed plugins** | ⚠️ **Recoverable but painful.** Re-installable, yes — but you will not necessarily remember which versions, and a plugin version mismatch silently changes analysis results. Treat as "must back up, can reconstruct" |
| `sonar-data` | ⭐ **the Elasticsearch index** | ⚠️ **Recoverable at a cost.** ES is a *derived* store — the authoritative data is in PostgreSQL — so SonarQube can reindex. But a full reindex of 40 repos takes hours, during which search and issue navigation are broken or empty |
| *(the PostgreSQL volume)* | ⛔ **history, trends, measures, gate decisions, debt records, every analysis ever run** | ⛔⛔ **NOT recoverable.** This is the product. There is no way to reconstruct ten months of trend data by re-scanning: a re-analysis produces *today's* snapshot, not the historical record. **Losing the DB loses the entire reason SonarQube is a server rather than a CLI** (§2) |

⭐ **The generalisation worth carrying:** in any system, find the component that holds **non-derivable state** and that is your backup priority. ES is derivable from Postgres; Postgres is derivable from nothing.

**0.2**

```bash
export SONAR_HOST=http://localhost:9000
export SONAR_TOKEN=sqp_…

curl -s -u "$SONAR_TOKEN:" "$SONAR_HOST/api/system/status" | jq
# { "version": "26.9.0.129388", "status": "UP" }
```

```bash
# the edition — several routes, because the endpoint varies by version
curl -s -u "$SONAR_TOKEN:" "$SONAR_HOST/api/editions/show_details" 2>/dev/null | jq '.edition // empty'
curl -s -u "$SONAR_TOKEN:" "$SONAR_HOST/api/system/info" | jq '.System, .Statistics' 2>/dev/null
# and the reliable one: the UI footer, and Administration → System
```

So: **Community Build 26.9.0.129388**.

| Capability | Available? | Reason |
|---|---|---|
| **(a) Analyse a feature branch** | ⛔ **No** | **Branch analysis is edition-gated** — Developer and above. Community Build analyses `main` only. Setting `sonar.branch.name` is rejected/ignored; there is no workaround |
| **(b) Decorate a pull request** | ⛔ **No** | **PR analysis is edition-gated** and depends on branch analysis — the PR is analysed *as a branch* and compared to its base. Without (a) there is no (b) |
| **(c) Taint analysis** | ⛔ **No** | **Taint analysis is edition-gated** — Developer and above. You get pattern-based vulnerability detection, not dataflow tracking from source → sanitiser → sink |

⭐ **The consequence to say out loud:** on Community Build, **"SonarQube found no injection vulnerabilities" is not evidence that there are none** — the engine that looks for them never ran. That distinction matters enormously in a security review, and conflating the two is how a team ends up with a false assurance record.

**What you *can* do on Community Build:** full bug/smell/vulnerability-pattern/hotspot analysis, coverage and duplication, Quality Profiles, and a **Quality Gate with trends** — all on `main`, all with history. That is still valuable; it is just **post-merge** feedback rather than pre-merge.

**0.3** Trigger it by disabling the chart's sysctl init and running on a node with the default:

```bash
# install WITHOUT the init fix, on a node with the stock value
helm upgrade --install sonarqube sonarqube/sonarqube --version 2026.4.1 \
  -n sonarqube -f values.yaml --set initSysctl.enabled=false --wait || true

kubectl -n sonarqube logs deploy/sonarqube-sonarqube | grep -i 'max_map_count'
```

**The exact log line:**

```
ERROR: [1] bootstrap checks failed
[1]: max virtual memory areas vm.max_map_count [65530] is too low,
     increase to at least [262144]
```

followed by the pod going `CrashLoopBackOff`, and typically `max file descriptors [1024] for elasticsearch process is too low, increase to at least [65535]` as bootstrap check `[2]`.

**Where the setting actually lives:** on the **node's kernel**, not in the container.

```bash
# read it on the node — this is the only check that tells the truth
kubectl debug node/<node-name> -it --image=busybox -- sysctl vm.max_map_count
# or, from a privileged pod on that node:
kubectl run sysctl-check --rm -it --privileged --image=busybox -- \
  sh -c 'sysctl vm.max_map_count; sysctl fs.file-max'
```

A container cannot raise a **host** kernel parameter without privilege — which is exactly why the chart's fix is a **privileged init container**.

**Why `initSysctl` may not be allowed:** it runs `privileged: true`, which is denied by **Pod Security Admission** `baseline` or `restricted` (and by most org policy). Enabling it means either labelling the namespace to permit privileged pods — ⛔ which weakens policy for *everything* in that namespace — or getting an exception. So the "easy fix" is a security decision, and it should be made as one.

**The two durable solutions:**

```bash
# ① NODE IMAGE / node bootstrap — the right answer
#    Set it in the node's own sysctl config so it survives reboot and needs no privilege at runtime.
echo 'vm.max_map_count=524288' | sudo tee /etc/sysctl.d/99-elasticsearch.conf
echo 'fs.file-max=131072'      | sudo tee -a /etc/sysctl.d/99-elasticsearch.conf
sudo sysctl --system
```
Bake this into the node image (Packer/AMI), the node-pool startup script, or cloud-init. ⭐ **This is the correct place**, because the requirement is a property of *running Elasticsearch on this node*, not of the SonarQube pod.

```bash
# ② A privileged DaemonSet that sets it once per node
#    Confined to one namespace, one ServiceAccount, one purpose — and reviewable.
apiVersion: apps/v1
kind: DaemonSet
metadata: { name: sysctl-tuner, namespace: kube-system }
spec:
  selector: { matchLabels: { app: sysctl-tuner } }
  template:
    metadata: { labels: { app: sysctl-tuner } }
    spec:
      hostPID: true
      containers:
        - name: tuner
          image: busybox:1.36
          securityContext: { privileged: true }
          command: ["sh","-c","sysctl -w vm.max_map_count=524288 && sysctl -w fs.file-max=131072 && sleep infinity"]
```

⭐ **Managed-Kubernetes note:** on GKE/EKS/AKS you often **cannot** change the node image, and the managed nodes may already set a suitable value — **check before you build anything**. On some managed offerings the correct answer is that `initSysctl: true` with a narrowly-scoped PSA exception is genuinely the pragmatic choice. The point is to make it *deliberately*, having read the trade-off.

**0.4**

```properties
# sonar-project.properties — note what is ABSENT
sonar.projectKey=demo-gate
sonar.sources=src
# ⛔ sonar.qualitygate.wait is NOT set
```

Make the gate fail — add a condition **Coverage on New Code < 80%** and analyse code with no tests, or add **Issues on New Code > 0** and introduce an obvious smell.

```bash
mvn clean verify sonar:sonar -Dsonar.host.url=$SONAR_HOST -Dsonar.token=$SONAR_TOKEN
echo "CI exit code: $?"
```

**Result:**

```
INFO: ANALYSIS SUCCESSFUL, you can find the results at: http://…/dashboard?id=demo-gate
INFO: Note that you will be able to access the updated dashboard once the server has processed the submitted analysis report
INFO: More about the report processing at http://…/api/ce/task?id=AZ…
…
CI exit code: 0        ← ⛔ GREEN
```

Meanwhile the dashboard, a minute later:

```bash
curl -s -u "$SONAR_TOKEN:" "$SONAR_HOST/api/qualitygates/project_status?projectKey=demo-gate" \
  | jq '.projectStatus.status, .projectStatus.conditions'
```
```
"ERROR"
[ { "status":"ERROR", "metricKey":"coverage", "comparator":"LT", "periodIndex":1,
    "errorThreshold":"80", "actualValue":"0.0" } ]
```

**The gap, in §4's numbered steps:**

- The scanner completed steps **①–⑤**: parse, run rules, import coverage, compute measures, **POST the report**. Then it **exited 0** — because *its* job succeeded. A successful **upload** is not a successful **analysis**.
- Steps **⑥–⑧** happen **asynchronously in the Compute Engine**: dequeue, recompute, resolve new code, evaluate the **Quality Gate**, write to Postgres and ES. That is where the `ERROR` verdict is produced — after the CI step is already green and the pipeline has moved on.
- Step **⑨** — a verdict CI can act on — never arrives, because nothing is waiting for it.

⭐ **The log line that gives it away** is the one everyone scrolls past: *"Note that you will be able to access the updated dashboard **once the server has processed** the submitted analysis report."* SonarQube is telling you, explicitly, that the analysis is not finished.

**The fix — two options:**

```properties
# OPTION A: block in the scanner
sonar.qualitygate.wait=true
sonar.qualitygate.timeout=300        # seconds; the CE queue can be slow under load
```

```bash
# OPTION B: poll the API after the scan
TASK_ID=$(… from the scanner output …)
curl -sf -u "$SONAR_TOKEN:" "$SONAR_HOST/api/ce/task?id=$TASK_ID" | jq -r '.task.status'
#   PENDING → IN_PROGRESS → SUCCESS
curl -sf -u "$SONAR_TOKEN:" "$SONAR_HOST/api/qualitygates/project_status?analysisId=$ANALYSIS_ID" \
  | jq -e '.projectStatus.status == "OK"' || exit 1
```

⭐ **Option A is simpler; Option B is better when you need the *reasons*** — the failing conditions — to post as a PR comment or a Slack message. Option A blocks on a timeout and gives you a bare exit code; Option B lets you say *"coverage on new code is 0%, threshold 80%"* to the person who can fix it. Real pipelines often do both: A to gate, B to report. [`03-CI-CD-INTEGRATION.md`](03-CI-CD-INTEGRATION.md)

**0.5** Make it show 0%, then fix it:

```bash
# STEP 1 — run the analysis WITHOUT the coverage property, or before tests run
mvn clean compile sonar:sonar -Dsonar.host.url=$SONAR_HOST -Dsonar.token=$SONAR_TOKEN
#   ⛔ no `verify` phase → JaCoCo never runs → no report exists
```

Dashboard: **Coverage 0.0%**.

```bash
# STEP 2 — diagnose. Does the report exist at analysis time?
ls -la target/site/jacoco/jacoco.xml
find . -name 'jacoco*.xml' -o -name 'jacoco*.exec'
```

**The two most common reasons for a 0% reading that is not a SonarQube bug:**

**① The report was never generated** — because the build phase that produces it did not run. ⭐ This is the most common by a wide margin.

For Maven/JaCoCo, `jacoco.xml` is produced by the **`report` goal**, which must be bound to a lifecycle phase, and it must run **before** the Sonar analysis:

```xml
<plugin>
  <groupId>org.jacoco</groupId>
  <artifactId>jacoco-maven-plugin</artifactId>
  <version>0.8.13</version>
  <executions>
    <execution>
      <id>prepare-agent</id>
      <goals><goal>prepare-agent</goal></goals>       <!-- instruments -->
    </execution>
    <execution>
      <id>report</id>
      <phase>verify</phase>                            <!-- ⭐ must be bound -->
      <goals><goal>report</goal></goals>               <!-- produces jacoco.xml -->
    </execution>
  </executions>
</plugin>
```

```bash
mvn clean verify sonar:sonar …      # ⭐ `verify`, not `compile`, not `test`
```

The `jacoco.exec` → `jacoco.xml` distinction matters: **SonarQube reads the XML report, not the binary `.exec`.** Having `prepare-agent` without `report` gives you a `.exec` file and still 0% in SonarQube.

For JS/TS the equivalent is that `jest --coverage` must actually run and emit lcov, and `sonar.javascript.lcov.reportPaths` must point at it.

**② The path is wrong, or relative to the wrong directory.**

```properties
sonar.coverage.jacoco.xmlReportPaths=target/site/jacoco/jacoco.xml
```

- ⭐ The path is resolved **relative to the scanner's working directory** (the project base dir), not relative to `sonar.sources`. A multi-module Maven build is the classic trap: the module produces `module-a/target/site/jacoco/jacoco.xml`, and a single root-level property misses it. Use a comma-separated list or a glob.
- The file must exist **at analysis time**. In CI, a separate "test" job that does not share its workspace with the "analyse" job means the report is on a different machine entirely. ⭐ This is the #1 CI-specific cause: tests ran, coverage was real, and the analysis step could not see the artifact. Fix by running both in one job, or by passing the report as an artifact.

```bash
# verify SonarQube actually ingested it — the scanner log says so explicitly
mvn verify sonar:sonar … 2>&1 | grep -iE 'coverage|jacoco|sensor'
#   SENSOR JaCoCo XML Report Importer …
#   SENSOR JaCoCo XML Report Importer (done) | time=…
```

⭐ **If that sensor line is absent, no coverage report was found** — regardless of what your property says. That log grep is the definitive diagnostic, faster than reading the dashboard.

Then the correct number appears:

```bash
curl -s -u "$SONAR_TOKEN:" \
  "$SONAR_HOST/api/measures/component?component=shop-api&metricKeys=coverage,line_coverage,lines_to_cover" \
  | jq '.component.measures'
```

**0.6** Developer edition, three heaps at 2 G each.

**Step 1 — the heap total:**

```
web   -Xmx2g   = 2048 M
CE    -Xmx2g   = 2048 M
search -Xmx2g  = 2048 M
────────────────────────
heap total     = 6144 M  ≈ 6.0 GiB
```

⚠️ **First check the constraint:** official guidance for Developer is a **sum of Xmx = 1536M**, and Enterprise 5 G (§8.1). **6 G of heap is above the documented guidance for this edition** — so before sizing the container, question the sizing of the heaps. The right question is *which component actually needs 2 G*, answered from evidence (`Administration → Background Tasks` queue depth for CE, UI latency for web, index size for search), not from a round number. Assume here that measurement justified web 1 G / CE 2 G / search 1.5 G = **4.5 G heap**, which is closer to Enterprise guidance and is what the arithmetic below uses as well as the 6 G worst case.

**Step 2 — the two categories of memory `-Xmx` does not cover:**

**(a) Non-heap JVM memory, per JVM.** `-Xmx` bounds only the *heap*. Each of the three JVMs also uses:

| Region | Typical |
|---|---|
| **Metaspace** (class metadata) | 256–512 M per JVM — SonarQube loads a lot of classes and plugins |
| **Code cache** (JIT-compiled native code) | 100–240 M |
| **Thread stacks** | ~1 M × threads; the web server has many worker threads → 100–300 M |
| **Direct/native buffers, GC structures** | 100–300 M |
| **Subtotal per JVM** | ⭐ **~500 M – 1 G** |

With **three** JVMs in one container: **~1.5 – 3 G** of non-heap memory that no `-Xmx` flag accounts for.

**(b) Elasticsearch off-heap.** ⭐ This is the one people miss entirely. Lucene deliberately works **outside** the JVM heap — it uses the OS page cache and mmap'd segment files for its inverted indexes. ES's own documentation recommends the heap be **no more than 50% of available memory** precisely because the other half must be left for this. So a 2 G ES heap implies **~2 G more** of memory the JVM will use but not report as heap.

**Step 3 — the arithmetic:**

```
heap total                            6144 M   (6.0 GiB)
+ non-heap JVM overhead (3 × ~750 M)  2304 M   (2.25 GiB)
+ ES off-heap / page cache            2048 M   (2.0 GiB)
─────────────────────────────────────────────────
working set                          10496 M   (10.25 GiB)
+ headroom (20%, for spikes & GC)     2100 M   (2.05 GiB)
══════════════════════════════════════════════
CONTAINER LIMIT  ≈  12.5 GiB          → set 12Gi or 13Gi
REQUESTS         ≈  8 GiB             → ~65% of limit
```

```yaml
resources:
  requests: { cpu: "1", memory: 8Gi }
  limits:   { cpu: "4", memory: 12Gi }
```

⭐ **The naive answer — `limits.memory: 6Gi` because "the heaps total 6 G" — guarantees an OOMKill under load**, and the kill will happen during a large analysis, which is exactly when you need it not to.

**Two more rules that follow:**

- ⛔ **Never set the ES heap above ~31 GiB.** Above that the JVM loses **compressed ordinary object pointers**, and every reference grows from 4 to 8 bytes — so a 32 G heap holds *less* data than a 31 G one. The limit is a cliff, not a slope.
- ⭐ **Split the container if you can.** The chart runs all four components in one pod. At this size, moving Elasticsearch to its own StatefulSet (with its own limits, its own PVC, its own scaling) makes the arithmetic tractable and removes the coupling where a CE spike OOMs your search index.

Verify against reality, not against your YAML:

```bash
kubectl top pod -n sonarqube --containers
kubectl -n sonarqube exec deploy/sonarqube-sonarqube -- sh -c \
  'cat /sys/fs/cgroup/memory.max; cat /sys/fs/cgroup/memory.peak 2>/dev/null'
kubectl -n sonarqube describe pod -l app=sonarqube | grep -A6 'Last State'   # OOMKilled?
```

`memory.peak` is the number that tells you whether your limit is right — compare it to `memory.max` and keep peak under ~80%.

**0.7**

```bash
# Create all three in My Account → Security:
#   TOK_USER    = user token
#   TOK_GLOBAL  = global analysis token
#   TOK_PROJECT = project analysis token, scoped to "shop-api"

attempt() {  # $1 = token, $2 = project key
  code=$(curl -s -o /tmp/out.json -w '%{http_code}' -u "$1:" \
    "$SONAR_HOST/api/qualitygates/project_status?projectKey=$2")
  printf '  %-12s → %-14s HTTP %s  %s\n' "$2" "$(basename $1)" "$code" "$(jq -r '.errors[0].msg // "ok"' /tmp/out.json 2>/dev/null)"
}

echo "── with the PROJECT token (scoped to shop-api) ──"
attempt "$TOK_PROJECT" shop-api        # → HTTP 200 ok
attempt "$TOK_PROJECT" checkout        # → HTTP 401/403  ⛔ Unauthorized

echo "── with the GLOBAL ANALYSIS token ──"
attempt "$TOK_GLOBAL"  shop-api        # → HTTP 200 ok
attempt "$TOK_GLOBAL"  checkout        # → HTTP 200 ok   ⚠️ any project

echo "── with the USER token ──"
attempt "$TOK_USER"    shop-api        # → HTTP 200 ok
attempt "$TOK_USER"    checkout        # → HTTP 200 ok   ⛔ and more than analysis:
                                       #    it can also call ADMIN APIs that user can reach
```

**Blast radius, smallest to largest:**

| Token | Can analyse | Can do more? | Revoke cost |
|---|---|---|---|
| ⭐ **Project analysis** | **one project** | ⛔ no — analysis only | one repo re-runs its pipeline with a new token |
| **Global analysis** | **every project** | ⛔ no — analysis only | ⛔ **every repo's pipeline breaks at once** |
| **User** | every project the user can | ⚠️⛔ **yes** — whatever that human can do: change Quality Profiles, edit gates, administer projects, read all source snippets, manage users | ⛔ breaks CI **and** is a person-shaped credential: it survives their access review, and if they leave the token keeps working until someone remembers it |

⭐ **The rule that follows:** ⛔ **never put a user token in CI.** It is the full authority of a named human, in a system, with no expiry tied to that human's employment. The March 2026 Trivy incident ([`../02-SUPPLY-CHAIN-AND-PINNING.md`](../02-SUPPLY-CHAIN-AND-PINNING.md)) is a reminder that CI credentials get used by things you did not personally run.

**The default choice is the project analysis token** — one repo, one capability, revocable without collateral damage. Use a global analysis token only for a genuinely central system (a shared build service analysing many repos), and then scope it as tightly as the product allows and rotate it on a schedule.

**0.8** ⭐⭐ The response — honest, specific, and with a path.

---

### Re: "SonarQube to block bad pull requests"

**Short answer:** we can do it, but not with the edition we have, and not this month. Here is exactly what is possible, what the change costs, and what I would do in the meantime.

**1. What is actually possible on Community Build today — and the gap.**

Community Build analyses **`main` only**. **Branch analysis and pull-request analysis are edition-gated** (Developer and above), and PR analysis is built on branch analysis — the PR is analysed *as a branch* and compared to its base. So:

- ✅ We **can** run a full analysis on every merge to `main` and enforce a **Quality Gate** on it.
- ⛔ We **cannot** analyse the PR's own code before merge, and we **cannot** post findings on the PR diff.

**That means the literal request — "block bad pull requests" — is not achievable on the current licence.** The closest available behaviour is *"block the merge by analysing the would-be result"*, which is a materially worse control: feedback arrives after review, on a merge commit nobody will look at, and there is no diff-level attribution so the finding does not land on the person who wrote it.

**2. The minimum viable change.**

**SonarQube Developer edition** for the repositories where PR-level feedback matters. That unlocks branch analysis, PR analysis, PR decoration, and **taint analysis** — which matters more than the licensing page suggests, because taint analysis is the engine that finds real injection vulnerabilities by following data from source to sink. ⛔ **On Community Build, "no injection vulnerabilities found" is not evidence there are none; that engine does not run.** I would not want that ambiguity in a security review.

**Scope it, don't buy it everywhere.** 40 repos do not all need it. My proposal: Developer for the **~8–10 repos** that are internet-facing, handle data, or change most often; Community Build for the rest. That is a fraction of the cost and covers most of the risk. **This needs a procurement decision from you, not an engineering one from me.**

**3. What it costs — budget and engineering time.**

| | Estimate |
|---|---|
| **Budget** | Developer-edition licensing for 8–10 repos. ⭐ **Also budget for Server, not just Developer**: Community Build has **one month of support per release**, so we are currently on a forced monthly upgrade with an in-place database migration and **no down-migration**. That is a recurring engineering tax we are paying whether or not we buy Developer |
| **Engineering — licensing path** | ~2 weeks: procure, upgrade the instance (**backup Postgres first, verify the restore, follow the documented intermediate-hop path**), re-test the gate, wire PR analysis and decoration into CI for the scoped repos |
| **Engineering — no-licensing path** | ~1 week to build the workaround below, and it stays permanently inferior |

**4. What I would do in the meantime — with the two free tools in this folder.**

⭐ **Both Trivy and Checkov are free, stateless, and emit SARIF — which means they deliver PR-level, diff-line feedback today, on Community Build, with no licence.** They cover a different layer than SonarQube, but they cover the layer where "block the bad PR" has the most immediate value:

| Gate, live this month | Tool | What it blocks |
|---|---|---|
| **Hardcoded secrets** | 🟢 Trivy (`--scanners secret`) / 🔵 Checkov (`--framework secrets`) | ⛔ the highest-severity, cheapest-to-catch class. Zero tolerance from day one |
| **Insecure infrastructure** | 🔵 Checkov (`CKV_K8S_*`, `CKV2_*`, `CKV_DOCKER_*`) | privileged containers, root users, secrets in env vars, no NetworkPolicy, missing limits, `latest` tags |
| **Known CVEs in what we ship** | 🟢 Trivy (`--severity CRITICAL,HIGH --ignore-unfixed`) | vulnerable dependencies and base images |
| **IaC in the chart, rendered per environment** | 🔵 Checkov on `helm template` output | the divergences between `values.yaml` and `values-production.yaml` |
| **Code quality — post-merge** | 🟣 SonarQube Community Build on `main` | bugs, smells, coverage, duplication, with trends and a Quality Gate |

That is **four blocking gates on the PR** and one blocking gate on merge, with **zero licence spend**. The pattern in all three tools is the same and is what makes it survivable on legacy code: **gate on new findings only**, keep a committed baseline, burn it down on a schedule, and put every finding on the diff via SARIF so it reaches the author.

**5. My recommendation.**

1. **Now (2 weeks):** wire Trivy + Checkov into all 40 PR pipelines with SARIF and new-findings gating. This delivers most of "block bad pull requests" immediately.
2. **Now (ongoing):** keep SonarQube Community Build gating `main` on a Quality Gate tuned to **new code** — the ratchet still works, it just lands after merge.
3. **This quarter:** a budget decision on **Developer edition for the 8–10 highest-risk repos**, driven by two requirements: PR-level code-quality feedback and taint analysis.
4. **Independently, and sooner:** decide whether we accept **monthly forced upgrades with an in-place DB migration** on Community Build, or move to **Server** for a supportable horizon. ⭐ That question is orthogonal to Developer-vs-Community and, operationally, more urgent — we are three months from being on an unsupported version.

**The one thing I want on the record:** we should not describe the current setup as "PR gating" in any compliance or security review. It gates merges, not pull requests, and it does not run taint analysis. Both are fixable; neither should be quietly assumed.

**0.9** ⭐⭐ Month three, Community Build 26.7 → current (26.9). Two months unsupported.

---

### Upgrade plan: SonarQube Community Build 26.7 → 26.9

**The governing fact.** ⛔ **SonarQube migrates its database schema in place and there is no down-migration.** Once a newer version starts against a database, that database belongs to the newer version. Every step below is arranged around one question: *at which point can I still go back?* **The answer is "until the CE touches the DB"** — which is why the backup is step 1 and the restore test is step 2.

#### Phase A — before anything (the steps that most teams skip)

**A1. ⭐⭐ Back up PostgreSQL. Not "take a snapshot" — take a dump AND a snapshot.**

```bash
# logical dump — portable, restorable into a different instance/version
pg_dump -h sonar-db.internal -U sonar -Fc -f sonarqube-$(date +%F).dump sonarqube

# AND a storage/volume snapshot if your platform offers one — faster to restore
# Record both, with timestamps, in the change record.
```

⭐ **Why both.** The dump is portable and survives a lost volume; the snapshot restores in minutes rather than hours. On a 40-repo instance with a year of history the dump restore can take a long time, and you want the option.

**A2. ⭐⭐ RESTORE THE BACKUP AND PROVE IT WORKS. ← this is the step most teams skip.**

```bash
createdb -h sonar-db.internal -U sonar sonarqube_restore_test
pg_restore -h sonar-db.internal -U sonar -d sonarqube_restore_test sonarqube-$(date +%F).dump
psql   -h sonar-db.internal -U sonar -d sonarqube_restore_test \
  -c 'select count(*) from projects;' -c 'select count(*) from snapshots;' -c 'select count(*) from issues;'
dropdb -h sonar-db.internal -U sonar sonarqube_restore_test
```

> ⭐⭐ **Why this is the step most teams skip, and why it is the one that matters most.** A backup you have never restored is a **hypothesis**. The failure modes it catches are mundane and common: the dump job's credentials lost `pg_dump` permission three months ago and it has been writing an error to a log nobody reads; the dump succeeded but the disk it wrote to was full, so the file is truncated; the cron job was disabled during a node migration. Every one of those produces a **backup that exists and does not restore** — and you find out during the incident, which is the one moment you cannot afford a discovery.
>
> It costs ten minutes. It is the difference between "we can roll back" and "we believe we can roll back."

**A3. Determine the actual upgrade path — do not guess it.**

```bash
curl -s -u "$SONAR_TOKEN:" "$SONAR_HOST/api/system/status" | jq -r .version   # → 26.7.0.xxxxx
```

Then use **SonarSource's official update-path calculator**, not memory. For 26.7 → 26.9 check specifically whether **26.8 must be an intermediate step**. ⭐ Community Build is a monthly train; consecutive months are usually direct, but **December 2025 (25.12.0.117093) had database-migration problems** that made **26.1.0.118079** a required intermediate hop in some paths — proof that "obviously it's direct" is not a safe assumption. Read the release notes for **both** 26.8 and 26.9 before starting.

**A4. Read the release notes for schema changes and removed features.** Look for: DB migration notes, removed/deprecated properties (`sonar.*` keys you set in `sonarProperties`), plugin compatibility, and analyser changes that would alter results.

**A5. Check plugin compatibility.** Anything in `sonar-extensions/plugins` must support the target version. ⛔ An incompatible plugin can fail the CE at startup, *after* the DB migration — the worst possible timing.

**A6. Freeze analyses.** Tell CI to stop, or accept that in-flight reports will fail. A report being processed during a shutdown is how you get a half-applied task.

**A7. Book a window, and a rollback decision point.** Decide **in advance** how long you will try before restoring: e.g. *"if not `UP` within 45 minutes, restore from the A1 backup."* Deciding that during an outage is how a 45-minute problem becomes a day.

#### Phase B — the upgrade

```bash
# B1. Quiesce: stop CI, then wait for the CE queue to DRAIN
curl -s -u "$SONAR_TOKEN:" "$SONAR_HOST/api/ce/pending?ps=1" | jq '.pending,.failing,.inProgress'
#   → 0, 0, 0   ⭐ do not proceed until all three are zero

# B2. Note the current state so you can compare afterwards
curl -s -u "$SONAR_TOKEN:" "$SONAR_HOST/api/projects/search?ps=500" | jq '.paging.total'
curl -s -u "$SONAR_TOKEN:" "$SONAR_HOST/api/system/info" > sonarqube-info-BEFORE.json

# B3. Snapshot the ES index volume too (sonar-data). Not authoritative, but a
#     reindex of 40 repos takes hours; having the option matters.

# B4. Upgrade
helm upgrade sonarqube sonarqube/sonarqube --version <chart for 26.9> \
  -n sonarqube -f values.yaml \
  --set community.buildNumber="26.9.0.129388" \
  --wait --timeout 20m
# ⛔ NOT --atomic here: --atomic would roll the RELEASE back while the DB
#    migration has already run, leaving a new-version database with an
#    old-version server. That is worse than failing forward.
```

⭐ **That `--atomic` note is a real trap.** Everywhere else in this workspace the rule is "always `--atomic`" ([`../../prometheus-in-kubernetes/04-INSTALL-KUBE-PROMETHEUS-STACK.md`](../../prometheus-in-kubernetes/04-INSTALL-KUBE-PROMETHEUS-STACK.md)). Here it is **wrong**, because the database migration is a side effect Helm cannot roll back. ⛔ `--atomic` gives you the illusion of safety while creating the most unrecoverable state available: a migrated DB and an unmigrated server.

```bash
# B5. WATCH THE MIGRATION — it runs at startup, in the logs
kubectl -n sonarqube logs -f deploy/sonarqube-sonarqube | grep -iE 'migrat|schema|started|operational|error|fatal'
```

Expect: `Starting DB Migration…` → `DB Migration completed` → the four component "started" lines → `SonarQube is operational`.

```bash
# B6. Verify
curl -s -u "$SONAR_TOKEN:" "$SONAR_HOST/api/system/status" | jq   # → "UP", version 26.9.x
```

#### Phase C — verification (all of it, in order)

```bash
# C1. Project count matches B2 — nothing was lost
curl -s -u "$SONAR_TOKEN:" "$SONAR_HOST/api/projects/search?ps=500" | jq '.paging.total'

# C2. History survived — pick a repo and confirm old snapshots are still there ⭐
curl -s -u "$SONAR_TOKEN:" \
  "$SONAR_HOST/api/measures/search_history?component=shop-api&metrics=coverage,ncloc&ps=100" \
  | jq '.measures[0].history | length'
#   ⛔ a small number here means the migration dropped history. STOP and restore.

# C3. Background Tasks processes cleanly — the real end-to-end test
curl -s -u "$SONAR_TOKEN:" "$SONAR_HOST/api/ce/component?component=shop-api" | jq '.queue'

# C4. Run ONE analysis and confirm it lands
mvn verify sonar:sonar -Dsonar.host.url=$SONAR_HOST -Dsonar.token=$SONAR_TOKEN \
    -Dsonar.qualitygate.wait=true
curl -s -u "$SONAR_TOKEN:" "$SONAR_HOST/api/qualitygates/project_status?projectKey=shop-api" | jq -r '.projectStatus.status'

# C5. Search works (ES reindexed or the index survived)
#     UI → Issues → filter by rule. Empty results while the overview shows
#     correct counts = the index did not come back.

# C6. Quality Profiles and Gate conditions unchanged — diff against BEFORE
curl -s -u "$SONAR_TOKEN:" "$SONAR_HOST/api/qualityprofiles/search" | jq '.profiles[] | {name,language,activeRuleCount}'

# C7. Only then: re-enable CI.
```

⭐ **C2 is the check that justifies the whole procedure.** Version numbers, HTTP 200s and a green pod all come back fine from a migration that silently dropped historical snapshots. **The product is the history** (§2) — if the trend lines are gone, the upgrade failed even though the server is `UP`.

#### Phase D — after

- Update the runbook with the real timings, the actual path taken, and anything that surprised you.
- Record: from-version, to-version, date, path, backup location, verification results, operator. ⭐ This is the audit trail, and it is what makes the *next* monthly upgrade fast.
- **Decide the recurring problem.** You just did this because Community Build supports each release for **one month**. Either (a) automate it — a monthly, tested, low-drama pipeline with the restore test built in — or (b) escalate the **Server** conversation. ⛔ Doing it manually, reluctantly, every month, is how instances end up six months unsupported: which is where we are right now.

#### The steps where a mistake loses data

| Step | Mistake | Loss |
|---|---|---|
| **A1/A2** | backup not taken, or not restore-tested | ⛔⛔ **total** — no rollback exists |
| **B1** | upgrading with a non-empty CE queue | a half-processed report; possibly an inconsistent task row |
| **B4** | using `--atomic` | ⛔⛔ **the worst state**: migrated DB + rolled-back server |
| **B4** | skipping an intermediate version | migration fails partway → **restore from backup** |
| **B5** | not watching the migration log | you learn about the failure from users, not from the log |
| **C2** | not verifying history | ⛔ silent loss of the actual product, discovered months later |

**The step most teams skip: A2 — restoring the backup to prove it works.** It is the only step whose entire purpose is to invalidate your assumptions, which is exactly why it feels like wasted time until the day it isn't.

</details>

---

## ➡️ Next

**[`01-FIRST-SCAN-AND-READING-OUTPUT.md`](01-FIRST-SCAN-AND-READING-OUTPUT.md)** — reading the dashboard: Bug vs Vulnerability vs Code Smell vs **Security Hotspot** (the distinction everyone gets wrong), the three ratings, technical debt, duplication, and how to find the six issues that matter in a report of six hundred.

**Then:** [`02-CONFIGURATION-AND-BASELINES.md`](02-CONFIGURATION-AND-BASELINES.md) — ⭐ **the Quality Gate and "Clean as You Code"**, the highest-leverage file in this folder.

**Read alongside:** [`../00-WHICH-TOOL-FOR-WHAT.md`](../00-WHICH-TOOL-FOR-WHAT.md) · [`../trivy/00-INSTALL-AND-FUNDAMENTALS.md`](../trivy/00-INSTALL-AND-FUNDAMENTALS.md) · [`../checkov/00-INSTALL-AND-FUNDAMENTALS.md`](../checkov/00-INSTALL-AND-FUNDAMENTALS.md) · [`../../helm-charts-mastery/`](../../helm-charts-mastery/README.md)

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
