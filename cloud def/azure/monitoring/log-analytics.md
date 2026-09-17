# Azure Log Analytics — Interview Questions

> **Cloud:** Azure · **Category:** Monitoring · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~8 min

---

## JSON File Format

Log Analytics **saved searches** (and the query API) are JSON; the workspace itself is ARM JSON (`Microsoft.OperationalInsights/workspaces`). Queries are KQL strings stored in JSON.

```json
{
  "type": "Microsoft.OperationalInsights/workspaces/savedSearches",
  "apiVersion": "2020-08-01",
  "name": "law/errors-last-hour",
  "properties": {
    "category": "Ops",
    "displayName": "Errors in the last hour",
    "query": "Event | where TimeGenerated > ago(1h) | where EventLevelName == 'Error' | summarize count() by Source"
  }
}
```

**Key fields:** `query` (the KQL string) · `category` / `displayName`. The **query API response** is also JSON (`tables[].rows`). Workspace JSON carries `retentionInDays`, `sku`, and `publicNetworkAccessForIngestion`.


## Case A — Basic

**A1. What is Log Analytics?**
**Answer:** The log-query and storage engine of Azure Monitor — a **workspace** that ingests logs from Azure resources, agents, and apps, and lets you query them with **KQL**.

**A2. What is a Log Analytics workspace?**
**Answer:** A logical container for log data — the unit of ingestion, retention, access control, and cost in Azure Monitor. One or more workspaces per environment/region.

**A3. What is KQL and why is it important?**
**Answer:** Kusto Query Language — used to query Log Analytics, Application Insights, Sentinel, and Defender. It's the core skill for investigating logs in Azure.

**A4. What are the main KQL operators?**
**Answer:** `where` (filter), `summarize` (aggregate), `project`/`extend` (select/compute columns), `join`, `union`, `sort`/`order`, `parse`, `bin` (time buckets), and `render` (visualize).

**A5. What is a table in Log Analytics?**
**Answer:** Each data type lands in a **table** (e.g., `Perf`, `Heartbeat`, `Event`, `Syslog`, `AzureActivity`) — KQL queries target these tables.

**A6. What are the common tables you use?**
**Answer:** **Perf** (performance counters), **Heartbeat** (agent status), **Event/Syslog** (OS logs), **AzureActivity** (management-plane ops), **AzureDiagnostics**/resource-specific tables, and App Insights tables (**requests**, **exceptions**, **dependencies**).

**A7. How do you write a basic query (e.g., errors in the last hour)?**
**Answer:** `Event | where TimeGenerated > ago(1h) | where EventLevelName == "Error" | summarize count() by Source` — filter by time, filter by level, aggregate by source.

**A8. What is a log query alert?**
**Answer:** An alert rule that runs a KQL query on a schedule; if results meet a threshold (e.g., > N rows), it fires and triggers action groups.

**A9. What is the difference between basic and analytics logs?**
**Answer:** **Analytics logs** = full interactive querying (higher cost). **Basic logs** = cheaper tier for high-volume, low-query data (limited KQL operators). Choose per data type to control cost.

**A10. What is data retention in Log Analytics?**
**Answer:** How long data stays interactive-queryable (default 30 days, configurable up to 2 years interactive); **total retention** can extend longer with archive/search jobs.

**A11. How does data get into Log Analytics?**
**Answer:** Via **agents** (AMA), **diagnostic settings** (resource logs), **Application Insights**, **Sentinel/Defender**, and direct **Data Collector API** — governed by **DCRs** for agent data.

**A12. What is a workspace's access control model?**
**Answer:** **RBAC** on the workspace (readers/contributors) + **resource-context vs workspace-context** access — users see data for resources they can access (or the whole workspace if granted).

**A13. What is the difference between Log Analytics and Application Insights?**
**Answer:** Both use KQL + the same platform. **Log Analytics** = infrastructure/resource logs. **Application Insights** = application telemetry (requests, exceptions, dependencies). They often share a workspace.

**A14. How do you search for a specific string across logs?**
**Answer:** Use `where * contains "string"` (or `search "string"`), scoped to time/tables — e.g., `search in (Event, Syslog) "error" | where TimeGenerated > ago(1h)`.

**A15. What is the ingestion latency?**
**Answer:** Logs typically appear within a few minutes (often < 1 min for many sources); there's a short delay between data generation and query availability.

---

## Case B — Advanced (Senior)

**B1. Explain workspace design: one workspace vs many (per team/app/region), and the tradeoffs.**
**Answer:** **One/few central workspaces** = lower cost (no duplication), simpler cross-resource queries, but needs careful RBAC. **Per-team/app** = isolation, clear ownership, but harder cross-querying and higher management. Best practice: few workspaces (e.g., per environment/region or per security boundary), with RBAC and resource-context controls for isolation.

**B2. How does resource-context vs workspace-context access work, and how do you design least-privilege log access?**
**Answer:** **Resource-context**: users query logs for resources they have RBAC read access to (scoped automatically). **Workspace-context**: users query the whole workspace (needs workspace Reader). Design: grant resource RBAC for team-level access; reserve workspace-level for central ops/security. Use **custom roles** to allow querying without seeing all tables.

**B3. How do you control ingestion cost (DCR transforms, filtering, sampling, caps)?**
**Answer:** Use **DCR transformations** to **filter out noisy sources** (e.g., drop debug logs) before ingestion, **sample** high-volume telemetry, route low-value data to **basic logs**, set **daily caps** to bound cost, and review per-table ingestion via **Usage and estimated costs**. These reduce GB-ingested (the main cost driver).

**B4. What are DCR transformations and how do they work (KQL at ingestion)?**
**Answer:** A **Data Collection Rule** can include a **transform** — a KQL query that runs **at ingestion time** to filter/rename/modify data before it's stored (e.g., `where LogLevel != "Debug"`). This drops unwanted data (saving cost) and normalizes schemas — a powerful cost/governance tool.

**B5. How do you write efficient KQL (avoid full scans, use time filters, summarize properly)?**
**Answer:** Always filter **TimeGenerated** first, restrict tables/columns (`project` early), use `summarize` with `bin()` for aggregations, prefer `has`/`contains` over wildcards, and avoid `search *` on huge tables. Efficient queries = faster results + lower query cost.

**B6. What is the difference between workspace retention, archive, and Data Export (long-term storage)?**
**Answer:** **Retention** = interactive query window (up to 2 years). **Archive** = cheaper long-term store (up to 12 years) queryable via **search jobs/restore**. **Data Export** = stream to **Storage/Event Hubs** for external long-term storage/analytics. Choose archive for compliance queryability; export for external tools.

**B7. How does Log Analytics integrate with Microsoft Sentinel (workspace as the SIEM data lake)?**
**Answer:** Sentinel **requires** a Log Analytics workspace as its data store; connectors ingest security logs, **analytics rules** (KQL) detect threats, and **incidents** are created. The same KQL/workspace skills apply — Sentinel adds the SIEM/SOAR layer (detections, playbooks) on top.

**B8. How do you build a log query alert with aggregation and thresholds (avoiding per-event noise)?**
**Answer:** e.g., alert when error count > 10 in 15 min: `Event | where TimeGenerated > ago(15m) | where EventLevelName == "Error" | summarize Count = count() by Computer | where Count > 10`, with the alert evaluating every 5–15 min. Aggregating (rather than alerting per event) is the key to low-noise alerting.

**B9. What are the key KQL functions for time-series and statistical analysis?**
**Answer:** `bin()` for bucketing, `percentile()`/`percentiles()` for latency, `series_decompose_anomalies()` for anomaly detection, `arg_max()`/`top`, `dcount()` for distinct counts, `summarize make-series` for time charts, and `render timechart` for visualization. These power both troubleshooting and alerting.

**B10. How do you monitor the health of the workspace itself (ingestion volume, latency, failures)?**
**Answer:** Check **Usage and estimated costs** (per-table GB), the **Operation** table (ingestion/query activity), **Ingestion latency** metrics, and **heartbeat** gaps (agents offline). Alert on ingestion anomalies (drop = agents broken) and on cost crossing budgets.

**B11. What are workspace-based Application Insights resources, and why consolidate?**
**Answer:** Workspace-based App Insights stores telemetry **in a Log Analytics workspace** (instead of its own store) — enabling **cross-resource queries** (app + infra in one KQL), unified retention/cost, and Sentinel integration. The recommended configuration for new resources.

**B12. How do you query across multiple workspaces and subscriptions?**
**Answer:** Use **cross-workspace queries** (`workspace("name").Table` or `union workspace(...)`) and **Azure Resource Graph** for inventory; for enterprise scale, use **Azure Lighthouse** to manage/query tenants, or **Log Analytics workspace insights** for monitoring workspaces themselves.

---

## Case C — Scenario

**C1. Scenario:** You need to find all failed sign-ins for a specific user in the last 24 hours across Azure AD.
**Question:** Write the query and explain.
**Answer:** `SigninLogs | where TimeGenerated > ago(24h) | where UserPrincipalName == "user@corp.com" | where ResultType != 0 | project TimeGenerated, AppDisplayName, IPAddress, Location, ResultDescription` — filter by time, user, and non-success result, then project the useful fields.

**C2. Scenario:** Log ingestion costs doubled after a new app started shipping DEBUG logs.
**Question:** How do you find the culprit and cut cost?
**Answer:** Query the **Usage and estimated costs** view (or `Usage` table) to find the top-ingesting tables/sources, identify the DEBUG-heavy source, then apply a **DCR transformation** to **drop DEBUG logs at ingestion**, or reduce sampling/verbosity in the app, and move low-value data to **basic logs**. Set a **daily cap** as a guardrail.

**C3. Scenario:** An on-call engineer needs to correlate "5xx errors increased" with "which dependency is failing" for an App Insights-enabled API.
**Question:** Which KQL approach?
**Answer:** Query `requests | where resultCode startswith "5" | summarize count() by bin(TimeGenerated,5m)` to see the error spike, then `dependencies | where success == false | summarize count() by target, type` to find failing dependencies, and **join** on operation IDs to correlate failing requests with the dependency calls that caused them.

**C4. Scenario:** VMs stop reporting heartbeats overnight; you discover it only when a user complains.
**Question:** How do you detect this proactively?
**Answer:** Create a **log query alert** on the `Heartbeat` table: `Heartbeat | summarize LastBeat = max(TimeGenerated) by Computer | where LastBeat < ago(15m)` — alerting when any agent misses beats for 15 min. Route via action group to on-call. This catches agent/VM outages before users do.

**C5. Scenario:** A security team needs 7 years of certain logs, queried occasionally, without paying interactive-retention prices.
**Question:** Design the retention strategy.
**Answer:** Set the workspace's **interactive retention** short (e.g., 30–90 days) and enable **archive** (or **total retention**) to keep data up to 7 years; query old data via **search jobs/restore** (restore a time range temporarily). Alternatively **Data Export** to cheap **Storage** for the full 7 years. This balances cost vs compliance.

**C6. Scenario:** Two teams share one workspace; team A must not see team B's data.
**Question:** How do you isolate access?
**Answer:** Use **resource-context RBAC**: grant each team read access only to **their resources** (not workspace-level Reader), so queries are scoped to their resources' logs. For true table-level separation, use **separate workspaces** per team. Reserve workspace-level access for central ops. Use custom roles for granular control.
