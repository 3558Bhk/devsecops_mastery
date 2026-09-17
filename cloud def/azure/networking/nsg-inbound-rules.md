# Azure NSG Inbound Rules — Interview Questions

> **Cloud:** Azure · **Category:** Networking · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

Inbound NSG rules are the same JSON rule shape with `direction: "Inbound"`. The source can be a CIDR, a **service tag**, or an **ASG resource id**.

```json
{
  "name": "AllowSshFromOffice",
  "properties": {
    "priority": 110,
    "direction": "Inbound",
    "access": "Allow",
    "protocol": "Tcp",
    "sourceAddressPrefix": "203.0.113.0/24",
    "sourcePortRange": "*",
    "destinationAddressPrefix": "*",
    "destinationPortRange": "22"
  }
}
```

**Key fields:** `direction: "Inbound"` · `sourceAddressPrefix` (or `sourceAddressPrefixes[]`, `sourceApplicationSecurityGroups[]`) · `destinationPortRange` / `destinationPortRanges[]`. NSGs are stateful, so the return path is automatic; inbound evaluation order is subnet NSG → NIC NSG.


## Case A — Basic

**A1. What is an NSG inbound rule?**
**Answer:** A security rule that controls traffic **entering** a subnet or NIC — evaluated by priority (lowest first, first match wins), with Allow or Deny action.

**A2. What are the default inbound rules of an NSG?**
**Answer:** **AllowVnetInBound** (allow all traffic within the VNet), **AllowAzureLoadBalancerInBound** (allow LB probes/health), and **DenyAllInBound** (deny everything from the internet not otherwise allowed).

**A3. What fields define an inbound rule?**
**Answer:** Priority, source (IP/CIDR/service tag/ASG), source port range, destination, destination port range, protocol, and action (Allow/Deny).

**A4. Why is the default `DenyAllInBound` important?**
**Answer:** It's the safety net: anything not explicitly allowed from outside is denied by default — so new resources are closed to the internet until you add rules.

**A5. How do you allow HTTPS (443) from the internet?**
**Answer:** Inbound rule: priority e.g. 100, source `Internet` (or `*`), source port `*`, destination `*`, destination port `443`, protocol TCP, action **Allow** — placed above the default DenyAll.

**A6. What does source `*` vs `Internet` vs `VirtualNetwork` mean?**
**Answer:** `*` = any source (including Azure + internet). `Internet` = public internet addresses. `VirtualNetwork` = the VNet's address space. Use the tightest tag that fits.

**A7. Can you specify both source and destination as service tags or ASGs?**
**Answer:** Yes — source can be a service tag/ASG/CIDR, and destination can be an ASG/CIDR (destination service tags are limited; destination is usually the resource's IP or an ASG).

**A8. What is the priority range and which number wins?**
**Answer:** Priority 100–4096 (custom rules); **lower numbers are evaluated first** and win on first match.

**A9. Does an inbound Allow automatically allow the outbound response?**
**Answer:** Yes — NSGs are **stateful**, so the return traffic for an allowed inbound flow is permitted without a matching outbound rule.

**A10. What happens when two inbound rules match the same traffic?**
**Answer:** The rule with the **lower priority number** (evaluated first) applies; the other is never reached (first match wins).

**A11. How do you restrict SSH to only your office IP?**
**Answer:** Inbound rule: source = your office **CIDR** (not `*`), destination port 22, TCP, Allow — so only that IP range can SSH.

**A12. What is the difference between inbound rules on the subnet vs the NIC?**
**Answer:** For inbound traffic, the **subnet NSG** is evaluated first, then the **NIC NSG** — both must allow for the traffic to pass (effective rules).

**A13. Can you use ICMP in inbound rules?**
**Answer:** Yes — protocol **ICMP** (or `*` for all protocols), e.g., to allow ping to a VM (ICMP has no ports, so port is `*`).

**A14. What is the `AzureLoadBalancer` inbound rule for?**
**Answer:** It allows the load balancer's **health probe** traffic to reach backend VMs — required for probes to succeed (the default rules include it).

**A15. How do you see which inbound rules apply to a NIC?**
**Answer:** Use **Network Watcher → Effective security rules** on the NIC, which merges subnet + NIC NSG rules in evaluation order.

---

## Case B — Advanced (Senior)

**B1. Explain the full inbound evaluation path: NIC vs subnet NSG ordering and stateful behavior.**
**Answer:** Inbound traffic first passes the **subnet NSG** (if attached), then the **NIC NSG** (if attached) — both must Allow. Because NSGs are stateful, the outbound response is allowed automatically. The **effective security rules** view shows the merged, ordered list — use it to reason about the final decision.

**B2. How do you design inbound rules for least privilege in a public-facing web tier?**
**Answer:** Allow only: 80/443 from `Internet` (or from a CDN/WAF prefix via service tag where available), `AzureLoadBalancer` for probes, and management ports (22/3389) only from a **bastion/JIT** or corporate CIDR. Add an explicit **DenyAll** and never use `*` for management ports. Document each rule's purpose.

**B3. What are the pitfalls of using `*` as source, and how do service tags reduce risk?**
**Answer:** `*` includes the entire internet **and** Azure — very risky for management ports (RDP/SSH brute-force). Service tags (e.g., `Internet`, `VirtualNetwork`, `AzureCloud`) scope the source to a meaningful set. Prefer specific CIDRs or ASGs; reserve `*` for truly public endpoints (443).

**B4. How do inbound rules interact with Azure Load Balancer (data path vs probe path)?**
**Answer:** **Probes** originate from the Azure platform (allow `AzureLoadBalancer` tag → backend port). **Client data** flows through the LB but the **source IP is the client's IP** (default L4 LB), so your inbound rules must allow the **client IPs** on the backend port. Confusing these two is a frequent cause of "LB works but backends don't get traffic."

**B5. How do you implement IP allowlisting that changes frequently (e.g., SaaS provider IPs)?**
**Answer:** Use **service tags** if Azure publishes one; otherwise maintain a **CIDR list** via an **IP group** (reusable in Azure Firewall) or update NSG rules through **automation** (PowerShell/CLI/ARM) when the provider publishes new ranges. Consider Azure Front Door/WAF for edge allowlisting instead of per-subnet NSGs.

**B6. How do inbound NSGs apply to private endpoints and delegated subnets (gotchas)?**
**Answer:** Private endpoints have a **NIC in your subnet**, so NSGs can apply at that NIC — but some services require the subnet's `PrivateEndpointNetworkPolicies` disabled, which changes enforcement. For **delegated subnets** (e.g., SQL MI, App Service), NSG policy support varies — always check the service's NSG compatibility before relying on it.

**B7. How do you test and validate inbound rules before and after changes?**
**Answer:** **Before**: review the change via ARM/CLI dry-run and peer review. **After**: use **IP flow verify** (test the 5-tuple), **Connection troubleshoot**, and **NSG flow logs** (confirm Accept/Deny in the logs). Automate validation with Azure Policy for forbidden rules (e.g., no 22 from Internet).

**B8. What is the relationship between inbound NSG rules and Windows/Linux OS firewalls?**
**Answer:** They're **independent layers** — the NSG (platform) and the OS firewall (iptables/ufw/Windows Firewall) must **both** allow the traffic. A common trap: NSG allows 22 but the OS firewall blocks it (or vice versa). Check both when troubleshooting.

**B9. How do you handle overlapping/subnet-and-NIC inbound rules cleanly (rule sprawl)?**
**Answer:** Keep a clear convention: subnet NSGs for **shared baseline** (deny management ports, allow LB probes), NIC NSGs only for **exceptions**. Use ASGs to group roles, avoid duplicate rules, and periodically review with **Defender for Cloud** recommendations + an IaC pipeline (Bicep/Terraform) so rules are code-reviewed.

**B10. How do you prioritize inbound rules when requirements conflict (e.g., "allow this IP but block that IP")?**
**Answer:** Order by specificity: put the **Deny for the specific IP** at a **lower priority number** than the broader Allow, so the specific deny wins (first match). Always place specific rules before broad ones; the default DenyAll remains the catch-all.

**B11. How does Just-in-Time (JIT) VM access relate to inbound NSG rules?**
**Answer:** Defender for Cloud's **JIT** automatically adds **temporary Allow** inbound NSG rules (for your current IP, on 22/3389, for a limited window) and removes them after expiry — so management ports stay closed by default and open only when requested, replacing permanent open rules.

**B12. What inbound rule design supports a WAF/App Gateway in front of app servers (source restriction)?**
**Answer:** Allow inbound to app servers **only from the Application Gateway subnet** (or its CIDR/ASG) on the backend port — not from `Internet` — since the App Gateway (with WAF) is the only legitimate entry. Optionally use the `AzureFrontDoor.Backend`/AppGW service tag. This prevents direct access bypassing the WAF.

---

## Case C — Scenario

**C1. Scenario:** RDP (3389) to a VM times out. NSG shows an Allow rule for 3389.
**Question:** What else could block it (checklist)?
**Expected answer:** (1) The Allow's **source** may not include your IP (e.g., a wrong CIDR), (2) a lower-priority **Deny** is matching first, (3) the **subnet NSG** (not just NIC) lacks the allow, (4) the VM has no **public IP** or the route is wrong, (5) the **OS firewall** blocks 3389, (6) the VM is stopped. Use **IP flow verify** + **effective rules** to isolate.

**C2. Scenario:** After migrating a VM, users can't reach the app on 443 even though the old NSG was copied.
**Question:** What's a likely cause?
**Answer:** The copied NSG's rules may reference **old IPs/service tags/ASGs** that don't apply to the new VM (e.g., a destination ASG the new NIC isn't in, or a source CIDR from the old subnet). Verify the destination/ASG membership and that the NSG is **attached** to the new subnet/NIC; check effective rules.

**C3. Scenario:** A security audit flags inbound rules with source `*` on ports 22, 3389, and 1433.
**Question:** Remediate without breaking business access.
**Answer:** Inventory who needs access: replace `*` with **corporate CIDRs**, a **bastion subnet/ASG**, or **JIT** for admins; restrict 1433 to the **app-tier ASG/CIDR** only. Implement **Azure Policy** to deny `*` on management ports going forward and verify with flow logs that legitimate traffic still flows.

**C4. Scenario:** A health probe from Azure Load Balancer is failing only for one backend VM.
**Question:** Which inbound rule specifics could cause it?
**Answer:** That VM's NSG (or its NIC NSG) may be missing/denying the **`AzureLoadBalancer` service tag** on the probe port, or a rule change on that NIC blocks it. Check the effective rules for that NIC vs healthy VMs, and re-add Allow `AzureLoadBalancer` → backend port.

**C5. Scenario:** You must allow inbound traffic only from another VNet (10.20.0.0/16) to a DB subnet.
**Question:** Write the rule and note the peering prerequisite.
**Answer:** Prerequisite: the VNets must be **peered** (or connected via hub/ER). Inbound rule: source = `10.20.0.0/16` (or the `VirtualNetwork` tag won't cover cross-VNet), destination port 1433/3306, TCP, Allow, priority above DenyAll. Using the peer's actual CIDR is required since `VirtualNetwork` only means "this VNet."

**C6. Scenario:** An app behind Application Gateway is reachable via the gateway, but users can also hit the VM's public IP directly, bypassing WAF.
**Question:** How do you block direct access?
**Answer:** Remove the VM's **public IP** (or stop using it), and set the app VM's inbound NSG to allow 443 **only from the Application Gateway subnet/ASG** — not from `Internet`. Then the only internet path is through the App Gateway + WAF. Optionally add a `Deny` for `Internet` on 443.
