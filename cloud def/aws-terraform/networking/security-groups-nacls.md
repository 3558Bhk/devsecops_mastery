# Terraform Security Groups & NACLs (AWS) — Interview Questions

> **Cloud:** AWS · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~6 min

---

## Case A — Basic

**A1. What is an `aws_security_group`?**
**Answer:** A stateful virtual firewall at the instance/ENI level. It allows traffic via ingress/egress rules; allowed return traffic is automatic (stateful).

**A2. What is the difference between SG and NACL?**
**Answer:** SGs are stateful, operate at the instance level, and support allow rules only. NACLs are stateless, operate at the subnet level, and support both allow and deny rules with rule numbers.

**A3. How do you declare a security group rule in Terraform?**
**Answer:** Either inline `ingress`/`egress` blocks in the SG resource, or separate `aws_security_group_rule` resources referencing the SG — the latter is preferred for managing rules independently.

**A4. What fields does an ingress rule have?**
**Answer:** `from_port`, `to_port`, `protocol`, `cidr_blocks`/`ipv6_cidr_blocks`, `security_groups`, `self`, and `description`.

**A5. What does `self = true` do?**
**Answer:** It allows traffic from the SG's own members (same SG) — e.g. all instances in the "web" SG can talk to each other on a port.

**A6. How do you reference another security group as a source?**
**Answer:** In the `security_groups` list of the rule, e.g. `security_groups = [aws_security_group.db.id]`.

**A7. What is the default security group of a VPC?**
**Answer:** The one AWS creates with the VPC, which allows all outbound and only same-SG inbound. Manage it with `aws_default_security_group`.

**A8. What is an `aws_network_acl`?**
**Answer:** A stateless subnet firewall with numbered allow/deny rules evaluated in order. Attach to subnets with `aws_network_acl_association`.

**A9. What is an ephemeral port range and why do NACLs need it?**
**Answer:** Return traffic uses high ports (1024–65535). Because NACLs are stateless, you must open the return range explicitly in both directions.

**A10. What is `aws_security_group_rule` preferred over inline rules?**
**Answer:** Separate rule resources let you add/remove rules without recreating the SG, and support `for_each`/modules more cleanly. Inline rules can cause churn.

**A11. Can a security group deny traffic?**
**Answer:** No — SGs only allow. To deny, remove the allow or use a NACL (or a firewall service like AWS Network Firewall).

**A12. What does `cidr_blocks` vs `prefix_list_ids` mean?**
**Answer:** `cidr_blocks` are IP ranges; `prefix_list_ids` reference managed prefix lists (e.g. the S3/VPC endpoints or a shared list of office ranges).

**A13. How many rules can a security group have?**
**Answer:** Default quota of 60 inbound and 60 outbound rules per SG (including separate-SG rules). Plan aggregations to stay under limits.

**A14. What is `protocol = "-1"`?**
**Answer:** All protocols (any IP protocol), used for "allow everything" rules — avoid in production.

**A15. What does `aws_vpc_security_group_ingress_rule` (the newer resource) do?**
**Answer:** A dedicated resource for ingress rules in the newer API model, separating rules from the SG resource entirely — cleaner for dynamic rule sets.

## Case B — Advanced / Senior

**B1. How do stateful vs stateless firewalls change rule design?**
**Answer:** Stateful SGs need only the initiating direction. Stateless NACLs need both directions plus ephemeral return ports, doubling the rules and increasing misconfiguration risk.

**B2. How do you build a "least privilege" web-app-db SG chain?**
**Answer:** Web SG allows 80/443 from 0.0.0.0/0; app SG allows only from web SG on app port; db SG allows only from app SG on 3306/5432. Everything else is denied by default. Reference SGs, not IPs, so scaling works.

**B3. Why reference a security group by ID instead of its CIDR?**
**Answer:** IPs change as instances scale; SG references keep the rule correct automatically and restrict to that SG's members regardless of IP.

**B4. How do you avoid circular SG dependencies in Terraform?**
**Answer:** Two SGs referencing each other can be expressed with separate `aws_security_group_rule` resources so each SG resource itself has no cycle, only the rules reference each other.

**B5. How do you manage a shared set of rules across many SGs?**
**Answer:** Use managed prefix lists (`aws_ec2_managed_prefix_list`) referenced in `prefix_list_ids`, or a module that emits consistent rule sets — updating the list updates all consumers.

**B6. What is the order of evaluation for NACL rules?**
**Answer:** Lowest rule number first, and the first match (allow or deny) wins. Keep a high-numbered catch-all deny.

**B7. When would you use both SG and NACL?**
**Answer:** Defense-in-depth: SG for instance-level allow rules, NACL for subnet-level deny rules (blocking specific bad IPs) and explicit stateless control at the boundary.

**B8. What is the default NACL and why change it carefully?**
**Answer:** The default NACL allows all traffic; modifying it affects all subnets using it. Manage with `aws_default_network_acl` or create explicit NACLs and associate them.

**B9. How do you enforce "no 0.0.0.0/0 on SSH/RDP" across a codebase?**
**Answer:** Policy-as-code (OPA/tfsec/checkov) scanning plan/config for rules with open admin ports, failing CI on violations, plus code review.

**B10. What's the risk of inline `ingress` blocks when adding a rule?**
**Answer:** Terraform reconciles the whole block set, so external edits or reordering can force SG recreation (brief connectivity loss). Separate rule resources are additive and safer.

**B11. How do IPv6 rules differ in Terraform?**
**Answer:** Use `ipv6_cidr_blocks` on the rule and ensure the VPC has an IPv6 CIDR. Egress-only internet gateways cover outbound IPv6.

**B12. How do you troubleshoot "plan shows SG changed every run"?**
**Answer:** Check for drift (someone edited in console), inconsistent `description`/`protocol` casing, or rules managed by both inline blocks and `aws_security_group_rule`. Adopt with `-refresh-only` and centralize rule management.

## Case C — Scenario

**C1. An incident: your database was reachable from the internet. What went wrong and how do you prevent it?**
**Answer:** Likely a rule with `0.0.0.0/0` on the DB port or a mis-referenced SG. Remove the rule, change to SG-to-SG references, add a deny policy-as-code rule against open DB ports, and alert on such changes.

**C2. You need to temporarily block one abusive IP at the subnet level.**
**Answer:** Add a NACL rule with a low rule number (e.g. 100) denying that IP for the relevant ports on the subnets, since SGs can't deny. Remove it when the threat passes.

**C3. Instances in an ASG can't reach a service that allows "web SG" — the ASG replaced instances.**
**Answer:** Confirm the ASG's launch template attaches the correct SG, and that the service rule references that SG ID. If it referenced old instance IPs, switch to the SG reference so new instances are covered automatically.

**C4. A compliance scan flags too many SGs per instance and overlapping rules.**
**Answer:** Consolidate into a tiered SG model (web/app/db), move per-instance one-offs into rule sets by role, and document the standard. Then import/refactor Terraform to match and delete legacy SGs.

**C5. You're migrating from inline SG rules to `aws_security_group_rule` without downtime.**
**Answer:** Create the separate rule resources (matching current rules) first, then remove the inline blocks in the same apply — Terraform sees no net change. Verify the plan shows only in-place updates, not SG replacement.

**C6. A shared prefix list update unexpectedly opened your app to new IPs.**
**Answer:** Prefix lists are shared; changing one affects all consumers. Scope the list narrowly, version/approve changes, and add an alert/policy check on SG rules that reference prefix lists to catch broad access.
