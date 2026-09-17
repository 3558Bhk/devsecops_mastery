# Azure Functions — Interview Questions

> **Cloud:** Azure (Other Services) · **Category:** Compute (Serverless) · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~8 min

---

## JSON File Format

Azure Functions bindings are declared in **function.json** (per function) — the core JSON file format of Functions. `host.json` (runtime config) and `local.settings.json` (local dev) are also JSON.

```json
{
  "bindings": [
    { "name": "myBlob", "type": "blobTrigger", "direction": "in",  "path": "uploads/{name}", "connection": "AzureWebJobsStorage" },
    { "name": "outBlob", "type": "blob", "direction": "out", "path": "thumbs/{name}.png", "connection": "AzureWebJobsStorage" }
  ]
}
```

**Key fields:** `bindings[]` with `name`, `type` (httpTrigger, timerTrigger, queueTrigger, blobTrigger, serviceBusTrigger…) · `direction` (in/out) · `path` / `connection` / `queueName`. `host.json` holds `version`, `extensions`, and `logging` config.


## Case A — Basic

**A1. What is Azure Functions?**
**Answer:** A serverless compute service that runs event-driven code (functions) on demand — scaling automatically and billing only for execution, without managing servers.

**A2. What is a trigger and a binding?**
**Answer:** A **trigger** starts a function (HTTP request, timer, queue message, blob event). A **binding** is a declarative connection to input/output data (read/write a blob, queue, table) without writing plumbing code.

**A3. What are the main trigger types?**
**Answer:** **HTTP**, **Timer**, **Queue Storage / Service Bus**, **Blob/Event Grid**, **Cosmos DB change feed**, **Event Hubs**, and **Durable Functions** orchestrations.

**A4. What are the hosting plans?**
**Answer:** **Consumption** (pay-per-execution, auto-scale, cold starts), **Premium** (pre-warmed workers, VNet, longer timeouts), and **Dedicated (App Service)** (always-on, existing plan).

**A5. What is the pricing model?**
**Answer:** Based on **executions** (requests) + **GB-seconds** (memory × time) in Consumption; Premium adds always-ready cost; Dedicated uses the App Service plan.

**A6. What is a cold start?**
**Answer:** The latency when a function's worker initializes (runtime + dependencies) before executing — happens when no warm instance is available (Consumption plan scales to zero).

**A7. What is a function app?**
**Answer:** The container that hosts one or more functions — the unit of deployment, configuration, and scaling (all functions in an app scale together).

**A8. What is the maximum timeout?**
**Answer:** Consumption: **10 min** (default 5). Premium: **unlimited** (default 30 min). Dedicated: unlimited. Long work uses Durable Functions.

**A9. How does Azure Functions differ from App Service?**
**Answer:** Functions = event-driven, serverless, pay-per-execution, auto-scale to zero. App Service = always-on hosted apps, pay per plan. Functions for event tasks; App Service for continuous web apps.

**A10. What is a local.settings.json?**
**Answer:** Local development config (connection strings, app settings) — used by the Functions Core Tools locally; secrets go to app settings in Azure.

**A11. What are Durable Functions?**
**Answer:** An extension for **stateful workflows** in Functions — orchestrations, fan-out/fan-in, and long-running patterns with checkpoints/state, built on Durable Task Framework.

**A12. What is the Functions host and Core Tools?**
**Answer:** The **host** is the runtime that runs your functions. **Core Tools** (CLI, `func`) lets you develop/test locally and deploy.

**A13. What languages are supported?**
**Answer:** C#, JavaScript/TypeScript, Python, Java, PowerShell, and Go (custom handlers) — via in-process or isolated worker models.

**A14. What is the difference between a function app and an App Service plan (when Dedicated)?**
**Answer:** In the **Dedicated** plan, a function app runs on an **App Service plan** (always-on VMs); it's effectively App Service hosting the Functions runtime — vs Consumption/Premium serverless hosting.

**A15. How do you secure HTTP-triggered functions?**
**Answer:** Function-level, admin, and anonymous **authorization levels** (function keys), **App Service Authentication** (Entra ID), API Management in front, and HTTPS-only.

---

## Case B — Advanced (Senior)

**B1. Explain the scaling model: Consumption vs Premium (instances, scale-out, concurrency).**
**Answer:** Consumption scales out based on **event rate** (new instances added as queue/requests grow; scales to zero when idle). Premium keeps **pre-warmed instances** (always-ready) for zero cold starts and adds **VNet integration**, longer timeouts, and higher scale limits. Each instance handles concurrent invocations; scaling is per function app.

**B2. How do you handle cold starts (Premium, pre-warming, optimized dependencies)?**
**Answer:** Use the **Premium plan with always-ready instances**, reduce **package size/dependencies**, move heavy init to **module/global scope**, use **startup hooks** (isolated worker), avoid loading everything at startup, and warm HTTP endpoints with health pings. Measure cold-start via App Insights (init vs run time).

**B3. What are Durable Functions patterns (chaining, fan-out/fan-in, async HTTP, monitoring, human interaction)?**
**Answer:** **Function chaining** (sequential steps), **fan-out/fan-in** (parallel work then aggregate), **async HTTP APIs** (poll status endpoints), **monitoring** (poll until condition), and **human interaction** (wait for external event). Orchestrations are **deterministic** — replay-based, so orchestrator code must not do I/O directly (use activity functions).

**B4. What is the isolated worker model vs in-process, and why does it matter?**
**Answer:** **In-process** = functions run inside the host process (older, faster startup for some languages). **Isolated worker** = functions run in a separate process (recommended now) — better dependency isolation, .NET version flexibility, and required for newer .NET. Choose isolated for new projects.

**B5. How do bindings simplify code, and what are input vs output vs trigger bindings?**
**Answer:** Bindings are **declarative** — you specify "read this blob" (input) or "write this queue message" (output) in the function's config (attributes/decorators), and the runtime handles connections/serialization. **Trigger** = the event that starts it. This removes boilerplate SDK code and centralizes connection strings in app settings.

**B6. How does Functions integrate with VNet (Premium/Dedicated) and private endpoints?**
**Answer:** **Premium/Dedicated** plans support **regional VNet integration** (outbound to private resources) and **private endpoints** (inbound private access to HTTP functions). Consumption has no VNet integration (use API Management/private endpoints via the app, or move to Premium). This enables functions to reach private DBs/APIs.

**B7. How do you implement reliable queue processing (retries, poison messages, idempotency)?**
**Answer:** Queue triggers **retry up to 5 times** (configurable via `maxDequeueCount`), then move to a **poison queue** (`-poison`). Make functions **idempotent** (dedupe by message ID), use **visibility timeout**, and handle **partial failures** (Service Bus sessions/batching). Monitor poison queue depth.

**B8. How do you monitor Functions (App Insights, metrics, distributed tracing)?**
**Answer:** Functions auto-integrates with **Application Insights**: metrics (requests, exceptions, durations), **structured logs** (ILogger), and **distributed tracing** across triggers/bindings/durable steps. Alert on failures/durations/throttles; use **Live Metrics** and the **Functions monitor**. Correlation IDs flow through the orchestration.

**B9. What is the "functions scale controller" and how do triggers affect scale decisions?**
**Answer:** The scale controller watches **trigger metrics** (queue length, event rate) and adds/removes instances. HTTP scales by request rate; queue scales by message count; timer/blob have their own behavior. Understanding this explains why a backed-up queue spawns many instances (and why you may want `maxConcurrentCalls`/`batchSize` tuning).

**B10. What are the key limits to design around (timeouts, payloads, instances)?**
**Answer:** Consumption: 10-min timeout, 1.5 GB memory, 200 instances default (per app), request payload limits, and scale-out latency. Premium raises memory/instances/timeouts. For very long or heavy jobs, use **Durable Functions** or move to containers/AKS. Check current limits when designing.

**B11. How do you deploy Functions (CI/CD, slots, zero-downtime)?**
**Answer:** Deploy via **GitHub Actions/Azure DevOps** (zip/container deploy), use **deployment slots** (Premium/Dedicated) for staged rollouts, **run-from-package** for immutable, atomic deploys, and set app settings per slot. Version functions and use **Key Vault references** for secrets.

**B12. When do you choose Functions vs Logic Apps vs App Service vs AKS?**
**Answer:** Functions = custom code, event-driven, serverless (fine-grained control, any logic). Logic Apps = **low-code workflow/integration** (hundreds of connectors, no custom code). App Service = always-on web apps. AKS = full container orchestration. Often combined: Logic Apps orchestrate, Functions run custom code.

---

## Case C — Scenario

**C1. Scenario:** An image is uploaded to blob storage; thumbnails must be generated automatically.
**Question:** Design the serverless flow.
**Answer:** A **Blob trigger** function fires on upload, generates thumbnails (an activity), and writes them back to a thumbnails container. Use **bindings** for blob in/out (no SDK code), handle **poison blobs** and retries, and scale automatically with upload volume. Add App Insights for monitoring.

**C2. Scenario:** An order-processing workflow needs sequential steps (validate → charge → ship) with retries and state.
**Question:** Which feature and pattern?
**Answer:** **Durable Functions — function chaining**: an **orchestrator** calls activity functions in order (Validate → Charge → Ship), checkpointing after each so retries/failures resume from the last completed step. The orchestrator stays deterministic (no I/O); activities do the work. This gives reliable, stateful workflows serverlessly.

**C3. Scenario:** A function times out at 10 minutes on a long-running report job.
**Question:** Options to fix?
**Answer:** (1) Move to **Premium/Dedicated** plan (longer/unlimited timeout), (2) use **Durable Functions** to break the work into steps/parallel activities (each within limits), (3) **chunk** the job (process N rows per invocation, chain via queue), or (4) offload to a container/batch service for very heavy compute.

**C4. Scenario:** A queue-triggered function keeps failing on a specific message; it's retried and eventually poisons the queue.
**Question:** Diagnose and handle poison messages.
**Answer:** Inspect the **poison queue** (`<queue>-poison`) to see the failing payload; fix the bug (e.g., bad input handling); then **replay** the poison message back to the main queue. Make the function **idempotent** and validate input so one bad message doesn't block others. Set `maxDequeueCount` appropriately.

**C5. Scenario:** A function must reach a private SQL DB in a VNet and must not be exposed publicly.
**Question:** Which plan + networking?
**Answer:** Use the **Premium (or Dedicated) plan** with **VNet integration** for outbound to the private SQL; for the HTTP endpoint, use a **private endpoint** (or API Management in internal mode) so it's only reachable inside the VNet. Consumption doesn't support VNet — that's the key constraint.

**C6. Scenario:** A multi-step pipeline must fan out to 100 parallel tasks and aggregate results.
**Question:** Implement with Durable Functions.
**Answer:** **Fan-out/fan-in**: the orchestrator creates 100 **activity function** tasks (in parallel, possibly chunked), `await Task.WhenAll`, then aggregates results. Durable Functions checkpoints progress, so a mid-flight failure resumes without re-running completed activities — ideal for parallel, stateful processing.
