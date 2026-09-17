# Amazon S3 — Interview Questions

> **Cloud:** AWS · **Category:** Storage · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

S3's flagship JSON is the **bucket policy** (resource-based policy) and the **CORS/notification/lifecycle** configuration. Bucket policies use the IAM policy language.

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "AWS": "arn:aws:iam::111122223333:role/app-role" },
    "Action": ["s3:GetObject", "s3:ListBucket"],
    "Resource": ["arn:aws:s3:::my-bucket", "arn:aws:s3:::my-bucket/*"],
    "Condition": { "StringEquals": { "aws:SourceVpce": "vpce-0abc123" } }
  }]
}
```

**Key fields:** `Principal` (who) · `Action` / `Resource` (ARNs) · `Condition` (e.g. `aws:SourceVpce`, `s3:prefix`). Also relevant: Lifecycle rules, Event Notification config, and CORS config are all JSON documents.


## Case A — Basic

**A1. What is Amazon S3?**
**Answer:** A highly durable, scalable **object storage** service. You store objects (files) in buckets, addressed by a unique key, accessible over HTTP/HTTPS via a global namespace.

**A2. What is a bucket and an object?**
**Answer:** A **bucket** is a container for objects (globally unique name, region-scoped). An **object** is the data file plus its metadata, identified by a **key** (the path/name) within the bucket.

**A3. What is S3's durability and availability guarantee?**
**Answer:** **11 nines durability (99.999999999%)** — designed to lose no objects — and **99.99% availability** for Standard. Durability is about not losing data; availability is about being able to access it.

**A4. What are the main S3 storage classes?**
**Answer:** Standard (frequent access), Intelligent-Tiering (auto-moves between tiers), Standard-IA (infrequent), One Zone-IA, Glacier Instant Retrieval, Glacier Flexible Retrieval, and Glacier Deep Archive (cheapest, for long-term archive).

**A5. What is versioning and why enable it?**
**Answer:** Versioning keeps every version of an object when it's overwritten or deleted. It protects against accidental deletion/overwrite and enables restore of prior versions. Once enabled, it can only be suspended, not fully disabled.

**A6. What is an S3 bucket policy vs an IAM policy?**
**Answer:** A **bucket policy** is a resource-based policy attached to the bucket controlling who/what can access it (and from where). An **IAM policy** is attached to a principal (user/role) granting permissions. Effective access = union of both (with explicit denies winning).

**A7. What does "block public access" do?**
**Answer:** A bucket/account-level setting that prevents public access regardless of bucket policies/ACLs — a guardrail against accidentally exposing data. AWS enables it by default on new buckets.

**A8. How is S3 data encrypted?**
**Answer:** Server-side: **SSE-S3** (S3-managed keys), **SSE-KMS** (KMS customer or AWS-managed keys), **SSE-C** (customer-provided keys), and **DSSE-KMS** (dual-layer). Or client-side encryption before upload.

**A9. What is a lifecycle policy?**
**Answer:** Rules that automatically transition objects to cheaper storage classes or expire/delete them based on age (e.g., move to IA after 30 days, delete after 365). They can also apply to previous versions and incomplete multipart uploads.

**A10. What is the maximum size of a single S3 object?**
**Answer:** **5 TB**. Uploads larger than 5 GB must use **multipart upload** (recommended above ~100 MB for parallelism and resilience).

**A11. What is a presigned URL?**
**Answer:** A time-limited URL that grants temporary access to an S3 object (GET/PUT) without the requester needing AWS credentials — useful for sharing downloads or direct-to-S3 uploads from browsers.

**A12. What are S3 event notifications?**
**Answer:** S3 can send events (object created/deleted/restored) to SNS, SQS, or Lambda — the backbone of serverless file-processing pipelines (e.g., image resizing on upload).

**A13. What is Cross-Region Replication (CRR) vs Same-Region Replication (SRR)?**
**Answer:** Both asynchronously copy objects (with versioning) to another bucket. **CRR** targets a different region (DR/compliance/latency), **SRR** targets the same region (log aggregation, copy to another account/tenant).

**A14. What is S3 Transfer Acceleration?**
**Answer:** Uses CloudFront edge locations to speed up uploads/downloads to S3 over long distances (optimized network path), priced per GB accelerated.

**A15. What is a static website on S3 and its limitations?**
**Answer:** You can host static sites (HTML/JS/CSS) with website hosting enabled — HTTP only (HTTPS via CloudFront). No server-side code, no PHP/DB — only static assets.

---

## Case B — Advanced (Senior)

**B1. Explain S3's consistency model (strong vs eventual) and its implications.**
**Answer:** S3 is now **strongly consistent** for all GET/PUT/LIST/DELETE operations (read-after-write, including overwrites and deletes) in all regions — no more eventual-consistency caveats. Implication: apps can safely read immediately after write; still design for idempotency and handle 404s during replication lag.

**B2. How do bucket policies, IAM policies, ACLs, and SCPs compose for access decisions?**
**Answer:** S3 evaluates the union of applicable policies: if any allows and none denies → allowed (explicit deny always wins). SCPs (org level) cap maximum permissions; bucket policies control the resource; IAM policies control the principal; ACLs (legacy) control object-level grants. Best practice: use bucket + IAM policies and disable ACLs.

**B3. When would you use SSE-S3 vs SSE-KMS vs SSE-C vs client-side encryption?**
**Answer:** SSE-S3 = simplest, S3-managed keys, no KMS cost. SSE-KMS = audit trail (CloudTrail), key rotation, per-key permissions, but KMS API costs and request throttling concerns. SSE-C = you manage keys (S3 never stores them). Client-side = encrypt before upload for maximum control (and compliance requiring data never visible to AWS). Choose by compliance, audit, and cost needs.

**B4. How does multipart upload work, and how do you handle failures/cleanup?**
**Answer:** Split the object into parts (min 5 MB, up to 10,000 parts), upload parts in parallel, then complete (S3 assembles). If aborted, parts remain and incur cost — use **lifecycle rules to abort incomplete multipart uploads** after N days, and S3 multipart upload APIs/EventBridge for tracking.

**B5. Explain S3 replication internals: requirements, what replicates, what doesn't.**
**Answer:** Requires versioning on both buckets and an IAM role. Replicates new objects and new versions (and optionally delete markers) to the destination. Doesn't replicate existing objects (use S3 Batch Replication for backfill), objects before replication was enabled, or encrypted-by-SSE-C unless configured. Replication time control (RTC) gives a 15-minute SLA for most objects.

**B6. How do you design S3 for a data lake — partitioning, formats, access?**
**Answer:** Use a partitioning scheme (e.g., `s3://lake/table/year=2026/month=09/`), columnar formats (Parquet/ORC) with compression, and query via **Athena** (SQL on S3), **Redshift Spectrum**, or EMR. Use lifecycle to tier old partitions to IA/Glacier, enable versioning + CRR for DR, and secure with bucket policies + Lake Formation.

**B7. What are S3 Access Points and Object Lambda, and why use them?**
**Answer:** **Access Points** give named, permission-scoped entry points into a shared bucket (per-application policies, per-network restrictions). **Object Lambda** runs a Lambda on each GET to transform data on the fly (e.g., redact PII, convert format) without storing a second copy.

**B8. How do you secure S3 comprehensively (CSPM-style checklist)?**
**Answer:** Block public access at account+bucket, least-privilege bucket policies, SSE (KMS for audit), versioning + MFA Delete, lifecycle for old versions, CloudTrail object-level logging, Config rules (e.g., `s3-bucket-public-read-prohibited`), Security Hub/Macie for sensitive-data detection, VPC endpoints for private access, and pre-signed URLs for temporary sharing.

**B9. How does S3 pricing work, and how do you optimize costs?**
**Answer:** Costs = storage (per GB-month, class-dependent), requests (PUT/GET/LIST per 1k), data transfer (egress out to internet is charged; transfer to same-region AWS services or via CloudFront can be free), plus features (KMS, replication, acceleration). Optimize via lifecycle tiering, Intelligent-Tiering for unknown patterns, compression, fewer small files, VPC endpoints for private egress, and CloudFront in front for repeat reads.

**B10. Compare S3 vs EBS vs EFS: when to use which?**
**Answer:** S3 = object storage, web-accessible, unlimited, cheapest, not a filesystem (no random in-place edits, no OS mount as POSIX). EBS = block storage for a single EC2 instance (like a disk). EFS = shared POSIX file system for many instances/Lambda. Use S3 for data/lakes/backups/static; EBS for OS/data volumes; EFS for shared, low-latency file workloads.

**B11. What is the difference between a DELETE and a Delete Marker in a versioned bucket?**
**Answer:** A normal DELETE in a versioned bucket inserts a **delete marker** (a new version that hides the object) rather than removing it — restoring = removing the marker. Permanently deleting requires specifying the **version ID**. This is why versioning protects against accidental deletion.

**B12. How do you monitor S3 at scale (metrics, logs, alarms)?**
**Answer:** CloudWatch metrics (BucketSizeBytes, NumberOfObjects, 4xx/5xx errors, FirstByteLatency), **S3 server access logs** (detailed per-request), **CloudTrail** (API/management events), Storage Lens (org-wide usage/activity analytics), and alarms on error rates/latency. For access anomalies use CloudTrail + GuardDuty.

---

## Case C — Scenario

**C1. Scenario:** A public-facing bucket was misconfigured and leaked customer data. The security team asks you to fix and prevent recurrence.
**Question:** What's your response plan and long-term controls?
**Expected answer:** Immediate: enable **Block Public Access** and fix the bucket policy/ACLs; identify exposure via CloudTrail/Macie; notify per incident process. Long-term: SCPs denying public buckets org-wide, Config rules + Security Hub for continuous detection, least-privilege bucket policies, encryption, and restricted access via VPC endpoints/CloudFront with OAC.

**C2. Scenario:** A nightly ETL writes 100M small files to S3; costs and LIST performance are terrible.
**Question:** Recommend optimizations.
**Expected answer:** Aggregate small files into larger objects (batching/compaction), use Parquet/ORC, partition by date/tenant, use prefix-based partitioning to speed LISTs and parallelize Athena queries, and consider S3 Express One Zone for hot, high-RPS small-object workloads. Tune the producer to buffer writes.

**C3. Scenario:** You must store 5 years of logs: rarely accessed, some queries needed within minutes, legally required retention.
**Question:** Design the storage lifecycle and access.
**Expected answer:** Standard/IA for the first 30–90 days → **Glacier Instant Retrieval** (millisecond access, cheap) → **Glacier Deep Archive** for long-term with a retention policy. Enable **versioning + MFA Delete** to prevent deletion, and optionally S3 **Object Lock** (compliance mode) if legal hold is required. Query via Athena over recent data and restore from Glacier as needed.

**C4. Scenario:** A mobile app lets users upload photos directly from the browser; you don't want uploads passing through your servers.
**Question:** How do you implement secure direct-to-S3 uploads?
**Expected answer:** Backend generates a **presigned PUT URL** (short expiry, size/content limits via conditions) for the user's object key, the browser uploads directly to S3, and an S3 event (or callback) triggers processing (thumbnail Lambda) and records metadata. Use SSE-SSE/KMS and, for larger files, consider STS temp creds with a restricted policy.

**C5. Scenario:** You need cross-account access: Account B's app must read from Account A's bucket, with Account A in control of the permissions.
**Question:** Design the two-sided setup.
**Expected answer:** Account A attaches a **bucket policy** granting `s3:GetObject`/`s3:ListBucket` to Account B's **IAM role ARN** (resource side controls). Account B attaches an IAM policy to its role allowing the same actions on the bucket (principal side). Both must allow; test with the role. Use KMS key policy sharing if objects are SSE-KMS encrypted.

**C6. Scenario:** Users on another continent complain about slow uploads/downloads to your S3 bucket.
**Question:** What options improve transfer performance?
**Expected answer:** Enable **S3 Transfer Acceleration** (edge-optimized paths) for global transfers, or put **CloudFront** in front for downloads with edge caching. For consistent big transfers, consider AWS backbone routing via Global Accelerator. Also confirm the region is close to users, use multipart uploads for large files, and enable connection reuse.
