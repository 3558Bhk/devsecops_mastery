# Amazon CloudFront — Interview Questions

> **Cloud:** AWS (Other Services) · **Category:** CDN / Edge · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

CloudFront distributions use a large **DistributionConfig** JSON (via CloudFormation `AWS::CloudFront::Distribution` or `create-distribution`).

```json
{
  "Origins": { "Items": [{
    "Id": "s3-origin",
    "DomainName": "my-bucket.s3.us-east-1.amazonaws.com",
    "S3OriginConfig": { "OriginAccessIdentity": "origin-access-identity/cloudfront/EXAMPLE" }
  }]},
  "DefaultCacheBehavior": {
    "TargetOriginId": "s3-origin",
    "ViewerProtocolPolicy": "redirect-to-https",
    "MinTTL": 0, "DefaultTTL": 86400, "MaxTTL": 31536000
  },
  "Enabled": true
}
```

**Key fields:** `Origins` · `DefaultCacheBehavior` (`TTLs`, `ViewerProtocolPolicy`, cache policy/origin-request policy IDs) · `CacheBehaviors` (path rules) · `ViewerCertificate` (TLS) · `PriceClass`. Cache policies / origin request policies are their own JSON documents.


## Case A — Basic

**A1. What is CloudFront?**
**Answer:** AWS's global **Content Delivery Network (CDN)** that caches content at edge locations to serve users with low latency, and provides TLS, DDoS protection (with Shield), and Lambda@Edge/CloudFront Functions.

**A2. What are the main components of CloudFront?**
**Answer:** **Distribution** (the CDN configuration), **origins** (where content comes from: S3, ALB, EC2, custom HTTP), **cache behaviors** (routing/caching rules per path), and **edge locations**.

**A3. What is a distribution, and what are the two types?**
**Answer:** A distribution is the CloudFront configuration for a domain. **Web distribution** (HTTP/HTTPS, the standard) and **RTMP distribution** (legacy, media streaming — deprecated).

**A4. What is an origin and what can be an origin?**
**Answer:** The source of truth where CloudFront fetches content: **S3 bucket**, **ALB**, **EC2**, **API Gateway**, **Lambda function URL**, **MediaStore**, or any **custom HTTP server**.

**A5. How does caching work in CloudFront?**
**Answer:** When a user requests content, CloudFront serves it from the nearest edge cache if present (cache hit); otherwise it fetches from the origin, stores it per the cache policy/TTL, and serves it (cache miss).

**A6. What are cache behaviors?**
**Answer:** Path-based rules (`/images/*`, `/api/*`) that define how requests are handled: which origin, cache TTL, allowed methods, headers/query-string forwarding, and viewer/response policies.

**A7. What is a cache key?**
**Answer:** The unique identifier for a cached object: typically the URL (including query strings, headers, or cookies you configure as part of the key). Two requests with the same key share a cache entry.

**A8. What is TTL in CloudFront?**
**Answer:** Time-to-live for cached objects — minimum, default, and maximum TTL, possibly overridden by `Cache-Control`/`Expires` headers from the origin.

**A9. What is cache invalidation?**
**Answer:** Explicitly removing objects from edge caches (by path or wildcard) before TTL expiry — used after deploys to push fresh content.

**A10. What is an OAI vs OAC?**
**Answer:** **Origin Access Identity** (legacy) and **Origin Access Control** (current) are identity mechanisms that let CloudFront access a **private S3 bucket** without making it public. OAC is the recommended, more granular approach.

**A11. What is a signed URL vs signed cookie?**
**Answer:** Mechanisms to serve **private content**: signed URLs grant access to a single object; signed cookies grant access to multiple objects (e.g., a whole video library) after one authentication.

**A12. What are Lambda@Edge and CloudFront Functions?**
**Answer:** Edge-compute options: CloudFront Functions (lightweight JS, viewer request/response, sub-ms) and Lambda@Edge (full Node/Python, all 4 event hooks, regional replicas) for header manipulation, auth, redirects, and rewrites.

**A13. How does CloudFront help with TLS?**
**Answer:** It terminates HTTPS with ACM certificates (or custom), supports HTTP→HTTPS redirect, HTTP/2/3, and TLS 1.2/1.3, and can enforce a minimum TLS version.

**A14. What is a geo restriction?**
**Answer:** CloudFront can allow/block access by country (via a geo-restriction list) — or use a CloudFront Function for more precise logic.

**A15. What is the difference between CloudFront and Global Accelerator?**
**Answer:** CloudFront **caches content** at the edge (HTTP/S CDN). Global Accelerator does **no caching** — it optimizes the network path (static IPs + backbone) for any TCP/UDP application.

---

## Case B — Advanced (Senior)

**B1. Explain a request's journey through CloudFront (viewer → edge → regional cache → origin).**
**Answer:** Viewer → nearest **edge location** (POP). On cache miss, the request goes to a **regional edge cache** (a mid-tier cache), then to the **origin**. CloudFront then caches along the path. Understanding this hierarchy explains why invalidations and origin load behave as they do.

**B2. What is a cache policy and an origin request policy?**
**Answer:** A **cache policy** defines what's included in the cache key (headers, cookies, query strings) and TTLs. An **origin request policy** defines what headers/cookies/query strings are **forwarded to the origin** when there's a miss. Separating these lets you cache aggressively while still sending needed context to the origin.

**B3. How do you secure an S3 origin properly (private bucket + OAC)?**
**Answer:** Keep the bucket **private**, create an **OAC**, attach it to the distribution with the bucket as origin, and add a **bucket policy** granting the OAC (`cloudfront` service principal) `s3:GetObject`. This ensures objects are only reachable via CloudFront — never directly from S3.

**B4. How does cache invalidation differ from versioned URLs (cache busting), and which is better?**
**Answer:** Invalidation purges specific paths (costly, limited free invalidation paths, takes time to propagate). **Versioned/cache-busted URLs** (`/app.v2.js`) avoid invalidation entirely — new URL = new cache key = instant deployment. Prefer versioning for assets; use invalidation for rare full-site changes.

**B5. How do you implement signed URLs/cookies with CloudFront (trusted key groups)?**
**Answer:** Create a **public/private key pair** (or trusted key group), enable "Restrict Viewer Access" on the behavior, and sign the URL/cookie with the private key (AWS SDK or custom code) with an expiry and optional IP/path policy. CloudFront validates the signature at the edge before serving.

**B6. Compare CloudFront Functions vs Lambda@Edge — capabilities, latency, and use cases.**
**Answer:** CloudFront Functions: lightweight JS, run at viewer request/response, ~sub-ms, cheap, great for header manipulation, URL rewrites, simple auth checks. Lambda@Edge: full Node/Python runtime, all 4 hooks (viewer + origin request/response), can call external services, higher latency/cost — use for complex logic, dynamic content generation, or origin-side processing.

**B7. How do you design CloudFront for a dynamic application behind an ALB (cache + security)?**
**Answer:** Put CloudFront in front of the ALB: cache static paths (`/static/*`) with long TTL, forward dynamic paths (`/api/*`) with no caching (or short TTL), attach **AWS WAF** to the distribution, use **managed origin request policies** to forward the right headers (Host, client IP via CloudFront headers), and restrict the ALB's SG to CloudFront's IP ranges (or use an OAC-like header secret).

**B8. What is origin shield and when does it help?**
**Answer:** An optional **centralized caching layer** between edge POPs and the origin, reducing the number of requests hitting the origin (aggregating misses from many edges) and improving cache-hit ratio. Use it for expensive/rate-limited origins.

**B9. How do you handle custom error pages and origin failover in CloudFront?**
**Answer:** Configure **custom error responses** (e.g., serve `/404.html` with 200/404) per error code. For failover, use **origin groups** (primary + secondary origin) so CloudFront automatically fails over to the secondary on origin errors — good for S3 multi-region DR.

**B10. What are CloudFront's security integrations (WAF, Shield, field-level encryption)?**
**Answer:** **AWS WAF** attaches to distributions (SQLi/XSS/bot/IP rules). **Shield Standard** (free DDoS) and **Shield Advanced** (enhanced DDoS + cost protection) protect the edge. **Field-level encryption** encrypts sensitive form fields end-to-end. CloudFront also supports TLS policies, geo-restriction, and OAC for origin security.

**B11. How does CloudFront integrate with Lambda@Edge for A/B testing and personalization?**
**Answer:** Use a **viewer-request** Lambda@Edge function to read a cookie/header, select a variant, and rewrite the URI or set headers (`/index-a.html` vs `/index-b.html`) or route to different origins — enabling A/B tests and personalization at the edge without app changes.

**B12. What are the costs and limits to consider with CloudFront at scale?**
**Answer:** Costs: data transfer out (tiered by region), requests (HTTP/HTTPS), invalidation (first 1,000 paths free), Lambda@Edge/CloudFront Functions invocations, and optional features (OAC is free; Shield Advanced, real-time logs, field-level encryption cost extra). Limits: distributions per account, cache behavior counts, request/response size limits (default 10 GB per request? — verify current), and Lambda@Edge limits.

---

## Case C — Scenario

**C1. Scenario:** A static SPA on S3 must be served over HTTPS globally with custom domain `app.example.com`.
**Question:** Design the setup.
**Expected answer:** Create a CloudFront distribution with the S3 bucket as origin, secure via **OAC + bucket policy** (bucket stays private), attach an **ACM certificate** for `app.example.com` (must be in us-east-1 for CloudFront), add a Route 53 **Alias record** `app.example.com` → the distribution domain, and configure the default root object + a 404→index.html custom error response for SPA routing.

**C2. Scenario:** Users in India experience slow image loads; your origin S3 bucket is in us-east-1.
**Question:** Why, and how does CloudFront fix it?
**Answer:** Users fetch from a distant bucket over the public internet. CloudFront caches images at nearby **edge locations** (e.g., Mumbai/Chennai), serving them from the edge on cache hits — cutting latency dramatically. Enable compression, set appropriate TTLs, and warm the cache if needed.

**C3. Scenario:** After a deploy, users still see old JS/CSS for hours despite the new build being in S3.
**Question:** Diagnose and fix.
**Expected answer:** The old assets are still cached at edges under their old cache keys until TTL expiry. Fix: (1) **invalidate** the changed paths (or `/*`), or (2) better — use **versioned filenames** (`app.abc123.js`) so each deploy has a new cache key (no invalidation needed). Also set long TTL for immutable assets.

**C4. Scenario:** A private video library must be accessible only to logged-in paying users.
**Question:** Design access control.
**Expected answer:** Serve videos via CloudFront with **signed cookies** (or signed URLs) using a **trusted key group**. The app authenticates the user, then issues a signed cookie (with expiry + optional path policy) so their browser can stream multiple files. Without a valid signature, CloudFront returns 403.

**C5. Scenario:** An attacker is hammering your CloudFront distribution with bots; costs and origin load spiked.
**Question:** How do you mitigate?
**Expected answer:** Attach **AWS WAF** with managed rules (AWSManagedRulesBotControl, rate-based rules, IP reputation) to the distribution, enable **Shield Advanced** if under DDoS, add geo-restriction if appropriate, and use CloudFront's caching to absorb reads (protecting the origin). Monitor with WAF logs + CloudFront metrics.

**C6. Scenario:** You need the client's real IP on your ALB backend, but logs show CloudFront IPs.
**Question:** How do you preserve client IPs?
**Answer:** CloudFront adds headers like **`X-Forwarded-For`** (client IP chain) and `CloudFront-Viewer-*` headers. Configure the ALB/backend to read `X-Forwarded-For` (first hop) or the CloudFront headers, and use a **managed origin request policy** that forwards these headers to the origin. Optionally restrict the ALB SG to CloudFront IP ranges and use a shared secret header for direct-access protection.
