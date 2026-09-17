# Case 3 — Scenario-Based Questions (bullet Q&A with flows)

> Level: **scenario-based / real-time** ("in your last project, how did you handle…")
> Format: situation → what you would do (step flow) → the point the interviewer is checking

---

### S1. Your teammate's laptop died mid-`apply`. Now every `plan` in the team is stuck "Acquiring state lock…". What do you do?

- **Situation**: state lock (DynamoDB / Azure lease) held by a dead process.

- Flow:
  1. Confirm with the teammate that their machine is actually dead (no zombie terminal session).
  2. Check CI history — make sure no pipeline `apply` is still running (they look the same from the lock's point of view).
  3. Inspect the lock record — AWS: `aws dynamodb get-item` on the lock table; note the `ID` (the lock path) and who created it.
  4. **Force-release the lock** — `aws dynamodb delete-item` (or delete the lease blob on Azure). This is the only dangerous step — do it once, deliberately, and tell the team.
  5. Run `terraform plan` to confirm the state is readable and consistent.
  6. If the dead apply was **part-way through** (some resources created, some not): state was last saved *before* the apply, so `plan` will show the not-yet-created resources → `apply` resumes and finishes the job. That's the point of state: **crashes recover, they don't corrupt.**

- What's being checked: do you know locking is a *lease*, that force-release is safe when (and only when) nothing is running, and that a crashed apply resumes from state.

---

### S2. A resource was deleted out-of-band (someone dropped the bucket in the console to "free up space"). Your next `plan` says "No changes." What do you do?

- **Situation**: drift — the real world no longer matches state, but the plan looks innocent.

- Flow:
  1. Don't celebrate the empty plan — run `terraform plan -refresh-only` (or just `plan`; modern TF refreshes). It re-reads the cloud and will now report the bucket as **gone**.
  2. Decide intent:
     - **It should exist** (it was your app's asset bucket!) → plain `apply` recreates it. Then: chase *who* deleted it (CloudTrail / Activity Log), because the next deploy's data is gone until re-uploaded.
     - **It was deliberately retired** → `terraform state rm aws_s3_bucket.old` so Terraform stops expecting it; remove the block from code.
  3. Put a **drift detector** in place — a scheduled nightly `plan` in CI that pages you when real-world ≠ code. That's how you catch it in hours, not when the app breaks.

- What's being checked: you know state is a *cache of the world*, that "No changes" can be a lie after manual edits, and that you fix the *process* (drift alerts), not just the symptom.

---

### S3. You need to move a production RDS instance to a new instance type, and the `plan` shows "forces replacement" (destroy + create). Walk me through your plan.

- **Situation**: a stateful resource, a change that can't be done in place.

- Flow:
  1. **Understand why**: some instance types can't be changed in place (crossing architectures, e.g. x86 → Graviton, or changing the engine version). Verify with the plan's "because…" line.
  2. **Never destroy-and-recreate prod RDS casually** — data lives there.
  3. Choose the safe path:
     - **Preferred — in-place where possible**: most instance-type changes *are* in place (`modify-instance`); double-check the attribute that's forcing replacement (maybe it's `db_name` or `availability_zone` that changed, not the size).
     - **If replacement is unavoidable**: snapshot/backup first (automated + manual), then `terraform apply -replace=aws_db_instance.main` (or `taint`) with `create_before_destroy` where supported, pointed at the **restore-from-snapshot** path (a new instance created from the old snapshot, cutover of the endpoint, then destroy the old).
     - Do it in a **maintenance window**, with the app pointed at the new endpoint only when ready.
  4. Post-check: connect, verify data, monitor error rates, then clean up the snapshot policy.

- What's being checked: you read the *reason* in the plan, you protect data before any destructive change, and you know RDS has restore/snapshot mechanics that make "replacement" survivable.

---

### S4. You have one `main.tf` that works for dev. Now you need the same thing in staging and prod, with different sizes and regions. How do you structure this?

- **Situation**: multi-environment without copying-pasting the whole repo.

- Flow:
  1. **Keep one source of truth for the infrastructure** — a module (or root) that takes all the differences as **inputs**: `environment`, `region`, `instance_size`, `db_class`, `name_prefix`.
  2. **One state per environment, forever** — `envs/dev/terraform.tfvars` → backend key `dev/terraform.tfstate`; `envs/staging/…` → `staging/…`; prod → `prod/…`. Each env folder is tiny: vars file + the same module call.
  3. **CI applies per environment**:
     - PR → `plan` against dev (or a throwaway state).
     - Merge to `release` branch → apply dev + staging.
     - Tag / manual approval → apply prod (protected environment, approvers required).
  4. **Prod is stricter by construction**: prod vars pin smaller blast radius (smaller defaults where sane), CI role for prod has *less* permission, and prod applies require a human click.
  5. Test the promotion order: every env that gets closer to prod runs the *same code* that already proved itself one step closer.

- What's being checked: state-per-env as an invariant, differences expressed as inputs (not copy-paste), and promotion/approval design.

---

### S5. You're onboarding: the team's Terraform state is in an S3 bucket, and half the resources were created *before* Terraform (legacy). What's your first-month plan?

- **Situation**: partial adoption — new stuff in TF, old stuff not.

- Flow:
  1. **Inventory first** — `terraform state list` (what TF knows) vs a full account scan (what exists): tag coverage, resources without owner tags. Diff the two lists → that's your adoption backlog.
  2. **Adopt high-value / high-risk items first** — anything the app depends on and that someone could accidentally delete (prod DB, VPC, DNS): write the resource blocks, `terraform import` by ARN, confirm a clean `plan`.
  3. **Import in batches with git discipline** — one PR per logical group (all VPC stuff, all storage stuff), each PR = code + import + clean plan. Reviewers check that blocks match the imported attributes.
  4. **Tag as you import** — the moment a resource enters state, give it `Team`/`Project`/`Lifecycle` tags through the code, so the next audit is automatic.
  5. **Stop the bleeding at the edges** — from day one, new resources must be born in Terraform (code review rule + alert on untagged/unmanaged resources via a drift check).
  6. Don't boil the ocean: cheap, stable legacy (e.g. an old S3 bucket nobody touches) can wait for a lower-priority batch.

- What's being checked: prioritization (risk first), import hygiene (clean plan after import), and building the *system* that keeps the team from drifting back.

---

### S6. Your `terraform plan` in CI takes 4 minutes and everyone is annoyed. How do you make it fast?

- **Situation**: slow CI feedback loop.

- Flow (in order of impact):
  1. **`init` caching** — cache `~/.terraform.d/plugins` (the provider binaries) between runs in CI (actions/cache). `init` usually dominates; cached = seconds.
  2. **Parallelism & partial plans** — split independent stacks so each plan is smaller; skip `plan` on PRs that only touched docs (path filters).
  3. **Don't do what you don't need** — `plan` on a PR only needs to read state, not lock for writes… (it still refreshes; keep refresh scope tight — avoid giant `data` sources that re-query the whole region).
  4. **Provider-level** — some providers do expensive discovery per `init`/`plan` (region lists, etc.); a warm cache and pinned, current provider versions help.
  5. **Measure first** — `terraform plan -parallelism` and provider debug logs tell you where the 4 minutes actually go; fix the top item, re-measure.

- What's being checked: you profile before optimizing, and you know `init`-caching is the biggest cheap win.

---

### S7. A provider upgrade changed a resource attribute's name (e.g. `x_old` → `x_new`). Your `plan` after upgrading shows a mass of in-place updates you didn't expect. What's happening and what do you do?

- **Situation**: provider schema migration causing plan churn.

- Flow:
  1. **Read the provider changelog** for the version jump — attribute renames usually come with a deprecation note and, often, an upgrade guide.
  2. **Distinguish three cases**:
     - *Rename with compatibility* — provider reads the new attribute from the same API field; the diff is cosmetic (a value "changed" to the same real-world value). Safe: update code to the new attribute name; plan goes quiet.
     - *True behavioral change* — the provider now interprets the value differently (e.g. a default flipped). The diff is **real**: the cloud *will* change. Decide if you want that; set the attribute explicitly to the value you want.
     - *State-shape change* — the attribute moved in state; sometimes `terraform refresh` / one clean apply normalizes it.
  3. **Upgrade staged**: dev first, read the plan line-by-line, then staging, then prod — never jump all envs at once.
  4. If it's too messy → **pin the old version** (`= 4.57.0`) and schedule the upgrade properly. Pinning is a feature, not a failure.

- What's being checked: you separate cosmetic churn from real-world changes, use the changelog, and roll out upgrades in stages.

---

### S8. You discover a production password sitting in plaintext in `terraform.tfstate` (in S3) *and* in Git history (someone committed `terraform.tfvars`). What's your response, hour by hour?

- **Situation**: credential compromise, two leaks, one password.

- Flow:
  1. **Hour 0 — rotate the password first.** Everything else is cleanup; rotation is the fix. Do it before the Slack thread, before the post-mortem. If it's an RDS master password: rotate via the DB console/CLI *and* update the code so the next apply doesn't re-leak the old one.
  2. **Hour 0–1 — assume breach, verify**: pull CloudTrail / audit logs for that resource since the commit date; look for suspicious sign-ins/connections. Report per your incident process.
  3. **Hour 1–2 — stop the bleeding at the source**:
     - The S3 state: verify `encrypt = true`, tighten the bucket policy to the team/CI role only, enable versioning + MFA delete if not on.
     - The repo: the file is in history → `git filter-repo` to remove it, **but** treat history rewrite as cosmetic until the password is rotated (already done in step 1).
  4. **Hour 2+ — make it structurally impossible**:
     - Move secrets out of vars: app reads from Secrets Manager / Key Vault at runtime; Terraform creates the store, not the value.
     - Add **pre-commit scanning** (gitleaks/trufflehog) + a CI secret scan so a `*.tfvars` containing "password" fails the PR.
     - `sensitive = true` everywhere a secret must flow; state encryption + restricted access.
  5. **Post-mortem without blame**: timeline, the 3 fixes above, and one metric to watch (secrets detected pre-merge).

- What's being checked: *rotate first*, then forensics, then process — the order is the answer.
