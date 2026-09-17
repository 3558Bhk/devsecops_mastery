# Terraform NSGs & Network Security (Azure) — Interview Questions

> **Cloud:** Azure · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~6 min

---

## Case A — Basic

**A1. What is a Network Security Group (NSG) in Terraform?**
**Answer:** `azurerm_network_security_group` — a stateful firewall filtering traffic to/from Azure resources via security rules.

**A2. How do you declare an NSG?**
**Answer:** `resource "azurerm_network_security_group" "nsg" { name = ... ; resource_group_name = ... ; location = ... }` plus `security_rule` blocks (or separate rule resources).

**A3. What does an NSG rule contain?**
**Answer:** `name`, `priority` (100–4096), `direction` (Inbound/Outbound), `access` (Allow/Deny), `protocol`, `source/destination_port_range(s)`, and `source/destination_address_prefix(es)`.

**A4. What are the default NSG rules?**
**Answer:** Built-in rules: allow VNet-internal traffic, allow Azure Load Balancer probes, deny all inbound from internet, and allow outbound to internet — overridable with higher-priority rules.

**A5. How are rules evaluated?**
**Answer:** Lowest priority number wins; the first match (allow or deny) is applied. Higher numbers are evaluated later.

**A6. What is the difference between NSG and Azure Firewall?**
**Answer:** NSG is a basic stateful L3/L4 filter for subnets/NICs; Azure Firewall is a managed, centralized NVA with L7 filtering, threat intelligence, and FQDN rules.

**A7. What is an Application Security Group (ASG)?**
**Answer:** `azurerm_application_security_group` — a logical grouping used as a source/destination in NSG rules (e.g. "all web servers"), avoiding IP maintenance.

**A8. How do you associate an NSG to a subnet?**
**Answer:** `azurerm_subnet_network_security_group_association` (or the NIC-level `azurerm_network_interface_security_group_association`).

**A9. How do you use an ASG in a rule?**
**Answer:** `source_application_security_group_ids = [azurerm_application_security_group.web.id]` as the source.

**A10. What is `azurerm_network_security_rule` (separate resource)?**
**Answer:** A dedicated rule resource — cleaner for rules managed independently of the NSG (e.g. added by different modules).

**A11. What is a deny rule used for?**
**Answer:** Explicitly blocking traffic (e.g. a specific bad IP or port) — NSGs support deny, unlike AWS security groups.

**A12. What is NSG flow logging?**
**Answer:** `azurerm_network_watcher_flow_log` (or NSG flow logs) — sends accepted/denied flow records to a storage account for analysis.

**A13. What are service tags in rules?**
**Answer:** Named prefixes like `Internet`, `AzureLoadBalancer`, `Storage`, `VirtualNetwork` representing service address ranges, avoiding hard-coded IPs.

**A14. What is the `priority` requirement for user rules?**
**Answer:** 100–4096; lower numbers are processed first, so use ranges (e.g. 100-block for allow, 4000-block for deny-all).

**A15. How do you output an NSG ID for other resources?**
**Answer:** `output "nsg_id" { value = azurerm_network_security_group.nsg.id }`.

## Case B — Advanced / Senior

**B1. How do you design a defense-in-depth NSG model?**
**Answer:** Layer subnet NSGs (perimeter) with NIC NSGs (host) and Azure Firewall (edge): subnet rules allow broad internal flows, NIC rules tighten per-role, and the firewall handles L7/threat filtering.

**B2. How do you build a least-privilege web-db NSG setup?**
**Answer:** Web subnet: allow 80/443 from Internet, deny all else inbound. DB subnet: allow 1433/3306/5432 only from the web subnet (or web ASG), deny Internet. Outbound rules default-allow but tighten where needed.

**B3. Why use ASGs instead of IP addresses in rules?**
**Answer:** IPs change as VMs scale; ASG references stay correct automatically and express intent ("web tier") rather than fragile IP lists.

**B4. What is the difference between subnet-level and NIC-level NSGs, and when to use both?**
**Answer:** Subnet NSG protects all traffic entering/leaving the subnet; NIC NSG adds per-VM control. Use both for layered security (subnet baseline + host-specific rules).

**B5. How do you manage a shared set of rules across many NSGs?**
**Answer:** A module emitting consistent rule sets (or `azurerm_network_security_rule` resources) so every NSG inherits the org's baseline — and a policy-as-code check for forbidden rules (e.g. open RDP).

**B6. What are the pitfalls of very low-priority deny rules?**
**Answer:** A low-priority (e.g. 100) deny can block intended traffic if it's too broad — test rules in order and document the priority scheme.

**B7. How do you troubleshoot "NSG blocks traffic but Terraform doesn't show a diff"?**
**Answer:** Check rules added outside Terraform (portal/another tool) — run `terraform plan -refresh-only` to adopt drift, and audit with NSG flow logs to see which rule denies the traffic.

**B8. How do you enforce "no RDP/SSH from internet" across the estate?**
**Answer:** Policy-as-code scanning plans for rules with `Internet` source on 3389/22, plus Azure Policy to audit/deny such NSG rules at the platform level.

**B9. How does Azure Firewall differ from NSG in Terraform code?**
**Answer:** Azure Firewall uses `azurerm_firewall` + `ip_configuration` + network/application rule collections; NSGs use security rules. The firewall sits in a hub and handles cross-VNet + L7, while NSGs stay distributed.

**B10. What is the relationship between NSG rules and service tags for PaaS?**
**Answer:** Service tags like `Storage.<region>` let rules target a service's ranges without static IPs; combined with service endpoints/private endpoints you can lock access tightly.

**B11. How do you associate an NSG created in a shared module to a subnet in another module?**
**Answer:** Output the NSG ID from the security module and pass it as an input to the network module, which creates the `azurerm_subnet_network_security_group_association`.

**B12. How do you handle rule churn and ordering with `for_each`?**
**Answer:** Define rules as a map with explicit priorities and iterate `for_each` — stable keys prevent reordering, and priorities are part of the data so ordering is explicit.

## Case C — Scenario

**C1. Your database is reachable from the internet; how did it happen and how do you fix it?**
**Answer:** A rule allowed `Internet` (or `0.0.0.0/0`) on the DB port. Remove/replace it with a rule allowing only the app subnet/ASG, add a deny rule as a guard, and enable a policy check to prevent recurrence.

**C2. You need to block one abusive IP at the network edge quickly.**
**Answer:** Add a low-priority deny rule (e.g. 100) for that IP on the relevant NSGs (subnet/NIC), since NSGs can deny. Remove it once the threat passes.

**C3. VMs in an ASG can't reach a service that allows "web ASG" after a scale event.**
**Answer:** Confirm the new VMs' NICs are joined to the ASG (`azurerm_network_interface_application_security_group_association`) — if the association is missing for new instances, add it via Terraform so scaling keeps them covered.

**C4. A compliance scan flags several open management ports.**
**Answer:** Close RDP/SSH from `Internet`, route admin access through Azure Bastion/JIT, and add a policy-as-code rule (and Azure Policy) that denies management ports from the internet going forward.

**C5. Traffic between two subnets is unexpectedly blocked after a Terraform change.**
**Answer:** Review the newly applied rules and priorities — a new low-priority deny likely shadows an allow. Fix priorities (allow before deny) and add a regression check on the rule set.

**C6. You're migrating from per-resource inline rules to a centralized NSG module.**
**Answer:** Extract rules into the module's map input, apply `azurerm_network_security_rule`/module output to existing NSGs (or import them), and verify plans show no net change before removing the inline blocks.
