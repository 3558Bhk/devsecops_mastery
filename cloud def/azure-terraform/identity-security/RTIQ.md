# RTIQ — Terraform Identity & Security on Azure (Real-Time Interview Questions)

> **Cloud:** Azure · **Tool:** Terraform · **Domain:** Entra ID/RBAC, Key Vault, managed identity, private access · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~23 min

**How this file is used live:** this is the round where security engineers separate operators from talkers. Expect to design the identity model for a pipeline, explain why a Key Vault is still a risk if the network is open, and walk through an incident where a secret leaked. Terraform is the vehicle; the questions are about least privilege and blast radius.

**Legend:** ⚡ Rapid · 🔍 Deep dive · 🚨 War room · ⚖️ Trade-off · 🎯 Senior signal

---

## 1. Identity, RBAC & Managed Identity — `identity-rbac.md`

**⚡ Rapid**
1. **Q:** Which providers manage identity on Azure, and what's the split?
**A.** `azurerm` for Azure resources and role assignments; `azuread` (or the newer `msgraphbeta`/Graph approach) for Entra ID objects — applications, service principals, groups, app role assignments, conditional access. Custom roles and their definitions are `azurerm_role_definition`.
2. **Q:** How does a pipeline authenticate without secrets?
**A.** Workload identity federation: an Entra application + service principal with a federated identity credential bound to the CI issuer/subject (`azuread_application_federated_identity_credential`), used from GitHub Actions/Azure DevOps/GitLab — no client secret stored anywhere.
3. **Q:** How do you scope a pipeline's permissions?
**A.** `azurerm_role_assignment` at the narrowest scope (resource group for workload pipelines, subscription only for the platform/landing-zone root), with built-in roles chosen deliberately (`Contributor` doesn't include RBAC; `Owner` adds `User Access Administrator`), plus deny assignments/PIM for elevation. Never `Owner` at tenant root for a workload pipeline.
4. **Q:** What's a managed identity, and how do you create one in Terraform?
**A.** An Azure-managed service principal with no credentials, attached to a resource: `azurerm_user_assigned_identity` (shared/reusable) or system-assigned (`identity {}` on the resource), then `azurerm_role_assignment` for its `principal_id`. Prefer user-assigned for determinism (identity survives resource recreation).
5. **Q:** Difference between `application_id`, `object_id`, and `principal_id`?
**A.** `application_id`/`client_id` identifies the app registration (used in config/tokens); `object_id` is the directory object ID of the app/SP/service principal (used for role assignments, admin objects, federated credentials); service principals and managed identities are referred to by `principal_id` in `azurerm_role_assignment`. Mixing them up is the #1 azuread/azurerm error.
6. **Q:** How do you assign RBAC to a group rather than individuals?
**A.** `azurerm_role_assignment` with `principal_id = azuread_group.<g>.object_id` — group-based access is the audit-friendly pattern (joiners/leavers managed by identity governance) and supports PIM eligibility for Azure resource roles.
7. **Q:** How do you manage PIM in Terraform?
**A.** PIM eligibility/schedule resources exist (`azurerm_pim_eligible_role_assignment`, and Entra PIM for roles via the azuread/graph providers), with `schedule` blocks (start/expiration) and justification policies. Many orgs manage PIM policy in the portal (free tier) — but eligibility should be code-reviewed, because it's a privilege grant.
8. **Q:** How do you restrict which locations/resources can be created?
**A.** Azure Policy (`azurerm_management_group_policy_assignment`/`subscription_policy_assignment`) with built-in definitions (allowed locations, allowed resource types, require tags, deny public IPs), assigned at the management-group level so it inherits. Policy is the guardrail that applies even when someone bypasses Terraform.
9. **Q:** What are the highest-privilege roles to keep out of pipelines?
**A.** `Owner`/`User Access Administrator` at subscription/management-group scope (they include RBAC changes, i.e. privilege escalation), `Contributor` at tenant root (almost never needed), and role-definition creation. If a pipeline needs to grant roles, scope it to a specific resource group and use a custom role with `Microsoft.Authorization/roleAssignments/write` limited by `condition`/ABAC where possible.
10. **Q:** How do you grant an app access to Key Vault with Terraform?
**A.** `azurerm_role_assignment` with `Key Vault Secrets User` (data-plane read) for the app's managed identity at the vault or secret scope; `azurerm_key_vault_access_policy` is the legacy model (vault-level, applies to all secrets). RBAC model is preferred and works with PIM/least privilege.

**🔍 Deep dive**
11. **Q:** Design the identity and governance model for a 3-tier landing zone (platform, shared services, workloads).
**A.** Break-glass accounts plus group-based administration; platform pipeline SP with federated credentials scoped to the platform subscription (`Contributor` + scoped `Role Based Access Control Administrator` on specific RGs); workload pipeline SPs scoped per environment RG; human access via Entra groups with PIM-eligible roles (Contributor on non-prod standing, Contributor on prod eligible-only with approval and MFA); application access exclusively through user-assigned managed identities with data-plane-only roles (no `Contributor`); Policy assignments at management groups enforcing tags/locations/public-access denials, with a documented exemption register; and all identity objects (apps, federated credentials, groups, role assignments, policy) in Terraform with plan review and drift detection.
**↳ Follow-up:** "What's the difference between Contributor and RBAC Administrator for your pipelines?"
**A.** `Contributor` can manage resources but not grant access — the pipeline can build infrastructure but can't escalate privileges. `RBAC Administrator` (or Owner) can assign roles — that's a privilege-escalation path, so grant it only where the pipeline genuinely manages access (e.g. the platform root creating role assignments), scoped narrowly and ideally with ABAC conditions.
12. **Q:** How do you avoid the Terraform "I need Owner" trap?
**A.** Identify the actual operations: role assignment creation (needs `User Access Administrator`/`RBAC Administrator` or a custom role limited to specific role GUIDs), resource moves, and policy assignments. Then either (a) split roots so only the identity root has RBAC rights, or (b) use a custom role that permits `roleAssignments/write` only for a fixed set of role definition IDs, or (c) let a separate, tightly approved pipeline handle assignments. Document the requirement rather than escalating the whole pipeline.
13. **Q:** How do you design federated credentials for multiple repos/environments?
**A.** One Entra application per repo/environment boundary (or one app with multiple federated credentials if the RBAC scope is identical), with `subject` claims restricted to a specific repo+branch/environment (e.g. `repo:org/repo:environment:prod`) and `audience` bounded to the CI's token audience. Then assign the RBAC at the scope matching the environment so a dev credential can't touch prod.
14. **Q:** How do you manage custom roles?
**A.** `azurerm_role_definition` with explicit `permissions { actions, not_actions, data_actions }` and assignable scopes; keep the number small (a role sprawl is unmanageable) and design them for delegation boundaries (e.g. "network operator" without subnet deletion). Test with a real principal that the role permits what's needed and denies what it should — and review the definitions on Azure API changes.
15. **Q:** How do you handle conditional access / MFA policy in IaC?
**A.** Conditional access policies can be managed with the `azuread`/Graph provider (`azuread_conditional_access_policy`), but changes are high-impact (they can lock everyone out). Pattern: manage the safe, standard policies in Terraform with plan review; test with report-only mode first; keep a break-glass account excluded from policies; and require out-of-band verification before enforcement.
16. **Q:** How do you audit who can do what?
**A.** Export role assignments (`az role assignment list`/Resource Graph queries) into reports, use Entra access reviews for group membership/PIM eligibility, and alert on new privileged role assignments/PIM activations (Activity Log/Entra signals → Sentinel/Log Analytics). Terraform-managed assignments give you a code-level audit too — but the runtime truth is the Azure API, so reconcile both.
17. **Q:** How do you handle secrets and certificates in Terraform on Azure?
**A.** Prefer no secrets (managed identity everywhere), else Key Vault as the store with `azurerm_key_vault_secret`/`azurerm_key_vault_certificate`, RBAC-scoped access, and no values in tfvars (generate with `random_password` where needed, mark sensitive). Rotation via Key Vault events/automation, and a documented process for the secrets Terraform itself must hold (e.g. SQL admin during bootstrap).
18. **Q:** How do you test an identity/RBAC change?
**A.** A sandbox subscription with the same structure: apply the role assignment, then use a real principal (or `az rest` with a token) to assert the permitted action succeeds and a forbidden action fails (403). Also review role scope creep via `az role assignment list --assignee` before merging, and add negative tests for the critical deny boundaries. RBAC changes are the highest-risk category to review by eye alone.

**🚨 War room**
19. **Q:** A leaked client secret was found in a repo. What's your sequence?
**A.** Revoke/rotate the credential immediately (remove the secret, add a federated credential), then assess the blast radius via Activity Log/Entra sign-in logs for that app (what did it do, from where?), rotate anything it could read (Key Vault secrets, storage keys, DB credentials), check for persistence (new role assignments, apps, credentials added by that identity), and only then remediate the repo (secret scanning, history rewrite/GitHub push protection). Report per policy; the exfiltration window matters more than the cleanup.
20. **Q:** Someone added themselves as Owner on production via the portal.
**A.** Remove the assignment, assess what they did (Activity Log), and review how it was possible (should only be via PIM with approval — if not, that's the control to fix). Then add alerting on privileged role assignments and periodic access reviews. This is a governance failure first, an access problem second.
21. **Q:** Terraform wants to delete a role assignment used by a running service.
**A.** Check whether the config removed it deliberately (a refactor merging assignments) or whether a data source/`for_each` key changed (causing a "delete+create" pattern that breaks access briefly). Restore, then fix the state/config so assignments aren't churned — role assignment churn in production is a common cause of transient 403s.
22. **Q:** Key Vault access broke for several apps after a migration from access policies to RBAC.
**A.** The vault's `enable_rbac_authorization` flip means old access policies no longer apply; the apps' identities need `Key Vault Secrets User` role assignments. Fix per app, verify with `az keyvault secret show` as the identity, and stage the migration (RBAC assignments first, then flip) rather than flipping in one apply.
23. **Q:** Policy is blocking deployments but Terraform shows no error until apply.
**A.** Policy evaluates at ARM request time, so the plan can look fine and the apply fails with a policy violation. Fix by testing in a sandbox with the same policies, surfacing violations in CI (a pre-apply ARM dry-run/`what-if` or a dedicated validate step), and giving the pipeline a read of Policy assignments/definitions so violations are caught earlier. Exemptions, if granted, should have expiry dates.
24. **Q:** A user-assigned identity was deleted and took access with it (shared across services).
**A.** User-assigned identities are a shared dependency — deleting one breaks every resource using it. Restore the identity (or recreate with the same name), recreate its role assignments and federated credentials, and then reconsider: either scope identities per workload (recommended) or protect the shared one with `prevent_destroy` plus alerts. Also verify which resources were affected via Activity Log.

**⚖️ Trade-off**
25. **Q:** System-assigned vs user-assigned managed identity?
**A.** System-assigned: lifecycle-bound to the resource (deleted with it), simple, unique per resource; user-assigned: created/managed separately, shareable, survives resource recreation, and lets you pre-assign permissions before deployment. For platform-managed workloads, user-assigned gives cleaner Terraform (identity created first, permissions assigned once).
26. **Q:** Group-based RBAC vs direct assignments to identities?
**A.** Groups for humans (audit-friendly, joiner/leaver automation, PIM eligible), direct assignments for service identities (managed identities don't need group membership; adding them to groups adds a layer without benefit). Keep humans in groups and machines directly assigned.
27. **Q:** Built-in roles vs custom roles?
**A.** Built-in roles are maintained and understood but coarse (and include unintended permissions like `Contributor`'s inability to grant access — sometimes a benefit, sometimes a problem); custom roles allow precise delegation at the cost of maintenance and testing. Use built-in where they match intent; custom only for genuine delegation boundaries.
28. **Q:** Terraform-managed RBAC vs Azure PIM/portal for privileged access?
**A.** Terraform for the durable structure (which groups hold which eligible/standing roles at which scope); PIM for the time-bound, approved activation of privileged roles. Managing standing access in Terraform is fine; managing *activations* there isn't practical — keep the two layers distinct.
29. **Q:** Workload identity federation vs client secrets for CI?
**A.** Federation: no secret to leak/rotate, subject-scoped to a repo/branch/environment, and no expiry management — the modern default. Client secrets: broader compatibility but long-lived credentials in a store, requiring rotation and monitoring. Only fall back to secrets when the CI platform can't do OIDC.
30. **Q:** Policy-as-guardrail vs pipeline-only enforcement?
**A.** Pipeline enforcement catches what goes through Terraform (plan-time, fast feedback) but not portal/CLI/script changes; Policy applies to the ARM API, so it covers everything at the cost of late failure (apply-time). Mature setups do both: plan-time policy-as-code for UX, Azure Policy as the platform backstop.
31. **Q:** One identity root for the whole tenant vs per-environment/team roots?
**A.** Per-environment/team roots with narrow scopes limit the blast radius of a compromised pipeline and keep plan times sane; a single identity root is simpler but means one pipeline credential can touch everything (and every root needs access to it). Strongly prefer scoped roots, with the tenant/management-group layer owned by a separate, highly controlled platform pipeline.

**🎯 Senior**
32. **Q:** What's your Azure identity standard in Terraform?
**A.** Zero standing secrets: workload identity federation for every pipeline, managed identities for every workload, no client secrets and no storage keys; human access only via Entra groups with PIM-eligible privileged roles on production; RBAC scoped to the narrowest resource (RG/container/secret) using built-in roles where possible; identity objects, federated credentials, role assignments, custom roles and Policy assignments all in Terraform with plan review and drift detection; alerting on privileged role assignment changes and PIM activations; periodic access reviews; `prevent_destroy` on shared identities; and a rehearsed break-glass path with its own credentials and monitoring.

**🎯 Senior signal:** "Contributor doesn't include RBAC, so the pipeline can't escalate itself", "the subject claim scopes federation to a repo and environment", and "Policy fires at ARM, so plan-clean isn't apply-clean". Those three are DevSecOps-grade answers on Azure.

---

## 2. Key Vault & Private Access — `key-vault.md`

**⚡ Rapid**
1. **Q:** Core Terraform resources for Key Vault?
**A.** `azurerm_key_vault` (with `sku_name`, `tenant_id`, `enable_rbac_authorization`, `purge_protection_enabled`, `soft_delete_retention_days`, `public_network_access_enabled`), `azurerm_private_endpoint` (+ `privatelink.vaultcore.azure.net` DNS zone), `azurerm_role_assignment` for `Key Vault Secrets Officer/User`, and resource-level `azurerm_key_vault_secret`/`_key`/`_certificate`.
2. **Q:** Which settings do you always set?
**A.** `purge_protection_enabled = true` (prevents permanent deletion of secrets even after soft delete), `soft_delete_retention_days` 7–90, `enable_rbac_authorization = true`, `public_network_access_enabled = false`, `network_acls` default action deny (if not fully private), and `min_tls_version = "TLS1_2"`. Backups matter too — purge protection plus backups is the pair people forget.
3. **Q:** What are the Key Vault naming rules?
**A.** 3–24 characters, alphanumerics and hyphens, globally unique, must start with a letter, must end with a letter or digit, and no consecutive hyphens — plus the `-` only rule set means your naming module needs a Key Vault-specific variant.
4. **Q:** Access policies vs RBAC for Key Vault?
**A.** RBAC (`enable_rbac_authorization = true`) uses standard Azure roles scoped to vault/secret and supports PIM/ABAC/audit — the current default. Access policies (`azurerm_key_vault_access_policy`) are the legacy vault-wide model; migrating requires assigning roles before flipping the flag, or apps lose access.
5. **Q:** How do you give an app a secret?
**A.** `azurerm_role_assignment` granting `Key Vault Secrets User` at the vault or secret scope to the app's managed identity, and the app fetches at runtime (SDK or Key Vault reference). No secret in env vars, no secret in Terraform state.
6. **Q:** How do you handle certificates (including App Gateway/Front Door)?
**A.** `azurerm_key_vault_certificate` (with a Key Vault-integrated CA or imported PFX) and consumers referencing `key_vault_secret_id` versionless, with their managed identity granted `Key Vault Secrets User`. Renewals then propagate automatically rather than requiring a Terraform change.
7. **Q:** What does purge protection actually prevent?
**A.** Permanent (purge) deletion during the soft-delete retention window — including by an attacker with delete rights. With it enabled plus backups, ransomware/careless deletion can't fully destroy secrets. Once enabled, it can't be disabled (and it makes a vault undeletable until retention expires, which matters for test cleanup).
8. **Q:** Why disable public network access?
**A.** Without a private endpoint and with public access enabled, the vault is reachable from anywhere (protected only by auth), which broadens the attack surface and often fails audit. Private endpoint + DNS zone (with `public_network_access_enabled = false`) means only the VNet path works — including for your pipelines, which must then be in the VNet or use a service-endpoint/allow-listed path.
9. **Q:** How do you allow a whitelisted set of networks instead of fully private?
**A.** `network_acls { default_action = "Deny", bypass = "AzureServices", ip_rules = [...], virtual_network_subnet_ids = [...] }` — note `bypass = "AzureServices"` allows trusted Azure services (backup, ARM) and is often required. This is the pragmatic middle ground but leaves a public endpoint.

**🔍 Deep dive**
10. **Q:** Design the Key Vault architecture for an enterprise platform in Terraform.
**A.** One vault per environment+workload (or a small number of shared platform vaults for CA/keys with strict RBAC), RBAC authorization on, purge protection on, soft delete 90 days, private endpoint from the hub with DNS zones linked to all spoke VNets (via Azure Policy `deployIfNotExists` for the link where possible), firewall default-deny with `bypass = AzureServices`, CMK keys for storage/SQL in dedicated vaults, separate vaults for certificates (with CA integration) and for app secrets, diagnostic logs to a central workspace with alerts on any deny/permission change, secret expiry alerts, and automated rotation where supported. Access: Secrets User for apps (secret-scoped where the platform supports it), Secrets Officer only for the platform pipeline, humans via PIM-eligible roles with justification.
**↳ Follow-up:** "A vault is compromised — how bad is it and what do you do?"
**A.** Assess what it held: TLS certificates (interception risk), CMK keys (crypto-shredding risk and the ability to decrypt/disable), DB connection strings, third-party API keys. Sequence: check diagnostic logs for reads/deletes, revoke/rotate everything readable, rotate CMK keys (re-wrap) if keys were accessed, reissue certificates, and verify no new role assignments/purge attempts. Purge protection + backups are what make this survivable — say that.
11. **Q:** How do you manage secret rotation end to end?
**A.** Prefer identity/keyless (nothing to rotate). Where secrets exist: Key Vault holds the value with a rotation policy where supported (storage account keys via Key Vault's managed rotation, some SQL/CA integrations), Event Grid notifications on near-expiry/rotation, consumers that re-read the secret rather than caching forever, and a dual-credential pattern for credentials that must be swapped (old+new valid during overlap). Terraform should manage the *configuration* (vault, rotation policy, who can read), not hold the value.
12. **Q:** How do you handle secrets Terraform itself needs (bootstrap)?
**A.** Generate with `random_password` at creation, write to Key Vault, and reference from consumers — accepting that the value is in Terraform state (so the state backend must be private/encrypted/RBAC-controlled). Better: keep bootstrap values out of state by creating them out-of-band (documented) or in a separate bootstrap root whose state is extra-protected. Be explicit about this residual risk instead of pretending it doesn't exist.
13. **Q:** How do you make Key Vault work for pipelines?
**A.** Pipeline identity (federated SP) granted `Key Vault Secrets User` at the vault, with private access via a runner in the VNet (or an allow-listed IP/network path). Avoid `Secrets Officer` for deployment pipelines — that's for the platform root managing secrets. If a pipeline needs to write a secret, that's a signal the value should be created out-of-band or by the app.
14. **Q:** How do you do BYOK/CMK for storage and SQL?
**A.** Create the key in a vault (`azurerm_key_vault_key` with RSA 2048/3072, `key_opts` for wrap/unwrap), grant the resource's identity `Key Vault Crypto Service Encryption User`, and reference the key from `azurerm_storage_account_customer_managed_key` / `azurerm_mssql_server_transparent_data_encryption`. Consider a dedicated vault with purge protection and a rotation policy; never disable the key, because that makes the data unavailable.
15. **Q:** How do you handle private endpoints for Key Vault from many VNets?
**A.** One private endpoint per vault (in the hub or a central networking subscription) with the private DNS zone (`privatelink.vaultcore.azure.net`) linked to every VNet that needs resolution — or one endpoint per VNet if private DNS linking isn't acceptable. The usual failure is a new spoke VNet without the zone link: apps get a public IP and are denied. Automate the link (Policy `deployIfNotExists` or a networking module) so onboarding a VNet includes DNS.
16. **Q:** How do you monitor and alert on Key Vault?
**A.** `azurerm_monitor_diagnostic_setting` to Log Analytics for `AuditEvent` (all access), alerts on denied requests, on `SecretNearExpiry`/`CertificateNearExpiry` events (Event Grid → alert), on purge/delete attempts, and on permission changes (Activity Log). Then a dashboard of near-expiry certificates/secrets so renewals are proactive — expiry is the most common Key Vault incident.
17. **Q:** How do you handle Key Vault for multi-region apps?
**A.** Vaults are regional: either one vault per region (with the app reading its regional vault), or a single vault with private endpoints in both regions (higher latency across regions) — plus certificate/key replication considerations. For certificates used by regional ingress (App Gateway per region), per-region vaults with the same certificate material is usually cleanest.
18. **Q:** What does a Key Vault test look like?
**A.** Negative tests: a service identity can read its secret and gets 403 for another vault/secret; a public-network/off-VNet client fails to connect; a purge attempt is rejected by purge protection; and diagnostics show the access. Wire at least the 403 test into the pipeline so an RBAC refactor can't silently over-grant.

**🚨 War room**
19. **Q:** Every app fails with "The operation is not permitted" against Key Vault. Where do you look?
**A.** Order: (1) the vault's `enable_rbac_authorization` state vs whether apps use roles (access policies ignored after the flip), (2) the identity's role assignment (was it removed/churned by an apply?), (3) private endpoint/DNS (a new VNet without a zone link, or DNS pointing at the public IP), (4) `network_acls`/firewall changes blocking the app subnet. That order matches the frequency of causes in real incidents.
20. **Q:** A secret used by production was deleted (soft delete).
**A.** Recover it (`az keyvault secret recover` — possible within the soft-delete window) or from a backup if purged; then check who deleted it and why (diagnostics), and whether Terraform did it (a removed resource in config). Prevent: purge protection on, secrets managed in code with review, and `prevent_destroy` where appropriate. Purged secrets are unrecoverable — that's the point to make.
21. **Q:** A certificate expired and the customer-facing endpoint broke.
**A.** Reissue/renew and re-bind (Key Vault + gateway/app reference), then fix the process: expiry alerts at 30/14/7 days via Event Grid, versionless references so renewals propagate automatically, and a synthetic TLS check. Most cert incidents are monitoring failures, not technical ones.
22. **Q:** Key Vault was made public by a config change.
**A.** Revert (`public_network_access_enabled = false` / `network_acls` deny), then audit diagnostic logs for access from unexpected networks during the window, and rotate anything plausibly exposed if the window was long or the vault held high-value material. Add a CI policy check that fails plans enabling public access on vaults, plus a Policy assignment as the platform backstop.
23. **Q:** A pipeline was granted `Key Vault Secrets Officer` "just to deploy".
**A.** Reduce to `Secrets User` (read) — deployment doesn't need write — and split secret creation into the platform root. Then review who can write secrets generally: write access to a vault is equivalent to controlling every consumer, so it must be tightly held and alerted on.
24. **Q:** Someone deleted the vault's CMK key (or disabled it) and storage/SQL stopped working.
**A.** Recover the key (soft delete recover) or re-enable it, then verify the resource reconnects (may need a retry). Then enforce: purge protection, key rotation policies that never leave the vault without a usable key version (`azurerm_key_vault_key` with rotation policy and `not_before`/`expiration` handled), and alerts on key disable/delete events. This is the crypto-shredding failure mode in reverse — it takes the data offline.
25. **Q:** A new spoke VNet can't resolve the vault, and only that team is affected.
**A.** Missing private DNS zone VNet link for that spoke. Fix the link, then automate: a networking module or Policy `deployIfNotExists` that links the standard private DNS zones to every new VNet, plus a connectivity test in the VNet's onboarding pipeline. Onboarding gaps like this recur without automation.

**⚖️ Trade-off**
26. **Q:** One shared Key Vault vs per-workload vaults?
**A.** Per workload/environment: bounded blast radius, independent RBAC and rotation, and a leaked secret affects one workload; shared: fewer objects but a single compromise exposes everything and RBAC gets coarse. Prefer per workload; share only for platform material (CA, CMKs) with strict, alerted access.
27. **Q:** RBAC vs access policies (current state of practice)?
**A.** RBAC is the modern model with PIM/ABAC/audit and is the direction Azure pushes; access policies remain for legacy apps and templates. New vaults should use RBAC — but plan the migration (assign roles first, then flip) since apps break if you flip without assignments.
28. **Q:** Fully private (public access disabled) vs firewall with allowed networks?
**A.** Fully private is the strongest posture but requires every consumer (including pipelines and jump hosts) to be in/through the VNet; firewall allow-lists are pragmatic when you have on-prem or unmanaged consumers, at the cost of a public endpoint. Choose by consumer inventory — then document and monitor what's allowed.
29. **Q:** Secrets in Key Vault vs Key Vault references in app settings?
**A.** Both end up in Key Vault; the difference is how the app reads it. Key Vault references in app settings (App Service/Functions) are convenient and require less code, but the app may cache and you lose per-request control; SDK reads give you control over caching/refresh and are needed for rotation without restarts. Prefer SDK/token-based reads where rotation latency matters, and say why.
30. **Q:** Managed HSM vs standard Key Vault?
**A.** Managed HSM gives single-tenant, FIPS 140-2 Level 3 key custody with full control over keys (required by some compliance regimes) at much higher cost and operational complexity; standard Key Vault is multi-tenant, cheaper, and sufficient for most workloads. Choose by compliance and key-custody requirements, not by preference.
31. **Q:** Terraform-managed secrets vs out-of-band creation?
**A.** Terraform-managed secrets land in state (and in plan artifacts if mishandled) — acceptable only with a hardened backend; out-of-band creation (portal/CLI/pipeline outside Terraform) keeps values out of state but loses declarative management of metadata (rotation policy, access). Common compromise: Terraform manages vault, access, and rotation policy; the secret values are written by a controlled process (or generated where no human needs them).

**🎯 Senior**
32. **Q:** What's your Key Vault standard in Terraform?
**A.** Per-workload/environment vaults with RBAC-only access and purge protection on; soft delete at 90 days; private endpoints with private DNS zones linked to every consumer VNet (automated via a module/Policy); firewall default-deny with `bypass = AzureServices`; versionless secret/certificate references from consumers; managed identities with `Secrets User` (never Officer for deployment pipelines); CMKs in dedicated vaults with rotation policies and alerts on disable/delete; diagnostics to a central workspace with alerts on denies, deletes, and permission changes; expiry alerting at 30/14/7 days; `prevent_destroy` on platform vaults and CMK keys; and CI checks that fail plans enabling public access or disabling purge protection.

**🎯 Senior signal:** "purge protection is what makes a vault incident survivable", "write access to a vault equals control of every consumer", and staging the access-policy→RBAC migration (assign roles, then flip). Those three are the marks of someone who has run Key Vault in production.
