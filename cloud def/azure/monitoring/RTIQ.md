# RTIQ — Azure Monitoring (Real-Time Interview Questions)

> **Cloud:** Azure · **Domain:** Azure Monitor, Log Analytics, NSG Flow Logs · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~24 min

**How this file is used live:** for SRE/platform roles, this is the round where you either sound like an operator or don't. They'll ask what you alert on, how you investigate at 3 a.m., how you control log costs, and how you prove network behaviour. Numbers, KQL, and incident narratives win; "we have dashboards" loses.

**Legend:** ⚡ Rapid · 🔍 Deep dive + follow-ups · 🚨 War room · ⚖️ Trade-off debate · 🎯 Senior signal

---

## 1. Azure Monitoring — `azure-monitoring.md`

**⚡ Rapid**
1. **Q:** What are the core components of Azure Monitor?
**A.** Metrics (time-series, 1-min or platform-dependent), Logs (Log Analytics workspace, KQL), Alerts (metric/log/activity/availability), Action Groups (notify/automate), Application Insights (APM), Workbooks/dashboards, and Autoscale. Data sources: platform metrics, resource logs (diagnostic settings), agents (AMA), and the app SDK.
2. **Q:** What minimum alerts do you configure for a web app?
**A.** Availability (synthetic/URL test), 5xx error rate, response-time p95/p99, saturation (CPU/memory capacity or App Service plan metrics), queue/backlog depth, and dependency failures — plus one business KPI (e.g. sign-in or order success rate). Alert on symptoms, dashboard on causes.
3. **Q:** Metric alert vs log (search) alert vs activity log alert?
**A.** Metric: fast, cheap, near-real-time thresholds/dynamic thresholds. Log: KQL queries on a schedule (richer conditions, alerting on patterns/multi-resource). Activity log: control-plane events (resource deleted, role assignment changed, service health). All three have a place.
4. **Q:** What is an action group?
**A.** Notification + action targets: email/SMS/push/voice, webhook, ITSM, Logic App, Function, Automation Runbook, Event Hub. Reuse groups (`oncall-critical`, `security-channel`, `ticket-only`) so alert definitions stay standard.
5. **Q:** What is smart detection in Application Insights?
**A.** Automatic anomaly detection on failure rates/response times/dependency degradation — useful baseline signal, but tune it or it becomes noise. Pair with your own SLO alerts.
6. **Q:** What's the difference between metrics and logs for alerting?
**A.** Metrics are cheap, fast, and good for thresholds/latency; logs are richer (multi-source, joins, string matching) but pay per GB and have query latency. Use metrics for paging and logs for investigation/detailed conditions.
7. **Q:** How do you monitor for "the app is up but broken"?
**A.** Availability tests (URL ping with content match), synthetic user journeys (multi-step), business KPIs from app telemetry, and dependency failure rates. This is the "green dashboard, broken customer" question — always mention business-level signals.

**🔍 Deep dive**
8. **Q:** Design monitoring for a 3-tier app with an SLO of 99.9% and p95 < 500 ms.
**A.** SLO-based alerts: availability from synthetic tests per region; error budget burn-rate alerts (fast burn pages, slow burn tickets); latency p95 metric alerts; dependency latency/failure on the DB and downstream APIs; saturation dashboards (CPU/mem/connections); and business KPIs. Traces (App Insights/OTel) end-to-end with correlation IDs so you can go from alert → trace → failing dependency in one click. Alert routing: pages to on-call, tickets to the team, security to the SOC.
**↳ Follow-up:** "How do you set the thresholds?"
**A.** From the SLA and observed behaviour (load tests + past incidents), not guesses: p95 < 500 ms becomes an alert at ~450 ms for 5 minutes with dynamic thresholds as a secondary, and the burn rate math derives from the error budget over 30 days. Then tune in a weekly ops review using false-positive rate.
9. **Q:** How do you structure Log Analytics workspaces for a large estate?
**A.** Few workspaces, not many (one per region/environment or a central one with resource-context queries) — too many workspaces fragments queries and multiplies cost, while a single workspace can hit ingestion/query limits and RBAC granularity issues. Use resource-context access + table-level RBAC, workspace data retention settings per table, and Sentinel on a dedicated workspace for security data.
10. **Q:** KQL: find the top 5 failing operations in the last 24 hours.
**A.** Something like `requests | where timestamp > ago(24h) | where success == false | summarize failures = count() by name, resultCode | top 5 by failures desc` — or with `AppRequests`/`AppExceptions` tables. The point is fluency with `where/summarize/top/render`, plus `join` across tables and `make-series` for trends.
11. **Q:** How do you correlate a user complaint with telemetry?
**A.** Ask for the timestamp + trace/tenant/user ID, then query by `operation_Id`/session ID across requests/dependencies/exceptions (if the app propagates correlation IDs). If correlation isn't implemented, that's the finding: instrument OTel/W3C trace context across all services and propagate through queues/events too.
12. **Q:** How do you keep Azure Monitor affordable?
**A.** Ingest control: log levels (no debug in prod), sample/filter at the source (agent/DCR transformation, App Insights sampling), direct only needed resource logs via diagnostic settings, exclude noisy tables/categories, set retention per table (short for verbose, long only where required), use basic/auxiliary plans for verbose low-value logs, and archive to Storage for compliance. Cost = ingestion + retention + alerts + queries — measure by table/resource.
13. **Q:** How do you alert on resource deletions or role changes?
**A.** Activity log alerts (or Log Analytics with a query on `AzureActivity`) for delete/update operations on critical resource types, and for security-relevant changes (`Microsoft.Authorization/roleAssignments/write`, key vault policy changes, NSG rule changes). Route to the SOC channel plus the owning team, and include the principal + resource in the alert body.
14. **Q:** How do you monitor multi-region and multi-subscription estates?
**A.** Central workspaces with cross-workspace queries, Azure Monitor alerts at scale via alert processing rules, Dashboards/Workbooks parameterised by subscription/region, and Policy to enforce diagnostic settings on every resource type (otherwise you find gaps when you need the data). Plus Azure Service Health alerts for platform events.
15. **Q:** What is a DCR (data collection rule) and why care?
**A.** DCRs define what data Azure Monitor Agent collects, how it's transformed, and where it's sent — the modern replacement for the per-agent workspace config. They enable filtering/transformation at ingest (cost control) and standardised collection across a fleet. Governance-wise, they should be managed centrally as code.

**🚨 War room**
16. **Q:** 3 a.m. page: "high CPU on app tier". How do you decide whether to wake up?
**A.** That's the wrong alert — CPU alone is a cause, not a symptom. The correct page is latency/error-rate/availability. If you're paged on CPU, first check whether user impact exists (latency/errors/saturation); if not, resolve at a sane hour. Then fix the alert: composite alerts (CPU high AND latency high) or burn-rate-based paging, plus auto-scale as the automatic response.
17. **Q:** An incident happened last night and there's no telemetry for it. What do you do?
**A.** Reconstruct from what exists (activity logs, flow logs, load balancer/app logs, APM if enabled), then close the observability gap: confirm diagnostic settings are applied everywhere (Policy), verify retention covered the window, and add the missing signal. Communicate the gap honestly — "we can't answer that question yet, here's the change to make it answerable" is a senior answer.
18. **Q:** Alert storms: 200 alerts fired for one incident. How do you fix it?
**A.** Correlate/group alerts (alert processing rules, smart groups), alert on the symptom at the edge (availability) rather than every downstream component, set dependencies as "health signals" instead of pages, and add suppression/de-duplication for known cascades. Target: one incident = one page with a rich context payload.
19. **Q:** Query suddenly times out in Log Analytics. Why?
**A.** Querying too wide a time range/too many tables without filters, a workspace that's over-ingested, or a poorly written query (no `where` on indexed fields first). Fix by narrowing time + filters, using summarise before joins, and pre-aggregating with scheduled queries to a summary table for expensive dashboards.
20. **Q:** On-call says they're being paged 15 times a night. What do you do?
**A.** Audit each alert for actionability: delete/convert-to-dashboard the non-actionable ones, add thresholds/grouping for the noisy ones, and automate responses (autoscale, runbooks) where the answer is always the same. Track pages-per-shift and % actionable as metrics; a firefighting culture is a configuration problem.
21. **Q:** After a deploy, error rate is up but the dashboard shows normal. What's missing?
**A.** Deployment markers/correlation — you can't see the change point. Add deployment annotations (App Insights release annotations from the pipeline), version/dimension on metrics, and alert on post-deploy error-rate deviation. This makes "which version caused it" a 10-second question.

**⚖️ Trade-off**
22. **Q:** Azure Monitor vs a third-party (Datadog/Grafana/Splunk)?
**A.** Azure Monitor is native, cheap to start, and integrates with the platform; third parties give better UX, cross-cloud correlation, and long-term analytics at a price. Many shops: Azure Monitor for platform/alerts, third-party for APM/log analytics or multi-cloud, with OpenTelemetry as the portability layer so you're not locked in.
23. **Q:** One central workspace vs per-team workspaces?
**A.** Central: easier cross-service correlation, one retention/cost model, one query surface. Per-team: clearer ownership and RBAC but fragmentated investigations and duplicated costs. Compromise: a few workspaces by domain/environment with resource-context permissions and cross-workspace queries.
24. **Q:** Metrics or logs for alerting?
**A.** Metrics for paging (fast, cheap, reliable), logs for rich conditions and investigation. The anti-pattern is paging on a KQL query over a huge table — slow, expensive, and flaky.
25. **Q:** Sampling on or off for APM?
**A.** Adaptive sampling is usually essential at volume (cost) but it can hide rare errors — use it with "keep all failures/exceptions" behaviour, or sample only successful requests. State your policy explicitly rather than letting the default decide.
26. **Q:** Should every resource have diagnostic settings?
**A.** At minimum all resource types involved in incident response/compliance (key vault, NSG, app gateway, SQL, storage, AKS control plane, activity log). Not everything needs every category — use Policy to enforce a baseline and DCRs to filter the noise.

**🎯 Senior**
27. **Q:** What does "observability" mean to you beyond monitoring?
**A.** The ability to ask new questions without shipping new code: structured logs with consistent schemas, distributed traces with correlation IDs propagated through queues/events, high-cardinality dimensions on metrics, deployment markers, and SLOs tied to user outcomes. Monitoring tells you *that* it broke; observability lets you explain *why* for a case you've never seen before.

**🎯 Senior signal:** "alert on symptoms, dashboard on causes", burn-rate/error-budget alerting, deployment annotations, and pages-per-shift as a health metric. That's a person who runs production.

---

## 2. Log Analytics — `log-analytics.md`

**⚡ Rapid**
1. **Q:** What is the difference between Log Analytics and Application Insights today?
**A.** Application Insights is now workspace-based, storing its telemetry in Log Analytics tables (`AppRequests`, `AppTraces`, `AppExceptions`, `AppDependencies`) — so you query them together in one workspace. Functionally they're one platform with different SDKs/tables.
2. **Q:** What is a workspace data retention model?
**A.** Interactive retention (default 30 days, configurable per table up to 730 in some cases, longer on some tables) plus long-term retention (up to 12 years at lower cost, queryable with `search`/restore). Retention is per-table, so you can keep noisy tables short and compliance tables long.
3. **Q:** Pricing plans?
**A.** Pay-as-you-go per GB (Analytics), Basic logs for high-volume low-touch data (cheaper, limited KQL features), Auxiliary logs for very high volume with even less query capability, plus commitment tiers (100 GB+/day discounts). Choosing the right plan per table is the main cost lever.
4. **Q:** How does access control work?
**A.** Workspace-level RBAC (Log Analytics Reader/Contributor) and resource-context access (see logs only for resources you have RBAC on), plus table-level RBAC for sensitive tables. Good practice: give teams resource-context read, not workspace-wide.
5. **Q:** What is a saved query/function?
**A.** Named, reusable KQL stored in the workspace (`function`) — how you turn tribal queries into self-service investigation tools and standard dashboards.
6. **Q:** What are workbooks?
**A.** Interactive reports built from KQL + parameters (subscription/resource/time), used for service dashboards and drill-downs. They're the shareable layer on top of queries.
7. **Q:** What is Sentinel and when do you need it?
**A.** Microsoft Sentinel is the SIEM/SOAR that runs on a Log Analytics workspace with analytics rules, incidents, hunting queries, and playbooks — needed when you have a SOC and compliance obligations, separate from operational monitoring.

**🔍 Deep dive**
8. **Q:** Design logging for a microservices estate with 40 services and a tight budget.
**A.** Standardised structured JSON logs (consistent fields: timestamp, level, service, version, env, traceId, tenant, duration, status), correlation IDs propagated end-to-end (including through Service Bus/Event Grid), OpenTelemetry instrumentation for traces/metrics, log levels enforced (INFO prod, no debug), DCR transformations to drop noisy fields, high-volume verbose data to Basic/Auxiliary plan, per-table retention tuned, and a small set of curated workbooks/alerts. Central workspace per environment, resource-context RBAC, and Policy enforcing diagnostics.
**↳ Follow-up:** "How do you know the logging standard is actually followed?"
**A.** Automated checks: a query that finds log entries missing the required fields or with unexpected schema, a CI lint of the logging library usage, and a periodic report by service. Also verify trace propagation with a synthetic test that asserts a single trace ID spans all hops.
9. **Q:** KQL: find the slowest 10 dependencies in the last hour with p95.
**A.** `AppDependencies | where timestamp > ago(1h) | summarize p95 = percentile(duration, 95), count() by target, name | top 10 by p95 desc` — plus `render timechart` for trends. Fluency with `percentile`, `summarize`, `bin(timestamp, 5m)`, `join`, and `render` is what they're testing.
10. **Q:** How do you investigate a latency regression with KQL?
**A.** Compare `percentile(duration,95)` by operation over the incident window vs the previous week (`bin(timestamp, 5m)`), break down by dependency/target/region/version, and check whether the regression tracks a deployment (join with a release-annotations table or filter by cloud_RoleVersion). Then drill into a representative trace to see which span dominates. Structure: baseline → change → component → trace.
11. **Q:** How do you control ingestion costs?
**A.** Identify the top tables by volume (Usage/`Usage` table or workspace insights), then: drop unneeded columns via DCR transformation, filter at source (agent-level and app-level), switch noisy tables to Basic plan, reduce verbose logging, exclude health-check/static traffic from request logs, sample APM successes, and set daily caps (careful — a cap can silence incident data). Publish a cost trend and per-team attribution; otherwise nobody changes behaviour.
12. **Q:** How do you handle multi-tenant log isolation?
**A.** Resource-context RBAC won't separate tenants inside one workspace — so either include a `TenantId` dimension and enforce row-level security via queries/dashboards + strict access, or isolate workspaces per tenant (costlier). For strict isolation, use separate workspaces (or Sentinel-style data separation) and be explicit about the trade — many teams ship row-level filtering and later regret it when a customer demands proof of isolation.
13. **Q:** How do you alert on missing data (silent failures)?
**A.** Log alerts with a `count` over a window that should always have data, or metric alerts with `numberOfEvaluationPeriods`/`failingPeriods` handling "no data" as breaching; plus heartbeat queries (`datatable` trick) that alert when a service stops logging. The default behaviour of "no data = OK" is how you get silent outages.
14. **Q:** How do you do log-based anomaly detection?
**A.** Baseline with `make-series` + dynamic thresholds/`series_decompose_anomalies()` in a scheduled query, alert on deviations rather than fixed numbers, and separate seasonal patterns (weekday/weekend, batch windows). Use it for volume anomalies (traffic spikes, error surges, unusual log patterns) where static thresholds fail.

**🚨 War room**
15. **Q:** Log ingestion spiked 5× overnight and the bill is going to be ugly. What happened?
**A.** Query volume by table/service to find the spike source: a debugging level left on, a chatty exception loop (one broken dependency logging thousands of errors), an agent misconfiguration, or a new resource with diagnostics enabled. Fix the source immediately (log level/config), then apply DCR filtering and per-table caps; add an ingestion anomaly alert so it's caught in hours, not at invoicing.
16. **Q:** You need logs from 3 days ago but retention was 7 days and a table got truncated. Options?
**A.** Long-term retention/restore from Archive (if enabled), or restore a bounded time range for query (`restore` command) — if it wasn't archived, the data is gone. Post-incident action: set long-term retention for tables involved in audit/IR, and export critical logs to immutable storage (or Azure Data Explorer/S3-equivalent) for regulatory windows.
17. **Q:** An incident review needs "who did what and from where" — how do you answer from Log Analytics?
**A.** `AzureActivity` table (control-plane operations with caller/IP/resource/status) plus resource logs and `SigninLogs` (if Sentinel/Entra logs are onboarded). Join by correlation ID where available; report the principal, IP, user agent, and timestamp — and note that data-plane reads need diagnostic settings/data events enabled, otherwise the honest answer is "not captured".
18. **Q:** A team says "our dashboards are slow" and queries time out. Fix?
**A.** Reduce the time range and add indexed filters first, avoid `search *`/full-text scans, pre-aggregate expensive dashboards into a summary table via a scheduled query (materialised view-style), reduce the number of panels, and consider Basic plan for high-volume tables where query patterns are simple. Then review the workspace for over-ingestion as the root cause.
19. **Q:** Your KQL alert is firing constantly with false positives. Improve it rather than deleting it.
**A.** Add a minimum-sample condition (`count > N`), an "and sustained for X periods" clause, filter known non-impacting cases (health checks, internal tooling users, test tenants), use dynamic thresholds, and correlate with a second signal (errors AND latency, not just errors). Document the tuning as code so it's reviewed.

**⚖️ Trade-off**
20. **Q:** Log everything vs sample?
**A.** Log everything is expensive and slow to query; sampling loses rare events. Pragmatic: full logs for errors/audit/security, sampled for high-volume success paths, structured so sampling preserves dimensions, and always-full retention for security-relevant tables. Say the policy, not "it depends".
21. **Q:** One workspace vs many?
**A.** Fewer workspaces with resource-context RBAC gives correlation and simpler cost management; many workspaces give isolation (multi-tenant/regulated) but fragment investigations and duplicate cost. Default: per environment (or region) with central queries; isolate only for concrete compliance or tenancy reasons.
22. **Q:** Analytics vs Basic logs plan?
**A.** Analytics for data you query/alert on (full KQL, per-GB cost); Basic for high-volume, low-touch data (cheap ingestion, limited query, 30-day retention-ish, no alerting support in the same way). The right move is per-table: keep operational tables in Analytics, firehose/verbose tables in Basic/Auxiliary.
23. **Q:** Azure Monitor logs vs exporting to a data lake?
**A.** In-workspace for interactive investigation/alerting; export to Storage/Event Hubs/data lake for long-term, cheap, immutable retention and cross-source analytics (Synapse/Databricks/Athena-style). Regulated orgs do both: short interactive + long archive.
24. **Q:** Do you really need Sentinel?
**A.** Only if you're running security operations (incidents, hunting, automation) or a regulator requires SIEM. Otherwise the cost/complexity isn't justified — but Entra sign-in/audit logs and Defender alerts should still be centralised somewhere queryable.

**🎯 Senior**
25. **Q:** You're handed a 60-service platform with no logging standards and a $40k/month Azure Monitor bill. 90-day plan?
**A.** Days 0–30: cost breakdown by table/resource, identify the top 10 sources (usually chatty apps and agents), publish a logging standard (JSON schema + levels + trace IDs), and apply quick DCR filters/plan changes for the worst offenders. Days 30–60: roll out the standard via shared libraries and templates, add OTel instrumentation with correlation across queues, build 5–8 core workbooks/alerts (per service), and set per-table retention. Days 60–90: per-team cost attribution and budgets, ingestion anomaly alerts, an SLO/burn-rate alert set, and a governance loop (Policy enforces diagnostics; the standard is linted in CI). Report the before/after cost and the pages-per-shift trend.

**🎯 Senior signal:** per-table plan/retention thinking, DCR transformation for cost, missing-data alerting, and the ability to write KQL live. Those are the four markers.

---

## 3. NSG Flow Logs (VNet Flow Logs) — `nsg-flow-logs.md`

**⚡ Rapid**
1. **Q:** What are NSG flow logs, in one line?
**A.** Per-NSG records of allowed/denied flows (5-tuple, direction, action, bytes/packets) written to a storage account and/or Log Analytics, with Traffic Analytics aggregating them for querying. The newer VNet flow logs extend this to subnet/NIC-level coverage.
2. **Q:** What fields do they capture?
**A.** Source/destination IP+port, protocol, direction (in/out), action (allow/deny), flow state (B/C/E), packets/bytes sent+received, plus NSG rule name (in the newer schema) and MAC/interface identifiers. Timestamps are flow-window based, not per-packet.
3. **Q:** Where's the cost?
**A.** Storage (per GB written/retained) + optional Traffic Analytics (Log Analytics ingestion) + the processing overhead. Flow logs are cheap-ish at low volume and expensive at high traffic; choose the sampling/aggregation model deliberately.
4. **Q:** Why enable them if nothing's broken?
**A.** They're your forensic and compliance record (who talked to what), the data source for egress/cost analysis (NAT/egress attribution), and the evidence base for micro-segmentation validation. Without them, incident response in Azure networking is guesswork.
5. **Q:** What is Traffic Analytics?
**A.** A solution that ingests flow logs into Log Analytics and produces topology maps, flow visualisations, and KQL-queryable datasets (`AzureNetworkAnalytics_CL`) — the practical layer for humans. It's the difference between raw JSON in a storage account and usable insight.
6. **Q:** Retention?
**A.** Storage retention is your choice (lifecycle policy — 30/90/365 days, archive tier for longer); Log Analytics retention follows the workspace/table policy. Compliance windows drive this, so set lifecycle rules from day one.
7. **Q:** Do flow logs capture the payload or DNS names?
**A.** No payload, and DNS names only via Traffic Analytics enrichment (DNS resolution from the agent) — raw flow logs are IP-based, so you need DNS context (or name resolution datasets) to answer "which service was this?".

**🔍 Deep dive**
8. **Q:** How do you use flow logs to prove segmentation to an auditor?
**A.** Export/query the accepted flows per tier over a period, produce a flow matrix (source tier/subnet → destination tier, port, protocol), compare it against the approved matrix, and show the denied attempts that evidence the rules working. Combine with effective NSG rules export and a change history from IaC — the "approved vs actual" comparison is the deliverable.
9. **Q:** Egress traffic costs doubled — how do flow logs help?
**A.** Aggregate bytes by destination IP/FQDN (with Traffic Analytics), map to services (Blob, update endpoints, third parties), then attribute to source VMs/subnets for owner accountability. Typical findings: storage reads not using private endpoints, backup traffic, container image pulls, monitoring agents, or a misconfigured app pulling large data over the internet. Then fix the path (private endpoints) or the workload.
10. **Q:** Design flow-log collection for 60 subscriptions.
**A.** Central storage account (or one per region) with lifecycle policies, Traffic Analytics into a central workspace (per environment), Azure Policy to auto-enable flow logs on every NSG/VNet, RBAC so only security/network can read the raw logs, and dashboards/alerts on top (denied spikes, unexpected external destinations). Also plan ingestion cost with sampling/traffic-analytics interval settings.
11. **Q:** How do you detect a compromised VM using flow logs?
**A.** Look for: outbound connections to rare/unexpected destinations (especially non-standard ports), sudden large data egress, connections to known-bad IPs (threat intel enrichment), beaconing patterns (regular interval/small packets), and lateral movement attempts inside the VNet (denied scans, SMB/RDP between tiers). Correlate with Defender for Cloud/Defender for Servers alerts, and pivot on the VM's IP in KQL.
12. **Q:** How do you find a "chatty service" problem with flow logs?
**A.** `AzureNetworkAnalytics_CL` aggregated by source/destination over a window; sort by connection count and bytes, look for high-frequency small flows (polling every second), cross-AZ or cross-region pairs that should be local, and health checks hitting backends too often. Fix by batching, caching, co-locating, or reducing probe/agent frequency — and then prove the drop in the logs.
13. **Q:** What are the limitations of flow logs?
**A.** No payload/content inspection, IP-only (needs DNS context), flow-window granularity (sub-minute detail isn't per-packet), potential gaps when logs are disabled or storage is unreachable, cost at scale, and no insight into encrypted traffic's contents. Be explicit — interviewers check whether you oversell them.
14. **Q:** How do you troubleshoot a specific connectivity problem with flow logs?
**A.** Filter by the 5-tuple in the storage logs/Traffic Analytics, check the action (`A` allow / `D` deny) and the rule name, then correlate the direction and the return flow: an allow with no return flow means the response is blocked elsewhere (asymmetric rules, UDR, host firewall). This is faster than guessing at NSGs.

**🚨 War room**
15. **Q:** An incident happened 10 days ago and you need the flows, but flow logs were off for that NSG.
**A.** You can't recover them — be honest in the postmortem and immediately fix coverage: Policy-enforced flow logs on all NSGs/VNets, monitored "flow log enabled" state, and an alert when flow logs are disabled (that's an attacker technique too — disabling logging). Use other evidence in the meantime (activity logs, LB/App Gateway logs, host logs).
16. **Q:** Alert: the flow log storage account was deleted.
**A.** Treat as a potential anti-forensics event if it was unplanned: check who deleted it (activity log), whether logging is now off across the estate, and restore/recreate the account (soft delete/blob versioning may save data) plus re-enable logging. Then protect it: resource locks on the log storage account, restricted IAM (no delete), and alerts on delete operations.
17. **Q:** You suspect an internal host is port-scanning the VNet.
**A.** Query for many denied connections from one source with varied destination ports/IPs in a short window; identify the VM, isolate it (NSG deny-all/quarantine subnet), snapshot for forensics, and check Defender alerts plus any successful follow-on connections. Then ensure the segmentation rules that stopped it are documented as controls that worked.
18. **Q:** Flow logs show traffic to an unexpected external IP:port from a production subnet. Investigate and respond.
**A.** Identify the VM/process, resolve the IP to a service/owner (reverse DNS/whois/threat intel), check whether data volumes indicate exfiltration, then contain (block at the firewall/NSG, isolate the VM if malicious). Post-incident: add the destination to an alerting rule (new-destination detection) and tighten egress to an allow-list.
19. **Q:** Traffic Analytics cost is significant and the workspace is over-ingested. Reduce without losing forensics.
**A.** Increase the Traffic Analytics processing interval (e.g. from 10 to 60 min) for non-critical networks, keep raw flow logs in storage (cheap) as the forensic record, restrict Traffic Analytics to the VNets that matter, shorten Log Analytics retention for those tables and rely on storage lifecycle for long-term, and alert only on curated detections rather than storing everything hot.

**⚖️ Trade-off**
20. **Q:** NSG flow logs vs VNet flow logs vs Azure Network Watcher packet capture?
**A.** NSG flow logs: per-NSG metadata. VNet flow logs: broader (subnet/NIC coverage, unified) and the direction Microsoft is heading — prefer VNet flow logs for new deployments. Packet capture: full payload for deep troubleshooting, expensive and short-term, used case-by-case with consent. Different tools for different questions.
21. **Q:** Storage-only flow logs vs Traffic Analytics?
**A.** Storage-only is cheap and fine for archives/forensics if you can parse JSON yourself; Traffic Analytics costs more but gives queryability, topology, and enrichment that makes incidents tractable. Practical answer: store raw in storage (long retention) + Traffic Analytics for the networks you actively operate.
22. **Q:** Enable flow logs everywhere vs selectively?
**A.** Everywhere is the compliance/IR-correct answer if you can afford ingestion and storage lifecycle (raw logs to cheap tiers). Selective (production + sensitive segments) is the budget answer with a documented gap. Never leave an unmonitored production network with no forensic record.
23. **Q:** Flow logs vs Defender for Cloud/Defender for Servers for threat detection?
**A.** Flow logs are raw evidence and volume/cost analysis; Defender provides detections and alerts (network anomalies, crypto-mining, lateral movement) with less noise and more context. Use both: Defender for the alert, flow logs for the evidence and scope.

**🎯 Senior**
24. **Q:** You're asked for a network-flow inventory across 60 subscriptions to support a zero-trust programme. Plan?
**A.** Policy-enforced VNet flow logs + central storage with lifecycle, Traffic Analytics to a central workspace, a normalisation pipeline into a flow dataset (ADX/Synapse for scale), a published tier/flow matrix compared against approved policy with owners per flow, denied-flow dashboards for enforcement validation, alerting on new destinations and egress anomalies, and a quarterly review that converts unapproved flows into either justified exceptions or closed rules. Deliverable: an approved-vs-actual matrix that shrinks over time.

**🎯 Senior signal:** "flow logs are the forensic record and the egress-attribution source", knowing flows are IP-only without DNS enrichment, and the anti-forensics angle (protect/alert on the log storage). That's real security-and-NOC maturity.
