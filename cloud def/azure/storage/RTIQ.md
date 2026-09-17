# RTIQ — Azure Storage (Real-Time Interview Questions)

> **Cloud:** Azure · **Domain:** Storage Accounts, Identity Management for Storage · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~19 min

**How this file is used live:** storage rounds are about *durability, access, and cost*. Interviewers ask how you'd design a multi-tenant data platform, how you'd stop a public exposure, and how you'd cut the bill. Expect SAS, RBAC vs keys, redundancy options, lifecycle, and a "the account key leaked" drill.

**Legend:** ⚡ Rapid · 🔍 Deep dive · 🚨 War room · ⚖️ Trade-off · 🎯 Senior signal

---

## 1. Storage Accounts — `storage-accounts.md`

**⚡ Rapid**
1. **Q:** What services live in a storage account?
**A.** Blob, File, Queue, Table, and (classic) Disk — one account is the management/billing/scale boundary, and the *kind/SKU* (StorageV2, Premium BlockBlob, Premium FileShare, etc.) determines what you get.
2. **Q:** Redundancy options?
**A.** LRS (3 copies, one datacentre), ZRS (3 zones in-region), GRS/RA-GRS (secondary region, async, readable with RA), GZRS/RA-GZRS (zones + secondary region). Choose by RPO/RTO and cost; ZRS for zone-failure resilience, GZRS for regional DR.
3. **Q:** Access tiers?
**A.** Hot (frequent), Cool (≥30 days, cheaper storage, higher access), Cold (≥90 days), Archive (≥180 days, offline, rehydrate hours). Lifecycle management moves data automatically based on age/access — and every tier has minimum-duration charges if you delete/move early.
4. **Q:** What is a SAS?
**A.** Shared Access Signature — a time-limited, scope-limited delegated token (account/user/delegation level) that grants specific permissions on a resource. Use user delegation SAS (backed by Entra ID) rather than account-key SAS, and keep short expiries. SAS leaks are a classic breach vector.
5. **Q:** Blob vs Files vs Queue vs Table vs Disk?
**A.** Blob: objects/unstructured at scale; Files: SMB/NFS shares; Queue: simple messaging; Table: NoSQL key-value (legacy vs Cosmos Table); Disk: managed VM disks. Choose by protocol/access pattern — don't force Blob into a filesystem role.
6. **Q:** How do you secure an account?
**A.** `publicNetworkAccess=Disabled` + private endpoints, `SharedKeyAccess=false` (Entra-only auth), no anonymous/public blob access (block public access), minimum TLS 1.2, infrastructure encryption if required, CMK via Key Vault where needed, and diagnostic logs to a central workspace. That trio (private endpoint + no shared key + no anonymous access) is the modern baseline.
7. **Q:** What are the account limits to plan for?
**A.** Per-account scale targets (transactions/egress, ingress limits), 5 PiB capacity, and per-blob/list limits. At high throughput you shard across multiple accounts (or use a storage account per tenant/workload), and remember that partition/prefix-level throughput matters for Blob performance.
8. **Q:** How do you give an app access?
**A.** Managed identity + RBAC data-plane roles (`Storage Blob Data Reader/Contributor/Owner`) scoped to the container/account — with no keys in the app's config at all. This should be your default answer for every storage question.

**🔍 Deep dive**
9. **Q:** Design storage for a multi-tenant data platform: 500 tenants, PII, global reads, regulated retention.
**A.** One account (or account per grouping) per region with containers per tenant and `{tenantId}/` prefixes; RBAC scoped per container plus ABAC conditions where supported; private endpoints per VNet; CMK (Key Vault) and infrastructure encryption for the sensitive tier; immutable/versioned blobs + WORM (immutability policies) for the regulated records; lifecycle policies (Cool→Cold→Archive) and a documented restore SLA for archived data; diagnostic logging (Blob read/write) for the audit path; and geo-redundancy (GZRS) with a tested failover for reads. Include a per-tenant capacity/egress dashboard for cost allocation.
**↳ Follow-up:** "How do you handle a GDPR erasure request?"
**A.** Identify all copies (blobs, versions, snapshots, soft-deleted, backups, secondary region, analytics copies) and delete with all versions included (`Delete Blob` with version handling); if immutability/WORM is in force, erasure via crypto-shredding (per-tenant CMK) is the honest answer. Document the process — "we can't delete due to retention" needs to be an approved, disclosed policy, not an accident.
10. **Q:** How do you reduce storage costs significantly?
**A.** Right-size redundancy (not every workload needs GZRS), lifecycle policies to Cool/Cold/Archive based on real access, delete old versions/snapshots/soft-deleted data (versioning buildup is the biggest surprise), fix hot-tier data that's rarely read, reduce transactions (chatty LIST loops, small-object churn — batching/aggregation), move infrequently used data out of Premium disks/shares, and use reservable capacity (Azure Storage Reserved Capacity) for steady usage. Measure with Storage Insights first.
11. **Q:** How do you do point-in-time recovery for blob data?
**A.** Enable blob versioning + soft delete + change feed, then recover individual versions or restore a container/time range; enable point-in-time restore for block blobs (up to 30 days) for bulk recovery. For file shares, use share snapshots. And for anything critical, replicate to a separate account/locked container as the ransomware-safe copy.
12. **Q:** How do you protect against ransomware/insider deletion?
**A.** Immutability (time-based retention/legal hold) on backups and critical containers, no standing delete permissions (RBAC least privilege + PIM for elevated), soft delete + versioning, a separate account with locked retention for backups (an admin can't delete it), alerts on mass-delete patterns, and Defender for Storage detections. Test a recovery — locked retention that can't be restored from is still a data-loss event.
13. **Q:** How do you handle high-throughput access patterns?
**A.** Blob scales by prefix/partition — spread keys (not all under one timestamp), use parallel uploads (block blobs + `PutBlock`), consider multiple accounts for extreme throughput/tenants, and use Premium block blob for latency-sensitive workloads. Reading: CDN/Front Door for public assets, and `Range` gets for partial reads. Also check the client's connection reuse and retry behaviour.
14. **Q:** How do you safely design an SFTP/partner file exchange?
**A.** Azure Blob SFTP (supported on hierarchical namespace accounts) or Azure Files with private endpoints, per-partner containers/folders and identities, restricted ingress (private endpoint or IP allow-list), malware scanning of uploads (Defender for Storage), and lifecycle rules to clean the drop zone. Never expose a storage account publicly for exchange.
15. **Q:** What are the common storage-account design mistakes you've seen?
**A.** Shared account keys distributed to apps, public access left enabled, one giant account for everything (blast radius + limits), versioning on with no lifecycle (cost creep), hot tier for archives, no private endpoints while "we block public access" via firewall rules only, and immutability/backup never tested. Each one is a good interview talking point.

**🚨 War room**
16. **Q:** An account key leaked. Response?
**A.** Rotate keys immediately with the dual-key method (rotate the unused key, update consumers, then rotate the other) — or better, disable shared key access entirely and move consumers to identity-based auth; audit access logs (Blob read/write/delete) for the exposure window and check for data exfiltration or modified content; restrict network access; notify per policy if customer data was involved. Then fix the root cause (why did an app need a key?).
17. **Q:** A container was public and indexed by search engines. Response?
**A.** Disable public access immediately (`AllowBlobPublicAccess=false` at account level), check for anonymous read logs (which objects, how much, from where), assess PII/secret exposure, rotate/build incident comms as required, and then harden: Policy to block public access account-wide, alerts on `SetContainerAcl`/`SetAccountProperties` changes, and a review of every account's public-access setting.
18. **Q:** Mass deletion of blobs (thousands) overnight. Recovery?
**A.** Check soft delete/versioning: restore soft-deleted blobs or roll back to a previous version (bulk via script/Azure Storage Explorer, or point-in-time restore for a range). Identify the actor (diagnostic logs: principal, IP, user agent) — this is either a bug, a bad script, or an attacker. Then prevent: immutability on critical data, least privilege (no delete for app identities), and alerts on delete-rate anomalies.
19. **Q:** Storage throttling (`ServerBusy`/503) during a batch job. Fix.
**A.** You're hitting scale targets for the account/partition — spread load across prefixes/multiple accounts, batch operations, add retry with backoff (and check the SDK's default), and check whether one prefix is hot (timestamp-named containers are a classic). For sustained high throughput, shard or use Premium storage.
20. **Q:** Lifecycle policy moved active data to Archive and users can't open it.
**A.** Archive requires rehydration (hours, and it costs) — restore the affected blobs by priority and, structurally, fix the lifecycle rules: base them on actual access patterns (last-access-time tracking, Storage Insights) rather than age alone, exclude active containers/prefixes, and test new policies on a small scope first. Consider Intelligent tiering-like behaviour via access-based rules instead of blind age.
21. **Q:** Costs jumped 40% with no traffic change. Where do you look?
**A.** Versions/snapshots accumulating (soft delete + versioning without lifecycle), tier changes causing early-deletion/minimum-duration charges and retrieval fees, transaction volume from polling/LIST loops, cross-region replication egress (GRS/RA-GRS reads), and data moved out via a secondary region. Storage Insights/Cost analysis by meter shows it fast; then set lifecycle rules for versions (e.g. delete noncurrent versions after 30 days).
22. **Q:** A private endpoint was deleted and apps lost storage access.
**A.** Recreate the private endpoint and the private DNS A record (deleting the endpoint can remove the DNS entry), verify name resolution from inside the VNet, and add protection: resource locks on endpoints/DNS zones where possible, alerts on endpoint deletion, and an IaC-owned definition so drift is recreated automatically.

**⚖️ Trade-off**
23. **Q:** Blob vs Data Lake Storage Gen2 vs Files vs Disk vs NetApp Files?
**A.** Blob for objects/analytics; ADLS Gen2 (blob with hierarchical namespace) for big-data workloads needing directory semantics/ACLs; Files for SMB/NFS shares; Disk for VM volumes; NetApp/Managed Lustre for high-performance NFS/HPC. Choose by protocol and performance, and remember Gen2 can be enabled only at account creation.
24. **Q:** Shared key vs SAS vs Entra ID RBAC?
**A.** Entra ID RBAC is the target state (identity-based, auditable, no secrets, per-resource scope). SAS is for delegating limited access to external/unknown clients (user delegation SAS preferred). Shared keys are the legacy root credential — disable them where you can (`SharedKeyAccess=false`), because they grant full control and can't be scoped.
25. **Q:** LRS vs ZRS vs GRS?
**A.** LRS: cheapest, single-DC failures tolerated. ZRS: survives a zone outage in-region (best price/resilience balance for many workloads). GRS/GZRS: regional DR with async replication (RPO measured in minutes) and higher cost — RA-GRS adds readable secondary. Choose from the RPO/RTO commitment, not from habit.
26. **Q:** Hot vs Cool vs Archive — what traps people?
**A.** Early deletion/minimum retention charges, rehydration costs and latency for Archive, higher per-operation costs in cooler tiers (so chatty access gets expensive), and lifecycle rules that don't match real access. Model the access pattern, not just the storage price.
27. **Q:** One account for everything vs many?
**A.** One account simplifies management but creates a huge blast radius, hits scale limits, and makes RBAC coarse; many accounts give isolation/scale but complicate governance, cost attribution, and discovery. Standard: per workload/environment (and per region), with Policy enforcing security settings and naming.
28. **Q:** Should you use storage accounts or Cosmos DB/SQL for application data?
**A.** Blob for unstructured/large objects and analytics; a database for structured transactional data with query needs. Anti-patterns: using Table Storage/Blob as a relational store (no joins/transactions/queries) and storing large binaries in a database (cost/latency). Know the boundary and say it.
29. **Q:** CDN/Front Door in front of Blob — when?
**A.** For public/static content served to many users (cache at the edge, cut egress, absorb traffic) or when you need WAF/geo rules. For private/internal data, private endpoints and SAS are the answer, not CDN.

**🎯 Senior**
30. **Q:** What does a production-ready storage account look like?
**A.** `SharedKeyAccess=false` with Entra-only auth (managed identities), private endpoints + public access disabled, public blob access blocked, minimum TLS 1.2, redundancy matched to the RPO commitment, blob versioning + soft delete + lifecycle rules on noncurrent versions, immutability for regulated records, diagnostic logs (read/write/delete) to a central workspace with alerts on mass deletes and ACL/permission changes, Defender for Storage enabled, cost/usage dashboards per workload, and a tested restore/DR procedure.

**🎯 Senior signal:** "disable shared key access", "versioning without lifecycle is a cost trap", and separating the backup copy into a locked account. That's storage ownership, not storage familiarity.

---

## 2. Identity Management for Storage — `identity-management-storage.md`

> **RTIQ note:** this is the "who can read the data" round — RBAC scopes, SAS design, delegation, ABAC conditions, and auditability. Senior/DevSecOps interviews dig here hardest.

**⚡ Rapid**
1. **Q:** Why is "we block public access" not an access-control answer?
**A.** It controls network exposure, not identity — a leaked account key or an over-scoped SAS still reads everything. Access control must be identity-based (RBAC), be least privilege, and be logged.
2. **Q:** What RBAC roles matter for storage?
**A.** Data-plane roles: `Storage Blob Data Reader/Contributor/Owner`, `Storage Queue Data *`, `Storage File Data *`, plus `Reader` for the control plane. `Contributor` alone does *not* grant data access — a very common misconception (people grant Contributor and wonder why the app gets 403).
3. **Q:** Scope levels?
**A.** Management group → subscription → resource group → account → container/share → (blob-level with conditions/ACLs where supported). Scope assignments to containers, not accounts, whenever possible.
4. **Q:** What are ABAC conditions in Azure Storage?
**A.** Role assignment conditions using blob path/index tags (`.../blob/*` with `StringLike` on container/blob path, or tag-based conditions) so one role assignment can grant, say, read only under `tenant/{userId}/`. It reduces the number of role assignments dramatically for multi-tenant data.
5. **Q:** What's the difference between a user delegation SAS and a service/account SAS?
**A.** A user delegation SAS is signed with an Entra ID credential (no account key involved, automatically revoked if the identity loses permission/access) — the recommended kind. Service/account SAS are signed with the account key, can outlive the signer's access, and are a common leak source.
6. **Q:** How do you define a least-privilege SAS?
**A.** Specific resource (blob/container), specific permissions (read-only vs write), short expiry (minutes/hours), no more services than needed, and ideally IP-restricted and/or HTTPS-only. Emit them from the backend on demand rather than sharing long-lived ones.
7. **Q:** How do you audit data access?
**A.** Enable diagnostic settings (Blob read/write/delete, Authentication) to Log Analytics + archive to immutable storage; query by principal, IP, and operation. Without read logging, "who accessed the customer's data?" is unanswerable — that's an audit finding.
8. **Q:** How do managed identities change storage architecture?
**A.** No keys in config, no rotation tickets, per-workload identity (so access is attributable), and revocation = removing a role assignment. It also enables conditional access to the data plane and clean per-tenant scoping.

**🔍 Deep dive**
9. **Q:** Design access for a multi-tenant SaaS with 500 customers sharing one storage account.
**A.** Containers or top-level prefixes per tenant with RBAC assignments per tenant (or, better, a single assignment with ABAC conditions keyed on path/tags to avoid 500 assignments), a managed identity per service that is granted only what it needs, per-tenant CMK where isolation/erasure requires it, user delegation SAS issued by the app for direct browser upload/download (scoped to the tenant's path with a short expiry), Blob read/write diagnostic logs for the audit trail, and tenant-scoped access reviews. Test the isolation: a user from tenant A must get a 403 for tenant B's path.
**↳ Follow-up:** "How do you prove tenant isolation to a customer?"
**A.** Show the RBAC/ABAC model, demonstrate the 403 with a test, provide audit logs of their tenant's access, and run periodic automated isolation tests (a synthetic "cross-tenant access attempt" that must fail). Evidence + automated negative tests is the answer customers' security teams accept.
10. **Q:** How do you give a partner access to exactly one folder for 30 days?
**A.** A user delegation SAS scoped to that container/prefix with read (or read/write) permissions and a 30-day expiry, IP-restricted to their ranges if possible, plus logging and a calendar/tracked expiry. Where possible, use their own Entra identity via B2B + a role assignment instead of a secret-bearing URL — that's the more auditable path.
11. **Q:** How do you manage storage RBAC at scale (100 accounts, 300 apps)?
**A.** Naming/tagging standards + a module/template that creates accounts with standard settings, role assignments generated from a declarative source (app → container → role), ABAC where it reduces assignment count, PIM for any human elevated access, automated access reviews (unused assignments flagged), and Policy to enforce account settings. Treat assignments as code, reviewed in PRs.
12. **Q:** How do you handle key rotation if you still must use shared keys?
**A.** A dual-key rotation runbook: regenerate the unused key, update consumers from Key Vault (which should be the *only* place the key lives), verify, then rotate the other key on a schedule; monitor for authentication failures after rotation. And be explicit that this is legacy posture — the target is `SharedKeyAccess=false`.
13. **Q:** How do you restrict access by network AND identity?
**A.** Both are needed: private endpoints (network) + RBAC (identity), plus firewall rules if public access is unavoidable. Conditionally, use "selected networks" with service endpoints and `networkAcls` defaults of Deny. Interviewers like hearing that network and identity controls are independent layers.
14. **Q:** What privileges get abused in storage?
**A.** Account key read (`listKeys` — full data access, survives RBAC changes), `Microsoft.Storage/storageAccounts/listKeys/action` granted broadly, SAS generation by an app identity (an app that can mint SAS can be leveraged), blob delete, ACL/permission changes, and diagnostic-settings tampering (disabling logging). Alert on all of them.
15. **Q:** How do you handle access reviews for storage?
**A.** Quarterly review of role assignments per account/container (owner sign-off), automated reports of assignments unused for 90 days, PIM-eligible rather than permanent for human roles, removal of inherited subscription-level assignments in favour of container scope, and evidence retention for audit. Automate the report; humans decide.

**🚨 War room**
16. **Q:** You discover an app identity has `Storage Blob Data Owner` on every account in the subscription.
**A.** Immediately scope it down (remove the broad assignment, add container/prefix-level assignments and ABAC conditions), verify the app still functions, and investigate whether it was exploited (check read/write logs for unusual patterns from that identity, especially access to other tenants'/workloads' data). Then check how it got granted — usually a convenience change during an incident — and add a Policy/alert that flags subscription-wide data-plane role assignments.
17. **Q:** A SAS URL was posted publicly. Response?
**A.** Revoke it immediately: user delegation SAS → revoke the delegator's access or rotate the signing credential; account/service SAS → rotate the account key (which invalidates all key-signed SAS). Check what it exposed (SAS tokens carry scope — see the logs for reads/writes in the window), assess customer impact, and rotate any downstream data. Then redesign: short-lived, IP-restricted, backend-issued SAS only.
18. **Q:** A user reports they can see another tenant's data.
**A.** Treat as a sev-1 data-isolation breach: identify the access path (RBAC assignment scope, ABAC condition mismatch, a shared SAS, a cached token, an app bug using the wrong prefix), stop the exposure (fix the assignment/policy), determine the scope of actual access from logs, and notify per incident/regulatory requirements (this may be a reportable breach). Then add automated negative isolation tests to the pipeline.
19. **Q:** After migrating apps to managed identity, some get 403s.
**A.** Missing data-plane role (people grant `Contributor` which doesn't include data access), assignment at the wrong scope (RG vs container), the app caching old credentials/environment settings, or the identity is user-assigned and not attached to the right resource. Troubleshoot with `az role assignment list --assignee` and test the exact operation (some APIs need `Storage Blob Data Contributor` plus `Queue Data *` separately).
20. **Q:** An engineer runs a script with their own credentials to bulk-delete "test" data and deletes production.
**A.** Restore from soft delete/versioning or point-in-time restore (check immutability for any locked data), and investigate: why did a human have delete rights on production storage? Then fix: no standing human data-plane write on production (PIM-elevated, time-boxed), delete operations on production data gated through a review/approval, alerts on mass-delete events, and a documented "cool-down" for destructive scripts (dry-run first).
21. **Q:** Storage diagnostic logs were disabled and you need last month's access history.
**A.** If logs weren't shipped elsewhere (or archived), it's not recoverable — say so plainly, then fix: Policy to enforce diagnostic settings on every account (with a monitored compliance state), continuous export to a separate immutable workspace/account, an alert on diagnostic-settings changes (an anti-forensics technique), and a quarterly check that logging is live across the estate.
22. **Q:** A workload's managed identity was compromised via a vulnerable app.
**A.** Contain (restrict the workload, revoke its identity or remove the role assignments), then determine what the identity could reach (its scopes) and audit the data-plane logs for what it accessed — this is why per-workload identities with narrow scopes matter. Rotate anything the app could read (secrets in Key Vault, tokens), then fix the vulnerability and re-grant with tighter scope.

**⚖️ Trade-off**
23. **Q:** RBAC vs SAS vs keys — which for which consumer?
**A.** Internal Azure workloads: RBAC with managed identity. External/unknown clients or browsers: short-lived user delegation SAS issued by your backend. Shared keys: never in new designs. And for partner integration, prefer B2B identity + RBAC over a shared secret whenever the partner can support it.
24. **Q:** Container-per-tenant vs prefix-per-tenant for isolation?
**A.** Containers: cleaner RBAC scoping and easier backup/lifecycle per tenant, but more containers to manage and potential per-container limits at huge scale. Prefixes: fewer objects to manage and ABAC conditions can scope them, but RBAC alone can't scope to a prefix without conditions — so isolation depends on correct ABAC/application logic. High-isolation/regulated tenants → containers (or accounts); high-scale commodity tenants → prefixes with ABAC.
25. **Q:** Account-level vs container-level RBAC?
**A.** Container-level is least privilege and the default for apps that need one dataset; account-level is convenient for platform/tooling identities and creates a much larger blast radius. Start narrow and widen only with justification.
26. **Q:** Should you ever use `Storage Blob Data Owner`?
**A.** Rarely — it includes permission management (ACL/role changes), which is administrative. Applications should get Reader/Contributor, and management should be a human/PIM-elevated or platform identity role. If an app has Owner, that's a finding.
27. **Q:** Human access to production data — direct read vs via an application?
**A.** Prefer break-glass, time-boxed access with justification and alerting; day-to-day humans shouldn't browse production data. If they must, scope narrowly (specific container/prefix), log everything, and use access reviews. Regulated environments often require approval workflows and session recording — say it.
28. **Q:** ABAC vs many role assignments?
**A.** ABAC scales (one assignment covers many resources via conditions, and new resources inherit by tag/path) and is easier to audit; many assignments are explicit but become unmanageable and drift. ABAC where the model supports it (blob path/index tags), explicit assignments where conditions can't express the rule.

**🎯 Senior**
29. **Q:** What does your storage access standard say?
**A.** `SharedKeyAccess=false`; Entra-only auth with managed identities per workload; no `Owner` roles for apps; assignments scoped to container/prefix with ABAC where multi-tenant; PIM for any human data-plane access with justification and alerting; SAS only as short-lived backend-issued user delegation tokens; private endpoints for network isolation; data-plane diagnostic logs to a separate immutable store with alerts on mass-delete, permission changes, and `listKeys`/logging changes; quarterly access reviews and automated cross-tenant isolation tests; and CMK for the highest classification exposing crypto-shredding as an erasure mechanism.

**🎯 Senior signal:** "network exposure and identity are separate questions", ABAC for multi-tenant scoping, and the cross-tenant negative test. That's DevSecOps-grade storage thinking.
