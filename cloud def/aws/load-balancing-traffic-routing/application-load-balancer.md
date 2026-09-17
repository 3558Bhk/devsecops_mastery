# Application Load Balancer (ALB) — Interview Questions

> **Cloud:** AWS · **Category:** Load Balancing & Traffic Routing · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

ALB listener rules and target groups are JSON in CloudFormation (`AWS::ElasticLoadBalancingV2::ListenerRule`, `AWS::ElasticLoadBalancingV2::TargetGroup`). The rule **conditions/actions** JSON is the interesting part.

```json
{
  "Type": "AWS::ElasticLoadBalancingV2::ListenerRule",
  "Properties": {
    "ListenerArn": "arn:aws:elasticloadbalancing:us-east-1:111122223333:listener/app/my-alb/abc/def",
    "Priority": 10,
    "Conditions": [{ "Field": "path-pattern", "Values": ["/api/*"] }],
    "Actions": [{ "Type": "forward", "TargetGroupArn": "arn:aws:elasticloadbalancing:...:targetgroup/api/xyz" }]
  }
}
```

**Key fields:** `Conditions` (path-pattern, host-header, http-header, query-string, source-ip, http-request-method) · `Actions` (forward, redirect, fixed-response, authenticate-oidc/cognito) · `Priority` (lower = evaluated first).


## Case A — Basic

**A1. What is an Application Load Balancer?**
**Answer:** A Layer 7 (HTTP/HTTPS) load balancer that routes traffic to targets (EC2, containers, Lambda, IPs) based on request content — host headers, paths, query strings, headers, and methods. It is best suited for web applications, APIs, and microservices.

**A2. What OSI layer does an ALB operate at?**
**Answer:** Layer 7 (application layer). It can inspect HTTP/HTTPS request content to make routing decisions, unlike an NLB (Layer 4).

**A3. What are the main components of an ALB?**
**Answer:** Listener (protocol+port, e.g., HTTPS 443), rules (conditions + actions), target groups (logical grouping of targets with health checks), and targets (EC2, ECS tasks, Lambda, IP addresses).

**A4. What is a Target Group?**
**Answer:** A logical grouping of targets that receive traffic from a listener rule. Each target group has its own health check, port, protocol, and routing settings.

**A5. How does an ALB decide where to send a request?**
**Answer:** Listeners evaluate rules in priority order. A rule's conditions (e.g., path `/api/*`, host `api.example.com`) are checked; the first match forwards to the target group (or performs a redirect/fixed response).

**A6. What target types does an ALB support?**
**Answer:** **Instance** (EC2), **IP** (any private IPs — ECS Fargate, on-prem, other VPCs), and **Lambda** functions.

**A7. What is a health check and why is it needed?**
**Answer:** The ALB periodically sends requests (e.g., `GET /health` on port 80/8080) to targets to determine health. Only healthy targets receive traffic; unhealthy ones are marked out-of-service until they recover.

**A8. What is the difference between ALB and NLB?**
**Answer:** ALB is Layer 7 (content-based routing, WebSocket, TLS offload, WAF). NLB is Layer 4 (ultra-high performance, static IPs, TCP/UDP/TLS, lowest latency). Choose ALB for HTTP apps; NLB for raw TCP/TLS or extreme throughput.

**A9. Can an ALB route to targets on multiple ports?**
**Answer:** Yes — different target groups (or target-group port overrides) can map to different backend ports. E.g., listener 443 → target group on 8080; another rule → target group on 9090.

**A10. Does an ALB have a static IP?**
**Answer:** No. ALBs use a DNS name that resolves to changing IPs. (Use an NLB or Global Accelerator if you need static IPs.)

**A11. What is "sticky sessions" (session affinity)?**
**Answer:** The ALB can stick a client to a specific target using a cookie (application-based or duration-based). Useful when the app keeps session state on the instance; generally avoided with stateless apps.

**A12. What is SNI support on an ALB?**
**Answer:** Server Name Indication lets the ALB present different TLS certificates for different hostnames on the same listener (e.g., multiple sites on one HTTPS listener).

**A13. Can an ALB do TLS/SSL termination?**
**Answer:** Yes. You attach an ACM (or imported) certificate and the ALB terminates TLS, then forwards plain HTTP (or re-encrypts) to targets — offloading certificate management from instances.

**A14. What is the "slow start" feature?**
**Answer:** Newly registered targets ramp up gradually to avoid being flooded before they're warmed up (e.g., after scaling events or instance launch).

**A15. How is an ALB made highly available?**
**Answer:** You enable it in **at least two AZs**; AWS provisions nodes in each AZ, and the DNS name resolves across them. An ALB spans AZs but is **regional**, not global.

---

## Case B — Advanced (Senior)

**B1. Explain how ALB listeners, rules, conditions, and actions compose, and the rule priority semantics.**
**Answer:** A listener receives traffic on a protocol/port. Rules (default rule = last priority) have conditions (host-header, path-pattern, http-header, query-string, source-ip, method) and actions (forward, redirect, fixed-response, authenticate-oidc/cognito, weighted-target-groups). Rules evaluate top-down by priority; the first match wins. The default rule catches everything else — understanding this ordering is essential to debugging routing.

**B2. How does ALB handle WebSockets and HTTP/2?**
**Answer:** ALB natively supports WebSocket upgrades (long-lived connections are kept between client and target) and HTTP/2 and gRPC (via HTTP/2). For gRPC you use an HTTPS listener with an HTTP/2 target group protocol version.

**B3. What are "weighted target groups" and when would you use them?**
**Answer:** A listener rule can forward to **multiple target groups with weights** (e.g., 90% old version, 10% new version). This enables canary/blue-green releases at the routing layer without separate ALBs or DNS changes.

**B4. How does ALB security differ from NLB, and where does AWS WAF fit?**
**Answer:** ALB integrates with **AWS WAF** (web ACLs) for SQL injection, XSS, bot, and IP rules at Layer 7 — NLB does not support WAF directly (you'd put an ALB behind it or use Network Firewall). ALB also supports security groups, authentication (Cognito/OIDC), and mTLS (newer feature); NLB has SG support but no WAF/content inspection.

**B5. Explain the ALB→target connection model: how does the ALB rewrite headers, and why is X-Forwarded-For important?**
**Answer:** The ALB terminates the client connection and opens a new connection to the target, rewriting the source IP. It injects headers like `X-Forwarded-For` (client IP), `X-Forwarded-Proto`, and `X-Forwarded-Port` so the backend can log the real client and scheme. Apps must trust these headers (and not trust raw socket IP) for correct logging/geo/security.

**B6. How do you design an ALB for a private/internal application vs a public one?**
**Answer:** Internal ALB: **scheme = internal**, no public IPs, DNS resolves to private IPs, accessible only within the VPC (or via VPC peering/TGW/DX/PrivateLink). Public: internet-facing with a security group allowing 80/443 from needed sources. Internal ALBs are used for service-to-service traffic and by PrivateLink endpoint services.

**B7. What are the common causes of ALB 5xx errors, and how do you distinguish ALB vs target errors?**
**Answer:** 502 = target returned malformed response/closed connection; 503 = no healthy targets or capacity issues; 504 = target response timeout (gateway timeout — increase idle/target timeout or fix slow backend). ALB-generated 5xx vs target 5xx are distinguishable in access logs and CloudWatch (`HTTPCode_ELB_5XX_Count` vs `HTTPCode_Target_5XX_Count`).

**B8. How do ALB access logs and request tracing work?**
**Answer:** Enable access logs to S3 (they include request details, latencies, and the target that served it). ALB also injects `X-Amzn-Trace-Id` and can propagate AWS X-Ray tracing headers to give end-to-end request traces through ALB → targets.

**B9. How does ALB scale, and what is the "pre-warming" concept?**
**Answer:** ALB scales automatically based on traffic, but very rapid, massive traffic spikes (e.g., from zero to millions of RPS, or during launches/load tests) can exceed short-term capacity. AWS recommends requesting **pre-warming** (via support) for known big events. Design for gradual ramp and enable multi-AZ.

**B10. Compare ALB vs API Gateway vs CloudFront for exposing an HTTP API.**
**Answer:** ALB = L7 routing/load balancing within a region, cheapest per request at scale, WAF support, no auth/API-key/throttling features. API Gateway = API management (auth, keys, throttling, stages, REST/WebSocket) but higher per-request cost. CloudFront = global CDN/edge cache + WAF + edge security. They often compose: CloudFront → API GW or CloudFront → ALB.

**B11. How does deregistration delay / connection draining work on an ALB?**
**Answer:** When a target is deregistered (or fails health checks), the ALB stops new connections and lets in-flight requests finish up to the **deregistration delay** (default 300s) before closing. This enables graceful scaling-in and deployments without dropping active requests.

**B12. What considerations apply when using ALB with Lambda targets?**
**Answer:** ALB forwards to Lambda with a payload limit (~1 MB requests / ~1 MB responses), uses synchronous invocation, supports multi-value headers, and the Lambda doesn't need VPC connectivity to be a target (ALB handles the network). Timeouts must account for ALB's max idle timeout. Path/method routing works the same as other targets.

---

## Case C — Scenario

**C1. Scenario:** You're migrating a monolith to microservices behind one public domain: `/api/users/*` → user service, `/api/orders/*` → order service, everything else → the SPA.
**Question:** Design the ALB configuration.
**Expected answer:** One ALB with an HTTPS listener. Rules by path: `/api/users/*` → users target group; `/api/orders/*` → orders target group; default rule → SPA target group. Enable health checks per target group, TLS via ACM, WAF web ACL, and access logs. Use priority so path rules precede the default.

**C2. Scenario:** During a deployment, some users hit 502s while instances are replaced one at a time.
**Question:** Why, and how do you make deploys zero-downtime?
**Expected answer:** 502s occur when a target is deregistered/terminated while still receiving connections, or when the new instance's health check hasn't passed yet. Fix: use **connection draining** (deregistration delay), health checks with proper thresholds, and rolling/blue-green deploy (register new instances first, then deregister old), plus retry logic client-side.

**C3. Scenario:** Your backend must know the real client IP for fraud checks, but logs show the ALB's private IP for every request.
**Question:** Explain and fix.
**Expected answer:** The ALB terminates and re-originates connections, so the socket source is the ALB. Fix: read **X-Forwarded-For** (and X-Forwarded-Proto/Port) on the backend, and configure the web server/proxy to trust the ALB and use these headers for logging. Never trust client-supplied XFF without sanitizing.

**C4. Scenario:** A load test shows the ALB returning 503s even though most EC2 targets look healthy and CPU is fine.
**Question:** What could be wrong?
**Expected answer:** 503 = no healthy targets *or* ALB capacity/surge issues. Check: (1) health checks actually passing for all targets (wrong path/port → all unhealthy), (2) targets' SG allowing ALB subnet traffic on the target port, (3) target group has targets registered, (4) ALB pre-warm/surge protection for very steep traffic ramps, (5) per-target connection limits (surge queue overflow). Verify with CloudWatch target/ELB 5xx metrics and access logs.

**C5. Scenario:** You need a canary release: 5% of traffic to a new app version, and rollback if error rate rises.
**Question:** Design it with ALB features.
**Expected answer:** Create a second target group for the new version and use a **weighted target group** action (95/5 split). Monitor `HTTPCode_Target_5XX_Count` and latency via CloudWatch alarms; if the error rate crosses a threshold, shift weights back to 100/0 (or use CodeDeploy's canary/Lambda hooks for automated rollback).

**C6. Scenario:** Same service needs to be reachable internally (service-to-service) and externally, but you want different rules/security for each.
**Question:** How do you structure the ALBs?
**Expected answer:** Use **two ALBs** (or an internet-facing + internal): the internet-facing ALB handles public traffic with WAF and strict rules; the internal ALB (scheme=internal) serves other services in the VPC with SG-only access. Alternatively, a single internal ALB can be exposed publicly via CloudFront/Global Accelerator or API Gateway. Sharing one ALB for both is possible but mixes security domains — usually avoided.
