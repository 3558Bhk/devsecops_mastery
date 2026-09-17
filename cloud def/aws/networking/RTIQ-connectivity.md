# RTIQ — AWS Connectivity (Real-Time Interview Questions)

> **Cloud:** AWS · **Domain:** VPC Peering, Transit Gateway · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~11 min

**How this file is used live:** this is the "can you design a network for 40 teams" round. Expect a whiteboard: N VPCs, on-prem, shared services, a compliance boundary. Then they'll ask why traffic still isn't flowing and who pays for the data transfer. Senior answers quantify (routes, attachments, cost per GB) and speak in terms of blast radius and ownership.

**Legend:** ⚡ Rapid · 🔍 Deep dive + follow-ups · 🚨 War room · ⚖️ Trade-off debate · 🎯 Senior signal

---

## 1. VPC Peering — `vpc-peering.md`

**⚡ Rapid**
1. **Q:** Is VPC peering transitive?
**A.** No. Peering is strictly 1:1 — if A↔B and B↔C are peered, A cannot reach C through B. You need direct peering, a Transit Gateway, or a routing appliance.
2. **Q:** Biggest hard constraint?
**A.** Non-overlapping CIDRs. Overlapping ranges cannot be peered at all, which is why address planning at account-creation time matters more than any later networking choice.
3. **Q:** What must you configure on each side?
**A.** The peering connection (accepted by the other side), a route in each subnet's route table pointing the peer's CIDR at the peering connection, and SG rules allowing the traffic. Both-direction routes are the classic miss.
4. **Q:** Does peering cost anything?
**A.** No hourly charge, but cross-AZ and cross-region data transfer are billed (inter-region peering has its own per-GB rates, typically cheaper than internet egress).
5. **Q:** Cross-region peering vs same-region?
**A.** Same-region: simple, low latency, SG referencing supported. Cross-region: same API but higher latency, data transfer cost, and SG referencing has caveats — verify support rather than assuming.

**🔍 Deep dive**
6. **Q:** Peered VPCs, routes exist, SGs allow, still no connectivity. Debug.
**A.** Check: the peering connection status is `active` (not `pending-acceptance`), routes exist in *both* VPCs *and* the specific subnets involved (route tables are per-subnet), no more-specific route elsewhere (0.0.0.0/0 via NAT will win over a /16 peer route if the destination matches the NAT route more specifically), NACLs, SG referencing validity, and DNS resolution if using private hosted zones (`enableDnsSupport`/`enableDnsHostnames` and zone association for cross-account).
**↳ Follow-up:** "It works from AZ-a but not AZ-b in the same VPC."
**A.** The AZ-b subnet's route table wasn't updated (or has a conflicting route). Route tables are per-subnet — the #1 peering bug.
7. **Q:** How many peerings before it becomes unmanageable, and what's the alternative?
**A.** Peerings scale as n(n-1)/2; anything past a handful of VPCs becomes a route-table and cost mess. Past ~10 VPCs (or with on-prem/hybrid) move to Transit Gateway with segmented route tables, or VPC sharing via AWS RAM for same-account/same-org workloads.
8. **Q:** How do you share services (DNS, AD, logging, endpoints) across VPCs?
**A.** Peering to a shared-services VPC, or better: AWS RAM to share a VPC/subnets, PrivateLink for specific services, Route 53 Resolver for hybrid DNS, and centralised endpoints. Choose based on isolation requirements and whether you want to grant visibility into a whole VPC.
9. **Q:** How do you prevent a peer from reaching your database subnet?
**A.** Route tables, not peering, are the control: only route the subnets you want reachable (the peer's route table only sees what you advertise). Add SG references and NACLs for defence in depth; consider putting the shared resources behind a PrivateLink endpoint so only that service is reachable.
10. **Q:** Can you peer across organisations/accounts with the same CIDR?
**A.** Across accounts: yes (accept via account ID or org). Same CIDR: no — never. If they overlap, you need a NAT/routing appliance or a redesign; overlapping CIDRs are the reason "we'll sort out IPs later" fails.

**🚨 War room**
11. **Q:** Post-acquisition: you must connect two orgs' VPCs that both use 10.0.0.0/16. Options?
**A.** (1) PrivateLink for the specific services that need to cross (no CIDR requirement). (2) A NAT/proxy appliance in one VPC translating addresses. (3) Re-IP one estate (painful, months, but often the eventual answer). Recommend PrivateLink for speed and isolation, with a re-IP programme as the strategic fix.
12. **Q:** Peering works until a new subnet was added — now that subnet can't reach the peer.
**A.** New subnets get a *new* route table (or the VPC main route table) without the peer route. Fix the IaC module so subnet creation always attaches the standard route table, and add a Config rule/drift check for missing peer routes.
13. **Q:** A 40% spike in data transfer cost after adding a peering. Why?
**A.** Cross-AZ traffic now flows where it previously stayed local — chatty services in different AZs, or replication/monitoring traffic. Fix: co-locate chatty pairs (same AZ), use zonal endpoints, batch/reduce chatter, and verify with flow logs per destination.

**⚖️ Trade-off**
14. **Q:** Peering vs Transit Gateway for 3 VPCs?
**A.** Peering: simple, no hourly cost, no extra hop, but no transitivity and per-subnet route management. TGW: hub-and-spoke, transitive, centralised policy/logging, but hourly per attachment + per-GB, and you must design route-table segmentation. Small, static, low-count → peering; growing or hybrid → TGW.
15. **Q:** Peering vs PrivateLink for cross-account service access?
**A.** Peering exposes the network; PrivateLink exposes one service with one-way initiation and no CIDR dependence. If the requirement is "they need my API", PrivateLink is the better security and management answer.
16. **Q:** Do you ever want a "full mesh"?
**A.** Only in small, flat, trusted estates. In multi-team orgs, a mesh removes natural blast-radius boundaries; hub-and-spoke with segmented route tables gives you an audit point and a place to enforce policy.

**🎯 Senior**
17. **Q:** Design connectivity for 30 VPCs across 4 accounts with shared services and on-prem, plus a PCI segment.
**A.** Transit Gateway hub in a network account, separate TGW route tables for prod/non-prod/PCI/shared, attachments per VPC with association+propagation controlled per segment, centralised egress VPC with NAT and inspection, Direct Connect with BGP to on-prem, Route 53 Resolver endpoints for hybrid DNS, TGW Flow Logs + VPC Flow Logs to a central lake, and IaC modules so new VPCs join a segment by parameter — the key is that segmentation is a route-table property, not a convention.

**🎯 Senior signal:** "peering is not transitive" plus per-subnet route tables plus the n(n-1)/2 cost of mesh — and then framing segmentation as *route-table design*, not firewall rules.

---

## 2. Transit Gateway — `transit-gateway.md`

**⚡ Rapid**
1. **Q:** What is Transit Gateway in one line?
**A.** A regional hub that connects VPCs, VPNs, and Direct Connect attachments transitively, with per-attachment routing controlled by TGW route tables.
2. **Q:** How do you isolate segments (prod vs dev, PCI vs non-PCI)?
**A.** Multiple TGW route tables: attachments associate to a table (what they can send) and propagate into tables (where they're advertised). Prod and dev in different tables never see each other's routes.
3. **Q:** Transit Gateway vs VPC peering — the deciding factor?
**A.** Transitivity and centralisation: TGW scales to hundreds of VPCs with one routing policy; peering becomes a mesh. TGW is a shared service with cost and a failure domain — treat it as critical infrastructure.
4. **Q:** What's the pricing model?
**A.** Per-attachment hourly + per-GB data processed over the TGW. Data processed includes traffic between VPCs — a surprise when people route chatty east-west traffic through it instead of keeping it local.
5. **Q:** Is TGW global?
**A.** No — it's regional. Global connectivity needs TGW peering (inter-region peering attachments) or Direct Connect between regions.

**🔍 Deep dive**
6. **Q:** Two VPCs are attached and advertised, but they can't reach each other. Debug order?
**A.** (1) Attachment state `available`. (2) Association: is the VPC's attachment associated with a route table? (3) Propagation: is the other VPC's CIDR propagated (or documented via static route) into that table? (4) VPC subnet route tables pointing the peer CIDR at the TGW. (5) Both sides' SGs. (6) Blackhole routes (stale attachments). Most "TGW doesn't work" cases are missing VPC-side routes or a route-table association mismatch.
**↳ Follow-up:** "Traffic works one direction only."
**A.** One VPC's subnet route table lacks the return route, or that attachment isn't associated with a table that contains the source's CIDR. Asymmetric routing in TGW is nearly always a missing association/propagation.
7. **Q:** How do you do centralised egress (and ingress) with TGW?
**A.** Spokes advertise 0.0.0.0/0 from an egress VPC (static route or `0.0.0.0/0` propagation), inspection VPC with a firewall (GWLB) inline, and a separate ingress path for inbound via ALB/NLB. Keep the egress VPC's route tables in their own TGW table so only egress-capable attachments propagate the default.
8. **Q:** How do you enable on-prem connectivity with TGW?
**A.** Site-to-Site VPN or Direct Connect gateway attached to TGW, BGP for dynamic routing, and segmentation per VPC attachment. Consider **TGW Connect** for SD-WAN, and check your attachment throughput limit — a single VPN tunnel's bandwidth cap (≈1.25 Gbps) can bottleneck an entire estate.
9. **Q:** How do you scale throughput and availability?
**A.** TGW itself scales elastically, but each VPC/VPN attachment has limits (e.g. ~50 Gbps per VPC attachment; VPN tunnel limits). Use multiple attachments/ECMP for VPNs, multiple DX connections (max 4 per DX gateway for resilience), and monitor per-attachment metrics. Design links, not just connectivity.
10. **Q:** What's the failure domain and how do you survive it?
**A.** A regional TGW outage/route table misconfiguration affects everything attached. Mitigations: multi-region TGW with peering for cross-region paths, no single-route-table choke (segment by environment), change control on TGW route tables via IaC with plan review, and a documented break-glass path (re-point critical routes, use direct peering for the most critical pair).
11. **Q:** How do you monitor and bill TGW usage per team?
**A.** TGW Flow Logs + VPC Flow Logs into a central lake (Athena), aggregated by attachment/CIDR/environment, then showback via tags and Cost Explorer allocation. Data-processed cost per attachment is what you attach to the team's budget.

**🚨 War room**
12. **Q:** After adding a new attachment, a large environment loses all internet access. Why?
**A.** The new attachment propagated a competing 0.0.0.0/0 (or a more specific prefix) into the shared route table, or an association change altered which table handles the internet-bound traffic — TGW takes the longest-prefix/most specific match, and an unexpected default can blackhole egress. Fix: isolate the new attachment in its own table, use explicit propagation control, and always `plan`-diff route-table associations.
13. **Q:** One VPC can reach the internet but not on-prem; another can reach on-prem but not the internet. Explain and fix.
**A.** Segmented route tables: the internet-bound path needs the egress attachment's default propagated into that table; the on-prem path needs the DX/VPN routes propagated. Fix by attaching the right routes to the right table where the VPC's attachment is associated — the common error is propagating everything into one table ("flat network") for convenience.
14. **Q:** TGW data-processed cost triples in a month. Investigate.
**A.** Flow logs by attachment + destination: typical causes are a new backup/replication job routing cross-VPC (should be in-AZ or via endpoints), chatty service-to-service calls that should be local, NAT/egress misroutes causing hairpins, or a chatty health check between VPCs. Optimise by co-locating chatty pairs, using endpoints/PrivateLink, and reviewing any "route everything to the hub" default.
15. **Q:** An entire region's workloads can't reach the database VPC after a security change. First five minutes?
**A.** Check TGW route table associations/propagations for the DB attachment and any recently changed route (Config + CloudTrail on `CreateRoute`/`ReplaceRoute`), check attachment state and blackhole routes, verify the DB VPC's return routes, then check SGs on the DB. Communicate and, if needed, restore the previous route table state from IaC.

**⚖️ Trade-off**
16. **Q:** TGW vs VPC peering for two chatty services in different VPCs?
**A.** Peering avoids the per-GB data-processed charge and an extra hop for high-volume chatty traffic. If volume is high and both sides are stable, peering (or even co-locating/endpoints) is cheaper and simpler; TGW for scale/breadth, peering for a few hot paths.
17. **Q:** TGW vs AWS Cloud WAN?
**A.** TGW is VPC-centric, per-account/attachment policy, mature. Cloud WAN adds a global network with policy-as-code segments across regions and accounts, centralised (with more moving parts and newer limits). Choose Cloud WAN when you need a true global, policy-driven network; TGW when regional connectivity and cost control matter most.
18. **Q:** One giant TGW vs one per environment?
**A.** One per environment (or one TGW with strict route-table segmentation) reduces blast radius; one giant flat TGW is cheaper in attachments but means a single misroute can raze everything. Regulated orgs: separate prod TGW.
19. **Q:** Should application traffic go through a hub firewall or stay local?
**A.** Inspect what compliance demands (north-south egress/ingress, cross-boundary east-west), keep intra-app traffic local (same VPC/AZ) to avoid TGW and GWLB data charges and latency. Say the words "inspection is a cost and latency decision, not a default".

**🎯 Senior**
20. **Q:** Walk me through a TGW migration from a peering mesh with zero downtime.
**A.** Phase 0: document routes and CIDRs, verify no overlap. Phase 1: stand up TGW + attachments, add routes with *more specific* prefixes to steer a low-risk workload (canary), keep peering routes intact. Phase 2: migrate workload by workload, monitoring flow logs and latency. Phase 3: remove peerings after a soak period. Rollback at every phase is "delete the more-specific route". Include cost modelling and a rollback runbook in the plan.

**🎯 Senior signal:** describing TGW as *routing-policy-as-code with a blast radius* rather than "a hub", and immediately talking about route tables, propagation, and data-processed cost, is exactly the platform-architect bar.
