# RTIQ — Azure Compute (Real-Time Interview Questions)

> **Cloud:** Azure · **Domain:** Virtual Machines, Custom Image Creation · **Target roles:** SDE-3 · Cloud Engineer · DevOps · DevSecOps · SRE · Platform Engineer · **Reading time:** ~14 min

**How this file is used live:** Azure VM rounds are about *lifecycle and failure*, not SKU trivia. Expect "the VM is unreachable", "the image build broke production", "we're 40% over cost" — plus questions on availability sets/zones and managed identity, because those decide whether a design is production-grade.

**Legend:** ⚡ Rapid · 🔍 Deep dive + follow-ups · 🚨 War room · ⚖️ Trade-off debate · 🎯 Senior signal

---

## 1. Virtual Machines — `virtual-machines.md`

**⚡ Rapid**
1. **Q:** Availability set vs availability zone vs VMSS?
**A.** Availability set: fault/update domains within one datacentre (99.95% SLA, protects against rack/host failure). Zones: physically separate datacentres in a region (99.99% SLA, protects against datacentre failure). VMSS: identical, autoscaled VMs — the default for stateless tiers (zone-spanning where possible).
2. **Q:** What does "stopped (deallocated)" mean for billing?
**A.** You stop paying compute; disks/storage and reserved public IPs still bill. "Stopped" (not deallocated) still holds the compute allocation and bills — a real cost leak people miss.
3. **Q:** Azure Spot VMs — when?
**A.** Interruptible/batch/CI workloads with checkpointing. Eviction policy (`Deallocate` vs `Delete`) matters, and you must handle the 30-second eviction notice in the app/SIG.
4. **Q:** Managed disks — what types?
**A.** Ultra (latency-critical DBs), Premium SSD v2 (tunable IOPS/throughput, cheaper than Ultra), Premium SSD (production default), Standard SSD (dev/web), Standard HDD (backup/archive). Disks are AZ-bound.
5. **Q:** How does a VM get Azure permissions?
**A.** Managed identity (system- or user-assigned) + RBAC role assignment — no secrets. Avoid service principals with secrets inside a VM.
6. **Q:** Where does VM admin access come from?
**A.** SSH keys (Linux) / Entra ID login (Windows/Linux where supported), with access via Azure Bastion or JIT — no public IP, no open 22/3389.
7. **Q:** What is a proximity placement group?
**A.** Co-locates VMs for ultra-low network latency (HPC/trading). Cost: reduced resiliency options (fewer AZs available) and placement failures when capacity is tight — a deliberate trade.

**🔍 Deep dive**
8. **Q:** Design a production 3-tier VM deployment with 99.99% availability.
**A.** Zone-redundant VMSS across 3 zones (or VMs in 3 zones with a zone-redundant load balancer), managed disks with zone redundancy/tier appropriate IOPS, a Standard Load Balancer with health probes, NSGs + ASGs for tiering, Bastion for access, managed identity for PaaS access, VM insights + Log Analytics + alerts on availability/CPU/memory/disk, Azure Backup with cross-region restore, and everything defined in Bicep/Terraform with Policy enforcing the standards.
**↳ Follow-up:** "What still breaks at 99.99%?"
**A.** Region-level failures, a shared dependency (DB, DNS, Key Vault), a bad deployment, or the in-region SLA being met while your app SLA isn't. That's when you discuss multi-region active-active/active-passive with Front Door and data replication.
9. **Q:** How do you patch 500 VMs with no unplanned downtime?
**A.** Azure Update Manager with schedules and maintenance configurations by tag/ring (dev → staging → prod), pre/post scripts, the update orchestration that respects availability, reboot control, and compliance dashboards. For stateless tiers prefer image rebuild + rolling replacement; patch in place for legacy/stateful with a maintenance window.
10. **Q:** How do you reduce Azure VM cost significantly without hurting reliability?
**A.** Right-size using VM insights/utilization data (not gut feel), shut down dev/test on schedules (auto-shutdown/start-stop), use Spot/eviction-tolerant workloads, buy reservations/savings plans for steady baselines (1-year/3-year), move bursty workloads to PaaS/serverless, delete orphan disks/NICs/public IPs/snapshots, and use B-series for low-utilisation workloads where CPU credits fit.
11. **Q:** Explain the VM boot/extension lifecycle and where it fails.
**A.** Boot → provisioning agent (waagent/WindowsAgent) → extensions (custom script, monitoring, Defender) → app config. Failures usually show up as: unreachable VM with no SSH (NSG/route/host-level firewall), boot loop (bad fstab/kernel), extension failure blocking provisioning, or DNS resolution wrong. Use Boot Diagnostics (serial console/screenshot) and Run Command — those two tools solve most cases.
12. **Q:** How do you encrypt VM disks?
**A.** Server-side encryption (platform-managed keys) by default; for CMK, use a Disk Encryption Set backed by Key Vault and optionally encryption at host (encrypts temp disks/caches too — required by some compliance regimes). Guest-level encryption (BitLocker/dm-crypt) for defence in depth. Know the difference: SSE-at-rest protects the platform, encryption-at-host protects the host path.
13. **Q:** What's the difference between redeploy, resize, and restore from backup when a VM is unhealthy?
**A.** Redeploy (moves to a new host, keeps disks — fixes host-level issues), resize (different SKU, may need a stop, changes CPU/RAM/network limits), and restore (recover data/state from a backup — the only option for corruption/data loss). Interviewers want to hear that you pick the least destructive action first.

**🚨 War room**
14. **Q:** A production VM is unreachable. Walk through the first 10 minutes.
**A.** Check resource health/VM status (running?), NSG/effective rules for the port, Boot Diagnostics screenshot/serial log, then use Run Command (or serial console) to check the OS firewall, disk full, service state, and agent status. If the host is degraded → redeploy; if the OS is broken → repair/replace from image or restore. Always confirm the blast radius (one VM or the whole tier) before changes.
15. **Q:** An extension deployment failed and now the VM won't provision/report.
**A.** Remove/reinstall the failing extension, check waagent/WindowsAzureGuestAgent status and logs, ensure outbound access to the extension endpoints (a locked-down egress blocks extensions), and if the VM is unusable, rebuild from the image (immutable approach) rather than fighting extension state.
16. **Q:** CPU is at 100% every night at 2 a.m. and nobody knows why.
**A.** Check the OS-level scheduled tasks/cron, Windows Update/Defender scans, backup jobs, and monitoring agents; then correlate with VM insights. Fix by moving scans/patches to a maintenance window with enough capacity, or right-size. This question tests whether you look inside the guest, not just at Azure metrics.
17. **Q:** After a resize, the VM boots but the network is dead.
**A.** NIC/driver change (reinstall/enable the right accelerated-networking driver), the OS holding the old MAC/ARP, or the new SKU's NIC needing a guest-level reset. Fastest path is usually redeploy or reattach the NIC; use serial console to inspect `ip a`/network state before touching Azure config.
18. **Q:** You're told a VM was compromised. What are your first three actions?
**A.** Isolate (NSG deny-all / move to a quarantine subnet, keep it running for forensics), preserve evidence (snapshot disk + capture memory/logs if possible), and start the IR process (notify, engage security, check the identity it used and what it accessed via CloudTrail-equivalent activity logs/Defender alerts). Do not "fix" the VM before evidence collection.
19. **Q:** Disk is at 92% and growing 2 GB/day. Immediate and structural fix?
**A.** Immediate: identify the consumer (logs/`du`/log rotation, temp files, app data), clean safely, and if needed expand the disk online (Premium SSD resize) + `growpart`/filesystem extend. Structural: log rotation and retention, monitoring with an 80% alarm, app-side data lifecycle (move to Blob), and capacity planning so growth is a known quantity.

**⚖️ Trade-off**
20. **Q:** VMs vs App Service vs AKS vs Container Apps for a new service?
**A.** VMs when you need OS-level control/legacy software; App Service for standard web apps with least ops; Container Apps for containerised microservices/serverless-ish scaling; AKS when you need the K8s ecosystem/platform standardisation. Weight team capability and long-term ops cost, not just capability lists.
21. **Q:** Single large VM vs multiple smaller VMs?
**A.** Multiple smaller VMs across zones/instances gives HA and horizontal scale (plus scaling granularity), at higher licensing/management overhead. Single large VM = SPOF and vertical ceiling. For production, horizontal wins unless the workload can't scale out (then invest in HA with a standby).
22. **Q:** Reserved instances vs pay-as-you-go vs savings plans?
**A.** Reservations for known, steady VM usage (biggest discount, tied to SKU/region); savings plans for flexible spend commitment across SKUs/regions; PAYG for spiky/uncertain. Most estates: reservations for a stable baseline + PAYG/Spot for peaks. Prove it with actual utilisation data.
23. **Q:** Managed disks vs Azure Files/Blob for app data?
**A.** Managed disks for VM OS/data volumes (block, single attach per disk type); Azure Files for shared SMB/NFS mounts; Blob for object/unstructured. Don't use OS disks as shared storage — that's how you get corruption and failed clustering.

**🎯 Senior**
24. **Q:** What does "production-ready VM" mean to you, as a standard?
**A.** No public IPs, Bastion/JIT access only, managed identity (no secrets on box), zone-redundant placement, sized from measured utilisation with disk alarms at 80%, patched via Update Manager rings, backups with tested restore, CMK/encryption-at-host where required, diagnostics + VM insights to a central workspace, tags for owner/cost/environment, and deployment only through IaC with Policy guardrails.

**🎯 Senior signal:** "check Boot Diagnostics and Run Command first", "isolate before you remediate a compromised VM", and shutting down dev/test on a schedule. Those answers prove operational maturity.

---

## 2. Custom Image Creation (Azure Compute Gallery) — `image-creation.md`

**⚡ Rapid**
1. **Q:** What is the Azure Compute Gallery, in one line?
**A.** A registry for image definitions and versions (with replication to regions, versioning, and sharing across subscriptions/tenants via RBAC and direct share) — the modern replacement for managed images.
2. **Q:** What's the difference between a managed image and a gallery image version?
**A.** A managed image is a single, region-bound snapshot-based image with no versioning/replication. A gallery image version is versioned, replicable across regions, shareable, and supports specialized/generalized states. Production uses the gallery.
3. **Q:** Generalized vs specialized image?
**A.** Generalized (deprovisioned with `waagent -deprovision+user` / `sysprep /generalize`) can be used to create VMs with new hostnames/credentials. Specialized retains machine identity (useful for golden state, VDI, or specific scenarios) but can't be re-generalized. Choosing wrong causes broken hostnames or duplicate identities.
4. **Q:** How do you build images on Azure?
**A.** Azure Image Builder (AIB) with a Bicep/Terraform template + customization steps, or Packer, or the simpler "build a VM, capture" (not recommended for automation). AIB is the managed, pipeline-friendly option.
5. **Q:** How do you version images?
**A.** Semantic-ish versions (`1.0.3`, plus `latest` pointer control) with a version policy on the definition (`excludeFromLatest`, retention). Consumers reference a specific version — never "latest" in production.
6. **Q:** How do images get distributed across regions?
**A.** Gallery replication by region (with per-region replica counts for scale), or the newer community/direct-share options. Replication takes time; `replication_status` must be complete before relying on it in a failover.

**🔍 Deep dive**
7. **Q:** Design a golden-image pipeline for 400 VMs.
**A.** Base image (Microsoft marketplace or CIS-hardened) → AIB build with patching, agents, hardening, app runtime → validation (boot + smoke test + security scan, e.g. Defender/Trivy/qualys) → publish a new **version** to the gallery with tags (build date, CVE state, source commit) → promote to non-prod → canary VMSS roll out → promote to prod with a rolling replacement → retain N versions for rollback. Add a monthly rebuild so base CVEs are picked up automatically.
**↳ Follow-up:** "A CVE lands in a package you ship. How fast can you have patched images everywhere?"
**A.** Answer with the pipeline's real cadence: rebuild trigger → validation gate → ring-based rollout with instance refresh/boot diagnostics. Typically hours for images, days (or a scheduled maintenance window) to fully replace prod — and say what the constraint is (reboot windows, stateful workloads).
8. **Q:** How do you roll out a new image version without downtime?
**A.** VMSS with a rolling update policy (or instance refresh), max-unhealthy/batch size and pause controls, health probes so bad instances are replaced or the rollback triggers, canary at a small percentage first, and Boot Diagnostics + VM insights watched during the rollout. For non-VMSS workloads, use a blue/green pair of scale sets with a load balancer swap.
9. **Q:** How do you keep secrets and identity out of images?
**A.** Never bake credentials; use managed identity at runtime, Key Vault references, and cloud-init/extension-time config. Also avoid baking machine-specific state (hostnames, SSH host keys if regenerating, license tokens) and ensure `waagent -deprovision` runs for generalized images.
10. **Q:** How do you handle Windows patching and licensing in images?
**A.** Patch the base during build (or use the latest patched marketplace image), enable Windows Update for ongoing patches via Update Manager, and honor licensing (Azure Hybrid Benefit for Windows Server/SQL must be configured; images captured with AHB require care). Mention licensing because auditors ask.
11. **Q:** What's the image storage cost story?
**A.** Each version replicates as snapshots/managed disks per region + replica count — so versions multiply storage. Apply a retention policy (keep N versions + `latest`), avoid unnecessary regions, and remember deleted versions leave blob/snapshot data briefly. Cost discipline = version policy, not manual cleanup.
12. **Q:** How do you test an image before production?
**A.** Automated validation: boot, agent heartbeat, extension application, app smoke tests, security scan results, and a canary scale set receiving a small slice of traffic or synthetic checks. "We built it, looks fine" is not testing — say the smoke-test part explicitly.

**🚨 War room**
13. **Q:** A new image version shipped and 60% of new VMs fail to boot.
**A.** Stop the rollout (pause the rolling update / pin the previous version), diagnose via Boot Diagnostics and serial console, identify the build change (deprovision step, driver, disk/partition sizing, cloud-init failure), fix and rebuild, then re-roll out canary-first. Post-incident: add a boot+smoke test to the pipeline as a hard gate before publishing.
14. **Q:** You need to roll back a fleet to the previous image fast.
**A.** Because versions are immutable and referenced explicitly, rollback = point the VMSS/scale set at the previous version and run another rolling update (or scale-set swap for blue/green). This is the payoff for versioning properly — and the reason you never reference `latest`.
15. **Q:** The image is 40 GB and rollouts take 25 minutes per batch. Optimize.
**A.** Slim the image (remove build artifacts, caches, unused packages, use smaller base), enable disk caching/`osDisk` caching settings, pre-replicate to the target region with enough replicas, and use faster disk tiers for the scale set. Also consider a two-stage approach: small base image + extension/container pull for the app layer.
16. **Q:** After a gallery replication change, a failover region had no usable image.
**A.** Replication is asynchronous — check `replication_status` before relying on it; the failover attempted to create VMs from a version not yet replicated. Fix: pre-replicate critical versions to DR regions as part of the release process, and validate with a canary deployment in the DR region.
17. **Q:** Someone captured a production VM as an image and it's full of secrets and personal data.
**A.** Treat as a data-exposure incident: delete/restrict the image version (RBAC on the gallery/definition), audit who could access it, rotate any secrets found, and then fix the process — images only from the pipeline, never from production VMs, with Policy/ABAC limiting capture and gallery sharing.

**⚖️ Trade-off**
18. **Q:** Golden images vs configuration management vs containers?
**A.** Golden images give fast, reproducible starts and immutable rollback (best for VMSS/legacy OS workloads); config management (Ansible/Arc) is flexible for long-lived pets but drifts; containers are best for app portability. Mature estates: golden base image + minimal boot-time config, with apps containerised where possible.
19. **Q:** Azure Image Builder vs Packer vs manual capture?
**A.** AIB: managed, Azure-native, pipeline-friendly, easier permissions. Packer: mature, multi-cloud, more control/plugins, you own the runner. Manual capture: adds human error and drift, no place in production. Choose AIB for Azure-only shops, Packer for multi-cloud.
20. **Q:** One image for all workloads vs per-workload images?
**A.** One hardened base + per-workload layers is maintainable; a single monolith image for everything bloats and couples teams. Balance: shared base gallery + per-team image definitions building on it.
21. **Q:** How often should you rebuild images?
**A.** At least monthly for patched bases, plus on any critical CVE and on app release for app-layer images — driven by automation, not a calendar reminder. Measure "oldest running image" as a KPI; that number is your real patch posture.

**🎯 Senior**
22. **Q:** How do you prove image provenance and compliance to an auditor?
**A.** Every gallery version tagged with source commit, pipeline run ID, build date, scan results (signed attestation in the build artifact store), the pipeline enforces scans and blocks publishing on failure, and deployment evidence showing scale sets reference approved versions only (Policy: allowed image definitions). Provenance = automated evidence, not a spreadsheet.

**🎯 Senior signal:** "never `latest` in production", "rollback = repin the version", and pre-replicating to DR regions. Those signal real image lifecycle ownership.
