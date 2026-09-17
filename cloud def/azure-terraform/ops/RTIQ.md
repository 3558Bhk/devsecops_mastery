# RTIQ — Terraform Operations & Monitoring on Azure (Real-Time Interview Questions)

> **Cloud:** Azure · **Tool:** Terraform · **Domain:** Azure Monitor, Log Analytics, alerts, Blueprints/APIOps, Service Bus & Event Grid · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~13 min

**How this file is used live:** this is the SRE-leaning Terraform round: how you make a platform observable, how you alert, how you evolve Azure Policy/Blueprints alongside infrastructure, and how you build messaging that survives failure. Expect "what alerts would you create by default?" and "the queue is backing up — walk me through it."

**Legend:** ⚡ Rapid · 🔍 Deep dive · 🚨 War room · ⚖️ Trade-off · 🎯 Senior signal

---

**⚡ Rapid**
1. **Q:** Core Terraform resources for Azure monitoring?
**A.** `azurerm_log_analytics_workspace` (+ `azurerm_log_analytics_solution`, saved searches/query packs), `azurerm_monitor_metric_alert`, `azurerm_monitor_scheduled_query_rules_alert_v2`, `azurerm_monitor_action_group`, `azurerm_monitor_diagnostic_setting` (per resource), `azurerm_application_insights`, `azurerm_monitor_workspace` + `azurerm_monitor_data_collection_rule`/association, and `azurerm_monitor_autoscale_setting`.
2. **Q:** What's the alerting flow on Azure?
**A.** Resource → diagnostic settings/metrics → Log Analytics or Azure Monitor metrics → alert rule (metric or scheduled query) → action group (email/SMS/Teams/webhook/Logic App/Function/ITSM) → on-call tooling. Terraform manages every link except the human process; the action group is the piece that decides whether anyone is paged.
3. **Q:** Metric alert vs log (scheduled query) alert?
**A.** Metric alerts evaluate platform/custom metrics (fast, ~1 min, cheap) and suit latency/CPU/availability; scheduled query alerts (KQL, `azurerm_monitor_scheduled_query_rules_alert_v2`) query logs or metrics with thresholds/dimensions and suit business/error-pattern conditions — with the size-based cost and a minimum 1-minute frequency. Default to metric alerts for paging.
4. **Q:** How do you create an action group properly?
**A.** `azurerm_monitor_action_group` with `short_name` (used in SMS), `enabled`, and receiver blocks (email/SMS/webhook/Logic App/Function/`automation_runbook`/`itsm`/`voice`); plus a common schema for webhooks where the consuming tool needs structure. One group per rotation/severity, reused by many alerts — not one group per alert.
5. **Q:** How do you turn on diagnostics for many resources?
**A.** `azurerm_monitor_diagnostic_setting` per resource (they're separate resources), parameterised by the module that creates the resource, or — at scale — Azure Policy with a `deployIfNotExists` effect that creates diagnostics for every new resource (and a remediation task for existing ones). Policy is how you guarantee coverage across teams.
6. **Q:** Core Terraform resources for messaging?
**A.** `azurerm_servicebus_namespace` (+ `azurerm_servicebus_queue`/`_topic`/`_subscription`, `_namespace_authorization_rule`), `azurerm_eventhub_namespace`/`azurerm_eventhub`, `azurerm_eventgrid_topic`/`azurerm_eventgrid_event_subscription`, and `azurerm_storage_queue`/`azurerm_storage_account` for simple queues.
7. **Q:** How do you do DLQ handling on Service Bus?
**A.** `forward_dead_lettered_messages_to` on the subscription/queue (funnelling dead letters to a central DLQ entity) or the default DLQ per entity with an alert on its depth; plus `max_delivery_count`, `dead_lettering_on_message_expiration`, and `dead_lettering_on_filter_evaluation_exception`. Then a replay process (Service Bus Explorer/Function) that is documented and idempotent.
8. **Q:** Where do Service Bus credentials come from?
**A.** Managed identity: `azurerm_role_assignment` with `Azure Service Bus Data Sender`/`Receiver` scoped to the namespace/queue/topic, and RBAC-authenticated connections (`namespace_authorization_rule` only for legacy). No connection strings with `RootManageSharedAccessKey` — that key is full-namespace access and is the classic over-grant.
9. **Q:** How do you set up Log Analytics retention and cost control?
**A.** `retention_in_days` (30–730 interactive) plus `azurerm_log_analytics_workspace_table` for per-table retention/plan (Analytics vs Basic vs Auxiliary), data export/`azurerm_log_analytics_data_export_rule` for long-term retention in Storage, and commitment tiers where volume justifies it. Terraform manages the configuration; the discipline is per-table plans and alerts on ingestion spikes.
10. **Q:** What's the Azure Blueprints/APIOps angle in Terraform terms?
**A.** Blueprints themselves are legacy (deployment stacks/Policy at scale are the successors), but the concept maps to Terraform: management-group policy assignments + platform modules as the "blueprint" equivalent, published as versioned modules with Policy assignments for compliance, and an evidence trail from plans and Policy compliance. If asked about Blueprints, describe the modern equivalent rather than the retired feature.
11. **Q:** How do you alert on policy compliance and configuration drift?
**A.** `azurerm_monitor_scheduled_query_rules_alert_v2` over the Policy/Resource Graph tables (non-compliant resources), plus scheduled `terraform plan` jobs whose diffs raise alerts (via pipeline notification or a Function that posts to an action group). Compliance and drift both need detection, not hope.
12. **Q:** How do you do notifications for Terraform pipelines themselves?
**A.** Pipeline-level notifications (Azure DevOps/GitHub) plus an action group/webhook so failed applies, pending approvals, and drift plans reach the owning team; and (for critical roots) a scheduled plan that opens a work item rather than failing silently. The platform's own operations need monitoring — meta-monitoring is a senior talking point.

**🔍 Deep dive**
13. **Q:** Design the observability baseline every Azure workload inherits from your platform modules.
**A.** Every module creates: diagnostic settings to the central workspace (Resource logs + metrics) for the resources it builds; a metric alert set per resource type (App Gateway unhealthy backends/5xx/response time, SQL DTU/CPU/storage/deadlocks, Storage availability/latency/anonymous access, Service Bus DLQ/active messages, AKS node/pod health); a scheduled query alert for error-rate/business-KPI from App Insights; a default action group per environment/severity (page vs ticket); and a resource-health alert (`azurerm_monitor_activity_log_alert` on resource health/availability). Workload teams add domain alertson top, using the same action groups.
**↳ Follow-up:** "How do you avoid alert sprawl across 40 teams?"
**A.** Standard action groups and thresholds defined in the platform module (teams don't invent their own), an alert catalogue documented per service tier, a review of alert-to-incident ratios per team, and automatic cleanup: an inventory job that lists alerts with no action group, no recent activity, or owned by a deleted service. Treat alert hygiene as a measurable platform responsibility.
14. **Q:** How do you handle multi-environment monitoring without duplicate noise?
**A.** Separate action groups per environment (dev/ticket-only, prod/paging), environment in the alert's name/dimensions, and suppression for planned maintenance (maintenance windows in the ITSM/on-call tool, or alert processing rules). Then dashboards filtered by environment so the on-call sees one environment at a time. Noise in shared channels is how real alerts get missed.
15. **Q:** How do you implement SLO-style alerting in Terraform?
**A.** Define the SLI (availability = successful/valid requests, latency = p95 under threshold) from App Insights/Container Insights/App Gateway metrics, create scheduled query alerts on the *error budget burn rate* (fast/slow burn rules — e.g. page on 14.4× burn over 1h, ticket on 6× over 6h), and publish the SLO to the team dashboard. Terraform expresses all of it as alert rules + workbooks — which makes the SLO reviewable code rather than a spreadsheet.
16. **Q:** How do you build a Service Bus / Event Grid topology for reliability in Terraform?
**A.** Namespace per environment (premium for isolation/throughput where needed), queues/topics with `max_delivery_count` bounds, DLQ with `forward_dead_lettered_messages_to` for central handling, duplicate detection where useful, sessions for ordered processing, `partitioning_enabled` for throughput (with its ordering caveats), and RBAC-scoped identities for senders/receivers. Event Grid: system/custom topics with event subscriptions, retry policy (`event_ttl`, `max_delivery_attempts`), a dead-letter storage container, and managed identity for the destination. Alerts: DLQ depth, active message count, throttled requests, and subscription delivery failures.
17. **Q:** How do you do retries and idempotency guidance for Azure messaging?
**A.** At-least-once delivery is the norm: consumers must be idempotent (dedup keys stored transactionally with the side effect), retries must be bounded (`max_delivery_count` with DLQ after), and the app should use `ServiceBusProcessor`/`ServiceBusReceiver` with lock renewal and `Complete/Abandon` semantics. Terraform sets the bounds (`max_delivery_count`, lock duration, `forward_dead_lettered_messages_to`), and the design must state that duplicates are expected.
18. **Q:** How do you monitor the platform's own governance layer?
**A.** Activity Log alerts on policy assignment changes, role assignment changes, management-group changes, and resource-lock deletions; Policy compliance trends over time; Defender for Cloud secure score and recommendations exported to a dashboard with owners; and a scheduled review of exemptions/waivers with expiry dates. If nobody monitors the guardrails, they quietly stop working.
19. **Q:** How do you integrate Azure Monitor with an external on-call tool (PagerDuty/Opsgenie)?
**A.** Action groups with webhook receivers (common alert schema) pointing at the tool's Azure integration, a dedicated service per environment/severity, and alert processing rules for suppression. Then test the path end to end (a synthetic alert that must reach the on-call) — an untested notification path is the most common cause of "nobody knew" postmortems.
20. **Q:** How do you handle workspace architecture (one vs many)?
**A.** One central workspace per environment (or per region) for platform/workload logs, with per-team tables and RBAC (`Log Analytics Reader` scoped by resource/table, or workspace-level with data filtering), plus subscriptions where data residency demands separation. Many-workspace sprawl makes cross-service correlation impossible; one giant workspace needs access control discipline — choose and document.
21. **Q:** How do you do cost attribution for observability?
**A.** Estimate ingestion by resource (per-table plans, Basic logs for verbose low-value data, sampling in App Insights, retention tuning) and tag/exempt non-prod, plus budgets on the workspace and alerts on ingestion spikes. Also expose per-team ingestion so the cost conversation is evidence-based — visibility usually changes behaviour.

**🚨 War room**
22. **Q:** Nobody was paged during a 40-minute outage. What do you fix?
**A.** Find the missing or broken signal: no alert for the symptom, an alert with the wrong threshold/evaluation, an action group with a broken/disabled receiver, an unlinked action group, or a suppression still in effect. Fix it, then test the path with a synthetic alert. Add a pre-launch checklist requirement (each service must prove one successful page) so this class of gap can't ship again.
23. **Q:** The Service Bus DLQ is growing and consumers appear healthy.
**A.** Check the dead-letter reason (`DeadLetterReason`/description) via Service Bus Explorer/KQL: message expiry, max delivery count, filter evaluation exception, or a schema/processing error. Fix the root cause first, then replay deliberately (idempotent, throttled), and alert on DLQ depth so the next occurrence pages earlier than a customer complaint.
24. **Q:** Log ingestion costs tripled overnight.
**A.** Identify the table/resource driving it (workspace usage query by `Type`/`_ResourceId`): verbose logs switched on, a debug/loop error storm, Container Insights per-container metrics, or a noisy diagnostic setting added by a policy. Reduce at the source (log levels, sampling, per-table Basic plan), set a workspace budget alert, and add a review step for diagnostic-setting changes.
25. **Q:** Alerts fire for a resource that was intentionally deleted.
**A.** Clean up alerts with the resource (the module/root should delete them together — orphan alerts indicate the resource wasn't fully managed by Terraform), and add an inventory job/report listing alerts whose target no longer exists. Orphaned alerts are a symptom of partial IaC ownership.
26. **Q:** A scheduled query alert isn't firing despite errors being visible.
**A.** Common causes: the query's time range/frequency/`evaluation_frequency` mismatch (looking at a window shorter than the alert interval), the threshold type (`total` vs `count`) or aggregation, dimension splits (`alert_sensitivity`/`dimensions` grouping), a missing `severity`, the rule being disabled, or the log data landing in a different workspace/table than the query references. Test the KQL manually in the workspace first — most "alert doesn't fire" tickets end there.
27. **Q:** Message processing is stopped after a deploy, and there's no DLQ activity.
**A.** The consumer may be failing before completing (messages going back to active state with incremented delivery count — check `ActiveMessageCount` and `DeliveryCount`), the subscription/client identity may have lost RBAC (`Service Bus Data Receiver` removed by an apply), or the consumer's trigger may be disabled. Check identity + connection first (RBAC regressions from Terraform are common), then entity state, then app logs.
28. **Q:** A Policy assignment broke deployments across every team.
**A.** Policy is applied at ARM, so failures appear at apply time across subscriptions — the fastest fix is to set the assignment to `enforcement_mode = "DoNotEnforce"` (audit-only) or remove it, then remediate properly with a staged rollout (audit → targeted exemptions → enforce) and a communication plan. Postmortem action: high-impact Policy changes require staged rollout with test subscriptions and a documented rollback.
29. **Q:** Event Grid deliveries are failing and events are being lost.
**A.** Check the subscription's delivery response (`deliveryAttempts`, `lastDeliveryOutcome`), the destination identity/permission, whether the TTL (`event_ttl`) expired before delivery, whether a dead-letter container is configured (`storage_blob_dead_letter_destination` — key, since without it events are dropped), and the retry policy. Fix the destination, then replay what's recoverable and add DLQ + delivery-failure alerts.

**⚖️ Trade-off**
30. **Q:** Metric alerts vs scheduled query alerts for paging?
**A.** Metric alerts are cheaper, faster, and more reliable for thresholds; scheduled queries are flexible (complex conditions, joins, business logic) but cost more, have latency, and can silently fail if data is missing. Page on metrics (plus resource health); use queries for business KPIs and non-paging signals.
31. **Q:** One central Log Analytics workspace vs per-team workspaces?
**A.** Central: correlation across services, one retention/access model, cheaper at scale, but access control must be deliberate and ingestion becomes everyone's cost; per-team: isolation and autonomy at the cost of fragile cross-team queries and duplicated configuration. Central with scoped RBAC and per-team cost reporting is the usual enterprise answer.
32. **Q:** Diagnostics via per-resource resources vs Policy `deployIfNotExists`?
**A.** Per-resource (module-created) diagnostics give immediacy and clarity but only apply to resources Terraform creates; Policy `deployIfNotExists` guarantees coverage for everything (including out-of-band resources) but adds latency and remediation complexity (and can fight Terraform for ownership of the same setting). Mature setups do both: Policy as the backstop, modules for the intended path — and they avoid managing the same diagnostic setting in both places.
33. **Q:** Service Bus Premium vs Standard tier?
**A.** Premium gives dedicated resources, predictable latency, larger messages/entities, VNet/private endpoint support, and no throttling surprises; Standard is multi-tenant and cheaper with shared capacity. Production with strict latency/throughput or private networking requirements → Premium (and note Standard's entity/message limits).
34. **Q:** Event Grid vs Service Bus for events?
**A.** Event Grid: reactive, push-based notification of "something happened" with filtering/retries — not a queue (no competing consumers, TTL-bound); Service Bus: reliable command/message queues with sessions, transactions, and DLQs. Use Event Grid for notifications, Service Bus for work distribution.
35. **Q:** Basic vs Analytics log plans per table?
**A.** Basic (and Auxiliary) plans are much cheaper for high-volume, low-value logs (verbose/debug), but with restricted query capabilities and lower retention; Analytics is fully queryable and needed for alerting. Terraform sets per-table plans — a real cost lever most teams don't use, and a good answer to "how do you control log cost?"
36. **Q:** Alert on causes vs symptoms in an Azure estate?
**A.** Symptoms page: resource health, availability tests, 5xx rates, latency, DLQ depth, business KPIs; causes live on dashboards and drive autoscaling (CPU/memory, queue length). Cause-based paging produces noise and misses novel failures. This is the classic SRE question — answer it crisply.
37. **Q:** Managed Prometheus + Container Insights vs App Insights for AKS workloads?
**A.** Managed Prometheus for infrastructure/Kubernetes metrics (HPA/KEDA inputs, node/pod resource views) with Grafana; App Insights for application traces/dependencies/requests. They're complementary — and both should feed the same alerting and the same on-call rotations.
38. **Q:** Should Terraform own alert rules, or should teams create them in the portal?
**A.** Terraform for the standard baseline (guaranteed coverage, consistent thresholds/naming, reviewable), with teams free to add ad-hoc rules — but then inventory and reap the ad-hoc ones periodically. The failure mode of portal-created alerts is invisible gaps and drift; the failure mode of Terraform-only is slow iteration. Baseline in code, experimentation allowed, cleanup enforced.

**🎯 Senior**
39. **Q:** What does a production-grade observability + messaging baseline look like in Terraform on Azure?
**A.** A central Log Analytics workspace (per environment) with per-table retention/plans, data export for long-term retention, and scoped RBAC; diagnostics enabled per resource by modules with Policy `deployIfNotExists` as the backstop; a standard alert set per resource type (resource health/availability, error rate, latency, capacity/utilisation, DLQ/backlog, certificate/secret expiry, policy non-compliance, role-assignment changes); common action groups per environment/severity wired to the on-call tool with the common alert schema and a tested synthetic page; SLO burn-rate alerts for tier-1 services; Application Insights for app telemetry with sampling/retention tuned; dashboards/workbooks per service with deploy markers; Service Bus/Event Grid entities with RBAC-authenticated identities, bounded delivery counts, DLQs forwardable to a central handler, and delivery/DLQ alerts; and meta-monitoring of Terraform itself (pipeline failures, drift plans, policy changes).

**🎯 Senior signal:** "page on symptoms, dashboard on causes", per-table log plans/data export as the cost lever, and testing the notification path with a synthetic alert. Those three are the marks of an SRE who has carried a pager on Azure.
