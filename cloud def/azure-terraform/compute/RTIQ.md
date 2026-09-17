# RTIQ — Terraform Compute on Azure (Real-Time Interview Questions)

> **Cloud:** Azure · **Tool:** Terraform · **Domain:** Virtual machines/VMSS, App Service, Functions, AKS · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~38 min

**How this file is used live:** Azure compute rounds test whether you can express a *service's* lifecycle in Terraform — slots, VNet integration, managed identity, image versions, node pools — and whether you can recover when an apply goes wrong. Expect plan reviews ("this will replace 40 VMs, what now?") and questions about identity and secrets.

**Legend:** ⚡ Rapid · 🔍 Deep dive · 🚨 War room · ⚖️ Trade-off · 🎯 Senior signal

---

## 1. Virtual Machines & Scale Sets — `virtual-machines.md`

**⚡ Rapid**
1. **Q:** Core resources for a VM in Terraform?
**A.** `azurerm_linux_virtual_machine`/`azurerm_windows_virtual_machine` (with `size`, `admin_username`, `network_interface_ids`, `os_disk`, `source_image_id`/`source_image_reference`, `identity`), `azurerm_network_interface` (subnets, private IPs, ASG membership), `azurerm_managed_disk`, and `azurerm_virtual_machine_extension` (monitoring/Defender/custom script).
2. **Q:** Which is preferred: VM or VMSS?
**A.** VMSS (flexible orchestration) for anything horizontal and stateless — it supports zones, rolling upgrades, and autoscale, and can host a single instance when you don't need scale. Individual VMs are for genuinely unique/pet workloads (jump hosts, appliances) and even those benefit from being rebuilt from images.
3. **Q:** How do you do zone-redundant VMs/VMSS in Terraform?
**A.** `zones = ["1","2","3"]` on the VMSS (or the VM) with the load balancer/App Gateway frontend also zone-redundant, and managed disks/OS disks configured appropriately (ZRS where supported). Availability sets (`azurerm_availability_set`) are the older intra-datacentre option — use zones where the region supports them.
4. **Q:** Where do credentials come from?
**A.** No passwords: SSH keys (`admin_ssh_key`) for Linux, and preferably no keys at all — use Azure AD login/Bastion/SSH over Azure AD. Windows: `admin_password` from Key Vault (or AD join) and no RDP exposure.
5. **Q:** How do you attach managed identities?
**A.** An `identity { type = "SystemAssigned" | "UserAssigned", identity_ids = [...] }` block on the VM/VMSS, then role assignments (`azurerm_role_assignment`) and Key Vault access for the principal ID. Prefer user-assigned for consistency across rebuilds/scales.
6. **Q:** How do you handle images?
**A.** `source_image_reference` for marketplace images (publisher/offer/sku + `version` — pin, don't use `latest`), or `source_image_id` referencing an Azure Compute Gallery image version (`azurerm_shared_image_version`). Versioned gallery images + VMSS rolling upgrades are the production pattern.
7. **Q:** How do you do bootstrapping?
**A.** `custom_data` (cloud-init) for simple first-boot config, or VM extensions (Custom Script, DSC, Azure Monitor Agent) — and nothing that can't be re-run (scripts are not idempotent by default). Prefer golden images for anything heavy; keep cloud-init minimal.
8. **Q:** What disks do you need to plan?
**A.** OS disk (size/type; Premium SSD by default for production), optional data disks (`azurerm_managed_disk` + attachment), and the disk caching setting. Disk type/size affects IOPS and cost — and Azure VM SKUs have uncached IOPS/throughput ceilings you can hit.

**🔍 Deep dive**
9. **Q:** Design a zone-redundant VMSS deployment in Terraform with rolling upgrades.
**A.** Flexible VMSS across 3 zones with `platform_fault_domain_count`, `instances` managed by autoscale rules (`azurerm_monitor_autoscale_setting`, min 3 for zone redundancy), a load balancer/App Gateway backend pool with health probes, `upgrade_mode = "Rolling"` (or `"Automatic"`) with `rolling_upgrade_policy { max_batch_instance_percent, max_unhealthy_instance_percent, pause_time_between_batches }`, an Azure Compute Gallery image version input, managed identity + Key Vault access, Azure Monitor Agent via `extension` with a DCR association, and diagnostics (`azurerm_monitor_diagnostic_setting`) to a central workspace. Outputs: VMSS ID/name and the principal ID for role assignments.
**↳ Follow-up:** "How do you roll back a bad image version?"
**A.** Point the VMSS at the previous gallery image version and let the rolling upgrade replace instances (or perform an explicit rolling upgrade), because images are immutable and versioned. That's exactly why you don't use `latest` — rollback is a one-line config change plus a rolling upgrade, and you should test the timing of that path once.
10. **Q:** How do you handle patching in Terraform?
**A.** Update Manager (via `azurerm_maintenance_configuration` and `azurerm_maintenance_assignment_virtual_machine`/`dynamic_scope`) with rings by tag, or image rebuild + VMSS rolling upgrade for immutable fleets (preferred for stateless). Terraform defines the maintenance configuration; the act of patching is the platform's, and compliance evidence comes from Update Manager/Resource Graph.
11. **Q:** How do you attach VMSS to a load balancer or App Gateway?
**A.** `azurerm_lb_backend_address_pool` association via the VMSS's `network_interface` block (or `azurerm_lb_backend_address_pool_address` for individual IPs), and for App Gateway the backend pool referencing the VMSS ID (or its NICs). Health probes must match the app's readiness endpoint, else you'll see healthy infrastructure with failing requests.
12. **Q:** How do you handle VM extensions and their ordering?
**A.** Extensions are separate resources with implicit dependencies (some need the other first, e.g. dependency agent after the monitoring agent); use `depends_on` where needed and be aware that a failed extension can leave the VM in a bad provisioning state. Prefer fewer extensions, and consider baking configuration into the image to reduce extension reliance.
13. **Q:** How do you do VM-level backups in Terraform?
**A.** `azurerm_backup_policy_vm` + `azurerm_backup_protected_vm` in a Recovery Services vault (`azurerm_recovery_services_vault`), with the vault's redundancy (LRS/GRS/ZRS), `soft_delete_enabled`, and (for ransomware resilience) immutability + multi-user authorisation. Backups are a platform standard implemented by a module and applied by tag.
14. **Q:** How do you handle disk encryption?
**A.** Platform-managed keys by default; for CMK, `azurerm_disk_encryption_set` backed by Key Vault (with the key's permissions for the DES identity) referenced on the VM/disks, and `encryption_at_host_enabled = true` where required (encrypts temp disks/caches). Note the SKU/region constraints for encryption at host.
15. **Q:** How do you structure a VM/VMSS module?
**A.** Inputs: naming/env/region, subnet ID (or list), size/SKU and zone list, image (gallery version or marketplace reference), identity (user-assigned IDs), data disks (map), extensions/agents, tags, and diagnostics destination. Externally it hides NIC/disk/extension wiring; internally it's opinionated (no public IPs, no password auth, zone-redundant by default, monitoring on). Outputs: VMSS ID, name, principal ID, private IPs (if any).

**🚨 War room**
16. **Q:** A plan wants to replace a production VMSS (or 40 VMs). What do you do?
**A.** Find the forcing attribute — `zone` changes, `network_interface` restructuring, image reference format changes, or a name change all force replacement. Then either fix the config to an in-place change or plan a deliberate migration (a second VMSS behind the same load balancer, shift traffic, then delete the old). Add a plan-level policy that flags replacement of compute resources for manual approval.
17. **Q:** After an apply, half the VMSS instances fail health checks.
**A.** Likely the new image/config is broken (app not starting, extension failure, missing Key Vault/secret access from the new managed identity, NSG blocking the probe) or the probe is too strict for the boot time. Check the instance's boot diagnostics/serial log and extension status, then pause the rolling upgrade and fix forward or roll the image back.
18. **Q:** VMs can't reach Key Vault/storage after a networking change.
**A.** Private endpoint DNS resolution (the VM resolves the public FQDN and gets blocked), missing private DNS zone link, or the subnet's egress path changed (NAT/UDR). Verify from inside the VM with `nslookup`/`curl`, then fix DNS or routing. This is the most common post-change failure in private Azure environments.
19. **Q:** An apply failed and left VMs in a failed provisioning state.
**A.** Check `az vm get-instance-view`/the resource's `provisioning_state` and the error (quota, SKU unavailable in the zone, extension failure). Often the fix is to retry after addressing the cause; in bad cases, redeploy (deallocate/redeploy) or rebuild from the image. Terraform's next plan may show a change — apply after fixing the root cause rather than tinkering.
20. **Q:** Costs jumped after an autoscale rule change.
**A.** Check `min_count`/`max_count`, the metric and thresholds (a low CPU target with a long scale-in cooldown keeps instances running), whether the default scale-in is too slow, and whether the new instances are over-provisioned SKUs. Also check for orphaned disks/NICs/public IPs from replaced VMs (a classic Azure cost leak Terraform should clean up via `delete_os_disk_on_termination`/lifecycle settings).
21. **Q:** An engineer resized a production VM in the portal and Terraform wants to resize it back.
**A.** Terraform is enforcing the declared state — correct behaviour. Confirm the resize was intentional; if yes, codify it (update the module/tfvars and apply); if not, let Terraform revert it. Then address the process: read-only console access, plus activity-log alerts on VM size changes outside the pipeline.
22. **Q:** VMSS instances were deleted by the autoscaler, and one contained local state.
**A.** That's the anti-pattern: state must live outside the instance (managed disk attached to a stable resource, Azure Files, a database, or a queue). Restore what's recoverable from backups, then redesign the workload to be stateless. Autoscalers delete instances by design — the interview point is that the design, not the autoscaler, is at fault.

**⚖️ Trade-off**
23. **Q:** VMs vs VMSS vs App Service vs Container Apps?
**A.** VMs when you need OS-level control/legacy software; VMSS for horizontal stateless fleets with images and rolling upgrades; App Service for standard web workloads with least ops; Container Apps for containers without cluster management. Choose by capability need and the team's operational capacity.
24. **Q:** Availability sets vs availability zones?
**A.** Sets protect against host/rack failure within one datacentre (99.95% SLA) and give fine-grained fault domains; zones protect against datacentre failure (99.99%) but are region-dependent and require zone-aware services (LBs, disks). Production default where supported: zones.
25. **Q:** Marketplace images vs Azure Compute Gallery images?
**A.** Marketplace images are convenient but unversioned in practice (unless you pin versions) and unmodified; gallery images are versioned, replicable, hardened, and support rolling upgrades/rollback — the production pattern. Start from a hardened marketplace base in your image pipeline.
26. **Q:** Extensions vs golden images for configuration?
**A.** Golden images (baked) give fast, immutable, reproducible instances with no per-boot drift; extensions/config at boot are flexible for environment-specific values but add failure modes and slow provisioning. Bake everything static; use cloud-init/extensions only for per-environment facts (and keep the count small).
27. **Q:** Autoscale on CPU vs a custom/service metric?
**A.** CPU is easy and often used, but if the bottleneck is queue depth, request latency, or connection count, scaling on CPU will be too late. App Service/VMSS can autoscale on custom metrics (via `azurerm_monitor_autoscale_setting` rules with metric triggers) — match the metric to the constraint.
28. **Q:** Spot VMs/VMSS for cost — when?
**A.** Interruptible workloads (batch/CI/stateless tests) where eviction is tolerable, with a mixed policy (an on-demand base + Spot), graceful shutdown handling, and no single-instance services. Say that eviction is a scheduled event your app must tolerate, not an exception.
29. **Q:** Self-managed VM fleet vs Azure's managed compute (App Service/Functions/Container Apps)?
**A.** Managed services remove OS/patching/scaling work at the cost of control and some lock-in; IaaS gives control and legacy compatibility at the cost of operational ownership. For new stateless workloads, managed services usually win — and the interview is really asking whether you reach for VMs by default.

**🎯 Senior**
30. **Q:** What does production-grade compute look like in Terraform on Azure?
**A.** Golden gallery images with pinned versions and a rebuild pipeline; zone-redundant VMSS with min ≥3 instances and autoscale tied to the real bottleneck metric; no public IPs and no password auth (Bastion/Azure AD login); user-assigned managed identities with least-privilege role assignments; private endpoints + linked private DNS zones for PaaS dependencies; Azure Monitor Agent with DCRs, diagnostics and alerts; backups via a tag-driven policy with soft delete and immutability where required; maintenance/patching rings; `prevent_destroy` where state or identity matters; and a plan-level gate that requires manual approval for any replacement of compute resources.

**🎯 Senior signal:** "rollback is repointing the image version plus a rolling upgrade", orphaned disks/NICs as a cost leak, and encryption-at-host vs platform-managed keys. Those three are earned Azure compute details.

---

## 2. App Service — `app-service.md`

**⚡ Rapid**
1. **Q:** Core Terraform resources for App Service?
**A.** `azurerm_service_plan` (SKU/OS/zone redundancy), `azurerm_linux_web_app`/`azurerm_windows_web_app` (site config, app settings, identity), `azurerm_app_service_slot` (staging), `azurerm_app_service_custom_hostname_binding`, `azurerm_app_service_managed_certificate` (or Key Vault cert), and `azurerm_app_service_virtual_network_swift_connection` for VNet integration.
2. **Q:** How do you do zero-downtime deployments?
**A.** A `staging` slot, deploy to it, warm it, then swap (`azurerm_app_service_active_slot` or the pipeline's swap action) — with `azurerm_app_service_slot` mirroring the production config and slot-sticky settings where needed. App settings should be marked sticky (`slot_config_names`/`sticky_settings`) for environment-specific values.
3. **Q:** How do you integrate with a VNet?
**A.** Outbound: `azurerm_app_service_virtual_network_swift_connection` with a delegated subnet. Inbound: private endpoint (`azurerm_private_endpoint` + DNS zone `privatelink.azurewebsites.net`) and/or access restrictions. Both are needed for a private app — most teams do one and are surprised.
4. **Q:** How do you handle lets-encrypt-style certificates?
**A.** `azurerm_app_service_managed_certificate` for free managed certs (single domain, auto-renew with correct DNS validation), or Key Vault certificates referenced with the app's managed identity for wildcards/multi-domain. Terraform manages the binding, not the renewal process (for Key Vault certs, the renewal is the CA/Key Vault's job, with alerts).
5. **Q:** Where do app settings and secrets go?
**A.** `app_settings` on the app/slot for non-secrets; Key Vault references (`@Microsoft.KeyVault(SecretUri=...)`) for secrets with the app's managed identity granted `Key Vault Secrets User`. Secrets never in tfvars/state — a Terraform-managed app setting with a secret lands in state.
6. **Q:** How do you enable health checks?
**A.** `health_check_path` in the site config (and in production slot settings) plus Application Insights/availability tests; the platform uses the path for load-balancer-style health and can replace unhealthy instances. Combine with `auto_heal` rules if needed.
7. **Q:** How do you scale App Service?
**A.** `azurerm_monitor_autoscale_setting` on the service plan (`azurerm_service_plan` must be Standard+), with rules on CPU/memory/queue length (or `azurerm_monitor_autoscale_setting` custom metrics); `zone_balancing_enabled` on the plan for zone redundancy, and instance counts ≥2–3 for production. Remember scaling is per-plan — apps in the same plan share instances.
8. **Q:** What are common App Service Terraform gotchas?
**A.** Slots sharing the plan's resources; settings that aren't sticky changing on swap; the connection string/app setting names differing between Windows/Linux; `always_on` not applicable on the free tier; VNet integration requiring a delegated subnet and Premium for certain features; and private endpoints needing the right DNS zone to work end to end.

**🔍 Deep dive**
9. **Q:** Design an App Service deployment in Terraform for a production web app (private, zero-downtime, observable).
**A.** Premium v3 service plan (zone redundancy enabled, autoscale min 3), Linux web app with system-assigned or user-assigned identity, private endpoint for inbound + `ip_restriction`/access restrictions allowing Front Door, VNet integration (delegated subnet) for outbound to private PaaS, Key Vault references for secrets, `health_check_path` configured, staging slot with sticky settings for environment values, `azurerm_app_service_custom_hostname_binding` + managed/Key Vault certificate, Application Insights (`azurerm_application_insights`) with a connection string, diagnostic settings to Log Analytics, and alerts on 5xx/latency/instance count. Deployment is via the pipeline to the slot then a swap — Terraform owns the configuration, not the code.
**↳ Follow-up:** "How do you keep the app's configuration identical between slots?"
**A.** Define settings once (a map in locals) and apply the same map to the app and the slot, keeping only genuinely slot-specific values sticky. Also verify with a post-swap smoke test because the swap can surface differences immediately (a non-sticky connection string pointing at the wrong database is the classic incident).
10. **Q:** How do you handle multiple apps/environments without duplication?
**A.** A module taking a typed object per app (name, plan inputs, settings, tags, VNet/identity settings) called per app, with per-environment tfvars. Keep plan sharing deliberate (which apps share a plan) — it's a performance and cost decision, not an accident.
11. **Q:** How do you do custom domains and DNS?
**A.** `azurerm_dns_zone` + `azurerm_dns_cname_record`/`azurerm_dns_txt_record` (validation) + `azurerm_app_service_custom_hostname_binding`, with managed certificates for automatic TLS. For apex domains use A records + TXT validation (or Front Door). Automation matters: DNS validation records are often the piece people do manually and then break on renewal.
12. **Q:** How do you handle App Service for containers?
**A.** `azurerm_linux_web_app` with `docker_image`/`docker_image_name` and, for private registries, registry credentials from Key Vault plus the app's identity; plus a webhook or pipeline step to update the image tag. Terraform should manage config and the image reference (as a variable), not build images.
13. **Q:** How do you handle staging/blue-green with slots vs a second app?
**A.** Slots are cheap and fast (swap is near-instant) but share the plan's resources; a second app in its own plan gives full isolation (useful for load tests or capacity differences) at double cost. Slots for normal releases; separate apps when isolation matters.
14. **Q:** How do you secure an App Service end-to-end?
**A.** Private endpoint (no public access), Front Door/App Gateway in front with WAF, access restrictions to the edge's service tag plus a header check, managed identity for PaaS access (no secrets), Key Vault references, HTTPS-only + minimum TLS 1.2, FTPS disabled, remote debugging off, SCM site also locked down (the SCM endpoint is a separate attack surface people forget), Defender for App Service enabled, and diagnostics/App Insights to a central workspace.
15. **Q:** How do you do blue/green with traffic splitting?
**A.** App Service supports `traffic_route` on the production slot's `azurerm_app_service_slot`? In practice: for gradual traffic shifting, use a slot swap for instant cutover, or Front Door origins/weights for canary percentages, or App Gateway multi-backend with weighted rules. Terraform can express Front Door weights — which makes canary reviewable in code.

**🚨 War room**
16. **Q:** A swap caused 500s for 2 minutes.
**A.** The staging slot wasn't warmed (cold start/DI/JIT), settings differed after the swap (non-sticky app settings), or the app's health wasn't verified before the swap. Fix: warm the slot (`WEBSITE_WARMUP_PATH`/App Init), run smoke tests against the slot before swapping, do a swap-with-preview, and mark environment-specific settings sticky. Then add post-swap alarms so a regression is caught automatically.
17. **Q:** After enabling private endpoints, the app can't reach the database.
**A.** Inbound vs outbound confusion: the private endpoint makes the app private for *incoming* traffic; outbound to the DB needs VNet integration (swift connection) plus the DB's private endpoint/DNS zone linked to that integration subnet. Fix by adding integration and verifying DNS resolution from the app's Kudu/SSH console.
18. **Q:** The app is slow every morning at 9 a.m.
**A.** `always_on` is off (the app unloads when idle), cold starts after a recycle, an overnight scaling-in event, or a scheduled job colliding with the traffic ramp. Verify with metrics (response time, instance count) and fix the configuration (`always_on = true`, min instances, warm-up). It's a configuration question, not a mystery.
19. **Q:** Costs spiked after an autoscale change on the plan.
**A.** Rules too aggressive (low thresholds, long scale-in cooldowns), min instances raised and never reduced, or a Premium plan scaled up for a temporary load test. Right-size the rules from actual metrics and confirm the plan's SKU matches the workload (Premium when isolation/scale is needed, Standard otherwise).
20. **Q:** Someone changed an app setting in the portal and a later apply reverted it, breaking the app.
**A.** The revert is Terraform enforcing desired state; the break happened because the change was needed and untracked. Codify the necessary change (in the module/tfvars) and re-apply, then reduce the chance of out-of-band changes: read-only console for production, alerts on site-config changes (activity log/Config), and a policy preventing direct edits where possible.
21. **Q:** Certificate renewal broke custom domain bindings.
**A.** The binding referenced a specific certificate version (instead of the Key Vault secret's versionless ID) or the DNS validation record was missing for a managed certificate. Fix the reference and the validation record, then add expiry alerts and a synthetic TLS check so renewals are validated automatically.
22. **Q:** The app works via the Azure-generated hostname but not the custom domain (or vice versa).
**A.** The custom domain binding/validation is incomplete, or access restrictions/WAF rules reference the Azure hostname so requests to the custom domain are blocked. Also possible: Front Door is configured for the custom hostname but the origin host header is wrong. Check the binding, the access restrictions, and the origin host header — in that order.

**⚖️ Trade-off**
23. **Q:** App Service vs Container Apps vs AKS for a web app?
**A.** App Service: least ops, built-in slots/scaling/auth, best for standard web/API workloads. Container Apps: containers without cluster ops, event-driven scaling (KEDA), and Dapr. AKS: full Kubernetes with platform standardisation at real operational cost. Choose by workload shape and team capacity.
24. **Q:** Shared plan vs per-app plan?
**A.** Shared plans cut cost and are fine when apps have similar load/importance; a noisy app then affects the others, and autoscaling decisions apply to all. Per-app plans isolate performance/cost at higher spend. Production user-facing apps usually deserve their own plan.
25. **Q:** Slots vs separate app for staging?
**A.** Slots share the plan (cheap, fast swap, easy rollback) but compete for resources and share some platform limits; a separate app gives isolation (useful for load testing or different SKUs) but doubles cost and complicates DNS/config parity. Slots for standard release flow.
26. **Q:** Managed certificates vs Key Vault certificates?
**A.** Managed certs are free and auto-renew but limited to single domains (no wildcards) and require correct DNS validation; Key Vault gives wildcard/multi-domain support and central management with automatic renewal if the CA integration is configured, but you own the plumbing. Choose by domain strategy.
27. **Q:** App Service vs VM for a legacy app that "must have OS access"?
**A.** If it truly needs OS-level control (kernel modules, specific services, GPU), a VM/VMSS with a golden image is correct; otherwise App Service for containers can often host it via a custom image. Challenge the requirement once — many "must have OS access" cases are really "we don't want to change the deployment model".
28. **Q:** Zone redundancy on vs off for the plan?
**A.** Zone redundancy (zone_balancing_enabled with ≥3 instances) survives a zone failure and is the production default where the region supports it; it costs more (more instances) and needs the region's availability-zone support. Off is acceptable only for non-critical/dev workloads.
29. **Q:** Should Terraform deploy the app code?
**A.** No — Terraform manages the infrastructure/config (plan, app, settings, bindings, slots); the pipeline deploys code/containers via zip deploy/containers/`az webapp deploy`. Mixing code into Terraform state is brittle and bypasses the app's own CI. Draw the boundary explicitly.

**🎯 Senior**
30. **Q:** What does production-ready App Service look like in Terraform?
**A.** Premium v3 plan with zone redundancy and autoscale (min 3), private endpoint inbound plus VNet integration outbound with linked private DNS zones, Front Door/App Gateway with WAF in front and access restrictions limited to the edge, managed identity + Key Vault references (no secrets in state), health check path configured, staging slot with identical settings (sticky only for env-specific values) and a warm-up + swap-with-preview flow, managed/Key Vault certificates with expiry alerts, Application Insights + diagnostics + alerts on 5xx/latency/instances, `always_on` enabled, FTPS/debugging disabled, and code deployed by the pipeline (not Terraform).

**🎯 Senior signal:** "inbound private endpoint and outbound VNet integration are different things", "swap without warming will 500", and keeping secrets out of state via Key Vault references. Those three are the practical tells.

---

## 3. Azure Functions — `azure-functions.md`

**⚡ Rapid**
1. **Q:** Core resources for a Function App?
**A.** `azurerm_service_plan` (Consumption/Premium/App Service plan) or the Flex Consumption plan resources, `azurerm_linux_function_app`/`azurerm_windows_function_app` with `storage_account_name` + `storage_account_access_key` (or managed identity), `azurerm_storage_container` for deployments, `azurerm_application_insights`, and identity/role assignments.
2. **Q:** How do you avoid keys in the Function App config?
**A.** Use managed identity for the storage account (`storage_uses_managed_identity = true`) and role assignments for blob/queue access, plus `AzureWebJobsStorage__accountName`-style settings for identity-based storage connections. Secrets go via Key Vault references.
3. **Q:** Hosting plan choices in Terraform?
**A.** `azurerm_service_plan` with `sku_name = "Y1"` (Consumption), `EP1`–`EP3` (Premium — pre-warmed, VNet, longer timeouts), or a dedicated plan (B1+/P1v3); Flex Consumption uses `azurerm_function_app_flex_consumption`. Choose by latency tolerance, timeout needs, and network requirements.
4. **Q:** How do you do VNet integration?
**A.** `virtual_network_subnet_id` on the app (or `azurerm_app_service_virtual_network_swift_connection`) with a delegated subnet for outbound; inbound private endpoints need `privatelink.azurewebsites.net` + access restrictions. Premium/Flex plans support the fuller set of features — Consumption has limits.
5. **Q:** Where does the code live?
**A.** Deployed by the pipeline (zip deploy/`func azure functionapp publish`/container image), not by Terraform. Terraform manages the app, settings, identity, storage, and monitoring; the code artifact is a pipeline concern with its own versioning.
6. **Q:** How do you configure app settings safely?
**A.** Non-secret settings in `app_settings`; secrets as Key Vault references resolved via managed identity. Remember `WEBSITE_RUN_FROM_PACKAGE`/deployment settings that the platform needs, and mark the storage connection in the identity-based form so no keys are stored.
7. **Q:** How do you monitor Functions?
**A.** `azurerm_application_insights` (connection string in app settings), diagnostic settings to Log Analytics, metric/log alerts on failures/execution count/duration, and alarms on storage queue depth (for queue-triggered functions). Since instances are ephemeral, telemetry is the only reliable debugging surface.
8. **Q:** What are the common Function Terraform gotchas?
**A.** The storage account dependency (functions need it for state/keys — a shared single point of failure), consumption-plan limitations with VNet/private endpoints, `WEBSITE_CONTENTSHARE` naming, slot settings, and the fact that a change to certain app settings triggers a restart. Also: identity-based storage connections use different setting names than connection strings — mixing them breaks startup.

**🔍 Deep dive**
9. **Q:** Design a Functions deployment in Terraform for an event-driven workload (Service Bus → Function → Cosmos DB).
**A.** Premium plan (or Flex) with VNet integration and private endpoints, Function App with managed identity, role assignments for Service Bus receiver + Cosmos DB data contributor, storage account with private endpoints and identity-based access (`storage_uses_managed_identity = true`), Application Insights with alerts on failures/duration, Service Bus queue with DLQ and an alarm on DLQ depth, Cosmos container with the right partition key and autoscale, and app settings for `maxConcurrentCalls`/prefetch to protect downstreams. Code deployed by the pipeline; Terraform owns the wiring.
**↳ Follow-up:** "How do you protect the database from a Functions scale-out storm?"
**A.** Bound the concurrency in the trigger configuration (`maxConcurrentCalls`/`maxConcurrentSessions` for Service Bus, host-level `functionTimeout`/`maxOutstandingRequests`), use identity-based connections with a connection pool or an intermediary (e.g. Cosmos SDK with sensible retries), and set alert thresholds on the downstream's throttling metrics. Scaling is the platform's job; bounding blast radius is yours — and it's a Terraform-visible setting.
10. **Q:** How do you manage secrets and identity in Terraform for Functions?
**A.** Managed identity (system or user-assigned) with `azurerm_role_assignment` at the narrowest scope, Key Vault references in settings for third-party secrets, and no `storage_account_access_key` when identity-based storage is used. Where a key must exist, source it from Key Vault rather than state.
11. **Q:** How do you handle multiple environments?
**A.** A module taking environment inputs (plan SKU, concurrency settings, identity IDs, VNet/subnet, alert thresholds) and per-environment tfvars; separate function apps per environment with their own storage and Key Vault. Avoid sharing a storage account across environments — the failure and security boundaries blur.
12. **Q:** How do you do private-only Functions?
**A.** Premium/Flex plan with VNet integration (outbound), private endpoints for inbound (with private DNS zones for `azurewebsites.net` and `blob/queue/table.core.windows.net`), access restrictions denying public traffic, and a deployment path for the pipeline (self-hosted runner in the VNet or a service-endpoint route). Consumption plan can't do all of this — plan choice is the constraint.
13. **Q:** How do you handle the storage account dependency?
**A.** Put the Function App's storage in a dedicated account per app (or at least per environment), enable soft delete/versioning where relevant, use identity-based access (no keys), and monitor it (the failure mode is that everything breaks at once). For high throughput, consider separate accounts per function app to avoid the shared 20,000-IOPS-class limits.
14. **Q:** How do you do deployment slots for Functions?
**A.** `azurerm_linux_function_app_slot` with the same settings, then swap via the pipeline; note slot-specific app settings (sticky) and that some triggers (timers) behave differently during the swap. Slots need a Standard+ plan.
15. **Q:** How do you handle timer triggers safely with multiple instances?
**A.** Timer triggers fire per instance — so a scaling function can run the job multiple times. Make the function idempotent and use a distributed lock (blob lease) or `WEBSITE_MAX_DYNAMIC_APPLICATION_SCALE_OUT = 1` (consumption) for singleton behaviour. This is a design point the interviewer wants to hear because it causes duplicate work in production.

**🚨 War room**
16. **Q:** All functions in a region stopped after a storage account change.
**A.** The shared storage account is the Function runtime's backing store — a firewall/network change, key rotation, or deleted container breaks everything at once. Check the storage account's network rules and the identity's role assignment, and restore access. Then split storage per app/environment and add alerts on storage auth failures.
17. **Q:** Where do you look when a function fails silently?
**A.** Application Insights (exceptions/traces with the operation ID), the function's invocation logs, the trigger's poison/DLQ (for Service Bus/queues), and the host's health (startup errors appear in logs before invocations). If telemetry is missing, that's the first fix — check the App Insights connection string and sampling settings.
18. **Q:** Costs jumped 4× on a Consumption plan.
**A.** Check execution counts and GB-seconds: a polling trigger or retry loop, verbose logging into App Insights (a hidden but significant cost), increased duration from a slow dependency, or unused premium instances at minimum. Fix the trigger/code and set App Insights retention/sampling deliberately.
19. **Q:** After enabling a private endpoint, the function can't reach the storage account.
**A.** Missing private DNS records — the function resolves the public storage endpoint and is blocked. Link `privatelink.blob.core.windows.net` (and queue/table/file as needed) to the VNet used for integration, verify from the Kudu/SSH console, and check that the app's `WEBSITE_VNET_ROUTE_ALL`/DNS settings are correct for the plan type.
20. **Q:** A plan wants to recreate the Function App (name change from a random suffix).
**A.** Random suffixes computed in locals (rather than a `random_string` resource in state) regenerate and force recreation — that's the classic cause. Fix by using a `random_string` resource whose value persists, and if recreation is needed, migrate deliberately (create the new app, switch consumers/DNS, delete the old). Also check `WEBSITE_CONTENTSHARE` naming if using slots.
21. **Q:** The function works locally but fails after deploy with an identity error.
**A.** Missing role assignments for the deployed identity (a common gap: local dev uses your credentials, the deployed app uses the managed identity) or the identity wasn't enabled/assigned in Terraform. Check the app's identity block, the role assignment scopes, and the exact error in App Insights — then add the role to the module so it can't be forgotten.
22. **Q:** Concurrency limits changed and downstream throttling alerts fired.
**A.** Someone raised `maxConcurrentCalls`/host concurrency without considering the downstream's capacity. Reset to a safe bound, add a documented rationale, and protect downstreams with autoscale limits (Cosmos RU autoscale, SQL tier) plus alerting. Terraform-visible settings should be reviewed with the same rigour as code.

**⚖️ Trade-off**
23. **Q:** Consumption vs Premium vs Flex Consumption vs Dedicated plan?
**A.** Consumption: cheapest per execution, scale-to-zero, cold starts, limited networking/timeout; Premium: pre-warmed instances, VNet, longer timeouts, higher cost when idle; Flex: modern scaling with VNet support and instance sizes; Dedicated: predictable cost and always-on capacity. Match to latency/VNet requirements and steady-state load.
24. **Q:** Functions vs Container Apps vs AKS for event-driven work?
**A.** Functions for short, event-driven, low-ops work with rich triggers/bindings; Container Apps for containers with KEDA scaling and no cluster ops; AKS when you need Kubernetes-level control or a standard platform. Trigger richness and execution duration usually decide.
25. **Q:** Keys vs managed identity for storage connections?
**A.** Managed identity removes secret rotation and is the modern default, but requires the right role assignments and (for some bindings) specific setting names; keys are simpler but are long-lived secrets that end up in config/state. Identity-first, keys only where a binding genuinely doesn't support identity.
26. **Q:** One Function App with many functions vs one app per concern?
**A.** Group by scaling/identity/network profile and lifecycle: functions that must scale together and share permissions can share an app; differing network requirements or privilege levels need separate apps. Over-splitting creates cost/config sprawl; under-splitting couples everyone to one decision.
27. **Q:** Deployment slots vs a second Function App?
**A.** Slots (Standard+ plans) enable warm deploys and swaps but share some platform state (and timer triggers can be awkward); a second app gives clean isolation for breaking changes at extra cost. For most releases, slots.
28. **Q:** Private endpoints for Functions — worth the complexity?
**A.** Yes when the workload handles sensitive data or must not traverse the public internet; the cost is networking complexity (integration subnet, DNS zones, deployment path for the pipeline) and plan limitations (Premium/Flex needed). For internal/low-risk functions, identity-based access with restricted networking may be adequate — but "public function app with a storage key in settings" is the pattern auditors flag.
29. **Q:** Terraform-managed function code vs pipeline?
**A.** Pipeline for code (with its own tests/versioning), Terraform for the platform (plan, identity, networking, settings, monitoring). Mixing them means every code change rewrites infrastructure state, and rollbacks get messy.

**🎯 Senior**
30. **Q:** What does production-ready Functions look like in Terraform?
**A.** Premium/Flex plan where networking/latency matters with VNet integration and private endpoints plus linked private DNS zones; managed identity throughout (storage, Service Bus, Cosmos, Key Vault) with scoped role assignments; identity-based storage connections and no keys in settings/state; App Insights with a connection string plus diagnostics to a central workspace and alarms on failures/duration/backlog/DLQ depth; DLQ and poison-message handling for async triggers; bounded trigger concurrency to protect downstreams; slots for deployment; storage per app/environment; and a pipeline that deploys code while Terraform owns the wiring.

**🎯 Senior signal:** "the runtime's storage account is a shared dependency — everything fails together", identity-based storage settings vs connection strings, and timer triggers being per-instance. Those three are real serverless-on-Azure detail.

---

## 4. AKS — `aks.md`

**⚡ Rapid**
1. **Q:** Core Terraform resources for AKS?
**A.** `azurerm_kubernetes_cluster` (default node pool, identity, network profile, `azure_active_directory_role_based_access_control`), `azurerm_kubernetes_cluster_node_pool` (additional pools, spot, taints/labels), `azurerm_kubernetes_cluster_extension` (or Helm) for add-ons like Azure Monitor/Policy, `azurerm_kubernetes_cluster_node_configuration`, and `azurerm_role_assignment` for RBAC.
2. **Q:** How do you give AKS workload access to Azure resources?
**A.** Workload identity: `azurerm_user_assigned_identity` + `azurerm_federated_identity_credential` on the AKS OIDC issuer + a Kubernetes service account annotation, then role assignments for the identity. This replaces the older pod-managed identity.
3. **Q:** How do you configure networking?
**A.** `network_profile` with `network_plugin = "azure"` (VNet IPs) or `"kubenet"`, `network_policy = "azure"` or Calico/Cilium, `service_cidr`/`dns_service_ip` (plan them — changing later is disruptive), and an outbound type (`loadBalancer`/`userDefinedRouting`/`managedNATGateway`). Subnet sizing must cover pod IPs with Azure CNI.
4. **Q:** How do you do private clusters?
**A.** `private_cluster_enabled = true` (or `private_cluster_public_fqdn_enabled` for a public FQDN with a private endpoint), `api_server_access_profile` for authorized IP ranges where public, and a private DNS zone (`azurerm_private_dns_zone` `privatelink.<region>.azmk8s.io`). Then plan how CI/kubectl reach the API server (jump host, self-hosted runner in the VNet, VPN).
5. **Q:** How do you configure RBAC?
**A.** `azure_active_directory_role_based_access_control` (Azure RBAC for Kubernetes authorization), local accounts disabled (`local_account_disabled = true`), and `azurerm_role_assignment` for admin/user roles (`Azure Kubernetes Service RBAC Cluster Admin`/`Reader`), plus Entra groups. Kubernetes-level RBAC (namespaces/roles) is usually managed by GitOps or a second Terraform stage.
6. **Q:** How do you do autoscaling?
**A.** Cluster autoscaler via `auto_scaling_enabled` + `min_count`/`max_count` on node pools (plus node pool `zones` for zone redundancy), HPA via Kubernetes resources (GitOps/Helm), and KEDA for event-driven scaling. Terraform owns the pool bounds; the cluster owns the rest.
7. **Q:** How do you handle upgrades?
**A.** `automatic_channel_upgrade` (patch/stable/rapid) or explicit `kubernetes_version` updates per environment, node pool `upgrade_settings` (max surge), and `maintenance_window`/`maintenance_window_auto_upgrade` to control timing. Plan the version path (minor-by-minor) and test in a non-prod cluster first — AKS can't be downgraded.
8. **Q:** How do you integrate monitoring?
**A.** `azurerm_monitor_workspace` (managed Prometheus) + `azurerm_monitor_data_collection_rule`/associations, `azurerm_log_analytics_workspace` for Container Insights and control-plane logs (`oms_agent`/`monitor_metrics` blocks or extensions), and diagnostics for API server/audit logs. Alerting on workload metrics then flows through Azure Monitor alert rules.

**🔍 Deep dive**
9. **Q:** Design a production AKS platform in Terraform for 10 teams.
**A.** Cluster with private API server (or IP-restricted), Azure CNI (with planned CIDRs) or kubenet overlay, managed identity + workload identity federation, 3 zones, system node pool (tainted, small) plus user pools by workload class (general/memory/spot with taints), cluster autoscaler bounds, Azure RBAC integration with Entra groups (namespace delegation via role assignments), managed Prometheus + Container Insights, Azure Policy for Kubernetes (or Gatekeeper) guardrails, maintenance windows, and a separate Terraform stage (or GitOps) for namespaces/quotas/network policies/ingress. Teams get namespace + quotas + RBAC through a GitOps PR; platform changes go through the Terraform pipeline with plan review.
**↳ Follow-up:** "How do you handle two Terraform stages (cluster then in-cluster resources)?"
**A.** The `azurerm_kubernetes_cluster` outputs (`kube_config`, `oidc_issuer_url`, `kubelet_identity`) feed a second root that configures the `kubernetes`/`helm` providers, creates namespaces/quotas/policies, and grants RBAC — with the CLI context or `kube_admin_config` (avoid storing admin kubeconfig in state where you can; prefer `kube_config` with Entra auth or a service-account-based token flow). Many teams use GitOps for the second stage to avoid two tools managing the same objects.
10. **Q:** How do you size AKS subnets and address space?
**A.** With Azure CNI, each node consumes a block of VNet IPs based on instance type/max pods, so subnet sizing must account for nodes × pods; alternatively use CNI overlay or (older) kubenet to conserve IPs. Plan `service_cidr`/`dns_service_ip` to not overlap VNet/on-prem ranges. Terraform should validate these inputs — resizing after the fact is painful.
11. **Q:** How do you manage node pool upgrades and rolling replacements in Terraform?
**A.** Change the pool's `orchestrator_version` (or enable automatic upgrades) with `upgrade_settings { max_surge }` (e.g. "33%") and `node_soak_duration`; Terraform coordinates the replacement, but the *workload* must tolerate drains (PDBs, multiple replicas, topology spread). For dedicated pools, do one pool at a time. Verify with `kubectl get nodes`/drain events and watch for PDB blocks.
12. **Q:** How do you handle secrets in AKS?
**A.** Prefer not storing secrets in Kubernetes: use workload identity/CSI Secrets Store driver to fetch from Key Vault at runtime (`azurerm_kubernetes_cluster` + the Secrets Store CSI add-on, with a `SecretProviderClass` in GitOps). If Kubernetes Secrets are necessary, enable etcd encryption with a Key Vault key (`key_vault_key_id` on the cluster) and restrict RBAC.
13. **Q:** How do you do ingress in Terraform for AKS?
**A.** Either Application Gateway Ingress Controller (AGIC, with Terraform managing the App Gateway and AGIC adding rules — beware two tools managing one object), an internal NGINX behind App Gateway, or Front Door → ingress. Terraform typically owns the App Gateway/Front Door and TLS (Key Vault), while ingress rules for apps live in GitOps; document the ownership boundary because conflicting ownership causes rule deletion.
14. **Q:** How do you implement node pool isolation for workloads (spot, GPU, memory-hungry)?
**A.** Separate `azurerm_kubernetes_cluster_node_pool` per class with labels/taints (`node_taints`, `node_labels`), matching tolerations/nodeSelectors in manifests, autoscaler bounds per pool, and (for spot) `priority = "Spot"` + eviction policy. Terraform defines the pools; the workloads' scheduling lives in GitOps — the contract is labels/taints, so name them consistently.
15. **Q:** How do you upgrade/rotate certificates and credentials?
**A.** AKS rotates cluster certificates automatically; `azurerm_kubernetes_cluster` supports `rotate_certificates` via `az aks rotate-certs` (Terraform exposes some rotation via recreate or targeted actions — generally done out-of-band with a follow-up to verify state). Service principal/managed identity credential rotation is automatic with managed identities. Document the process and verify access after rotation.
16. **Q:** How do you handle AKS cost in Terraform terms?
**A.** Node pool sizing and autoscaler bounds (min too high = idle spend), spot pools for interruptible work, correct VM SKUs (memory-heavy SKUs for memory workloads), cluster autoscaler/KEDA over-provisioning settings, managed Prometheus/Log Analytics ingestion volumes, and the Uptime SLA tier choice. Add budgets and use `azurerm_cost_management_export`/Kubecost-style tooling for attribution by namespace.

**🚨 War room**
17. **Q:** A node pool upgrade is stuck because pods won't drain.
**A.** PodDisruptionBudgets with zero-disruption budgets, single-replica deployments, or DaemonSets/standalone pods block eviction. Fix by relaxing PDBs/replica counts during the maintenance window (or running more replicas), then re-trigger the upgrade. Terraform's `upgrade_settings` (`max_surge`, `drain_timeout`) plus Kubernetes PDB design are both part of the answer.
18. **Q:** The API server is unreachable and CI can't deploy.
**A.** For private clusters, the path (VPN/jump host/runner) is broken; for IP-restricted public clusters, the CI egress IP changed. Check `api_server_access_profile`/authorized IP ranges and the private DNS zone link, and confirm with `az aks get-credentials` + a test. Then make the deployment path resilient (runner in the VNet or a stable egress IP with alerts on change).
19. **Q:** After an apply, workloads lost access to Key Vault/storage.
**A.** Workload identity changes: the federated identity credential, the service account annotation, or the role assignment scope. Check the pod's identity (the `azure.workload.identity/client-id` annotation), the federated credential's subject, and the role assignment — then fix and verify from inside a pod. This affects every workload using identity, so treat it as a high-severity config change.
20. **Q:** Nodes fail to join the cluster after a network change.
**A.** Subnet route table/NAT changes, NSG blocking the required AKS endpoints (or the pod/node CIDRs), or DNS resolution failures from the node subnet. AKS requires outbound access (or the right private endpoints) to the control plane and to Azure services — a hub-and-spoke change without AKS's endpoints will break node registration.
21. **Q:** Costs doubled after a node pool change.
**A.** Pool `min_count`/`max_count` raised (idle capacity at minimum), a new pool added for a test that wasn't removed, SKU changes, or a surge of spot evictions causing on-demand fallback. Use node pool metrics/Container Insights to see actual utilisation and reset the bounds; delete orphaned pools.
22. **Q:** A Terraform apply wants to recreate the cluster (e.g. a `name`/`network_profile` change).
**A.** Stop — cluster recreation means rebuilding all workloads. Identify the forcing attribute, then plan explicitly: build a new cluster alongside, migrate workloads (GitOps makes this feasible), move ingress/DNS, then delete the old. Some fields (like `dns_service_ip`/`network_plugin`) genuinely can't change in place — document them as immutable in the module and validate inputs to prevent accidental changes.

**⚖️ Trade-off**
23. **Q:** Azure CNI vs kubenet/overlay?
**A.** Azure CNI: pods get VNet IPs (direct integration, NSG/UDR visibility, more IP consumption); overlay/kubenet: pods are NAT'd (fewer VNet IPs, extra hop, less direct policy visibility). Large clusters/IP-constrained environments favour overlay; strict network policy/integration favours Azure CNI.
24. **Q:** Managed AKS vs self-managed Kubernetes?
**A.** Managed gives you control-plane patching/upgrades/SLA, identity/RBAC integration, and less operational burden; self-managed gives full control over the control plane (versions, add-ons, extensions) but you own upgrades, certificates, and etcd. Azure workloads overwhelmingly favour managed.
25. **Q:** Cluster autoscaler vs KEDA vs HPA?
**A.** HPA scales pods on metrics (CPU/memory/custom); KEDA scales on external events (queues/streams) and can scale to zero; cluster autoscaler adds/removes nodes to fit pending pods. Terraform owns node bounds; Kubernetes owns pod scaling — and the two must be aligned (avoid pods that can't schedule because max nodes is hit).
26. **Q:** Terraform vs GitOps for in-cluster resources?
**A.** Terraform for infra/cluster/pools/add-ons (slow-changing, Azure-side), GitOps for workloads/namespaces/policies/ingress rules (fast-changing, reviewed in PRs, drift-corrected continuously). Mixing them means two controllers fighting over the same objects — pick a boundary and document it.
27. **Q:** System pool + user pools vs a single pool?
**A.** System pools host critical add-ons (CoreDNS, metrics-server) — keep them separate, tainted, and modest so user workloads can't destabilise them; user pools sized by workload class. One pool is simpler but couples everything and makes upgrades riskier.
28. **Q:** Spot node pools — worth it?
**A.** Yes for interruptible/stateless workloads, with tolerations, PDBs, and graceful shutdown; and consider a mixed strategy (on-demand base + spot burst). Don't run single-replica or stateful services on spot unless you've tested the eviction path.
29. **Q:** Private cluster vs public API with IP restrictions?
**A.** Private is the stronger security posture (no public API server) at the cost of access plumbing for engineers/CI; IP-restricted public is a pragmatic middle ground (works with existing tooling, still limits exposure). Choose based on your access tooling maturity and compliance requirements.
30. **Q:** Managed Prometheus vs self-hosted?
**A.** Managed Prometheus (Azure Monitor managed service) offloads storage/scaling with Grafana integration and Azure-native alerts, at ingestion cost; self-hosted gives full control and portability but you own HA/storage/upgrades. For Azure-centric shops, managed is usually the pragmatic default.

**🎯 Senior**
31. **Q:** What does production-ready AKS look like in Terraform?
**A.** Private or IP-restricted API server with a documented access path; Azure RBAC with Entra groups and local accounts disabled; workload identity (federated credentials) for all Azure access; system pool separated and tainted with workload pools by class (zones, autoscaler bounds, spot for interruptible work); CNI/service CIDRs planned and validated against VNet/on-prem ranges; managed Prometheus + Container Insights with alarms and control-plane/audit logs; Azure Policy/Gatekeeper guardrails and network policies; etcd encryption with Key Vault keys; maintenance windows and a documented upgrade cadence; `prevent_destroy` on the cluster; and an explicit ownership boundary between Terraform (platform) and GitOps (workloads).

**🎯 Senior signal:** "cluster recreation means rebuilding everything — validate immutable fields", the two-stage/Terraform-vs-GitOps boundary, and workload identity federation replacing pod-managed identity. Those three mark real AKS platform ownership.
