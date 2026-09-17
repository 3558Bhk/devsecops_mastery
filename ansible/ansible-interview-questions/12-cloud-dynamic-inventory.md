# 12 — Cloud & Dynamic Inventory (🟢 5 · 🟡 7 · 🔴 6)

> Course ref: [12-cloud-dynamic-inventory.md](../ansible-mastery/12-cloud-dynamic-inventory.md)

## 🟢 Basic

**Q1. What is dynamic inventory?**
> A: An inventory **plugin** (or script) that queries a source of truth — AWS/Azure/GCP/vCenter/CMDB — at run time, generating hosts/groups automatically so the fleet is never stale.

**Q2. Name two cloud inventory plugins.**
> A: `amazon.aws.aws_ec2` and `azure.azcollection.azure_rm` (also `google.cloud.gcp_compute`, `community.vmware.vmware_vm_inventory`, NetBox…).

**Q3. What does `keyed_groups` do in an inventory plugin?**
> A: Auto-creates groups from host attributes — e.g., `key: tags.Role prefix: role` → hosts tagged `Role:web` join group `role_web`.

**Q4. What is the `add_host` pattern?**
> A: A provision play creates an instance, then `add_host` injects it into an in-memory run-only group; the next play targets that group to configure the brand-new host — same-run provisioning.

**Q5. What are Terraform and Ansible each best at?**
> A: Terraform: provisioning/lifecycle with state, plan/apply, destroy. Ansible: configuring and orchestrating what's inside. Terraform owns birth→death; Ansible owns everything after birth.

## 🟡 Intermediate

**Q6. Write the shape of an aws_ec2 inventory config from memory (key directives).**
> A: `plugin: amazon.aws.aws_ec2`, `regions`, `filters` (e.g., `instance-state-name: running`, `tag:ManagedBy: ansible`), `keyed_groups`, `compose` (`ansible_host: private_ip_address`), `hostnames`, and `cache:` settings.

**Q7. `wait: true` on ec2_instance still fails the configure play — why?**
> A: "Running" ≠ SSH-ready ≠ cloud-init done. Add `wait_for` port 22 and/or `wait_for_connection` before the configuration play targets the new host.

**Q8. How does auth work for dynamic inventory in CI?**
> A: Standard provider chains — instance profile/role on the runner (preferred), OIDC federation, or scoped env credentials; never long-lived static keys in inventory configs.

**Q9. Why cache dynamic inventory, and what are the knobs?**
> A: API cost/latency (thousands of describe calls per run); knobs: `cache: true`, `cache_plugin`, `cache_connection`, `cache_timeout`; `--flush-cache` for critical runs.

**Q10. How do Ansible and Terraform share state?**
> A: Terraform outputs (IPs, IDs) become an inventory source (script/plugin reading `terraform output -json`), so Ansible configures exactly what Terraform created — one source of truth, no drift between tools.

**Q11. A playbook run started; 5 instances launched during it. Does it see them?**
> A: No — inventory is snapshotted at run start. They appear next run (subject to cache TTL). Same-run needs `add_host`.

**Q12. What cloud modules would you use for DNS, firewall, and object fetch?**
> A: `community.aws.route53`, `amazon.aws.ec2_security_group` (declarative rule lists), `amazon.aws.s3_object` (`mode: get`) — all idempotent against provider APIs.

## 🔴 Advanced

**Q13. Design inventory for a hybrid estate (AWS + bare metal + edge).**
> A: Multiple `-i` sources: aws_ec2 plugins per account/region (tag-keyed groups, cached), static YAML for bare metal, edge sites pull via regional runners; normalized groups via `composed` vars; CMDB plugin adds ownership metadata; governance = tagging standards enforced upstream because inventory quality is a tagging problem.

**Q14. Your dynamic inventory cached a terminated instance and the playbook "succeeded" against a recycled IP. Prevent this class of incident?**
> A: Layered: filter `instance-state-name: running`, short cache TTL + `--flush-cache` pre-run for critical jobs, pre-task connectivity + identity assertion (compare expected host key/fact vs inventory), and prefer stable identifiers (instance-id/Private DNS) over mutable names in `hostnames`.

**Q15. Terraform-owned infra: where exactly is the boundary, and what happens if Ansible creates instances anyway?**
> A: Boundary: Terraform owns creation/modification/deletion and state; Ansible mutates only inside the OS/app. If Ansible creates infra, Terraform plan shows eternal drift (or import gymnastics) — one owner per resource, decided explicitly per resource type.

**Q16. How would you auto-provision a full environment (VPC→instances→DNS→config) with both tools?**
> A: Terraform: network + compute + DNS zones (stateful lifecycle). Outputs → dynamic inventory → Ansible playbook configures OS/services → smoke-test play → record. Pipeline: `terraform plan/apply` (reviewed) → `ansible-playbook --check --diff` → apply. Two tools, one pipeline, explicit ownership per layer.

**Q17. What are the idempotency semantics of cloud modules, and where do they break?**
> A: They diff desired vs current via provider API (`state: present`, `exact_count`). Break where names aren't unique/stable (random-suffixed names recreate on re-run), where tags are the only identity, or when two tools fight over the same field — pin identities, one owner per field.

**Q18. Cost-control question: inventory refresh hits the API 5,000 times per run. Optimize.**
> A: Enable plugin cache with tuned TTL shared on the runner; scope `regions`/`filters`/`exclude_filters` to what plays actually target; schedule inventory-heavy jobs; cache-friendly runner placement (fewer, central runners for inventory, mesh for execution).
