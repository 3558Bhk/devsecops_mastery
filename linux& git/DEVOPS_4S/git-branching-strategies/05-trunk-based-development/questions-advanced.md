# 05 Trunk-Based Development — Advanced Questions

**Q1.** "Merge ≠ release" — explain the operational consequences.
**Answer:** Because deployment no longer exposes behaviour, you gain: deploys at any time (including
Friday), instant rollback by flag flip instead of a redeploy, dark launches and internal dogfooding,
gradual rollouts (1% → 10% → 100%) with automatic halt on error-budget burn, and per-customer
entitlements without branches. The cost: every flag is a code path that must be tested (ideally both
states in CI), flags become debt, and product/eng must own rollout as an explicit activity.

**Q2.** How do you test both flag states without doubling CI time?
```bash
FLAGS_new_checkout=on  npm test -- --grep checkout     # matrix job for the ON state
FLAGS_new_checkout=off npm test -- --grep checkout     # and the OFF state
```
Run the matrix only for changed areas (affected-only tests), keep the default state in the main job,
and delete the OFF job when the flag is retired. Contract-test the flag service itself.

**Q3.** Flag debt: 300 flags in the codebase. How do you get to zero?
```bash
grep -rn "flags\.\(enabled\|get\)" src/ | wc -l            # inventory
# export flag metadata (created date, owner, rollout %) from the flag service, join with the code:
grep -rn "new_coupon_ui" src/                              # every reference to one flag
```
Process: every release flag gets an owner and an expiry ticket created **at creation time**; a weekly
report of flags at 100% for >14 days; a "flag removal" chore quota per sprint; CI fails on flags older
than N days. Treat it like dependency updates — automated, scheduled, owned.

**Q4.** Trunk is broken at 9 AM and 40 engineers are blocked. Respond and prevent.
```bash
git log --oneline -5                       # what landed
git revert --no-edit <sha> && git push     # revert FIRST (restore green), investigate second
```
Prevention: required checks with high signal, flaky-test quarantine (auto-skip + ticket), merge queue
so combined results are tested, fast CI, canary deploys with automatic rollback, and a rule that
whoever breaks the trunk drops everything to fix it (or revert). Measure: change-failure rate,
time-to-green.

**Q5.** When is trunk-based genuinely the wrong choice?
```text
✗ No deploy automation or unsafe rollback → every merge is a potential outage
✗ CI longer than ~20-30 min and no path to fix it → batching becomes inevitable
✗ Versioned artefacts customers install and stay on for years → you need release branches (GitFlow-ish)
✗ Regulated separation of duties requiring staged promotion with human gates → GitLab Flow
✗ Multiple independently released products in one repo with no build-graph tooling → per-product trunks
✗ Team lacks review/flag discipline and pairing culture → the model amplifies bad habits
```

**Q6.** How do you do trunk-based in a monorepo with 30 services?
```bash
git diff --name-only $(git merge-base origin/main HEAD)...HEAD   # what changed
# affected-only builds/tests: nx affected, bazel query, turborepo, or path filters in CI
git clone --filter=blob:none <url> && git sparse-checkout set services/payments   # fast local clones
```
Plus: CODEOWNERS per path, a merge queue, per-service deploy pipelines triggered by path changes, and
strict library versioning inside the repo. Without affected-only CI, trunk-based monorepos drown in
build time.

**Q7.** Stacked PRs in a trunk-based team — how do you keep them from becoming long-lived branches?
```bash
git switch -c part2 part1                  # child branch off the parent
git log --oneline part1..HEAD              # review only this slice
git rebase --onto main part1 part2         # when part1 merges, re-parent part2 onto main
git push --force-with-lease
```
Rules: max 2–3 in a stack, each slice independently mergeable behind a flag, and the whole stack must
land within days. Tools: `ghstack`, `graphite`, `git-spice`.

**Q8.** How do you measure whether trunk-based is working?
```bash
git log --first-parent --oneline --since="30 days" main | wc -l   # merges to trunk per month
git for-each-ref --sort=committerdate refs/heads --format='%(committerdate:relative)|%(refname:short)' | head
git log --since="30 days" --pretty='%ct %H' main | awk 'NR>1{print $1-p} {p=$1}' | sort -n | tail -1  # largest gap between merges
```
Track the four DORA metrics (deploy frequency, lead time for change, change-failure rate, failed
deployment recovery time) plus: PR cycle time, branch age, PR size, revert rate, % changes behind a
flag, and time-to-green after a trunk break.

**Q9.** "We do trunk-based" — but their branches live 3 weeks. What's actually wrong?
**Answer:** they have GitHub-Flow mechanics without trunk-based discipline, usually caused by one of:
work that cannot be split (no flags, no branch-by-abstraction), slow CI (batching is rational),
review bottleneck (PRs wait days), or a big-bang refactor with no strangler path. Diagnose with the
branch-age and PR-cycle-time metrics, then fix the constraint — telling people to "merge sooner"
without removing the blocker just creates broken trunks.
