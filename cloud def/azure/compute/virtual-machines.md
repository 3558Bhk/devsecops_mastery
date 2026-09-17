# Azure Virtual Machines — Interview Questions

> **Cloud:** Azure · **Category:** Compute · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~8 min

---

## JSON File Format

Azure VMs are ARM JSON (`Microsoft.Compute/virtualMachines`) combining hardware, storage, OS, and network profiles.

```json
{
  "type": "Microsoft.Compute/virtualMachines",
  "apiVersion": "2023-03-01",
  "name": "myVM",
  "properties": {
    "hardwareProfile": { "vmSize": "Standard_D2s_v3" },
    "storageProfile": {
      "imageReference": { "publisher": "Canonical", "offer": "0001-com-ubuntu-server-jammy", "sku": "22_04-lts-gen2", "version": "latest" },
      "osDisk": { "createOption": "FromImage", "managedDisk": { "storageAccountType": "Premium_LRS" } }
    },
    "osProfile": { "computerName": "myvm", "adminUsername": "azureuser" },
    "networkProfile": { "networkInterfaces": [{ "id": "/subscriptions/<sub>/.../networkInterfaces/myvm-nic" }] }
  }
}
```

**Key fields:** `hardwareProfile.vmSize` · `storageProfile` (`imageReference`, `osDisk`/`dataDisks`) · `osProfile` · `networkProfile.networkInterfaces` · `zones` (availability zones) / `availabilitySet.id`.


## Case A — Basic

**A1. What is an Azure Virtual Machine?**
**Answer:** An on-demand, scalable compute resource (IaaS) — a virtual server in Azure that you fully control (OS, software, config), billed per second/minute.

**A2. What are the main components of a VM?**
**Answer:** **VM size** (vCPU/memory), **OS disk**, **data disks**, **virtual network (NIC)**, **public/private IP**, **NSG**, and the **resource group**/region.

**A3. What is a VM size and what are the families?**
**Answer:** The size defines vCPU, RAM, and capabilities. Families: **General purpose** (B/D/DSv), **Compute optimized** (F), **Memory optimized** (E/M), **Storage optimized** (L), **GPU** (NC/ND/NV), **High-performance compute** (H). Choose by workload profile.

**A4. What is the difference between an OS disk and a data disk?**
**Answer:** **OS disk** = boot volume with the operating system (persistent). **Data disks** = additional managed disks for app data. Both are **managed disks** (or ephemeral/temporary disks).

**A5. What is a temporary (ephemeral) disk?**
**Answer:** A local SSD attached to the host — fast but **not persistent** (lost on maintenance/stop/deallocate). Use for scratch/temp data only.

**A6. What is an Availability Set?**
**Answer:** Groups VMs across **fault domains** (physical racks) and **update domains** (maintenance groups) to protect against hardware/maintenance failures — for VMs not using Availability Zones.

**A7. What is an Availability Zone?**
**Answer:** A physically separate datacenter within a region; deploying VMs across **zones** protects against an entire datacenter failure (higher availability than availability sets).

**A8. What is a VMSS (Virtual Machine Scale Set)?**
**Answer:** A managed group of identical, auto-scaling VMs behind a load balancer — for scale-out/in workloads.

**A9. How is a VM billed?**
**Answer:** Per compute time (second/minute granularity for most sizes) + **managed disk** storage + bandwidth. **Stopped (deallocated)** VMs don't incur compute charges (only disks).

**A10. What is the difference between "Stopped" and "Stopped (deallocated)"?**
**Answer:** **Stopped** = VM halted but still allocated (compute charges continue). **Stopped (deallocated)** = resources released (no compute charges, but disks still bill; public IP may change unless reserved).

**A11. What is a managed disk?**
**Answer:** Azure-managed storage for VM disks — you specify type/size and Azure handles the underlying storage (vs unmanaged disks in storage accounts).

**A12. What are the managed disk types?**
**Answer:** **Premium SSD**, **Standard SSD**, **Standard HDD**, **Ultra Disk** (high IOPS/throughput, sub-ms), and Premium SSD v2. Choose by performance needs.

**A13. What is Azure Spot VMs?**
**Answer:** Deeply discounted VMs using Azure's unused capacity — but **evictable** when Azure needs the capacity back (good for interruptible/batch workloads).

**A14. What is a reserved instance / savings plan?**
**Answer:** 1–3 year commitments for significant (up to ~72%) discounts vs pay-as-you-go — for predictable, steady-state VMs.

**A15. How do you connect to a Linux vs Windows VM?**
**Answer:** Linux: **SSH** (port 22) with key/certificate auth. Windows: **RDP** (port 3389). Both require the NSG to allow the port and (for public access) a public IP.

---

## Case B — Advanced (Senior)

**B1. Compare Availability Sets vs Availability Zones vs VMSS for HA — when each?**
**Answer:** **Availability Set** = same region, fault/update domain separation (SLA 99.95%) — for apps not zone-ready. **Availability Zones** = separate physical datacenters (SLA 99.99% for zone-redundant VMs) — best HA within a region. **VMSS** = scaling + HA combined (instances across zones). Use zones for new designs; availability sets for legacy/single-zone constraints; VMSS for scale.

**B2. What is the VM SLA and how do you meet it (99.9% vs 99.95% vs 99.99%)?**
**Answer:** Single VM with **Premium SSD**: 99.9%. Two+ VMs in an **Availability Set**: 99.95%. VMs across **Availability Zones**: 99.99% (for zone-redundant). To meet SLAs you must configure the redundancy correctly (all VMs in the set/zone, managed disks, etc.).

**B3. How does a VM boot/repair flow work, and what do you check when a VM won't start?**
**Answer:** Boot: allocation (size/capacity) → NIC/disk attach → OS boot → extension/agent. If it won't start: check **deallocation/state**, **disk/OS corruption** (use **Serial Console**, **Boot Diagnostics** screenshots), **capacity issues** (resize/redeploy), and **extension/agent failures**. Use **Redeploy** (moves to a new host) as a common fix for host-level faults.

**B4. What are VM extensions and the Azure VM Agent, and how are they used?**
**Answer:** The **VM Agent** runs inside the VM and manages **extensions** — post-deploy configuration (custom scripts, DSC, Chef/Puppet), monitoring (Azure Monitor agent), backup, and security (Defender). Extensions enable automation without direct login; they require outbound connectivity to Azure endpoints.

**B5. How do you resize a VM (up/down) and what are the constraints?**
**Answer:** Change the **VM size** (stop the VM, pick a size in the same family/region with capacity, then start). Constraints: the size must be available in the region, support the VM's disks/features (e.g., accelerated networking, premium storage), and fit within quota. Resizing changes CPU/RAM; disks persist.

**B6. What is accelerated networking and when should you enable it?**
**Answer:** **SR-IOV**-based networking that bypasses the virtual switch for lower latency and higher throughput (up to 30 Gbps). Enable on supported sizes for latency-sensitive, high-throughput workloads (DBs, network appliances). It's a per-NIC setting, usually on by default for many newer sizes.

**B7. How do you design VM storage for performance (OS disk, temp disk, data disks, Ultra/SSD v2)?**
**Answer:** Use **Premium SSD** for OS; place heavy I/O (DBs, logs) on **Premium SSD v2 / Ultra Disk** with provisioned IOPS/throughput; use the **temp disk** for scratch (non-persistent); stripe **multiple data disks** for aggregate throughput; enable **host caching** (ReadOnly for data, ReadWrite for OS where appropriate). Match disk performance to workload IOPS/latency needs.

**B8. What is Azure Site Recovery (ASR) for VMs, and how does it differ from backup?**
**Answer:** **ASR** = **disaster recovery** — continuous replication of VMs to another region with orchestrated failover (RPO minutes, RTO minutes). **Azure Backup** = point-in-time **backups** for restore (not continuous DR). Use ASR for region-level DR; Backup for data protection/retention.

**B9. How do you patch and update VMs at scale (Update Manager, maintenance configurations)?**
**Answer:** Use **Azure Update Manager** (or the older Automation Update Management) to assess + schedule patches across VMs, define **maintenance configurations** (windows) so Azure-initiated updates don't disrupt, and use **Defender for Cloud** patch-compliance reporting. Pair with custom images/Image Builder for a patched base.

**B10. What are the cost optimization levers for VMs?**
**Answer:** **Right-size** (Azure Advisor/Compute recommendations), **reserved instances/savings plans** for steady workloads, **Spot VMs** for interruptible workloads, **auto-shutdown** for dev/test, **stop-deallocate** when idle, choose the right **disk tier** (Standard vs Premium), and consolidate with **App Service/containers** where VMs are overkill.

**B11. How do you secure a VM (identity, disks, network, OS)?**
**Answer:** **Managed identity** (no passwords), **Azure AD login** for VMs (Entra), **disk encryption** (Azure Disk Encryption/BitLocker/DM-Crypt, or encryption-at-host), **NSG** least privilege + **JIT** access (Defender), **Defender for Servers** (threat detection), **no public IPs** unless needed (use Bastion), and patch management.

**B12. What is a Proximity Placement Group and when is it needed?**
**Answer:** A logical grouping that keeps VMs **physically close** (low network latency between them) in a region — for latency-sensitive clusters (HPC, SAP, quorum-based clusters) that need sub-millisecond inter-VM latency across availability sets/zones.

---

## Case C — Scenario

**C1. Scenario:** A legacy app needs to move from on-prem to Azure as-is, with full OS control and minimal rework.
**Question:** Which compute option and migration approach?
**Answer:** **Azure VMs (IaaS)** via **Azure Migrate**: discover/assess on-prem servers, replicate disks, and cut over to Azure VMs (right-sized). This is lift-and-shift — no code changes, full OS control. Add managed disks, backup, and monitoring post-migration.

**C2. Scenario:** A VM is unresponsive and you can't SSH/RDP in, but you need to recover data or see why.
**Question:** What Azure tools do you use?
**Answer:** (1) **Boot Diagnostics** (screenshot/serial log) to see boot state, (2) **Serial Console** for out-of-band access (GRUB/single-user recovery), (3) **Redeploy** to move to a new host, (4) **detach the OS disk and attach to a rescue VM** to access files, (5) if OS is corrupt, restore from **Azure Backup**/snapshot.

**C3. Scenario:** An app must survive a datacenter outage within a region (not just a rack failure).
**Question:** Availability Set or Availability Zones? Justify.
**Answer:** **Availability Zones** — an availability set only spreads across fault/update domains **within a datacenter**, so a full datacenter outage still takes it down. Zones spread VMs across **separate physical datacenters** (99.99% SLA), surviving a datacenter failure. Deploy the VMs across zones (with zone-redundant storage/LB).

**C4. Scenario:** A batch-processing fleet runs only at night and can tolerate interruption.
**Question:** Which pricing option?
**Answer:** **Azure Spot VMs** — they use spare capacity at a steep discount and can be **evicted** when Azure needs capacity (acceptable for interruptible night jobs). Add eviction handling (checkpointing) and pair with **auto-shutdown/scheduling** so the fleet only runs during the night window.

**C5. Scenario:** A VM's disk fills up with logs and the VM goes unhealthy.
**Question:** Prevent and respond.
**Answer:** Prevent: **disk space alerts** (Azure Monitor on disk metrics/agent), log rotation, move logs to a **data disk** (not OS), and monitor with the Azure Monitor agent. Respond: extend the **managed disk size** (resize disk → extend filesystem), or attach a new data disk and relocate logs. Use automation (Runbook) to auto-extend.

**C6. Scenario:** You must ensure all VMs are patched monthly with zero manual effort and a compliance report.
**Question:** Design it.
**Answer:** **Azure Update Manager** with a **maintenance configuration** (monthly window, by tag/group), patching OS + reporting compliance in the portal. Combine with **Azure Policy** to require patch assessment and **Defender for Cloud** for compliance dashboards. Use custom images (Image Builder) for the base so patches are baked in too.
