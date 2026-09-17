# 15 — AWX, Ansible Tower & Ansible Automation Platform (AAP)

> ⏱️ **Time to complete: ~1.5 hrs** — read 40 min · explore/whiteboard 50 min · self-quiz 10 min
> 📦 **Covers:** AWX vs Tower vs AAP naming · the object model (projects, inventories, credentials, job templates) · surveys & self-service · workflow templates with approval gates · execution environments & automation mesh · RBAC, audit, ops debugging

> **Interview framing:** "How do you let 40 engineers run automation against prod without giving them SSH?" That's the platform question: **RBAC, self-service, audit trails, schedules, and approval workflows** — Ansible as a product, not a CLI.

---

## 1. The naming map (get this right; it's asked directly)

| | What it is |
|---|---|
| **AWX** | Open-source upstream of Tower. Free, fast-moving, community-supported. |
| **Ansible Tower** | Red Hat's old commercial product (now legacy naming). |
| **Ansible Automation Platform (AAP 2.x)** | Current product: controller (Tower lineage) + **automation hub** (private Galaxy) + **execution nodes / automation mesh** (scale-out runners) + private automation hub + insights/analytics. |
| **Execution Environments (EE)** | Container images (OCI) bundling ansible-core + collections + Python deps — the runner is now a container. Built with `ansible-builder`. |

> 💬 **The 20-second version:** *"AWX is the free upstream; Tower was Red Hat's commercialization; AAP 2+ is the platform: a control plane (controller), a content registry (hub), and containerized execution via automation mesh. The big 2.x shift was execution environments — reproducible, containerized control nodes."*

---

## 2. Core object model (know these terms cold)

```
Organization
 ├── Projects            ← git repos (SCM) containing playbooks/roles
 ├── Inventories         ← static/uploaded/dynamic (cloud credential-backed SCM or custom)
 ├── Credentials         ← machine SSH, vault passwords, cloud keys, SCM tokens
 │                          (encrypted at rest; injected at job runtime — never in playbooks)
 ├── Job Templates       ← "run playbook X against inventory Y with credential Z"
 │     ├── Surveys       ← guided parameter forms (self-service UI)
 │     ├── Schedules     ← cron-like triggers
 │     └── Notifications ← slack/email/webhook on success/failure
 └── Workflow Templates  ← DAG of job templates + approvals + forks on success/failure
Teams → Roles (use/admin/execute/approve) bound to objects = RBAC
```

Execution flow: user (or API) launches Job Template → controller schedules on an **execution node** running the right **EE** container → playbook runs → streamed logs, artifacts, notifications, full audit row.

---

## 3. 🎬 SCENARIO — Self-service deployment with a survey + approval gate

> *"Devs need to deploy their app without Ansible knowledge or prod SSH. Ops keep control. This is the AWX/AAP elevator pitch scenario."*

**Job Template:** `deploy-app` → playbook `playbooks/deploy_app.yml` → inventory `production` (or workflow-scoped) → credentials: machine + vault.

**Survey** (defined on the Job Template):

```json
[
  {
    "question_name": "Application version to deploy",
    "variable": "app_version",
    "type": "text",
    "required": true,
    "default": "latest"
  },
  {
    "question_name": "Environment",
    "variable": "target_env",
    "type": "multiple_choice",
    "choices": ["staging", "production"],
    "required": true
  },
  {
    "question_name": "Enable canary rollout?",
    "variable": "canary",
    "type": "boolean",
    "default": true
  }
]
```

The playbook consumes survey answers as normal extra-vars — same code as CI, CLI, and API:

```yaml
- import_playbook: "{{ target_env | default('staging') }}-deploy.yml"
```

**Workflow Template** (the governance layer):

```
[lint job] → [deploy staging] → (success) → [approval node: prod owners] → [deploy prod]
                     │                                          │
                     └── (failure) → [notify #ops slack] ◀──────┘ (denied → notify requester)
```

The **approval node** is the money feature: prod deploy literally cannot start until an authorized human clicks approve — every click is in the audit log.

**API-first usage** (what teams actually end up doing):

```bash
# launch via API with a token (RBAC-scoped)
curl -X POST https://aap.internal/api/v2/job_templates/42/launch/ \
  -H "Authorization: Bearer $AAP_TOKEN" -H "Content-Type: application/json" \
  -d '{"extra_vars": {"app_version": "1.9.0", "target_env": "production"}}'

# or the collection
ansible localhost -m awx.awx.job_launch \
  -a "name=deploy-app extra_vars={'app_version':'1.9.0'}" 
```

> 💬 **The three-value pitch:** *"Self-service (surveys hide complexity), safety (RBAC + approvals + credentials never leave the vault), audit (who ran what, when, with which vars, full stdout)."* Also the CI integration: pipelines call the API instead of holding SSH keys — **the runner no longer needs fleet credentials at all.**

---

## 4. Execution Environments — why containerized control nodes matter

```bash
# ansible-builder: define what your automation needs
# execution-environment.yml
version: 3
images:
  base_image:
    name: registry.redhat.io/ansible-automation-platform-24/ee-minimal-rhel9:latest
dependencies:
  galaxy: requirements.yml          # collections, pinned
  python: requirements.txt          # boto3, kubernetes, psycopg2...
  system: bindep.txt                # rpm-level deps (gcc, libpq...)
```

```bash
ansible-builder build -t registry.internal/ee/platform-team:1.4.0
ansible-navigator run site.yml --execution-environment-image registry.internal/ee/platform-team:1.4.0
```

Talking points:
- *"Pre-EE pain: 'works on the Tower server' — someone `pip install`ed a library in 2019. EEs make the control node an artifact: versioned, scanned, reproducible, promoted staging→prod like any image."*
- **Automation mesh** = execution nodes placed near hosts (regions/VPCs), connected back to the control plane — solves the "control node in the wrong network" scaling problem from file 11.
- `ansible-navigator` is the CLI that runs playbooks inside EEs locally.

---

## 5. Operational realities (what seniors know)

- **Projects sync from git** — automation code still lives in git; AWX/AAP is the *executor*, not the source of truth.
- **Credentials:** machine creds (SSH key, become password), vault creds, cloud creds (boto-style), custom credential types for anything else. All encrypted (AES) in the controller DB, decryptable only by execution nodes at runtime.
- **Capacity & concurrency:** forks/fleet sizing happens per execution node; job slices split inventories across nodes (job slicing for 10k+ hosts).
- **Schedules** replace cron-on-a-random-server — and their history/audit comes free.
- **Notifications:** Slack/email/webhook per job-template on success/fail; pairs with `block/rescue` alerts (file 08) for task-level detail.
- **When NOT to use it:** one-off debugging (use CLI), or as a git-replacement (never edit playbooks in the UI's source view).

---

## 6. 🎤 SDE-3 Interview Corner

**Q1. AWX vs Tower vs AAP?**
> Upstream (AWX, free, community) → Tower (commercial, legacy name) → AAP 2+ (controller + hub + EEs + mesh). Interviews want: you know AWX is the OSS upstream and EEs are the 2.x game-changer.

**Q2. Design automation for 40 devs, 3 envs, prod approval required.**
> AAP: one org, teams per env role; project from git; inventories per env; job templates + surveys per operation; workflow: lint → staging → approval → prod; notifications to team channels; devs get `execute` on staging templates, `approve`-holders on prod; CI uses tokens + API. Nobody gets SSH; every run is attributed and logged.

**Q3. How do credentials work in the platform vs plain Ansible?**
> Encrypted at rest in controller DB, decrypted only into the EE at job runtime, never rendered in logs/UI, and never present in git. Compare: plain Ansible vault passwords arrive via files/env — the platform closes that operational gap.

**Q4. Job is queued forever. Diagnose?**
> Capacity: all execution nodes' worker slots full (check instance groups/capacity); or EE image pull failing on the node; or inventory plugin hanging (cloud API timeouts) before tasks start; or a dependency job holding a lock. Controller API `/api/v2/jobs/{id}/` shows status + execution_node — that's your first stop.

**Q5. Why not just CI (Jenkins) instead of AWX/AAP?**
> CI optimizes pipelines; AAP optimizes *operations*: standing RBAC, credential custody, inventories with per-env scoping, schedules, approvals, human-triggered ad-hoc runs, audit. Overlap is real — many orgs run both: CI for change-driven deploys, AAP for operational automation and self-service.

---

## ⚠️ Common pitfalls

- Treating AWX as the git repo: playbooks only ever change in git; projects sync — never UI-edited.
- Putting survey vars with business logic conditionals in giant Jinja in one playbook — split plays/roles; surveys are inputs, not logic.
- Granting `admin` org role instead of granular `use`/`execute` on specific templates — RBAC rot.
- Forgetting EE updates when requirements.yml bumps collections → mysterious "module not found" on one node only (mesh skew).
- No notifications on failure → automation runs nobody notices until the incident.

---

**➡️ Next:** [16 — Scenario Cookbook: Six End-to-End Projects](16-scenario-cookbook.md)
