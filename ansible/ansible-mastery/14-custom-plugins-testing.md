# 14 — Custom Modules & Plugins + Testing (Lint, Molecule)

> ⏱️ **Time to complete: ~3 hrs** — read 30 min · practice (write a module + a Molecule scenario) 150 min · self-quiz 15 min
> 📦 **Covers:** custom module with AnsibleModule (JSON contract, argument validation, check mode, DOCUMENTATION strings) · filter/lookup/callback plugins · ansible-lint as CI policy · Molecule role testing incl. the idempotence step · sharing code via collections

> **Interview framing:** At SDE-3 you'll be asked *"What do you do when no module exists?"* — answer: write a custom module (correctly, with `AnsibleModule`), or a filter/lookup/callback plugin. And the maturity question: *"How do you test playbooks?"* — lint in CI, `--check` in pipelines, **Molecule** for roles.

---

## 1. Custom module — the correct skeleton

When no module fits (internal REST API, proprietary appliance), write one. It's **just Python** with a contract: consume JSON args, print JSON result.

```python
# library/app_health.py        ← next to your playbook (or in a collection)
#!/usr/bin/python
from __future__ import annotations

DOCUMENTATION = r"""
---
module: app_health
short_description: Check a deployment's health endpoint
options:
  url:
    description: Health endpoint URL.
    type: str
    required: true
  expected:
    description: Required status code.
    type: int
    default: 200
  retries:
    description: How many times to retry.
    type: int
    default: 5
author: ["platform-team"]
"""

EXAMPLES = r"""
- name: Wait until healthy
  app_health:
    url: http://localhost:8080/healthz
    retries: 10
"""

RETURN = r"""
status:
  description: Last HTTP status observed.
  type: int
"""

import time
import urllib.request

from ansible.module_utils.basic import AnsibleModule


def run_module():
    module_args = dict(
        url=dict(type="str", required=True),
        expected=dict(type="int", default=200),
        retries=dict(type="int", default=5),
    )

    result = dict(changed=False, status=0)

    module = AnsibleModule(
        argument_spec=module_args,
        supports_check_mode=True,          # declare it — CI runs --check!
    )

    if module.check_mode:
        module.exit_json(**result, msg="would have probed (check mode)")

    last_error = None
    for _ in range(module.params["retries"]):
        try:
            with urllib.request.urlopen(module.params["url"], timeout=5) as resp:
                result["status"] = resp.status
                if resp.status == module.params["expected"]:
                    module.exit_json(**result, msg="healthy")
                last_error = f"status {resp.status}"
        except Exception as e:                       # noqa: BLE001
            last_error = str(e)
        time.sleep(2)

    module.fail_json(msg=f"unhealthy after retries: {last_error}", **result)


def main():
    run_module()


if __name__ == "__main__":
    main()
```

Use it like any module:

```yaml
- name: Wait until app is healthy
  app_health:
    url: "http://localhost:8080/healthz"
    retries: 10
  register: health
```

**The contract points to narrate:**
- `AnsibleModule` handles **argument parsing, validation (types/choices/required), and check-mode plumbing** — never parse args yourself.
- `exit_json(changed=...)` vs `fail_json(msg=...)` — the only two exits; `changed` drives handlers/reports.
- `DOCUMENTATION`/`EXAMPLES`/`RETURN` strings aren't decoration — `ansible-doc` renders them, `ansible-test sanity` validates them, and they're what makes a module *reviewable*.
- Placement: `library/` beside the playbook (auto-loaded), `library/` inside a role (role-scoped), or properly inside a collection (`plugins/modules/`).
- **Before writing one, check:** does `uri`+`until` cover it? Is there a generic `community.general.*` module? Custom code = maintenance debt; write it for genuinely missing capability.

---

## 2. Other plugin types (know one example each)

**Filter plugin** — team-wide Jinja2 helpers:

```python
# filter_plugins/net_filters.py
def cidr_host(network, index):
    """Return the Nth host of a CIDR: cidr_host('10.0.0.0/24', 5) -> '10.0.0.5'."""
    import ipaddress
    return str(ipaddress.ip_network(network)[int(index)])

class FilterModule(object):
    def filters(self):
        return {"cidr_host": cidr_host}
```

```yaml
- debug: { msg: "{{ '10.0.0.0/24' | cidr_host(groups['web'].index(inventory_hostname)) }}" }
```

**Lookup plugin** — pull data from your internal systems at control-node time:

```python
# lookup_plugins/itsm.py — e.g. fetch change-window data
from ansible.plugins.lookup import LookupBase

class LookupModule(LookupBase):
    def run(self, terms, variables=None, **kwargs):
        # terms[0] = CR id; call your ITSM API here
        return [f"CR-{t}" for t in terms]
```

**Callback plugin** — custom output/notifications (Slack on failure, metrics to Prometheus pushgateway).

**Inventory plugin** — file 12's `aws_ec2` is exactly one; custom ones talk to your CMDB.

> 💬 **Say:** *"Modules change state on targets; plugins extend Ansible itself. The split decides where code goes. And check-mode support is the dividing line between a toy and a production module — CI runs everything with `--check`."*

---

## 3. Static analysis — lint gates every repo should have

```bash
pip install ansible-lint yamllint
ansible-lint                     # Ansible-aware: idempotency, FQCN, naming, risky shell
yamllint .                       # pure YAML hygiene
ansible-playbook site.yml --syntax-check
```

`ansible-lint` rules that catch real production bugs:

| Rule | Catches |
|---|---|
| `command-instead-of-shell` | needless `shell` (injection, non-idempotent) |
| `command-instead-of-module` | `command: curl` → should be `uri` |
| `risky-shell-pipe` | `\| sudo` / curl-pipe-bash patterns |
| `risky-file-permissions` | files created without explicit `mode` |
| `fqcn[action-core]` | non-fully-qualified module names |
| `name[template]` | task names containing `{{ }}` (log-formatting bug) |
| `no-changed-when` | bare `command` tasks reporting false changes |
| `no-handler` | task right after another named "do X then restart" — should be a handler |

`.config/ansible-lint.yml` — the *policy* file (what you allow and why):

```yaml
profile: production           # built-in strictness level
exclude_paths: [.cache/, .venv/]
skip_list: []                 # prefer documenting exceptions over blanket skips
warn_list:
  - experimental
kinds:
  - playbook: "**/*.yml"
  - tasks: "roles/**/tasks/*.yml"
```

> 💬 **Say:** *"Lint is where playbook quality scales past one person — I treat ansible-lint warnings as build failures with documented exceptions, because every 'temporary' skip becomes permanent."*

---

## 4. Molecule — testing ROLES (the real answer to "how do you test Ansible?")

Molecule spins up disposable containers/VMs, runs your role against them, and verifies **behavior**, not syntax.

```bash
pip install molecule molecule-plugins[docker] ansible-lint
cd roles/nginx
molecule init scenario default --driver-name docker
```

Scenario structure:

```
roles/nginx/molecule/default/
├── molecule.yml       # platform matrix + driver + lint config
├── converge.yml       # the play that applies your role
├── verify.yml         # assertions on the RESULTING system
└── create.yml / destroy.yml   # (docker driver handles these)
```

```yaml
# molecule.yml
---
dependency: { name: galaxy }
driver: { name: docker }
platforms:
  - name: nginx-ubuntu
    image: geerlingguy/docker-ubuntu2204-ansible
    pre_build_image: true
    privileged: true
provisioner: { name: ansible }
verifier: { name: ansible }
```

```yaml
# converge.yml — apply the role exactly as production would
---
- name: Converge
  hosts: all
  become: true
  roles:
    - role: nginx
      vars:
        nginx_vhosts:
          - name: test.local
            port: 80
            upstream: "app:9000"
```

```yaml
# verify.yml — test BEHAVIOR
---
- name: Verify
  hosts: all
  become: true
  tasks:
    - name: Nginx config is valid
      ansible.builtin.command: nginx -t
      changed_when: false

    - name: Vhost file exists and is managed
      ansible.builtin.stat:
        path: /etc/nginx/conf.d/test.local.conf
      register: vhost
    - ansible.builtin.assert: { that: vhost.stat.exists }

    - name: Server responds on port 80
      ansible.builtin.uri:
        url: "http://localhost/"
        status_code: 200
      register: resp
      retries: 5
      delay: 2

    - name: Re-run converge → idempotency check (THE test)
      # molecule idempotence step does this automatically:
      # second run must show changed=0
```

```bash
molecule test                  # create → converge → idempotence → verify → destroy
molecule converge              # iterate fast while developing
molecule login --host nginx-ubuntu   # debug inside the test container
```

**The idempotence step deserves its own sentence:** Molecule runs converge **twice** and fails the build if the second run reports `changed > 0`. That's automated enforcement of Ansible's core promise.

CI wiring: one job per platform matrix (`ubuntu`, `rocky`), `molecule test` per changed role only (`paths` filters), plus lint jobs. Full-fleet testing isn't the goal — **fast, disposable, behavioral** is.

---

## 5. 🎤 SDE-3 Interview Corner

**Q1. No module exists for our internal API. Options?**
> Escalate first: `uri` + `failed_when` often suffices; `community.general` may have it. Otherwise custom module with `AnsibleModule` (validation, check mode, JSON contract), placed in a shared collection, tested, documented. Avoid raw `shell`+curl — no idempotency, no check mode, no portability.

**Q2. How do you test playbooks?**
> Layers: `yamllint`/`ansible-lint` (static) → `--syntax-check` (parse) → `--check --diff` against staging (plan-like) → **Molecule** for roles (behavior + idempotency in disposable containers) → canary wave in prod with health gates (the real test). "Testing Ansible" = testing *outcomes*, second-run idempotency, and blast radius — not just YAML validity.

**Q3. Why does `supports_check_mode` matter in custom modules?**
> Without it, `--check` runs skip your module (Ansible assumes it can't be simulated) or worse, your module mutates during a check run if you ignore the flag. `module.check_mode` lets you no-op safely — CI pipelines running `--check` depend on this contract.

**Q4. Molecule vs just running on staging?**
> Staging proves integration (real LBs, real DNS), but it's shared, stateful, slow, and "someone else's config got there first". Molecule is hermetic: exact role + exact vars + fresh container, idempotency-enforced, minutes per run, per-platform matrix. Both; they answer different questions.

**Q5. How do you share a filter plugin across 40 repos?**
> Team collection (`plugins/filter/`) versioned and pinned in each repo's `requirements.yml` — same distribution path as modules/roles. Loose `filter_plugins/` dirs die at repo #4.

---

## ⚠️ Common pitfalls

- Writing a custom module that uses `print()` — stdout pollution breaks the JSON contract; only `exit_json`/`fail_json` may print.
- Custom module without check-mode support quietly corrupting state during `--check` CI runs.
- Skipping `DOCUMENTATION` → `ansible-test sanity` fails and nobody can use your module correctly.
- Molecule tests that only assert "no errors" — verify behavior (`uri`, `stat`, config validity), and always the second-run idempotency.
- Blanket `skip_list` on ansible-lint — lint theater; document per-line exceptions instead.

---

**➡️ Next:** [15 — AWX / Ansible Automation Platform](15-awx-aap.md)
