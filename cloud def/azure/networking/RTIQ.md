# RTIQ — Azure Networking (Real-Time Interview Questions)

> **Cloud:** Azure · **Domain:** VNet basics, NSGs (intro/inbound/outbound), ASGs, hub-and-spoke, VPN · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~43 min

**How this file is used live:** Azure networking rounds are connectivity-failure rounds. The interviewer draws a VNet, adds an NSG, a route table, a peered spoke, and a firewall, then says "the app can't reach the database — go". Knowing the *evaluation order* (NSG + Azure Firewall + route table) and the platform default rules wins this round.

**Legend:** ⚡ Rapid · 🔍 Deep dive + follow-ups · 🚨 War room · ⚖️ Trade-off debate · 🎯 Senior signal

---

## 1. Basic Networking — `basic-networking.md`

**⚡ Rapid**
1. **Q:** VNet, subnet, NIC — one line each?
**A.** VNet is an isolated address space (any RFC1918 range, non-overlapping with peers/on-prem), subnets segment it (some are reserved: GatewaySubnet, AzureFirewallSubnet, AzureBastionSubnet), and a NIC attaches a VM to a subnet and gets private IPs (plus optional public IP).
2. **Q:** Are subnets NSGs mandatory?
**A.** No, but no NSG means no filtering — and in Azure, *any* NSG (on either the subnet or the NIC) can affect the flow. Both are evaluated, per direction.
3. **Q:** What are the default outbound rules everyone forgets?
**A.** `AllowInternetOutbound`, `AllowVnetOutbound`, `AllowAzureLoadBalancerInbound` (health probes), and `DenyAllOutbound` — plus inbound `AllowVnetInBound`, `AllowAzureLoadBalancerInBound`, `DenyAllInBound`. Custom rules override defaults by priority (lower number wins).
4. **Q:** How do you give a private subnet outbound internet?
**A.** A NAT Gateway attached to the subnet (modern, scalable, static egress IPs) — or a public IP on the VM/NIC (bad practice), or a load balancer outbound rule (legacy). Default outbound access is being retired, so plan for NAT Gateway.
5. **Q:** What's the difference between a private IP and a public IP in Azure?
**A.** Private = RFC1918 inside the VNet, static or dynamic, NIC-attached. Public = internet-routable, can be attached to NICs, load balancers, NAT gateways, firewalls; SKUs (Basic/Standard) matter for availability zones and security features.
6. **Q:** How do you reserve and plan address space?
**A.** Plan /16 per environment with /24 subnets (leave room), avoid overlaps with on-prem and other VNets (peering cannot overlap), and reserve the special-purpose subnets. Re-IP'ing a VNet later means redeploying resources — address planning is a one-way door.

**🔍 Deep dive**
7. **Q:** Walk me through how a packet from the internet reaches a VM in a private subnet behind an App Gateway.
**A.** Internet → public IP (App Gateway, WAF) → App Gateway routes to the backend pool → the backend VM NIC's subnet NSG must allow the App Gateway's subnet/backend port → the route table must allow VNet-local traffic (system route) → the VM responds via the same path. If a UDR sends traffic to a firewall, the firewall must allow and return it, or you get asymmetric routing failures.
**↳ Follow-up:** "The App Gateway shows unhealthy backends; the app is up. Why?"
**A.** NSG blocking the GatewayManager service tag or the backend port, health probe path/port mismatch (probe hits HTTPS while the app serves HTTP, or the app returns a redirect/401 for `/`), the backend is in a different VNet without peering, or a UDR sending probe traffic to an appliance. Check the NSG flow logs and the probe's exact path.
8. **Q:** How does Azure route traffic inside a VNet by default?
**A.** System routes: subnet-to-subnet within the VNet, VNet-to-peered VNets, to on-prem via VPN/ExpressRoute (if gateway propagation is on), and 0.0.0.0/0 to the internet. UDRs override system routes with longest-prefix match — the key mechanism for firewalls, NVAs, and egress control.
9. **Q:** What is service delegation and when do you need it?
**A.** Delegating a subnet to a service (e.g. `Microsoft.Web/serverFarms` for App Service VNet integration, `Microsoft.ContainerInstance`) so the service can inject resources and manage that subnet — required for VNet-integrated PaaS and it comes with size/usage constraints.
10. **Q:** Private Endpoints vs Service Endpoints?
**A.** Private Endpoint: a private IP in your VNet for the PaaS resource (traffic never leaves the VNet/PrivateLink, per-resource, DNS via private zone). Service Endpoint: routes to the PaaS over the Azure backbone but the resource still has a public endpoint — access controlled with `Microsoft.*` service tags and firewall rules. Private Endpoint is the modern, stronger isolation; Service Endpoints are simpler and free.
11. **Q:** How do you handle DNS for private endpoints?
**A.** A private DNS zone (`privatelink.<service>.azure.com`) linked to the VNets, with the endpoint registered as an A record — then the PaaS FQDN resolves privately. Without this, clients resolve the public IP and either fail or bypass the private path. It's the number one private-endpoint gotcha.
12. **Q:** What happens if two VNets have overlapping address spaces and need to communicate?
**A.** Peering is impossible; options are redesign/re-IP, a NAT/translation layer via an NVA, PrivateLink (no CIDR dependence) for specific services, or a proxy. Call out that this is why IPAM (Azure Virtual Network Manager/IPAM) matters from day one.

**🚨 War room**
13. **Q:** A VM can't reach the internet. Diagnose in order.
**A.** Effective routes on the NIC (is 0.0.0.0/0 going to a firewall/NVA/blackhole?), effective NSG rules (outbound deny?), NAT gateway/subnet association, public IP needed if going via IGW equivalent, DNS resolution failing (test by IP), and the destination's own restrictions. Azure's "effective routes"/"effective security rules" blades are the fast path — mention them by name.
14. **Q:** Two subnets, same VNet, can't talk. Why?
**A.** NSG on either subnet/NIC, a UDR sending the traffic to an NVA that drops it (or doesn't return it), or the app binding/firewall inside the VM. Same-VNet traffic is allowed by default system routes, so a break is *always* NSG, UDR, or host-level.
15. **Q:** After adding a UDR to force egress through Azure Firewall, half the services broke. Explain.
**A.** Asymmetric routing or missing return path, firewall rules lacking FQDN/port exceptions, the firewall's own route table not allowing it, or the UDR sending VNet-local/Azure-service traffic to the firewall which then can't resolve/allow it. Fix by defining the full rule set (network + application rules) and keeping Azure-internal traffic (AzureCloud/Internet tags, private endpoint ranges) out of the forced path, or explicitly allowing it.
16. **Q:** A new subnet was created and workloads there can't reach on-prem.
**A.** The subnet's route table doesn't have the on-prem/VPN routes (UDRs are per-subnet), the gateway subnet status, or the NSG. Also check the virtual network gateway's route propagation setting (`EnableBGP`/propagate gateway routes) and whether the subnet is associated with the correct route table.
17. **Q:** Cost: your NAT gateway bill is huge and you don't know from where.
**A.** NSG flow logs + Traffic Analytics / VNet flow logs to Log Analytics, aggregated by destination IP and source VM — typically it's storage, backup, monitoring agents, or container image pulls. Then use private endpoints/service endpoints for Azure PaaS so the traffic doesn't traverse the NAT, and alert on NAT data volume.

**⚖️ Trade-off**
18. **Q:** Public IP on a VM vs Load Balancer vs NAT Gateway vs Bastion?
**A.** Public IP on a NIC = direct exposure, avoid in prod. Load Balancer/App Gateway for inbound, NAT Gateway for outbound, Bastion for admin access. Each has a purpose; "just give it a public IP" is the anti-pattern interviewers look for you to reject.
19. **Q:** Service Endpoints vs Private Endpoints for storage?
**A.** Service Endpoint is free, easy, keeps traffic on the backbone, but the storage account still has a public endpoint (and you protect it with VNet rules). Private Endpoint removes public exposure entirely and works cross-region/on-prem via PrivateLink, but costs per endpoint and needs DNS. Regulated/cross-prem → private endpoint.
20. **Q:** One big VNet vs many small VNets?
**A.** One VNet with subnets is simpler (no peering costs/latency), but coarse blast radius and no per-team subscription isolation. Many VNets give isolation and delegation per team but need hub-and-spoke, peering, DNS, and centralised egress. Standard enterprise answer: workload VNets per environment/team, hub for shared services.
21. **Q:** UDR to a firewall for all egress — worth it?
**A.** Yes when you need L7 inspection, FQDN filtering, or a compliance control; no if it just adds cost and latency without a requirement. And always design the DNS path (Azure Firewall DNS proxy) with it, or name resolution breaks.

**🎯 Senior**
22. **Q:** Design networking for a 3-tier app with PaaS dependencies in a regulated environment.
**A.** Hub-and-spoke: app VNet (web/app/data subnets with NSGs per tier) peered to a hub containing Azure Firewall, Bastion, private DNS zones and shared private endpoints. UDRs force egress through the firewall; PaaS access via private endpoints with private DNS; ingress via App Gateway + WAF; no public IPs on VMs; admin access only via Bastion; NSG flow logs + Traffic Analytics to a central workspace; and Azure Policy to enforce "no public IP on NICs" and "NSG required on every subnet".

**🎯 Senior signal:** naming *effective routes*/*effective security rules*, knowing NAT Gateway replaces default outbound, and the private-endpoint DNS trap — those three mark real Azure operations experience.

---

## 2. NSG Introduction — `nsg-introduction.md`

**⚡ Rapid**
1. **Q:** NSG vs Azure Firewall vs WAF?
**A.** NSG: stateful L3/L4 allow/deny on subnets/NICs, free. Azure Firewall: managed L4–L7 with FQDNs, threat intel, central policy, logging. WAF: HTTP L7 protection (OWASP rules) on App Gateway/Front Door. They're layers, not alternatives.
2. **Q:** Evaluation order for a flow?
**A.** For inbound: subnet NSG then NIC NSG (both must allow). Outbound: NIC NSG then subnet NSG. Within each NSG, rules are processed by priority (100–4096, lowest first); first match wins; no match = default deny.
3. **Q:** Are NSGs stateful?
**A.** Yes — return traffic for an allowed flow is automatically permitted. So you don't need inbound rules for responses, but you *do* need explicit outbound rules to restrict egress.
4. **Q:** What are service tags and why use them?
**A.** Named, Azure-maintained IP groupings (`Internet`, `VirtualNetwork`, `AzureLoadBalancer`, `Storage`, `Sql`, `AzureCloud.<region>`). They remove IP management, update automatically, and are the recommended way to reference Microsoft services — though for strict control use private endpoints instead.
5. **Q:** What is an application security group (ASG)?
**A.** A logical grouping of NICs referenced in NSG rules as source/destination — lets you write "web ASG → app ASG on 443" without IPs. Best practice for tiered apps; requires NICs to be members.
6. **Q:** Do NSGs log?
**A.** NSG flow logs (VNet flow logs in the newer model) → Storage/Log Analytics, with Traffic Analytics for querying and visualisation. Not on by default — a classic audit finding.

**🔍 Deep dive**
7. **Q:** Design NSG rules for a 3-tier app with zero public exposure of the data tier.
**A.** GatewaySubnet/AppGw subnet: inbound 443 from Internet (or Front Door service tag), plus GatewayManager/AzureLoadBalancer rules. Web/app subnets: inbound only from the App Gateway subnet/ASG on the app port. Data subnet: inbound only from the app ASG on the DB port, deny internet inbound/outbound except required endpoints (or use private endpoints and deny all internet egress). Deny-all as the base plus priorities spaced by 100 so you can insert rules later.
**↳ Follow-up:** "How do you validate it?"
**A.** NSG flow logs + Traffic Analytics to confirm only expected flows, a change-review process with the NSG rules in IaC, and periodic review of `Deny` hits to catch shadowed rules and missing access.
8. **Q:** How do you debug "which rule allowed/denied this"?
**A.** Network Watcher → IP flow verify (per VM/NIC, exact 5-tuple) and Next hop, plus effective security rules on the NIC. IP flow verify gives you the deciding rule name — that's the answer they want.
9. **Q:** What's the trap with multiple NSGs and rule shadowing?
**A.** A broad allow at a lower priority number (e.g. `AllowVnetInBound` at 65000 vs your custom deny at 4096 on the NIC, or an allow-any 100 rule) makes your careful rules meaningless. Review the *effective* rules, not the ones you wrote, and keep priority numbering conventions documented.
10. **Q:** How do you manage NSGs at scale (100+ subnets)?
**A.** Rules as code (Terraform/Bicep) with reusable modules and small standard rule sets, ASGs instead of IP lists, Azure Virtual Network Manager security admin rules for org-wide guardrails (e.g. "deny inbound from internet to any subnet tagged `data`"), and Policy to require NSGs on every subnet. Avoid bespoke per-subnet rule sets — that's how drift and shadowing happen.
11. **Q:** How do NSGs interact with load balancers and health probes?
**A.** The `AzureLoadBalancer` service tag (or the specific probe source ranges) must be allowed inbound, or backends show unhealthy — even though the app is fine. A very common outage cause after tightening NSGs.
12. **Q:** Service tags vs IP allow-lists for third parties?
**A.** Customer-managed IP prefix lists (Azure Firewall IP groups or Policy-managed rules) updated centrally; hardcoded IPs in NSG rules rot silently. Prefer private endpoints or a firewall for partner traffic where possible.

**🚨 War room**
13. **Q:** After an NSG change, the App Gateway reports all backends unhealthy.
**A.** The change likely removed `AzureLoadBalancer`/`GatewayManager` inbound or the app port from the App Gateway subnet/ASG. Revert immediately, then re-apply incrementally with flow-log verification. Add the standard App Gateway rule set to your module so it can't be omitted again.
14. **Q:** A VM can ping but not connect on 443 from another subnet.
**A.** Ping (ICMP) may be allowed while the TCP rule isn't; check the effective rules for that exact 5-tuple, ASG membership of the NIC, whether the destination's OS firewall allows it, and any NVA/UDR in the path. Use IP flow verify to see the deciding NSG rule.
15. **Q:** Attackers were inside your network for a week; segmentation didn't stop lateral movement. Review.
**A.** Almost certainly east-west was allowed by a broad `AllowVnetInBound` or a "temporary" any-to-any rule, with no micro-segmentation between tiers. Remediate with deny-by-default within the VNet, ASG-based tier rules, Azure Firewall for east-west inspection where required, and flow logs/Traffic Analytics to prove the new path set. Frame it as a design gap, not just a rule.
16. **Q:** NSG rules look correct but traffic still fails. What else could be blocking?
**A.** Azure Firewall policy, UDR blackhole, private DNS resolving to a wrong (public) IP, the destination PaaS firewall (storage/SQL network rules), Service Endpoints not configured, a host-based firewall, or a load balancer's distribution rules. NSGs are only one of several layers — always ask "what else is in the path?".

**⚖️ Trade-off**
17. **Q:** NSG on subnet vs NIC?
**A.** Subnet-level for consistent policy across all resources in the segment; NIC-level for workload-specific rules (or when the same subnet hosts differently-trusted resources). Best practice: subnet NSGs as the primary control, NIC NSGs sparingly — two NSGs evaluated together is where confusion starts.
18. **Q:** NSG on Azure Firewall subnet — needed?
**A.** Azure Firewall manages its own traffic; an NSG on AzureFirewallSubnet is generally not required (and can break it). Use the firewall's own policy for filtering. Mentioning this avoids an unnecessary support case.
19. **Q:** Service tags vs private endpoints for PaaS restrictions?
**A.** Service tags + storage/SQL network rules are quick and free but leave a public endpoint reachable (and tags cover broad ranges). Private endpoints remove public exposure and are per-resource. Regulated workloads: private endpoints; convenience/internal: service tags.
20. **Q:** How granular should NSG rules be before it's counterproductive?
**A.** Granular enough to be explicable and auditable (per-tier, per-ASG, per-service-port) — but not per-VM rules. Push finer L7 policy (FQDN, URL, TLS inspection) to Azure Firewall/WAF; NSGs can't do that and pretending otherwise creates rule sprawl.

**🎯 Senior**
21. **Q:** How would you prove to an auditor that your network is segmented?
**A.** Effective NSG rules exported per subnet, flow logs + Traffic Analytics showing only expected flows and denied attempts, Azure Virtual Network Manager security admin rules as an org-wide guardrail, a documented tier/flow matrix with owners, and a quarterly access review. Evidence, not intent.

**🎯 Senior signal:** evaluation order (subnet then NIC, priority first-match, default deny), the `AzureLoadBalancer` probe gotcha, and default-deny east-west thinking. Those are the three highest-signal answers in this topic.

---

## 3. NSG Inbound Rules — `nsg-inbound-rules.md`

**⚡ Rapid**
1. **Q:** What's the default inbound behaviour?
**A.** `AllowVnetInBound` (100), `AllowAzureLoadBalancerInBound` (65001), then `DenyAllInBound` (65500). So intra-VNet is open by default and everything else is denied — most real incidents come from `AllowVnetInBound` being too permissive for the design.
2. **Q:** How do you expose a web app publicly with the fewest rules?
**A.** Ingress via App Gateway/Front Door with WAF; allow only 443 (and 80 for redirect) inbound from `Internet` or (better) the Front Door/App Gateway service tag; deny the rest. Never expose app VMs directly.
3. **Q:** What's the rule for admin access?
**A.** No inbound 22/3389 from the internet, ever. Use Azure Bastion or Just-In-Time VM access (Defender for Cloud) with approval and time limits. If Bastion is impossible, allow from a specific corporate IP range only, with MFA.
4. **Q:** Why do health probes need a rule?
**A.** The platform probes from `AzureLoadBalancer`/`GatewayManager` addresses, which aren't part of your VNet — without allowing those tags on the probe port, backends are marked unhealthy. It's the most common self-inflicted inbound incident.
5. **Q:** How do you handle a rule needing many source IPs?
**A.** IP groups (Azure Firewall) or ASGs where the source is your own workloads; for external sets, a documented, centrally-maintained list (Policy/automation) — never hand-typed into 20 rules. Where possible, replace IP allow-listing with private endpoints/PrivateLink.

**🔍 Deep dive**
6. **Q:** Design inbound rules for a PCI app on Azure.
**A.** Front Door/App Gateway with WAF (OWASP + custom rules) is the only public ingress; backend subnets accept only the gateway's service tag/subnet; data tier accepts only the app ASG; management only via Bastion/JIT; deny-by-default with explicit, documented rules per flow; NSG flow logs + Traffic Analytics retained per policy; and Azure Policy preventing public IPs on NICs.
**↳ Follow-up:** "Front Door in front of App Gateway — what has to be allowed?"
**A.** Inbound from `AzureFrontDoor.Backend` service tag on the App Gateway listener port, plus a header/secret check to prove the request came through Front Door, and rate/WAF rules at both layers. Also make sure the App Gateway's own origin isn't publicly reachable (block direct access).
7. **Q:** How do you restrict who can reach your storage/SQL inbound?
**A.** Private endpoints (best) with public network access disabled, or storage/SQL firewall rules with VNet service endpoints + specific subnets and IPs, and ideally a managed identity rather than shared keys. Note that "selected networks" with the Azure services exception is a common audit finding.
8. **Q:** A rule allows `Internet` on 443 for a VM, but the app is still unreachable. Why?
**A.** No public IP/load balancer in front, or the NIC NSG (second NSG) doesn't allow it, or a UDR/route issue, or the OS firewall, or the App listening only on localhost. Check effective rules on both NSG layers and the listener binding.
9. **Q:** How do you maintain rule hygiene over time?
**A.** Priority conventions and naming standards (`allow-web-from-appgw-443`), IaC with review, quarterly recertification of "any" source rules, flow logs to identify zero-hit rules for deletion, and a rule budget per NSG with a linting check in CI. Untracked rules are the real risk.

**🚨 War room**
10. **Q:** Port 3389 was found open to the internet on 30 VMs. Response?
**A.** Close the rules now (blast-radius first), check Defender for Cloud JIT/WAF logs and sign-in logs for successful access, assume compromise until proven otherwise (check for new local admin accounts, scheduled tasks, outbound anomalies), then enforce: Policy/auto-remediation to remove internet RDP/SSH rules, Azure Bastion/JIT as the only path, and an alert on any new `Internet`-source admin-port rule.
11. **Q:** Users get intermittent 403/connection resets from one region. NSG cause?
**A.** A rule referencing a specific IP or a stale corporate IP block (office IPs change), or blocking a CDN/proxy range that serves that region, or front-end WAF geo rules. Compare flow logs for accepted vs denied client IPs from that region — the pattern usually jumps out.
12. **Q:** After enabling a WAF in prevention mode, legitimate traffic is blocked. Fix fast.
**A.** Switch the WAF to detection mode (or add exclusions for the specific rule IDs) immediately, review the blocked requests to identify the false positive (often a JSON body field, an encoded payload, or a large upload), then re-enable in prevention with tuned exclusions and staged rollout (new rules in detection first).
13. **Q:** You must allow a partner to call your API inbound from their fixed IPs. Best design?
**A.** Terminate at App Gateway/Front Door with WAF, allow only the partner's IP range on the listener (or mutual TLS + certificate validation), log and rate-limit, and rotate/recertify the allow-list quarterly. Prefer mTLS over IP allow-listing since it survives their infrastructure changes.

**⚖️ Trade-off**
14. **Q:** IP allow-list vs mTLS vs VPN/private endpoint for partner access?
**A.** IP allow-list: easy, weak (IPs change/spoof-friendly with shared NAT). mTLS: strong identity per client, needs cert lifecycle management. Private endpoint/VPN: strongest isolation, most setup/ops. Ranked by assurance with the trade being operational overhead — and always combine with WAF/rate limits.
15. **Q:** Should you use `AllowVnetInBound` for internal traffic?
**A.** Only where east-west is genuinely trusted; for tiered/regulated apps, replace it with explicit ASG-based allows and a deny-by-default posture (Virtual Network Manager security admin rules can enforce this org-wide). The default open-east-west is the segmentation gap auditors flag.
16. **Q:** Expose admin ports only to Bastion vs deploy Bastion-less (JIT) access?
**A.** Bastion gives a managed jump path with session logging and no public IPs; JIT (Defender for Cloud) opens temporary NSG rules on demand with approval. Both beat static rules; Bastion is more auditable, JIT is cheaper/less infra — pick per team maturity, and never leave static admin rules.

**🎯 Senior**
17. **Q:** Give me your inbound policy standard for Azure workloads.
**A.** Only Front Door/App Gateway public, WAF in prevention with tuned rules, backends restricted to gateway tags/ASGs, no public IPs on NICs (Policy-enforced), admin access via Bastion/JIT only, default-deny with documented flows, private endpoints for PaaS, Flow Logs + Traffic Analytics retained, and an automated check that flags any new internet-facing admin-port rule within minutes.

**🎯 Senior signal:** naming `AzureLoadBalancer`/`GatewayManager` probe rules, JIT/Bastion over SSH, and WAF false-positive handling in detection mode first — practical, not theoretical.

---

## 4. NSG Outbound Rules — `nsg-outbound-rules.md`

> **RTIQ note:** outbound control is where senior/staff-level Azure questions live — most orgs are fine on inbound and completely blind on egress.

**⚡ Rapid**
1. **Q:** What does the default outbound posture look like?
**A.** `AllowInternetOutbound` (65001) and `AllowVnetOutbound` (65000) with `DenyAllOutbound` (65500). So everything can reach the internet by default until you add explicit denies — egress control is opt-in and that's the security gap.
2. **Q:** How do you actually block internet egress?
**A.** Explicit outbound rules denied by priority (with `Internet` as destination), UDR sending 0.0.0.0/0 to Azure Firewall with an allow-list policy, and/or a proxy. Only the combination gives you a real allow-list; an NSG deny alone blocks everything including required Azure services.
3. **Q:** What outbound access do VMs need to function?
**A.** OS/agent endpoints: Azure platform/IMDS (169.254.169.254), monitoring/Defender agents, Windows Update/Linux repos, DNS, and any PaaS endpoints (ideally via private endpoints). Blocking egress without allow-listing these breaks agent health and patching — a classic own-goal.
4. **Q:** What replaces default outbound access now that it's being retired?
**A.** NAT Gateway (recommended) or a load balancer outbound rule / explicit public IP. Without one, new VMs lose outbound internet — plan migrations by checking which subnets rely on implicit outbound.
5. **Q:** Why is `AllowVnetOutbound` a data-exfiltration concern?
**A.** It lets any VM reach any other VM/service in the VNet — so a compromised host can move laterally or reach a shared storage/DB. Egress rules + micro-segmentation + firewall inspection close it.

**🔍 Deep dive**
6. **Q:** Design egress control for a regulated workload.
**A.** UDR for 0.0.0.0/0 → Azure Firewall (with DNS proxy so FQDN rules resolve correctly), firewall policy with FQDN allow-lists per workload tag/rule collection group, private endpoints for PaaS (so they're not internet egress at all), NSG outbound denies for the data tier, TLS inspection where compliance demands it, and logs to a central workspace with alerts on new destinations. Workloads then have an explicit, reviewable allow-list.
7. **Q:** How do you allow a specific FQDN like `api.partner.com` for one subnet?
**A.** Azure Firewall application rules (FQDN allow) + the subnet's UDR to the firewall + firewall DNS proxy configured. NSGs can't do FQDNs — that's the honest limitation, and it's why the firewall exists.
8. **Q:** How do you find what's actually going out today before you lock it down?
**A.** Flow logs + Traffic Analytics (or Firewall logs if already in path) to inventory destinations by subnet/VM, group into required vs unknown, communicate a freeze window, then enforce in *detection mode* first (log-only deny/allow-list), fix what breaks, and only then enforce. Never flip to deny-only without the inventory.
9. **Q:** How do you stop data exfiltration to personal storage/cloud?
**A.** Egress allow-list at the firewall, block by category/known-cloud-storage FQDNs, TLS inspection for regulated segments, DLP/Defender for Cloud alerts, and monitor for large uploads. Be honest about limits — determined exfiltration over allowed endpoints (e.g. your own storage) needs DLP and identity controls, not just network rules.
10. **Q:** How do you scale egress rules across many VNets?
**A.** Centralise egress in a hub with Azure Firewall + firewall policy managed as code (rule collection groups per environment/workload), spokes UDR to the hub firewall, shared policy with inheritance, and a self-service rule request process. Never duplicate rule sets per spoke.
11. **Q:** What breaks when you force egress through a firewall?
**A.** DNS (needs DNS proxy or your own DNS forwarder with the right routes), certificate/CRL checks, NTP, agent endpoints (Microsoft monitoring/Defender), and anything resolving to IPs not in your rules. Plan the firewall's own dependencies (management, updates) too — misconfigured egress can break the firewall's ability to update.

**🚨 War room**
12. **Q:** After enforcing egress allow-lists, production apps start timing out on third-party APIs.
**A.** Expected — the allow-list is incomplete or the firewall's DNS proxy/FQDN rules don't cover the API's CDN endpoints (SaaS APIs often resolve to many IPs/CDNs). Roll back to detection mode, capture the actual destinations from firewall logs for the affected apps, add them, and re-enforce in a staged way with app owners validating per batch.
13. **Q:** A VM is sending a huge volume of data to an unknown external IP. Response?
**A.** Treat as potential exfiltration: isolate the VM (NSG deny-all + snapshot for forensics), identify the process and the data, revoke its identity/credentials, then scope the impact. Post-incident: why was egress allowed (no firewall in path? rule too broad?), add alerts on anomalous egress volume, and tighten to an allow-list.
14. **Q:** NAT gateway traffic costs are spiralling. Investigate and reduce.
**A.** Flow logs by destination: usually Backup/monitoring, storage access not using private endpoints, container registries, or log shipping. Fix by adding private endpoints/service endpoints for Azure services, checking for chatty agents, and (for cross-region) moving data locally. Track it with a cost anomaly alert so it never surprises you again.
15. **Q:** App works from the office but not from a VM. Outbound or DNS?
**A.** Test by IP: if the IP works, it's DNS (no forwarder, wrong private zone, or firewall DNS proxy missing); if the IP also fails, it's routing/firewall/NSG. Then use Network Watcher connection troubleshoot, which reports latency hops and the blocking rule.

**⚖️ Trade-off**
16. **Q:** Full egress lockdown (deny-all + allow-list) vs monitoring-only?
**A.** Lockdown is the security ideal but demands inventory, DNS design, exception process, and an owner; monitoring-only gives visibility with near-zero breakage but limited control. Mature route: monitoring first, then staged enforcement by workload tier, with a fast exception path so the security team isn't the bottleneck.
17. **Q:** Azure Firewall vs NSG-only egress vs third-party NVA?
**A.** NSG-only: free, coarse (CIDR/ports/tags), no FQDNs. Azure Firewall: FQDN rules, threat intel, central policy, logging — the pragmatic default. Third-party NVA: deeper inspection/features at higher cost/complexity. Choose by whether you need FQDN/L7 policy.
18. **Q:** TLS inspection on egress — do it?
**A.** Only where regulation demands it and you can handle certificate distribution, performance, privacy/legal implications, and app exceptions (pinned certs break). Many orgs inspect metadata only + FQDN filtering. Be prepared to discuss the trade honestly.
19. **Q:** Centralised egress (hub firewall) vs per-VNet egress?
**A.** Centralised gives one policy, one log, one bill, and better detection; it costs an extra hop, a shared failure domain, and hub scaling/throughput planning. Per-VNet egress isolates blast radius but multiplies policy drift. Most enterprises centralise and invest in hub reliability.

**🎯 Senior**
20. **Q:** How do you get from "no egress control" to allow-list-only without an outage?
**A.** Phase 1: flow logs + Traffic Analytics everywhere, publish the destination inventory. Phase 2: put firewalls in path in log-only mode (no deny). Phase 3: enforce for low-risk/dev, then staging, then prod by workload tier, with a documented exception SLA. Phase 4: remove default outbound reliance (NAT Gateway), deny `Internet` outbound at NSG level for tiers that shouldn't need it, and keep a monthly review of new destinations. Publish the phases and the rollback plan — that's what makes it survivable.

**🎯 Senior signal:** "default outbound is open, so you have to opt into control", "firewall needs DNS proxy for FQDN rules", and a phased monitoring-then-enforcement plan. This is staff-level Azure security thinking.

---

## 5. Application Security Groups — `asg.md`

**⚡ Rapid**
1. **Q:** What is an ASG, in one sentence?
**A.** A named group of NICs used as source/destination in NSG rules, so policy follows workload identity instead of IP addresses.
2. **Q:** How do you join an ASG?
**A.** Attach it to the VM's NIC(s). A NIC can be in multiple ASGs; an ASG is region/VNet-scoped and can't be used across VNets (peered or not).
3. **Q:** Where do ASG rules work?
**A.** Only *within the same VNet* (ASG as source and/or destination). Cross-VNet peering traffic can't be filtered by the peer's ASG — you must use CIDRs/service tags there. This limitation is a favourite interview follow-up.
4. **Q:** Why prefer ASGs over IPs?
**A.** Scale changes (autoscaling, new subnets) don't require rule edits, policy is readable ("app-tier → db-tier"), and you eliminate stale IP rules.
5. **Q:** How many ASGs and NICs can you have?
**A.** Limits exist per subscription/region (ASG count, NICs per ASG, ASGs per NIC). For very large fleets, that's when you move policy to Azure Firewall rule collection groups/Policy or use virtual network manager security admin rules.

**🔍 Deep dive**
6. **Q:** Contrast ASG-based rules with subnet-NSG rules for a microservices app.
**A.** Subnet NSGs are coarse (all resources in the subnet share the policy) and force either wide allows or per-VM NSGs. ASG-based rules express exactly "service A may talk to service B on port X" even when they share a subnet — practical micro-segmentation without per-VM rules. Cost: ASG membership must be managed (IaC) or the policy silently fails to apply.
**↳ Follow-up:** "What happens if a NIC isn't in the ASG?"
**A.** Traffic is denied by default (no matching allow) — so a missing ASG attachment is a classic "the new instance can't reach the DB" incident. Automate ASG membership in the VM provisioning module.
7. **Q:** How do you handle VM scale sets with ASGs?
**A.** Attach the ASG to the scale set's NIC configuration (or the flexible scale set's network profile) so all instances inherit membership — that's the reason ASGs exist. With flexible orchestration, ensure the profile applies to each VM and verify effective rules on a sample instance.
8. **Q:** How do you migrate from CIDR-based rules to ASGs without downtime?
**A.** Inventory the flows, create ASGs and add NICs (membership alone doesn't change traffic), add new ASG-based allow rules at a *lower priority number* (higher precedence) alongside existing CIDR rules, verify with flow logs, then delete the old CIDR rules. Reversible at every step — say that.
9. **Q:** How do you document/audit ASG-based policy?
**A.** Name ASGs by tier/service (`asg-web`, `asg-app`, `asg-db`), keep rules in IaC with a documented matrix, and export effective rules per VM to prove that only intended flows are permitted. Add an automated check that every VM in a tier is a member of the expected ASG.

**🚨 War room**
10. **Q:** A new VM can't reach the database though the rule exists. Why?
**A.** Its NIC isn't in the source ASG (or the DB NIC isn't in the destination ASG), both ASGs are in different VNets, or a higher-priority deny matched first. Check effective rules on the VM and ASG membership on both ends — in that order.
11. **Q:** After a scale-out event, new instances are unhealthy while old ones are fine.
**A.** ASG membership wasn't applied to new instances by the deployment module (also check the ASG is attached at the right NIC and the NSG rule's priority wasn't overridden). Fix the module so membership is part of provisioning, then sweep for other instances missing membership.
12. **Q:** You must allow traffic from a peered VNet's app tier. ASGs?
**A.** Not possible across VNets — use the peer's subnet CIDRs (documented, kept current), service tags where applicable, or front the service with a private endpoint/load balancer and control access there. Be explicit that this is a design constraint, not a configuration mistake to fix.

**⚖️ Trade-off**
13. **Q:** ASG-based security vs Azure Firewall for east-west?
**A.** ASGs give free, fine-grained L3/L4 micro-segmentation with no extra hop — enough for most tiering. Azure Firewall adds L7/FQDN/inspection/logging with cost and an extra hop (and requires UDRs). Use ASGs as the default, firewall where inspection is required.
14. **Q:** ASGs vs per-VM NSGs?
**A.** ASGs express policy once for a group and scale automatically; per-VM NSGs multiply configuration and drift. Per-VM NSGs only where a single VM genuinely has unique requirements — and even then, consider an ASG of one.
15. **Q:** Should every VM be in an ASG?
**A.** In a mature environment, yes — membership makes policy explicit and auditable, and lets you move away from CIDR rules. The caveat is discipline: unmanaged membership creates policy gaps, so tie it to the provisioning pipeline.

**🎯 Senior**
16. **Q:** Give me your design for micro-segmentation of a 4-tier app with ASGs.
**A.** ASGs per tier and per service identity (`asg-web`, `asg-app-orders`, `asg-app-payments`, `asg-db`, `asg-jump`), a small rule set per pair (source ASG → destination ASG on the specific port), deny-by-default with no reliance on `AllowVnetInBound`, ASG membership enforced by the VM module, NSG flow logs + Traffic Analytics for validation, and virtual network manager security admin rules as the org-level backstop that even a miswritten NSG can't override.

**🎯 Senior signal:** knowing ASGs are intra-VNet only, and that membership is the failure point you must automate. Those two facts separate hands-on Azure engineers from exam-passers.

---

## 6. Hub-and-Spoke — `hub-and-spoke.md`

**⚡ Rapid**
1. **Q:** Why hub-and-spoke?
**A.** Centralise shared services (firewall, VPN/ExpressRoute gateway, Bastion, DNS, private endpoints, monitoring) once, and keep workloads isolated in their own VNets/spokes — cost, policy, and blast-radius benefits.
2. **Q:** What must the hub/spoke peering configuration include?
**A.** Peering both directions (`spoke→hub` and `hub→spoke`), `allowForwardedTraffic` on the spoke's peering for traffic via NVAs/firewall, `allowGatewayTransit` on the hub and `useRemoteGateways` on the spokes for on-prem access, and `allowVirtualNetworkAccess` on both. Missing flags are the classic "peering is connected but nothing works".
3. **Q:** Where do UDRs go?
**A.** On the spoke subnets: 0.0.0.0/0 (and on-prem ranges) → the hub firewall's private IP. The GatewaySubnet must not be routed through the firewall (it breaks VPN/ER), and the firewall subnet needs its own correct routes.
4. **Q:** What's the alternative to peering for shared services?
**A.** Private endpoints in the hub (customers reach them via peering), Azure Virtual WAN (managed hub), or Virtual Network Manager-connected groups. Private endpoints + DNS zones in the hub is the pattern that keeps spokes thin.
5. **Q:** How do spokes talk to each other?
**A.** Only through the hub (firewall/NVA) — peering is non-transitive, so spoke-to-spoke needs the firewall to route and allow it, which is exactly where you enforce policy. Don't create spoke-to-spoke peerings; you'd bypass the inspection point.

**🔍 Deep dive**
6. **Q:** Design hub-and-spoke for 40 applications with centralised egress, on-prem connectivity, and private PaaS access.
**A.** Hub VNet: Azure Firewall (with policy per environment), VPN/ER gateway, Bastion, private DNS zones, and shared private endpoints. Spokes: app VNets with NSGs/ASGs, UDRs to the firewall, `useRemoteGateways` for on-prem, and no public IPs. Peering mesh = spoke↔hub only. Then: Policy to enforce standard routes/NSGs, DNS forwarders per spoke (or central DNS resolver VMs), Flow Logs to a central workspace, and an IPAM process for new spokes.
**↳ Follow-up:** "Spoke B can't reach on-prem while Spoke A can."
**A.** Check `useRemoteGateways` on Spoke B's peering, whether B's subnet UDR sends on-prem traffic to the firewall (which must allow and route it back to the gateway), whether the firewall's rule allows that source/destination, and BGP route propagation on B's route table. The `useRemoteGateways` flag being absent is the usual answer.
7. **Q:** How do you scale hub-and-spoke to hundreds of spokes?
**A.** Replace peering sprawl with Azure Virtual WAN (managed hubs, hub-to-hub routing, routing intent for centralised egress) or Virtual Network Manager hub-and-spoke connectivity with connected groups; centralise policy via firewall policy and security admin rules. Manual peering per spoke stops scaling around 20–50 spokes.
8. **Q:** Where do you put private DNS zones, and why does it matter?
**A.** In the hub (or a dedicated DNS subscription), linked to all spokes, with per-zone A records from private endpoints and conditional forwarders for on-prem. If zones are per-spoke, private endpoint records fragment and cross-spoke resolution fails — say this, it's the top private-endpoint failure in hub topologies.
9. **Q:** How do you avoid asymmetric routing in hub-and-spoke with a firewall?
**A.** Make sure both directions traverse the firewall: spoke subnets UDR everything to the firewall, and the firewall's subnet has routes for the spoke address spaces so return traffic comes back through it (Azure system routes usually handle this inside a VNet, but NVAs and gateway traffic need care). Also don't route the GatewaySubnet through the firewall.
10. **Q:** How do you handle multi-region with hubs?
**A.** One hub per region, spoke peerings to their local hub, hub-to-hub peering (or Virtual WAN) for cross-region traffic, firewall policy defined globally and applied per region, and DNS zones shared/replicated with proper regional records. Keep regional egress local to avoid data-transfer costs and latency.
11. **Q:** How do you onboard a new spoke in a repeatable way?
**A.** A Terraform/Bicep module that creates the VNet, subnets with standard NSG/UDR associations, the peerings (both directions with the right flags), DNS zone links, diagnostic settings, and IPAM allocation — then a single parameterised call per app. Onboarding should be a PR, not a two-week ticket.
12. **Q:** What are the hub's failure modes?
**A.** Firewall throughput/quota limits (AZ-scoped firewalls need planning), gateway redundancy (active-active VPN/ER recommended), DNS dependency (private resolver availability), and the hub as a shared blast radius for any policy mistake. Mitigate with zone-redundant firewalls, autoscale, and change control on hub policy.

**🚨 War room**
13. **Q:** A wrong firewall rule took down egress for every spoke. How do you prevent this class of incident?
**A.** Stage policy changes: firewall policy as code with a canary rule collection applied to a test spoke, change windows, DNS/FQDN validation, and automated post-change synthetic checks (a canary VM hitting the required endpoints). Keep a documented last-known-good policy for instant rollback, and alert on new deny hits/firewall health after every change.
14. **Q:** Spokes can reach each other's subnets but shouldn't. Fix.
**A.** Peering flags/routing allow it (or someone added spoke-to-spoke peerings). Enforce through the firewall: remove direct spoke-to-spoke peering, UDR spoke traffic to the firewall, and add explicit deny rules for unauthorized spoke pairs (or Virtual Network Manager security admin rules). Then verify with flow logs.
15. **Q:** After moving the gateway to a hub, spoke VPN access broke intermittently.
**A.** `useRemoteGateways` set on too many spokes/multiple spokes with gateway transit, BGP propagation disabled on a route table, or UDRs overriding the gateway-learned routes (more specific /32s vs system routes). Check effective routes on an affected VM — the answer is almost always visible there.
16. **Q:** Costs jumped after centralising egress through the hub.
**A.** Inter-region/hub data transfer, firewall data processing charges, and spoke↔hub peering transfer for chatty workloads. Fix by keeping chatty pairs in the same spoke/region, using private endpoints in-region for PaaS, avoiding cross-region hairpins, and reviewing west-east flows in Traffic Analytics.

**⚖️ Trade-off**
17. **Q:** Hub-and-spoke vs Virtual WAN?
**A.** Hub-and-spoke: full control, cheaper at small scale, you own the gateways/firewall/DNS HA. Virtual WAN: Microsoft-managed hubs with global transit, routing intent, and SD-WAN integration, and much less per-spoke plumbing — better past a few dozen spokes or with many branch sites. Migration is painful; choose with 3-year growth in mind.
18. **Q:** Centralised firewall vs distributed (per-spoke) firewalls?
**A.** Centralised = one policy, one log, lower cost, but a shared bottleneck and blast radius. Distributed = better throughput/isolation, higher cost and policy drift. Large orgs: one firewall per environment/region in a regional hub.
19. **Q:** Peering everything vs using private endpoints in the hub?
**A.** Private endpoints let consumers reach a specific service without full VNet peering/visibility; peering is needed for general connectivity. The lean pattern is: peering for east-west app traffic that's required, private endpoints for PaaS.
20. **Q:** Should spokes have their own gateways for isolation?
**A.** Usually no — gateway transit centralises cost and management. Separate gateways only for strict tenant isolation (e.g. regulated subsidiary) or to avoid a shared failure domain.

**🎯 Senior**
21. **Q:** You inherit a flat network of 60 VNets, all peered, no firewall, no DNS standard. 90-day plan?
**A.** Days 0–30: inventory flows (flow logs/Traffic Analytics), publish an address/DNS map, stand up the hub (firewall, DNS zones, gateway), and peer spokes to it without changing routes. Days 30–60: move DNS to a standard, apply UDRs to pilot spokes (dev → staging), enforce NSG/ASG standards with Policy, and validate with synthetic checks. Days 60–90: enforce per environment, remove direct spoke-to-spoke peerings, complete spoke onboarding modules, and hand over a documented onboarding process with guardrails (VNet Manager security admin rules). Include a rollback plan and named owners per phase.

**🎯 Senior signal:** peering *flags* (`allowForwardedTraffic`, `useRemoteGateways`), centralised private DNS zones, and "spokes talk through the hub, never directly". That's the Azure platform-engineer vocabulary.

---

## 7. VPN (Site-to-Site, Point-to-Site, ExpressRoute) — `vpn.md`

**⚡ Rapid**
1. **Q:** Site-to-Site vs Point-to-Site vs ExpressRoute?
**A.** S2S: IPsec tunnel from an on-prem device/gateway to Azure (encrypted over the internet, cheap, variable latency). P2S: individual clients connect to Azure (remote workers, OpenVPN/IKEv2). ExpressRoute: private dedicated circuit via a provider (predictable latency/bandwidth, not encrypted by default — add IPsec/MACsec if required).
2. **Q:** What gateway SKU would you pick?
**A.** VpnGw1–5 by required throughput/tunnels; favor zone-redundant SKUs (`VpnGw1AZ`+) with active-active for HA. ExpressRoute uses ErGw SKUs by throughput. Match SKU to required bandwidth, not to "smallest that works" — throughput claims are aggregate.
3. **Q:** What must the gateway subnet be called?
**A.** `GatewaySubnet`. It must exist (min /27 recommended) and must not be routed through a firewall/NVA or the tunnel breaks. Naming and routing both bite people.
4. **Q:** How many tunnels for HA?
**A.** Two (active-active) across two on-prem devices/AZs, or a VPN as backup for ExpressRoute. A single tunnel is a single point of failure, and BGP (if used) should advertise/receive routes on both.
5. **Q:** Encryption/IPsec parameters — what matters?
**A.** IKE version (v1/v2), phase 1/2 encryption+integrity, DH group, and the SA lifetime must match on both sides; Azure has default and custom policies. Mismatched proposals are the number-one reason a tunnel won't come up.
6. **Q:** Does ExpressRoute require encryption?
**A.** No — it's a private circuit, and encryption is optional (IPsec over the private peering, or MACsec at supported providers). Compliance regimes usually require adding encryption explicitly; say that unprompted.

**🔍 Deep dive**
7. **Q:** A VPN tunnel is "Connected" but traffic doesn't flow. Debug.
**A.** Connected means IKE/SA is up. Then check: BGP sessions/routes received (or static routes), the GatewaySubnet route table, effective routes on the target VM (is on-prem advertised/propagated?), UDRs overriding gateway routes (a more-specific /32 to a firewall/NVA), NSGs on the subnet, and on-prem firewall rules for the Azure CIDRs. Diagnose with the gateway's effective routes and Network Watcher on the VM.
8. **Q:** Design hybrid connectivity for a workload needing 5 Gbps and <5 ms jitter to on-prem.
**A.** ExpressRoute (dedicated circuit, ideally two diverse providers/locations) with a VPN as backup, active-active gateways, and BGP with route preference so ER is primary. Add encryption if required by policy, monitor circuit/latency with Network Watcher/BGP metrics, and keep the DG (ExpressRoute Direct) option for higher bandwidth where available. Validate with real latency/jitter measurements, not assumptions.
9. **Q:** How does BGP work here, and why enable it?
**A.** BGP (over S2S or ER) advertises on-prem routes to Azure and Azure routes to on-prem dynamically — new subnets propagate automatically, failover is faster, and you can prefer one path with AS-path/communities. Static routing means editing both sides for every change, which is where drift comes from.
10. **Q:** What is forced tunnelling and when is it a problem?
**A.** Sending internet-bound traffic through on-prem (0.0.0.0/0 from the VPN/ER gateway, or a UDR to an NVA). It's required when all egress must be inspected on-prem, but it's a performance bottleneck and a single point of failure for the whole cloud estate — size the path for the throughput and design for the tunnel dropping.
11. **Q:** How do you do DNS and identity across hybrid?
**A.** DNS: on-prem DCs as forwarders (and Azure DNS Private Resolver for the reverse direction), with conditional forwarding per zone; private endpoint zones must be resolvable from on-prem too (forward `privatelink.*` to Azure). Identity: Entra Connect/Cloud Sync to your on-prem AD, with SSO for Azure access. Both are the actual blockers in most hybrid projects.
12. **Q:** How do you migrate from VPN to ExpressRoute with minimal disruption?
**A.** Run both in parallel (ER + VPN), use BGP to prefer ER (local preference/AS-path), migrate workloads/subnets in a controlled order, monitor packet loss/latency during cutover, then decommission the VPN as a backup or keep it as DR. Always keep a documented rollback path — the VPN stays as the break-glass.
13. **Q:** How do you monitor connectivity quality?
**A.** Gateway metrics (tunnel bandwidth/egress, BGP peer status), Network Watcher Connection Monitor for latency/loss to on-prem endpoints, ExpressRoute circuit metrics (ARP/BGP availability, QoS), alerts on tunnel down or BGP flap, and synthetic checks from Azure to critical on-prem services. Circuit health is a KPI, not a checkbox.

**🚨 War room**
14. **Q:** The VPN tunnel drops every 30 minutes. Causes?
**A.** SA lifetime/PFS mismatch (one side rekeys and the other rejects), a small on-prem MTU/fragmentation issue, DPD timeouts because a keepalive/route is missing, an unstable physical link, or an on-prem firewall idle timer closing the session. Correlate with on-prem device logs — rekeying timers are the usual culprit.
15. **Q:** After the on-prem firewall team changed a rule, Azure workloads lost access to on-prem apps but not the reverse.
**A.** Asymmetric or one-directional rule: the on-prem firewall is blocking the Azure CIDR as source (or only allowing the gateway IP), or the return path is preferred over the wrong link (asymmetric routing across two tunnels). Verify with traceroute in both directions and check the on-prem firewall's logs for the Azure source ranges.
16. **Q:** ExpressRoute circuit goes down at 2 a.m.; engineering discovers 90% of workloads broke. Response and prevention?
**A.** Immediate: confirm circuit/ARP/BGP status, switch to the VPN backup (or the second circuit), and communicate. Prevention: dual diverse circuits or ER+VPN with automatic route preference, workloads that don't hard-depend on on-prem (local caching/queues), monitoring on circuit health with alarms *before* users notice, and a tested runbook for the failover.
17. **Q:** Latency to on-prem jumped from 8 ms to 40 ms after a change.
**A.** Traffic is now taking the VPN instead of ExpressRoute (route preference/BGP change), or hair-pinning through a firewall/NVA, or a new UDR forced a longer path, or the provider changed the path. Check effective routes and BGP attributes, then Network Watcher's IP flow/connection monitor — this is nearly always a routing change, not a bandwidth issue.
18. **Q:** Only one subnet can't reach on-prem, everything else works. Why?
**A.** That subnet isn't associated with the route table that propagates gateway routes (or has a UDR without the on-prem ranges), an NSG blocks it, or it was added after the gateway/BGP config and isn't advertised. Check effective routes on a VM in that subnet — it's a per-subnet routing problem, not a gateway problem.

**⚖️ Trade-off**
19. **Q:** VPN vs ExpressRoute — cost vs quality?
**A.** VPN is cheap, quick, encrypted by default, but bandwidth/latency over the internet varies. ER costs significantly more (circuit + gateway), gives predictable latency/bandwidth and SLAs, but isn't encrypted by default and provisioning takes weeks. Decision driver: is on-prem latency/throughput business-critical? If not, VPN + a good backup design is usually right.
20. **Q:** ExpressRoute with Microsoft peering — do you need it?
**A.** Only if you need to reach Microsoft 365/Azure PaaS over a private path (with specific requirements/approvals). For most workloads, private peering + private endpoints covers it — Microsoft peering adds cost and complexity, and Microsoft has been narrowing which services qualify.
21. **Q:** VPN gateway vs Virtual WAN VPN?
**A.** Virtual WAN gives managed, global hubs with branch-to-branch and SD-WAN integration, and simpler scaling for many sites; a VNet VPN gateway is simpler and cheaper for one site/region. Many sites/branches → vWAN; one or two → gateway.
22. **Q:** One VNet gateway shared by all spokes vs per-spoke gateways?
**A.** Shared via peering with `useRemoteGateways` is the standard: cheaper, one config, central monitoring. Per-spoke gateways only for strict isolation or where a spoke needs independent routing/failure domains.

**🎯 Senior**
23. **Q:** Design and justify a hybrid connectivity architecture for a company with 3 offices, two data centres, and an Azure landing zone.
**A.** Dual ExpressRoute circuits from diverse providers/locations for the DCs (primary), VPN gateways as backup (or for offices), Virtual WAN if there are many branch sites, BGP everywhere with route preference for ER, forced tunnelling only if compliance demands, DNS via Azure Private Resolver + on-prem conditional forwarders, ExpressRoute encryption where data classification requires it, Connection Monitor + circuit metrics with alarms, and a documented, rehearsed failover runbook.

**🎯 Senior signal:** "GatewaySubnet must stay out of the firewall path", "ExpressRoute isn't encrypted by default", and "asymmetric routing is the usual hybrid failure". Those three answers show real hybrid operations.
