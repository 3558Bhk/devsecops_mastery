# 09 — Vault & Secrets (🟢 5 · 🟡 7 · 🔴 6)

> Course ref: [09-vault-secrets.md](../ansible-mastery/09-vault-secrets.md)

## 🟢 Basic

**Q1. What is Ansible Vault?**
> A: Built-in AES256 encryption for variables/files — `ansible-vault create/edit/view/rekey` files, or `encrypt_string` for single values; decrypted only in control-node memory during a run.

**Q2. How do you run a playbook that uses Vault?**
> A: `--ask-vault-pass` (interactive), `--vault-password-file` / `--vault-id prod@path` (scripted). CI uses launcher-injected password files, never committed.

**Q3. What does `ansible-vault encrypt_string` give you?**
> A: A single encrypted value with a `!vault` tag you paste into an otherwise-plaintext YAML file — keeps the file greppable/diffable while the secret stays opaque.

**Q4. What is `no_log: true`?**
> A: Suppresses a task's output (stdout/stderr and rendered args) in logs — mandatory wherever secrets flow through command lines or rendered templates.

**Q5. Where does decryption happen?**
> A: On the control node only. Targets receive plaintext values inside module args over SSH — Vault protects data at rest, not the wire or target-side process listing.

## 🟡 Intermediate

**Q6. Explain vault-ids and the multi-env pattern.**
> A: Labels mapping which password decrypts what: `--vault-id prod@file`, `staging@prompt`. Pattern: per-env encrypted files (all vars `vault_`-prefixed) + plaintext indirection in `vars.yml` (`db_password: "{{ vault_db_password }}"`) — friendly names stay stable across rekeys.

**Q7. encrypt_string vs whole-file encryption — trade-offs?**
> A: Strings: greppable, diffable, mergeable; leaks var-name metadata. Whole files: atomic and simple for many secrets; every edit rewrites the blob → terrible diffs/merges. Teams: strings for few secrets, files for many, external stores for the crown jewels.

**Q8. How do you rotate a vault password?**
> A: `ansible-vault rekey` (per file/set), update the password file/CI secret. With vault-ids you rotate per environment independently — schedule it like any credential rotation.

**Q9. `no_log` limitations?**
> A: You lose failure diagnostics too; at very high verbosity there are bypass avenues (module debug env) — so control-node access is itself part of the secret threat model, and diff output needs care (`diff: false` on secret tasks).

**Q10. Why is `--ask-vault-pass` bad in CI?**
> A: It requires a TTY → hangs pipelines. Use identity-scoped password files created per job (chmod 600, ephemeral) or AAP credentials that inject vault passwords at launch.

**Q11. Where does `--diff` leak secrets?**
> A: Template/copy diffs show before/after content — including rendered secrets. Mitigate: `no_log` (suppresses diff too) or `diff: false` on secret-bearing tasks, and restrict CI artifact access.

**Q12. What's the vars.yml → vault.yml two-layer convention?**
> A: Plaintext file maps friendly names to `vault_`-prefixed names; the encrypted file holds the real values. Consumers never reference vault internals; rekeying/rotating never touches playbook code.

## 🔴 Advanced

**Q13. A secret was committed in plaintext and force-pushed away. What now?**
> A: Assume compromised: **rotate the credential first**, then scrub history (`git filter-repo`), then migrate to Vault/external store, then add secret scanning (gitleaks) to CI. Rotation precedes forensics — forks/clones already have the data.

**Q14. Compare Ansible Vault vs external secrets (HashiCorp Vault / AWS SSM).**
> A: Vault-in-git: versioned with code, no infra; but shared-password auth, no per-read audit, rotation = rekey. External: per-identity auth, TTLs, audit trails, native rotation; needs network/auth setup. Best practice: external lookups for high-value secrets, Vault files only for bootstrap-level config.

**Q15. How do dynamic database credentials work with Ansible?**
> A: Vault's database engine issues short-TTL creds per run via lookup — playbooks never store DB passwords at all; auth is the control node's identity (AppRole/instance role); leaked creds die within the hour by construction.

**Q16. How does AAP/AWX change secret handling?**
> A: Credentials (machine, vault, cloud) are encrypted at rest in the controller DB, injected into execution environments only at job runtime, never rendered in UI/logs, and never live in git. That closes the "password file on a random CI runner" gap.

**Q17. Design secret handling for a pipeline: lint → staging → prod.**
> A: CI secret store injects per-env vault passwords as ephemeral files (600, job-scoped); prod job gated by environment approval; SSH keys are per-env deploy keys (or AAP machine creds); `no_log` on secret tasks; log-scan step fails on accidental secret patterns; rotation runbook documented.

**Q18. What do you do when `no_log` hides a failure you now need to debug?**
> A: Reproduce in a dev environment with the secret swapped for dummy data and `no_log` temporarily off — never ship no_log:false to prod. For prod diagnosis, log sanitized fields explicitly (e.g., register + `debug` of non-secret keys).
