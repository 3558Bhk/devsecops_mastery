# AWS AMI (Amazon Machine Image) — Interview Questions

> **Cloud:** AWS · **Category:** Compute · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

AMIs are represented in JSON through EC2 launch/block-device mapping (`AWS::EC2::Instance`, `AWS::EC2::LaunchTemplate`) and EC2 Image Builder pipelines (`AWS::ImageBuilder::ImagePipeline`).

```json
{
  "Type": "AWS::EC2::Instance",
  "Properties": {
    "ImageId": "ami-0abc123",
    "InstanceType": "t3.medium",
    "BlockDeviceMappings": [{
      "DeviceName": "/dev/xvda",
      "Ebs": { "VolumeSize": 30, "VolumeType": "gp3", "DeleteOnTermination": true }
    }],
    "UserData": { "Fn::Base64": "#!/bin/bash ..." }
  }
}
```

**Key fields:** `ImageId` (the AMI) · `BlockDeviceMappings` (`Ebs` size/type/`DeleteOnTermination`) · `UserData` (base64 bootstrap script). An AMI itself = snapshot + block device mapping + launch permissions.


## Case A — Basic

**A1. What is an AMI?**
**Answer:** An Amazon Machine Image is a template that contains the operating system, application server, and application configuration needed to launch an EC2 instance. It's the blueprint every instance starts from.

**A2. What are the components of an AMI?**
**Answer:** (1) Root volume template (EBS snapshot or instance-store), (2) launch permissions (who can use it), and (3) a block device mapping (volumes to attach on launch).

**A3. What are the sources of AMIs?**
**Answer:** AWS-provided (Amazon Linux, Windows, Ubuntu), AWS Marketplace (vendor software), community AMIs, and your own **custom AMIs** created from configured instances.

**A4. How do you create a custom AMI?**
**Answer:** Launch an instance, install/configure software, then **Create Image** (console/CLI) — AWS snapshots the volume and registers it as an AMI. The instance should be stopped (or you risk filesystem inconsistency) for a clean image.

**A5. What is the difference between an EBS-backed and instance store-backed AMI?**
**Answer:** EBS-backed: root volume is an EBS snapshot — can stop/start, persists independently. Instance store-backed: root is ephemeral instance storage — can't stop (only terminate), lost on termination, and the AMI is stored in S3 (via a bundle/upload process).

**A6. Are AMIs regional?**
**Answer:** Yes — an AMI exists in one region. To use it in another region you **copy** it (which creates a new AMI ID in that region).

**A7. How do you share an AMI with another account?**
**Answer:** Modify the AMI's **launch permissions** to add the other account ID (private sharing), or make it public/Marketplace. For encrypted AMIs, also share the underlying **KMS key** and snapshot.

**A8. What is the difference between stopping an instance and terminating it (re: AMIs and volumes)?**
**Answer:** **Stop**: instance is stopped, EBS root volume and data persist (you can restart or image it). **Terminate**: instance and (by default) the root volume are deleted; additional volumes persist if not set to delete-on-termination.

**A9. What is "launch permission" on an AMI?**
**Answer:** The setting controlling who can launch instances from the AMI: private (your account), shared (specific accounts/orgs), or public.

**A10. Can you change an existing AMI?**
**Answer:** No — AMIs are immutable. You make changes by launching an instance, modifying it, and creating a **new AMI** (and a new version/deprecation of the old).

**A11. What is the AMI ID format?**
**Answer:** `ami-` followed by a 17-character hex identifier, e.g., `ami-0abcdef1234567890`.

**A12. What is EC2 Image Builder?**
**Answer:** An AWS service that automates building, testing, and distributing AMIs (and container images) via a pipeline — the recommended way to create and maintain golden images.

**A13. What is a "golden AMI"?**
**Answer:** A pre-hardened, pre-configured, security-baselined AMI (patched, agents installed, CIS-compliant) that teams use as the approved base for all instances — faster, consistent, and compliant launches.

**A14. What happens to an AMI's root snapshot if you deregister the AMI?**
**Answer:** The AMI is removed (can no longer launch from it), but the underlying **snapshot is NOT automatically deleted** — you must delete snapshots separately to avoid storage costs.

**A15. What is instance user data, and how does it relate to AMIs?**
**Answer:** User data is a script/config passed at launch (runs on first boot) to customize an instance. It lets a single base AMI produce differently-configured instances (bootstrap pattern) — AMI = static base, user data = dynamic config.

---

## Case B — Advanced (Senior)

**B1. Explain the AMI creation process under the hood and why you should stop the instance first.**
**Answer:** Creating an image snapshots the EBS root volume and registers the snapshot + block device mappings + launch permissions as an AMI. A running instance may have in-flight writes; **stopping** (or reboot with a quiesced filesystem) ensures a consistent snapshot. Best practice: stop → create image → restart, or use EC2 Image Builder which handles this.

**B2. EBS-backed vs instance store-backed AMIs: performance, persistence, and use cases.**
**Answer:** EBS-backed = persistent, stoppable, easy to snapshot/copy — default choice. Instance store-backed = faster local I/O and lower cost but ephemeral and requires S3 bundling (legacy); used rarely today for specialized high-IO scratch workloads. Almost all production systems standardize on EBS-backed.

**B3. How do you share an encrypted AMI across accounts, and what are the exact steps?**
**Answer:** (1) Share the **snapshot** with the target account. (2) Share the **KMS key** (modify key policy to grant target account `kms:DescribeKey`, `kms:CreateGrant`, `kms:Decrypt`, `kms:ReEncrypt*`, `kms:GenerateDataKey*`). (3) In the target account, **copy** the shared snapshot (re-encrypt with their own KMS key) and register a new AMI from it. You cannot launch directly from a shared encrypted AMI without a copy.

**B4. Design a golden-image pipeline with EC2 Image Builder.**
**Answer:** Define a **recipe** (base image + components: install/patch/harden/test steps), a **pipeline** (schedule + tests), and a **distribution** (share to accounts/regions). Image Builder runs the pipeline, runs tests, and distributes versioned AMIs — integrating with the org's patching (e.g., latest Amazon Linux base, SSM agent, security agents) and tagging for compliance.

**B5. How do you keep AMIs patched and consistent across many accounts and regions?**
**Answer:** Centralize: Image Builder (or a CI pipeline) builds monthly golden AMIs from the latest patched base, tags them (`os`, `version`, `build-date`), and distributes via **AWS RAM sharing** or copy across regions/accounts. Enforce with SCPs/Config that instances must launch from approved AMIs; use SSM Patch Manager for in-place patching between rebuilds.

**B6. What is AMI deprecation and why is it important?**
**Answer:** Marking old AMIs deprecated (via console/API `EnableImageDeprecation`) signals they should no longer be used while remaining launchable for a grace period. It prevents teams from launching stale, vulnerable images and supports lifecycle governance.

**B7. How does an AMI's block device mapping work, and how do you customize volumes on launch?**
**Answer:** The AMI defines the root volume (type/size/snapshot) and additional volumes. On launch you can **override** sizes, types, encryption, and delete-on-termination flags per device. This lets one AMI produce instances with different storage footprints.

**B8. Compare baking (pre-configured AMI) vs frying (bootstrap via user data/SSM) — and the hybrid.**
**Answer:** **Baking** = put everything in the AMI (fast launches, immutable, but stale if not rebuilt). **Frying** = base AMI + user data/Config at launch (always fresh config, but slower boot and more moving parts). **Hybrid** = golden AMI with OS/agents/base + user data for app config — the industry best practice.

**B9. What consistency/perf issues arise when an AMI snapshot is shared across regions (cold start)?**
**Answer:** EBS volumes restored from snapshots are **lazily loaded**, causing first-access latency for warm workloads. Mitigate with EBS **Fast Snapshot Restore** for critical AMIs in the AZs where you scale, or pre-warm volumes after launch.

**B10. How do you automate AMI lifecycle: build → test → distribute → deprecate → delete?**
**Answer:** Use a CI/CD pipeline (Image Builder or CodePipeline + Packer) with tests (SSM/Inspector scans, boot checks), distribution via RAM/copies, tagging for inventory, **deprecation** after N months, and snapshot cleanup scripts (deregister + delete snapshots). Log all steps in CloudTrail for audit.

**B11. How do Packer vs EC2 Image Builder compare?**
**Answer:** Packer (HashiCorp) = open-source, multi-cloud, code-defined images, great in existing Terraform pipelines. EC2 Image Builder = native AWS, GUI/YAML, built-in tests, distribution & sharing, integrated with AWS accounts. Choose by team stack and whether you need multi-cloud.

**B12. What are the security checks you run before promoting an AMI to production?**
**Answer:** Scan with **Amazon Inspector** (vulnerabilities), verify CIS/baseline hardening (SSM/Config), confirm no secrets baked in (scan for keys/tokens), check AMI is encrypted with the right KMS key, restrict launch permissions (private/shared only), and ensure the AMI is from an approved base. Only then publish as golden.

---

## Case C — Scenario

**C1. Scenario:** Auto Scaling launches are too slow (5+ min) because instances install everything at boot, and a config error once took the whole fleet down.
**Question:** Recommend an image strategy.
**Expected answer:** Bake a **golden AMI** with the OS, runtime, agents, and application version (via Image Builder/Packer in CI). Keep only light boot-time config in user data (env-specific values via SSM Parameter Store/Secrets Manager). This cuts launch time dramatically and removes boot-time failure modes — rebuild the AMI per app release.

**C2. Scenario:** Compliance requires every instance to launch from an approved, encrypted AMI in your account.
**Question:** How do you enforce and verify?
**Expected answer:** Enforce with an **SCP** (deny `ec2:RunInstances` unless `ec2:ImageId` is in an allowed list / tag condition) and AWS Config rule (`ec2-managedinstance...` / custom rule checking the AMI). Verify via CloudTrail + Config: no instance launched from an unapproved AMI; AMIs encrypted with the standard KMS key; Image Builder distributes the approved set.

**C3. Scenario:** A teammate deregistered an AMI and now an ASG fails to launch new instances ("AMI not found").
**Question:** Explain and fix, plus how to prevent recurrence.
**Expected answer:** Deregistered AMIs can't launch instances, so the ASG's launch template is broken. Fix: update the launch template to the current golden AMI (or restore/re-register if you still have the snapshot). Prevent: use AMI **deprecation instead of deregistration**, automate launch-template AMI updates to always point at the latest image, and alert when a launch template references a deregistered AMI (Config custom rule).

**C4. Scenario:** You must give AMIs to a subsidiary in another AWS account, but they must not see the KMS key or be able to share further.
**Question:** Design the sharing.
**Expected answer:** Share the **snapshot + KMS key** with the subsidiary account (grant them minimal KMS usage permissions via the key policy), let them **copy** the snapshot (optionally re-encrypting with their own key), and register their own AMI. Sharing the AMI directly with launch permissions for an **encrypted** image requires the same key sharing; ensure they cannot modify launch permissions of your source AMI (they only get their own copy).

**C5. Scenario:** Instances launched from a shared AMI are slow on first boot (database warm-up) during a scale-out.
**Question:** Diagnose and fix.
**Expected answer:** The EBS volume is lazily loading blocks from S3 (snapshot restore). Fix: enable **Fast Snapshot Restore (FSR)** on the AMI's snapshot for the AZs where you scale, or pre-warm volumes post-launch, or keep a warm pool of instances. This is a classic cold-start issue.

**C6. Scenario:** A security scan found SSH private keys and AWS access keys baked inside a published AMI.
**Question:** What's the incident response and long-term fix?
**Expected answer:** Immediate: **deregister the compromised AMI**, rotate any exposed keys/credentials, revoke share permissions, and identify/terminate instances launched from it. Long-term: add secret-scanning to the image pipeline (before publish), build from hardened bases, never bake credentials (use instance roles + Secrets Manager), and run Inspector/secret scanners as a required CI gate.
