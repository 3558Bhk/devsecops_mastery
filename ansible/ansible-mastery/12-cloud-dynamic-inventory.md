# 12 — Cloud Provisioning & Dynamic Inventory

> ⏱️ **Time to complete: ~2 hrs** — read 30 min · practice 90 min (AWS free tier, or dry-run the configs) · self-quiz 15 min
> 📦 **Covers:** dynamic inventory plugins (aws_ec2: filters, keyed_groups, compose, caching) · provisioning EC2 + the **add_host two-play pattern** · cloud modules (Route53, security groups, S3) · idempotency vs provider APIs · the Ansible↔Terraform boundary question

> **Interview framing:** In cloud environments, static inventory is a lie — instances come and go. They'll ask: *"How does your playbook know about a server created 5 minutes ago?"* Answer: inventory plugins, source-of-truth queries, and the **two-play provisioning pattern**.

---

## 1. Dynamic inventory plugins (the modern way)

### 🎬 SCENARIO — AWS fleet, discovered not maintained

```yaml
# inventories/aws_prod.yml   ← this IS an inventory, not a config OF an inventory
plugin: amazon.aws.aws_ec2
regions:
  - us-east-1
  - us-west-2

# Only running, owned, tagged instances
filters:
  instance-state-name: running
  tag:ManagedBy: ansible

# Build groups automatically from tags/attrs
keyed_groups:
  - key: tags.Environment          # → groups: env_prod, env_staging
    prefix: env
  - key: tags.Role                 # → groups: role_web, role_db
    prefix: role
  - key: instance_type             # → groups by size: t3_micro, m5_large
    prefix: type
  - key: placement.region          # → groups by region
    prefix: aws_region

# Give hosts their private DNS as inventory name, public IP as target
hostnames:
  - tag:Name
compose:
  ansible_host: private_ip_address
  ansible_user: "'deploy'"         # constant via nested quotes trick

# Don't hammer the API on every run
cache: true
cache_plugin: community.general.jsonfile
cache_connection: /tmp/aws_inventory_cache
cache_timeout: 1800

strict: false                      # hosts missing expected tags don't break inventory
```

```bash
ansible-inventory -i inventories/aws_prod.yml --graph
# @all:
#  |--@aws_region_us_east_1: ...
#  |--@env_prod: ...
#  |--@role_web: ...
ansible web -i inventories/aws_prod.yml -m ping          # 'web' = tag Role:web group
```

Auth: standard boto3 chain — env vars, `~/.aws/credentials`, or **instance profile** (preferred on a CI runner inside AWS).

**Other plugins, same idea:** `azure.azcollection.azure_rm`, `google.cloud.gcp_compute`, `community.vmware.vmware_vm_inventory`, `openstack.cloud.openstack`, plus generic ones (`community.general.ini_file`-style sources, Kubernetes, Proxmox, NetBox — a CMDB as inventory is a *great* talking point).

### Inventory scripts (legacy but know it)

Executable that prints JSON with `{"_meta": {"hostvars": {...}}, "groups": {...}}` on `--list`. Plugins replaced scripts in 2.10+; you'll still meet old repos using `ec2.py`. Say: *"We migrated scripts → plugins for caching, FQCN auth, and keyed_groups."*

---

## 2. 🎬 SCENARIO — Provision an EC2 instance and configure it in the SAME run

> *"Create a web server in AWS, then deploy the app to it. This is the most common cloud-interview exercise."*

The key concept: **the instance doesn't exist in your inventory yet** — use the `add_host` module to inject it into an **in-memory, run-only group**.

```yaml
# provision_web.yml
- name: 1. Create the instance
  hosts: localhost
  connection: local
  gather_facts: false
  vars:
    instance_name: web-{{ 100000 | random }}      # unique-ish; use uuid in prod
  tasks:
    - name: Launch EC2
      amazon.aws.ec2_instance:
        name: "{{ instance_name }}"
        key_name: deploy-key
        instance_type: t3.micro
        image_id: ami-0abcdef1234567890           # pin in vars, never inline magic
        region: us-east-1
        vpc_subnet_id: subnet-0123456789abcdef
        security_group: web-sg
        network:
          assign_public_ip: true
        wait: true                                 # block until running
        tags:
          Environment: prod
          Role: web
          ManagedBy: ansible
      register: ec2

    - name: Register the new host in an in-memory group
      ansible.builtin.add_host:
        name: "{{ instance_name }}"
        groups: just_created
        ansible_host: "{{ ec2.instances[0].public_ip_address }}"
        ansible_user: ubuntu

    - name: Wait for SSH to be ready
      ansible.builtin.wait_for:
        host: "{{ ec2.instances[0].public_ip_address }}"
        port: 22
        delay: 5
        timeout: 300

- name: 2. Configure the brand-new instance
  hosts: just_created                    # targets ONLY the host added above
  become: true
  roles:
    - role: nginx
    - role: app_deploy
```

**Talking points:**
- `add_host` = runtime inventory mutation; group `just_created` lives only for this run (dynamic inventory picks the instance up on the NEXT run via tags — two systems, one truth).
- `wait: true` + `wait_for` — boot completion ≠ SSH readiness ≠ cloud-init done; gate each.
- In **Terraform shops**, play 1 belongs to Terraform and Ansible consumes outputs — know both models (below).

### idempotency in cloud modules

```yaml
- amazon.aws.ec2_instance:
    name: web-42
    state: present        # exists with same params → ok; differs → updates
    exact_count: 3        # declarative fleet size!
```

> 💬 *"Cloud modules are idempotent against the provider API — `state: present` diffs desired vs current resource. But creation is NOT replayable identically: re-running a `random`-suffixed name creates a NEW instance. That's why real fleets are declared in Terraform, and Ansible configures them."*

---

## 3. Ansible + Terraform — the boundary question (asked constantly)

| | Terraform | Ansible |
|---|---|---|
| Scope | **Provision** infra (VPC, EC2, RDS, DNS) | **Configure** what's inside (OS, packages, apps) |
| Model | Declarative + **state file** + plan/apply | Declarative-ish, stateless, converge live |
| Mutation | Can destroy/recreate | Mutates in place |
| Lifecycle | Owns resources birth→death | Doesn't track ownership |

```
terraform apply                  # infra exists; outputs private IPs
  └── outputs: web_ips = [...]
       └── ansible dynamic inventory (terraform output → JSON)
            └── ansible-playbook site.yml     # configure everything
```

```bash
# bridge: terraform-inventory or a 5-line script around `terraform output -json`
ansible-playbook -i inv/terraform.py site.yml
```

> 💬 **The answer:** *"Terraform owns creation and destruction; Ansible owns configuration and orchestration. Overlap areas (e.g., `local-exec` provisioners vs Ansible) get decided per team — I keep Terraform pure infrastructure and Ansible pure configuration, sharing state through Terraform outputs as a dynamic inventory source. If someone runs `terraform destroy`, Ansible never fights it — it just configures whatever exists next run."*

---

## 4. 🎬 SCENARIO — Other cloud pieces you should be able to sketch

```yaml
# Route53 DNS record
- community.aws.route53:
    state: present
    zone: internal.example.com
    record: "{{ instance_name }}.internal.example.com"
    type: A
    value: "{{ ec2.instances[0].private_ip_address }}"
    overwrite: true

# Security group (declarative rules)
- amazon.aws.ec2_security_group:
    name: web-sg
    description: web tier
    rules:
      - { proto: tcp, from_port: 443, to_port: 443, cidr_ip: 0.0.0.0/0 }
      - { proto: tcp, from_port: 22,  to_port: 22,  cidr_ip: "{{ office_cidr }}" }

# S3 artifact fetch on target
- amazon.aws.s3_object:
    bucket: artifacts
    object: "releases/app-{{ app_version }}.tar.gz"
    dest: /tmp/app.tar.gz
    mode: get
```

---

## 5. 🎤 SDE-3 Interview Corner

**Q1. Static vs dynamic inventory — how do you decide?**
> Static: bare metal, long-lived VMs, small fleet, wants reviewable diffs in git. Dynamic: any autoscaling/cloud estate — the provider is the source of truth. Hybrid is normal: multiple `-i` sources merge; cloud tags drive grouping, CMDB adds ownership metadata.

**Q2. Playbook run started; 5 new instances were launched during it — does it see them?**
> No — inventory is snapshotted at parse/run start. Next run sees them (with cache TTL caveat). For same-run provisioning, that's exactly what `add_host` exists for.

**Q3. Dynamic inventory cache caused a run against a decommissioned host. Prevent?**
> `cache_timeout` tuned to fleet churn; `--flush-cache` before critical runs; pre_tasks connectivity check (`ping` with `ignore_unreachable` + fail play if any unreachable); cloud-side: filter on instance-state so dead instances never appear.

**Q4. How do you group 2,000 instances meaningfully?**
> `keyed_groups` on tag dimensions (env/role/region/version) + `compose` to normalize connection vars. Governance: tagging standards enforced by CI/SCP policies — inventory quality is a tagging problem, not an Ansible problem.

**Q5. Cost: every `--list-hosts` hits the AWS API 200 times?**
> Cache plugin with TTL; scoped `filters`/`regions`; include `exclude_filters` to shrink result sets; and CI runners share one cached inventory path. Also `strict: false` so tag regressions don't nuke runs.

**Q6. Terraform vs Ansible for creating 50 VMs — why not just Ansible?**
> Ansible can create them, but has no state graph: no drift plan, no dependency ordering, no destroy semantics, no import of manually-made changes. Terraform's plan/apply and state lock exist precisely for that. Ansible's `ec2_instance` is fine for ephemeral test instances — the interview point is knowing where each tool's state model wins.

---

## ⚠️ Common pitfalls

- Forgetting the instance profile/IAM role on the control node → auth errors only in CI.
- `wait: true` on EC2 but no SSH wait → play 2 fails with connection refused (cloud-init race).
- Dynamic inventory cache + autoscaling = running against instances that no longer exist → set `instance-state-name: running` filter AND freshness policy.
- `compose: ansible_user: deploy` (unquoted) — YAML parses `deploy` as a string, but expression-syntax traps; use the `"'deploy'"` nested-quote idiom.
- Ansible creating infra that Terraform owns → next `terraform plan` shows eternal drift; pick one owner per resource.

---

**➡️ Next:** [13 — Docker, Kubernetes & CI/CD](13-docker-k8s-cicd.md)
