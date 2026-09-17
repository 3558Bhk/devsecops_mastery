# 09 — Ansible Vault & Secrets Management

> ⏱️ **Time to complete: ~1.5 hrs** — read 25 min · practice 60 min · self-quiz 10 min
> 📦 **Covers:** vault CLI (create/edit/view/rekey/encrypt_string) · vault-ids & per-env passwords · the vars.yml→vault.yml best-practice pattern · no_log · external secret managers (HashiCorp Vault, AWS SSM, 1Password) · CI integration · the "secret leaked" response plan

> **Interview framing:** "How do you handle secrets in Ansible?" is a trust question. They're checking whether you'd leak their DB password into git, logs, or CI output. Answer with defense in depth: Vault + no_log + external secret backends + least privilege.

---

## 1. Vault fundamentals

```bash
ansible-vault create group_vars/production/vault.yml     # new encrypted file
ansible-vault edit group_vars/production/vault.yml       # decrypt→$EDITOR→re-encrypt
ansible-vault encrypt secrets.yml                        # encrypt EXISTING plaintext file
ansible-vault decrypt secrets.yml                        # back to plaintext
ansible-vault rekey group_vars/production/vault.yml      # rotate password
ansible-vault view group_vars/production/vault.yml       # read without editing
ansible-vault encrypt_string 's3cr3t' --name 'db_password'   # encrypt ONE value
```

- Default cipher: **AES256** (symmetric, password-based via PBKDF2).
- Encrypted payload has a header `ANSIBLE_VAULT;1.2;AES256;my-vault-id` — version + vault-id label.
- Vault **encrypts data at rest**, but everything is decrypted **in memory on the control node** during a run — it is not end-to-end encryption on targets. Say that; it shows depth.

### Encrypting a single value (better than whole files)

```bash
ansible-vault encrypt_string --name 'db_password' 'hunter2' 
# paste result into a YAML file:
```

```yaml
# group_vars/production/db.yml
db_password: !vault |
  $ANSIBLE_VAULT;1.2;AES256;prod
  3534353362346138363862333738376564663137323564...
```

The file itself stays readable/greppable/diffable; only the value is opaque. 

---

## 2. 🎬 SCENARIO — Multi-env secrets with `vault-id` (the production setup)

> *"Prod and staging must use different vault passwords, different teams hold different passwords, CI needs non-interactive access. How?"*

### The convention: `<env>/group_vars/all/vault.yml` + matching password file

```
inventories/
├── production/group_vars/all/
│   ├── vars.yml          # plaintext: references
│   └── vault.yml         # encrypted: actual secrets
└── staging/group_vars/all/
    ├── vars.yml
    └── vault.yml
```

```yaml
# vars.yml — plaintext layer, points at vaulted names
db_password: "{{ vault_db_password }}"
slack_token: "{{ vault_slack_token }}"

# vault.yml — encrypted layer (all vars prefixed vault_)
vault_db_password: !vault ...
vault_slack_token: !vault ...
```

> This two-layer pattern (`vars.yml` → `vault.yml`) is **the community best practice**: consumers use friendly names; the encrypted file is swappable/rekeyable without touching playbooks.

### Running with vault-ids

```bash
# interactive
ansible-playbook -i inventories/production site.yml --vault-id prod@prompt

# scripted / CI — password in a protected file
ansible-playbook -i inventories/production site.yml \
  --vault-id prod@~/.vault-pass-prod

# multiple vaults in one run (e.g., shared + prod)
ansible-playbook site.yml --vault-id shared@~/.vault-shared --vault-id prod@~/.vault-pass-prod

# old-school single password
ansible-playbook site.yml --ask-vault-pass
```

Password file hygiene:

```bash
echo 'long-random-passphrase' > ~/.vault-pass-prod && chmod 600 ~/.vault-pass-prod
echo '.vault-pass-*' >> .gitignore        # NEVER commit
```

> 💬 **Say:** *"Vault IDs label which password decrypts what — `prod@...` decrypts anything stamped `prod`, `default@...` the rest. That gives per-env key separation: a leaked staging password can't open prod. Rotation is `ansible-vault rekey`, which I schedule like any credential rotation."*

---

## 3. `no_log` — secrets also leak through OUTPUT

```yaml
- name: Set DB password (value must not appear in logs)
  ansible.builtin.shell: |
    psql -c "ALTER USER app WITH PASSWORD '{{ db_password }}';"
  no_log: true                    # suppress task output entirely
  changed_when: false
```

- `no_log: true` hides stdout/stderr AND the rendered command (which contains the secret).
- Debug it with `ANSIBLE_NO_LOG=false`… no — you debug by temporarily converting to a debug task in a dev env; never ship no_log:false.
- Also relevant: `diff` output in `--diff` mode can leak secrets in template changes → consider `diff: false` on secret-bearing template tasks.
- At verbosity `-vvv`, even no_log can be bypassed by module debug env vars — another reason control-node access is itself a secret privilege.

---

## 4. 🎬 SCENARIO — Secrets WITHOUT Vault (external managers — usually the better answer)

> *"Your security team forbids encrypted files in git. Where do secrets live?"*

```yaml
# Option A: HashiCorp Vault lookup (control-node time)
- name: Fetch DB creds from Vault
  ansible.builtin.set_fact:
    db_password: "{{ lookup('community.hashi_vault.hashi_vault',
                     'secret=kv/data/app/db auth_method=approle') }}"

# Option B: AWS SSM Parameter Store / Secrets Manager
- name: Fetch from SSM
  ansible.builtin.set_fact:
    api_key: "{{ lookup('amazon.aws.aws_ssm', '/prod/api/key', decrypt=true, region='us-east-1') }}"

# Option C: one-time dynamic DB creds (Vault database engine — the senior answer)
- name: Generate 1h TTL postgres credential
  community.hashi_vault.hashi_vault:
    ...

# Option D: OS keyring / 1Password / Bitwarden lookups for operator convenience
api_token: "{{ lookup('community.general.onepassword', 'API token', vault='Infra') }}"
```

> 💬 **The answer to give:** *"Vault is fine for secrets that live with the code. But best practice is externalizing to a secrets backend with audit logs, TTLs, and rotation — Vault/SSM lookups. Then Ansible holds no long-lived secrets at all: the playbook references a path, auth happens via instance role/AppRole, and the secret material is fetched at run time. For CI, the runner's identity authorizes the fetch — no vault password files to babysit."*

**Comparison table to rattle off:**

| | Ansible Vault | External (Vault/SSM) |
|---|---|---|
| Storage | Encrypted blobs in git | Central server w/ audit |
| Rotation | `rekey` + redeploy | Native, often automatic |
| Auth | Shared password(s) | Per-identity (IAM/AppRole) |
| Audit | ❌ (git history only) | ✅ per-read |
| Blast radius of leak | Everything under that password | Single path, revocable |

---

## 5. CI/CD integration (preview of file 13)

```yaml
# GitHub Actions snippet
- run: |
    echo "$VAULT_PASS_PROD" > ~/.vault-pass-prod
    chmod 600 ~/.vault-pass-prod
    ansible-playbook -i inventories/production site.yml --vault-id prod@~/.vault-pass-prod
  env:
    VAULT_PASS_PROD: ${{ secrets.VAULT_PASS_PROD }}   # injected by CI secret store
```

Rules: password files ephemeral (created per job, never committed), least-privilege CI identities, `no_log` everywhere secrets flow, and consider AAP/AWX **credential types** which inject vault passwords at launch without any file (file 15).

---

## 6. Operational checklist (recite this)

1. **Never** commit plaintext secrets — pre-commit hook + `ansible-vault view` in code review for any `!vault`.
2. `vault.yml` files only contain `vault_`-prefixed vars; plaintext indirection in `vars.yml`.
3. Per-env vault passwords; separate team ownership; rekey on offboarding.
4. `no_log: true` on any task that renders secrets into command lines or templates.
5. Tight file modes (`0600`/`0640`) on secret files on targets; dedicated service users.
6. Prefer **external secret lookups** for anything high-value; Vault password = last-resort bootstrap.
7. Enable `ANSIBLE_DISPLAY_OK_HOSTS=false`-style noise reduction… more importantly: centralize run logs (AAP) so `no_log` suppression is actually auditable.
8. Rotate: vault passwords quarterly; dynamic DB creds per-run if possible.

---

## 7. 🎤 SDE-3 Interview Corner

**Q1. How does Vault encryption actually work?**
> AES256-CTR of the YAML payload, key derived from your password via PBKDF2 with salt; header carries format version + vault-id label. Decryption happens only on the control node; targets see plaintext values in module args (over SSH) — so protect the wire (standard SSH) and control node, not just git.

**Q2. Someone committed a secret in plaintext and force-pushed. What now?**
> Assume compromised: rotate the credential FIRST (deleting history doesn't un-leak forks/clones), then scrub history (`git filter-repo`), then move to Vault/external, then add pre-commit secret scanning (gitleaks) to CI to prevent recurrence. Order matters — rotation before forensics theater.

**Q3. `encrypt_string` vs whole-file encryption — trade-offs?**
> Strings: file stays greppable/diffable/mergeable; risk = neighbors in the file leak metadata (var names). Whole files: atomic, simpler for 50 secrets; risk = any edit rewrites the whole blob → terrible diffs, merge conflicts. Teams usually end up: strings for few secrets, files for many, external lookups for the crown jewels.

**Q4. How do you run a playbook that needs secrets in a fully air-gapped environment?**
> Shipped password files via controlled channel (or HSM/yubikey-stored), Vault inside the enclave, or AAP with credential providers. Also `--ask-vault-pass` interactive for human ops. The real answer: secrets must live inside the air gap — nothing secret crosses it.

**Q5. Playbook prints the password into the job log. Root causes?**
> Missing `no_log` on a task echoing it (debug/shell), `--diff` showing template content, or verbosity flags in CI. Fix all three; add log-scanning CI step that fails on `vault`-decrypted markers; treat the secret as rotated.

---

## ⚠️ Common pitfalls

- Committing `.vault-pass` (or leaving it root-readable) — automate the chmod, gitignore it, verify in CI.
- One vault password for everything — rotation/delegation become impossible; use vault-ids.
- `no_log: true` on tasks where you NEED failure output — you lose the error message too; log sanitized parts instead.
- Believing Vault protects targets — module args still contain plaintext; SSH and become logs are in scope.
- `--ask-vault-pass` in CI (needs TTY — hangs forever); use password files or launcher-injected credentials.

---

**➡️ Next:** [10 — Rolling Deploys, Async & Strategies](10-rolling-deploys-async.md)
