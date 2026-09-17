# RTIQ — Terraform Networking on AWS (Real-Time Interview Questions)

> **Cloud:** AWS · **Tool:** Terraform · **Domain:** VPC networking, security groups/NACLs, load balancers, Route 53/CloudFront · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~35 min

**How this file is used live:** these questions test whether you can express real network architecture in Terraform *and* anticipate its failure modes. Interviewers ask you to draw a VPC module, then ask what happens when an AZ fails, why `for_each` beat `count` in your subnet design, and how a security-group change propagates to 200 instances.

**Legend:** ⚡ Rapid · 🔍 Deep dive · 🚨 War room · ⚖️ Trade-off · 🎯 Senior signal

---

## 1. VPC Networking — `vpc-networking.md`

**⚡ Rapid**
1. **Q:** What's the minimum set of resources for a usable VPC in Terraform?
**A.** `aws_vpc`, subnets (public/private per AZ), an internet gateway, route tables + associations, a NAT gateway + EIP per AZ for private egress, and (usually) VPC endpoints for S3/DynamoDB. Everything else is workload-specific.
2. **Q:** `count` vs `for_each` for subnets — which and why?
**A.** `for_each` over a map keyed by AZ (e.g. `{ "us-east-1a" = "10.0.1.0/24", ... }`) so adding/removing an AZ only affects that subnet; `count` reindexes and can replace/recreate subnets when the list changes — dangerous for anything referencing them.
3. **Q:** How do you compute CIDRs instead of hardcoding?
**A.** `cidrsubnet(var.vpc_cidr, 8, index)` (or a loop with a counter) to derive /24s from a /16 — parameterised so the same module works for any VPC size, with validation on the prefix length.
4. **Q:** Why one NAT gateway per AZ?
**A.** NAT gateways are AZ-scoped; one shared NAT means an AZ failure takes down egress for other AZs (and adds cross-AZ data charges). Terraform: `aws_nat_gateway` with `for_each` over public subnets, and each private route table pointing at its local NAT.
5. **Q:** What's the difference between `aws_route` and `aws_route_table_association`?
**A.** `aws_route` adds a route to a route table (target = IGW, NAT, peering, TGW); the association binds a subnet to that table. Missing one of them is the classic "route exists but the subnet doesn't use it".
6. **Q:** How do you create VPC endpoints in Terraform?
**A.** `aws_vpc_endpoint` with `vpc_endpoint_type = "Gateway"` (S3/DynamoDB, plus route-table association) or `"Interface"` (other services, with `security_group_ids`, `subnet_ids`, and `private_dns_enabled = true`). Gateway endpoints are free; interface endpoints bill hourly + per GB.
7. **Q:** What does a data source give you in a VPC context?
**A.** Lookups of existing infrastructure (`aws_vpc` by tag, `aws_subnets`, `aws_ami`, `aws_caller_identity`, `aws_region`). Prefer variables/remote outputs to data-source lookups where possible — data sources fail plan if the resource doesn't exist yet.

**🔍 Deep dive**
8. **Q:** Write the shape of a production VPC module (inputs/outputs) and explain your choices.
**A.** Inputs: `name`, `cidr`, `az_count`, `public_subnet_bits`, `private_subnet_bits`, `enable_nat`, `endpoints`, `tags`. Internals: `for_each` over an AZ map, deterministic naming, one route table per subnet class per AZ, NAT per public subnet, gateway endpoints for S3/DynamoDB by default, flow logs to a central destination. Outputs: `vpc_id`, `public_subnet_ids` (map by AZ), `private_subnet_ids` (map), `nat_gateway_ids`, `route_table_ids`. Rationale: maps keyed by AZ (stable refs), private by default, and observability/endpoints included so teams can't forget them.
**↳ Follow-up:** "How do you add a new AZ to a live VPC?"
**A.** Add an entry to the AZ map: Terraform creates that AZ's subnets/routes/NAT and only touches new resources — the key benefit of keyed `for_each`. Workloads referencing `private_subnet_ids` by key see the new one appear (and ASGs/ALBs spread into it); nothing is recreated.
9. **Q:** How do you handle VPC flow logs in Terraform at scale?
**A.** `aws_flow_log` with destination = CloudWatch Logs (fast query) or S3 (cheap long-term) plus the required IAM role/policy and log group with retention; create at the VPC level (`traffic_type = ALL`) and standardise in the module with a `flow_log_destination` variable. Centralise the destination in a logging account and let the module accept the ARN.
10. **Q:** How do you create a second VPC and connect it (peering or TGW) in Terraform?
**A.** Peering: `aws_vpc_peering_connection` (+ accepter for cross-account), then `aws_route` entries in *both* VPCs' route tables (every subnet class on both sides) — the classic omission. TGW: `aws_ec2_transit_gateway`, one attachment per VPC, and TGW route tables/associations/propagations; the access-control layer is the TGW route table design, not the attachments.
11. **Q:** How do you express "private by default" in Terraform?
**A.** Private subnets with no IGW route and `map_public_ip_on_launch = false`, public subnets only for load balancers/NAT, security groups with explicit egress rather than `0.0.0.0/0`, and endpoint/service access instead of internet where possible. Add `precondition` checks or policy-as-code (e.g. deny `map_public_ip_on_launch = true`) so the default can't be violated quietly.
12. **Q:** How do you manage many VPCs across accounts without copy-paste?
**A.** A single network module called from each account's root with account-specific inputs (CIDR, AZ count), CIDR allocation tracked centrally (IPAM/parameter store) to prevent overlaps, and shared services (TGW, DNS, endpoints) owned by the network account with outputs published for consumers. Registry + versioning for the module; policy to enforce the standard.
13. **Q:** What are the Terraform-specific pitfalls in VPC code?
**A.** Cyclic dependencies (SG referencing a resource that references the SG), `for_each` with unknown values (e.g. deriving keys from resources created in the same apply), destroying a NAT/IGW while route tables still reference it (ordering), and hardcoded AZ names/account IDs. Also: `aws_route` for IPv6 and the association order on `create_before_destroy`.
14. **Q:** How do you test network changes before production?
**A.** Deploy the same module into a sandbox account, use `terraform plan` review for anything destructive (route/subnet deletion), validate connectivity with automated checks (Reachability Analyzer, curl from a test instance/SSM run-command), and add post-apply smoke tests in the pipeline. Network changes are the least reversible — treat them like database migrations.

**🚨 War room**
15. **Q:** An apply will delete a production subnet. What do you do?
**A.** Stop the apply. Diagnose *why* Terraform thinks the subnet should be replaced (a changed CIDR/AZ/attribute forces recreation, a key renaming in `for_each`, or a config restructuring). Fix with a matching `moved` block or by reverting the attribute; if the subnet must genuinely change, plan a migration (create new, move resources, delete old) with a maintenance window. Add `prevent_destroy` and a policy gate for subnets/VPCs after this.
16. **Q:** After adding a NAT gateway per AZ, costs tripled.
**A.** Expected — NAT gateways bill hourly plus per GB. Mitigate by ensuring the traffic actually needs NAT: add S3/DynamoDB gateway endpoints (free) and interface endpoints for high-volume services (ECR pulls, KMS, SQS), so much of the egress leaves the NAT path entirely. Then right-size the number of NATs (some teams run one per AZ for prod, one shared for dev).
17. **Q:** A route-table change broke on-prem connectivity for one subnet class.
**A.** The UDR order/associations changed (or a more specific route now wins), a TGW/VPN-propagation setting was toggled, or the wrong route table got the change. Check effective routes for a test instance and revert the specific change; then add a plan-time check that flags modifications to routes containing on-prem CIDRs.
18. **Q:** Security groups can't be created because of a dependency cycle.
**A.** Circular reference: SG A allows SG B and SG B allows SG A. Break it with separate `aws_vpc_security_group_ingress_rule` resources (references resolve independently) or by attaching one rule after both SGs exist. This is a well-known Terraform AWS pattern — knowing the fix immediately signals experience.
19. **Q:** `terraform destroy` on a network root would delete shared infrastructure other roots depend on.
**A.** This is a design flaw, not just an accident: shared network roots should have `prevent_destroy` on the VPC/subnets/endpoints, a separate role/account for them, and IAM that denies `DeleteVpc` for the pipeline that manages app roots. Add a CI policy that blocks plans containing network deletions.
20. **Q:** Flow logs were silently disabled for three months.
**A.** Re-enable via the module (drift vs config removal — check state/plan), then add controls: a Config rule/policy that asserts flow logs exist on every VPC, alerts on `DeleteFlowLogs`/`DeleteLogGroup` events, and (if compliance requires) immutable retention in a separate account. Disabling logging is both a compliance gap and an anti-forensics technique.
21. **Q:** A cross-account peering was created manually and Terraform keeps trying to change routes.
**A.** Codify it (import the peering and routes into the owning root) or remove it if it isn't needed — leaving unmanaged network paths in place is how shadow connectivity appears. Add a drift-detection plan that flags unmanaged route entries in shared route tables.

**⚖️ Trade-off**
22. **Q:** One big VPC with many subnets vs many VPCs?
**A.** One VPC with segmentation (subnets, NACLs, SGs) is simpler/cheaper and fine for a single application or team; many VPCs give isolation, independent CIDR/quotas, and cleaner ownership at the cost of peering/TGW, DNS, and endpoint duplication. Split by environment and by trust/ownership boundaries, not arbitrarily.
23. **Q:** NAT gateway vs NAT instance in Terraform?
**A.** NAT gateway is managed, HA-ish within an AZ, and scales — the default; a NAT instance is cheaper but you own HA (fleet + failover scripts), patching, and bandwidth. Unless cost dominates small dev environments, use the gateway; in Terraform that's one resource vs an ASG + scripts.
24. **Q:** Managed by Terraform vs created by the console for network plumbing?
**A.** Network plumbing is the worst candidate for manual change: it's shared, references everything, and errors are outages. Codify it (module + reviewed plans), with a documented break-glass process (and a follow-up to import whatever break-glass created). "We'll codify the network later" never happens.
25. **Q:** Gateway endpoints vs interface endpoints for S3 in Terraform?
**A.** Gateway endpoints are free and route-table based (in-VPC only, no on-prem access); interface endpoints cost hourly+GB but work everywhere and support private DNS. Most setups: gateway for S3/DynamoDB, interface for the rest — and this is a cost-design decision you should model, not guess.
26. **Q:** One module per subnet class vs one module for the whole VPC?
**A.** One VPC module with internal structure keeps related resources together (routes, associations, NAT) and prevents inconsistent states; splitting by subnet class creates cross-module dependencies and half-built VPCs. Keep the unit of change = the VPC.
27. **Q:** Public subnets for load balancers vs everything in private subnets with NLBs/PrivateLink?
**A.** Public subnets for public-facing ALBs/NLBs (they need IGW routes); private-only with PrivateLink/NLB-in-public for stricter compliance, but you still need a public entry point somewhere for internet traffic. Be explicit about where the public boundary lives.

**🎯 Senior**
28. **Q:** What does a production-grade VPC module include, in your opinion?
**A.** Keyed `for_each` over AZs with `cidrsubnet` allocation and validation; one NAT per AZ (configurable) with per-AZ private route tables; gateway endpoints for S3/DynamoDB by default and interface endpoints for the services the platform uses; flow logs to a central account with retention; `prevent_destroy` on the VPC and subnets; tagging (owner, env, cost-centre, data classification); outputs as keyed maps (never index-based lists); a documented upgrade path for adding AZs/CIDR expansion; and CI policy checks that block public-by-default or unencrypted/no-logging variations.

**🎯 Senior signal:** breaking SG cycles with separate rule resources, `for_each` keyed by AZ, and treating network changes as migration-like operations. Those three say you've operated networks through Terraform, not just written them once.

---

## 2. Security Groups & NACLs — `security-groups-nacls.md`

**⚡ Rapid**
1. **Q:** How do you create SG rules in Terraform, and which style do you prefer?
**A.** Inline `ingress`/`egress` blocks on `aws_security_group`, or separate `aws_vpc_security_group_ingress_rule`/`egress_rule` resources (newer), or the legacy `aws_security_group_rule`. Separate rule resources avoid whole-SG replacement churn and are safer for large rule sets; never mix inline and standalone rules for the same SG.
2. **Q:** Why do SG changes sometimes destroy/recreate?
**A.** Inline blocks are part of the SG resource, so a rule change rewrites the resource (and historically forced replacement in some cases); standalone rule resources change independently. It's the reason the newer split-resource pattern is recommended.
3. **Q:** How do you reference another SG as the source?
**A.** `source_security_group_id = aws_security_group.app.id` (or the `referenced_security_group_id` field on the newer resource). It's better than CIDR because membership replaces IP management.
4. **Q:** How do you handle default egress?
**A.** AWS SGs allow all egress by default. In a least-privilege setup, replace it (`aws_vpc_security_group_egress_rule` for 443 to specific destinations/CIDRs/prefix lists) and be aware that removing default egress breaks things like package installs — inventory first.
5. **Q:** How do you manage NACLs in Terraform?
**A.** `aws_network_acl` + `aws_network_acl_rule` (numbered, ingress/egress) + `aws_network_acl_association`. Remember statelessness: you must allow ephemeral ports in both directions, and rule numbering determines precedence.
6. **Q:** Where do prefix lists fit?
**A.** `aws_ec2_managed_prefix_list` (your own CIDR set, e.g. partner ranges) referenced by SG/NACL rules — single source of truth for IPs, updated atomically by Terraform.
7. **Q:** How do you tag and name rules for auditability?
**A.** Descriptive tags/descriptions per rule (`description = "allow 443 from ALB SG"`), naming conventions in the module, and grouping rules by SG-purpose. Descriptions appear in flow logs/console — auditors read them.
8. **Q:** What's the common Terraform trap with SGs and instances?
**A.** Changing an SG attachment triggers ENI changes; and an SG created after the instance attached (`create_before_destroy`) can cause replace-on-attach churn. Attach SGs in the launch template/ASG, not ad hoc, so instances are never created without them.

**🔍 Deep dive**
9. **Q:** Design the SG structure for a 3-tier app in Terraform (with code shape).
**A.** `aws_security_group.alb` (ingress 443 from internet/CloudFront prefix list, egress to app SG on app port), `aws_security_group.app` (ingress from alb SG only, egress to db SG + endpoints), `aws_security_group.db` (ingress from app SG only, no egress beyond needed). Each with `aws_vpc_security_group_ingress_rule`/`egress_rule` resources, ASG launch templates referencing the tier's SG, and a `depends_on`-free structure (references handle ordering). Add `name_prefix`/deterministic naming and tags.
**↳ Follow-up:** "How do you prove the rules are minimal?"
**A.** Flow logs + a generated matrix of allowed flows vs observed flows, and a policy check in CI that fails on `0.0.0.0/0` ingress to management ports; then a quarterly review removing rules with zero hits. Evidence beats intent.
10. **Q:** How do you manage an SG used by 200 instances without reloading them?
**A.** SG rules are applied at the ENI level, so rule changes take effect immediately without touching instances — but each rule change is a security-relevant change, so it should go through the pipeline with a plan diff. Keep the SG per-tier (not per-instance) and use descriptions so the change is understandable in review.
11. **Q:** How do you express dynamic rule sets (e.g. N partner IPs) without a messy plan?
**A.** `for_each` over a map/set of CIDRs into separate rule resources (adding one entry adds one resource, no churn), or a managed prefix list updated in one place. Avoid `dynamic` blocks over large lists inside a single SG when churn matters.
12. **Q:** How do you handle rule limits and count quotas?
**A.** SGs have rule limits per SG and per ENI (and older default SG counts per ENI matter) — consolidate with SG references/prefix lists rather than hundreds of CIDR rules, and be aware that many SGs attached to one instance multiply rules toward the ENI ceiling.
13. **Q:** How do you do least-privilege egress in Terraform without breaking builds?
**A.** Inventory actual egress with flow logs, then allow 443 to specific destinations (AWS endpoints via prefix lists/VPCEs, package mirrors, partner ranges), plus DNS (53) and NTP where required. Roll out per environment (dev → prod) and keep an exception input with a documented reason for services that need broader egress.
14. **Q:** What does your NACL usage look like, and why?
**A.** Usually minimal: default allow-all with a documented exception for a hard block (known-bad ranges, an incident containment rule, or a compliance-mandated second layer). Where used, keep rules numbered with gaps, include ephemeral ports, and describe intent — most NACL incidents come from unused complexity.
15. **Q:** How do you integrate SGs with security tooling?
**A.** IaC scanning (checkov/tfsec) for public admin ports and unrestricted egress, policy-as-code on the plan for "no 0.0.0.0/0 to 22/3389", Config rules for ongoing compliance, and GuardDuty/Security Hub for runtime. Make the CI check the primary guardrail so bad rules can't merge.

**🚨 War room**
16. **Q:** A security group change opened 22 to the world and merged. What now?
**A.** Revoke immediately (a fast apply of the corrected rule — don't wait for the pipeline), check flow logs/SSH logs for successful logins in the exposure window, rotate keys/credentials on affected instances, and notify per policy. Then prevent: a plan-level policy that fails the pipeline on public admin ports, plus Config auto-remediation, plus an alarm on SG rule changes with `0.0.0.0/0` and admin ports.
17. **Q:** An SG rule was created manually and Terraform wants to remove it.
**A.** Decide: if it's needed (a real access requirement), codify it in the module; if not, let the apply remove it — but check dependencies first (someone may depend on that access) and communicate. Then close the loop on why manual changes are possible (human write roles in prod).
18. **Q:** Instances in an ASG intermittently can't reach the ALB's target port.
**A.** Check the app SG's ingress source (is it the ALB SG or a CIDR that drifted?), whether the ASG's launch template attaches the right SGs (a mix of old/new templates after a rollout), and whether a second SG on some instances creates an unexpected union. ASG instance refresh after fixing the template is the rollout mechanism.
19. **Q:** After adding a NAT/endpoint change, egress broke for the app tier.
**A.** SGs are evaluated as a union of attached SGs and are stateful, so the usual suspects are: the app SG's explicit egress rules don't include the new destination (endpoint ENI CIDR or prefix list), or a NACL on the new subnet blocks ephemeral return traffic. Compare effective rules/resolved flows and revert the specific rule change.
20. **Q:** `terraform plan` shows the SG being replaced, which would briefly break connectivity.
**A.** Find the forcing attribute (usually `name` vs `name_prefix` changes, or a VPC change), and use `create_before_destroy` plus `name_prefix` (unique names) so the new SG is created before the old is destroyed; verify that the instances/ENIs move to the new SG without a connectivity gap, or plan a maintenance window for the cut.
21. **Q:** A pentester found an internal service reachable from a subnet it shouldn't be.
**A.** Identify which rule allows it (SG union + `AllowVnetInBound`-style defaults — in AWS, a permissive SG or an intra-VPC CIDR rule), tighten to SG references only, verify with flow logs, and check whether the access was used. Then add the "no intra-VPC CIDR allows between tiers" policy check to CI and treat it as a segmentation gap.

**⚖️ Trade-off**
22. **Q:** SG references vs CIDR rules in Terraform?
**A.** References are self-maintaining, readable, and survive replacement of the referenced SG (mostly); CIDRs are needed across VPCs/accounts or for external parties. Prefer references internally, prefix lists/CIDRs at the edges, and never hand-maintain IP lists in multiple rules.
23. **Q:** Inline rules vs separate rule resources?
**A.** Separate resources: independent changes, no churn, easier to manage dynamically, and they avoid the SG-replacement problem — at the cost of more resources in state. Inline: fewer objects, but rule changes rewrite the SG. For anything with more than a couple of rules, go separate.
24. **Q:** SG on subnet vs instance/ENI (and does AWS even support subnet-level SGs)?
**A.** AWS SGs attach to ENIs (instances), not subnets — subnet-level filtering is NACLs. So the equivalent question is: NACL (subnet, stateless, coarse) vs SG (ENI, stateful, fine). Use SGs for real policy, NACLs for coarse exceptions.
25. **Q:** Strict egress control vs default allow-all?
**A.** Strict egress is a genuine security win (exfiltration, lateral movement) but breaks workloads in surprising ways (package repos, telemetry, auth endpoints). Approach it iteratively: inventory, allow-list, monitor, enforce — and keep an explicit, documented exception mechanism rather than abandoning the control.
26. **Q:** Security group changes via Terraform vs via an incident-response tool (e.g. a script to block an IP now)?
**A.** Break-glass must be fast (a script/console change now), but it must be followed by codifying the change or reverting it, and it must be logged. The failure mode is silent drift; the control is drift detection plus mandatory follow-up — say that trade explicitly.
27. **Q:** One SG for a whole tier vs per-service SGs?
**A.** Per-service SGs are least privilege and make rules meaningful; tier-wide SGs are simpler but any new rule applies to everything in the tier (blast radius grows quietly). Prefer per-service, and use ASGs/references for scale.
28. **Q:** Should you manage the default SG and default VPC in Terraform?
**A.** Yes — at minimum, remove the default SG's rules (or ensure nothing uses it) and delete/lock down default VPCs so nobody deploys into them. Managing "defaults that should never be used" is a good interview point about intent.

**🎯 Senior**
29. **Q:** What's your standard for production security groups in IaC?
**A.** Per-tier/per-service SGs with SG-reference sources, separate rule resources for churn-free changes, descriptions on every rule, no `0.0.0.0/0` on admin ports (policy-enforced in CI), explicit egress to endpoints/prefix lists where feasible, NACLs left simple with documented exceptions, flow logs enabled to validate, `prevent_destroy` on shared SGs, and a quarterly review that removes zero-hit rules with evidence.

**🎯 Senior signal:** the SG circular-dependency fix (separate rule resources), `name_prefix` + `create_before_destroy` for zero-gap replacement, and flow-log-driven rule minimisation. Those three are practical, earned knowledge.

---

## 3. Load Balancers — `load-balancers.md`

**⚡ Rapid**
1. **Q:** What's the modern Terraform resource set for an ALB?
**A.** `aws_lb_type = "application"`, `aws_lb_target_group` (with health check config), `aws_lb_listener` (443 with certificate), `aws_lb_listener_rule`, target group attachments (via `aws_lb_target_group_attachment` or the ASG's `target_group_arns`), and `aws_lb_listener_certificate` for extra certs.
2. **Q:** `aws_alb` vs `aws_lb`?
**A.** `aws_lb` is the current resource (covers ALB/NLB/GWLB via `load_balancer_type`); `aws_alb` is the legacy alias. Use `aws_lb` for new code.
3. **Q:** How do you attach an ASG to a target group?
**A.** `target_group_arns` on `aws_autoscaling_group` (or `aws_autoscaling_attachment` for multiple/external ASGs) — instances register automatically, which is what you want for autoscaling.
4. **Q:** How do you configure zero-downtime deploys?
**A.** Health check path/interval/thresholds on the target group, `deregistration_delay` (connection draining) matched to the app's request duration, `slow_start` for warm-up, and ASG instance refresh or blue/green target groups with weighted listener rules.
5. **Q:** How do you terminate TLS in Terraform?
**A.** `aws_lb_listener` with `protocol = "HTTPS"`, `certificate_arn` from ACM, `ssl_policy` (e.g. `ELBSecurityPolicy-TLS13-1-2-2021-06`), and an HTTP listener with a redirect action. Reference ACM certs by ARN — with `validation` handled by `aws_acm_certificate_validation`.
6. **Q:** How do you add WAF?
**A.** `aws_wafv2_web_acl` + `aws_wafv2_web_acl_association` to the ALB ARN, plus logging configuration (`aws_wafv2_web_acl_logging_configuration`) — associations are the step people forget.
7. **Q:** Access logs and where they go?
**A.** `access_logs { bucket = ..., enabled = true, prefix = ... }` on the LB with an S3 bucket policy allowing the ELB service principal (via `aws_elb_service_account` data source / your account-region principal). Missing the bucket policy is a common apply-time failure.
8. **Q:** How do you do host/path routing?
**A.** `aws_lb_listener_rule` with `condition { host_header / path_pattern }` and a forward action to the appropriate target group; priority ordering matters. Keep rules IaC-managed so tenant/service routing is reviewable.

**🔍 Deep dive**
9. **Q:** Design a blue/green deployment with ALB + Terraform.
**A.** Two target groups (blue/green) attached to the same listener; a `weighted_forward` action (or two listener rules with weights) so you can shift 1% → 100%; the ASG points at the active target group with a variable; the pipeline updates the inactive ASG's launch template with the new AMI/app, waits for health, shifts weights, monitors alarms, then flips the ASG variable. Rollback = shift weights back (seconds). The key Terraform detail: the weight lives in `aws_lb_listener_rule` (or the legacy `aws_lb_listener`'s default action), so the pipeline must manage that as a variable.
**↳ Follow-up:** "How do you avoid Terraform fighting the pipeline over weights?"
**A.** Either let Terraform own the weights (pipeline edits a variable file and applies) or use `ignore_changes = [default_action]` and let the deployment tooling manage weights via API. Mixing both causes flapping plans — pick one owner per attribute.
10. **Q:** How do you make an ALB tolerant of an AZ failure?
**A.** Create the LB with subnets in ≥2 (preferably 3) AZs, enable `cross_zone_load_balancing`, ensure the ASG spans the same AZs with capacity headroom, and health checks that detect app failure. For NLBs, remember cross-zone is off by default and static IPs per AZ matter for allow-listing.
11. **Q:** How do you manage multiple certificates and domains?
**A.** A default listener cert plus `aws_lb_listener_certificate` for additional SANs/wildcards, all from ACM with DNS validation automated via Route 53 records and `aws_acm_certificate_validation`. Track expiry with a Lambda/Config rule or ACM's expiry events.
12. **Q:** NLB specifics in Terraform?
**A.** `load_balancer_type = "network"`, `aws_lb_target_group` with TCP/UDP protocols, `preserve_client_ip`, and per-AZ `subnet_mapping` blocks with `allocation_id` for EIPs (that's how you get static IPs). NLB has no security groups (except when it does — newer support with SG on NLB exists), so target SGs must allow the client sources.
13. **Q:** How do you handle slow-start/warm-up and connection draining?
**A.** `slow_start` seconds on the target group (ramps new targets), `deregistration_delay` for draining (raise for long-lived requests/WebSockets), and the app must handle SIGTERM to finish in-flight work. Also align the app's keep-alive with the LB's idle timeout to avoid spurious 5xx.
14. **Q:** How do you structure LB resources across many services?
**A.** A shared edge LB with host/path rules for many services (cheaper, fewer public IPs) or per-service LBs (isolation, more cost). In Terraform, that's a module for the LB and per-service listener rules from each service's root — with care about who owns the listener default action (a common multi-root conflict).
15. **Q:** How do you test an LB change safely?
**A.** Plan review for listener/rule changes (they're traffic-affecting), apply in a non-prod environment first, use listener rules with a test host header to validate before cutting over, and monitor target health/5xx after the change. Add synthetic checks post-apply in the pipeline.

**🚨 War room**
16. **Q:** A plan wants to replace the ALB (new ARN, new DNS name). What do you do?
**A.** Find the forcing attribute — commonly a changed name, a subnet/`subnet_mapping` change, or an internal/external change. If replacement is genuinely required, migrate deliberately: create the new LB, point DNS (Route 53 alias) at it, drain the old one, then remove it — don't let a single apply swap the DNS name out from under users. Use `create_before_destroy` for the listener/target groups as needed.
17. **Q:** All targets show unhealthy after a Terraform apply.
**A.** The apply changed the health check (path/port/protocol) or the SG (the LB's SG or the target's SG no longer allowing the LB), or the target group was replaced and instances weren't re-registered. Check the target group config diff in the plan and the effective SG rules — the plan diff nearly always names the cause.
18. **Q:** Users see 502/504 after a deploy.
**A.** 502 = malformed response/connection closed by target (app crash, crash-loop, wrong port/protocol); 504 = timeout (app too slow or idle timeout mismatch). Correlate the deploy time, check target health history and app logs, and verify the app's `SIGTERM` handling during instance refresh. Roll back the launch template version if needed.
19. **Q:** Access logs stopped appearing.
**A.** The S3 bucket policy lost the ELB principal (someone hardened the bucket), the bucket was deleted/recreated, or `access_logs` was disabled by a config change. Fix the policy/config, then add a check (Config rule/alarm on log delivery or a metric on objects landing in the bucket) so silent log loss doesn't recur.
20. **Q:** Target group deregistration is killing in-flight requests during scale-in.
**A.** `deregistration_delay` is too short for the app's request duration (or WebSockets are being drained before the connection closes), and `scale_in_protected_instances` isn't set for long-running work. Raise the delay, add lifecycle hooks for graceful shutdown, and align the app's drain behaviour — then verify with synthetic long-request tests.
21. **Q:** Certificate renewal broke the listener because Terraform pinned a specific cert ARN version.
**A.** The listener should reference the ACM certificate ARN (which is stable across renewals) rather than a versioned/copied cert; if you use a re-issued cert in another region, that's a different ARN and Terraform must update the listener. Stop pinning per-reissue artifacts, and monitor ACM expiry with alerts.
22. **Q:** WAF started blocking legitimate traffic after Terraform applied a rule update.
**A.** Roll back the WAF config (Terraform apply of the previous state or set the rule to count mode), inspect the WAF logs for the matching rule, then re-deploy with an exclusion/false-positive tuning in count mode first. Treat WAF rule changes as production changes with a staged rollout.

**⚖️ Trade-off**
23. **Q:** Shared ALB vs per-service ALB?
**A.** Shared: fewer public IPs, lower cost, central WAF/certs, but coupled blast radius, listener-rule conflicts across roots, and rule limits. Per-service: isolation and independent ownership at higher cost. Common hybrid: shared edge (ALB + WAF) for public traffic, per-service LBs internally.
24. **Q:** Let Terraform own deployment weights, or let the deploy tool?
**A.** Terraform-owned weights keep everything declarative (weights become variables, plan shows the shift) but coupling deployments to infra pipelines; tool-owned weights (CodeDeploy/Argo/skripts) are faster and purpose-built but need `ignore_changes`/lifecycle to prevent Terraform fighting them. Choose one owner per attribute and document it.
25. **Q:** Manage LBs in the app root vs a separate shared root?
**A.** App root: everything about the service in one place, simplest for teams, but the LB name/DNS is coupled to the app lifecycle. Shared root: LBs are infrastructure with their own lifecycle and are consumed by many apps (rules added per app) — required when DNS/allow-lists/WAF scope is central. Split when the resource outlives the app.
26. **Q:** ALB with WAF vs CloudFront + WAF for the public edge?
**A.** CloudFront+WAF absorbs at the edge (DDoS, caching, geo), reducing origin load and cost of LCU/ALB traffic; ALB+WAF is simpler (one hop, fewer components) and needed if you can't front with CloudFront. For internet-facing production at scale, CloudFront in front is the common architecture.
27. **Q:** NLB for static IPs vs ALB for L7 features?
**A.** NLB: static EIPs (partner allow-listing), TCP/UDP, extreme throughput, source IP preservation — but no L7 routing/WAF. ALB: everything L7. Many designs use both (NLB in front for static IPs → ALB), which adds a hop and cost but satisfies both requirements.
28. **Q:** Should health checks hit a deep (dependency-aware) endpoint?
**A.** Deep checks stop routing to instances with broken dependencies — good for correctness, dangerous if the dependency is shared (a DB blip removes your entire fleet from rotation and causes a full outage). Best practice: liveness/readiness for routing decisions, dependency health as a separate signal/alarm, and never fail the LB health check on a shared dependency unless you've designed for the blast radius.

**🎯 Senior**
29. **Q:** What does a production-grade ALB configuration include?
**A.** ≥2–3 AZ subnets with cross-zone enabled, HTTPS listener with a modern TLS policy + HTTP→HTTPS redirect, ACM cert with automated validation and expiry monitoring, target groups with dependency-aware-but-safe health checks plus slow start and a drain delay matched to request durations, access logs to a policy-correct S3 bucket with retention, WAF associated and logging, alarms on 5xx/healthy-host count/latency, deletion protection enabled, `prevent_destroy` where the DNS name matters, and deployment weights owned by an explicit pipeline step.

**🎯 Senior signal:** "replacing the ALB changes the DNS name — migrate deliberately", the S3 bucket policy requirement for access logs, and deep-vs-shallow health check blast radius. Those are the details of someone who's operated load balancers.

---

## 4. Route 53 & CloudFront — `route53-cloudfront.md`

**⚡ Rapid**
1. **Q:** How do you create a hosted zone and records in Terraform?
**A.** `aws_route53_zone` (with `name` and optional delegation set), then `aws_route53_record` for each record, and `aws_route53domains_registered_domain`/NS delegation to point the registrar at the zone. For new zones, Terraform can also register the domain (limited TLDs) or you wire NS manually.
2. **Q:** Alias vs CNAME records?
**A.** `alias { name, zone_id, evaluate_target_health }` for AWS resources (ALB, CloudFront, S3 website) — free queries, no charge for alias lookups, and it follows the resource's IPs; `aws_route53_record` type CNAME for external targets (billed per query). Prefer alias for AWS endpoints.
3. **Q:** How does `evaluate_target_health` work?
**A.** For alias records to ELBs/S3, it makes the record serve the target only when the ALB's own health checks deem it healthy; for failover/weighted/latency records with health checks, Route 53 uses the check to decide. Essential for active-passive failover.
4. **Q:** How do you get ACM validation automated?
**A.** `aws_acm_certificate` with `validation_method = "DNS"`, an `aws_route53_record` for the validation CNAME(s), and `aws_acm_certificate_validation` with `validation_record_fqdns` — then reference the validated cert ARN in the LB/CloudFront. This pattern is a Terraform rite of passage.
5. **Q:** CloudFront in Terraform — core resources?
**A.** `aws_cloudfront_distribution` (origins, default cache behaviour, viewer certificate, aliases), `aws_cloudfront_origin_access_control` (or legacy OAI) for S3 origins, `aws_cloudfront_cache_policy`/`origin_request_policy` (replacing the deprecated forwarded_values), and `aws_cloudfront_function` for lightweight edge logic.
6. **Q:** Where must a CloudFront ACM certificate live?
**A.** `us-east-1` (global) — a well-known gotcha; regions get their own certs for regional services. In Terraform this usually means an aliased `aws.us_east_1` provider for the CloudFront cert and validation records.
7. **Q:** How do you manage S3 origin access?
**A.** Origin Access Control (OAC) in Terraform (`aws_cloudfront_origin_access_control`) + a bucket policy allowing the distribution's service principal with a `SourceArn` condition — the bucket stays private. OAI is the legacy pattern; OAC is current and supports newer features.
8. **Q:** What about cache invalidation?
**A.** `aws_cloudfront_invalidation` exists but is best avoided: use hashed/versioned filenames for static assets (immutable, long TTL) and short TTLs for entry HTML. Invalidation costs money after the free tier and takes time.

**🔍 Deep dive**
9. **Q:** Design global static-site hosting with CloudFront + S3 + custom domain in Terraform.
**A.** S3 bucket (private, versioned, no public access) + OAC, `aws_cloudfront_distribution` with a default behaviour using a managed caching policy and `viewer_protocol_policy = "redirect-to-https"`, ACM cert in us-east-1 with DNS validation via Route 53, `aliases` for the custom domain, an A/AAAA alias record in Route 53, a 403/404 error-response mapping for SPA routing if needed, WAF associated if public, access logging to a separate bucket, and a deployment pipeline that syncs hashed assets then flips the index. Add a CloudFront function for redirects/header normalisation.
**↳ Follow-up:** "How do you deploy a new version with no cache problems?"
**A.** Never overwrite asset filenames: upload `app.<hash>.js`, then update `index.html` (short TTL/no-cache) to reference it, so the cache for hashed assets never needs invalidation. In Terraform terms, the distribution's config is stable; only the S3 objects change — so keep content deployment in the app pipeline, not Terraform.
10. **Q:** How do you set up multi-region failover with Route 53 in Terraform?
**A.** Failover records: primary record with `failover_routing_policy { type = "PRIMARY" }` + `health_check_id`, secondary with `SECONDARY`, both aliases to regional endpoints, plus `aws_route53_health_check` (HTTP/HTTPS/TCP with path, thresholds, and optionally `calculated` for multi-signal) and low TTLs (30–60 s). Remember DNS failover is TTL-bounded — say that when presenting the design.
11. **Q:** How do you manage many zones/records across accounts?
**A.** Central DNS account owning public zones with consumer accounts requesting records via PRs/pipelines (or `aws_route53_record` in the app root with a shared-zone output), reusable delegation sets for consistent NS, and a naming/tagging standard. Decentralised zones cause collisions and orphaned records.
12. **Q:** How do you handle private hosted zones?
**A.** `aws_route53_zone` with `vpc { vpc_id }` associations (or `aws_route53_zone_association` to attach additional VPCs across accounts). For hybrid DNS you also need Resolver rules/endpoints (`aws_route53_resolver_rule`, `aws_route53_resolver_endpoint`) — plan the association model early, as changing it later impacts resolution everywhere.
13. **Q:** How do you keep secrets/config out of the CloudFront resource?
**A.** CloudFront config is not a secrets store: use environment-agnostic distributions and put secrets in the backend or Secrets Manager at runtime; lambda@edge/CloudFront functions should fetch config via SSM/KV with a short cache, not embed values. Distribution configs still show up in state and change history.
14. **Q:** How do you customise CloudFront cache behaviour properly?
**A.** Behaviours per path pattern with managed cache policies (`CachingOptimized` for static, `CachingDisabled` for API), explicit forwarded headers/cookies/query strings (only what's needed, so you don't destroy cache hit ratio), compression enabled, allowed HTTP methods per behaviour, and `viewer_protocol_policy`/TLS versions set for security. Modern configs should avoid legacy `forwarded_values`.
15. **Q:** How do you test DNS/CloudFront changes before they hit users?
**A.** Plan review for record changes (they're instantly effective globally), stage in a non-prod zone/domain, verify with `dig` against the zone's name servers before delegation, use a test host name (e.g. `canary.example.com`) to validate a new distribution, and post-apply synthetic checks per region. DNS changes are global and cached — treat them as high-risk.

**🚨 War room**
16. **Q:** DNS failover didn't trigger during an outage. Diagnose.
**A.** Health check misconfiguration (wrong path/port, expecting 200 while the app returns 302, or checking a CDN-served page that stays healthy while the origin is down), thresholds too lenient, `evaluate_target_health` not set, or the standby being unhealthy so there was nothing to fail to. Also check that the record is actually a FAILOVER type and the TTL is low. Fix the check to exercise the real app path.
17. **Q:** Terraform wants to recreate the hosted zone (delegation/NS change). Stop it.
**A.** A `force_destroy`/name change or a delegation-set change forces replacement (and a new zone = new name servers = downtime while delegation propagates). Fix the config to keep the same name/delegation set; if a change is unavoidable, migrate by creating the new zone, replicating records, then switching NS with a low TTL and monitoring.
18. **Q:** A CloudFront distribution update is taking 20–30 minutes and the pipeline timed out.
**A.** Distribution updates are global and slow (15–30 min typical, sometimes cancelling in-flight deployments). Make the pipeline tolerant (longer timeouts, async notification), avoid frequent distribution updates by turning over content in S3 (versioned filenames), and separate distribution config changes from content deploys so app releases don't wait on CloudFront.
19. **Q:** Users see stale content after a deploy.
**A.** Check the cache policy/TTLs, whether the entry HTML is cached too long (it should be short/no-cache), whether query strings/headers in the cache key make old variants stale, and whether the browser itself is caching. Fix with versioned filenames + `Cache-Control` headers per object class; use invalidation only as a stopgap.
20. **Q:** Certificate validation records were deleted and renewal will fail.
**A.** Recreate the validation CNAMEs (Terraform restores them on apply) and confirm ACM shows the certificate as "issued/renewed"; then protect: don't manage validation records outside Terraform, add an alert on ACM expiry events, and a Config rule checking cert status. Silent renewal failure is a classic outage cause.
21. **Q:** CloudFront returns 403 from the S3 origin.
**A.** The bucket policy no longer grants the distribution (OAC/OAI mismatch, a new distribution ARN after replacement, or a hardened bucket policy), the object key/path is wrong, or an S3 block-public-access change broke website-endpoint access. Check the distribution's origin config vs the bucket policy's `AWS:SourceArn` condition.
22. **Q:** Terraform and a WAF/other tool are both modifying the CloudFront distribution.
**A.** Conflict on the same attributes (origin/behaviour config) causes plans that flip-flop; assign one owner per attribute (usually Terraform owns the distribution, the WAF is associated separately via `aws_wafv2_web_acl_association`) and use `ignore_changes` for attributes managed elsewhere — but document it, because silent `ignore_changes` hides real drift.

**⚖️ Trade-off**
23. **Q:** Route 53 failover vs Global Accelerator vs CloudFront multi-origin?
**A.** Route 53: cheap, DNS-bound failover (minutes), protocol-agnostic. Global Accelerator: anycast static IPs, seconds-scale failover, TCP/UDP — higher cost. CloudFront with multiple origins/origin groups: fast failover for HTTP with caching/WAF included. Choose by RTO and protocol; many designs use CloudFront at the edge and Route 53 for the regional layer.
24. **Q:** Terraform-managed CloudFront vs content pipeline-managed?
**A.** Terraform should manage the distribution's configuration (origins, behaviours, TLS, WAF) because it's infrastructure; content and file versions should be managed by the app pipeline (s3 sync/hashed names). Mixing content into Terraform state creates huge state and slow applies.
25. **Q:** CloudFront vs S3 website endpoint vs ALB directly?
**A.** CloudFront for global caching, TLS, WAF, and origin protection; S3 website endpoint is HTTP-only and public (dev/testing); ALB directly gives you nothing at the edge and exposes origin capacity to the internet. Production static/dynamic → CloudFront.
26. **Q:** Weighted routing vs failover records in Terraform?
**A.** Weighted for gradual rollout/canary and A/B (`weighted_routing_policy { weight }`); failover for active-passive DR with health checks. You can nest them (weighted inside a failover set of records) but complexity grows — document the routing intent in code comments because DNS config is hard to read.
27. **Q:** One CloudFront distribution per environment vs shared?
**A.** Per environment is the standard (isolation, different TTLs/behaviours, safe WAF testing); shared distributions with path-based environments invite cache/WAF/config coupling and make changes risky. Cost of extra distributions is low relative to the risk.
28. **Q:** Health checks on every record vs only failover-critical ones?
**A.** Health checks cost money per check and add complexity; they're only useful where routing decisions depend on health (failover, latency, weighted with health). Don't blanket-enable them — monitoring is what CloudWatch/synthetics are for.

**🎯 Senior**
29. **Q:** What does production-grade global DNS/edge configuration look like in Terraform?
**A.** Zones centrally owned with delegation sets and IaC-managed records; alias records (not CNAMEs) to AWS endpoints with `evaluate_target_health` where failover matters; health checks that exercise a real dependency-aware path with alerts on state changes; low TTLs (30–60 s) for failover-critical records; ACM certificates validated by Route 53 records with expiry monitoring; CloudFront with OAC + private buckets, managed cache policies, HTTPS-only, WAF associated and logging, access logs with retention, and content deployed by the app pipeline using versioned filenames; plus a documented, rehearsed failover drill with measured RTO.

**🎯 Senior signal:** "CloudFront certs must be in us-east-1", "distribution updates are slow — keep content out of them", and "DNS failover is TTL-bounded". Those three are the fingerprints of hands-on edge experience.
