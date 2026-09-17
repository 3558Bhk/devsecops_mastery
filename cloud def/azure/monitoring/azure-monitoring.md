# Azure Monitor — Interview Questions

> **Cloud:** Azure · **Category:** Monitoring · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~8 min

---

## JSON File Format

Azure Monitor config uses JSON **Data Collection Rules (DCR)** and **alert rules** (ARM `Microsoft.Insights/...`).

```json
{
  "type": "Microsoft.Insights/dataCollectionRules",
  "apiVersion": "2022-06-01",
  "name": "dcr-vm-logs",
  "properties": {
    "dataSources": {
      "performanceCounters": [{
        "name": "cpu",
        "counterSpecifiers": ["Processor(_Total) Percent Processor Time"],
        "samplingFrequencyInSeconds": 60
      }]
    },
    "destinations": {
      "logAnalytics": [{ "workspaceResourceId": "/subscriptions/<sub>/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/law", "name": "law" }]
    },
    "dataFlows": [{ "streams": ["Microsoft-Perf"], "destinations": ["law"] }]
  }
}
```

**Key fields:** `dataSources` (what to collect) · `destinations` (Log Analytics workspace) · `dataFlows` (stream → destination mapping) · `streams` (Microsoft-Perf, Microsoft-Syslog…). Alert rules are JSON too (`Microsoft.Insights/metricAlerts` or `scheduledQueryRules`).


## Case A — Basic

**A1. What is Azure Monitor?**
**Answer:** Azure's unified monitoring platform that collects, analyzes, and acts on **metrics, logs, and traces** from Azure resources, applications, and on-prem systems.

**A2. What are the core components of Azure Monitor?**
**Answer:** **Metrics** (numeric time-series), **Logs** (Log Analytics workspaces), **Application Insights** (app telemetry), **Alerts**, **Dashboards/Workbooks**, and **Action groups** (who gets notified).

**A3. What is a metric vs a log?**
**Answer:** **Metrics** = lightweight numeric values over time (CPU %, request count) — fast, near-real-time, alertable. **Logs** = rich, detailed records (events, traces) queried via KQL — for deep analysis.

**A4. What is the difference between platform metrics and application telemetry?**
**Answer:** **Platform metrics** come from Azure resources automatically (CPU, disk, network). **Application telemetry** (Application Insights) comes from **your app** (requests, dependencies, exceptions, custom events) via an SDK/agent.

**A5. What is an alert rule?**
**Answer:** A condition on a metric or log query that, when met, fires an **alert** and triggers an **action group** (email, SMS, webhook, ITSM, Automation runbook).

**A6. What is an action group?**
**Answer:** A reusable set of notification actions (email, SMS, push, voice) and automated actions (webhook, Logic App, Function, ITSM) triggered by alerts.

**A7. What is Application Insights?**
**Answer:** The **application performance monitoring (APM)** part of Azure Monitor — tracking requests, dependencies, exceptions, and performance of live apps (any language/cloud).

**A8. What is a Log Analytics workspace?**
**Answer:** The central store for **log data** in Azure Monitor — where logs from resources/agents land and are queried with **KQL**.

**A9. What is KQL?**
**Answer:** Kusto Query Language — the query language for Log Analytics/Application Insights (and Defender/Sentinel), used to analyze log data.

**A10. What is the Azure Monitor Agent (AMA)?**
**Answer:** The modern agent that collects **logs and metrics** from VMs (and on-prem) — replacing the older Log Analytics agent, with multi-homing and data collection rules.

**A11. What is a Data Collection Rule (DCR)?**
**Answer:** Defines **what data to collect** and **where to send it** for the Azure Monitor Agent — separating collection config from the agent.

**A12. What is a Workbook vs a Dashboard?**
**Answer:** **Workbooks** = interactive, data-rich reports (tables, charts, parameters). **Dashboards** = pinned visualizations (from metrics/queries) on a shared canvas.

**A13. What is diagnostic settings?**
**Answer:** The configuration that sends a resource's **platform logs/metrics** to destinations (Log Analytics, Storage, Event Hubs, partner tools).

**A14. What is the difference between Azure Monitor and Microsoft Sentinel?**
**Answer:** Azure Monitor = **operational/performance** monitoring. Sentinel = **SIEM/SOAR** (security analytics, threat detection, response) built on Log Analytics. Sentinel consumes and enriches Monitor data for security.

**A15. What is VM Insights / Container Insights?**
**Answer:** Curated monitoring experiences: **VM Insights** (guest OS perf + dependencies via AMA/Dependency agent) and **Container Insights** (AKS/container metrics + logs) — prebuilt workbooks/alerts.

---

## Case B — Advanced (Senior)

**B1. Explain the Azure Monitor data model: metrics vs logs, and the ingestion pipeline (data sources → workspaces → queries/alerts).**
**Answer:** Data flows from **sources** (resources, agents, apps, diagnostics) into **Log Analytics workspaces** (logs) and the **metrics database** (metrics). **DCRs** govern agent collection; **diagnostic settings** govern resource logs. You then build **alerts** (metric/log), **workbooks/dashboards**, and export via **Data Export**/Event Hubs. Understanding the pipeline helps troubleshoot missing data.

**B2. What is the Azure Monitor Agent and how does it differ from the legacy Log Analytics agent?**
**Answer:** AMA is the **unified agent** for VMs: collects perf metrics + logs, supports **DCRs**, **multi-homing**, and is the required agent for newer features (Sentinel, VM Insights). Legacy MMA/OMS agent is **deprecated** (retired Aug 2024). Migration = define DCRs + install AMA.

**B3. How do you design an alert strategy (metric vs log alerts, severity, noise reduction)?**
**Answer:** Use **metric alerts** for fast, cheap, near-real-time thresholds (CPU, availability); **log alerts** for complex/aggregate conditions (e.g., ">5 errors in 15 min across resources"). Set **severities** (Sev0–4) mapping to on-call routing, use **dynamic thresholds** to reduce noise, **suppression windows**, and **action groups** with ITSM integration. Test with synthetic traffic.

**B4. What are dynamic thresholds and when are they better than static thresholds?**
**Answer:** **Dynamic thresholds** use ML on a metric's history to define a normal band and alert on deviations — ideal for metrics with variable baselines (traffic, latency) where static thresholds cause false alarms. Use static for known hard limits (e.g., disk > 90%).

**B5. How does Application Insights work (sampling, correlation, distributed tracing)?**
**Answer:** The SDK/auto-instrumentation captures **requests, dependencies, exceptions, traces**, and assigns **operation IDs** to correlate a request across services (distributed tracing). **Sampling** reduces telemetry volume (adaptive sampling keeps the most interesting data). Data lands in the workspace, queryable with KQL and visualized in the **application map**.

**B6. How do you monitor a hybrid environment (Azure + on-prem) with Azure Monitor?**
**Answer:** Install the **Azure Monitor Agent** on on-prem servers (via Arc-enabled servers for central management), define **DCRs**, and send logs/metrics to a workspace. Use **Arc** to extend Azure Monitor, Policy, and update management to on-prem — one monitoring plane for hybrid.

**B7. What is cost management for Azure Monitor (data ingestion, retention, per-GB)?**
**Answer:** Azure Monitor bills per **GB ingested**, **retention** (default 31 days free? — actually 30 days interactive), and extra for **data export**/long retention. Optimize: **filter logs** (DCR transforms — drop noisy sources), **sampling** (App Insights), set **daily caps**, use **basic vs analytics logs**, and archive to **Storage** for cheap long-term. Alert on ingestion cost anomalies.

**B8. How do you build multi-subscription/multi-tenant monitoring at enterprise scale?**
**Answer:** Use **Azure Lighthouse** to manage across tenants and **centralize** in a few Log Analytics workspaces (per environment/region) with **workspace-based data collection rules**, **Azure Policy** to auto-enable diagnostics + deploy AMA, and **workbooks/dashboards** aggregating across subscriptions. Standardize naming/tags for queryable alerts.

**B9. What are KQL patterns for troubleshooting (joins, aggregations, time-series)?**
**Answer:** Common patterns: `summarize count() by bin(TimeGenerated, 1h)`, `where` filters, `join` across tables (e.g., alerts + metrics), `extend` computed columns, `parse` for strings, and `percentiles()` for latency. Mastery of these lets you answer "what happened and when" from logs quickly.

**B10. How does Azure Monitor integrate with automation (alerts → remediation)?**
**Answer:** Alerts trigger **action groups** that can call **Azure Automation runbooks**, **Logic Apps**, **Functions**, or **webhooks** (e.g., auto-scale, restart a service, open a ticket). Combined with **Autoscale**, this creates self-healing loops (e.g., CPU alert → scale out; disk alert → runbook to extend disk).

**B11. What is the difference between Azure Monitor metrics and Azure Service Health / Resource Health?**
**Answer:** **Resource Health** = current/past **health status** of a resource (available/degraded). **Service Health** = Azure platform incidents/maintenance affecting you. **Monitor metrics/logs** = your **performance/telemetry**. Together: Service Health tells you if Azure is broken; metrics tell you if *your app* is.

**B12. How do you do end-to-end SLO/availability monitoring (Availability Tests, synthetic transactions)?**
**Answer:** **Application Insights Availability Tests** (URL ping, multi-step, or custom TrackAvailability) run from global locations on a schedule, measuring uptime/latency. Combine with metric alerts for availability %, and correlate with dependencies/requests to compute SLOs. Use **multi-step web tests** for critical user journeys.

---

## Case C — Scenario

**C1. Scenario:** Prod went down at 2 AM; the team got no alert and spent an hour diagnosing.
**Question:** What monitoring should have been in place, and how do you build it?
**Answer:** Build a layered stack: **platform metrics** (CPU/mem/disk) via AMA + **metric alerts** (with dynamic thresholds), **Application Insights** for app health + **availability tests** for user-facing checks, **log alerts** for error patterns, **action groups** → on-call (PagerDuty), and **dashboards/workbooks** for fast triage. Post-incident: add a specific alert for the root cause.

**C2. Scenario:** A VM's disk is 95% full and growing; you want an alert and an automatic fix.
**Question:** Implement.
**Answer:** Metric alert on **disk space %** (AMA perf counter, e.g., `% Used Space > 90` for 15 min) → **action group** that (a) notifies on-call and (b) triggers an **Automation runbook** to **extend the disk** (or clean logs). This creates an alert + self-healing loop, with the runbook's success/failure logged.

**C3. Scenario:** Users report slow responses, but CPU/memory look normal on the app VM.
**Question:** What do you monitor instead, and with which tool?
**Answer:** Enable **Application Insights** (or OpenTelemetry) to see **request latency**, **dependency calls** (which service/DB is slow), **exceptions**, and **traces** — the app-level view that VM metrics miss. Use the **application map** and KQL (`requests | summarize percentile(duration,95)`) to find the slow dependency, and correlate with the backend's metrics.

**C4. Scenario:** You must centralize logs from 200 VMs across 3 subscriptions into one place with a 90-day retention, plus archive for 2 years.
**Question:** Design it.
**Answer:** Deploy **AMA** on all VMs (via Azure Policy), use **DCRs** to send logs to a **central Log Analytics workspace** (per environment), set **interactive retention 90 days**, and enable **Data Export / archive to Storage** (or **total retention** settings) for the 2-year cold archive (cheap, queryable via search jobs). Standardize tables and set cost caps.

**C5. Scenario:** An alert fires every night at 3 AM for CPU on a batch VM, but it's expected behavior.
**Question:** How do you stop the noise without hiding real issues?
**Answer:** Use **alert processing rules** (suppress during the 3 AM window for that resource) or **dynamic thresholds** (learns the nightly spike as normal), or adjust the alert condition (e.g., sustained CPU > 90% for 30 min, not a 5-min spike). Route suppressed alerts to a log instead of paging. This reduces alert fatigue while keeping real alerts.

**C6. Scenario:** A customer-facing API must maintain 99.9% availability; you need to measure and alert on it.
**Question:** Implement SLO monitoring.
**Answer:** Set up **Application Insights availability tests** (multi-step) hitting the critical endpoints from multiple regions; compute availability % and latency; create a **metric alert** on availability < 99.9% (over a rolling window) and latency p95 thresholds; route to on-call. Correlate failures with requests/dependencies to find root causes, and track error budgets on a dashboard.
