# Azure NSG Outbound Rules — Interview Questions

> **Cloud:** Azure · **Category:** Networking · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

Outbound NSG rules use `direction: "Outbound"`. Azure allows all outbound by default, so you add **Deny** rules to lock down egress.

```json
{
  "name": "DenyInternet",
  "properties": {
    "priority": 100,
    "direction": "Outbound",
    "access": "Deny",
    "protocol": "*",
    "sourceAddressPrefix": "*",
    "sourcePortRange": "*",
    "destinationAddressPrefix": "Internet",
    "destinationPortRange": "*"
  }
}
```

**Key fields:** `direction: "Outbound"` · `destinationAddressPrefix` (e.g. `Internet`, `VirtualNetwork`, service tags) · `access: "Deny"` (since outbound defaults to allow). Outbound evaluation order is **NIC NSG → subnet NSG** (reverse of inbound).


## Case A — Basic

**A1. What is an NSG outbound rule?**
**Answer:** A security rule controlling traffic **leaving** a subnet or NIC — evaluated by priority (lowest first, first match wins) with Allow/Deny action.

**A2. What are the default outbound rules?**
**Answer:** **AllowVnetOutBound** (allow all traffic within the VNet) and **AllowInternetOutBound** (allow all outbound to the internet). There is **no default deny** for outbound — outbound is open by default.

**A3. Why is outbound traffic allowed by default?**
**Answer:** Azure assumes resources need to reach the internet (updates, packages, APIs). You must explicitly add **Deny** rules if you want to restrict outbound (a key difference from inbound's default deny).

**A4. Do you need an outbound rule for the response to an inbound request?**
**Answer:** No — NSGs are **stateful**: the response to an allowed inbound flow is automatically allowed outbound.

**A5. How do you block outbound internet for a VM?**
**Answer:** Add an outbound rule: priority e.g. 100, source `*`, destination `Internet` (or `*`), action **Deny** — with a lower priority number than the default AllowInternetOutBound (which is 65001).

**A6. What are common legitimate outbound rules?**
**Answer:** Allow outbound to the **VNet** (inter-subnet), to **Azure services** (updates, DNS, Key Vault via service tags), and to **specific external endpoints** (APIs, package repos) — while denying general internet.

**A7. What is the difference between destination `Internet` and `VirtualNetwork` in outbound rules?**
**Answer:** `Internet` = public internet addresses (outside Azure). `VirtualNetwork` = this VNet's address space. Use them to scope outbound destinations precisely.

**A8. Can outbound rules use service tags and ASGs?**
**Answer:** Yes — e.g., destination service tags (`Storage`, `AzureKeyVault`, `AzureCloud`) and ASGs as source (e.g., "deny outbound from the DB ASG to Internet").

**A9. What is SNAT and why do private VMs need it for outbound internet?**
**Answer:** Source Network Address Translation — Azure translates the VM's private IP to a public IP for outbound internet traffic (via the VM's public IP, a NAT gateway, or a load balancer outbound rule).

**A10. How do you allow outbound to a specific domain/IP while blocking everything else?**
**Answer:** Add **Allow** rules (lower priority) for the specific destinations (IPs/CIDRs/service tags), then a **Deny** for `Internet` (higher priority number) as the catch-all.

**A11. What happens if a VM has outbound Deny on its NIC NSG but not the subnet NSG?**
**Answer:** Outbound evaluation is **NIC NSG first, then subnet NSG** — a Deny on the NIC blocks the traffic before the subnet rules are reached (effective rules = both must allow).

**A12. Why would you restrict outbound from a database subnet?**
**Answer:** To prevent **data exfiltration** and limit lateral movement — DBs typically don't need internet, only responses to the app tier and maybe Azure service calls.

**A13. What is a "DenyAllOutBound" pattern?**
**Answer:** Adding an explicit outbound **Deny** for `*`/`Internet` at the end (high priority number) so that only explicitly-allowed outbound destinations are permitted — a least-privilege egress design.

**A14. Do outbound NSG rules affect traffic to Azure services via service endpoints/private endpoints?**
**Answer:** Traffic to **private endpoints** (private IPs in your VNet) is VNet traffic and is subject to NSGs; **service endpoint** traffic routes via the subnet's service-endpoint route but NSGs can still filter it (with the service tag). Test per service.

**A15. How do you verify outbound rule effectiveness?**
**Answer:** Use **Network Watcher → IP flow verify** (choose outbound direction), **NSG flow logs** (see Deny/Allow per flow), and **Connection troubleshoot**.

---

## Case B — Advanced (Senior)

**B1. Explain why outbound is open by default and how to design a least-privilege egress posture.**
**Answer:** Azure's default allows outbound internet so VMs can patch/reach services without config — but this risks exfiltration/C2 channels. Least-privilege egress: **deny Internet by default**, then allow only required destinations (service tags for Azure services, specific CIDRs/domains for external APIs), typically enforced centrally via **Azure Firewall + UDRs** (force-tunnel) with NSG Deny rules as a second layer.

**B2. How do NSG outbound rules complement (or conflict with) route-based egress via Azure Firewall?**
**Answer:** NSGs filter (allow/deny) but don't route; **UDRs** steer traffic (e.g., 0.0.0.0/0 → Azure Firewall). For enforced egress: UDR sends traffic to the firewall; the firewall's network/FQDN rules decide allow/deny; NSGs can add a coarse "deny Internet directly" rule (defense in depth). If NSG blocks before routing, traffic never reaches the firewall — align both layers.

**B3. What is the interplay between outbound rules and SNAT (public IP, NAT gateway, LB outbound rules)?**
**Answer:** An outbound NSG **Allow** is required for the flow, but connectivity also needs a **SNAT path**: a public IP on the VM, a **NAT gateway** on the subnet, or a **load-balancer outbound rule**. If SNAT is missing (or exhausted), outbound fails even with NSG Allow — check SNAT port exhaustion separately.

**B4. How do you prevent data exfiltration to arbitrary internet destinations?**
**Answer:** Layer controls: (1) NSG **Deny Internet** on sensitive subnets (DB, internal), (2) **UDR 0.0.0.0/0 → Azure Firewall** for forced tunneling, (3) firewall **FQDN/network allowlists** for egress, (4) **Microsoft Defender for Cloud / Defender for Servers** behavioral detection, (5) restrict **outbound** to service tags for Azure services (via service/private endpoints).

**B5. What are the challenges of allowlisting outbound domains (FQDN) with NSGs, and how do you solve them?**
**Answer:** NSGs work on **IPs, not FQDNs** — and external APIs' IPs change. Solving: use **Azure Firewall FQDN rules** (it resolves and enforces domain allowlists), or service tags for Azure services. NSGs alone can't reliably allowlist domains — route through the firewall instead.

**B6. How do outbound NSG rules apply to a VM with both subnet and NIC NSGs (ordering)?**
**Answer:** Outbound evaluation order: **NIC NSG first, then subnet NSG**. Both must allow (unless a Deny in the NIC blocks first). This asymmetric ordering (vs inbound: subnet first) matters when debugging conflicting rules.

**B7. How do you monitor outbound traffic for anomalies (C2, exfiltration)?**
**Answer:** Enable **NSG flow logs** → Log Analytics + **Traffic Analytics** to see outbound flows/destinations; integrate **Defender for Cloud** and **Defender for Endpoint/Servers** for behavioral detection; alarm on unusual outbound volume or connections to known-bad IPs (threat intelligence via Azure Firewall/Sentinel).

**B8. What outbound rules do Azure platform services require (e.g., AKS, App Service, VM agents)?**
**Answer:** Managed services need outbound to their control planes — e.g., AKS nodes require specific FQDNs (api-server, MCR registry, monitoring) — use the `AzureCloud` service tag or the service's published FQDN list, never blanket `Internet`. Azure VM agents need `AzureCloud`/Azure endpoints. Use **UDR + firewall** with the service's allowlist.

**B9. How do you enforce "no outbound internet except via approved proxy/firewall" at scale (policy)?**
**Answer:** Combine **Azure Policy** (audit/deny NSGs that allow outbound Internet on sensitive subnets), **UDRs on all subnets** (0.0.0.0/0 → firewall), and **Azure Firewall** egress rules. Standardize via a hub-spoke landing-zone template so every new spoke inherits the egress controls.

**B10. Compare NSG outbound filtering vs Azure Firewall egress vs Private Link for "private-only" workloads.**
**Answer:** NSG = coarse L4 allow/deny (fast, per-subnet). Azure Firewall = central L7 egress with FQDN/threat intel (for inspection). **Private Link/endpoints** = remove the need for public egress entirely for Azure PaaS (traffic stays private). Use Private Link where possible, firewall for external egress, NSG as segmentation.

**B11. What is SNAT port exhaustion, and how do outbound rules/NAT gateways interact with it?**
**Answer:** SNAT ports are limited (per public IP ~64k ports); many concurrent outbound connections can **exhaust** them, causing intermittent outbound failures. **NAT gateway** allocates ports more granularly (per VM) and scales with more public IPs — the recommended fix. NSG rules don't cause exhaustion but monitoring flow logs helps correlate.

**B12. How do you handle outbound DNS in a locked-down environment (NSG denies Internet)?**
**Answer:** VMs need DNS: allow outbound to the **Azure DNS** (168.63.129.16 / the `Internet`-independent recursive resolver) or your **custom DNS forwarders**. Blocking all outbound without a DNS path breaks name resolution — allow UDP/TCP 53 to your DNS servers (on-prem or Azure DNS) explicitly.

---

## Case C — Scenario

**C1. Scenario:** After adding an outbound "Deny Internet" rule, VMs can't get OS updates or reach Azure services.
**Question:** Diagnose and fix.
**Answer:** The Deny blocks required destinations. Fix: add **Allow** rules (lower priority) for **Azure service tags** (`AzureCloud`, `AzureUpdateDelivery`, `Storage`, etc.) and your package repos before the Deny, or route updates via a **NAT/firewall allowlist**. Confirm DNS (port 53) is still allowed. Verify with flow logs which destinations are being denied.

**C2. Scenario:** A DB server suddenly can't be reached from the app tier after a security change, and outbound from the app to DB is fine.
**Question:** Which NSG direction likely broke, and why do people miss it?
**Answer:** The **DB's inbound** rule is likely missing the allow from the app subnet — but if the change was an **outbound Deny on the DB** (blocking its responses), that also breaks it. Since NSGs are stateful, an outbound Deny on the DB prevents its response traffic. Check both the app's outbound and the DB's inbound/outbound effective rules.

**C3. Scenario:** You must ensure a financial app's servers can reach **only** a partner API (two IPs) and no other internet.
**Question:** Write the outbound rule set.
**Answer:** Outbound rules (in priority order): (1) **Allow** TCP 443 to the partner's two CIDRs; (2) **Allow** DNS (53) to your DNS; (3) **Allow** `AzureCloud`/required service tags for platform services (if needed); (4) **Deny** `Internet` (catch-all). Use flow logs to confirm only intended destinations are reached.

**C4. Scenario:** Outbound connections from a VM intermittently fail ("connection timed out") during a traffic spike, then recover.
**Question:** Diagnose the likely non-NSG cause.
**Answer:** **SNAT port exhaustion** — the VM (or LB public IP) ran out of outbound SNAT ports during the spike. Fix: attach a **NAT gateway** to the subnet (scales SNAT ports), or add public IPs to the LB outbound rule, and monitor SNAT metrics. NSG rules would block consistently, not intermittently — use flow logs to confirm.

**C5. Scenario:** A VM must send logs to a Log Analytics workspace, but you've locked down outbound to Deny-All.
**Question:** Which destinations must you allow?
**Answer:** Allow outbound to the **Azure Monitor/Log Analytics endpoints** — via the relevant **service tags** (e.g., `AzureMonitor`, `AzureCloud`, plus `AzureActiveDirectory`/`AzureResourceManager` as needed) on **443**, and allow **DNS**. Best practice: use the published Log Analytics FQDN/tag list rather than guess. A **private link** to Log Analytics removes the public egress need entirely.

**C6. Scenario:** A compliance rule says no VM may reach the public internet, but some must reach Azure Key Vault and Storage.
**Question:** Design the egress architecture.
**Answer:** Use **Private Endpoints** for Key Vault and Storage (traffic stays in the VNet — no internet), then NSG **Deny Internet** for outbound with Allow for `VirtualNetwork` and required Azure tags. For any true external need, route through **Azure Firewall** with strict FQDN allowlists. This achieves "no public internet" while keeping Azure services reachable privately.
