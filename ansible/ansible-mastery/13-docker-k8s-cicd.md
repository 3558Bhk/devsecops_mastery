# 13 — Ansible with Docker, Kubernetes & CI/CD Pipelines

> ⏱️ **Time to complete: ~2 hrs** — read 30 min · practice 90 min · self-quiz 15 min
> 📦 **Covers:** docker_image / docker_container / docker_compose_v2 · kubernetes.core (k8s, helm) & rollout-status gates · where Ansible fits vs GitOps (Argo/Flux) · the CI/CD pipeline (lint → check → staging → prod) in GitHub Actions/GitLab · runner security, host-key pinning & secrets injection

> **Interview framing:** Modern shops ask: *"Where does Ansible fit in a container/Kubernetes world?"* The answer they want: **Ansible automates the platform and the pipeline; containers/K8s run the workloads.** And: "Ansible vs Terraform" gets a sibling here — "Ansible vs GitOps (Argo/Flux)".

---

## 1. Docker automation with `community.docker`

### 🎬 SCENARIO — Build, ship, and run a containerized app across hosts

```yaml
- name: Build & push image
  hosts: build-node                      # one docker-capable node
  tasks:
    - name: Build image from the repo's Dockerfile
      community.docker.docker_image:
        build:
          path: "{{ playbook_dir }}/../app"          # build context
          platform: linux/amd64
          args:
            APP_VERSION: "{{ app_version }}"
        name: registry.internal/team/app
        tag: "{{ app_version }}"
        source: build
        push: true
      register: image

    - name: Also tag latest
      community.docker.docker_image:
        name: registry.internal/team/app
        tag: latest
        source: local
        push: true

- name: Deploy containers to the fleet
  hosts: docker-hosts
  become: true
  tasks:
    - name: Log in to registry
      community.docker.docker_login:
        registry_url: registry.internal
        username: "{{ lookup('env', 'REGISTRY_USER') }}"
        password: "{{ lookup('env', 'REGISTRY_PASS') }}"   # secrets via env lookup, never YAML

    - name: Run the app container
      community.docker.docker_container:
        name: app
        image: "registry.internal/team/app:{{ app_version }}"
        state: started
        recreate: "{{ recreate_containers | default(true) }}"   # pick up new image
        restart_policy: unless-stopped
        published_ports: ["8080:8080"]
        env:
          APP_ENV: "{{ env }}"
          DB_HOST: "{{ hostvars[groups['db'][0]].ansible_host }}"
        volumes:
          - /opt/app/logs:/var/log/app
        networks: [{ name: appnet }]
        healthcheck:
          test: ["CMD", "curl", "-f", "http://localhost:8080/healthz"]
          interval: 30s
          timeout: 5s
          retries: 3
      register: container

    - name: Verify
      ansible.builtin.uri: { url: "http://localhost:8080/healthz", status_code: 200 }
```

For compose-based stacks (very common on single-box deployments):

```yaml
- name: Deploy the compose stack
  community.docker.docker_compose_v2:          # v2 = the current module; v1 is deprecated
    project_src: /opt/stack
    files: [docker-compose.yml]
    state: present
    build: policy: missing
    pull: policy: always
  environment:
    APP_VERSION: "{{ app_version }}"           # compose file reads ${APP_VERSION}
```

> 💬 **Say:** *"Idempotency carries over: `docker_container` diffs the container spec — image, env, ports — and recreates only on change. I template the compose file for config, and treat `recreate` carefully because it costs a restart even when nothing changed if set carelessly."*

---

## 2. Kubernetes with `kubernetes.core`

### 🎬 SCENARIO — Deploy to K8s from Ansible (when you still have Ansible)

```yaml
- name: Deploy API to K8s
  hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - name: Ensure namespace exists
      kubernetes.core.k8s:
        state: present
        definition:
          apiVersion: v1
          kind: Namespace
          metadata: { name: "api-{{ env }}" }

    - name: Apply rendered deployment + service
      kubernetes.core.k8s:
        state: present
        src: "{{ item }}"
        namespace: "api-{{ env }}"
      loop:
        - templates/k8s-deployment.yaml.j2
        - templates/k8s-service.yaml.j2

    - name: Rollout status gate (wait for the deploy to actually finish)
      kubernetes.core.k8s_info:
        api_version: apps/v1
        kind: Deployment
        name: api
        namespace: "api-{{ env }}"
      register: dep
      until: >
        dep.resources[0].status.readyReplicas | default(0)
        == dep.resources[0].spec.replicas
      retries: 30
      delay: 10

    - name: Install an app via Helm (chart with values from Ansible vars)
      kubernetes.core.helm:
        name: monitoring
        chart_ref: prometheus-community/kube-prometheus-stack
        release_namespace: monitoring
        values:
          grafana:
            adminPassword: "{{ grafana_admin_pass }}"     # from vault/SSM
```

**The honest positioning answer (SDE-3 expected):**

> *"If a team is fully K8s, I'd deploy with GitOps (Argo CD/Flux) — K8s has its own reconciliation, and Ansible would be a second writer fighting the controller. I use Ansible for K8s in specific slots: **cluster bootstrap** (CNI, ingress, cert-manager — before GitOps exists), **platform add-ons with vault lookups**, **migrations/runbooks** (scale down, run DB migration, scale up), and **testing gates** in pipelines. Ansible is the orchestrator around the cluster, not a rival to the controller inside it."*

That paragraph — *bootstrap + runbook + pipeline-gate, not continuous reconciliation* — is exactly the maturity signal.

---

## 3. Ansible inside CI/CD (the pipeline integration question)

### 🎬 SCENARIO — GitHub Actions pipeline: lint → check → deploy

```yaml
# .github/workflows/deploy.yml
name: infra-deploy
on:
  push:
    branches: [main]
    paths: ["ansible/**"]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: pip install ansible-core ansible-lint yamllint
      - run: ansible-lint ansible/ && yamllint ansible/
      - run: ansible-playbook ansible/site.yml --syntax-check -i ansible/inventories/staging

  deploy-staging:
    needs: lint
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - uses: actions/checkout@v4
      - name: Set up SSH + vault material
        run: |
          echo "${{ secrets.DEPLOY_KEY }}" > ~/.ssh/id_ed25519 && chmod 600 ~/.ssh/id_ed25519
          echo "${{ secrets.VAULT_PASS }}" > ~/.vault-pass && chmod 600 ~/.vault-pass
          ssh-keyscan -H staging-web1 >> ~/.ssh/known_hosts 2>/dev/null   # pin host keys!
      - run: |
          cd ansible
          ansible-playbook site.yml -i inventories/staging \
            --vault-id staging@~/.vault-pass

  deploy-prod:
    needs: deploy-staging
    runs-on: ubuntu-latest
    environment: production          # ← requires manual approval in repo settings
    steps: [ ... same, prod inventory + prod vault-id ... ]
```

**Pipeline design talking points:**
- **Three stages minimum:** lint (ansible-lint/yamllint/syntax) → staging → prod (with environment approval gate).
- **Host key pinning** (`ssh-keyscan` into `known_hosts`) — prevents TOFU/MITM on first deploy.
- **Secrets injected by CI's own store** (GitHub `secrets`, GitLab CI variables) → written to ephemeral files with `chmod 600`, never echoed, never committed.
- `--check --diff` output published as PR artifact for review = "Terraform-plan-like" reviewability for Ansible.
- GitLab equivalent: stages `lint → plan(--check --diff) → deploy-staging → deploy-prod`, with `when: manual` for prod.

### What runs where — placement answer

```text
Developer → git push → CI runner (ephemeral, identity-scoped)
                          ├── ansible-lint, yamllint, --syntax-check
                          ├── ansible-playbook --check --diff  (report artifact)
                          └── ansible-playbook apply (staging → approval → prod)
                                     └── SSH (bastion/jump if private) → fleet
```

> *"CI runners get short-lived, least-privilege credentials: SSH deploy keys scoped to target users, vault passwords per env, cloud auth via OIDC federation (no static cloud keys). The runner is the control node — so its hardening IS part of the security model."*

---

## 4. 🎤 SDE-3 Interview Corner

**Q1. Where does Ansible fit in a container world?**
> Host/OS layer (Docker daemon, kernels, registries, log rotation — things containers can't configure about themselves), build/deploy orchestration in pipelines, K8s bootstrap and runbooks. Container-internal config belongs in images (Dockerfile) or K8s manifests — not Ansible tasks inside running containers.

**Q2. `docker_compose` vs `docker_container` module?**
> Container module = per-container desired state, precise diff/recreate control. Compose module = whole-stack lifecycle for people already defining stacks in compose files. Rule: single services on shared hosts → `docker_container`; multi-service stacks → compose; orchestrated fleets → K8s, not Ansible.

**Q3. Why not run Ansible from a container?**
> You do — that's **execution environments** (file 15): Ansible + collections + Python deps packaged as an OCI image, run via `ansible-navigator` or AAP. Reproducible control node = reproducible automation. Hand-rolled `pip install` runner images drift; EEs fix that.

**Q4. Your pipeline deploys fine, but idempotency reports `changed` every run. Debug approach?**
> Diff two runs (`--diff` artifacts), find the churning task — usually a non-deterministic template (timestamp/random), a `shell` without `creates`, a `latest` package pin, or mtime-vs-content comparison. Fix the source of nondeterminism; perma-changed plays destroy the signal value of reports and trigger handlers pointlessly.

**Q5. Ansible vs Argo CD for K8s deploys — pick one and defend it.**
> GitOps for anything K8s-native: continuous reconciliation, drift self-heal, auditable desired state in git. Ansible when: pre-GitOps bootstrap, cross-system orchestration (DB + K8s + DNS in one runbook), org-standard pipelines, or non-K8s components in the same delivery. Not either/or — GitOps for the cluster, Ansible for everything around it.

---

## ⚠️ Common pitfalls

- Registry credentials in playbooks instead of env/vault lookups; `docker_login` writes `~/.docker/config.json` — cleanup on shared runners.
- `docker_container` without explicit `recreate` logic → image updated on registry but container happily running the old one.
- K8s module on runner without `kubernetes.core` collection or `~/.kube/config`/in-cluster auth → "unable to load kubeconfig".
- Pipelines that run full plays without `--check --diff` first — no review surface for infra changes.
- Long-lived CI SSH keys; prefer per-env deploy keys + short-lived certs (or AAP machine credentials).

---

**➡️ Next:** [14 — Custom Modules, Plugins & Testing (Molecule)](14-custom-plugins-testing.md)
