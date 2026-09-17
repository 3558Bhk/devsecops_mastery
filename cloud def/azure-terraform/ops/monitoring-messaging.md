# Terraform Monitoring & Messaging (Azure) — Interview Questions

> **Cloud:** Azure · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~5 min

---

## Case A — Basic

**A1. What is Azure Monitor in Terraform?**
**Answer:** Azure's observability platform, managed via resources like `azurerm_log_analytics_workspace`, `azurerm_application_insights`, `azurerm_monitor_metric_alert`, and `azurerm_monitor_action_group`.

**A2. What is a Log Analytics workspace?**
**Answer:** `azurerm_log_analytics_workspace` — a store for logs/metrics from Azure and custom sources, with a retention period.

**A3. What is Application Insights?**
**Answer:** `azurerm_application_insights` — app performance monitoring (requests, exceptions, traces), linked to a Log Analytics workspace.

**A4. What is a metric alert?**
**Answer:** `azurerm_monitor_metric_alert` — alerts on a metric threshold (CPU, memory, requests) with a frequency and action group.

**A5. What is an action group?**
**Answer:** `azurerm_monitor_action_group` — the set of actions (email, SMS, webhook, ITSM, function) triggered when an alert fires.

**A6. What is a diagnostic setting?**
**Answer:** `azurerm_monitor_diagnostic_setting` — routes resource logs/metrics to a workspace, storage account, or Event Hub.

**A7. What is Service Bus in Terraform?**
**Answer:** `azurerm_servicebus_namespace` (the messaging namespace) + queues (`azurerm_servicebus_queue`) and topics/subscriptions.

**A8. What is the difference between a Service Bus queue and topic?**
**Answer:** A queue is point-to-point (one consumer); a topic uses subscriptions for publish/subscribe (many consumers), with filters on subscriptions.

**A9. What is an Event Hub?**
**Answer:** `azurerm_eventhub_namespace` + `azurerm_eventhub` — a high-throughput event streaming/ingestion service.

**A10. What is Event Grid in Terraform?**
**Answer:** `azurerm_eventgrid_*` (topics, subscriptions, system topics) — a push-based event router for reacting to Azure/application events.

**A11. What is a Service Bus queue's `max_delivery_count`?**
**Answer:** The number of delivery attempts before a message moves to the dead-letter queue.

**A12. What is a dead-letter queue?**
**Answer:** Where undeliverable/expired messages go for later inspection — built into Service Bus queues/subscriptions.

**A13. What is `azurerm_monitor_action_rule` vs action group?**
**Answer:** Action rules (alert processing rules) suppress/route alerts at scale (e.g. silence maintenance windows); action groups define the destinations.

**A14. How do you set log retention in a workspace?**
**Answer:** `retention_in_days` on `azurerm_log_analytics_workspace` (and per-table via `azurerm_log_analytics_workspace_table`).

**A15. What is a shared access policy for Event Hub/Service Bus?**
**Answer:** `azurerm_servicebus_namespace_authorization_rule`/`azurerm_eventhub_authorization_rule` — keys granting send/listen/manage access to clients.

## Case B — Advanced / Senior

**B1. How do you build a standard observability stack for any app with Terraform?**
**Answer:** A module emitting: Log Analytics workspace, Application Insights (connected), diagnostic settings on compute/network resources, metric + log alerts (5xx, CPU, availability), and an action group — instantiated per service for consistency.

**B2. What is the difference between metric alerts, log alerts, and activity log alerts?**
**Answer:** Metric alerts fire on numeric metrics (fast, near-real-time); log alerts query Log Analytics (richer conditions, scheduled); activity log alerts react to control-plane events (e.g. resource deletion).

**B3. How do you alert on custom application metrics from Application Insights?**
**Answer:** Query-based log alerts (or metric alerts on custom metrics) referencing the App Insights `customEvents`/`customMetrics`, e.g. alert when error rate exceeds X%.

**B4. Service Bus queues vs topics vs Event Hubs vs Event Grid — how do you choose?**
**Answer:** Queue: one-to-one async workload. Topic/subscription: one-to-many with filtering. Event Hub: massive-scale streaming/telemetry ingestion. Event Grid: push event routing (reactive, serverless). Match on fan-out, throughput, and ordering needs.

**B5. How do you configure Service Bus sessions and ordering?**
**Answer:** Enable `requires_session = true` on queues/subscriptions so related messages are grouped/ordered per session — for FIFO per-session processing.

**B6. How do you implement retries and dead-lettering properly?**
**Answer:** Set `max_delivery_count`, enable dead-lettering on expiry/filter failure, configure `lock_duration` long enough for processing, and have consumers complete/abandon explicitly.

**B7. How do you integrate Event Hub with Terraform for streaming into a data lake?**
**Answer:** Event Hub namespace/hub + `azurerm_eventhub_consumer_group` per consumer + diagnostic settings, then a downstream (Azure Stream Analytics/Data Explorer/Function) that Terraform also provisions.

**B8. How do you route resource logs to multiple destinations?**
**Answer:** `azurerm_monitor_diagnostic_setting` can send to a workspace, storage account, and Event Hub simultaneously — configure all three for compliance (query + archive + stream).

**B9. What is Azure Monitor Agent (AMA) vs the legacy agents?**
**Answer:** AMA (`azurerm_monitor_data_collection_rule` + association) is the modern agent with data collection rules; the legacy Log Analytics/Diagnostics agents are being phased out. Use AMA for new deployments.

**B10. How do you suppress alerts during maintenance windows?**
**Answer:** `azurerm_monitor_action_rule_suppression` (or alert processing rules) with a schedule, so planned maintenance doesn't page — paired with the action group.

**B11. How do you structure messaging namespaces for multi-tenant apps?**
**Answer:** Separate namespaces per environment/tenant with their own authorization rules and managed identities; use private endpoints for secure access and monitor queue depth via alerts.

**B12. How do you secure Service Bus/Event Hub with managed identity?**
**Answer:** Grant the app's managed identity the `Azure Service Bus Data Sender/Receiver` or `Azure Event Hubs Data Sender/Receiver` roles (RBAC) instead of shared access keys, and disable local/key auth where possible.

## Case C — Scenario

**C1. Nobody was paged when a critical service's error rate spiked.**
**Answer:** The alert or action group was missing/misconfigured. Add the metric/log alert on error rate with the right action group, and test by triggering it manually. Add availability tests (`azurerm_application_insights_standard_web_test`).

**C2. Messages pile up in a Service Bus queue and the DLQ is filling.**
**Answer:** Check consumer health/logs, the processing time vs `lock_duration`, and `max_delivery_count`. Fix the handler, then replay/route DLQ messages back to the main queue after resolving the cause.

**C3. You need to stream 100k events/sec into storage for analytics.**
**Answer:** Event Hub (with multiple partitions + consumer groups) as the ingestion buffer, capturing to storage via `azurerm_eventhub` `capture_description` (or a Stream Analytics job) — autoscale the throughput units as needed.

**C4. An event-driven app needs to react to blob uploads across several storage accounts.**
**Answer:** Event Grid system topics (or one custom topic) with subscriptions routing `Microsoft.Storage.BlobCreated` events to the handler (Function/webhook), configured in Terraform with the handler's endpoint.

**C5. Alerts fire every night during a known batch job — noise is causing fatigue.**
**Answer:** Add an alert processing rule (suppression) for the batch window, or raise thresholds/`evaluation_frequency`, and tune the alert to the real anomaly (e.g. anomaly detection instead of a fixed threshold).

**C6. Logs must be retained 1 year for compliance but the workspace default is 30 days.**
**Answer:** Set `retention_in_days` (workspace and per-table) to 365 (or export to storage for longer/cheaper retention via diagnostic settings), and add a policy/check so new workspaces default correctly.
