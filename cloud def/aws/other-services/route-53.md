# Amazon Route 53 — Interview Questions

> **Cloud:** AWS (Other Services) · **Category:** Networking / DNS · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~8 min

---

## JSON File Format

Route 53 records are JSON in CloudFormation (`AWS::Route53::RecordSet`) and via `change-resource-record-sets` (a `ChangeBatch` JSON with `Action: UPSERT/DELETE`).

```json
{
  "Type": "AWS::Route53::RecordSet",
  "Properties": {
    "HostedZoneId": "Z123456",
    "Name": "app.example.com.",
    "Type": "A",
    "AliasTarget": {
      "HostedZoneId": "Z35SXDOTRQ7X7K",
      "DNSName": "my-alb-123.us-east-1.elb.amazonaws.com"
    }
  }
}
```

**Key fields:** `Name` + `Type` (A/CNAME/MX/TXT…) · `TTL` (plain records) vs `AliasTarget` (AWS resources — free + apex-capable) · routing-policy fields: `SetIdentifier`, `Weight`, `Region`, `GeoLocation`, `Failover` (PRIMARY/SECONDARY), `HealthCheckId`.


## Case A — Basic

**A1. What is Route 53?**
**Answer:** AWS's scalable, highly available **DNS** web service (and domain registrar). It translates domain names to IP addresses and supports health checks and traffic routing policies.

**A2. What is a hosted zone?**
**Answer:** A container for DNS records of a domain. **Public hosted zone** = resolves on the internet; **private hosted zone** = resolves only within your VPC(s).

**A3. What are the main record types you use?**
**Answer:** **A** (IPv4), **AAAA** (IPv6), **CNAME** (alias to another domain name), **Alias** (AWS-specific, free, points to AWS resources like ALB/CloudFront/S3), **MX** (mail), **TXT**, **NS**, **SRV**.

**A4. What is an Alias record and how does it differ from a CNAME?**
**Answer:** An Alias is an AWS-specific record that maps a name to an AWS resource (ALB, CloudFront, S3 website, etc.) at **no charge**, and it works for the **apex/root domain** (CNAME cannot be used at the apex). It also auto-tracks resource changes.

**A5. What are the main routing policies?**
**Answer:** Simple, Weighted, Latency-based, Failover, Geolocation, Geoproximity, and Multivalue answer.

**A6. What is a simple routing policy?**
**Answer:** One record with possibly multiple values, returned in random order to clients. No health checks or traffic shaping.

**A7. What is weighted routing?**
**Answer:** Distributing traffic across resources by assigned weights (e.g., 80/20 split for canary testing or A/B).

**A8. What is latency-based routing?**
**Answer:** Routes users to the AWS region with the **lowest latency** for them, based on live latency measurements.

**A9. What is failover routing?**
**Answer:** Primary/secondary records with a **health check**; traffic goes to primary while healthy, else to secondary.

**A10. What is geolocation vs geoproximity routing?**
**Answer:** Geolocation routes based on the **user's location** (country/continent) to mapped endpoints. Geoproximity routes based on **geographic distance** to resources, with a "bias" to shift traffic.

**A11. What are Route 53 health checks?**
**Answer:** Monitors that test endpoint health (HTTP/HTTPS/TCP) or monitor other health checks (calculated) and CloudWatch alarms, feeding failover/DNS decisions.

**A12. What is TTL and why does it matter?**
**Answer:** Time-to-live: how long resolvers cache a record. Lower TTL = faster changes but more queries/cost; higher TTL = cheaper but slower failover (clients cache old IPs).

**A13. Can Route 53 register domains?**
**Answer:** Yes — it's also a **domain registrar** (buy/transfer domains), with automatic hosted zone creation.

**A14. What is a resolver endpoint?**
**Answer:** Route 53 Resolver endpoints (**inbound**: on-prem → VPC DNS resolution; **outbound**: VPC → on-prem DNS) enable hybrid DNS between your VPC and data center.

**A15. What is DNSSEC?**
**Answer:** Domain Name System Security Extensions — digitally signs DNS records so resolvers can verify authenticity (prevent spoofing/cache poisoning). Supported in Route 53.

---

## Case B — Advanced (Senior)

**B1. Explain how Route 53 achieves global scale and low latency (anycast, distributed resolvers).**
**Answer:** Route 53 uses a global network of **anycast DNS servers** — the same IPs are announced from many edge locations, so queries hit the nearest resolver. Combined with health checks and latency-aware answers, it gives fast, resilient resolution worldwide.

**B2. When do you use an Alias vs a CNAME, and what's the "apex" problem?**
**Answer:** CNAMEs can't exist at the zone apex (`example.com`), per DNS RFCs. Alias records solve apex pointing to AWS resources (ALB, CloudFront, S3, etc.) for free and are AWS-native. Use CNAME for non-apex names or external targets; Alias for AWS resources and apex.

**B3. How does failover routing with health checks actually fail over, and what are its latency characteristics?**
**Answer:** Route 53 health checkers (globally distributed) test the endpoint; if the primary fails N consecutive checks, Route 53 stops returning it and serves the secondary. Convergence depends on **TTL** — clients with cached records still use the old IP until TTL expires. Lower TTL (or Global Accelerator) reduces failover time.

**B4. How do you design multi-region active-active DNS with weighted + latency routing?**
**Answer:** Use **latency-based routing** across regional ALBs as the default (users → nearest region), optionally layered with **weighted** records for region-level traffic shifts, and **health checks** so unhealthy regions drop out. Combine with Global Accelerator for static IPs + backbone routing + instant failover if needed.

**B5. What is the difference between multivalue answer and a simple record with multiple values?**
**Answer:** Simple returns multiple IPs randomly with no health awareness. **Multivalue answer** returns up to 8 **healthy** IPs (each backed by a health check) — giving client-side load balancing with health filtering, but not ELB-style load balancing.

**B6. How does a private hosted zone work, and how do you share it across accounts/VPCs?**
**Answer:** It resolves only inside associated VPCs (requires `enableDnsSupport`/`enableDnsHostnames`). Share across VPCs/accounts via **Route 53 Resolver** rules or by associating the VPCs with the hosted zone (same account) / using **RAM** to share with other accounts.

**B7. Explain hybrid DNS with Resolver endpoints (inbound + outbound) and forwarding rules.**
**Answer:** **Inbound endpoint** lets on-prem resolvers forward queries to the VPC (to resolve AWS private names). **Outbound endpoint** + **forwarding rules** let VPC instances resolve on-prem domain names via your on-prem DNS servers. Together they give bidirectional hybrid DNS over Direct Connect/VPN.

**B8. How do you implement blue-green deployments at the DNS layer with weighted routing?**
**Answer:** Create records for old (weight 100) and new (weight 0) environments; ramp the new weight up gradually while monitoring error rates/latency; roll back by shifting weights. Use short TTLs during cutover. Note: DNS-based shifts are coarse (client caching) — for precise control use ALB weighted target groups instead.

**B9. What is Route 53 Traffic Flow, and when is it useful?**
**Answer:** A visual editor for complex routing trees (combining geo + latency + weighted + failover into one policy) exported as a **Traffic Policy**. Useful for sophisticated multi-region, multi-tenant routing logic that single records can't express.

**B10. How do you monitor Route 53 health checks and DNS query metrics?**
**Answer:** Route 53 publishes CloudWatch metrics: `HealthCheckStatus`, `HealthCheckPercentageHealthy`, `DNSQueries` (query volume per zone/record). Alarm on health check degradation and set calculated health checks that aggregate child checks (e.g., fail over only if 2 of 3 regions are down).

**B11. What are the security considerations for Route 53 (DNSSEC, access, registry locks)?**
**Answer:** Enable **DNSSEC** signing for zones, restrict `route53` API access with IAM least privilege, use **domain transfer lock**/registrar security, monitor for **domain hijacking** (unauthorized NS/hosted-zone changes via CloudTrail), and use private hosted zones so internal records never leak publicly.

**B12. Compare Route 53 vs CloudFront vs Global Accelerator for "global routing."**
**Answer:** Route 53 = DNS-level steering (latency/geo/failover) but subject to DNS caching and doesn't change the network path. CloudFront = edge caching CDN for HTTP content. Global Accelerator = static anycast IPs + AWS backbone routing + health-based failover for TCP/UDP (no DNS dependency). They often compose: Route 53 → CloudFront/GA.

---

## Case C — Scenario

**C1. Scenario:** After a region outage, some users couldn't reach the app for 15 minutes even though failover DNS was configured.
**Question:** Explain and improve.
**Expected answer:** DNS failover is limited by **TTL and client/resolver caching** — users kept the old IP until the record expired. Improve: lower TTL (tradeoff: more queries), use health checks with faster thresholds, and adopt **Global Accelerator** (static IPs, instant failover) or keep multi-region active-active so both IPs are always valid.

**C2. Scenario:** You must route EU users to the EU app and US users to the US app, with automatic failover between them.
**Question:** Which routing policy(ies) and health checks?
**Expected answer:** Use **geolocation routing** (EU → EU ALB, US → US ALB) with **health checks** on each endpoint; add a secondary/failover record per location (or use Traffic Flow to layer geolocation + failover) so if a region is unhealthy, users route to the healthy region.

**C3. Scenario:** An internal app needs a friendly name (`db.internal`) that resolves to an RDS endpoint only inside the VPC, not on the internet.
**Question:** How do you set it up?
**Expected answer:** Create a **private hosted zone** (`internal`) associated with the VPC, and add an **Alias/CNAME record** `db.internal` → RDS endpoint. Ensure `enableDnsSupport`/`enableDnsHostnames` are on. On-prem users can resolve it via a **Resolver inbound endpoint**.

**C4. Scenario:** A canary release: send 5% of users to a new version and roll back quickly if errors spike.
**Question:** DNS approach + its caveat + a better alternative?
**Expected answer:** **Weighted routing** (95 old / 5 new) with health checks and short TTL. Caveat: DNS weighting is approximate (resolver caching, uneven client distribution). Better for precise canary: **ALB weighted target groups** or CloudFront with Lambda@Edge — DNS is a blunt instrument for canaries.

**C5. Scenario:** Users in India get routed to a US endpoint even though an ap-south-1 endpoint exists.
**Question:** Diagnose.
**Expected answer:** Check the routing policy: if **latency-based**, Route 53 routes by measured latency (some clients may genuinely measure faster to the US). If **geolocation**, verify the record's location mapping (country/continent vs default record) — a default (`*`) record may be catching them. Also check the client's resolver uses EDNS0 client-subnet (without it, latency routing uses the resolver's location, not the user's).

**C6. Scenario:** You suspect your domain was hijacked — DNS now points to an attacker's server.
**Question:** What do you check and how do you recover + prevent?
**Answer:** Check CloudTrail for unauthorized `ChangeResourceRecordSets`/hosted-zone/NS changes and registrar transfer logs; immediately restore correct NS/records, rotate any compromised credentials, and enable MFA on the root/registrar. Prevent: **DNSSEC**, registrar **transfer lock**, least-privilege Route 53 IAM, and CloudTrail alerts on DNS changes.
