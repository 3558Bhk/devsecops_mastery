# Terraform Route 53 & CloudFront (AWS) — Interview Questions

> **Cloud:** AWS · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~6 min

---

## Case A — Basic

**A1. What is Route 53 in Terraform terms?**
**Answer:** AWS's DNS + domain service, managed via `aws_route53_zone` (hosted zones), `aws_route53_record` (records), and optionally `aws_route53_health_check`.

**A2. How do you create a hosted zone?**
**Answer:** `resource "aws_route53_zone" "main" { name = "example.com" }` — a public zone; add `vpc { vpc_id = ... }` blocks for private zones.

**A3. What is a record and how do you create an A record?**
**Answer:** `resource "aws_route53_record" "www" { zone_id = ... ; name = "www.example.com" ; type = "A" ; ttl = 300 ; records = ["1.2.3.4"] }`.

**A4. What is an alias record and why use it?**
**Answer:** An alias points to an AWS resource (ALB, CloudFront, S3) natively, using `alias { name, zone_id, evaluate_target_health }` instead of `records`/`ttl`, and it's free for queries to AWS endpoints.

**A5. How do you point a domain at an ALB?**
**Answer:** Alias record: `alias { name = aws_lb.web.dns_name ; zone_id = aws_lb.web.zone_id ; evaluate_target_health = true }`.

**A6. What is CloudFront in Terraform?**
**Answer:** AWS's CDN, managed via `aws_cloudfront_distribution` with an origin (S3/ALB/custom), cache behaviors, and optional WAF association.

**A7. What does a minimal CloudFront distribution need?**
**Answer:** `enabled`, `origin` (domain_name, origin_id), a `default_cache_behavior` (target_origin_id, viewer_protocol_policy, allowed_methods), `viewer_certificate`, and `restrictions`.

**A8. What is an origin access control (OAC)?**
**Answer:** `aws_cloudfront_origin_access_control` lets CloudFront access a private S3 bucket via SigV4, replacing legacy Origin Access Identity (OAI).

**A9. What is an ACM certificate and how do you validate it?**
**Answer:** `aws_acm_certificate` + `aws_acm_certificate_validation` (DNS validation creating Route 53 records) to issue a TLS cert for your domain before attaching to CloudFront/ALB.

**A10. Why must ACM certs for CloudFront be in us-east-1?**
**Answer:** CloudFront edge locations only accept certificates from us-east-1, so create the cert with an aliased `aws` provider pinned to `us-east-1`.

**A11. What is a record's `ttl`?**
**Answer:** Time-to-live in seconds that resolvers cache the record. Alias records don't use a user-set TTL.

**A12. What is a private hosted zone?**
**Answer:** A zone resolving only inside the VPCs you associate (`vpc` blocks), for internal DNS like `app.internal`.

**A13. How do you add an S3 bucket as a CloudFront origin?**
**Answer:** Point the origin `domain_name` at the bucket's regional endpoint, set `origin_access_control_id` for private buckets, and add a bucket policy allowing the OAC to read.

**A14. What is `aws_route53_health_check`?**
**Answer:** A health check resource used with failover routing policies to decide which records serve traffic.

**A15. What does `aws_route53_record` with `type = "CNAME"` require?**
**Answer:** A canonical name target (e.g. the CloudFront domain), and it can't be used at the zone apex (use an alias there instead).

## Case B — Advanced / Senior

**B1. How do you register a domain and wire it end-to-end with Terraform?**
**Answer:** `aws_route53domains_registered_domain` (or manual registration), create the hosted zone, get its name servers, then create records. For apex + www, use alias records to the LB/CloudFront.

**B2. Explain routing policies available in Route 53.**
**Answer:** Simple, weighted, latency, geolocation, geoproximity, failover, and multivalue. Each maps to `aws_route53_record` config (e.g. `weighted_routing_policy`, `failover_routing_policy`).

**B3. How do you implement blue-green DNS with Route 53?**
**Answer:** Weighted routing: two records for the same name with weights 100/0 (or 90/10), and adjust weights to shift traffic, optionally with health checks so unhealthy endpoints are excluded.

**B4. What is the CloudFront `viewer_certificate` configuration?**
**Answer:** It sets TLS at the edge — `acm_certificate_arn` + `ssl_support_method = "sni-only"` (required for custom domains), and `minimum_protocol_version` for security.

**B5. How do you add a custom domain to CloudFront with Terraform?**
**Answer:** Create the ACM cert in us-east-1, add `aliases` to the distribution, set `viewer_certificate`, then create a Route 53 alias record pointing to the distribution's domain name and hosted zone id.

**B6. What is cache invalidation in Terraform?**
**Answer:** `aws_cloudfront_invalidation` invalidates paths after deploy. It's not tracked for diffs well (runs on change), so many teams trigger it in CI after apply rather than managing it as a persistent resource.

**B7. How do you secure S3 behind CloudFront?**
**Answer:** Keep the bucket private, use an OAC so CloudFront can read it, and attach a bucket policy granting the OAC (service principal `cloudfront.amazonaws.com`) `s3:GetObject`. Never make the bucket public.

**B8. What is a cache behavior and how do you route /api to an origin?**
**Answer:** `ordered_cache_behavior` blocks route path patterns to different origins, e.g. `/api/*` → ALB origin, `/*` → S3 origin, each with its own TTL and policies.

**B9. What is origin failover in CloudFront?**
**Answer:** An `origin_group` with primary + secondary origins and failover criteria, so CloudFront retries the secondary when the primary fails.

**B10. How do you attach WAF to CloudFront?**
**Answer:** `aws_wafv2_web_acl` with `scope = "CLOUDFRONT"` created in us-east-1, referenced by the distribution's `web_acl_id`.

**B11. How do you import an existing hosted zone and its records?**
**Answer:** Import the zone with `terraform import aws_route53_zone.main Z12345`, then import/define the records you manage. Records AWS added outside Terraform stay managed separately.

**B12. What are the pitfalls of managing DNS with Terraform?**
**Answer:** It's easy to destroy records accidentally (always review plan), TTLs delay propagation, and name-server changes for registered domains are one-way-ish — keep domain registration and zone management separated from day-to-day resource changes.

## Case C — Scenario

**C1. Your site is down because the DNS record points to a deleted ALB.**
**Answer:** Recreate the ALB (or roll back to a previous config/state version), then ensure the alias record references the ALB's current zone_id/name. Prevent this by keeping DNS and LB in the same state, or using `prevent_destroy`.

**C2. You need to serve a static SPA from S3 over HTTPS at your apex domain.**
**Answer:** Private S3 bucket → CloudFront distribution (OAC + bucket policy, aliases for `example.com`), ACM cert in us-east-1 attached to the distribution, and a Route 53 alias record at the apex pointing to CloudFront.

**C3. Content updates aren't showing after deploy.**
**Answer:** CloudFront cached the old objects. Create an `aws_cloudfront_invalidation` (or CI-triggered invalidation) for changed paths, and consider cache-busting filenames or shorter TTLs for HTML.

**C4. You want to fail over to a standby region if the primary endpoint's health check fails.**
**Answer:** Two endpoints, an `aws_route53_health_check` on the primary, and failover routing with primary/secondary records — Route 53 shifts traffic to the secondary when the primary is unhealthy.

**C5. A compliance check flags that CloudFront serves HTTP (not HTTPS-only).**
**Answer:** Set `viewer_protocol_policy = "redirect-to-https"` on the cache behavior and `minimum_protocol_version` appropriately, then re-apply. Add a policy-as-code rule to keep it that way.

**C6. You're migrating DNS from a third-party registrar into Route 53.**
**Answer:** Create the hosted zone, copy all records, update the registrar's name servers to Route 53's, verify with dig, then keep the registrar or transfer the domain. Do it incrementally with low TTLs to minimize downtime.
