# Terraform Load Balancers (AWS) — Interview Questions

> **Cloud:** AWS · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~6 min

---

## Case A — Basic

**A1. What load balancer types does AWS offer?**
**Answer:** Application Load Balancer (ALB, layer 7), Network Load Balancer (NLB, layer 4), and Gateway Load Balancer (GWLB, for appliances). Classic ELB is legacy.

**A2. What resources make up an ALB in Terraform?**
**Answer:** `aws_lb`, `aws_lb_target_group`, `aws_lb_listener` (+ optional listener rules), and `aws_lb_target_group_attachment` for targets.

**A3. How do you declare an ALB?**
**Answer:** `resource "aws_lb" "web" { name = ... ; internal = false ; load_balancer_type = "application" ; security_groups = [...] ; subnets = aws_subnet.public[*].id }`.

**A4. What is a target group?**
**Answer:** A logical group of targets (instances, IPs, Lambda, containers) that a listener routes to, with a protocol/port and health checks.

**A5. How do you attach instances to a target group?**
**Answer:** `resource "aws_lb_target_group_attachment" "a" { target_group_arn = ... ; target_id = aws_instance.web.id ; port = 80 }` — or let an ASG register targets automatically.

**A6. What is a listener and its default action?**
**Answer:** A listener checks for connection requests on a port and forwards to a target group via a default action: `default_action { type = "forward" ; target_group_arn = ... }`.

**A7. What is a listener rule?**
**Answer:** An `aws_lb_listener_rule` routing traffic by host header/path beyond the default action, e.g. `/api/*` → api target group.

**A8. How does an NLB differ in Terraform config?**
**Answer:** `load_balancer_type = "network"`, no security groups (NLB uses subnet + elastic IPs), targets can be IPs/instances, and listeners are TCP/TLS/UDP.

**A9. What is `internal = true` on an aws_lb?**
**Answer:** It creates an internal (private) load balancer reachable only within the VPC, for backend tiers.

**A10. How do you configure health checks?**
**Answer:** In the target group: `health_check { path = "/health" ; port = "traffic-port" ; interval = 30 ; healthy_threshold = 3 ; matcher = "200" }`.

**A11. What is `aws_lb_listener_certificate`?**
**Answer:** It attaches an ACM certificate to an HTTPS listener for SNI-based multi-domain TLS.

**A12. What is a "stickiness" or session affinity setting?**
**Answer:** Target group `stickiness` block keeps a client on the same target using cookies — configure only when the app needs it.

**A13. What is a target type?**
**Answer:** `instance`, `ip`, `lambda`, or `alb`. IP targets register private IPs; Lambda targets invoke functions.

**A14. How do you get the ALB's DNS name?**
**Answer:** Output `aws_lb.web.dns_name` — AWS ELBs have a DNS name, not a static IP (NLBs can also have static IPs via subnets/EIPs).

**A15. What is an `aws_lb_listener` for HTTP→HTTPS redirect?**
**Answer:** A listener on 80 with a `default_action { type = "redirect" ; redirect { port = "443" ; protocol = "HTTPS" ; status_code = "HTTP_301" } }`.

## Case B — Advanced / Senior

**B1. ALB vs NLB: how do you choose?**
**Answer:** ALB for layer-7 routing (host/path), TLS termination, and web apps. NLB for ultra-low latency, static IPs, TCP/UDP/TLS pass-through, and very high throughput.

**B2. How do you wire an ASG to a target group?**
**Answer:** Attach the target group in the `aws_autoscaling_group` `target_group_arns`, so instances register/unregister automatically on scale. Remove manual attachments.

**B3. How do you do path-based routing in Terraform?**
**Answer:** One `aws_lb_listener` with a default action plus multiple `aws_lb_listener_rule` blocks matching `path_pattern` (or host_header) with `forward` actions to different target groups.

**B4. What is the recommended SG design around an ALB?**
**Answer:** ALB SG allows 80/443 from the internet; app SG allows traffic only from the ALB's SG (reference it), not from 0.0.0.0/0 — so instances are only reachable through the LB.

**B5. How does an internal NLB for PrivateLink work?**
**Answer:** An internal NLB + `aws_vpc_endpoint_service` exposes your service to other VPCs/accounts via interface endpoints — the endpoint connects to the NLB privately.

**B6. How do you handle zero-downtime deployments with Terraform and an ALB?**
**Answer:** Use immutable updates via ASG launch templates with `create_before_destroy`/instance refresh, or blue-green at the ASG/target-group level, so Terraform swaps targets without draining all at once.

**B7. What is connection draining / deregistration delay?**
**Answer:** Target group `deregistration_delay` keeps in-flight requests on a target before deregistering — set it long enough for graceful app shutdown.

**B8. How do you attach an ACM cert + route53 alias to an ALB?**
**Answer:** `aws_acm_certificate` + `aws_acm_certificate_validation`, attach via `aws_lb_listener` (HTTPS) `certificate_arn`, then `aws_route53_record` alias pointing `evaluate_target_health = true` to the LB.

**B9. What are the limits of Lambda targets on an ALB?**
**Answer:** Payload limits (1 MB request/response), no WebSockets, and the function must return a valid ALB response format. Used for serverless HTTP without API Gateway.

**B10. How do you troubleshoot unhealthy targets from Terraform's perspective?**
**Answer:** Check the SG path (LB→target port), health check path/matcher, and whether the ASG/target attachment is correct. Use plan/state to confirm the target group and listener wiring.

**B11. How do you make an NLB highly available across AZs?**
**Answer:** Attach subnets in multiple AZs; optionally assign `aws_eip` per subnet for static IPs. NLB automatically balances across its AZs.

**B12. What is `aws_lb` `drop_invalid_header_fields`?**
**Answer:** An ALB option to drop requests with invalid headers — hardening against malformed HTTP requests.

## Case C — Scenario

**C1. Your app is behind an ALB and suddenly returns 503s for all requests.**
**Answer:** 503 = no healthy targets. Check target health, the health-check path/matcher, the SG allowing LB→target traffic, and whether the ASG scaled to zero or instances failed the check.

**C2. You need two domains (site.com and api.site.com) on one ALB.**
**Answer:** One HTTPS listener with an ACM cert covering both domains, and two `aws_lb_listener_rule` blocks routing by `host_header` to the respective target groups (or a single cert with SANs).

**C3. A security review says your instances shouldn't be directly reachable.**
**Answer:** Move instances to private subnets, put only the ALB in public subnets, and change app SGs to allow traffic only from the ALB SG — then remove any public IPs/routes on instances.

**C4. You must deploy a new app version without dropping connections.**
**Answer:** Use an ASG with `instance_refresh` or a second target group for blue-green: register the new version, shift traffic gradually, then deregister the old. In Terraform, prefer in-place/refresh over destroy-then-create.

**C5. An NLB needs fixed IPs for a partner's firewall allowlist.**
**Answer:** Assign Elastic IPs to the NLB's subnets (one per AZ) so the addresses are static, then share those EIPs with the partner. (Or use a Global Accelerator for stable anycast IPs.)

**C6. You want WebSocket support and layer-7 routing — which LB and config?**
**Answer:** ALB supports WebSockets natively over HTTP/HTTPS listeners. Ensure the listener targets a target group with the right protocol (HTTP) and that the health check path works for the WebSocket endpoint.
