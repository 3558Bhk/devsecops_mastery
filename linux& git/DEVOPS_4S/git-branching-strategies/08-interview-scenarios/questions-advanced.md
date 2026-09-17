# 08 Interview Scenarios — Advanced Questions

**Q1.** An interviewer says "trunk-based is just marketing for no process." Rebut precisely.
**Answer:** trunk-based is the most process-heavy model — the process is just automated instead of
procedural. It requires: CI under ~10 minutes, required checks, a merge queue, PR size gates, a
feature-flag platform with owners and expiry, progressive delivery with automatic rollback,
flaky-test quarantine with SLAs, and DORA measurement. GitFlow's process lives in branch names and
human discipline; trunk-based's lives in CI and observability. The evidence (DORA/Accelerate)
correlates short-lived branches and small batches with elite throughput *and* stability — the opposite
of "no process".

**Q2.** They ask: "how do you do trunk-based when the DB schema changes?"
```bash
# expand/contract (parallel change) — never a long branch, never a locking migration
# 1. EXPAND: add the new column/table, nullable, no code depends on it
git switch -c db/expand-add-orders-v2 && git commit -am "feat(db): add orders_v2 (nullable)"
# 2. dual-write: write to both old and new (behind a flag)
# 3. backfill in batches: UPDATE ... WHERE id BETWEEN x AND y LIMIT 1000
# 4. CONTRACT reads: switch reads to the new column, behind a flag, roll out gradually
# 5. remove the dual-write and drop the old column in a later release
```
Every step is independently deployable and revertable, which is exactly what a 6-week branch cannot
give you. Add: online DDL tools (`gh-ost`, `pt-online-schema-change`) for locking migrations, and
migrations that are backward compatible with the previous release so rollbacks are safe.

**Q3.** "Your model assumes everyone is a strong engineer. What about juniors?"
**Answer:** the model should make the safe path the easy path, not rely on virtue: small PRs are easier
to review *and* to write; CODEOWNERS routes reviews to the right seniors; required checks catch what
juniors miss; a merge queue prevents "works alone, breaks together"; flags let a junior ship dark
instead of shipping broken; `git switch`/`git restore` (not `checkout`) reduce command confusion; and
pairing on the first few PRs plus a documented "how we work" page carries the culture. If a team
cannot support juniors safely, the missing piece is CI and review capacity — not a `develop` branch.

**Q4.** How would you answer "should we use a monorepo or polyrepo?" in a branching interview?
**Answer:** it changes the branching model, so it is fair game. Monorepo: one trunk, path-scoped
CODEOWNERS, affected-only CI, a merge queue, and internal library versioning — trunk-based is the
natural fit, but CI performance is the binding constraint. Polyrepo: each repo has its own trunk and
cadence, cross-repo changes need coordinated releases (contract tests, versioned APIs, and a
change-set ID in commit messages to correlate). Neither is "better"; the question is whether your
changes are usually cross-cutting (monorepo) or independently releasable (polyrepo).

**Q5.** They ask you to design a strategy for a team with a 6-month hardware/firmware release cycle.
```text
main (trunk) ── continuous integration against hardware-in-the-loop simulators
release/2.0  ── cut 3 months before tape-out/ship: fixes only, daily builds to QA rigs
support/1.x  ── field patches for devices already shipped; cherry-pick -x from trunk
flags        ── for anything not certifiable yet
tags         ── signed, with the build provenance (git describe + artefact digest) for audit
```
Long cycles make GitFlow-style release branches legitimate. Key differences from SaaS: you cannot
"roll back the fleet", so you invest in staged field rollouts, signed artefacts, and a
support matrix with real EOL dates.

**Q6.** "How do you prevent release-branch fixes from being lost?" (they will ask this twice)
```bash
# CI guard, nightly and on every push to main:
for b in $(git branch -r --list 'origin/release/*' | tr -d ' '); do
    n=$(git rev-list --count "$b" --not origin/main)
    [ "$n" -gt 0 ] && echo "MISSING FROM TRUNK: $b ($n commits)"
done
git cherry -v origin/main "$b"      # '+' = patch not upstream
```
Best structural answer: author every fix on trunk and cherry-pick **down**, so "forward-porting" is
not a step anyone can forget.

**Q7.** How do you handle a monorepo where two teams must ship on different cadences?
```text
One trunk + per-service release tags: cloud-2026.09.15, api-v3.4.1 — each service deploys from its own
tag/artefact while sharing history. Path-scoped CI triggers mean team A's merge does not redeploy
team B. If cadences diverge wildly (daily vs quarterly), that is a repo-split signal.
```

**Q8.** They push back: "flags add complexity and nobody removes them."
**Answer:** correct, and it is the real cost — so make removal mechanical: flag registry with owner +
created date + expiry ticket created **at flag creation**; CI fails on release flags older than N days;
a weekly report of flags at 100% for >14 days; a per-sprint flag-removal chore quota; and a
`grep -rn "flag_name" src/` step in the removal PR template to catch every reference. Also reduce flag
count: use one flag per *behaviour*, not per code path, and prefer kill-switches (ops flags) that are
permanent product surface rather than release flags.
