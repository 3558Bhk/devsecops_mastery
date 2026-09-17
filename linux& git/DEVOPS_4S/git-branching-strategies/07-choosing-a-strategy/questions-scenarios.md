# 07 Choosing a Strategy — Scenario Questions

## Scenario 1
A 6-person startup shipping a SaaS product asks you to pick a strategy. Justify your choice.
```bash
# what you'd check first
git log --first-parent --since="1 month" --oneline main | wc -l    # how often do they integrate?
ls .github/workflows/ 2>/dev/null                                  # is CI/CD already automated?
grep -rl "flags" src/ 2>/dev/null | head                           # any flag infrastructure?
```
**Answer:** GitHub Flow now (main + short-lived branches + squash merges + auto-deploy), because with
6 people and a SaaS product the cost of GitFlow's `develop` is pure delay. Add release tags for
traceability. Move toward trunk-based once they have flags and a canary/rollback path. Explicitly
reject GitFlow: no versioned artefacts, no multi-version support.

## Scenario 2
A 200-person company ships an on-prem appliance (quarterly) and a cloud service (daily) from one repo.
```text
Cloud:   trunk-based, deploy from main, flags + progressive rollout
Appliance: release/X.Y branches cut from trunk on a quarterly train, patch lines for supported versions
Shared:  one trunk, CODEOWNERS per path, affected-only CI, merge queue
```
```bash
git tag -a cloud-2026.09.15 <sha>          # calver tags for the cloud line
git switch -c release/appliance-3.2 <sha>  # quarterly train for the appliance
git cherry-pick -x <security-fix>          # fixes flow to all supported appliance lines
```
The key insight to state: **one trunk, two release mechanisms** — not two repos and not two trunks.

## Scenario 3
The team currently uses GitFlow and complains that releases take 3 weeks of "stabilisation hell".
```bash
git rev-list --count main..develop                 # size of the unreleased backlog
git log --oneline v1.3.0..v1.4.0 --no-merges | wc -l   # commits per release → too many
git log --oneline --since="6 months" -i --grep="back-merge" | wc -l   # are back-merges happening?
```
**Diagnosis:** releases are too big, so stabilisation is long, so branches drift, so merges hurt —
a self-reinforcing loop. **Fix:** cut release size (smaller trains, more often), automate the
back-merge, introduce flags so trunk is always releasable, then collapse `develop`. Do it in that
order; deleting `develop` first just moves the pain.

## Scenario 4
Management mandates "everyone uses trunk-based development from Monday". You know three teams aren't ready.
```bash
# evidence to bring:
for r in team-a team-b team-c; do echo "== $r"; (cd $r && git log --first-parent --since="1 month" --oneline main | wc -l); done
```
**Answer:** propose invariants + a readiness gate instead of a date: protected trunk, PR size limits,
required checks, tags per release, DORA measurement. Publish a readiness checklist (CI time, deploy
automation, rollback tested, flags available) and let teams migrate when they pass it, with a
platform team building the shared flag/CI tooling. Mandating the label without the capability
produces broken trunks and a loss of trust in the whole programme.

## Scenario 5
You inherit a repo with 9 long-lived branches nobody understands.
```bash
git for-each-ref --sort=committerdate refs/remotes/origin --format='%(committerdate:short)|%(refname:short)|%(authorname)' 
git rev-list --left-right --count origin/main...origin/develop 2>/dev/null
for b in $(git branch -r --format='%(refname:short)' | grep -v HEAD); do
  printf '%-40s unique-commits:%s last:%s\n' "$b" "$(git rev-list --count origin/main..$b)" "$(git log -1 --format=%cs $b)"
done
```
Then: classify each branch (active / stale / release line / abandoned), archive the abandoned ones as
tags, delete after asking the author, and document the surviving model in CONTRIBUTING.md with a CI
guard. Output = a one-page model + branch inventory, not a cleanup commit.

## Scenario 6
A regulated customer requires separation of duties: developers must not be able to deploy to production.
```text
GitLab Flow with environment branches + protected environments:
  main (developers) → pre-production (QA/CI only) → production (release manager/CI only)
```
```bash
# CI guard that enforces the one-way flow
git log --oneline origin/main..origin/production        # must be empty
git merge-base --is-ancestor origin/pre-production origin/main || exit 1
```
Add: four-eyes approval on the promotion, signed tags for every production release, `git notes`
audit annotations, and immutable artefact promotion (same digest staging → prod).

## Scenario 7
Two teams merge to the same trunk 30×/day and keep breaking each other.
```bash
git log --first-parent --oneline --since="1 week" main | wc -l
git log --oneline --since="1 week" -i --grep=revert main
```
**Fixes in order:** merge queue (test combined results), affected-only CI per path, CODEOWNERS,
flaky-test quarantine, contract tests between the two services, and PR size limits. If breakage
persists, the real issue is coupling — consider separate trunks or a repo split.

## Scenario 8
You must justify the cost of migrating from GitFlow to trunk-based to a sceptical CTO.
```text
Costs:   flag infrastructure (build or buy), CI time reduction work, deploy automation + canary/rollback,
         training/pairing, temporary velocity dip (~1-2 sprints)
Benefits (measurable): lead time for change ↓, deploy frequency ↑, change-failure rate ↓,
         MTTR ↓, merge-conflict hours ↓, release-day risk ↓, no more "stabilisation hell"
Evidence: DORA/Accelerate correlations between short-lived branches/small batches and elite performance
Plan:    phase 0 prerequisites → pilot one team 6-8 weeks → measure → roll out with automation
Risk:    if prerequisites are skipped, trunk-based fails loudly; the pilot exists to surface that early
```
Close with: "the migration is really an investment in CI/CD and rollback; the branching model is just
the visible part."
