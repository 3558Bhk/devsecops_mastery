# Terraform App Service (Azure) — Interview Questions

> **Cloud:** Azure · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~5 min

---

## Case A — Basic

**A1. What is Azure App Service in Terraform?**
**Answer:** A managed PaaS for web apps/APIs, defined with `azurerm_service_plan` (the hosting plan) and `azurerm_linux_web_app`/`azurerm_windows_web_app` (the app).

**A2. What is an App Service Plan?**
**Answer:** `azurerm_service_plan` — the compute tier (sku, size, region) shared by one or more apps, determining cost and features.

**A3. How do you declare a Linux web app?**
**Answer:** `resource "azurerm_linux_web_app" "app" { name = ... ; resource_group_name = ... ; service_plan_id = azurerm_service_plan.plan.id ; site_config { } }`.

**A4. What is the relationship between a plan and an app?**
**Answer:** Apps run on a plan; the plan's SKU defines the underlying compute. Multiple apps can share one plan (shared capacity).

**A5. How do you set app settings and connection strings?**
**Answer:** `app_settings` (env vars) and `connection_string` blocks on the web app resource.

**A6. What is `site_config` used for?**
**Answer:** Runtime stack, `always_on`, HTTPS-only, health check path, worker count, and language versions.

**A7. How do you enable HTTPS-only?**
**Answer:** `https_only = true` on the web app, redirecting HTTP to HTTPS.

**A8. What is a deployment slot?**
**Answer:** `azurerm_linux_web_app_slot` — a staging environment for an app that can be swapped with production (zero-downtime swaps).

**A9. What is a custom domain and TLS binding?**
**Answer:** `azurerm_app_service_custom_hostname_binding` + a certificate to serve your domain over HTTPS.

**A10. How do you configure continuous deployment?**
**Answer:** The app's `site_config`/`source_control` (or App Service "Deployment Center") pointing at GitHub/Azure DevOps, or deploy via the pipeline after Terraform creates the app.

**A11. What is a managed identity on App Service?**
**Answer:** An `identity` block giving the app an Azure AD identity to access Key Vault/storage without secrets.

**A12. What is VNet integration?**
**Answer:** `azurerm_app_service_virtual_network_swift_connection` (or newer subnet delegation) lets the app reach private resources in a VNet.

**A13. How do you set the runtime stack (e.g. Node/Python)?**
**Answer:** In `site_config`, e.g. `application_stack { node_version = "18-lts" }` or `linux_fx_version = "PYTHON|3.12"`.

**A14. What is `always_on`?**
**Answer:** Keeps the app loaded (no idle unload) — required for some features and for consistent background processing.

**A15. How do you output the app's URL?**
**Answer:** `output "url" { value = azurerm_linux_web_app.app.default_hostname }`.

## Case B — Advanced / Senior

**B1. How do you do zero-downtime deploys with deployment slots?**
**Answer:** Deploy to a staging slot (`azurerm_linux_web_app_slot`), warm it up, then swap with production (`azurerm_app_service_active_slot`/slot swap) — Azure swaps the routing instantly.

**B2. How do you store secrets for an App Service with Key Vault?**
**Answer:** Use a Key Vault reference in app settings (`@Microsoft.KeyVault(SecretUri=...)`) with the app's managed identity granted read access — secrets never live in the config.

**B3. What is the difference between a consumption plan, dedicated plan, and App Service Environment?**
**Answer:** Consumption (serverless, per-execution, for Functions), dedicated (your own VMs, fixed cost), and ASE (isolated, private, single-tenant). Choose by isolation/cost/scale needs.

**B4. How do you integrate an App Service with a private VNet for backend resources?**
**Answer:** Regional VNet integration (delegate a subnet to `Microsoft.Web/serverFarms`) so the app reaches private resources (SQL, storage) without public endpoints.

**B5. How do you configure autoscaling for an App Service Plan?**
**Answer:** `azurerm_monitor_autoscale_setting` targeting the plan, with scale-out/in rules on CPU/memory/requests — scaling instances, not just metrics.

**B6. What are the tradeoffs of many apps on one plan vs one app per plan?**
**Answer:** Sharing is cheaper but apps compete for CPU/memory and scale together; per-app plans isolate load and scaling but cost more. Balance by workload criticality.

**B7. How do you use a private endpoint for App Service (inbound)?**
**Answer:** `azurerm_private_endpoint` for the web app's `sites` subresource + a private DNS zone, so the app is reachable only inside your VNet.

**B8. How do you manage app settings across environments with Terraform?**
**Answer:** A web-app module with inputs (settings map, connection strings, secrets) instantiated per environment via tfvars/workspaces, keeping settings consistent.

**B9. What is `azurerm_app_service_certificate_binding` and certificate management?**
**Answer:** It binds a certificate (uploaded or Key Vault-stored) to a custom hostname for TLS — or use App Service Managed Certificates for free certs.

**B10. How do you enforce HTTPS, TLS version, and HSTS?**
**Answer:** `https_only = true`, `site_config { minimum_tls_version = "1.2" }`, and app-level headers for HSTS — plus a policy check to keep them on.

**B11. What is `ip_restriction`/access restriction in Terraform?**
**Answer:** `site_config { ip_restriction { ... } }` allow/deny lists (or `azurerm_app_service_virtual_network_swift_connection`) restricting who can reach the app.

**B12. How do you handle app content vs infrastructure separation?**
**Answer:** Terraform manages the infrastructure (plan, app, settings); app code deploys via CI (zip deploy/GitHub Actions), not via Terraform — keeps deploys fast and state clean.

## Case C — Scenario

**C1. Your app restarts randomly and you suspect idle timeout.**
**Answer:** Enable `always_on = true` (requires a paid tier) so the app doesn't idle out, and check health checks/metrics for other causes.

**C2. You need a staging version to test before release.**
**Answer:** Create a deployment slot with the same config, deploy the new build there, test, then swap to production — with auto-swap enabled for CI-driven releases.

**C3. A secret in app settings is exposed; how do you fix it properly?**
**Answer:** Move the secret to Key Vault, grant the app's managed identity read access, replace the app setting with a `@Microsoft.KeyVault(SecretUri=...)` reference, and rotate the exposed value.

**C4. The app must reach an internal API in a private VNet.**
**Answer:** Enable regional VNet integration on the app (delegated subnet) so outbound calls route through the VNet to the internal API, and allow the app's subnet in the API's NSG.

**C5. You're consolidating five apps onto one plan but worried about resource contention.**
**Answer:** Right-size the plan SKU, monitor per-app metrics, enable autoscaling, and split any noisy app onto its own plan — sharing is fine until a workload's spikes hurt others.

**C6. The app must be internet-facing but block a list of bad IPs.**
**Answer:** Add `ip_restriction` rules (deny the IPs, allow the rest) in `site_config`, optionally fronting with Front Door + WAF for richer filtering.
