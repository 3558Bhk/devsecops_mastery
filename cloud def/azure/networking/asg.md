# Azure Application Security Groups (ASG) — Interview Questions

> **Cloud:** Azure · **Category:** Networking · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

Application Security Groups are JSON ARM resources (`Microsoft.Network/applicationSecurityGroups`), and NSG rules reference them by **resource id** as source/destination.

```json
{
  "type": "Microsoft.Network/applicationSecurityGroups",
  "apiVersion": "2023-04-01",
  "name": "web-asg",
  "location": "eastus",
  "properties": {}
}
```

Rule referencing an ASG:
```json
{
  "name": "AllowWebToDb",
  "properties": {
    "priority": 100,
    "direction": "Inbound",
    "access": "Allow",
    "protocol": "Tcp",
    "sourceApplicationSecurityGroups": [{ "id": "/subscriptions/<sub>/resourceGroups/rg/providers/Microsoft.Network/applicationSecurityGroups/web-asg" }],
    "destinationApplicationSecurityGroups": [{ "id": "/subscriptions/<sub>/resourceGroups/rg/providers/Microsoft.Network/applicationSecurityGroups/db-asg" }],
    "destinationPortRange": "1433"
  }
}
```

**Key fields:** `sourceApplicationSecurityGroups` / `destinationApplicationSecurityGroups` (full resource ids, VNet-scoped). NICs join an ASG via the NIC's `ipConfigurations[].applicationSecurityGroups`.


## Case A — Basic

**A1. What is an Application Security Group (ASG)?**
**Answer:** A logical grouping of **network interfaces** (VMs) that you reference in NSG rules — letting you write security rules by **role** (e.g., "web servers") instead of IP addresses.

**A2. How does an ASG differ from a subnet-based NSG?**
**Answer:** Subnet NSGs filter by **network location** (all resources in a subnet). ASGs filter by **resource role** — you group NICs across subnets and write rules referencing the group, regardless of IPs.

**A3. How do you add a VM to an ASG?**
**Answer:** Attach the VM's **NIC** to the ASG (a NIC can belong to multiple ASGs; a VM's multiple NICs can each join different ASGs).

**A4. How is an ASG used in an NSG rule?**
**Answer:** As the **source** or **destination** of a rule — e.g., allow TCP 1433 from ASG `web-servers` to ASG `db-servers`.

**A5. Can ASGs span subnets and VNets?**
**Answer:** ASGs can span **subnets** freely, but are scoped to **one VNet** (you can't reference an ASG across different VNets; NSG rules referencing ASGs must be in the same VNet).

**A6. Does an ASG replace an NSG?**
**Answer:** No — an ASG is **not** a firewall. It's a grouping/tagging mechanism used **inside** NSG rules. You still need an NSG to enforce allow/deny.

**A7. What is the key benefit of ASGs?**
**Answer:** **IP-free security rules** — when VMs scale in/out or change IPs, rules stay valid because they reference the logical group, dramatically simplifying rule management.

**A8. Can one NIC belong to multiple ASGs?**
**Answer:** Yes — a NIC can join multiple ASGs (e.g., a VM can be in both `web-servers` and `app-servers`), enabling layered rules.

**A9. Is an ASG stateful or stateless?**
**Answer:** ASGs have no state concept — they're just groupings. The **NSG** that uses them remains stateful.

**A10. What's a common ASG design for a three-tier app?**
**Answer:** ASGs `web-asg`, `app-asg`, `db-asg`; rules: web → app (app port), app → db (db port), internet → web (80/443) — all referencing ASGs, not IPs.

**A11. How do ASGs help with Azure Load Balancer/VMSS backends?**
**Answer:** You can add VMSS/VM NICs to an ASG so NSG rules automatically cover all scale-set instances (new instances join the ASG and inherit the rules).

**A12. Can you use ASGs in both inbound and outbound rules?**
**Answer:** Yes — ASGs can be source or destination in either direction of an NSG rule.

**A13. Are there costs for ASGs?**
**Answer:** No — ASGs are free; you pay only for the underlying resources.

**A14. How is an ASG different from a service tag?**
**Answer:** A service tag = Azure's managed IP ranges for a **service** (e.g., `AzureLoadBalancer`). An ASG = **your** logical group of NICs. Both are rule abstractions, but ASGs are user-defined for your VMs.

**A15. What happens to NSG rules if you delete an ASG?**
**Answer:** Rules referencing a deleted ASG become invalid/stop matching — so remove or update rules before deleting an ASG.

---

## Case B — Advanced (Senior)

**B1. Explain how ASGs enable micro-segmentation without IP management (the core value).**
**Answer:** Instead of maintaining CIDRs per role (which break when IPs change or VMs scale), you assign NICs to role-based ASGs once, and NSG rules reference ASG-to-ASG. Auto-scaling instances automatically join the ASG and instantly inherit the security policy — no rule edits, no stale IPs. This is the foundation of scalable micro-segmentation.

**B2. Design a least-privilege east-west policy using ASGs across a multi-tier, multi-subnet app.**
**Answer:** Create ASGs per tier/function (`web`, `api`, `db`, `worker`). Write NSG rules: `web→api:443`, `api→db:1433`, `worker→db:1433`, `api→worker:5672`, etc., each **ASG→ASG** with a final Deny-All. No traffic between other roles is possible, regardless of subnet layout — a clean zero-trust east-west baseline.

**B3. What are ASG limitations you must design around?**
**Answer:** (1) Scoped to a **single VNet** (no cross-VNet ASG references), (2) membership changes require NIC updates (no auto-discovery by tag), (3) an NSG rule can reference **limited** ASGs, (4) ASGs are region/VNet-specific, (5) they don't work with **some Azure Firewall / advanced scenarios** where you use IP groups instead. Plan VNet boundaries accordingly.

**B4. How do ASGs compare to NSG "service tags" and "IP groups" for rule abstraction?**
**Answer:** ASGs = role-based grouping of **your NICs** (VNet-scoped). **Service tags** = Azure-managed IP ranges for services. **IP groups** = your own managed CIDR collections (usable in Azure Firewall and NSGs). Use ASGs for intra-VNet role segmentation; IP groups for reusable CIDR lists (e.g., branch offices); service tags for Azure platform ranges.

**B5. How do you automate ASG membership in a VMSS or CI/CD pipeline?**
**Answer:** In **VMSS**, reference the ASG in the network profile so every scale-out instance joins automatically. In IaC (Bicep/Terraform), declare the ASG + NIC association as code. For dynamic membership (beyond VMSS), use Azure Policy or a small automation runbook to manage NIC-ASG bindings.

**B6. How do ASGs interact with hub-spoke and Azure Firewall designs (do they cross boundaries)?**
**Answer:** ASGs are **VNet-scoped**, so spoke-to-spoke segmentation via ASG is only within one VNet. For cross-VNet policy, enforce centrally at the **Azure Firewall** (using IP groups/network rules) or peer with careful NSG rules per VNet. Keep ASGs for intra-VNet; use firewall policy for inter-VNet.

**B7. How do you troubleshoot a rule that references an ASG ("why is this traffic denied/allowed")?**
**Answer:** Check the ASG's **NIC memberships** (is the source/destination NIC actually in the ASG?), confirm the NSG rule's direction/ports, and use **Network Watcher → Effective security rules** (which resolves ASGs to the effective NICs) + **IP flow verify**. A common bug: the NIC was never added to the ASG.

**B8. What is the recommended governance for ASGs (naming, tagging, review)?**
**Answer:** Standardize ASG names by role (`asg-web-prod`), document membership, manage via IaC, restrict who can attach NICs to ASGs (RBAC — `Microsoft.Network/applicationSecurityGroups/join/action`), and periodically review membership for drift (a stale membership = unintended access).

**B9. How do ASGs help with compliance/audit (Defender for Cloud, network policies)?**
**Answer:** ASG-based rules are **self-documenting** (role-to-role intent is explicit), which auditors can read. Defender for Cloud/Network Security posture can assess NSG rules; combining ASGs with Azure Policy (e.g., require ASG-based segmentation for tiers) gives auditable, role-based network controls.

**B10. Compare ASG-based segmentation with Azure Firewall + network rules for east-west traffic.**
**Answer:** ASGs + NSGs = **distributed**, per-subnet/NIC, L4, no central logging/threat intel — good for fast, scalable micro-segmentation. Azure Firewall = **centralized** L3–L7 with FQDN/IDPS/threat intel and central logs — good for cross-VNet/egress inspection. Many designs use both: NSG+ASG inside VNets, firewall between VNets/internet.

**B11. How do you migrate existing IP-based NSG rules to ASG-based rules safely?**
**Answer:** (1) Create ASGs per role. (2) Attach the corresponding NICs. (3) Add parallel ASG-based Allow rules. (4) Validate with flow logs that traffic still flows (both rule sets active). (5) Remove the old IP-based rules. (6) Review effective rules to confirm identical outcomes before cutover.

**B12. What role do ASGs play in a zero-trust network model in Azure?**
**Answer:** Zero-trust assumes no implicit trust by location. ASGs enable **identity/role-based** segmentation at the network layer: rules are expressed by what the resource **is** (role), not where it sits (subnet/IP), and default-deny ensures only explicit role-to-role flows are allowed — a key building block of Azure zero-trust.

---

## Case C — Scenario

**C1. Scenario:** Your auto-scaling web tier (VMSS) talks to a DB; the DB NSG currently uses the web subnet CIDR, but you're migrating to a shared subnet.
**Question:** Refactor with ASGs.
**Expected answer:** Create `asg-web` and attach the VMSS's network profile (so all instances join automatically) and `asg-db` for the DB NICs. Change the DB NSG rule to: **Allow 1433 source = `asg-web`, destination = `asg-db`**. The rule now works regardless of subnet/IP changes and covers every scale-out instance.

**C2. Scenario:** Traffic between two VMs is denied, and the NSG rule references ASG `app-servers`.
**Question:** Diagnose.
**Expected answer:** Verify the source/destination **NICs are actually members of `app-servers`** (an empty or wrong ASG matches nothing). Check the rule direction/priority and use **Effective security rules** (it shows which ASG-resolved rules apply to the NIC) + **IP flow verify** to see the effective decision.

**C3. Scenario:** A developer added a test VM to `asg-db` "for testing" and it now has DB access.
**Question:** How do you control ASG membership (the real risk)?
**Answer:** This is the core ASG governance risk: membership grants access. Mitigate with **RBAC** — restrict `join/action` on ASGs to a security/automation identity (not developers), manage membership via **IaC/VMSS only**, and add **auditing** (Activity Log) + periodic membership review. Alternatively use Azure Policy to enforce which identities may attach to which ASGs.

**C4. Scenario:** You need role-based rules spanning **two VNets** (web in VNet-A, db in VNet-B).
**Question:** Why can't you use one ASG, and what's the alternative?
**Answer:** ASGs are **VNet-scoped** — you can't reference an ASG across VNets. Alternatives: (1) peer the VNets and use **CIDR-based** NSG rules on the DB subnet for VNet-A's web subnet, or (2) enforce cross-VNet role policy centrally via **Azure Firewall** (with IP groups per role). Keep ASGs for intra-VNet segmentation.

**C5. Scenario:** An auditor wants to see "which roles can talk to the database tier" without reading every IP rule.
**Question:** How do ASGs make this easier?
**Answer:** With ASG-based rules, the policy reads as role-to-role (e.g., `app-servers` → `db-servers` on 1433) — self-documenting intent. Export the NSG rules and ASG memberships for the auditor; the answer to "who can talk to the DB" is the set of ASGs allowed as sources, not a pile of CIDRs.

**C6. Scenario:** You're building a landing-zone template so every new app gets consistent tier segmentation automatically.
**Question:** Design the ASG + NSG pattern.
**Answer:** In the Bicep/Terraform module: create `asg-web`, `asg-app`, `asg-db`; a default-deny NSG with rules web→app, app→db, internet→web(443); and wire VMSS/NIC memberships. New apps deploy the same template, getting identical, least-privilege, role-based segmentation without bespoke IP planning.
