# Azure NSG Introduction — Interview Questions

> **Cloud:** Azure · **Category:** Networking · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~10 min

---

## JSON File Format

NSGs are defined in JSON as ARM resources (`Microsoft.Network/networkSecurityGroups`) whose `securityRules` array holds the rule objects.

```json
{
  "type": "Microsoft.Network/networkSecurityGroups",
  "apiVersion": "2023-04-01",
  "name": "web-nsg",
  "properties": {
    "securityRules": [{
      "name": "AllowHttps",
      "properties": {
        "priority": 100,
        "direction": "Inbound",
        "access": "Allow",
        "protocol": "Tcp",
        "sourcePortRange": "*",
        "destinationPortRange": "443",
        "sourceAddressPrefix": "*",
        "destinationAddressPrefix": "*"
      }
    }]
  }
}
```

**Key fields:** `securityRules[]` · `priority` (100–4096, lower wins) · `direction` (Inbound/Outbound) · `access` (Allow/Deny) · `protocol` · `sourceAddressPrefix` / `destinationAddressPrefix` (CIDR, service tag, or ASG id) · port ranges.


## Case A — Basic

**A1. What is a Network Security Group (NSG)?**
**Answer:** A filter that allows or denies inbound and outbound traffic to Azure resources, based on **security rules** (source/destination, port, protocol). It's Azure's basic stateful firewall, applied at the **subnet** and/or **NIC** level.

**A2. What can an NSG be attached to?**
**Answer:** A **subnet** (applies to all resources in it) and/or a **network interface (NIC)** (applies to that VM). You can attach at both levels for defense in depth.

**A3. Is an NSG stateful or stateless?**
**Answer:** **Stateful** — if you allow inbound traffic, the return traffic is automatically allowed (you don't need a separate outbound rule for the response).

**A4. What are the components of an NSG rule?**
**Answer:** **Priority** (100–4096, lower wins), **direction** (inbound/outbound), **source/destination** (IP/CIDR, service tag, ASG), **protocol** (TCP/UDP/ICMP/Any), **port range**, and **action** (Allow/Deny).

**A5. What are the default NSG rules?**
**Answer:** Default rules allow **all traffic within a VNet** and outbound to the internet, and deny all inbound from the internet — plus load balancer health-probe and Azure load-balancer allowances. These can't be deleted (but can be overridden with lower-priority rules).

**A6. What is a rule priority and how are rules evaluated?**
**Answer:** Rules are evaluated in **ascending priority order** (100 first, 4096 last); the **first match wins**. Lower number = higher precedence.

**A7. How does an NSG differ from Azure Firewall?**
**Answer:** NSG = basic, stateful L3/L4 filtering attached to subnets/NICs (no FQDN rules, no central logging/threat intelligence). Azure Firewall = a managed, central, L3–L7 firewall with FQDN filtering, threat intelligence, and centralized logging. They're often used together.

**A8. What is the difference between NSG rules and ASG-based rules?**
**Answer:** Standard rules use IP/CIDR/service tags. **ASG (Application Security Group)** rules reference logical groups of NICs (e.g., "web servers") — abstracting away IPs and simplifying management.

**A9. Do NSGs apply to traffic between subnets in the same VNet?**
**Answer:** Yes — NSGs filter traffic entering/leaving a subnet, including **inter-subnet** (east-west) traffic, depending on where they're attached.

**A10. Do NSGs apply to traffic within the same subnet (VM to VM)?**
**Answer:** Only if the NSG is attached to the **NICs** (subnet-level NSGs don't filter intra-subnet VM-to-VM traffic, because the traffic doesn't leave the subnet).

**A11. What is a service tag?**
**Answer:** A named alias for Azure service IP ranges (e.g., `Internet`, `AzureLoadBalancer`, `VirtualNetwork`, `Storage`, `AzureCloud`) — so you don't maintain IP lists.

**A12. Can an NSG have both Allow and Deny rules?**
**Answer:** Yes — unlike AWS Security Groups (allow-only), NSGs support **both Allow and Deny**, evaluated by priority.

**A13. How many rules can an NSG have?**
**Answer:** Up to **1,000 rules** per NSG (some regions 5,000 with limits), plus default rules — plan priorities accordingly.

**A14. What happens if a VM has an NSG on both its NIC and its subnet?**
**Answer:** Both are evaluated: **inbound** = subnet NSG first, then NIC NSG; **outbound** = NIC NSG first, then subnet NSG. Traffic must pass **both** (effective security rules).

**A15. What is the "Effective security rules" view?**
**Answer:** A Network Watcher feature showing the **combined** result of all NSGs (subnet + NIC) applied to a NIC — used to troubleshoot allow/deny decisions.

---

## Case B — Advanced (Senior)

**B1. Explain NSG rule evaluation order, including how default rules interact with your custom rules.**
**Answer:** Rules are matched by **priority (100–4096), first match wins**, for the relevant direction. Default rules are at high priorities (e.g., 65000/65001/65500), so any custom rule (100–4096) wins over them — meaning you can **override** the default deny-inbound by adding an Allow with lower priority. Understanding this lets you correctly punch holes (e.g., allow 22 from a specific IP above the default deny).

**B2. How does stateful filtering actually work in NSGs, and what does it mean for ephemeral ports?**
**Answer:** NSGs track flows (5-tuple): when you allow an inbound connection, the return packets are automatically allowed because they belong to an established flow. This is why you don't configure ephemeral-port return rules like you would with AWS NACLs. (For truly stateless scenarios, you'd use Azure Firewall/other tooling.)

**B3. When do you use NSG vs Azure Firewall vs both?**
**Answer:** **NSG** = fine-grained L3/L4 filtering at subnet/NIC (micro-segmentation). **Azure Firewall** = central L3–L7 filtering with FQDN rules, IDPS, threat intelligence, and centralized logging. **Both**: NSGs for per-subnet segmentation + Azure Firewall (in the hub) for central egress/inspection — the recommended hub-spoke pattern.

**B4. What are Application Security Groups (ASGs) and how do they simplify NSG management at scale?**
**Answer:** ASGs group NICs by **role** (e.g., `WebServers`, `DBServers`). NSG rules can then use the ASG as source/destination — e.g., "allow 3306 from `WebServers` ASG to `DBServers` ASG." This avoids IP-list maintenance when VMs scale in/out, since the ASG membership (not IPs) defines the rule.

**B5. How do you design least-privilege NSG rules for a three-tier app?**
**Answer:** Web subnet NSG: allow 80/443 from `Internet`, deny rest. App subnet NSG: allow app port only from **web subnet CIDR/ASG**. DB subnet NSG: allow 1433/3306 only from **app subnet CIDR/ASG**. Use **service tags** (e.g., `AzureLoadBalancer` for health probes) and explicit Deny-All as the final custom rule. Least privilege = allow specific flows, deny everything else.

**B6. Explain how NSG + service tags make rules resilient to IP changes (e.g., AzureLoadBalancer, Internet).**
**Answer:** Service tags abstract Azure-managed IP ranges: e.g., the `AzureLoadBalancer` tag covers the LB health-probe source IPs, and `Internet` covers public internet. When Azure updates ranges, your rules stay correct without edits. The default rules already use `AzureLoadBalancer` to permit probes — this is why health checks work even with restrictive NSGs.

**B7. How do NSGs interact with load balancers (probe traffic, data-path traffic)?**
**Answer:** Health **probes** come from Azure's platform (tag `AzureLoadBalancer`) and must be allowed to the backend port. **Client data traffic** flows through the LB with the **client's source IP preserved** (for the default load balancer), so NSG rules must allow the **client IPs** (not the LB's IP). This is a classic misconfiguration source.

**B8. What are the performance/scale considerations for NSGs (rule count, many rules, evaluation)?**
**Answer:** Rule evaluation is efficient (flow-based, stateful), but keep rule sets tidy: avoid hundreds of overlapping rules, use **service tags/ASGs** to consolidate, and remember limits (~1,000 rules/NSG). For very large, dynamic IP allowlists, consider Azure Firewall IP groups or a central firewall instead of bloated NSGs.

**B9. How do you audit NSG changes and detect over-permissive rules (0.0.0.0/0 on 22/3389)?**
**Answer:** Enable **NSG diagnostics** (send logs to Log Analytics/Storage), use **Azure Policy** (e.g., deny inbound from Internet on management ports), **Microsoft Defender for Cloud** recommendations (which flag open management ports), and query **NSG flow logs** for actual traffic. Alert on NSG rule changes via **Activity Log**/alerts.

**B10. What is the difference between an NSG at the subnet vs the NIC level, and when do you use both?**
**Answer:** Subnet NSG = coarse policy for everything in the subnet. NIC NSG = per-VM policy. Using both gives layered security (a VM gets subnet rules + its own NIC rules), but increases complexity and troubleshooting effort. Common practice: subnet-level for broad segmentation, NIC-level for exceptions/special cases.

**B11. How do NSGs apply to PaaS services (delegated subnets, private endpoints)?**
**Answer:** For services with **delegated subnets** (e.g., App Service vnet integration, SQL MI), NSG policies on the delegated subnet may be restricted — check the service's NSG support. **Private endpoints** use a NIC in your subnet, so NSGs **do** apply to private-endpoint traffic (NIC-level), though some services require the private endpoint subnet's `PrivateEndpointNetworkPolicies` to be disabled.

**B12. How do you troubleshoot "why is my traffic blocked/allowed" with NSGs efficiently?**
**Answer:** Use **Network Watcher → IP flow verify** (tests a 5-tuple against effective rules), **Effective security rules** (combined view), **NSG flow logs** (see accepted/denied flows), and **Connection troubleshoot**. Correlate the flow-log action with the specific rule priority/name.

---

## Case C — Scenario

**C1. Scenario:** SSH (port 22) to a VM fails, but the VM is running and has a public IP.
**Question:** Walk through the NSG diagnosis.
**Expected answer:** (1) Check the **NSG inbound rules** on the VM's NIC and subnet for an Allow on TCP 22 from your IP (priority must beat the default deny). (2) Verify the NSG is actually attached to the NIC/subnet. (3) Use **IP flow verify** to confirm the NSG decision. (4) Check the **OS firewall** (ufw/iptables/Windows) allows 22. (5) Confirm the public IP is associated with the NIC.

**C2. Scenario:** A web app behind an Azure Load Balancer fails health checks after you tightened NSGs.
**Question:** Which rule did you likely remove, and why?
**Answer:** The NSG must allow the LB's **health probes** — the default rules include an Allow from the `AzureLoadBalancer` service tag (port 1688 for the probe source). If you deleted/overrode it with a Deny-All that blocks that tag, probes fail and the backend is marked unhealthy. Re-add: Allow `AzureLoadBalancer` → backend port (and verify client-data rules still allow client IPs).

**C3. Scenario:** Security requires that only the web tier can reach the database tier on 1433, and nothing else — and the web tier auto-scales.
**Question:** Design with ASGs.
**Answer:** Create ASGs `web-asg` (attach web VMs' NICs) and `db-asg` (attach DB VMs' NICs). On the DB subnet/NSG: **Allow TCP 1433 source = `web-asg`, destination = `db-asg`**, and a final **Deny-All**. Because ASGs reference NIC membership, newly scaled web VMs automatically gain access without IP edits.

**C4. Scenario:** Users can't reach a VM on port 443, but 80 works. Both rules appear correct.
**Question:** Diagnose the priority/logic issue.
**Expected answer:** Check **rule priority** — a higher-precedence (lower number) **Deny** rule (e.g., Deny all 1–65535, or Deny 443) may be matching before the Allow 443. Because NSGs are **first-match-wins**, the Allow must have a **lower priority number** than any conflicting Deny. Review via **Effective security rules** and reorder.

**C5. Scenario:** A DB VM received a brute-force attack on port 3389 from the internet.
**Question:** How do you block it and prevent recurrence?
**Answer:** Immediately add a high-priority **Deny** rule for the attacker's IP (or better, ensure RDP is only allowed from your corporate CIDR/just-in-time). Use **Defender for Cloud JIT VM access**, remove 0.0.0.0/0 on 3389, restrict via service tag/ASG, enable **NSG flow logs**, and set **Azure Policy** to deny open management ports.

**C6. Scenario:** An app in subnet-A can't reach a service in subnet-B, but the reverse works.
**Question:** Why asymmetric, and how do you fix it?
**Answer:** NSGs are **stateful**, so an allowed outbound flow's return is auto-allowed — asymmetry suggests the **inbound** NSG on subnet-B's side (or NIC) lacks an Allow for subnet-A's CIDR on the service port, while the outbound from A is allowed. Fix: add the matching **inbound** Allow on B's NSG from subnet-A. Use IP flow verify on the failing direction.
