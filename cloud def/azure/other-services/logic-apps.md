# Azure Logic Apps — Interview Questions

> **Cloud:** Azure (Other Services) · **Category:** PaaS & Integration · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~7 min

---

## JSON File Format

A Logic Apps workflow is **entirely JSON** — the workflow definition (triggers + actions) is a JSON document (Consumption and Standard both use it).

```json
{
  "definition": {
    "$schema": "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#",
    "triggers": {
      "When_a_HTTP_request_is_received": {
        "type": "Request",
        "kind": "Http",
        "inputs": { "method": "POST", "schema": {} }
      }
    },
    "actions": {
      "Send_an_email": {
        "type": "ApiConnection",
        "inputs": {
          "host": { "connection": { "name": "@parameters('$connections')['office365']['connectionId']" } },
          "method": "post",
          "path": "/v2/Mail"
        }
      }
    },
    "outputs": {}
  },
  "parameters": { "$connections": { "type": "Object", "defaultValue": {} } }
}
```

**Key fields:** `definition` (the workflow) · `triggers` / `actions` with `type` (Request, Recurrence, ApiConnection…) · `inputs` · `parameters` (`$connections` maps to API connections). Control actions (Condition, For_each) are JSON nodes too.


## Case A — Basic

**A1. What is Azure Logic Apps?**
**Answer:** A **low-code/no-code** integration platform for building automated **workflows** that connect apps, services, and data — with hundreds of managed connectors and a visual designer.

**A2. What is a workflow?**
**Answer:** A sequence of steps (triggers + actions) that run automatically — defined in a JSON definition, visualized in the designer.

**A3. What is a trigger vs an action?**
**Answer:** A **trigger** starts the workflow (event/schedule/manual). **Actions** are the steps executed after (call APIs, transform data, send emails, etc.).

**A4. What are connectors?**
**Answer:** Wrappers around APIs that Logic Apps can call — **managed connectors** (200+ services: Office 365, Salesforce, SQL, Service Bus) and **custom connectors** (your APIs).

**A5. What are the common trigger types?**
**Answer:** **Recurrence** (schedule), **HTTP request** (webhook), **event triggers** (Service Bus, Event Grid, blob changes), and **manual** (button).

**A6. What is the difference between Logic Apps and Azure Functions?**
**Answer:** Logic Apps = **declarative, low-code workflows** with connectors (no custom code needed). Functions = **custom code**, event-driven serverless. They complement: Logic Apps orchestrate, Functions run custom logic.

**A7. What are the two Logic Apps resource types?**
**Answer:** **Consumption** (serverless, pay-per-run, multi-tenant) and **Standard** (single-tenant, runs on your own compute/AKS, better VNet/performance control).

**A8. What are control flow actions?**
**Answer:** **Conditions** (if/else), **switch**, **loops** (for-each, until), **scope** (grouping), and **parallel branches** — the workflow's logic.

**A9. What is a managed API connection?**
**Answer:** The authenticated connection to a connector's service (e.g., an Office 365 connection) — stored credentials used by the workflow.

**A10. How do you trigger a Logic App from an HTTP request?**
**Answer:** Use the **"When a HTTP request is received"** trigger, which generates a URL; POST to that URL to run the workflow (and use a **Response** action to reply).

**A11. What is the designer vs code view?**
**Answer:** The **designer** = visual canvas; **code view** = the underlying JSON workflow definition. You can edit either.

**A12. What is an expression in Logic Apps?**
**Answer:** Workflow Definition Language functions (`@concat(...)`, `@triggerBody()`, `@if(...)`) used to compute values dynamically in the designer.

**A13. What is a custom connector?**
**Answer:** A wrapper you create (from an OpenAPI/Postman collection) so Logic Apps can call **your own** HTTP API as a first-class connector.

**A14. What is the difference between Logic Apps and Power Automate?**
**Answer:** Power Automate = **end-user/personal** automation (Microsoft 365-centric, per-user licensing). Logic Apps = **enterprise/professional** integration (developer-grade, DevOps, VNet, governance). Similar engines, different audiences.

**A15. How do you monitor Logic Apps?**
**Answer:** **Run history** (status, duration, inputs/outputs), **trigger/action diagnostics**, Log Analytics + Application Insights, and **alerts** on failed runs.

---

## Case B — Advanced (Senior)

**B1. Explain the consumption model and pricing (per-action vs Standard plan).**
**Answer:** **Consumption**: pay **per executed action** (trigger + each action = a charge), scales automatically, multi-tenant. **Standard**: single-tenant, runs on a dedicated **App Service/AKS plan** (flat pricing) — better performance, VNet isolation, and higher throughput. Choose Standard for heavy/private workloads; Consumption for low-volume/cost-sensitive.

**B2. What is the retry and error-handling model (retry policies, scopes, run-after)?**
**Answer:** Each action has a **retry policy** (default 4 retries, exponential) and **run-after** (success/failure/skipped/timeout) to define conditional flow. Use **Scope** actions with try/catch/finally patterns and **terminate** actions for controlled exits. This makes workflows resilient to transient failures.

**B3. How does Standard (single-tenant) differ architecturally (Stateless vs Stateful workflows)?**
**Answer:** Standard Logic Apps support **Stateful** workflows (checkpointed, durable, resumable — the default) and **Stateless** workflows (faster, lower latency, but no checkpointing/retries persistence). Choose stateful for reliability/long workflows; stateless for low-latency high-throughput pipelines.

**B4. How do you integrate Logic Apps with VNet (ISEs vs Standard + VNet integration)?**
**Answer:** Legacy: **Integration Service Environment (ISE)** — dedicated, VNet-injected. Modern: **Standard Logic Apps** with **VNet integration** (outbound to private resources) and **private endpoints** (inbound). This lets workflows reach on-prem/private systems via private networking.

**B5. How do you handle large messages and batching (chunking, splitting, concurrency)?**
**Answer:** Enable **content chunking** for large files, **split-on** for arrays (process each item), control **for-each concurrency** (parallelism), and use **batched triggers** (collect N messages or wait T). This tunes throughput and avoids message-size limits.

**B6. How does Logic Apps integrate with Service Bus/Event Grid for event-driven architectures?**
**Answer:** Logic Apps can **trigger** on Service Bus queue/topic messages and **Event Grid** events (resource events, custom topics), enabling event-driven pipelines (e.g., blob created → Logic App processes). Combine with **dead-lettering** and **peek-lock** for reliable messaging.

**B7. How do you build reusable components (nested workflows, child Logic Apps, API connections)?**
**Answer:** Call a **child Logic App** (HTTP trigger) from a parent workflow for reuse; use **API connections** (shared authenticated connections) and **integration accounts** (B2B maps/schemas) for common artifacts. This reduces duplication and centralizes maintenance.

**B8. What is an Integration Account and when do you need it (B2B/EDI)?**
**Answer:** A container for **B2B/EDI artifacts**: schemas, maps (XSLT), partners, agreements, certificates — used with **Enterprise Integration Pack** for EDI/X12/AS2 workflows. Needed for formal B2B messaging scenarios.

**B9. How do you secure Logic Apps (managed identity, OAuth, key vault, IP restrictions)?**
**Answer:** Use **managed identities** to authenticate connectors (avoid shared secrets), **OAuth connections** for SaaS, **Key Vault** for secrets, **access restrictions** (IP allowlist) and **private endpoints** for inbound, and **RBAC** on the resource. Avoid storing credentials in workflow code.

**B10. How do you troubleshoot failed runs (run history, retries, diagnostics)?**
**Answer:** Open the **run history** → inspect the failed **action's inputs/outputs/error**, check **retry history**, enable **diagnostics → Log Analytics/App Insights**, and use **tracked properties** to surface custom values for querying. Fix the action/connector config and resubmit the run.

**B11. How does Logic Apps compare to Azure Data Factory / ADF for data pipelines?**
**Answer:** Logic Apps = **application/workflow integration** (events, APIs, approvals, SaaS) with low-code connectors. **ADF** = **data movement/ETL** at scale (copy activities, data flows, orchestration of datasets). Use Logic Apps for app-to-app automation; ADF for data engineering pipelines.

**B12. What are Logic Apps' limits to design around (timeouts, message size, concurrency)?**
**Answer:** Consumption: default run duration (up to 90 days for stateful? — actually longer), **request/message size limits** (~100 MB some actions, less for others), **concurrency** (per workflow), and **action limits per run**. Standard raises many limits. Design with chunking/splitting and durable patterns for big workloads.

---

## Case C — Scenario

**C1. Scenario:** When a file is dropped into SharePoint, it must be scanned, moved to blob storage, and notify a Teams channel.
**Question:** Design the workflow.
**Answer:** Logic App with a **SharePoint trigger** (file created) → **approval/scan action** (or call a Function) → **create blob** (Azure Blob connector) → **Teams post** notification → error handling (scope + email on failure). Use managed identities/OAuth for connectors and monitor run history.

**C2. Scenario:** A workflow calls an external API that intermittently fails; you need automatic retries and a fallback.
**Question:** Implement resilience.
**Answer:** Configure the HTTP action's **retry policy** (e.g., 5 retries, exponential backoff), then use **run-after** conditions: on success → continue; on failure → a **fallback action** (or Scope catch) that logs and notifies. This makes the workflow tolerant of transient outages.

**C3. Scenario:** A workflow processes an array of 1,000 orders, and you must control parallelism to avoid overwhelming the backend.
**Question:** How?
**Answer:** Use a **for-each** loop over the orders with **split-on** and set **concurrency control** (e.g., 20 parallel iterations) so the backend isn't flooded. Optionally add **batching** or a queue trigger with message batching for smooth throughput.

**C4. Scenario:** An approval workflow requires a human to approve an expense before payment.
**Question:** Which actions?
**Answer:** Use the **Approvals connector** (create approval → wait for approval → check outcome). On approval, proceed to the payment action; on rejection, notify and terminate. Approvals integrate with Teams/email for the human step — the classic "human-in-the-loop" pattern.

**C5. Scenario:** You must run a workflow inside your VNet to reach an on-prem SQL Server over ExpressRoute.
**Question:** Which resource type/config?
**Answer:** **Standard (single-tenant) Logic Apps** with **VNet integration** (outbound to the private/on-prem network) — the workflow can reach the on-prem SQL via the ExpressRoute/VNet path. (Legacy option: an ISE.) Use a private endpoint for inbound if needed.

**C6. Scenario:** A workflow fails silently; the business wants to know the moment any run fails and get the error details.
**Question:** Implement alerting.
**Answer:** Enable **diagnostic settings** → Log Analytics (or Application Insights); create an **alert** on failed runs (`RunsFailed` metric / log query); the alert's **action group** emails/Teams the team with a link to the failed **run** + error. Optionally add a **catch-all scope** that posts the error to Teams directly.
