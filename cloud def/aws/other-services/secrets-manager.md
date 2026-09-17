# AWS Secrets Manager — Interview Questions

> **Cloud:** AWS (Other Services) · **Category:** Security / Secrets · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~8 min

---

## JSON File Format

A Secrets Manager **secret value** is a JSON object of key-value pairs, retrieved via `GetSecretValue.SecretString`.

```json
{
  "username": "appuser",
  "password": "S3cr3t-Passw0rd!",
  "host": "db.example.internal",
  "port": "3306",
  "dbname": "orders"
}
```

**Key fields:** arbitrary key-value JSON (structured credentials) · **versioning** via staging labels `AWSCURRENT` / `AWSPENDING` / `AWSPREVIOUS` · rotation Lambdas receive/return this JSON in the rotation steps (createSecret → setSecret → testSecret → finishSecret).


## Case A — Basic

**A1. What is AWS Secrets Manager?**
**Answer:** A managed service for storing, retrieving, and **rotating** secrets (database credentials, API keys, tokens) — with encryption at rest, fine-grained IAM access, and audit logging.

**A2. What problems does Secrets Manager solve?**
**Answer:** Hardcoded credentials in code/config, secret sprawl, and manual rotation — providing a single secure source of truth with automatic rotation.

**A3. How is a secret structured?**
**Answer:** A secret contains a **name**, **versioned secret value** (JSON key-value pairs, e.g., username/password), metadata, and optional rotation config. Each update creates a new version.

**A4. How are secrets encrypted?**
**Answer:** At rest with **AWS KMS** (a KMS key, default `aws/secretsmanager` or your own CMK), and in transit over TLS.

**A5. How do you control access to secrets?**
**Answer:** Via **IAM policies** (resource-based policies on the secret + identity policies) — least privilege: only grant `secretsmanager:GetSecretValue` to the roles/apps that need it.

**A6. What is automatic rotation?**
**Answer:** Secrets Manager can periodically rotate a secret (e.g., every 30 days) by invoking a **Lambda rotation function** that updates both the secret and the target service (e.g., RDS password).

**A7. What is a secret version and staging label?**
**Answer:** Each update is a new **version**; labels like `AWSCURRENT` / `AWSPENDING` / `AWSPREVIOUS` mark the rotation state of versions (current, being rotated to, previous).

**A8. How does Secrets Manager differ from SSM Parameter Store?**
**Answer:** Secrets Manager = secrets-focused with **rotation**, cross-account access, and per-secret pricing. Parameter Store = general config/secrets with SecureString, free for standard params, no native rotation (unless you build it). Choose Secrets Manager for secrets needing rotation; SSM for simpler config.

**A9. How do you retrieve a secret from an app?**
**Answer:** Call `GetSecretValue` (SDK/CLI) with the right IAM role, and **cache** the value in memory with a refresh interval — don't fetch on every request.

**A10. Can you replicate secrets across regions?**
**Answer:** Yes — **replicate** a secret to other regions (kept in sync, with a replica KMS key) for multi-region apps and DR.

**A11. What is a resource-based policy on a secret?**
**Answer:** A policy attached to the secret itself controlling which principals/accounts can access it — enabling **cross-account sharing** without granting account-wide access.

**A12. What does `GetRandomPassword` do?**
**Answer:** Generates a cryptographically random password (with constraints) to store in a secret — handy for creating strong DB passwords programmatically.

**A13. What happens when you delete a secret?**
**Answer:** Secrets Manager requires a **recovery window** (default 30 days, 7–30 configurable) during which the secret can be restored before permanent deletion.

**A14. How does Secrets Manager integrate with RDS?**
**Answer:** RDS can store its master credentials in Secrets Manager, and Secrets Manager provides **managed rotation** for RDS (built-in Lambda templates for MySQL/Postgres/Oracle/SQL Server).

**A15. What is the pricing model?**
**Answer:** Per secret per month + per 10,000 API calls (there's a free tier for API calls). Rotation Lambda invocations cost separately.

---

## Case B — Advanced (Senior)

**B1. Explain the rotation flow (AWSCURRENT/AWSPENDING) and how a rotation Lambda works.**
**Answer:** On rotation: (1) Lambda creates a new version labeled `AWSPENDING` and sets the new password on the target (e.g., RDS). (2) It tests the pending credentials. (3) On success, it relabels `AWSPENDING` → `AWSCURRENT` and the old one → `AWSPREVIOUS`. Apps reading `AWSCURRENT` automatically get the new credentials. On failure, the pending version is discarded.

**B2. How do you design secret caching in an application to handle rotation gracefully?**
**Answer:** Fetch the secret at startup and **cache in memory**; refresh periodically (or on auth failure). On rotation, apps get the new value at next refresh; some SDKs/drivers (RDS Proxy, some DB clients) fetch automatically. Handle `ResourceNotFoundException`/auth errors by re-fetching. Avoid per-request `GetSecretValue` (cost + latency + throttling).

**B3. How does cross-account secret sharing work, and what are the steps?**
**Answer:** (1) Attach a **resource-based policy** on the secret granting Account B's role `secretsmanager:GetSecretValue` (+ `kms:Decrypt` via the **KMS key policy**). (2) In Account B, attach an IAM policy allowing the same. Both must allow. This is cleaner than sharing the whole account.

**B4. Compare Secrets Manager vs Parameter Store vs environment variables for config/secrets.**
**Answer:** Env vars = simplest but not encrypted/rotated/auditable. Parameter Store = free, encrypted (SecureString), hierarchical paths, good for config + simple secrets. Secrets Manager = rotation, cross-account policies, replication, per-secret cost — best for DB creds/API keys. Use SSM for config, Secrets Manager for rotating secrets.

**B5. How do you integrate Secrets Manager with ECS/EKS/Lambda?**
**Answer:** ECS: task definition `secrets` references the secret ARN (execution role needs `GetSecretValue`). EKS: **External Secrets Operator** or **Secrets Store CSI Driver** syncs to K8s secrets/volumes. Lambda: read at init via SDK with caching, or use the **Parameters and Secrets Lambda extension** (cached, encrypted).

**B6. What are the security best practices for Secrets Manager?**
**Answer:** Least-privilege IAM (no wildcards), **resource policies** for cross-account, use a **customer-managed KMS key**, enable **CloudTrail** (logs all API access), **replicate** for DR, enable rotation everywhere possible, never log secret values, restrict to VPC endpoints for private access, and enable deletion recovery windows.

**B7. How do you rotate a secret for a custom service (no built-in template)?**
**Answer:** Write a **custom rotation Lambda** implementing the rotation steps (`createSecret` → `setSecret` on the target → `testSecret` → `finishSecret`), store the Lambda's permissions, and attach it as the secret's rotation function with a schedule. The Lambda must handle the target's credential-update API and rollback.

**B8. How does Secrets Manager handle versions, and why is versioning important for rollback?**
**Answer:** Every update creates an immutable **version**; the `AWSPREVIOUS` label preserves the prior good value. On rotation failure or an app issue, you can point back to `AWSPREVIOUS` instantly — an audit-friendly rollback mechanism built into the service.

**B9. What is the Parameters and Secrets Lambda extension and its benefits?**
**Answer:** A Lambda layer that **caches** Parameter Store/Secrets Manager values inside the execution environment and refreshes them automatically (with TTL) — reducing `GetSecretValue` API calls, latency, and cost, while simplifying code.

**B10. How do you audit and monitor Secrets Manager usage?**
**Answer:** **CloudTrail** logs every API call (GetSecretValue, rotation, policy changes) — the audit source. CloudWatch metrics (`GetSecretValue` counts/errors) for usage; alarm on failures/throttles. Use Access Analyzer to detect secrets accessible to external principals.

**B11. What are the cost/limit considerations at scale (many secrets, high API volume)?**
**Answer:** Per-secret-per-month cost means many secrets get expensive (consolidate related creds into one JSON secret). API calls are cheap but add up with per-request fetches — **cache** to reduce calls. Watch KMS costs if using a customer key. Consider SSM Parameter Store for high-volume, low-sensitivity config.

**B12. How do you do zero-downtime credential changes across a fleet (rotation + consumer refresh)?**
**Answer:** Enable **managed rotation** (RDS) or custom Lambda; ensure consumers **cache + auto-refresh** (or use RDS Proxy which handles credential fetch). Rotation creates the pending version, tests it, then flips `AWSCURRENT` — consumers refresh within their cache TTL, avoiding downtime. Test rotation in staging first.

---

## Case C — Scenario

**C1. Scenario:** A Lambda needs RDS credentials; the team hardcoded them in the code and they were leaked on GitHub.
**Question:** Remediate + harden.
**Answer:** Immediately **rotate the DB password** and revoke exposed creds. Store creds in **Secrets Manager** with **automatic rotation**, grant the Lambda's execution role `secretsmanager:GetSecretValue` (least privilege), fetch + cache at init, and add **secret scanning** (git-secrets/TruffleHog + CodeGuru) and a policy against committing secrets.

**C2. Scenario:** An app caches a secret in memory; after rotation it starts failing auth.
**Question:** Diagnose and fix.
**Answer:** The app is still using the old cached value (or it cached before `AWSCURRENT` flipped). Fix: implement **cache refresh** (TTL) and re-fetch on **auth failure**; use the SDK's caching helpers or the Lambda extension. Confirm the rotation Lambda completed successfully (check `AWSCURRENT` label and CloudTrail).

**C3. Scenario:** A DB password must rotate every 30 days with zero downtime for a Python app on EC2.
**Question:** Design it.
**Answer:** Use **RDS + Secrets Manager managed rotation** (MySQL/Postgres template, 30-day schedule). The app fetches the secret at startup, caches it, and refreshes on failure/TTL. The rotation flow (pending → test → current) keeps one valid credential at all times, so no downtime. Monitor rotation success via CloudTrail/CloudWatch.

**C4. Scenario:** Account B's ECS task must read a secret in Account A without sharing the whole account.
**Question:** Set up cross-account access.
**Answer:** In Account A: attach a **resource-based policy** to the secret allowing Account B's **task role ARN** to `GetSecretValue`, and grant `kms:Decrypt` on the KMS key to Account B. In Account B: the task role's IAM policy allows `secretsmanager:GetSecretValue` on the secret ARN, and the task definition references the secret. Both sides must allow.

**C5. Scenario:** A developer deleted a secret by mistake and the app is down.
**Question:** Recover it.
**Answer:** Deleted secrets remain recoverable during the **recovery window** (default 30 days) — call `RestoreSecret` (console/CLI) to bring it back. If the window passed, the secret is gone — recover the value from backups/another replica region or rotate fresh credentials into a new secret. Prevent recurrence with deletion policies/SCPs and backups.

**C6. Scenario:** You need the same credentials available in two regions for a multi-region app with automatic sync.
**Question:** Which feature?
**Answer:** **Secret replication**: enable replication of the primary secret to the second region (with a replica KMS key). Secrets Manager keeps replicas in sync automatically, and either region's app reads its local replica. Rotation on the primary propagates to replicas.
