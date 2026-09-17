# AWS KMS — Interview Questions

> **Cloud:** AWS (Other Services) · **Category:** Security / Encryption · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

KMS access is governed by the **key policy** — a resource-based JSON policy document (same language as IAM policies).

```json
{
  "Version": "2012-10-17",
  "Id": "key-policy",
  "Statement": [{
    "Sid": "Allow use of the key",
    "Effect": "Allow",
    "Principal": { "AWS": "arn:aws:iam::111122223333:role/app-role" },
    "Action": ["kms:Encrypt", "kms:Decrypt", "kms:GenerateDataKey"],
    "Resource": "*",
    "Condition": { "StringEquals": { "aws:SourceVpce": "vpce-0abc123" } }
  }]
}
```

**Key fields:** `Principal` · `Action` (`kms:Encrypt/Decrypt/ReEncrypt*`, `kms:CreateGrant`, `kms:DescribeKey`…) · `Resource` (usually `*` = the key itself) · `Condition` (`aws:SourceVpce`, `kms:ViaService`, `aws:SourceAccount`). Both the **key policy and IAM policy** must allow.


## Case A — Basic

**A1. What is AWS KMS?**
**Answer:** AWS Key Management Service — a managed service for creating and controlling **cryptographic keys** used to encrypt your data across AWS services and your own applications.

**A2. What is a KMS key (formerly CMK)?**
**Answer:** A logical key resource in KMS with a unique ID, key material, and a **key policy** controlling who can use/administer it. (CMK = customer master key, the older term.)

**A3. What are the key types?**
**Answer:** **Symmetric** (single key for encrypt/decrypt — most common) and **asymmetric** (public/private pair for sign/verify or encrypt/decrypt). Plus **AWS-managed** vs **customer-managed** vs **AWS-owned** keys.

**A4. What is the difference between AWS-managed and customer-managed keys?**
**Answer:** AWS-managed keys are created/managed by AWS on your behalf for a service (e.g., `aws/s3`, `aws/ebs`) — limited control. Customer-managed keys are created by you with full control over key policy, rotation, and lifecycle.

**A5. What is envelope encryption?**
**Answer:** KMS encrypts a **data key**, and the data key encrypts the actual data. Only the small data key touches KMS (which has a 4 KB limit); bulk data is encrypted locally — efficient and scalable.

**A6. What does KMS actually encrypt (size limit)?**
**Answer:** The `Encrypt`/`Decrypt` APIs work on up to **4 KB** of data — which is why large data uses envelope encryption.

**A7. What is a key policy?**
**Answer:** The resource-based policy on a KMS key that defines who can administer, use, and share the key — the primary access control for KMS (IAM policies alone are NOT sufficient).

**A8. Does IAM alone grant KMS access?**
**Answer:** No — KMS requires permissions in **both** the key policy **and** IAM policy (the key policy must allow the principal/action). This is a common exam/interview point.

**A9. What is automatic key rotation?**
**Answer:** For symmetric customer-managed keys, KMS rotates the **backing key material** yearly (keeping the same key ID) — old material is retained for decryption.

**A10. What is a data key vs a key encryption key (KEK)?**
**Answer:** The **KEK** (the KMS key) encrypts **data keys**; data keys encrypt your data. The KEK never leaves KMS.

**A11. What is GenerateDataKey?**
**Answer:** Returns a plaintext data key + an encrypted copy. You encrypt data with the plaintext key and store the encrypted key with the data — decrypt later via KMS `Decrypt`.

**A12. What is a KMS grant?**
**Answer:** A delegation mechanism allowing a principal to use a key for specific operations without full key-policy changes (e.g., an EC2 instance or service using a key long-term).

**A13. What are the KMS API limits/throttling?**
**Answer:** KMS has per-account request quotas (e.g., shared limits on `Decrypt`/`Encrypt` calls). Excessive calls throttle — a key consideration for high-volume services (mitigate with data-key caching).

**A14. Can you import your own key material?**
**Answer:** Yes — **BYOK** (bring your own key): import key material into a KMS key (with an import token + wrapping key).

**A15. What is a multi-Region key?**
**Answer:** A set of KMS keys in different regions with the **same key ID and material**, replicated — for encrypting data that must be decrypted in multiple regions (DR, global tables).

---

## Case B — Advanced (Senior)

**B1. Explain envelope encryption end-to-end with GenerateDataKey/Decrypt.**
**Answer:** (1) Call `GenerateDataKey` → get plaintext data key + encrypted data key. (2) Encrypt the data with the plaintext key locally. (3) Store the encrypted data + encrypted data key together. (4) To decrypt, call KMS `Decrypt` on the encrypted data key (KMS uses the KEK), then decrypt the data locally. The KEK never leaves KMS; only small keys traverse it.

**B2. How do key policies vs IAM policies vs grants differ for KMS access?**
**Answer:** The **key policy** is the root of KMS access (must explicitly allow). **IAM policies** grant principals permission to call KMS APIs (also required). **Grants** delegate temporary/limited use (e.g., to an instance or service) without editing policies — used heavily by AWS services (EBS, RDS) and for cross-account sharing.

**B3. How do you share a KMS key across accounts (e.g., encrypted snapshot/AMI)?**
**Answer:** In the key policy, add the target account (or its principal) with `kms:DescribeKey`, `kms:CreateGrant`, `kms:Decrypt`, `kms:ReEncrypt*`, `kms:GenerateDataKey*`. Then share the resource (snapshot/AMI) — the target account copies/re-encrypts using the key. Both key policy and IAM must align.

**B4. Why does KMS throttle and how do you avoid it in high-volume apps?**
**Answer:** KMS has per-account request quotas (shared across `Decrypt`/`Encrypt` etc.); exceeding them causes throttling (and errors). Avoid by **caching data keys** (envelope encryption — call KMS once per key, not per record), using **grants** (fewer API calls), or request limit increases. High-volume EBS/CloudTrail encryption is managed by AWS internally.

**B5. What is automatic vs on-demand vs manual rotation, and what rotates?**
**Answer:** **Automatic** (yearly) rotates the backing key material of a symmetric customer-managed key (key ID stays the same). **On-demand** (manual) rotates asymmetric key material (new key version). **Manual** = you create a new key and re-encrypt data. Rotating never re-encrypts your data automatically — only the KEK's material changes.

**B6. Explain KMS key state (Enabled, Disabled, PendingDeletion) and the safety of deletion.**
**Answer:** Disabling a key stops all cryptographic use (data becomes inaccessible until re-enabled). **Scheduling deletion** requires a 7–30 day waiting period (default 30) during which the key is unusable but recoverable — a safety mechanism to avoid accidental permanent data loss.

**B7. How does KMS integrate with AWS services (EBS, S3, RDS) under the hood (grants)?**
**Answer:** The service assumes a role/uses a **grant** to call KMS on your behalf: e.g., EBS creates a grant so the instance can `Decrypt` the volume's data key via `GenerateDataKeyWithoutPlaintext`. This is why "KMS permissions" issues often manifest as service errors (e.g., can't attach encrypted volume) — the grant/key policy is the fix.

**B8. What are multi-Region keys, how do they work, and when are they needed?**
**Answer:** A primary key + replicas in other regions sharing the same key material and ID (replicated via KMS). Used when the **same ciphertext must be decryptable in another region** — e.g., DynamoDB Global Tables, Aurora global, or cross-region DR where you can't re-encrypt. You manage the primary; replicas are read-only copies.

**B9. What are the differences between symmetric and asymmetric keys and their use cases?**
**Answer:** Symmetric = one key for encrypt+decrypt (used by most AWS services; envelope encryption). Asymmetric = RSA/ECC key pairs (public for encrypt/verify, private never leaves KMS) — used when external parties need the **public key** (e.g., signing, or encrypting data without AWS credentials). Asymmetric keys don't support automatic rotation.

**B10. What is the KMS "confused deputy" problem and how does `aws:ViaAWSService` / source conditions mitigate it?**
**Answer:** A confused-deputy attack is when a service/principal is tricked into acting on your key on behalf of an attacker. Mitigate with key-policy conditions like `aws:SourceArn`, `aws:SourceAccount`, `kms:ViaService`, and `aws:ViaAWSService` so the key only allows use from specific resources/services.

**B11. How do you audit KMS usage?**
**Answer:** **CloudTrail** records every KMS API call (Encrypt/Decrypt/GenerateDataKey/rotation/schedule-deletion) — the primary audit trail. Combine with CloudWatch alarms on unusual patterns, and use KMS CloudTrail logs to prove "who decrypted what" for compliance.

**B12. What are the KMS quotas you must plan around, and how do you right-size key strategy?**
**Answer:** Quotas: number of keys per region, requests per second per key/account (shared), and the 4 KB operation limit. Right-size: use **fewer, well-scoped keys** (not one key per object), cache data keys, use envelope encryption, and consolidate keys per environment/tenant as needed.

---

## Case C — Scenario

**C1. Scenario:** A user can't download an SSE-KMS encrypted object from S3 despite having `s3:GetObject`.
**Question:** Diagnose and fix.
**Expected answer:** They also need **`kms:Decrypt`** on the key used to encrypt the object, granted in **both** the key policy and their IAM policy. Add `kms:Decrypt` (and `kms:GenerateDataKey` for uploads) to both, then retry. This dual-permission requirement is the most common KMS gotcha.

**C2. Scenario:** You must prove to an auditor that a specific user decrypted a specific file at 3 PM.
**Question:** How?
**Expected answer:** Query **CloudTrail** for the KMS `Decrypt` API call filtered by the key ARN, user ARN, and timestamp — CloudTrail logs every KMS operation, providing the cryptographic audit trail (who, when, which key). Cross-reference the resource (S3) access logs.

**C3. Scenario:** A high-throughput service calls KMS `Decrypt` per record and is being throttled.
**Question:** Redesign to avoid throttling.
**Expected answer:** Use **envelope encryption with data-key caching**: fetch a data key once (or cache `Decrypt` of the data key), encrypt/decrypt records locally with the data key, and refresh periodically. This reduces KMS calls from per-record to per-key-refresh, eliminating throttling and latency.

**C4. Scenario:** Cross-account: Account B must decrypt a KMS-encrypted snapshot shared from Account A.
**Question:** List the exact steps.
**Expected answer:** (1) In Account A, update the **key policy** to grant Account B's principal `kms:DescribeKey`, `kms:CreateGrant`, `kms:Decrypt`, `kms:ReEncrypt*`, `kms:GenerateDataKey*`. (2) Share the snapshot with Account B. (3) In Account B, **copy** the snapshot (optionally re-encrypting with Account B's own KMS key) and create the volume. Account B cannot use Account A's key directly without a copy + key grant.

**C5. Scenario:** An engineer accidentally scheduled deletion of a production key; data is now inaccessible.
**Question:** What's the recovery path?
**Expected answer:** If the key is in **PendingDeletion** (7–30 day window), **cancel the deletion** from the console/CLI (`CancelKeyDeletion`) to restore access — the waiting period exists precisely for this. If the key was fully deleted (or key material deleted), the ciphertext is **unrecoverable** — restore from backups (snapshots/versions) encrypted under a different key, or from a replica key.

**C6. Scenario:** You need the same data decryptable in us-east-1 and eu-west-1 without re-encrypting on every region switch (e.g., a global DynamoDB table).
**Question:** Which KMS feature and how?
**Answer:** **Multi-Region keys**: create a primary key in one region, create replicas in the other regions (same key material/ID). Encrypt once; any region's replica can decrypt the same ciphertext. Note replicas can't be deleted while linked and are managed from the primary.
