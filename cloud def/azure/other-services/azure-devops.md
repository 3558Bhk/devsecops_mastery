# Azure DevOps — Interview Questions

> **Cloud:** Azure (Other Services) · **Category:** DevOps / CI-CD · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~8 min

---

## JSON File Format

Azure DevOps **pipelines are YAML**, but the REST API and extensions use JSON — e.g. **task.json** (custom task manifest) and pipeline/build definitions exported via REST.

```json
{
  "id": "00000000-0000-0000-0000-000000000000",
  "name": "MyBuildTask",
  "friendlyName": "My Build Task",
  "description": "A custom pipeline task",
  "category": "Build",
  "execution": {
    "Node10": { "target": "index.js", "argumentFormat": "" }
  },
  "inputs": [
    { "name": "apiKey", "type": "string", "label": "API Key", "required": true }
  ]
}
```

**Key fields:** `id` / `name` · `execution` (runtime + entry point) · `inputs[]` (task parameters). Pipeline definitions fetched via the REST API (`GET .../build/definitions/{id}`) are JSON; `azure-pipelines.yml` is YAML.


## Case A — Basic

**A1. What is Azure DevOps?**
**Answer:** Microsoft's suite of DevOps tools: **Boards** (work tracking), **Repos** (Git), **Pipelines** (CI/CD), **Test Plans** (testing), and **Artifacts** (package feeds).

**A2. What is a pipeline (build vs release)?**
**Answer:** A **build (CI) pipeline** compiles/tests code and produces artifacts; a **release (CD) pipeline** deploys those artifacts to environments. Modern **YAML pipelines** can do both (multi-stage).

**A3. What is the difference between classic and YAML pipelines?**
**Answer:** **YAML pipelines** are **code-as-config** (versioned, reviewed, portable). **Classic** pipelines are GUI-configured (legacy). YAML is the modern recommendation.

**A4. What is an agent?**
**Answer:** The compute that runs pipeline jobs — **Microsoft-hosted** (managed VMs) or **self-hosted** (your machines, for private network/special tools).

**A5. What is a stage, job, and step?**
**Answer:** **Stage** = a phase (build → test → deploy). **Job** = runs on an agent (parallelizable). **Step** = a task/script within a job. This is the pipeline hierarchy.

**A6. What are service connections?**
**Answer:** Authenticated links from Azure DevOps to external services (Azure subscription, ACR, GitHub) used by pipelines to deploy — with scoped permissions.

**A7. What is a variable group and a secure variable?**
**Answer:** **Variable groups** store shared pipeline variables (per environment); **secure/secret variables** are encrypted (masked in logs) — often backed by **Key Vault**.

**A8. What is a trigger?**
**Answer:** What starts a pipeline: **CI triggers** (on code push/PR), **schedule triggers** (cron), **pipeline triggers** (another pipeline), or manual.

**A9. What are Artifacts?**
**Answer:** A package-management service — **feeds** for NuGet/npm/Maven/Python/Universal packages, shared across pipelines/teams.

**A10. What is a pull request and branch policy?**
**Answer:** A **PR** proposes code changes for review; **branch policies** enforce requirements (reviews, builds passing, work-item links) before merge — quality gates.

**A11. What is the difference between Azure DevOps and GitHub Actions?**
**Answer:** Both CI/CD + Git; Azure DevOps = full suite (Boards/Test Plans/Artifacts) with deep Azure integration; GitHub Actions = GitHub-native, YAML workflows, huge community. Many orgs use both or either.

**A12. What is an environment in a pipeline?**
**Answer:** A named deployment target (e.g., `dev`, `prod`) with **approvals, checks, and deployment history** — the CD gate.

**A13. What are approvals and checks?**
**Answer:** Gates before deploying to an environment: **manual approvals**, **branch controls**, **business hours**, **Azure Monitor alerts**, etc. — safety for production.

**A14. What is a deployment group?**
**Answer:** A set of **self-hosted target machines** for classic release pipelines (e.g., deploy to on-prem VMs) — now largely replaced by environments/VMs.

**A15. What is a task vs a template?**
**Answer:** A **task** = a packaged action (e.g., `AzureCLI@2`, `PublishBuildArtifacts@1`). A **template** = a reusable YAML snippet (steps/jobs/stages) included in pipelines — DRY for pipelines.

---

## Case B — Advanced (Senior)

**B1. Explain a modern multi-stage YAML pipeline: stages, jobs, conditions, and dependencies.**
**Answer:** A YAML pipeline defines **stages** (build → deploy dev → deploy prod) with **jobs** (parallel/sequential via `dependsOn`), **steps** (tasks/scripts), and **conditions** (`condition: succeeded()`) for gating. **Templates** parameterize reusable logic. This gives code-reviewed, versioned CI/CD.

**B2. How do you implement blue-green / canary deployments with Azure DevOps?**
**Answer:** Blue-green: deploy to a **staging slot** (App Service) → validate → **swap**. Canary: deploy to a small % (via App Service/Front Door weighted routing or AKS with progressive rollout) and **auto-rollback on alerts**. Azure DevOps **environments + approvals** gate the progression, and **release gates** (Azure Monitor) auto-abort on errors.

**B3. How do you manage secrets in pipelines (variable groups, Key Vault, service connections)?**
**Answer:** Link a **Key Vault** to a **variable group** (secrets pulled at runtime, never in YAML), use **secret variables** (masked), and **service connections** for Azure auth (managed identity/workload federation preferred). Never commit secrets; grant the pipeline's identity least-privilege Key Vault access.

**B4. What are release gates and how do they use Azure Monitor for auto-rollback/approval?**
**Answer:** **Release gates** (or **checks** in YAML) query **Azure Monitor alerts/metrics** (e.g., "no 5xx in last 5 min") before/after a stage; if the gate fails, the release **stops or rolls back** — automated quality/health gates replacing manual checks.

**B5. How do you secure Azure DevOps itself (permissions, branch policies, secret scanning)?**
**Answer:** **RBAC** (project/team permissions), **branch policies** (min reviewers, build validation, restrict pushes), **secret scanning** (CredScan/Defender for DevOps), **pipeline security** (restrict agents, protect service connections), **audit logs** (track changes), and **SSO/Conditional Access** (Entra ID) for org access.

**B6. What is an agent pool and how do you choose Microsoft-hosted vs self-hosted (and secure self-hosted)?**
**Answer:** **Microsoft-hosted** = managed, ephemeral, internet-reachable (simplest). **Self-hosted** = your VMs (private network, custom tools, but you patch/secure them). Secure self-hosted: isolated VNet, minimal permissions, ephemeral/scaled agents, and restricted access to service connections.

**B7. How do you implement infrastructure-as-code with Azure DevOps (ARM/Bicep/Terraform)?**
**Answer:** Pipelines run **Bicep/ARM** (`AzureResourceManagerTemplateDeployment`) or **Terraform** tasks to provision infra, with **state/plan review**, **staging environments**, and **approvals** before apply. Terraform uses remote state (Storage) + plan gating; Bicep uses `what-if`/validation. Infra changes go through the same PR/pipeline flow as code.

**B8. How do you do continuous testing (unit, integration, code coverage, quality gates)?**
**Answer:** The build runs **unit tests + code coverage**, **static analysis** (SonarQube), **security scanning** (CredScan/Dependabot-style), and **integration tests** in later stages; **quality gates** (coverage %, no high-severity issues) **fail the build/PR** if unmet. Publish test results to the pipeline for visibility.

**B9. What is the artifact promotion model (build once, deploy many) and why does it matter?**
**Answer:** Build the artifact **once**, then **promote the same artifact** through environments (dev → staging → prod) with config injected per environment (variables, Key Vault). This ensures what's tested in staging is **exactly** what ships to prod — no rebuild risk.

**B10. How does Azure DevOps integrate with AKS (deployments, progressive delivery)?**
**Answer:** Pipelines build container images → push to **ACR** → deploy to **AKS** via `kubectl`/Helm/`KubernetesManifest` tasks, using **service connections**. For progressive delivery: **canary deployments** (Flagger) or **blue-green** with the **Kubernetes** tasks + manual gates/rollback on alerts.

**B11. What are the parallel jobs / licensing considerations at scale?**
**Answer:** Azure DevOps limits **parallel jobs** (one free Microsoft-hosted job; more via paid parallel jobs or self-hosted agents, which are free in terms of job licensing but you pay for the VMs). Plan agent capacity for CI queue times; use self-hosted for private/parallel-heavy workloads.

**B12. How do you audit and govern pipelines at enterprise scale (templates, policies, required checks)?**
**Answer:** Enforce **required pipeline templates** (a central `deploy.yml` template with security steps) via `extends`, **required checks/approvals** on production environments, **service-connection restrictions**, **branch policies**, and **audit logs**. Centralize common steps (security scans, artifact promotion) in shared templates so teams can't bypass controls.

---

## Case C — Scenario

**C1. Scenario:** A team deploys manually via scripts on a VM; releases are error-prone and unrepeatable.
**Question:** Modernize with Azure DevOps.
**Answer:** Move to **YAML pipelines**: source in **Repos**, **CI** build (compile + test + package) → **artifact**, **CD** stages (dev → staging → prod) with **environments + approvals**, deploying via **Bicep/Terraform** (infra) + **App Service/K8s** tasks. Secrets via **Key Vault variable groups**. Everything versioned, reviewed, repeatable.

**C2. Scenario:** A bad release went to prod with no way to quickly revert.
**Question:** Design for safe rollback.
**Answer:** **Build once, deploy many** (promote the same artifact), deploy via **slots** (App Service swap-back = instant rollback) or **image tags** (AKS — re-deploy previous tag), keep **previous artifacts in Artifacts** for re-deploy, and add **release gates** (Azure Monitor alerts) so failing releases **auto-abort**. Document a rollback runbook.

**C3. Scenario:** A pipeline needs to deploy to a private AKS cluster that has no public API server.
**Question:** How do you run the pipeline?
**Answer:** Use a **self-hosted agent inside the VNet** (or connected via VPN/ExpressRoute) so the pipeline can reach the **private AKS** API server, with a **service connection** to the cluster. Keep the agent pool secured (private, minimal permissions). Microsoft-hosted agents can't reach private endpoints directly.

**C4. Scenario:** A compliance team requires human approval before any production deployment and an audit trail.
**Question:** Implement.
**Answer:** Add a **production environment** with **manual approvals** (specific approvers/groups) and **checks** (e.g., business-hours, branch control); every deployment records **who approved, when, and the result** in the **environment's deployment history** + **audit logs**. Combine with a required **deployment template** for consistency.

**C5. Scenario:** Secrets were committed to a repo, and a secret scan must block future PRs.
**Question:** Set it up.
**Answer:** Enable **secret scanning** (GitHub Advanced Security/Defender for DevOps or CredScan task in the pipeline) as a **required check** on PRs via **branch policy** — PRs with detected secrets fail. Rotate the leaked secrets, and enforce **Key Vault-linked variable groups** so secrets never live in code.

**C6. Scenario:** You must deploy the same app to 10 different customers with per-customer configuration.
**Question:** Design the pipeline.
**Answer:** **Build once** (a single artifact), then a **multi-environment CD** (or a parameterized template) that deploys the same artifact to each customer environment with **per-environment variables** (variable groups/Key Vault per customer) and **approvals** per customer. Use a **template** to define the deploy steps once and loop over customers.
