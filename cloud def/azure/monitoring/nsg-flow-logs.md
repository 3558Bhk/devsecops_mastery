# Azure NSG Flow Logs — Interview Questions

> **Cloud:** Azure · **Category:** Monitoring · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~9 min

---

## JSON File Format

NSG flow logs are stored as **JSON blobs** — the record structure (Version 1/2) with flows and the matched rule.

```json
{
  "records": [{
    "time": "2026-09-13T10:00:00.0000000Z",
    "category": "NetworkSecurityGroupFlowEvent",
    "properties": {
      "Version": 2,
      "flows": [{
        "rule": "UserRule_AllowHttps",
        "flows": [{
          "mac": "000D3A123456",
          "flowTuples": ["172.16.1.4,203.0.113.9,55910,443,T,I,D,B,1024,2048,120,300"]
        }]
      }]
    }
  }]
}
```

**Key fields:** `category` · `Version` (1 or 2 — v2 adds bytes/packets) · `flows[].rule` (the NSG rule that matched) · `flowTuples[]` — a comma string: `srcIP,dstIP,srcPort,dstPort,protocol,TrafficFlow(I/O),TrafficDecision(A/D),FlowState(B/E),bytesSent,bytesReceived,…`.


## Case A — Basic

**A1. What are NSG flow logs?**
**Answer:** A Network Watcher feature that logs **each network flow** allowed or denied by an NSG — the 5-tuple (source/dest IP, ports, protocol), direction, and decision — for security and traffic analysis.

**A2. What information does a flow log record contain?**
**Answer:** Source/destination IP, source/destination ports, protocol, **direction** (in/out), **action** (allow/deny), the **NSG rule** that applied, timestamps, and bytes/packets (in Version 2).

**A3. What is the difference between flow log Version 1 and Version 2?**
**Answer:** **V2** adds **bytes/packets sent** per flow and more metadata (rule that matched) — richer for traffic analysis/cost attribution. V2 is the current default.

**A4. Where are flow logs stored?**
**Answer:** In a **Storage Account** (JSON blobs) by default, and optionally sent to **Log Analytics** + **Traffic Analytics** for analysis.

**A5. What is Traffic Analytics?**
**Answer:** An add-on that processes flow logs to show **traffic maps, top talkers, ports, application ports, and security insights** — turning raw flow logs into actionable dashboards.

**A6. What is the difference between NSG flow logs and VNet flow logs?**
**Answer:** NSG flow logs capture flows **at the NSG**; **VNet flow logs** (newer) capture flows **for an entire VNet/subnet/NIC** even without an NSG — broader coverage. Both feed Traffic Analytics.

**A7. Are flow logs free?**
**Answer:** No — flow logs incur **storage** (and Log Analytics ingestion, if enabled) costs; Traffic Analytics has its own pricing. Budget for volume.

**A8. What is the retention consideration for flow logs?**
**Answer:** Set the **Storage retention** (0 = keep forever) per compliance; note older data should be tiered/archived to control cost.

**A9. What is the format/location of flow log files?**
**Answer:** JSON files in the storage account under `insights-logs-networksecuritygroupflowevent/...` organized by resource/date/time (every ~1–5 min per NSG).

**A10. What's the difference between a flow log "event" and "flow tuple"?**
**Answer:** An **event** = a snapshot (aggregation window, ~1 min) of **flow tuples** (individual connections) for that NSG.

**A11. Why are flow logs important for security?**
**Answer:** They record **denied** traffic (reconnaissance/blocked attacks) and **allowed** flows (for detecting exfiltration/lateral movement) — key evidence for incident response and compliance.

**A12. Can you log flows for a subnet without an NSG?**
**Answer:** With **NSG flow logs** you need an NSG attached; with **VNet flow logs** (newer) you can capture subnet/NIC flows without an NSG.

**A13. How do flow logs relate to NSG rules?**
**Answer:** Each flow tuple records the **rule that matched** (allow/deny) — so you can verify whether traffic was permitted/blocked by which rule, helping debug NSG misconfigurations.

**A14. What is the typical flow log file cadence?**
**Answer:** Files are written every **~1 minute** (aggregated), with some latency (a few minutes) before appearing in storage/Log Analytics.

**A15. How do you enable flow logs?**
**Answer:** Via **Network Watcher → Flow logs** (or the NSG/Portal), selecting the NSG, storage account, and optional Log Analytics + Traffic Analytics, plus retention.

---

## Case B — Advanced (Senior)

**B1. Explain how flow logs are structured and how to analyze them at scale (storage vs Log Analytics).**
**Answer:** Raw flow logs land as **JSON blobs** in storage (cheap, but hard to query); sending them to **Log Analytics** enables **KQL** queries (`AzureNetworkAnalytics_CL` / `NTANetAnalytics` tables via Traffic Analytics) and alerting. For scale: use Traffic Analytics for pre-aggregated insights, Log Analytics for custom queries, and archive raw JSON to storage.

**B2. How do you use flow logs to detect denied traffic (reconnaissance/attack attempts)?**
**Answer:** Query for **Deny** actions on unusual ports (e.g., inbound 22/3389 from the internet), aggregate by source IP, and correlate with threat-intel feeds. Persistent denied attempts from one IP = likely scanning/brute-force. Alert on high deny-volume from unknown IPs and block via NSG/Firewall rules.

**B3. How do you use flow logs to detect data exfiltration (allowed outbound)?**
**Answer:** Look for **unusual outbound ALLOW flows**: large byte volumes to new external IPs/domains (via Traffic Analytics top-talkers), connections to non-standard ports, or sustained uploads from DB/internal servers. Correlate with Defender/Sentinel for confirmation. This is why allowed-flow logging matters, not just denies.

**B4. What is Traffic Analytics and what are its key outputs (maps, top talkers, anomalous flows)?**
**Answer:** Traffic Analytics processes flow logs into: **traffic distribution maps** (by region/subnet), **top talkers** (IPs, ports, apps), **application port usage**, **malicious traffic** (with threat intel), and **NSG misconfiguration insights**. It uses an interval (10/60 min) and stores in the `NTANetAnalytics` tables.

**B5. How do flow logs help troubleshoot NSG misconfigurations ("why is this traffic blocked")?**
**Answer:** Flow logs record the **matched rule** and **action** per flow — so you can see exactly which rule denied a flow (or that no rule matched → default deny). Cross-check with the **effective security rules** view. This closes the loop between "traffic broken" and "which NSG rule to fix."

**B6. What are the cost drivers for flow logs and how do you control them?**
**Answer:** Costs = **storage** (per GB of flow JSON, high for busy NSGs) + **Log Analytics ingestion** (if enabled) + **Traffic Analytics** (per interval processed). Control: enable only on **critical NSGs** (not every NSG), choose **10-min** Traffic Analytics interval (vs 1-min), set **retention/tiering**, and disable Log Analytics for low-value NSGs.

**B7. What is the relationship between flow logs, Traffic Analytics, and Sentinel (threat detection)?**
**Answer:** Flow logs → Log Analytics → **Sentinel** can ingest and run **analytics rules** (e.g., detect port scans, impossible-travel flows, data exfil patterns) and **hunting queries**, while **Traffic Analytics** provides visual/anomaly insights. Sentinel turns flow logs from "records" into "detections + incidents."

**B8. How do you query flow logs in Log Analytics with KQL (examples)?**
**Answer:** e.g., denied traffic: `AzureNetworkAnalytics_CL | where FlowStatus_s == "D" | summarize count() by SrcIP_s, DestPort_d`; top talkers: `... | summarize Bytes = sum(BytesOut_d) by SrcIP_s | top 10 by Bytes`; or via Traffic Analytics tables `NTANetAnalytics | where FlowType == "MaliciousFlow"`. Time-bound all queries.

**B9. What are the limitations/gotchas of flow logs?**
**Answer:** (1) They're **sampled/aggregated** (not every packet — flow-level), (2) **latency** (~1–5 min to storage, more to Traffic Analytics), (3) **cost** at scale, (4) **no payload** (only metadata — no packet contents), (5) flows are for **NSGs/VNets** (not Azure Firewall — that has its own logs), and (6) **Traffic Analytics** has its own latency/processing.

**B10. How does VNet flow logging differ from NSG flow logging, and when do you use it?**
**Answer:** **VNet flow logs** capture flows at the **VNet/subnet/NIC** scope — covering traffic even where **no NSG exists** (or where NSG is bypassed). Use VNet flow logs for complete coverage of a VNet; NSG flow logs for rule-level detail at security boundaries. Both can feed Traffic Analytics (with some feature differences).

**B11. How do you integrate flow logs with IPAM/CMDB or third-party SIEMs?**
**Answer:** Export flow logs via **Event Hubs / Data Export** to third-party SIEMs (Splunk, QRadar) or **Sentinel**; enrich with CMDB/asset data for context (who owns the IP). Traffic Analytics + Log Analytics cover the Azure-native path; Event Hub streaming covers external tools.

**B12. What compliance use cases do flow logs support (audit, forensics, retention)?**
**Answer:** Flow logs provide **network audit trails**: proof of what was allowed/denied (for PCI/HIPAA/SOC2), **forensics** after incidents (reconstruct attacker movement), and **retention** per policy (storage tiering/immutability). Pair with immutable storage + Sentinel for a defensible audit record.

---

## Case C — Scenario

**C1. Scenario:** A security analyst suspects a VM is being brute-forced on RDP from the internet.
**Question:** How do flow logs confirm it?
**Answer:** Enable/query flow logs for the VM's NSG: filter **inbound, port 3389, FlowStatus = Denied** (or Allowed if RDP is open), aggregate by **source IP** — a high volume of denied attempts from one or many IPs confirms the brute-force. Then block the sources (NSG/Firewall) and enable JIT.

**C2. Scenario:** A DB server suddenly uploaded several GB to an unknown external IP overnight.
**Question:** How do flow logs help investigate exfiltration?
**Answer:** Query **outbound ALLOW flows** from the DB's IP, sorted by **bytes**, filter to non-standard ports/destinations and the overnight window, identify the destination IP/volume, then correlate (Threat Intel/Sentinel) and check the DB for compromise. Flow logs give the who/when/how-much of the exfiltration.

**C3. Scenario:** An app migration changed NSGs, and now a specific flow is blocked — but you're not sure which rule.
**Question:** How do flow logs + effective rules pinpoint it?
**Answer:** Use **IP flow verify** (or the flow log) to see the actual decision for that 5-tuple; flow logs record the **matched rule name and action** (deny) for the flow, and **effective security rules** shows the merged rule list. Find the deny rule, reorder/allow, and verify the flow now logs as **Allowed**.

**C4. Scenario:** Flow log storage costs are exploding across 200 NSGs.
**Question:** Right-size the flow log strategy.
**Answer:** Enable flow logs only on **critical NSGs** (edge, DB, DMZ), set **Traffic Analytics** to the 10-minute interval, disable **Log Analytics ingestion** for low-value NSGs (storage-only), apply **retention/tiering** (move old blobs to Cool/Archive), and monitor per-NSG volume to identify noisy ones. Consider VNet flow logs for broad coverage instead of per-NSG everywhere.

**C5. Scenario:** You must alert when any VM receives more than 100 denied inbound connections in 5 minutes (potential scanning).
**Question:** Build the detection.
**Answer:** Route flow logs to **Log Analytics**; create a **log query alert**: `AzureNetworkAnalytics_CL | where FlowStatus_s == "D" and FlowDirection_s == "I" | summarize count() by SrcIP_s, DestIP_s, bin(TimeGenerated, 5m) | where count_ > 100` → alert via action group. Optionally enrich in **Sentinel** with threat intel and auto-block via a playbook.

**C6. Scenario:** An auditor wants a monthly report of all internet-facing allowed flows to internal systems.
**Question:** Produce it.
**Answer:** Use **Traffic Analytics** (or Log Analytics KQL) filtered to **inbound ALLOW** flows from internet IPs to internal subnets, aggregated by destination port/service and source, exported monthly (Log Analytics → report/dashboard, or automate via Logic App/Automation to email a CSV). This documents the external attack surface for audit.
