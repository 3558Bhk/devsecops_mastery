# SRE Concepts - SDE3 Must Know

## SRE = Site Reliability Engineering (Google)

- Apply software engineering to operations, automate ops, 50% ops 50% dev

## Core Concepts

### SLA vs SLO vs SLI

| Term | Meaning | Example | Who defines |
|------|---------|---------|-------------|
| **SLA** | Service Level Agreement - Contract with customer, if breach penalty | 99.9% uptime per month, if not 10% credit | Business + Customer |
| **SLO** | Service Level Objective - Internal target, should be stricter than SLA | 99.95% uptime, P95 latency <200ms | SRE + Product |
| **SLI** | Service Level Indicator - Actual measurement | Measured uptime 99.96%, P95 latency 180ms | Metric |

- **SLA is business, SLO is internal goal, SLI is measurement**
- SLO should be tighter than SLA to have buffer

### Error Budget

- Error Budget = 100% - SLO
- If SLO 99.9%, error budget 0.1% = 43 min downtime per month
- If error budget exhausted (too many errors/downtime), freeze features, focus on reliability
- If error budget plenty, can take more risks, deploy faster, experiment
- **Burn Rate**: How fast error budget burning, burn rate 1 = exactly at SLO, burn rate 10 = 10x faster burning, need alert

Example:
- SLO: 99.9% uptime per 28 days = 40 min budget
- If 20 min downtime in first week, 50% budget burned, burn rate 2, okay but watch
- If 40 min downtime in 2 days, budget exhausted, freeze releases

### Toil

- Manual, repetitive, automatable, no enduring value, scales with service growth
- Examples: Manual deploys, manual ticket handling, manual scaling
- SRE goal: Automate toil, keep toil <50% of time
- If toil >50%, need automation project

### MTTR, MTBF, MTTF, MTTD

- **MTTR**: Mean Time To Repair/Recovery - how long to fix after failure, lower is better
- **MTBF**: Mean Time Between Failures - how long between failures, higher is better
- **MTTF**: Mean Time To Failure - for non-repairable
- **MTTD**: Mean Time To Detect - how long to detect failure

- Availability = MTBF / (MTBF + MTTR)

### Observability already covered

## SRE Practices

### 1. Automation
- Automate everything: Deployments, scaling, failover, testing, monitoring
- IaC: Terraform, Ansible
- CI/CD: Automated pipelines

### 2. Monitoring & Alerting
- Golden signals: Latency, Traffic, Errors, Saturation
- SLO based alerting: Alert on burn rate, not just CPU
- Runbooks for each alert

### 3. Incident Management

#### Incident Lifecycle
1. Detect (monitoring alert)
2. Triage (severity: SEV1 critical prod down, SEV2 major, SEV3 minor)
3. Mitigate (rollback, failover, scale, quick fix) - aim to reduce MTTR
4. Resolve (root cause fix)
5. Post-mortem (blameless)

#### Blameless Post-mortem
- No blame person, focus on system/process
- 5 Whys to find root cause
- Action items to prevent recurrence
- Document: Timeline, impact, root cause, what went well, what didn't, action items

#### On-Call
- Rotation, primary/secondary, escalation policy
- Alert only actionable, page only critical (avoid fatigue)
- Compensation for on-call

### 4. Capacity Planning
- Forecast growth, load testing, auto scaling, quota management
- Example: QPS grows 10% per month, need to add 2 servers per quarter

### 5. Change Management
- Progressive delivery: Canary, blue-green, feature flags
- Automated canary analysis (Kayenta)
- Rollback plan always

### 6. Chaos Engineering
- Intentionally inject failures to test resilience
- Tools: Chaos Monkey (kills random instances), Litmus, Gremlin, Chaos Mesh (K8s)
- Experiments: Kill pod, add latency, fill disk, blackhole network
- Game Days: Practice incident response

## SRE vs DevOps

| SRE | DevOps |
|-----|--------|
| Google's implementation of DevOps | Culture/philosophy |
| Prescriptive (SLO, error budget, toil) | Broad principles (CALMS) |
| Strong focus on reliability via engineering | Focus on collaboration Dev+Ops |
| Uses DevOps practices | Includes SRE as part |

- Both aim to bridge Dev and Ops, automate, CI/CD

## Error Budget Policy Example

```
If error budget >50% remaining: Normal release velocity
If 25-50%: More careful, extra review
If 10-25%: Freeze non-critical features, focus on reliability
If <10% or exhausted: Freeze all features except critical bug fixes for reliability
```

## DORA Metrics (DevOps Research)

- **Deployment Frequency**: How often deploy to prod (Elite: multiple per day)
- **Lead Time for Changes**: Time from commit to prod (Elite: <1 hour)
- **Change Failure Rate**: % deployments causing failure (Elite: 0-15%)
- **MTTR**: Time to restore after failure (Elite: <1 hour)

- Elite performers have high DF, low LT, low CFR, low MTTR

## Interview Q

**Q: How to set SLO for a service?**
- Choose SLI: Availability (success requests / total), Latency (P95), Throughput, maybe business SLI (orders success rate)
- Set SLO based on user expectations and business: 99.9% for internal, 99.99% for critical payment, latency <200ms P95
- Start with loose SLO then tighten as you improve
- Monitor SLI vs SLO, alert on burn rate

**Q: What if error budget exhausted?**
- Freeze feature releases, focus on reliability: Bug fixes, tech debt, performance, add tests, improve monitoring, capacity, post-mortems action items

**Q: How to reduce toil?**
- Identify repetitive tasks >50%, automate via scripts, tools, self-service platforms, chatbots, runbooks automation

**Q: How to handle on-call alert fatigue?**
- Only alert actionable, tune thresholds, use SLO burn rate not CPU, have runbooks, aggregate similar alerts, use severity, no info alerts as pages, improve signal-to-noise

## SRE Golden Rules

1. 50% of SRE time should be dev (automation, features for reliability)
2. Error budget is key to balance velocity and reliability
3. Blameless culture
4. Monitor user experience not just CPU (SLI = user happiness)
5. Automate toil
6. Progressive delivery
