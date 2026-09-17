# Terraform EC2 & Auto Scaling (AWS) — Interview Questions

> **Cloud:** AWS · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~6 min

---

## Case A — Basic

**A1. What is `aws_instance`?**
**Answer:** An EC2 virtual machine resource: `resource "aws_instance" "web" { ami = ... ; instance_type = "t3.micro" ; subnet_id = ... }`.

**A2. How do you pick the AMI dynamically?**
**Answer:** With a data source: `data "aws_ami" "ubuntu" { most_recent = true ; owners = ["099720109477"] ; filter { ... } }`.

**A3. What is user data?**
**Answer:** A script run on first boot (`user_data = ...`), often passed via `templatefile()` for bootstrap configuration.

**A4. What is a key pair in Terraform?**
**Answer:** `aws_key_pair` registers an SSH public key for instance access. For AWS-created pairs you'd need to output the private key (rarely recommended).

**A5. How do you attach a security group and IAM role to an instance?**
**Answer:** `vpc_security_group_ids = [...]` and `iam_instance_profile = aws_iam_instance_profile.app.name`.

**A6. What is an Elastic IP?**
**Answer:** `aws_eip` — a static public IPv4 you can associate with an instance or NAT gateway via `aws_eip_association`.

**A7. What is an `aws_ami` (or `aws_ami_from_instance`) resource?**
**Answer:** It creates a custom AMI from config or an existing instance, for golden images or launch templates.

**A8. What is a launch template?**
**Answer:** `aws_launch_template` defines instance settings (AMI, type, SG, user data) reused by ASGs and Spot Fleet requests.

**A9. What is an Auto Scaling Group (ASG)?**
**Answer:** `aws_autoscaling_group` maintains a desired count of instances across AZs, scaling in/out on policies, using a launch template.

**A10. What are the key ASG arguments?**
**Answer:** `min_size`, `max_size`, `desired_capacity`, `vpc_zone_identifier` (subnets), `launch_template`, `target_group_arns`, and `health_check_type`.

**A11. What is an ASG scaling policy?**
**Answer:** `aws_autoscaling_policy` (target tracking, step, or simple) adjusts capacity based on metrics like CPU.

**A12. What is `aws_autoscaling_attachment`?**
**Answer:** Attaches instances (or an ELB) to an ASG manually when not using target group registration via `target_group_arns`.

**A13. What is instance metadata and how is it accessed?**
**Answer:** Instance data (AMI, hostname, IAM creds) at 169.254.169.254, used by user data scripts and the AWS CLI on the box.

**A14. What does `associate_public_ip_address` do?**
**Answer:** Assigns a public IP on launch (in a subnet with `map_public_ip_on_launch` or explicitly).

**A15. What is a spot instance request in Terraform?**
**Answer:** `aws_spot_instance_request` — request spare capacity at a discount with the risk of interruption.

## Case B — Advanced / Senior

**B1. How do you do zero-downtime rolling deploys with an ASG?**
**Answer:** Update the launch template (new AMI/config), then trigger an instance refresh or a blue-green ASG swap so new instances come up healthy behind the LB before old ones are terminated.

**B2. What is the difference between `aws_launch_configuration` and `aws_launch_template`?**
**Answer:** Launch configurations are legacy and being phased out; launch templates are versioned, support more features (T2/T3 unlimited, mixed instances), and are required for newer ASG features. Use launch templates.

**B3. How does instance refresh work and how do you trigger it from Terraform?**
**Answer:** It replaces instances gradually to pick up a new launch template version. In Terraform, update the template version referenced by the ASG (a new `version` triggers refresh if `instance_refresh` is configured or via `aws_autoscaling_group` `instance_refresh` block).

**B4. Why does changing `desired_capacity` in Terraform get overridden?**
**Answer:** ASG policies scale capacity at runtime, so Terraform's `desired_capacity` drifts. Set `ignore_changes = [desired_capacity]` and let policies own it, or accept one-time set on creation.

**B5. How do you pass changing user data without replacing instances?**
**Answer:** User data changes still require instance refresh/replacement to take effect. Use `templatefile` with a versioned variable, then trigger an instance refresh — Terraform alone won't re-run user_data on existing instances.

**B6. What is `create_before_destroy` and `lifecycle` for instances?**
**Answer:** `create_before_destroy` provisions the replacement first (needed when names/identifiers must not collide), and `ignore_changes` suppresses diffs for fields owned elsewhere (e.g. AMI patched by automation).

**B7. How do you make a golden AMI pipeline with Terraform?**
**Answer:** Use Packer (or `aws_ami_from_instance`) to bake the image, publish the AMI ID (SSM Parameter Store or a data source lookup), and have the ASG reference the latest ID via `data "aws_ami"`/`aws_ssm_parameter`.

**B8. How do you configure an ASG across multiple AZs correctly?**
**Answer:** Pass subnets from ≥2 AZs in `vpc_zone_identifier`, and the ASG balances capacity; combine with target tracking policies for HA under load.

**B9. What is a mixed instances ASG and why use it?**
**Answer:** `mixed_instances_policy` blends on-demand and spot (and multiple instance types) to cut cost while keeping a guaranteed baseline.

**B10. How do you attach an ASG to an ALB target group?**
**Answer:** Set `target_group_arns` on the ASG so instances auto-register on launch and drain on termination — no manual `aws_lb_target_group_attachment` per instance.

**B11. What is `health_check_grace_period` and `default_cooldown`?**
**Answer:** Grace period gives new instances time to become healthy before scaling decisions; cooldown pauses scaling after an activity to avoid thrashing.

**B12. How do you find an instance's private IP to feed other resources?**
**Answer:** Reference `aws_instance.web.private_ip` directly for single instances; for ASG members, use the LB/target group or `data "aws_instances"` to discover them.

## Case C — Scenario

**C1. Instances keep being replaced because the AMI data source picks a newer image each run.**
**Answer:** Pin the AMI (exact ID or versioned filter) so plans are stable; only bump deliberately. Use `ignore_changes` on `ami` if a patching process owns updates, and refresh via instance refresh, not random replacement.

**C2. Your ASG scaled down and took a production node with it mid-request.**
**Answer:** Enable target group deregistration delay (draining) so in-flight requests finish before termination, set appropriate cooldowns, and use lifecycle hooks (`aws_autoscaling_lifecycle_hook`) to run cleanup before instance termination.

**C3. You need to run a one-time task on launch, then have the instance stay healthy.**
**Answer:** Use user_data (or cloud-init) for bootstrapping plus a proper health check in the target group; don't put long tasks in user_data that delay readiness. For heavy setup, use a baked AMI + SSM.

**C4. The ASG's `desired_capacity` keeps showing a diff in every plan.**
**Answer:** Add `ignore_changes = [desired_capacity]` to the ASG (or `min_size`/`max_size` if policies change them), since runtime scaling intentionally diverges from the declared value.

**C5. You must cut EC2 costs by using spot, but keep critical workers on-demand.**
**Answer:** Use a mixed instances policy: on-demand base capacity for the critical floor, spot percentage for the rest, with multiple instance types for spot diversity.

**C6. A launch template change rolled out, but some instances are still on the old AMI.**
**Answer:** The template update alone doesn't replace running instances. Trigger an instance refresh (or a new template version + refresh) with a minimum healthy percentage to roll the fleet safely.
