# Azure Image Creation (VM Images) — Interview Questions

> **Cloud:** Azure · **Category:** Compute · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

Azure image building is **JSON-native**: an Azure VM Image Builder template (`Microsoft.VirtualMachineImages/imageTemplates`) defines source → customize → distribute.

```json
{
  "type": "Microsoft.VirtualMachineImages/imageTemplates",
  "apiVersion": "2022-07-01",
  "name": "goldenImage",
  "properties": {
    "source": { "type": "PlatformImage", "publisher": "Canonical", "offer": "0001-com-ubuntu-server-jammy", "sku": "22_04-lts-gen2" },
    "customize": [
      { "type": "Shell", "name": "installAgent", "inline": ["curl -sL https://example.com/agent.sh | bash"] }
    ],
    "distribute": [{
      "type": "SharedImage",
      "galleryImageId": "/subscriptions/<sub>/resourceGroups/rg/providers/Microsoft.Compute/galleries/g/images/web/versions/1.0.0",
      "runOutputName": "web",
      "artifactTags": { "source": "CI" },
      "replicationRegions": ["eastus", "westeurope"]
    }]
  }
}
```

**Key fields:** `source` (PlatformImage / ManagedImage / SharedImageVersion) · `customize[]` steps (Shell, PowerShell, File, WindowsRestart) · `distribute[]` (`SharedImage` gallery id + `replicationRegions`, or `ManagedImage`). This is the JSON file format for image creation.


## Case A — Basic

**A1. What is an Azure VM image?**
**Answer:** A template that contains an OS, configuration, and optionally applications — used to create identical VMs. It can come from Azure Marketplace, the community, or be **custom-built** from your own VMs.

**A2. What is the difference between a Marketplace image and a custom image?**
**Answer:** Marketplace images = Microsoft/third-party maintained (e.g., Ubuntu, Windows Server). **Custom images** = created from **your** configured VM (generalized or specialized) for consistent, pre-configured deployments.

**A3. What is "generalize" (sysprep/waagent -deprovision)?**
**Answer:** Preparing a VM to be a reusable image by **removing machine-specific identity** (SIDs, hostname, SSH host keys, machine-specific state) — so new VMs from the image are unique.

**A4. What is the difference between a generalized and a specialized image?**
**Answer:** **Generalized** = machine identity removed (sysprep/deprovision) → can create **multiple** independent VMs. **Specialized** = retains identity (OS disk as-is) → used to create **one** VM that's a clone/backup of the original.

**A5. How do you capture an image from a VM?**
**Answer:** (1) Configure the VM, (2) **generalize** it (Linux: `waagent -deprovision`; Windows: `sysprep`), (3) **deallocate** the VM, (4) mark it **generalized**, then **capture** the image (portal/CLI/ARM). The VM is then unusable (it's been generalized).

**A6. What is Azure Compute Gallery (formerly Shared Image Gallery)?**
**Answer:** A service for storing, versioning, and **sharing VM images** (and VM apps) across subscriptions/regions/tenants — with image **versions**, **definitions**, and replication to regions.

**A7. What are the components of a Compute Gallery?**
**Answer:** **Gallery** (container), **image definition** (OS type, SKU, publisher, generation, etc.), and **image versions** (the actual image, replicated to target regions).

**A8. What is an image version?**
**Answer:** A specific, immutable version of an image (e.g., 1.0.0) in a Compute Gallery — enabling versioned, rollback-able deployments.

**A9. What is Azure VM Image Builder?**
**Answer:** A managed service (based on Packer) that automates building customized images — installing software/updates, then **distributing** the image to a Compute Gallery or managed image, as a pipeline.

**A10. What is the difference between a "managed image" and a "Compute Gallery image"?**
**Answer:** A **managed image** is a single, region-scoped image resource. A **Compute Gallery image** is versioned, replicable across regions, and shareable — the recommended approach for production golden images.

**A11. How do you share an image to another subscription/region?**
**Answer:** Via **Compute Gallery**: replicate the image version to target regions, and share the gallery with other subscriptions (RBAC/tenant). Managed images can be copied but not shared as cleanly.

**A12. What is "deprovision" on Linux?**
**Answer:** `waagent -deprovision` (or `-deprovision+user`) — removes the machine-specific provisioning state and (optionally) user data so the VM can be generalized into an image.

**A13. What is sysprep on Windows?**
**Answer:** The System Preparation tool that generalizes Windows (removes SID/computer-specific info) so the image can be deployed to multiple machines.

**A14. What happens to the source VM after capturing an image?**
**Answer:** The source VM is left in a **generalized** state (not bootable for normal use) — you should **delete** it and create new VMs from the image. (Specialized captures keep the source VM usable.)

**A15. What is a "golden image"?**
**Answer:** A pre-hardened, pre-configured, security-baselined image (patched, agents installed, compliant) that all teams use as the approved base for VM deployments.

---

## Case B — Advanced (Senior)

**B1. Walk through the full custom-image workflow for Linux and Windows, including the generalization commands.**
**Answer:** Configure the VM → **Linux**: `sudo waagent -deprovision+user`; **Windows**: run `sysprep /oobe /generalize /shutdown` → **deallocate** the VM → mark generalized (CLI/portal) → **capture** (managed image) or create an **image version** in a Compute Gallery → deploy VMs from the image. Skipping generalization produces a specialized (single-use) image.

**B2. What are the common pitfalls when generalizing/capturing images?**
**Answer:** (1) Capturing a **running** VM (snapshot inconsistency), (2) not deallocating before capture, (3) forgetting to **generalize** (results in a specialized image), (4) sysprep **failures** (app incompatibilities, sysprep limits), (5) losing the source VM (generalized → unusable), (6) missing **waagent/cloud-init** config for Linux, (7) licensing implications of custom images.

**B3. How does Azure Compute Gallery provide versioning and regional replication, and why does it matter?**
**Answer:** Each image is an **image definition** with multiple **versions** (1.0.0, 1.1.0). You **replicate** a version to target regions (Azure copies it), so VMs in any region deploy from a local copy (fast + consistent). Versioning enables controlled rollouts and instant rollback to a prior version.

**B4. How does Azure VM Image Builder work (pipeline: customize → validate → distribute), and how does it relate to Packer?**
**Answer:** Image Builder defines a **template** (source image + customization steps: scripts, PowerShell, file copies, reboots) → builds in Azure (using Packer under the hood) → validates → **distributes** to a Compute Gallery (optionally multiple regions) or managed image. It gives a managed, auditable golden-image pipeline without running Packer yourself.

**B5. How do you build a golden-image pipeline with Image Builder + Compute Gallery for an org?**
**Answer:** Define an Image Builder template from a patched base (e.g., latest Ubuntu/Windows), add components (security agents, runtimes, compliance config), schedule monthly rebuilds, **distribute as new versions** to a shared Compute Gallery (replicated to all regions), and have teams deploy only from approved definitions. Enforce with Azure Policy (VM must use approved image).

**B6. How do you share images securely across subscriptions/tenants via Compute Gallery?**
**Answer:** Grant **RBAC** on the gallery (or share to specific subscriptions/tenants). For cross-tenant, use gallery **sharing** (direct shared gallery or community gallery). Restrict who can create versions vs consume them; keep versions replicated to regions where consumers deploy.

**B7. What are the differences between Azure Disk Encryption/BitLocker and image-level concerns for custom images?**
**Answer:** Images aren't encrypted "as images," but VMs created from them use **managed disks** which can be encrypted (ADX/BitLocker or encryption-at-host). When building golden images, ensure the base + any baked secrets are handled (no credentials in the image), and rely on **managed disk encryption** at VM deployment rather than baking encryption keys into images.

**B8. How does Image Builder integrate with Azure DevOps/GitHub for CI/CD of images?**
**Answer:** Trigger Image Builder from a pipeline (Azure DevOps task / GitHub Action) on base-image updates or code changes; run **validation** (tests/security scans) before distribution; on success, publish a new **Compute Gallery version** and update VMSS/VM deployments (or ASG launch templates) to the new version. This gives fully automated, versioned image releases.

**B9. What are the security checks before promoting an image to production?**
**Answer:** **Defender for Cloud/VM vulnerability assessment** (or Microsoft Defender for Endpoint) scan, **CIS/baseline** compliance, verify **no secrets** baked in, confirm **generalization** done correctly, restrict the **Compute Gallery sharing** (least privilege), and require **approved image** via Azure Policy. Only promote after the scan gates pass.

**B10. How do you update VMs when a new image version is released (VMSS rolling, instance refresh)?**
**Answer:** For **VMSS**, update the scale-set model to the new image version and do a **rolling upgrade** (or manual instance refresh) with max-surge settings. For standalone VMs, redeploy from the new image (blue-green). Schedule via Image Builder + automation; use **Compute Gallery version aliases** (e.g., "latest") where appropriate (though pinning exact versions is safer).

**B11. What is the difference between a managed image, a snapshot, and a Compute Gallery image (use cases)?**
**Answer:** **Snapshot** = point-in-time copy of a disk (backup/clone one disk). **Managed image** = generalized VM template in one region (simple, single-region deploys). **Compute Gallery image** = versioned, replicated, shareable (enterprise golden-image management). Use gallery for anything production/shared; snapshots for point-in-time copies.

**B12. What are the licensing/compliance considerations with custom images (Windows, BYOL)?**
**Answer:** Windows custom images must be created from **licensed Azure Marketplace images** (or BYOL with Software Assurance/Hybrid Benefit) — you can't upload a non-Azure-licensed Windows VHD arbitrarily. Track image provenance, honor vendor licensing, and document the base image for compliance/audits.

---

## Case C — Scenario

**C1. Scenario:** Teams launch VMs and manually install agents/patches each time, causing drift and slow deploys.
**Question:** Fix with golden images.
**Answer:** Build a **golden image** via **Image Builder**: patched base + security agents + runtime + compliance config, published as a versioned **Compute Gallery image** replicated to all regions. Teams deploy from the approved definition (enforced by Azure Policy), eliminating per-VM manual setup and drift; rebuild monthly for patches.

**C2. Scenario:** A new image version broke an app in production; you must roll back immediately.
**Question:** How does Compute Gallery help?
**Answer:** Update the **VMSS/VM deployments** to point back to the **previous image version** (versions are immutable), and roll out. Since each version is stored, rollback is instant — just re-target the deployment to the known-good version. (Optionally use version aliases carefully; pinning exact versions makes rollback deterministic.)

**C3. Scenario:** You captured an image from a VM, but new VMs created from it have the **same hostname/SID** and conflict on the domain.
**Question:** What went wrong?
**Answer:** The VM was **not generalized** (sysprep/deprovision not run) — so the image is **specialized** and clones the original identity. Fix: create a fresh VM, run **sysprep** (Windows) or `waagent -deprovision+user` (Linux), deallocate, mark generalized, and re-capture. Then new VMs get unique identities.

**C4. Scenario:** You need the same image in 5 regions so VMs deploy fast and identically everywhere.
**Question:** Which feature?
**Answer:** **Compute Gallery with regional replication**: create the image version and **replicate it to all 5 target regions**. VMs in each region then use a local copy (fast, consistent). This beats manually copying managed images per region.

**C5. Scenario:** A compliance team requires proof that all VM images are patched within 30 days and built from approved bases.
**Question:** Design the pipeline + evidence.
**Answer:** **Image Builder** pipeline: monthly rebuild from the latest patched **Marketplace base**, apply hardening, run **vulnerability scans** as a gate, publish to **Compute Gallery** with a build date tag. Enforce "only approved gallery images" via **Azure Policy**, and produce the build logs + scan results as compliance evidence. Old versions deprecated after 30 days.

**C6. Scenario:** An image needs custom software installed (a vendor agent) that requires a reboot mid-install, and you want it fully automated.
**Question:** How does Image Builder handle this?
**Answer:** Image Builder **customization steps** support running scripts (PowerShell/Shell), file copies, and **reboots within the build** (the template can include restart steps and continue) — so the vendor agent install + reboot + final config is fully automated inside the pipeline, ending in a validated, distributed image. No manual interaction needed.
