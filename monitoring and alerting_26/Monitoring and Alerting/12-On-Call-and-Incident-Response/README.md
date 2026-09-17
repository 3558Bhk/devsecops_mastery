# 12 · On-Call & Incident Response

**Level:** operational · **Time:** ~2 h · **Goal:** turn alerts into resolved incidents with a process that doesn't burn people out — runbooks, escalation, communication, postmortems.

---

## 1. The chain from alert to resolution

```
alert fires ─► grouped notification ─► page ─► ACK (≤5 min) ─► triage
                                                                  │
                     ┌────────────────────────────────────────────┘
                     ▼
        declare incident (sev) ─► open channel ─► assign roles ─► runbook
                     │                                            │
                     ▼                                            ▼
              status updates every 30m ◄────────────── mitigate / fix
                     │                                            │
                     ▼                                            ▼
                 resolve ─► alert auto-resolves ─► postmortem (≤5 days) ─► action items
```

Every arrow is a place monitoring quality shows up: a bad alert wastes step 1–3; a missing runbook wastes step 5; a missing resolution notification wastes step 8.

---

## 2. Roles during an incident (assign them explicitly)

| Role | Job | Notes |
|---|---|---|
| **Incident Commander (IC)** | Owns the incident, makes decisions, delegates, does not type commands | Usually the on-call engineer until someone more senior takes over |
| **Operations / Lead** | Executes the fix, runs the commands | Should not be coordinating |
| **Communications** | Status page, stakeholder updates, timeline notes | Frees the IC |
| **Scribe** | Keeps the timestamped log | Becomes the postmortem draft |
| **Subject-matter experts** | Pulled in on demand | DB, network, third-party vendor |

For a small team one person wears IC + Comms; the **rule that matters** is that whoever is typing commands is not also deciding strategy and writing updates.

---

## 3. Runbooks — the link between an alert and an action

Every pageable alert has a runbook URL in its `annotations.runbook`. A runbook is not documentation; it is **a script for a tired person at 3 a.m.**

### Template

```markdown
# Runbook: CheckoutHighErrorRate
Alert: `CheckoutHighErrorRate` / `CheckoutSLOFastBurn`   Severity: page   Owner: @checkout-team
Last reviewed: 2026-09-01 by Priya   Next review: 2026-12-01

## What this means
Users are getting 5xx responses from checkout. Error budget is burning ≥14.4× too fast.
Business impact: lost orders. Money.

## Triage (do these first, in order — 5 minutes)
1. Open the dashboard: https://grafana.example.com/d/checkout-slo?var-service=checkout-api&from=now-1h
   - Is the error rate up across ALL endpoints or one? → one = code/config issue
   - Did a deploy happen in the last 60 min? (annotation line on the graph) → roll back first, investigate later
2. Check dependency health: payments API, inventory DB, Redis
   `sum(rate(http_requests_total{job="checkout-api",status=~"5.."}[5m])) by (upstream)`
3. Check saturation: are pods at CPU/memory limits? HPA at max?
   `kubectl -n checkout top pods` ; Grafana → Kubernetes / Compute Resources / Namespace
4. Read the errors: Grafana → Logs, `{app="checkout-api", level="error"}` last 15m, group by `err`

## Mitigations (pick the first that fits)
| If you see | Do |
|---|---|
| Recent deploy | `kubectl -n checkout rollout undo deploy/checkout-api` |
| One upstream failing | Enable the circuit breaker flag: `checkout.upstream.payments.fallback=true` |
| Pods OOMKilled | `kubectl -n checkout patch deploy checkout-api -p '{"spec":{"template":{"spec":{"containers":[{"name":"api","resources":{"limits":{"memory":"2Gi"}}}]}}}}'` |
| DB connection pool exhausted | Raise pool max via config, then investigate leak |
| Traffic spike / abuse | Enable rate limit profile `checkout-burst` at the ingress |
| Region-level failure | Fail over: `kubectl config use-context prod-eu && ...` |

## Escalation
- 15 min and no progress → page the checkout secondary: `amtool` / PagerDuty escalation policy
- 30 min and customer-visible → declare Sev-1, notify #incidents and the comms lead, update the status page
- DB involved → page @dba-oncall ; network → @netops

## Verification
Error ratio back under 0.1% for 15 minutes AND the burn-rate alert has resolved AND a
synthetic checkout completes: https://grafana.example.com/d/synthetic

## After
- Keep the incident channel; the scribe posts the timeline.
- Postmortem due within 5 working days (template below).
- If this runbook was wrong or incomplete, fix it in the same PR as the action item.
```

**Runbook quality rules:**
- Every step is a **command or a link**, not prose.
- Ordered by likelihood, not by architecture.
- Includes a **"how do I know it's fixed"** section.
- Reviewed quarterly; the review date is in the header.
- Lives next to the alert rule in Git, so changing one prompts changing the other.
- If an alert has no runbook → it isn't allowed to page. Enforce with a CI check that every `severity: page` rule has a `runbook` annotation.

---

## 4. Severity levels for incidents (distinct from alert severity)

| Sev | Definition | Response | Comms |
|---|---|---|---|
| **Sev-1 / P1** | Major customer impact, revenue or safety at risk, no workaround | All hands, IC + comms, exec aware | Status page + updates every 15–30 min |
| **Sev-2 / P2** | Significant degradation for many users, workaround exists | On-call + SME | Internal channel, updates hourly |
| **Sev-3 / P3** | Limited impact, few users, or a single non-critical service | On-call during business hours | Ticket |
| **Sev-4** | Cosmetic / no user impact | Backlog | None |

Declare severity early and **downgrade openly** when justified. An undeclared Sev-1 is how small teams get run over.

---

## 5. On-call operations

| Practice | Detail |
|---|---|
| **Rotation** | 1 week (or 2 weeks) minimum; never less than 4 people in a rotation (burnout); ≥6–8 is humane |
| **Handover** | A written + verbal handoff: active incidents, noisy alerts this week, upcoming changes, silences in place |
| **Compensation** | Retainer + per-page, or time off in lieu. Non-negotiable for sustainable on-call |
| **Escalation policy** | Primary (5 min) → Secondary (10 min) → Manager/Team (20 min) → Vendor. Configure in PagerDuty/Opsgenie/Grafana OnCall, not in people's heads |
| **Ack discipline** | Every page must be acknowledged. An unacked page escalates automatically |
| **Alert budget** | Target < 2 pages per shift; > 5 means the alerting is broken and gets fixed that week |
| **Follow-the-sun** | If you have teams in multiple regions, hand off rather than waking one region |
| **Shadowing** | New on-call shadows a full rotation before going primary |
| **Tooling** | On-call phone/laptop with VPN + `kubectl` + Grafana bookmarks pre-installed; test them *before* the shift |

Tools: **PagerDuty**, **Opsgenie (Atlassian)**, **Grafana OnCall / Grafana IRM**, **incident.io**, **FireHydrant**, **Rootly**, **Keep**, **SigNoz alerting**. All integrate with Alertmanager via a receiver (`pagerduty_configs`, `opsgenie_configs`, `webhook_configs`).

---

## 6. Maintenance windows and change management

- **Create a silence before** planned work: `amtool silence add --duration=2h --comment="k8s upgrade prod-2" cluster="prod-2"` — narrow matchers, always a comment, always an expiry.
- **Change freeze windows**: model as `time_intervals` (e.g. `change-freeze` in December) or as a policy, not as alert suppression. Don't mute your ability to see problems during a freeze — freeze the *changes*, not the *monitoring*.
- **Deploy annotations on dashboards** make "did we break it?" a 2-second question. Every incident review starts there.
- **Track change success rate** as a metric: `deploys per week`, `change failure rate`, `MTTR`. These are DORA metrics and they are the honest output of your alerting quality.

---

## 7. Postmortems (blameless, actionable)

Write it within **5 working days** while memory is fresh. Blameless ≠ consequence-free: it means analysing systems and decisions, not people. "Priya forgot" is not a cause; "the deploy tool allowed a config with no validation" is.

```markdown
# Postmortem: Checkout 5xx storm — 2026-09-12, 14:02–14:47 IST (Sev-2)

## Summary
45 minutes of elevated checkout errors (peak 18% 5xx) affecting ~12,400 orders,
~$38k of abandoned carts. Caused by a connection-pool exhaustion in the payments
client after a config change reduced max connections from 200 to 20.

## Impact
- SLO: error budget reduced from 78% to 31% in 45 minutes (fast-burn alert fired correctly)
- 12,400 failed checkout attempts; 8,900 recovered via retry
- Sev-2 declared 14:09; resolved 14:47

## Timeline (IST)
13:58  Config PR #4821 merged (payments client pool 200 → 20), auto-deployed
14:02  CheckoutSLOFastBurn fires → pages on-call (2 min detection)
14:04  ACK by @ravi
14:07  Dashboard shows 5xx concentrated on /checkout/complete
14:11  Sev-2 declared, #inc-2026-0912 opened
14:19  Root cause suspected: `payments_client_pool_wait_seconds` p99 at 30s
14:24  Rollback of PR #4821 initiated
14:31  Rollout complete across 40 pods
14:38  Error ratio < 0.1%
14:47  Alert resolved, Sev-2 closed

## What went well
- Detection in 2 minutes; burn-rate alerting worked exactly as designed
- Runbook step 1 (check recent deploys) led to the cause in 9 minutes
- Rollback was a single command and safe

## What went badly
- The config change had no validation and no review of blast radius
- No alert on `payments_client_pool_wait_seconds` — a leading indicator we had but never watched
- Deploy annotation was present but the dashboard's default 6h view buried it
- On-call had to guess which of three dashboards was authoritative

## Where we got lucky
- Traffic was at a weekday low; the same change at 19:00 would have been Sev-1

## Root cause
A configuration value governing the payments HTTP client connection pool was reduced
by a factor of 10, causing pool exhaustion and request timeouts under normal load.

## Contributing factors
- Config values are untyped strings with no bounds checking
- No canary/progressive delivery for config changes (only for code)
- The pool-wait metric existed but had no dashboard panel and no alert

## Action items
| # | Action | Owner | Due | Type |
|---|---|---|---|---|
| 1 | Add bounds validation + unit test for payments client config | @priya | 2026-09-26 | Prevent |
| 2 | Alert on `payments_client_pool_wait_seconds` p99 > 1s for 5m | @ravi | 2026-09-19 | Detect |
| 3 | Add pool-wait and pool-utilisation panels to the checkout dashboard | @ravi | 2026-09-19 | Detect |
| 4 | Canary rollout for config changes (5% → 50% → 100%) | @platform | 2026-10-15 | Prevent |
| 5 | Make deploy annotations show by default on service dashboards | @platform | 2026-10-01 | Detect |
| 6 | Link the authoritative dashboard from every checkout alert annotation | @priya | 2026-09-22 | Respond |

## Metrics
MTTD 2 min · MTTA 2 min · MTTR 45 min · change failure rate this quarter 6%
```

**Postmortem review ritual:** a weekly 30-minute meeting where new postmortems are read, action items are tracked to completion, and **alert-quality items get assigned like any other work**. Track "% action items completed within 30 days" — teams with low completion rates repeat their incidents.

---

## 8. Measuring your monitoring (the meta-metrics)

| Metric | Definition | Target |
|---|---|---|
| **MTTD** | Failure start → first alert | < 2 min |
| **MTTA** | Alert → human ack | < 5 min |
| **MTTR** | Failure → service restored | Trend down |
| **Alert precision** | Pages that led to real action ÷ total pages | > 80% |
| **Alert recall** | Incidents detected by monitoring ÷ total incidents | 100% (any user-reported outage is a monitoring bug) |
| **Pages per shift** | Count | < 5 |
| **% alerts with runbook** | Count | 100% for `page` |
| **% alerts resolved automatically** | Count | > 90% |
| **Noisy-alert count** | Alerts fired > 10×/week with no action | 0 (reviewed weekly) |
| **Action-item completion** | Postmortem items done within 30 days | > 90% |
| **Change failure rate / deploy frequency** | DORA | Improve together |

Review these monthly. **"Every incident reported by a user before monitoring caught it gets a bug filed against the monitoring system."** That single rule raises alert recall faster than anything else.

---

## 9. Automation and self-healing (use carefully)

| Level | Example | Guardrails |
|---|---|---|
| **Alert → webhook → script** | Restart a stuck consumer, clear a full temp dir | Idempotent, rate-limited, logged, dry-run mode |
| **Kubernetes native** | HPA, VPA, PDB, liveness/readiness probes, `restartPolicy` | Prefer platform mechanisms over custom scripts |
| **Alertmanager webhook receiver** | `webhook_configs` → your remediation service | Set `max_alerts`, verify signatures, and require the alert to be a *specific* fingerprint |
| **Runbook automation** | Kept, Rundeck, StackStorm, n8n, custom operator | Human approval for anything destructive |
| **Full auto-remediation** | Rollback on error-budget burn | Only for well-understood, reversible actions; always notify a human that it happened |

Rules: automate **mitigation** that is reversible and well-tested; never automate destructive or irreversible actions without approval; always emit a notification saying "I did X"; keep an audit log; and have a kill switch.

---

## 10. Self-check

1. What are the five incident roles and which one must not be typing commands?
2. What six sections does a good runbook contain?
3. How do you decide Sev-1 vs Sev-2, and who declares it?
4. What's the minimum sane on-call rotation size and why?
5. Name the difference between alert severity and incident severity.
6. What is a blameless postmortem, and what makes an action item good?
7. Define MTTD, MTTA, MTTR, alert precision, alert recall.
8. What single policy most improves alert recall?
9. When is auto-remediation appropriate, and what guardrails does it need?
10. A page arrives with no runbook link. What are the three process failures that allowed it?

→ Next: [`13-Alert-Rules-Library`](../13-Alert-Rules-Library/README.md)
