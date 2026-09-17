# Azure App Service — Interview Questions

> **Cloud:** Azure · **Category:** PaaS & Integration · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~8 min

---

## JSON File Format

App Service apps are ARM JSON (`Microsoft.Web/sites`), with slots as `Microsoft.Web/sites/slots`.

```json
{
  "type": "Microsoft.Web/sites",
  "apiVersion": "2022-09-01",
  "name": "myapp",
  "kind": "app,linux",
  "properties": {
    "serverFarmId": "/subscriptions/<sub>/resourceGroups/rg/providers/Microsoft.Web/serverfarms/plan1",
    "httpsOnly": true,
    "siteConfig": {
      "linuxFxVersion": "DOCKER|myreg.azurecr.io/web:1.0",
      "minTlsVersion": "1.2",
      "appSettings": [{ "name": "KEY", "value": "val" }]
    }
  }
}
```

**Key fields:** `serverFarmId` (App Service Plan) · `httpsOnly` · `siteConfig` (`linuxFxVersion`/`windowsFxVersion`, `appSettings`, `minTlsVersion`) · `kind`. App settings can be **Key Vault references** (`@Microsoft.KeyVault(SecretUri=...)`), which are JSON-encoded values.


## Case A — Basic

**A1. What is Azure App Service?**
**Answer:** A fully managed **PaaS** for hosting web apps, REST APIs, and mobile backends — you deploy code and Azure handles the OS, patching, scaling, and infrastructure.

**A2. What types of apps can App Service host?**
**Answer:** **Web Apps** (ASP.NET, Node, Python, PHP, Java, Go, Ruby, static), **API Apps**, **Mobile Apps**, **WebJobs** (background tasks), and **containerized apps** (Linux/Windows containers).

**A3. What are the App Service plans (pricing tiers)?**
**Answer:** **Free/Shared** (dev), **Basic**, **Standard**, **Premium v2/v3** (more instances, features, VNet integration), and **Isolated** (dedicated App Service Environment). Each tier adds scale/features.

**A4. What is an App Service Plan?**
**Answer:** The underlying VM "farm" (region + size + instance count) that hosts your app(s) — multiple apps can share one plan (and its cost/compute).

**A5. How do you scale an App Service?**
**Answer:** **Scale up** (bigger VM size/SKU) and **scale out** (more instances — up to 30, or 100 in Premium/Isolated), with **autoscaling** based on metrics/schedules.

**A6. What are deployment slots?**
**Answer:** Separate live environments (e.g., `staging`, `prod`) on the same plan — enabling **slot swaps** (instant promotion) and testing before production.

**A7. What is a slot swap and why is it useful?**
**Answer:** Swapping the staging and production slots promotes the staged app **instantly** (warm, no downtime) — the standard zero-downtime deployment technique for App Service.

**A8. What are App Service deployment options?**
**Answer:** **Git-based** (GitHub Actions, Azure DevOps, local Git, Kudu), **FTP/FTPS**, **ZIP deploy**, **containers** (ACR), and **OneDeploy** — CI/CD pipelines are the norm.

**A9. What is Kudu?**
**Answer:** The deployment/management engine behind App Service (SCM site) — provides the console, file access, and deployment APIs (used by Git/Zip deploy).

**A10. What are App Service authentication features?**
**Answer:** **Easy Auth** (built-in authentication/authorization) using Entra ID, social providers, or OpenID — without app code.

**A11. What is VNet integration?**
**Answer:** Connecting an App Service to a **VNet** (outbound, or inbound via Private Endpoint) so it can reach private resources (DBs, APIs) securely.

**A12. What is a custom domain and TLS in App Service?**
**Answer:** Map your domain (CNAME/A) to the app and add an **SSL/TLS certificate** (free managed cert or Key Vault) for HTTPS.

**A13. What are WebJobs?**
**Answer:** Background tasks (triggered or continuous) that run in the App Service context — for jobs alongside a web app (or use Azure Functions for serverless).

**A14. What is the difference between App Service and Azure Functions?**
**Answer:** App Service = always-on hosted app (pay per plan). Functions = **serverless** event-driven compute (pay per execution, auto-scale to zero). Choose per workload model.

**A15. What is the Kudu/SCM URL and its use?**
**Answer:** `https://<app>.scm.azurewebsites.net` — the site-management endpoint for deployment, diagnostics, and the web console.

---

## Case B — Advanced (Senior)

**B1. How does App Service handle scaling (scale up vs out, autoscale rules, instance warm-up)?**
**Answer:** **Scale up** = change the plan SKU (more CPU/RAM). **Scale out** = add instances (up to plan max). **Autoscale** rules (metric or schedule-based) add/remove instances; set **warm-up** (or use slots) so new instances are ready before taking traffic. Combine manual baseline + autoscale for cost/performance.

**B2. What is ARR affinity (sticky sessions) and when do you enable it?**
**Answer:** **ARR affinity** pins a client to the same instance via a cookie — needed only for **stateful in-memory apps**. For stateless apps (the modern default), **disable it** so the load balancer can distribute freely across instances.

**B3. How does slot swap work under the hood (warm-up, settings, and the "swap with preview" option)?**
**Answer:** Slot swap exchanges the app's content/config between slots; **settings marked "slot setting"** (connection strings, app settings) **stay with the slot**. The swap **warms up** the target before cutting over. **Swap with preview** does a phased swap so you can verify before finalizing. Use for zero-downtime deploys.

**B4. What are the common causes of 5xx/timeouts on App Service, and how do you diagnose?**
**Answer:** Causes: **app crashes/restarts** (check diagnostics), **CPU/memory limits** (plan SKU), **HTTP request queue** full (scale out), **slow startup** (warm-up), **platform issues** (Service Health), or **gateway errors**. Diagnose via **App Service diagnostics**, **App Insights**, **Kudu logs**, and **Metrics** (HTTP 5xx, CPU, memory, queue length).

**B5. How does VNet integration work (regional vs gateway-required), and what about private endpoints for inbound?**
**Answer:** **Regional VNet integration** = outbound access to a VNet (via a delegated subnet) so the app reaches private resources. **Gateway-required** = older (VPN gateway). For **inbound** private access, use a **Private Endpoint** on the app (Premium+) so it's reachable only from the VNet. Combine both for fully private apps.

**B6. How do you secure an App Service (auth, TLS, networking, secrets)?**
**Answer:** **Easy Auth** (Entra ID), **HTTPS-only + TLS 1.2**, **custom domains + managed certs**, **private endpoint + VNet integration** (no public), **access restrictions** (allowlist/deny by IP/service tag), **managed identity + Key Vault** for secrets, and **Defender for App Service** for threat detection.

**B7. What is a deployment strategy with slots (blue-green, canary via Traffic Manager/Front Door)?**
**Answer:** Deploy to **staging slot**, run validation, then **swap** to production (blue-green). For percentage-based canaries, front multiple apps/slots with **Traffic Manager** or **Front Door** (or **App Service "Testing in production"** feature) to shift a % of traffic gradually, rolling back by shifting weights.

**B8. What is the App Service Environment (ASE) and when do you need it (Isolated plan)?**
**Answer:** **ASE** = a **dedicated, isolated** App Service environment in your VNet (single-tenant hardware, private networking, larger scale). Use for high security/isolation requirements, VNet-native apps, or very high scale. It's the **Isolated** tier — the most expensive/controlled option.

**B9. How does App Service handle containers vs code, and what are Linux vs Windows considerations?**
**Answer:** **Linux** plans run Linux containers/code; **Windows** runs .NET/IIS. Containers (ACR images) give dependency control and portability; code deploys are simpler. Note feature differences (e.g., some features Windows/Linux-specific), and that Linux plans are often cheaper and faster to scale.

**B10. What is App Service backup and restore, and what are its limitations?**
**Answer:** Built-in **backup** snapshots app files + config (+ optional DB) to a storage account on a schedule, with **restore** to the same or a new app. Limitations: Standard+ tiers, and it doesn't include some settings; for full DR use **replication/CI** + external DB backups. (Being supplemented by newer features.)

**B11. How do you troubleshoot performance issues with App Insights + App Service diagnostics?**
**Answer:** Use **Application Insights** (requests, dependencies, exceptions — find the slow path), **App Service metrics** (CPU %, memory, HttpQueueLength, response time), **Diagnose and solve problems** blade, **Kudu** for process/file inspection, and **scale-out/up** to relieve resource pressure. Correlate app-level and platform-level signals.

**B12. What are App Service limits you must design around (instances, timeout, request size)?**
**Answer:** Instance counts per SKU (e.g., 30 Standard, 100 Premium v3), **230-second request timeout** (default; some tiers allow longer via `WEBSITES_PORT`/async patterns), **request/response size limits**, deployment package size, and plan-level resource caps. Design async processing for long requests and plan instance counts for peak.

---

## Case C — Scenario

**C1. Scenario:** A web app must deploy to production with zero downtime, with instant rollback.
**Question:** Design the deployment.
**Answer:** Use **deployment slots**: deploy to `staging`, run smoke tests, then **swap** staging → production (instant, warmed). On failure, **swap back** for immediate rollback. Configure **slot-specific settings** (connection strings) so staging points at test dependencies. Automate in CI/CD.

**C2. Scenario:** An app needs to reach a private SQL database in a VNet, and must not be publicly reachable.
**Question:** Which networking features?
**Answer:** Use **VNet integration** (regional) for the app's **outbound** access to the private SQL, and a **Private Endpoint** (Premium) so the app is **only reachable from the VNet** (no public endpoint). Add **access restrictions** and disable public access on the SQL. This is the fully-private App Service pattern.

**C3. Scenario:** Users hit 503s during a traffic spike, but the app code is fine.
**Question:** Diagnose and fix.
**Answer:** The app hit **instance/queue limits** (HTTP queue full when instances are saturated). Fix: **scale out** (more instances) or **scale up** (bigger SKU), enable **autoscale** on CPU/requests for future spikes, and check for **ARR affinity/instance imbalance**. Monitor **HttpQueueLength** + CPU.

**C4. Scenario:** An app stores a DB password in `appsettings.json`, which got committed to the repo.
**Question:** Remediate.
**Answer:** Rotate the DB password immediately; move the secret to **Key Vault** and reference it via **App Service Key Vault references** (`@Microsoft.KeyVault(...)`) using the app's **managed identity** — no secrets in code/config. Add **secret scanning** to CI and enforce **no-secrets-in-repo** policy. Revoke/rotate the leaked credential.

**C5. Scenario:** A background job in the web app runs > 230 seconds and gets terminated.
**Question:** How do you handle long-running tasks?
**Answer:** App Service's request timeout is ~230s (longer for some triggers); move the work to an **async pattern**: the web app queues the job (Storage Queue/Service Bus) and a **WebJob / Azure Function / Durable Function** processes it, returning a job ID for polling. This decouples long work from HTTP requests.

**C6. Scenario:** A client needs PCI-DSS compliance and doesn't want to share the App Service infrastructure with other tenants.
**Question:** Which tier/solution?
**Answer:** **App Service Environment (ASE) — Isolated plan**: dedicated, single-tenant App Service in your VNet, giving the isolation, private networking, and controls PCI-DSS requires. (Alternatively, Premium v3 + private endpoints if strict single-tenancy isn't mandated, but ASE is the compliance-grade answer.)
