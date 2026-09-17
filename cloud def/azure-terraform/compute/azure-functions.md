# Terraform Azure Functions — Interview Questions

> **Cloud:** Azure · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~5 min

---

## Case A — Basic

**A1. What is Azure Functions in Terraform?**
**Answer:** A serverless compute service; Terraform defines `azurerm_service_plan` + `azurerm_linux_function_app` (or `_windows_`) plus a storage account and Application Insights.

**A2. What resources does a Function App require?**
**Answer:** A storage account (for code/state), an App Service Plan (or consumption plan), the Function App, and optionally Application Insights for monitoring.

**A3. What is a consumption plan for Functions?**
**Answer:** A serverless plan (`sku_name = "Y1"`) where you pay per execution and scale automatically to zero.

**A4. What is a premium or dedicated plan for Functions?**
**Answer:** Premium (`EP1`…) offers warm instances, VNet integration, and longer runtimes; dedicated runs on a regular App Service Plan.

**A5. How do you declare a Linux Function App?**
**Answer:** `resource "azurerm_linux_function_app" "fn" { name = ... ; resource_group_name = ... ; service_plan_id = ... ; storage_account_name = ... ; storage_account_access_key = ... ; site_config { } }`.

**A6. What is `site_config` for a Function App?**
**Answer:** Runtime (`application_stack` like `python_version`/`node_version`), `always_on`, `use_32_bit_worker`, app scale limits, and health checks.

**A7. How do you set environment variables (app settings)?**
**Answer:** The `app_settings` block — including `AzureWebJobsStorage` for the storage connection and function-specific config.

**A8. What is `AzureWebJobsStorage`?**
**Answer:** The app setting pointing to the storage account the Functions runtime uses for triggers/state/queues.

**A9. How does a Function App get code?**
**Answer:** Via deployment (zip deploy, CI/CD, or `WEBSITE_RUN_FROM_PACKAGE`) — Terraform usually creates the infra; code deploys through the pipeline.

**A10. What triggers can a Function use?**
**Answer:** HTTP, timer, queue (Service Bus/Storage), Event Hub, Event Grid, and more — configured in the function code (`function.json`), not Terraform.

**A11. What is Application Insights for Functions?**
**Answer:** `azurerm_application_insights` + the `APPINSIGHTS_INSTRUMENTATIONKEY`/connection string setting, for logging/metrics.

**A12. How do you secure secrets in a Function App?**
**Answer:** Key Vault references in app settings with a managed identity, rather than plaintext settings.

**A13. What is a managed identity on a Function App?**
**Answer:** An `identity` block giving the function an Azure AD identity to access Azure services without credentials.

**A14. What is `https_only` on a Function App?**
**Answer:** Forces HTTPS for HTTP-triggered functions — set true in production.

**A15. What is `daily_memory_time_quota`?**
**Answer:** A daily memory/time quota (GB-seconds) that stops the function when exceeded — a cost guardrail.

## Case B — Advanced / Senior

**B1. Consumption vs premium vs dedicated — how do you choose?**
**Answer:** Consumption: cheapest, scale-to-zero, cold starts, 5–10 min max runtime. Premium: pre-warmed, VNet integration, longer runtimes, higher scale. Dedicated: predictable capacity on an App Service Plan. Match to latency/isolation/runtime needs.

**B2. How do you eliminate cold starts in production?**
**Answer:** Use a Premium plan (or dedicated) with `always_on` and pre-warmed instances; reduce package size and dependencies; avoid heavy init in the entrypoint.

**B3. How do you give a Function App access to a private resource (SQL, storage)?**
**Answer:** Regional VNet integration (delegated subnet) on the app, so it reaches private endpoints/internal resources without public exposure.

**B4. How do you wire a Function to a Service Bus/Event Hub trigger?**
**Answer:** Terraform creates the Service Bus/Event Hub + the Function App; the function's code declares the trigger and connection string setting (stored via Key Vault reference). The managed identity with the right role replaces connection strings where supported.

**B5. How do you deploy function code in a Terraform-managed pipeline?**
**Answer:** Two phases: Terraform apply (infra) then code deploy (zip/Func CLI/GitHub Action) — or use `WEBSITE_RUN_FROM_PACKAGE` pointing at a blob and update the blob on release. Don't manage code inside Terraform state.

**B6. What is `WEBSITE_RUN_FROM_PACKAGE` and how does it help?**
**Answer:** An app setting that runs the function from a zip package (URL or mounted), making deploys atomic and avoiding file-lock issues on the shared filesystem.

**B7. How do you configure Durable Functions infrastructure with Terraform?**
**Answer:** Just the standard Function App + storage account with the right `AzureWebJobsStorage`; Durable uses storage tables/queues automatically — no special Terraform resources beyond the storage.

**B8. What are function app scale limits and `function_app_scale_limit`?**
**Answer:** `function_app_scale_limit` caps the number of instances (cost protection). Consumption scales per events; premium uses `always_ready_instances` for warm workers.

**B9. How do you use a custom domain + TLS for an HTTP function?**
**Answer:** Bind a custom hostname + certificate (App Service managed cert or Key Vault cert) via `azurerm_app_service_custom_hostname_binding`/`azurerm_app_service_certificate_binding`.

**B10. How do you monitor Functions with Terraform?**
**Answer:** Application Insights resource + settings, plus `azurerm_monitor_metric_alert`/log alerts on function metrics (execution count, failures, duration) routed to an ops topic.

**B11. How do you restrict HTTP access to a function (auth)?**
**Answer:** Function-level auth (function keys / App Service auth via `auth_settings_v2`) or front with API Management/Front Door. Terraform can configure `auth_settings_v2` with an identity provider.

**B12. How do you standardize many Function Apps with a module?**
**Answer:** A function module with inputs (plan, runtime, storage, settings, identity, VNet, alerts) instantiated per function, so all functions share conventions for secrets, monitoring, and networking.

## Case C — Scenario

**C1. Your HTTP function intermittently times out on cold start.**
**Answer:** Move to a Premium plan with pre-warmed instances (or add `always_ready_instances`), optimize the package/deps, and increase the HTTP timeout where the caller allows.

**C2. A function can't reach an internal API in a private VNet.**
**Answer:** Enable regional VNet integration (delegated subnet) on the Function App, ensure NSG/routing allow it to the API's subnet, and use the private DNS name.

**C3. Secrets are hardcoded in app settings; how do you remediate?**
**Answer:** Move secrets to Key Vault, grant the function's managed identity access, switch settings to `@Microsoft.KeyVault(SecretUri=...)` references, and rotate the exposed values.

**C4. The function runs too long for the consumption plan's 10-minute limit.**
**Answer:** Migrate to Premium (or Durable Functions to fan out work), refactor long tasks into queue-triggered chunks, and set a sensible timeout.

**C5. You need to call the function from another app with authentication.**
**Answer:** Enable App Service auth (function keys or an identity provider via `auth_settings_v2`), or front it with API Management to add API keys/OAuth — then have callers authenticate.

**C6. Costs spiked unexpectedly on a consumption function.**
**Answer:** Check invocation count and `daily_memory_time_quota`, add alerts on execution metrics, optimize code efficiency, and consider a premium plan if traffic is sustained (which can be cheaper than high per-execution cost).
