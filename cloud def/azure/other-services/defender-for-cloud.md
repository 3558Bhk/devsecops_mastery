# Microsoft Defender for Cloud — Interview Questions

> **Cloud:** Azure (Other Services) · **Category:** Security / CSPM · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~8 min

---

## JSON File Format

Defender for Cloud recommendations are backed by **Azure Policy definitions** (JSON), and security **alerts** are JSON payloads.

```json
{
  "type": "Microsoft.Authorization/policyDefinitions",
  "apiVersion": "2021-06-01",
  "name": "deny-public-blob",
  "properties": {
    "displayName": "Storage accounts should restrict public access",
    "mode": "All",
    "policyRule": {
      "if": { "allOf": [ { "field": "type", "equals": "Microsoft.Storage/storageAccounts" } ] },
      "then": { "effect": "audit" }
    }
  }
}
```

**Key fields:** `policyRule` (`if` / `then` / `effect` — audit/deny) · `displayName` · `mode`. Security alert JSON: `alertDisplayName`, `severity`, `entities`, `startTimeUtc`, `remediationSteps`. Workflow automation (Logic Apps) is also JSON.


## Case A — Basic

**A1. What is Microsoft Defender for Cloud?**
**Answer:** Azure's **Cloud Security Posture Management (CSPM)** + **Cloud Workload Protection (CWP)** service — it continuously assesses your resources against best practices, and detects/responds to threats.

**A2. What is the Secure Score?**
**Answer:** A numeric score measuring your security posture (based on recommendations) — higher = more secure. Track it over time and drill into recommendations to improve it.

**A3. What is a security recommendation?**
**Answer:** A finding from a benchmark/assessment (e.g., "MFA should be enabled", "storage accounts should use private endpoints") with remediation steps — the core of CSPM.

**A4. What are the two main pillars (CSPM vs CWP)?**
**Answer:** **CSPM** = posture management (Secure Score, recommendations, compliance). **CWP** = **Defender plans** — active threat detection/protection for servers, storage, containers, SQL, etc.

**A5. What are Defender plans?**
**Answer:** Paid protection tiers per workload: **Defender for Servers**, **Storage**, **Containers**, **SQL**, **App Service**, **Key Vault**, **ARM**, **DNS**, **APIs**, **AI**, etc. — each adds threat detection/alerts.

**A6. What is the difference between the Foundational (free) CSPM and Defender plans?**
**Answer:** **Free** = Secure Score, recommendations, basic inventory (CSPM). **Defender plans** = advanced detection, alerts, vulnerability assessment, JIT, regulatory compliance, etc. (CWP).

**A7. What security standards does Defender for Cloud assess?**
**Answer:** **Microsoft Cloud Security Benchmark (MCSB)**, plus **NIST**, **CIS**, **PCI DSS**, **ISO 27001**, **SOC 2**, and more (regulatory compliance dashboard).

**A8. What is Just-in-Time (JIT) VM access?**
**Answer:** A Defender for Servers feature that **opens management ports (RDP/SSH) temporarily** for approved users/IPs and auto-closes them — eliminating permanently open management ports.

**A9. What are security alerts?**
**Answer:** Detections of suspicious/malicious activity (e.g., brute-force, malware, exfiltration) with severity + remediation guidance — from Defender plans.

**A10. What is the relationship between Defender for Cloud and Microsoft Sentinel?**
**Answer:** Defender for Cloud = **detects and assesses**. Sentinel = **SIEM/SOAR** — Defender alerts stream into Sentinel for correlation, investigation, and automated response (playbooks). They complement.

**A11. What is the regulatory compliance dashboard?**
**Answer:** A view mapping your resources' status against standards (PCI, NIST, CIS) — showing pass/fail per control for audits.

**A12. What is a security initiative / benchmark?**
**Answer:** A set of **Azure Policy** definitions (rules) grouped as a benchmark (e.g., MCSB) that Defender uses to evaluate compliance and generate recommendations.

**A13. How does Defender integrate with Azure Policy?**
**Answer:** Recommendations are backed by **Azure Policy** initiatives; remediating a recommendation often means fixing the underlying policy non-compliance. Policy + Defender work together (policy enforces, Defender reports).

**A14. What is "Defender for Cloud Apps" vs "Defender for Cloud"?**
**Answer:** **Defender for Cloud** = Azure resource security (CSPM/CWP). **Defender for Cloud Apps** (formerly MCAS) = **SaaS/cloud app security** (CASB — shadow IT, app governance). Different products, often used together.

**A15. What is the "inventory" or asset view?**
**Answer:** A unified view of all monitored resources across subscriptions with their security posture/health — the starting point for investigation.

---

## Case B — Advanced (Senior)

**B1. Explain the architecture: how Defender collects data (agents, plans, Log Analytics).**
**Answer:** Enabling **Defender plans** deploys the **Azure Monitor Agent / Defender extensions** (e.g., `MDE.Windows`) to workloads, which stream telemetry to **Log Analytics workspaces**; the Defender backend analyzes telemetry and emits **alerts/recommendations**. Some plans (storage, Key Vault, ARM) are service-side (no agent). Understanding this helps troubleshoot missing data.

**B2. What is the MCSB (Microsoft Cloud Security Benchmark) and how does it structure controls?**
**Answer:** MCSB is Microsoft's **cloud security baseline** — a set of **security controls** (identity, networking, data, etc.) each with Azure Policy-based recommendations. Defender scores you against MCSB by default, and it aligns with industry frameworks (NIST, CIS). It's the "what good looks like" standard.

**B3. How do you set up governance at scale (management groups, connectors, continuous export)?**
**Answer:** **Onboard subscriptions** to Defender (at the management-group level), configure **continuous export** of alerts/recommendations to **Log Analytics/Event Hubs**, set **workflow automation** (Logic Apps) for auto-remediation, and standardize via **Azure Policy/initiatives**. Use **Sentinel** as the central SIEM for all alerts.

**B4. What is workload protection for servers (Defender for Servers): features like JIT, adaptive controls, VA?**
**Answer:** **Defender for Servers** = EDR (via Defender for Endpoint), **vulnerability assessment** (Qualys/MDE), **JIT** access, **adaptive application controls** (allowlist), **adaptive network hardening** (NSG suggestions), **file integrity monitoring (FIM)**, and **malware detection** — a full server-protection stack.

**B5. How do you triage and respond to alerts (severity, kill chain, automated response)?**
**Answer:** Triage by **severity** + **MITRE ATT&CK** mapping (what stage of the kill chain); investigate in the **alert page** (entities, related alerts) or **Sentinel**; respond via **workflow automation** (Logic Apps — e.g., isolate a VM, revoke access) or **Sentinel playbooks**. Document standard response runbooks per alert type.

**B6. What is the relationship between recommendations, exemptions, and the Secure Score?**
**Answer:** **Recommendations** lower the Secure Score until remediated. **Exemptions** let you waive a recommendation for a scoped resource with a justification + expiry — properly used to avoid score-padding or false positives; overuse hides real risk. Manage exemptions centrally and review periodically.

**B7. How does Defender for Containers protect AKS (runtime, image scanning, Kubernetes posture)?**
**Answer:** **Defender for Containers** = **image scanning in ACR**, **runtime threat detection** on clusters (via the Defender profile/DaemonSet), **Kubernetes posture management** (misconfigurations mapped to CIS/Benchmark), and **network/API** monitoring. Alerts feed Sentinel. Enable at subscription level to cover all clusters.

**B8. What is Defender for APIs / AI workloads / other new plans, and why do they matter?**
**Answer:** Newer plans: **Defender for APIs** (inventory + threat detection for API endpoints — via APIM/Functions), **Defender for AI** (protect LLM/AI workloads — prompt injection, data leakage), **Defender for DevOps** (pipeline security — secret scanning, IaC misconfigs). They extend CSPM/CWP to modern attack surfaces.

**B9. How does Defender for Cloud support multi-cloud (AWS/GCP)?**
**Answer:** Via **connectors** — you onboard AWS/GCP accounts (with the required roles), and Defender applies **CSPM recommendations** (and some workload protection) to those clouds, giving a **single pane of glass** posture across Azure + AWS + GCP (with MCSB/industry standards mapped).

**B10. What is continuous export and workflow automation, and how do you build auto-remediation?**
**Answer:** **Continuous export** streams alerts/recommendations to **Event Hubs/Log Analytics** (for SIEM/retention). **Workflow automation** triggers **Logic Apps** on alert/recommendation events (e.g., auto-apply a fix, notify Teams, open a ticket). Together they turn Defender findings into automated responses.

**B11. How do you measure and report security posture to leadership (Secure Score, compliance, trends)?**
**Answer:** Track **Secure Score** trends, **regulatory compliance** pass/fail per framework, **alert volume/severity** over time, and **remediation SLAs** (MTTR). Export to **workbooks/dashboards** (or Power BI via continuous export) for exec reporting, and set score/alert KPIs per business unit.

**B12. What are the common deployment pitfalls (agent coverage, workspace config, cost)?**
**Answer:** Pitfalls: **agents not deployed** (no telemetry = no alerts), **multiple workspaces** (fragmented view — centralize), **Defender plans not enabled** on key workloads (free tier only = CSPM, no detection), and **cost** (Defender plans are per-resource; right-size coverage, use Sentinel wisely). Verify coverage via the **Defender inventory/coverage** view.

---

## Case C — Scenario

**C1. Scenario:** An exec asks: "How secure are we, and are we getting better?"
**Question:** What do you show and how do you drive improvement?
**Answer:** Show the **Secure Score** trend + **regulatory compliance** status (PCI/NIST/MCSB) + **open recommendations by severity** + **alert/incident trends**. Drive improvement: assign top recommendations to owners with SLAs, remediate highest-impact items (MFA, open ports, public endpoints), and review monthly.

**C2. Scenario:** A VM was brute-forced on RDP (port 3389 open to the internet).
**Question:** How would Defender help detect/prevent, and what do you fix?
**Answer:** **Defender for Servers** would alert on **brute-force attempts**; **JIT** would have kept 3389 closed until needed. Fix: enable **JIT**, remove the 0.0.0.0/0 NSG rule (restrict to corporate CIDR/bastion), review the alert in **Sentinel**, and apply **adaptive network hardening** recommendations.

**C3. Scenario:** An auditor needs PCI DSS compliance evidence for your Azure estate.
**Question:** How do you produce it?
**Answer:** Open the **regulatory compliance** dashboard → **PCI DSS** standard → show the **control pass/fail** per resource, **export** the report, and remediate failing controls (with exemptions documented for justified gaps). Continuous export/retention provides historical evidence for the audit period.

**C4. Scenario:** A container image with a critical vulnerability was deployed to AKS.
**Question:** How does Defender catch it (and prevent recurrence)?
**Answer:** **Defender for Containers** scans images in **ACR** (vulnerability assessment) and at **runtime** on the cluster, alerting on critical CVEs; **Azure Policy** can deny images with critical findings. Prevent: scan in **CI** (before push), enforce **ACR content trust/signing**, and block non-compliant images via policy/admission control.

**C5. Scenario:** You want alerts and recommendations from Defender to flow into Sentinel for automated response.
**Question:** Configure the integration.
**Answer:** In Defender for Cloud, enable **continuous export** (or the Sentinel **connector**) to stream **security alerts + recommendations** to the **Sentinel workspace**; then build **analytics rules** (correlate + escalate) and **playbooks** (Logic Apps) for automated response (e.g., isolate a compromised VM, revoke a user, open a ticket).

**C6. Scenario:** The Secure Score dropped 20 points overnight after a new team deployed resources.
**Question:** Diagnose and remediate.
**Answer:** Check **recently added/changed resources** in the inventory + the **new recommendations** they triggered (likely public endpoints, missing encryption, open NSGs). Remediate the top items, or apply **exemptions** with justification if intentional. Prevent: enforce **Azure Policy** (deny public access, require encryption) so non-compliant resources can't be created, and use **workflow automation** to alert on score drops.
