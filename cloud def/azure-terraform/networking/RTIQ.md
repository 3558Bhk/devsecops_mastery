# RTIQ — Terraform Networking on Azure (Real-Time Interview Questions)

> **Cloud:** Azure · **Tool:** Terraform · **Domain:** VNet/subnets, NSGs/ASGs, load balancing (LB/App Gateway/Front Door) · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~29 min

**How this file is used live:** Azure network rounds are usually whiteboard-plus-plan-review: build a VNet module, then explain why the plan changes 12 things when you expected one. Interviewers push on subnet delegation, private endpoints and DNS, NSG rule ordering, and the LB/App Gateway/Front Door decision tree.

**Legend:** ⚡ Rapid · 🔍 Deep dive · 🚨 War room · ⚖️ Trade-off · 🎯 Senior signal

---

## 1. VNet & Subnets — `vnet-subnets.md`

**⚡ Rapid**
1. **Q:** Core Terraform resources for a VNet?
**A.** `azurerm_virtual_network`, `azurerm_subnet` (or `azurerm_subnet` with delegations), optional `azurerm_subnet_nat_gateway_association`, and `azurerm_virtual_network_peering` (both directions). Subnets are often created in the same module as the VNet to keep routing/NAT consistent.
2. **Q:** What are the special subnets you must plan for?
**A.** `GatewaySubnet` (VPN/ExpressRoute, /27+ recommended), `AzureFirewallSubnet` (/26 recommended), `AzureFirewallManagementSubnet` (forced tunnelling), `AzureBastionSubnet` (/26+), and service-delegated subnets (App Service VNet integration/`Microsoft.Web/serverFarms`, Container Apps, etc.). Names are fixed by the platform — no freedom there.
3. **Q:** How do you compute subnets instead of hardcoding?
**A.** `cidrsubnet(var.address_space, newbits, netnum)` with a map of subnet definitions, so the address plan is data and validated (e.g. no overlaps, correct sizes for special subnets). Validating sizes avoids discovering at apply time that `AzureBastionSubnet` is too small.
4. **Q:** How do you write the two peerings?
**A.** Two `azurerm_virtual_network_peering` resources (spoke→hub and hub→spoke) with the right flags: `allow_forwarded_traffic = true` on the spoke→hub peering (for traffic via NVAs), `allow_gateway_transit = true` on the hub side, `use_remote_gateways = true` on spokes, and `allow_virtual_network_access = true`. Each peering has its own flags — forgetting the pair is the classic "connected but nothing works".
5. **Q:** How do you attach a NAT gateway?
**A.** `azurerm_nat_gateway` + `azurerm_public_ip` (or prefix) + `azurerm_subnet_nat_gateway_association` per subnet — the modern replacement for default outbound access. Terraform owns both the gateway and the association; the association is what people forget.
6. **Q:** How do you create private endpoints and DNS?
**A.** `azurerm_private_endpoint` (subnet + private service connection) plus a private DNS zone (`azurerm_private_dns_zone`, e.g. `privatelink.blob.core.windows.net`) and `azurerm_private_dns_zone_virtual_network_link`, with the A record usually auto-registered by the endpoint. Missing the zone link is why clients still resolve public IPs.
7. **Q:** How do you handle DNS for hybrid (on-prem ↔ Azure)?
**A.** `azurerm_private_dns_resolver` with inbound/outbound endpoints + forwarding rules, or custom DNS VMs with conditional forwarders configured via cloud-init/extension. In Terraform, DNS resolver endpoints are subnet-delegated (`Microsoft.Network/dnsResolvers`) — plan those subnets.
8. **Q:** What is `azurerm_subnet` delegation used for?
**A.** Allowing a specific service to inject/control resources in the subnet (App Service VNet integration, Container Apps environments, PostgreSQL Flexible Server, DNS resolver). It's a hard constraint on what else can live in that subnet — one reason to plan subnets per purpose.

**🔍 Deep dive**
9. **Q:** Design a VNet module for a 3-environment Azure landing zone.
**A.** Inputs: `name/prefix`, `environment`, `region`, `address_space`, `subnets` (map of objects with `cidr`, `delegations`, `service_endpoints`, `nat_gateway`, `nsg_id`), `enable_bastion/firewall/gateway_subnet`, `peerings` (list of remote VNet IDs + flags), `dns_zone_links`. Internals: `for_each` over the subnet map (stable keys), validations (address ranges within VNet, minimum sizes, no reserved-name collisions), gateway/firewall/bastion subnets created first, NSG associations and UDRs applied per subnet via inputs, flow logs at the VNet level, and tags/naming from a shared module. Outputs: `vnet_id`, `subnet_ids` (map by name — never a list), and `vnet_name`.
**↳ Follow-up:** "A new subnet is needed for a PaaS service — what's the change?"
**A.** Add an entry to the `subnets` map and apply: `for_each` creates only that subnet and its associations. If it needs delegation, add it in the map (the module handles the delegation block) — and validate the requested size against the service's minimums so the apply doesn't fail.
10. **Q:** How do you handle UDRs/route tables in Terraform?
**A.** `azurerm_route_table` + `azurerm_route` (with `next_hop_type = "VirtualAppliance"` and the firewall's private IP) + `azurerm_subnet_route_table_association`; keep route tables per purpose (app subnets forced through the firewall, gateway subnets excluded, data subnets with no internet route). The association is the step that actually applies it — verify with an empty plan and effective routes.
11. **Q:** How do you avoid Terraform breaking private-endpoint DNS?
**A.** Create the zone + links before/with the endpoint, use `private_dns_zone_group` on the endpoint (which registers A records), and avoid managing the same A record both manually and via the endpoint. For cross-team scenarios, host the zones centrally (hub/platform root) and link them to workload VNets — otherwise every team creates duplicate zones and resolution becomes unpredictable.
12. **Q:** How do you express "no public IPs" for subnets?
**A.** Subnets don't have public IPs (resources do), but you can enforce it: no `azurerm_public_ip` in workload modules, Policy denying public IP creation, NAT gateway for egress, private endpoints for PaaS, and Bastion for access. In code review, the presence of a public IP association is a finding — make the module not even offer it.
13. **Q:** How do you handle service endpoints in Terraform?
**A.** `service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", ...]` on the subnet (or `azurerm_subnet_service_endpoint_storage_policy` where applicable), combined with the PaaS resource's network rules allowing that subnet. Service endpoints are the cheaper/simpler alternative to private endpoints but leave the PaaS resource publicly reachable *except* from approved subnets — a distinction many teams discover during audits.
14. **Q:** What are the common Azure networking gotchas in Terraform?
**A.** Subnet deletion while resources exist (Azure refuses), address-space changes forcing VNet replacement (destructive — plan carefully), `GatewaySubnet` routing through a firewall breaking VPN, needing a `depends_on` because the private endpoint's DNS registration is asynchronous, and peering flags. Also: some subnets can't be deleted once delegated without removing the service first.
15. **Q:** How do you test a network module?
**A.** Apply it in a sandbox subscription, verify with `az network vnet subnet list`/effective routes, run connectivity tests (Network Watcher, or a test VM with curl), and include a plan-only check in CI for the module. Then add a post-apply smoke test in the pipeline for changes to shared networks — network changes are the least reversible.

**🚨 War room**
16. **Q:** A plan wants to replace the VNet. What do you do?
**A.** Stop. Find the forcing attribute — usually `address_space` change, name change, or region change. VNet replacement destroys all subnets and (in practice) forces the resource migration. If the address space genuinely must expand, note that Azure supports adding address space to an existing VNet (additive) — a config change that shouldn't force replacement if done via an additional `address_space` entry; if the plan still wants replacement, verify the provider behaviour and plan the migration explicitly.
17. **Q:** After a subnet change, every VM in the subnet lost internet access.
**A.** The route table association or NAT gateway association changed (or the UDR now points 0.0.0.0/0 at a firewall that isn't there/doesn't allow it). Compare effective routes for a NIC before/after, check the NAT association, and revert. Add post-apply connectivity tests for shared networks so this is caught in the pipeline, not by users.
18. **Q:** Private endpoints were created but apps still use public IPs.
**A.** DNS: the private DNS zone isn't linked to the app's VNet, the app caches DNS, or the resource's public access is still enabled and the app resolves the public endpoint. Verify with `nslookup` from inside the VNet, check zone links and the endpoint's DNS zone group, and (where required) disable public network access on the PaaS resource to force the private path.
19. **Q:** Two teams created private DNS zones with the same name in different resource groups.
**A.** Split-brain DNS: clients resolve against whichever zone is linked to their VNet, causing intermittent failures. Consolidate to a single central zone per service (usually in the hub/platform RG), delete/link-update the duplicates, and enforce zone ownership with Policy/RBAC so teams can't create conflicting zones.
20. **Q:** Peering is up but spoke-to-spoke traffic fails.
**A.** Peering is non-transitive: traffic must route via the hub firewall (UDRs both ways) and the firewall must allow it. Check the spoke's route table, the firewall's network rules, and — if the design intends spoke-to-spoke — that the hub's peering flags (`allow_forwarded_traffic`) are set. Don't create direct spoke-to-spoke peerings to "fix" it; you'd bypass inspection.
21. **Q:** An apply failed because `GatewaySubnet` is too small for the gateway SKU.
**A.** Resize the subnet (Azure allows resizing if no resources/delegations conflict) and re-apply; the gateway may need to be recreated if the SKU demands more. Then add validation to the module (min /27 for gateway, /26 for firewall/bastion) so it fails at plan time with a clear message rather than mid-apply.
22. **Q:** Flow logs were disabled for a VNet during a debugging session and never re-enabled.
**A.** Re-enable via the module (Terraform will correct it if configured), then add detection: a Config/Policy check that asserts flow logs exist, an alert on `DeleteFlowLogs`/log-group changes, and Terraform-managed flow log resources so the drift is visible in the next plan. Logging gaps are both a compliance issue and an anti-forensics signal.

**⚖️ Trade-off**
23. **Q:** Private endpoints vs service endpoints?
**A.** Private endpoints (private IP in your VNet via PrivateLink) remove public exposure, work cross-region/on-prem, and cost per endpoint + DNS work; service endpoints (subnet-level routing to the PaaS) are free and simpler but the resource keeps a public endpoint protected by VNet rules. Regulated/sensitive → private endpoints; internal convenience → service endpoints.
24. **Q:** Hub-and-spoke with a central firewall vs per-spoke egress?
**A.** Central: one policy/log/inspection point, shared cost, but a shared bottleneck and blast radius plus a data-processing cost; per-spoke: isolation and no hairpin, but duplicated policy and higher operational overhead. Centralise for governance, and keep chatty traffic local (same VNet/region).
25. **Q:** One VNet with many subnets vs many VNets?
**A.** One VNet simplifies routing/no peering costs and is fine for a single app/environment; many VNets give isolation, independent address spaces, and per-team ownership at the cost of peering/DNS complexity. Split by environment and trust boundary.
26. **Q:** Terraform-managed NAT gateway vs Azure's default outbound?
**A.** Default outbound access is being retired and gives you no control over source IPs or logging; a NAT gateway gives static egress IPs (allow-listing), scalable SNAT, and predictability at an hourly+GB cost. For production workload subnets, NAT gateway is the right default — and it's a Terraform resource you own.
27. **Q:** Bastion vs VPN vs JIT for administrative access?
**A.** Bastion: managed jump host over TLS in the portal/CLI, no public IPs on VMs (needs `AzureBastionSubnet`); VPN/P2S: broader network access for many users/apps; JIT (Defender): opens temporary NSG rules on demand. Terraform manages the infrastructure for all three, but the policy (who gets in, for how long) lives in RBAC/JIT configuration.
28. **Q:** Manage the hub network in the same root as spokes, or separate?
**A.** Separate roots with the hub owned by the platform team and spokes by workload teams, connected via peerings created where the ownership is clearest (often the spoke root creates both peerings using a hub VNet ID input). Coupling them into one root means a workload change can threaten shared connectivity.

**🎯 Senior**
29. **Q:** What does a production VNet module include on Azure?
**A.** Address-space and subnet planning as validated data (including correctly sized GatewaySubnet/Firewall/Bastion/delegated subnets); NSG and route-table associations per subnet via inputs; NAT gateway for egress with a static public IP; private DNS zone links with central zone ownership; subnet-level delegations and service endpoints where needed; VNet flow logs to a central workspace with retention; peering with explicit flags and both directions; `prevent_destroy` on the VNet and shared subnets; outputs of keyed subnet maps; and post-apply connectivity smoke tests in the pipeline.

**🎯 Senior signal:** "peering flags are per-direction and both matter", central private-DNS zone ownership to avoid split-brain, and `cidrsubnet`-driven address plans with validation for platform-required subnet sizes. Those three are Azure networking maturity.

---

## 2. NSG & Security — `nsg-security.md`

**⚡ Rapid**
1. **Q:** Core NSG resources?
**A.** `azurerm_network_security_group`, `azurerm_network_security_rule` (standalone rules) or inline `security_rule` blocks, and `azurerm_subnet_network_security_group_association` / `azurerm_network_interface_security_group_association`. Also `azurerm_application_security_group` and ASG membership via NIC configuration.
2. **Q:** Inline rules vs standalone rule resources?
**A.** Standalone (`azurerm_network_security_rule`) avoids rewriting the whole NSG on a single rule change and works better with `for_each` over rule sets; inline blocks keep it compact but couple all rules' lifecycles. For anything dynamic, separate resources.
3. **Q:** How do rule priorities work?
**A.** 100–4096, lower number wins, first match decides; the platform defaults (AllowVnetInBound 65000, AllowAzureLoadBalancerInBound 65001, DenyAllInBound 65500) sit at the bottom. Leave gaps (100, 200, 300) so rules can be inserted later without renumbering.
4. **Q:** What are Azure's service tags and when do you use them?
**A.** Named IP groups maintained by Microsoft (`VirtualNetwork`, `Internet`, `AzureLoadBalancer`, `GatewayManager`, `AzureCloud.<region>`, `Storage`, `Sql`, `AzureFrontDoor.Backend`). Use them instead of IP lists — but for private connectivity prefer private endpoints over tag-based allows.
5. **Q:** How do ASGs help?
**A.** `azurerm_application_security_group` groups NICs so rules can reference "web → app" instead of IPs; membership is set on the NIC/VMSS network interface (or via the module's NIC config). ASGs only work within the same VNet — cross-VNet peer traffic can't be filtered by ASG.
6. **Q:** What must every NSG have for load balancers to work?
**A.** Inbound allowance for `AzureLoadBalancer` (and `GatewayManager` for App Gateway/Bastion subnets) — otherwise health probes/management traffic is blocked and backends are marked unhealthy even though the app is fine. This is the most common self-inflicted Azure NSG incident.
7. **Q:** How do you enforce "no 0.0.0.0/0 on 22/3389"?
**A.** Policy (deny `Microsoft.Network/networkSecurityGroups` rules with those sources/ports, or use the built-in rule/policy), CI policy checks (checkov/OPA) on plans, Config-style compliance checks, and — architecturally — no SSH/RDP at all (Bastion/SSH-over-Azure-AD). Defence in depth: the rule shouldn't be expressible, and its absence shouldn't matter.
8. **Q:** How do you log NSG activity?
**A.** Flow logs (VNet/NSG flow logs) to Storage/Log Analytics with Traffic Analytics; `azurerm_network_watcher_flow_log` in Terraform. Also enable NSG diagnostics for rule-hit visibility. Without flow logs you can't prove segmentation or debug denies.

**🔍 Deep dive**
9. **Q:** Design NSG rules for a 3-tier app in Terraform and validate them.
**A.** Tiers as ASGs (`asg-web`, `asg-app`, `asg-db`); rules: inbound 443 from `AzureFrontDoor.Backend`/App Gateway subnet to `asg-web`; `asg-web` → `asg-app` on the app port; `asg-app` → `asg-db` on the DB port; explicit denies for internet-sourced admin ports; outbound restricted to endpoints/required CIDRs where feasible; `AzureLoadBalancer` allowed on probe ports. Validation: a mixed approach — NSG flow logs plus a scheduled connectivity test (Network Watcher connectivity check) between tiers, a generated approved-flows matrix, and CI policy checks that reject public admin ports. Then verify with effective rules and deny-hit dashboards.
**↳ Follow-up:** "Traffic between the app and DB is failing — where do you look first?"
**A.** Effective security rules on both NICs (both the subnet NSG and the NIC NSG must allow it), the ASG membership of both NICs, then routes/firewall (a UDR may send the traffic through a firewall that blocks it). Order matters: NSG union → routing → resource-level firewall (the DB's own firewall) → host firewall.
10. **Q:** How do you manage NSG rule sets at scale without sprawl?
**A.** Standard rule sets per tier published as a module (a `tier_rules` input), ASGs instead of IP lists, centralised special-case rules in one place with owners and expiry (documented exceptions), and a naming/priority convention enforced by the module. Then use policy-as-code to reject the patterns you've decided against (any-to-any, internet-to-admin).
11. **Q:** How do you handle a rule that must allow many partner IPs?
**A.** An IP group (`azurerm_ip_group`) referenced by the rule (Azure Firewall) or a maintained list applied via `for_each` in Terraform — with an owner and a review cadence. Better: private endpoint/PrivateLink or mTLS rather than IP allow-listing, since partner IPs change without notice.
12. **Q:** How do you handle NSG rules for Azure PaaS services?
**A.** Prefer private endpoints (then the traffic is VNet-internal and NSG rules apply to the endpoint subnet); if using service endpoints, allow the PaaS service tag on egress and restrict the PaaS resource's network rules to the subnet. Also remember the PaaS firewall itself is a second control — both must allow.
13. **Q:** How do you structure NSG resources in the repo?
**A.** NSGs created with the subnet (in the network module or the workload's network section) and rules defined as a typed map input so services declare intent ("allow app→db 1433"), with the module translating to resources. NSGs far from the resources they protect get stale fast.
14. **Q:** How do you handle NSG changes in CI?
**A.** Plan review showing the rule diff explicitly (rules as separate resources make this readable), policy checks on the plan (no internet admin ports, no any-to-any within the VNet, required tags), and post-apply validation for critical paths. Treat NSG changes like firewall rule changes: they're security-relevant, so review and evidence matter.
15. **Q:** What's the risk with "temporary" NSG rules?
**A.** They become permanent: `any → any` rules added during an incident are never removed and silently widen the blast radius (and auditors find them). Control with an expiry tag/metadata plus a scheduled report that flags rules older than N days, and route emergency changes through a documented break-glass process that requires follow-up.

**🚨 War room**
16. **Q:** A rule opened 22/3389 to the internet and merged. Response?
**A.** Revoke immediately (fast apply or direct CLI change — don't wait for the pipeline), check NSG flow logs and Azure AD sign-ins for successful logins in the exposure window, rotate credentials/keys on affected VMs, and notify per policy. Then prevent: policy-as-code gate on plans, Policy deny at the subscription level, and an Activity Log alert on NSG rule creation with internet sources on admin ports.
17. **Q:** All App Gateway backends are unhealthy after an NSG tightening.
**A.** The tightened NSG likely removed the `GatewayManager` inbound allowance (port 65200–65535) or the `AzureLoadBalancer` probe allowance on the backend, or blocked the app port. Restore the standard App Gateway rule set from the module (that's why it should be a module, not hand-written), and verify via the backend health blade.
18. **Q:** Intermittent connectivity from one subnet to another, NSGs look correct.
**A.** Check ASG membership (a new instance not in the ASG is denied by default), the route table/UDR sending traffic through a firewall, the destination's own firewall (e.g. Azure SQL's firewall rules), and whether both NSG layers (subnet + NIC) are involved. "Correct rules" usually means one of these four.
19. **Q:** A security review found `AllowVnetInBound` being relied on for east-west traffic.
**A.** That's an implicit trust assumption — any compromised host in the VNet can reach anything. Remediate by explicitly allowing only the required tier-to-tier flows (ASG-based) and denying the rest, then verify with flow logs that only expected flows occur. Add a CI/policy check to prevent new reliance on VNet-wide allows.
20. **Q:** NSG flow logs show denied traffic from an unexpected source to a database port.
**A.** Investigate the source (is it a legitimate dependency with a missing rule, or reconnaissance/lateral movement?), check whether anything was allowed in the same window, and involve security if it looks adversarial. If legitimate, add the narrowest rule; if not, quarantine the source and review its exposure. Either way, the flow log did its job — keep them on.
21. **Q:** A team added a firewall rule instead of an NSG rule and now traffic is blocked in a confusing place.
**A.** Clarify the layers (NSG at subnet/NIC, Azure Firewall for FQDN/L7 policy, service firewalls like SQL/Storage) and document which layer owns which decisions. Then fix the specific flow at the right layer and add a runbook snippet explaining the decision tree — most "NSG problems" are layer-confusion.
22. **Q:** NSG rule change caused a production outage at 2 a.m.; the change was made directly in the portal.
**A.** Restore service (revert the rule), then cause-analysis: who made the change, why (approved?), and why Terraform didn't revert it (drift not detected/plan not running). Fix the process: read-only human access in production, plan-based drift detection with alerts, Policy denying rule patterns, and a documented break-glass path with post-incident codification.

**⚖️ Trade-off**
23. **Q:** NSG on subnet vs NIC?
**A.** Subnet-level for consistent policy across all resources in the segment (the default); NIC-level for workload-specific needs. Both are evaluated (union for allows), so a NIC NSG can only add restrictions/allowances on top — two layers make debugging harder, so use it sparingly.
24. **Q:** ASG-based rules vs IP/subnet-based rules?
**A.** ASG references express intent, survive scaling/IP changes, and support micro-segmentation, but require membership management (automate it in the NIC/VMSS module) and only work within a VNet. IP/CIDR rules are needed across VNets/on-prem and for external parties, but rot quickly. ASGs internally, CIDR/prefix lists at the boundary.
25. **Q:** NSG + Azure Firewall vs NSG only?
**A.** NSG only: free L3/L4 filtering, no FQDN awareness, no central logging of L7; NSG + Firewall: central L7 policy (FQDNs), threat intel, and unified logging at the cost of a hub appliance, extra hop, and data-processing charges. FQDN policy or egress inspection requirements decide.
26. **Q:** Deny-by-default inside the VNet vs trusting intra-VNet traffic?
**A.** Deny-by-default with explicit tier flows is the security-correct posture (limits lateral movement) and works well with ASGs; trusting the VNet is easier but means any compromised host reachable to your services. For regulated environments, deny-by-default is expected — and flow logs prove it.
27. **Q:** One NSG per subnet vs one shared NSG across subnets?
**A.** Shared NSGs are convenient (fewer objects) but couple unrelated workloads' security posture and make changes risky; per-subnet/per-tier NSGs are clearer and safer. Share only between genuinely identical tiers (e.g. all web subnets in an environment).
28. **Q:** Manage NSGs in the network module vs the workload module?
**A.** NSGs for a workload's own subnets belong with the workload (so the app team can express its flows and own the change), while shared/hub NSGs belong to the platform team. Cross-boundary rules should be explicit interfaces (the platform publishes the firewall/hub IPs, the workload declares its flow).
29. **Q:** Emergency rule changes made directly vs waiting for the pipeline?
**A.** Break glass is legitimate during an incident — speed matters — but it must be logged, time-boxed, and codified or reverted afterwards. The alternative (waiting for a pipeline in an outage) is worse. What's unacceptable is a permanent unmanaged rule; detect it with drift plans.

**🎯 Senior**
30. **Q:** What's your NSG standard in Terraform for production?
**A.** NSGs per tier/subnet with ASG-or-subnet references rather than IP lists where possible; standalone rule resources with gaps in priority numbering and a naming convention expressing intent; explicit `AzureLoadBalancer`/`GatewayManager` allowances for LB/App Gateway paths; no 0.0.0.0/0 on admin ports (Policy + CI enforced); deny-by-default rather than relying on `AllowVnetInBound`; flow logs + Traffic Analytics to a central workspace with deny dashboards; changes deployed only via the pipeline with plan review and post-apply connectivity tests; and a documented, time-boxed break-glass path for incidents.

**🎯 Senior signal:** "ASG membership is the usual reason a rule 'doesn't work'", the App Gateway `GatewayManager`/probe requirement, and deny-by-default inside the VNet. Those three are Azure operations maturity.

---

## 3. Load Balancing — `load-balancing.md`

**⚡ Rapid**
1. **Q:** Which Azure load-balancing services exist, and how do you choose?
**A.** Load Balancer (L4: TCP/UDP, private or public, zone-redundant), Application Gateway (L7: HTTP/S, URL/host routing, WAF, TLS termination), Front Door (global L7 anycast with edge caching/WAF and fast failover), and Traffic Manager (DNS-based global routing). L4 → LB; regional L7 with WAF → App Gateway; global edge → Front Door; DNS-only steering → Traffic Manager.
2. **Q:** Core Terraform resources for Load Balancer?
**A.** `azurerm_lb` (SKU Standard, zone-redundant frontend), `azurerm_lb_backend_address_pool`, `azurerm_lb_probe`, `azurerm_lb_rule`, `azurerm_public_ip` (Standard, zone-redundant), and `azurerm_network_interface_backend_address_pool_association` (or the VMSS's pool association).
3. **Q:** For Application Gateway?
**A.** `azurerm_application_gateway` with frontend IP/configs, listeners (with `ssl_certificate` from Key Vault via `key_vault_secret_id` + managed identity), `backend_address_pool`s, `backend_http_settings` (probe), `http_listener`, `request_routing_rule`, and `probe`. It's one large resource — so most teams wrap it in a module with typed inputs.
4. **Q:** For Front Door?
**A.** `azurerm_cdn_frontdoor_profile`, `azurerm_cdn_frontdoor_endpoint`, `azurerm_cdn_frontdoor_origin_group`, `azurerm_cdn_frontdoor_origin` (with `private_link` for private backends), `azurerm_cdn_frontdoor_route`, and `azurerm_cdn_frontdoor_firewall_policy` for WAF.
5. **Q:** What's the App Gateway subnet/NSG requirement?
**A.** A dedicated subnet (no other resources), sized for autoscaling instances (a /24 is common), with NSG rules allowing `GatewayManager` (65200–65535) inbound and outbound to the backend, plus `AzureLoadBalancer`. Getting the subnet size wrong limits how many instances you can scale to.
6. **Q:** How do you attach TLS certificates?
**A.** Key Vault certificates referenced via `key_vault_secret_id` with the gateway's managed identity granted `Key Vault Secrets User` (or a `Certificate`/`Secrets` access policy) — the modern approach, since renewals are picked up automatically. Uploaded PFX in config is legacy and won't rotate.
7. **Q:** How do you do WAF in Terraform?
**A.** `azurerm_web_application_firewall_policy` with managed rule sets (OWASP/DRS, bot manager), custom rules (rate limits, geo blocks), exclusions, and `mode` — associated with App Gateway (`firewall_policy_id` on the gateway) or Front Door (per-route). Start new rules in `Detection` mode, tune, then `Prevention`.
8. **Q:** How do you do health probes?
**A.** `azurerm_lb_probe` (L4: TCP/HTTP with a port) for Load Balancer; `probe` blocks in App Gateway (path, interval, timeout, `match` on status codes/body, `host`) for L7. The probe path should reflect app readiness — but be careful about failing on shared dependencies (blast radius).

**🔍 Deep dive**
9. **Q:** Design global ingress for a multi-region Azure app with WAF and zero-downtime deploys.
**A.** Front Door Premium (custom domain + managed cert, WAF policy with rate limits, origin groups per region with health probes) → per-region Application Gateway v2 (WAF, TLS from Key Vault, URL routing, private backends) → VMSS/App Service with private endpoints and no public access. Deploys: region-by-region with Front Door health probes removing a draining region, plus weighted origins for canary. Observability: Front Door access/WAF logs + App Gateway diagnostics to Log Analytics, alarms on origin health/5xx/latency, and synthetic checks per region. All in modules with the WAF policy and routing rules as typed inputs.
**↳ Follow-up:** "How do you make the backends unreachable except through the gateway?"
**A.** Private endpoints (or `internal` App Gateway) plus NSG rules allowing only the gateway subnet; for App Service, access restrictions allowing `AzureFrontDoor.Backend`/the gateway. Then verify from outside that the direct endpoint is blocked — an ingress with a reachable origin isn't really protected.
10. **Q:** How do you do zero-downtime App Gateway deployments/changes?
**A.** App Gateway v2 supports autoscaling and doesn't restart on most config changes; but some changes (subnet, SKU, zone) require reconfiguration and can brief disruption. Approach: make changes in-place where supported, use `create_before_destroy` for listeners/certs, and validate with `terraform plan` for replacements. For risky changes, deploy a second gateway and switch DNS/Front Door origins. Test the plan—App Gateway changes are slow (10–30 min) so the pipeline needs generous timeouts.
11. **Q:** How do you configure autoscaling on App Gateway v2?
**A.** `autoscale_configuration { min_capacity, max_capacity }` with capacity units computed from traffic (CPU/connections/throughput); min ≥2 (≥3 for zone redundancy best practice) and max sized against subnet IP capacity. Set alerts on capacity-unit utilisation. v1 SKUs have no autoscale — another reason v2 is the default.
12. **Q:** How do you handle multiple apps/domains on shared ingress?
**A.** Front Door routes per domain, App Gateway multi-site listeners + request routing rules (host/path based) with per-site certificates from Key Vault, and per-backend-pool probes. As rule counts grow, watch limits and prefer finer-grained gateways per domain cluster — a 200-rule gateway becomes a change bottleneck.
13. **Q:** How do you do weighted/canary routing in Terraform?
**A.** Front Door origins with `weight` per origin group (or separate origin groups with priority), or App Gateway with multiple backend pools and rules — but App Gateway's weighting is limited, so canary is more usually done at Front Door, in Kubernetes (via an ingress controller with weights), or with App Service deployment slots + traffic routing (`azurerm_app_service_slot`/`traffic_route` blocks). Choose the layer that supports the strategy you need and keep the weights in code so changes are reviewed.
14. **Q:** How do you handle Azure Load Balancer for a stateful service?
**A.** Standard internal LB with a zone-redundant frontend, backend pool spanning zones, `floating_ip`/`idle_timeout_in_minutes` tuned, and session persistence only if required (`load_distribution` values like `SourceIP`); the app must handle connection draining. Prefer stateless backends — persistence is a scaling and deployment liability.
15. **Q:** How do you manage ingress certificates and their renewal?
**A.** Key Vault-issued certificates (via `azurerm_key_vault_certificate` or an integrated CA) referenced by `key_vault_secret_id` (versionless) so renewals propagate, with the gateway/front door's managed identity granted secrets access, and alerts on certificate expiry (Key Vault events/alarms). Terraform should not hold the PFX.
16. **Q:** What are the ingress failure modes you design against?
**A.** Backend health flapping (probe path/port mismatch, NSG blocking probes), certificate expiry, capacity exhaustion (App Gateway/subnet), TLS/protocol mismatches between gateway and backend, and single-region dependency. Each maps to a Terraform-controlled resource (probe, cert, autoscale, backend HTTP settings) — that's the point to make.

**🚨 War room**
17. **Q:** An apply replaced the Application Gateway and caused 20 minutes of downtime.
**A.** Identify the forcing attribute (subnet change, SKU change, zone config, or a `name` change) — those require replacement. Prevent: `create_before_destroy` isn't sufficient for App Gateway alone; instead avoid replacement-forcing changes, migrate by building a new gateway alongside and switching DNS/Front Door origins, and add a plan-level policy that flags replacement of ingress resources for manual approval.
18. **Q:** Front Door returns 502s; origins look healthy.
**A.** Check origin health probe configuration (path, host header, protocol/port, status codes — a probe hitting HTTPS on an HTTP listener marks unhealthy), private-link origin configuration, and whether a recent WAF rule is blocking (403 vs 502 distinction). Compare Front Door access logs to origin logs to find which hop fails.
19. **Q:** App Gateway backends all show unhealthy after a Key Vault/permission change.
**A.** The gateway's managed identity lost `Key Vault Secrets User`/certificate access, so the listener certificate couldn't be read (that surfaces as listener/probe failures), or the backend's own TLS certificate changed. Verify the identity's role assignment and the Key Vault diagnostic logs for denied reads; re-grant narrowly.
20. **Q:** Latency through the ingress tripled with no traffic change.
**A.** Common causes: a WAF rule set addition (inspection cost), backend HTTP settings with a slow probe/health churn, connections not being reused (backend HTTP settings), an autoscale minimum too low with capacity-unit saturation, or traffic now hair-pinning through a firewall/NVA because of a route change. Look at the ingress's own metrics first (capacity units, backend response time) to separate gateway cost from backend cost.
21. **Q:** The WAF blocked a legitimate customer's traffic.
**A.** Reproduce and identify the rule (WAF logs with match details), switch to Detection (or add a targeted exclusion for the specific rule+argument) immediately, then re-enable Prevention for that rule group after confirming the exclusion is narrow. Communicate to the customer, and add the case to the tuning notes — an untuned WAF in Prevention will keep doing this.
22. **Q:** Terraform shows drift on an App Gateway every plan (tags/settings flip-flopping).
**A.** Something outside Terraform (a policy `modify` tag, an autoscale-driven capacity change, or a portal change) is modifying fields Terraform manages. Decide ownership per field and use `ignore_changes` only for genuinely externally-managed fields, documenting why; then re-verify the plan is empty. Persistent non-empty plans erode trust in the pipeline.

**⚖️ Trade-off**
23. **Q:** Application Gateway vs Front Door vs both?
**A.** Front Door alone works for global HTTP(S) with edge WAF/caching and private backends; App Gateway adds regional L7 (URL routing, WAF in-region, integration with private VNets/subnets) and is often needed when backends are private or when regional policy requires in-region termination. Many designs use both (Front Door → App Gateway) — accept the extra hop for the additional control.
24. **Q:** Load Balancer vs Application Gateway for an internal API?
**A.** LB (L4) if you need raw performance/any TCP protocol or you're fronting something that isn't HTTP-aware (Kubernetes internal services, databases, custom protocols); App Gateway for HTTP routing, TLS termination, WAF, and header manipulation. HTTP with any L7 need → App Gateway.
25. **Q:** Azure Load Balancer Standard vs Basic SKU?
**A.** Standard: zone-redundant option, secure by default (NSG required for inbound), HA ports, outbound rules, SLA; Basic is legacy with no SLA and open by default. Always Standard for production (and it's a prerequisite for newer features).
26. **Q:** Public vs internal ingress for internal APIs?
**A.** Internal (private IP) for service-to-service and admin APIs — no public exposure, reachable via VNet/peering/VPN; public only for genuinely external consumers, always behind WAF. Many "public" APIs should be internal + Front Door/PrivateLink-fronted for partners.
27. **Q:** WAF in Prevention vs Detection during rollout?
**A.** Detection for new rule sets/custom rules while you build exclusions from real traffic (typically 1–2 weeks), then Prevention. Keeping everything in Detection means you have logging but no protection; jumping straight to Prevention causes customer-facing false positives. Say the staged approach.
28. **Q:** Manage ingress per environment in one root vs separate?
**A.** Per-environment roots (or at least per-environment resources) so a WAF/routing change in dev can't touch production, with the module shared. Shared production/dev ingress is a blast-radius mistake no team deliberately makes twice.
29. **Q:** Route traffic at the DNS layer (Traffic Manager) vs the data path (Front Door)?
**A.** Traffic Manager: cheap, protocol-agnostic, DNS-cached (failover in minutes); Front Door: anycast data path with seconds-scale failover, caching, and WAF, but HTTP(S) only and priced accordingly. Match to the RTO and protocol requirements.

**🎯 Senior**
30. **Q:** What does production-grade ingress look like in Terraform on Azure?
**A.** Front Door Premium (managed certs, WAF in Prevention with tuned exclusions, origin groups with health probes and weighted canary) → per-region zone-redundant App Gateway v2 (autoscale min 3, TLS from Key Vault via managed identity, private backends) → backends with private endpoints and no public access; NSGs allowing only gateway/probe sources; diagnostics and access/WAF logs to a central workspace with alerts on origin health, 5xx, latency, capacity units, and certificate expiry; synthetic checks per region; replacement-forcing changes gated by manual approval; and a documented, tested regional failover.

**🎯 Senior signal:** "the origin must be unreachable except through the gateway", App Gateway's subnet sizing as an autoscale limit, and Key Vault certificate references with the gateway's managed identity. Those three are real Azure ingress ownership.
