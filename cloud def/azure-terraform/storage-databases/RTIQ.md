# RTIQ — Terraform Storage & Databases on Azure (Real-Time Interview Questions)

> **Cloud:** Azure · **Tool:** Terraform · **Domain:** Storage accounts, Azure SQL / Cosmos DB · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~20 min

**How this file is used live:** data-layer Terraform rounds test whether you respect irreversibility. Interviewers ask what you'd protect with `prevent_destroy`, how you keep credentials out of state, and what happens when a plan wants to recreate a database. Azure-specific traps (globally unique names, irreversible changes, private endpoint DNS) are the differentiators.

**Legend:** ⚡ Rapid · 🔍 Deep dive · 🚨 War room · ⚖️ Trade-off · 🎯 Senior signal

---

## 1. Storage Accounts — `storage-accounts.md`

**⚡ Rapid**
1. **Q:** How many Terraform resources does a secure storage account need?
**A.** Around eight to ten: `azurerm_storage_account`, `azurerm_storage_container`(s), `azurerm_storage_account_network_rules` (or `network_rules` block), `azurerm_private_endpoint` + private DNS, `azurerm_storage_management_policy` (lifecycle), `azurerm_monitor_diagnostic_setting`, role assignments (`azurerm_role_assignment` for `Storage Blob Data Reader/Contributor`), and optionally `azurerm_storage_account_customer_managed_key`.
2. **Q:** What must you set for security?
**A.** `min_tls_version = "TLS1_2"`, `https_traffic_only_enabled = true` (or `enable_https_traffic_only = true` in older versions), `allow_nested_items_to_be_public = false`, `public_network_access_enabled = false` (when using private endpoints), `shared_access_key_enabled = false` where possible, and infrastructure encryption (`infrastructure_encryption_enabled`) for stricter compliance.
3. **Q:** What are the naming constraints?
**A.** 3–24 characters, lowercase letters and numbers only, globally unique — the source of most `random_string` usage in Azure Terraform. Changing the name forces account recreation (data loss), so the suffix must persist in state.
4. **Q:** How do you do redundancy?
**A.** `account_replication_type` = `LRS`, `ZRS`, `GRS`, `RAGRS`, `GZRS`, `RAGZRS` — plus `account_tier = "Standard"`/`"Premium"` and (for premium) `account_kind`. ZRS for zone resilience, GRS/GZRS for regional DR; each step costs more, so match it to the RPO commitment.
5. **Q:** How do containers and lifecycle rules work in Terraform?
**A.** `azurerm_storage_container` per container (with `container_access_type = "private"` always), and `azurerm_storage_management_policy` with rules for tiering (`base_blob.tier_to_cool_after_days_since_modification_greater_than` etc.), deletion, and `delete_after_days_since_last_access_time_greater_than` (last-access tracking must be enabled on the account).
6. **Q:** How do you grant an app access?
**A.** A managed identity + `azurerm_role_assignment` for `Storage Blob Data Reader/Contributor/Owner` scoped to the container (not the account), with `shared_access_key_enabled = false` to remove key-based access entirely. Then the app authenticates with identity — nothing in config.
7. **Q:** How do you create a private endpoint for storage?
**A.** `azurerm_private_endpoint` with a `private_service_connection` to the `blob` sub-resource (one endpoint per sub-resource: blob, file, queue, table, dfs), plus `azurerm_private_dns_zone` (`privatelink.blob.core.windows.net`) linked to the VNet and a `private_dns_zone_group` on the endpoint. Separate zones per sub-resource.
8. **Q:** How do you do CMK encryption?
**A.** `azurerm_storage_account_customer_managed_key` referencing a Key Vault key, with the storage account's identity granted access (or the key vault's firewall permitting the trusted service). Note: enabling CMK later is possible, but changing the key requires the account's identity to have permissions on the new key.
9. **Q:** What happens when you change the account's replication type?
**A.** Some transitions are allowed in place (LRS→GRS, etc.), some aren't (Premium kinds have restrictions), and each may trigger a long-running operation. Terraform handles it, but verify the plan and schedule it — replication changes are data-plane operations with time/cost implications.

**🔍 Deep dive**
10. **Q:** Design the storage layer for a multi-tenant data platform (Terraform shape).
**A.** One storage account (or a few by grouping) per region/environment with `shared_access_key_enabled = false`, `public_network_access_enabled = false`, private endpoints per sub-resource with DNS zones linked to each tenant's VNet, containers per data domain with lifecycle policies (cool/cold/archive by access), versioning/soft delete enabled, CMK via Key Vault, diagnostic logs to a central workspace, and role assignments scoped per container (or per prefix via ABAC conditions where supported). For tenant isolation, containers (or accounts) per tenant with scoped role assignments, and for regulated tenants per-tenant CMK. Terraform module takes a `containers` map and a `role_assignments` map.
**↳ Follow-up:** "How do you prove tenant isolation?"
**A.** Show scoped role assignments (container-level), a private DNS/network path that doesn't expose the account publicly, diagnostic logs of access by principal, and an automated negative test (a synthetic identity from tenant A getting a 403 for tenant B's container) run in the pipeline. Evidence plus negative tests is what auditors accept.
11. **Q:** How do you handle tables/queues/files in Terraform?
**A.** Sub-resources need their own private endpoints and DNS zones (`privatelink.queue.core.windows.net`, `.file.`, `.table.`), their own role assignments (`Storage Queue Data Contributor`, `Storage File Data SMB Share Contributor`), and — for Files — share-level quotas and identity-based access. Terraform manages shares/queues/tables as separate resources; don't assume the blob endpoint covers them.
12. **Q:** How do you handle lifecycle policies safely?
**A.** Start in a non-prod account with last-access tracking enabled, verify the policy's behaviour with a small container, and then apply to production — because a wrong policy can archive active data or delete versions. Also include `delete_after_days_since_creation` for noncurrent versions and a rule for days-since-last-access where supported. Cost savings are real, but so is the risk of over-aggressive rules; test them.
13. **Q:** How do you do versioning and point-in-time restore?
**A.** Blob versioning (`blob_properties { versioning_enabled = true }`), soft delete for blobs/containers (`delete_retention_policy`/`container_delete_retention_policy`), and point-in-time restore (`restore_policy`) — plus change feed where needed. Watch for the cost of accumulating versions: lifecycle rules on noncurrent versions are mandatory.
14. **Q:** How do you handle static website hosting?
**A.** Enable `static_website` on the account (public access required for the website endpoint) *or* — preferred — keep the account private and serve via a CDN (Front Door/Azure CDN) with the origin being the web endpoint. Modern designs use Front Door; note that `allow_nested_items_to_be_public` must be enabled for the classic website endpoint, which is a security smell for many orgs.
15. **Q:** How do you handle storage account keys if you must use them (legacy apps)?
**A.** Store them in Key Vault (`azurerm_key_vault_secret`) and reference from the app, rotate via Key Vault with a dual-key strategy, and keep `shared_access_key_enabled = true` only where required with a documented exception. Rotating keys: regenerate the unused key, update Key Vault, verify, then rotate the other. Explicitly mark this as debt to be removed by moving apps to identity.
16. **Q:** How do you do cross-region replication/DR for storage?
**A.** GRS/GZRS at the account level (async replication, RPO minutes) plus (for Blob) object replication (`azurerm_storage_account` `blob_properties`/`azurerm_storage_object_replication`) for control over which containers replicate and to a different account/region — the latter also supports different retention/immutability policies in the destination, which is the ransomware-resilient pattern. Test a restore from the secondary.

**🚨 War room**
17. **Q:** A plan wants to replace the storage account (name/suffix change). What now?
**A.** Stop — replacement means a new account and data loss. Investigate why: a regenerated `random_string` (because it was computed in a `local` rather than a resource), a name convention change, or a kind/SKU change. Fix the config to keep the same name, or (if the change is genuinely required) migrate: create the new account, copy data (AzCopy/object replication), update consumers, cut over, then delete the old after a soak with `prevent_destroy` on the new one.
18. **Q:** An apply enabled versioning but no lifecycle policy, and the bill jumped.
**A.** Expected: every overwrite retains a version. Add `azurerm_storage_management_policy` rules to delete noncurrent versions after N days (and snapshots), and set a sensible retention based on the recovery requirement. This is the most common storage cost surprise in Azure.
19. **Q:** After enabling `public_network_access_enabled = false`, apps broke.
**A.** They were using the public endpoint (and probably storage keys). Fix by adding a private endpoint + DNS zone for the VNet, moving the app to managed identity + RBAC, and verifying DNS resolution from inside the VNet. A firewall/`network_rules` allow-list for specific VNets/IPs is the intermediate path but leaves the public endpoint in place.
20. **Q:** Lifecycle policy archived data that users still need daily.
**A.** Restore what's needed (rehydration from archive takes hours and costs), then revise the policy: use last-access-based rules rather than age alone, exclude active containers/prefixes, and test changes on a subset first. Add monitoring on archive rehydrations (anomalies indicate a policy mismatch).
21. **Q:** Diagnostic logs show anonymous reads on a container.
**A.** Something is public: check container access level (`container_access_type`), the account's `allow_nested_items_to_be_public`, and any SAS with broad scope. Fix immediately (set the container private, disable public access at the account level), assess what was exposed, and add Policy/CI checks so public access can't be enabled again (and alerts on access-level changes).
22. **Q:** Storage costs doubled without a traffic change.
**A.** Check: noncurrent versions/snapshots accumulating, tier changes triggering early-deletion charges, transaction volume (chatty listings/polling), cross-region replication data transfer (GRS/RA-GRS reads), and data leaving via a secondary region. Use Cost Management breakdown by meter and the storage insights workbook, then apply lifecycle rules and fix the chatty pattern.
23. **Q:** Private endpoint DNS stopped resolving after a network change.
**A.** The private DNS zone link was removed, or a new VNet wasn't linked, or (classically) two teams created zones with the same name so resolution split. Re-link the correct central zone, remove duplicates, and add a post-change connectivity test for storage/DNS in the pipeline so it's caught automatically.

**⚖️ Trade-off**
24. **Q:** One storage account per workload vs a shared account?
**A.** Per workload/environment: clean RBAC boundaries, independent lifecycle/CMK, and bounded blast radius — at the cost of more accounts (and more private endpoints/DNS entries) to manage. Shared accounts: fewer resources but entangled permissions and a bigger blast radius. Default to per workload, automate with a module.
25. **Q:** LRS vs ZRS vs GRS/GZRS?
**A.** LRS is cheapest (single-region, three copies in one DC), ZRS survives a zone outage in-region (usually the best price/resilience point), GRS/GZRS adds a secondary region with async replication (for DR/RPO commitments) at higher cost and with restore-from-secondary caveats. Match to the business RPO/RTO, not to habit.
26. **Q:** Shared key access vs Entra ID RBAC?
**A.** RBAC (with `shared_access_key_enabled = false`) removes long-lived secrets, gives per-identity scoping/audit, and supports PIM — the modern default. Shared keys are legacy (full account access, no accountability per request), so keep them only for components that genuinely can't do identity, and rotate them through Key Vault.
27. **Q:** Terraform-managed CMK vs Microsoft-managed keys?
**A.** Customer-managed keys give you control (rotation, revocation — which also enables crypto-shredding) and often satisfy compliance, at the cost of Key Vault/key management, dependencies (the account can't decrypt if the key is unavailable/revoked), and operational care. Microsoft-managed keys are zero-effort but you don't control them.
28. **Q:** Cool/archive tiering via lifecycle vs leaving data hot?
**A.** Tiering saves significant cost for cold data but introduces retrieval charges/latency (archive rehydration takes hours) and early-deletion penalties; leaving everything hot is simple but expensive at scale. Use last-access-driven rules with a tested restore path — and document the retrieval SLA where archive is used for compliance data.
29. **Q:** Object replication vs account-level GRS?
**A.** GRS is account-wide async replication in a paired region (simple, coarse, and the secondary isn't writable); object replication is per-container/rule, can target a different account/subscription with different immutability/retention settings, and is the better fit for DR plus ransomware resilience (a locked destination). Many designs use both.
30. **Q:** Should Terraform manage individual blobs?
**A.** No — content belongs to the app pipeline (AzCopy/CLI/`s3`-equivalent uploads), not to Terraform state. Manage containers, policies, permissions, and lifecycle with Terraform; manage objects with the deploy pipeline. Managing blobs individually bloats state and couples content releases to infra.

**🎯 Senior**
31. **Q:** What does a production storage module look like in your repo?
**A.** Globally unique naming with a persisted `random_string`; `min_tls_version = TLS1_2`, HTTPS-only, public access disabled, `shared_access_key_enabled = false`; ZRS (or GZRS for DR-tier data); private endpoints per sub-resource with central DNS zone links; versioning + soft delete + a management policy that expires noncurrent versions; optional CMK with Key Vault; container-level RBAC assignments from an input map; diagnostic settings to a central workspace with alerts on anonymous access and mass deletes; Microsoft Defender for Storage enabled; `prevent_destroy` where data lives; and a CI policy check that fails any plan enabling public access or TLS < 1.2.

**🎯 Senior signal:** "versioning without lifecycle is a cost bomb", "shared_access_key_enabled = false and container-scoped RBAC", and object replication into a locked destination for ransomware resilience. Those three are storage maturity.

---

## 2. Databases — `databases.md`

**⚡ Rapid**
1. **Q:** Core Terraform resources for Azure SQL?
**A.** `azurerm_mssql_server` (with `azuread_administrator`), `azurerm_mssql_database` (SKU, collation, zone redundancy, short/long-term retention), `azurerm_mssql_firewall_rule` and `azurerm_mssql_virtual_network_rule` for network access, `azurerm_private_endpoint` for private connectivity, and `azurerm_mssql_server_security_alert_policy`/auditing resources.
2. **Q:** How do you avoid the admin password in state?
**A.** Prefer Entra ID-only auth (`azuread_administrator` with `login_username`/`object_id` and `azuread_authentication_only = true` on the server) so no SQL admin password exists. If SQL auth is required, generate with `random_password`, store in Key Vault, and mark sensitive (it *will* be in state — so protect the backend).
3. **Q:** How do you make Azure SQL highly available?
**A.** Zone redundancy where available (`zone_redundant = true` on the database in supported tiers), plus the platform's built-in HA (each tier has a standby) and auto-failover groups (`azurerm_mssql_failover_group`) for cross-region DR with listener endpoints. Note Business Critical/Hyperscale give local replicas and lower latency.
4. **Q:** How do you configure backups?
**A.** `short_term_retention_policy` (PITR, 7–35 days) and `long_term_retention_policy` (weekly/monthly/yearly to Blob for compliance), both as blocks on `azurerm_mssql_database`. Test restores — LTR retention is only useful if you can restore from it.
5. **Q:** What about elastic pools?
**A.** `azurerm_mssql_elasticpool` (with a SKU and per-database `max_size_gb`/capacity settings) and databases assigned via `elastic_pool_id` — the cost-efficient pattern for many small/variable databases (SaaS multi-tenant). Watch pool-level metrics for noisy neighbours.
6. **Q:** Core Terraform for Cosmos DB?
**A.** `azurerm_cosmosdb_account` (API kind, consistency, geo locations, capabilities, backup policy), `azurerm_cosmosdb_sql_database`, `azurerm_cosmosdb_sql_container` (partition key, throughput or autoscale, indexing policy), plus role assignments for data-plane access. Gremlin/Mongo/Cassandra/Table APIs use their own container/table resources.
7. **Q:** What's irreversible in Cosmos DB Terraform?
**A.** The partition key (changing it means a new container + migration), the API kind (account recreation), and the account name/location set. Get the partition key and consistency level right up front — these are design decisions, not settings.
8. **Q:** How do you control Cosmos throughput in Terraform?
**A.** `throughput` (manual RU/s) or `autoscale_settings { max_throughput }` at the database or container level, with alerts on RU consumption and throttling (429s). Shared database throughput is the cost-efficient pattern for many small containers.

**🔍 Deep dive**
9. **Q:** Design the database layer for a multi-tenant SaaS in Terraform (Azure SQL).
**A.** A single `azurerm_mssql_server` (Entra-only admin, private endpoint, no public access, TLS enforced, auditing + Defender enabled) with an elastic pool sized from aggregate DTU/vCore demand; databases per tenant (or per shard) created via a module with per-DB max size and PITR/LTR retention; tenant→database mapping held in a control-plane database or config; role assignments granting the app's managed identity access (contained database users created by a migration/onboarding step); geo-redundant backup/failover group for DR; and monitoring on pool utilisation, DTU/vCore %, storage, and failed connections. Onboarding a tenant = a pipeline run, not a manual portal task.
**↳ Follow-up:** "How do you onboard tenant 500 without touching Terraform for each one?"
**A.** Two patterns: (1) `for_each` over a tenants map in Terraform (fine to a few hundred, with plan time growing and state bloat), or (2) an application/onboarding service that executes a scripted provisioner (ARM/Bicep templates or T-SQL `CREATE DATABASE` against the pool) and records the mapping — Terraform manages the pool/server and the standard, while per-tenant elasticity is handled by the app. Choose based on scale; describe the trade-off explicitly.
10. **Q:** How do you do zero-downtime schema migrations with Terraform in the picture?
**A.** Terraform doesn't do schema: use a migration tool (Flyway/EF/DACPAC/`sqlpackage`) in the app pipeline with backward-compatible, expand/contract migrations, and keep Terraform to infrastructure and users/roles. Deploy migrations separately from app code, with feature flags for the switch and a tested rollback.
11. **Q:** How do you connect an app to Azure SQL privately?
**A.** `azurerm_private_endpoint` for the SQL server (`privatelink.database.windows.net`) + DNS zone linked to the app's VNet (or the hub), `public_network_access_enabled = false` (or firewall rules denying public if private-only isn't possible yet), and the app's managed identity as a contained database user. Verify from the app's subnet with a DNS/connection test — private endpoints without DNS are the most common failure.
12. **Q:** How do you secure Azure SQL end-to-end in Terraform?
**A.** Entra-only authentication (`azuread_authentication_only = true`), managed identity access via contained users, TDE with a customer-managed key (`azurerm_mssql_server_transparent_data_encryption` + Key Vault), auditing to a storage account/Log Analytics (`azurerm_mssql_server_extended_auditing_policy`), Defender/security alert policy, vulnerability assessment, private endpoint, and no public firewall rules. Add `minimum_tls_version` where configurable.
13. **Q:** How do you handle Cosmos DB multi-region and consistency?
**A.** `geo_location` blocks per region with `failover_priority` and `zone_redundant`; `consistency_policy` per account (Strong/BoundedStaleness/Session/ConsistentPrefix/Eventual) — Session is the common default; multi-master via `enable_multiple_write_locations` with a conflict resolution policy. Terraform changes here can be long-running and regionally impactful, so review plans carefully.
14. **Q:** How do you do Cosmos backups and DR?
**A.** `backup { type = "Continuous" }` (or periodic) with tiers (7/30 days) and `restore` performed out-of-band (Terraform doesn't restore data); multi-region writes/reads provide availability, but backup/PITR covers corruption/deletion. Document the restore procedure (create a new account/container from the restore, then migrate) — it's not a one-click in-place restore in Terraform.
15. **Q:** How do you manage index policies and partition keys in Terraform?
**A.** `azurerm_cosmosdb_sql_container` with `partition_key_path` (or `partition_key_paths` for hierarchical) and an `indexing_policy` block — start from the default (index everything) and exclude unused paths to cut write RU cost; changing index policies can be applied in place, but partition keys cannot. Validate the partition key choice with realistic queries before creating the container.
16. **Q:** How do you handle non-SQL Cosmos APIs and other Azure databases?
**A.** API-specific resources: `azurerm_cosmosdb_mongo_database`/`mongo_collection`, `cassandra_keyspace/table`, `gremlin_database/graph`, `sql_database/sql_container`, `table`; and for PaaS OSS databases `azurerm_postgresql_flexible_server`/`mysql_flexible_server` with their configuration, firewall/private endpoint, and backup settings. The same principles apply: private networking, identity-based auth where available, PITR/backups configured and tested, and irreversible design choices (version, region, storage) reviewed before apply.

**🚨 War room**
17. **Q:** A plan wants to recreate the Azure SQL server (name/region change). Stop.
**A.** A SQL server rename has no in-place path (the server name is the DNS endpoint) — so this is a migration: create the new server with the desired name/config, restore databases (or geo-replicate and fail over), update all connection strings (or use a failover-group listener/DNS alias), verify, then delete the old server after a soak. In Terraform terms: new resources, a cutover step, then removal — never a single apply.
18. **Q:** The Cosmos container was recreated with a new partition key and data is gone.
**A.** Restore from continuous backup (to a new container/account — the restore target is new), then migrate/merge data, and repoint the app. Post-incident: enforce a review rule that partition-key changes require a migration plan, add `prevent_destroy` on containers/accounts, and validate partition keys at design review. This class of error is config-change-driven but entirely preventable by process.
19. **Q:** App connections fail with "login failed for user" after a change.
**A.** Check the contained database user still exists (creating a DB from a restore doesn't carry the app's contained user), the managed identity's role/assignment, Entra-only auth behaviour (no SQL logins at all), and the private endpoint DNS. Then fix the user provisioning step and add it to the post-restore runbook.
20. **Q:** Database storage is at 95% with autogrow disabled.
**A.** Identify growth (tables/indexes/logs/audit), clean up or archive, and raise the max size (`max_size_gb`) — a fast metadata change. Then set capacity alerting at 80% and a retention policy; Terraform should manage the ceiling deliberately rather than letting the database hit a hard limit.
21. **Q:** Costs spiked after changing the Azure SQL SKU or Cosmos throughput mode.
**A.** Check the SKU/tier (Business Critical/Hyperscale are significantly pricier), whether autoscale is at a high max (Cosmos autoscale bills on the max for a portion of the time/pattern), and whether unused databases remain in a pool. Right-size from metrics (DTU/vCore %, RU consumption) and set budgets/alerts — the interview point is measuring before changing the tier.
22. **Q:** An apply disabled public network access and the CI pipeline (which uses SQL auth from a runner) broke.
**A.** The runner isn't in the VNet/using the private path. Fix by moving deployment/migration steps to a runner with private access (or a temporary, documented firewall rule for the runner's IP with removal afterwards), and prefer Entra ID auth so no SQL credentials are needed. Then re-verify private-only networking in the pipeline with a connectivity test.
23. **Q:** Failover group failover happened and the app didn't recover.
**A.** The app used the server name instead of the failover-group listener, cached DNS/connections too long, or the secondary was a lower tier and couldn't handle the load. Fix connection strings to use the listener, add retry logic/connection resiliency in the app, and size the secondary realistically; then include an app-level test in the DR drill.

**⚖️ Trade-off**
24. **Q:** Azure SQL vs PostgreSQL/MySQL Flexible Server vs Cosmos DB?
**A.** Azure SQL for T-SQL/enterprise features and Windows-centric stacks; PostgreSQL Flexible for open-source ecosystems and more control/cost flexibility (with extensions); Cosmos for globally distributed key-based access at scale with tunable consistency. The data model and access patterns decide.
25. **Q:** Elastic pool vs database-per-tenant dedicated?
**A.** Pools share resources across many databases — cost-efficient for many small/variable tenants with some noisy-neighbour risk; dedicated databases give isolation and predictable performance at higher cost. Common: pool for the long tail, dedicated for large/regulated tenants.
26. **Q:** Provisioned vs serverless (Azure SQL) vs autoscale (Cosmos)?
**A.** Provisioned for predictable load (cheap at steady utilisation, with reservations); serverless for intermittent workloads (auto-pause, per-second billing) at the cost of cold-start latency; Cosmos autoscale scales between 10% and max with a billing floor. Match the mode to the load shape and measure the actual duty cycle.
27. **Q:** Zone redundancy vs local redundancy for SQL/Cosmos?
**A.** Zone-redundant protects against a datacentre failure in-region and is the production default where supported (higher cost, sometimes API/tier restrictions); locally redundant is cheaper but only tolerates hardware failure. For anything with an availability commitment, zone-redundant.
28. **Q:** Failover group vs geo-replica vs backup restore for DR?
**A.** Failover groups give automatic/manual failover with a listener endpoint and readable secondaries (RPO seconds); geo-replicas are similar but more manual; backup/restore is the last resort (RPO up to the backup interval, RTO hours). Choose per tier-1 vs tier-2 workloads and test the failover, including the app's connection behaviour.
29. **Q:** Terraform-managed database users/roles vs migrations?
**A.** Infrastructure and identities (server-level Entra admins, contained-user creation via a controlled script) can be Terraform or pipeline-managed; grant-level permissions for app roles are usually migration-tool territory. Pick one owner per object type — duplicate ownership causes drift and failed applies.
30. **Q:** Azure SQL vs Managed Instance vs SQL on VMs?
**A.** Azure SQL (PaaS) for cloud-native apps (simplest, elastic, some feature limits); Managed Instance for near-100% SQL Server compatibility with instance-level features (lift-and-shift); SQL on VMs for full OS control or unsupported versions (you own patching/HA). Migration drivers decide, but the Terraform shape changes accordingly (database vs instance vs VM+extensions).

**🎯 Senior**
31. **Q:** What does production-ready database infrastructure look like in Terraform?
**A.** Entra-only authentication (or Key Vault-sourced credentials) with managed identities for apps; private endpoints with central DNS zones and public access disabled; TDE with CMK, auditing to an immutable store, Defender/security alerts enabled; zone redundancy; PITR + LTR configured and *tested*; failover groups for tier-1 DR with apps using the listener endpoint; elastic pools sized from metrics with per-database max sizes; Cosmos with a validated partition key, autoscale throughput, continuous backup, and multi-region reads as required; `prevent_destroy` on servers/accounts/containers and pipelines that deny destructive database actions in production; and a documented restore/failover runbook with measured RTO.

**🎯 Senior signal:** "the partition key can't be changed — it's a design decision", "restores create new resources, so the app needs a cutover plan", and "contained users don't come back with a restored database". Those three are marks of someone who has operated Azure data platforms.
