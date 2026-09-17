# 00 · Start Here

## What "mastering monitoring and alerting" actually means

You can recite definitions, or you can do the job. Mastery looks like this — can you, without Googling:

1. Look at a broken service and say **which 4 numbers** you'd check first.
2. Write a **PromQL query** that answers a real question about latency or errors.
3. Write an **alert rule** that pages someone only when a user is actually suffering.
4. Configure **Alertmanager** so 400 firing alerts arrive as 3 grouped notifications to the right team.
5. Build a **dashboard** that a new joiner can read in 30 seconds during an incident.
6. Define an **SLO**, compute the **error budget**, and defend a decision with it.
7. Diagnose **why your Prometheus is slow / out of memory** (cardinality).
8. Run a **postmortem** that changes something.

Every README in this folder exists to make one of those eight sentences true. Keep this list on your wall.

---

## The mental model to install first

```
        ┌──────────────────────────────────────────────────────────────┐
        │  WHAT HAPPENED?            WHY?              WHICH REQUEST?   │
        │  metrics                   logs              traces           │
        │  (numbers over time)       (events)          (request paths)  │
        └───────┬───────────────────────┬──────────────────┬───────────┘
                │                       │                  │
                ▼                       ▼                  ▼
        ┌──────────────┐        ┌──────────────┐    ┌──────────────┐
        │ Prometheus / │        │ Loki / ELK / │    │ Tempo /      │
        │ VictoriaM.   │        │ CloudWatch   │    │ Jaeger / X-Ray│
        └──────┬───────┘        └──────────────┘    └──────────────┘
               │  (this folder is mostly here)
               ▼
     ┌───────────────────┐      ┌────────────────┐      ┌─────────────┐
     │ Recording rules   │ ───► │ Alert rules    │ ───► │ Alertmanager│
     │ (precompute SLIs) │      │ (when to fire) │      │ group/route │
     └───────────────────┘      └────────────────┘      │ inhibit/sil.│
                                                        └──────┬──────┘
                                                               ▼
                                          Slack · PagerDuty · Email · Webhook
                                                               ▼
                                                   Human + Runbook
```

Read it left to right once, then again after topic 09. It will mean something completely different the second time.

---

## Two vocabulary traps that confuse everyone at the start

| Term | Loose usage | Precise usage (use this one) |
|---|---|---|
| **Monitoring** | "everything about watching systems" | Collecting and visualising telemetry. Answers *what is happening*. |
| **Alerting** | "monitoring" | Deciding something needs action and notifying a human/machine. Answers *who must act now*. |
| **Observability** | buzzword for "we have Grafana" | A property of the system: can you understand a *novel* failure from its outputs? Metrics+logs+traces+profiling are the instruments; observability is the outcome. |
| **Alert** (Prometheus) | — | A rule that evaluates to a non-empty vector = an alert in `PENDING`/`FIRING` state. |
| **Notification** | — | What Alertmanager actually sends after grouping/routing/inhibition. One notification can contain many alerts. |

**Alert ≠ notification.** Half of all Alertmanager confusion comes from conflating them.

---

## Set up your practice environment (15 minutes)

You cannot learn this by reading. Two options:

### Option A — the bundled lab stack (recommended)
Everything you need is in [`../16-Labs`](../16-Labs/README.md): a `docker-compose.yml` that starts Prometheus 3, Alertmanager, node_exporter, blackbox_exporter and Grafana, plus six guided labs that break things on purpose.

```bash
cd 16-Labs
docker compose up -d
# Prometheus     http://localhost:9090
# Alertmanager   http://localhost:9093
# Grafana        http://localhost:3000   (admin / admin)
```

### Option B — Kubernetes (if you have a cluster)
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kps prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace
kubectl -n monitoring port-forward svc/kps-grafana 3000:80
```
Topic `08-Kubernetes-Monitoring` covers this properly.

### Tools to have on your PATH
| Tool | Purpose | Install |
|---|---|---|
| `promtool` | Validate config & rules, unit-test rules, analyse TSDB | Ships with Prometheus |
| `amtool` | Query/silence alerts from the CLI, validate Alertmanager config | Ships with Alertmanager |
| `promql-lint` / Grafana Explore | Iterate on queries | Grafana |
| `curl`, `jq` | Poke HTTP APIs | your package manager |

```bash
promtool check config prometheus.yml
promtool check rules rules/*.yaml
promtool test rules tests/alert_test.yaml
amtool check-config alertmanager.yml
```
**Habit to build from day one:** never apply a config you have not `check`ed. CI should run these four commands on every PR that touches monitoring.

---

## A study method that works for this subject

For each topic README:

1. **Read it once fast** — get the shape, don't memorise.
2. **Type every config block by hand** into your lab. Typing is not a waste of time; it is where the syntax enters long-term memory, and where you hit the errors that teach you.
3. **Break it deliberately.** Change a threshold, remove a label matcher, typo a unit. Watch what happens. This is the single highest-yield activity in the whole folder.
4. **Answer the Self-check questions** without looking.
5. **Write one thing of your own** — a rule, a query, a panel — for a service you actually care about (your laptop, a side project, your company's app).

Time budget: ~1.5 h per concise topic, ~3–4 h per `★` deep-dive topic, plus labs. Roughly 45–60 hours total for genuine mastery.

---

## Keep a lab journal

Create `16-Labs/JOURNAL.md` and log one line per session:

```
2026-09-14 | Lab 4 | Made `for: 30s` alert flap by lowering threshold to 0.1; learned
             group_wait vs group_interval difference the hard way. Next: inhibition rules.
```

Three weeks of that journal is worth more than three weeks of highlighting.

---

## Next

→ [`01-Monitoring-Fundamentals`](../01-Monitoring-Fundamentals/README.md)
