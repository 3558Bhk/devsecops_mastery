# 05 Trunk-Based Development — Scenario Questions

## Scenario 1
A 3-week refactor of the billing engine. Trunk-based forbids a 3-week branch — how?
```bash
# 1. Branch by abstraction: introduce an interface, keep both implementations
git switch -c refactor/billing-interface && git commit -am "refactor: extract BillingProvider interface"
# 2. Merge it (behaviour unchanged, tests green)
# 3. Add the new implementation, dead code at first, behind a flag
git switch -c refactor/billing-v2 && git commit -am "feat(billing): v2 provider behind flag billing_v2"
# 4. Migrate call sites in small PRs, each merged to trunk
# 5. Flip the flag: 1% → 10% → 100%, watch error budget
# 6. Delete the legacy implementation and the flag
git switch -c refactor/billing-cleanup && git commit -am "chore(billing): remove legacy provider + flag"
```
This is the **strangler-fig** pattern. Every step is small, reviewable, deployable and revertable —
which is exactly what a long-lived branch cannot give you.

## Scenario 2
You must ship a feature for a launch date 6 weeks away, but the team integrates daily.
```bash
# merge incrementally behind a release flag, default OFF
git switch -c feat/launch-ui-part1 && git commit -am "feat(launch): hero section [flag launch_2026 off]"
# repeat with many small PRs; each one merged to trunk and deployed dark
# internal dogfooding:
#   enable flag for staff → beta customers → 1% → 100% on launch day
```
On launch day you flip a flag, not merge a branch — so rollback is seconds, and no code was untested
in production infrastructure.

## Scenario 3
Main is red at 09:00; the culprit is your teammate's merged PR.
```bash
git log --oneline -6                              # identify it
git revert --no-edit <sha> && git push            # restore green immediately
# open a ticket, ping the author, and let them re-land with a fix
git log --oneline --since="1 hour" --first-parent main   # anything else landed on top? revert in reverse order
```
Rule to state out loud: **restore the trunk first, diagnose second.** Then the systemic fix — the
missing test that let it through goes in with the re-land PR.

## Scenario 4
CI takes 35 minutes, so people batch work into week-long branches. Fix the root cause.
```bash
# measure
git for-each-ref --sort=committerdate refs/heads --format='%(committerdate:relative)|%(refname:short)' | head
# then attack CI time:
#  - affected-only tests: git diff --name-only $(git merge-base origin/main HEAD)...HEAD
#  - parallelise/shard, cache dependencies and build artefacts
#  - quarantine flaky tests (auto-skip + ticket) — flakiness causes retries, retries cause delay
#  - split "must pass to merge" from "must pass to deploy"
#  - partial clone + sparse checkout for faster agent setup
git clone --filter=blob:none <url>
```
Only after CI is fast should you enforce the 2-day branch rule. Otherwise you are asking people to
merge blind.

## Scenario 5
A customer on v1.4 (released 8 months ago) needs a security patch. You are on v2.x.
```bash
git tag -l 'v1.4*'                                 # find the release tag
git switch -c release/1.4 v1.4.9                   # patch branch from the tag
git cherry-pick -x <trunk-fix-sha>                 # backport the fix
git tag -a v1.4.10 -m "security patch" && git push origin release/1.4 --follow-tags
git switch main && git log --oneline -1 --grep "<fix>"   # confirm the fix is already in trunk
git branch -a --contains <fix-sha>                 # prove coverage across versions
```
The exception is legitimate: release branches exist for **patching shipped versions**, not for
developing new ones.

## Scenario 6
Product wants an A/B test with three variants, changing weekly.
```text
experiment flags with server-side assignment + sticky bucketing; variants live in trunk behind the flag
```
```bash
# CI matrix for the variants that matter:
VARIANT=a npm test -- --grep experiment
# analytics: log the flag+variant with every event so results are attributable
# cleanup: when the experiment ends, one PR removes ALL losing variants and the flag
grep -rn "exp_checkout_v3" src/ | wc -l            # find every reference before deleting
```

## Scenario 7
Two teams share a monorepo trunk and keep breaking each other.
```bash
# 1. path ownership
cat .github/CODEOWNERS                             # or GitLab CODEOWNERS
# 2. affected-only CI per service
git diff --name-only $(git merge-base origin/main HEAD)...HEAD | cut -d/ -f1-2 | sort -u
# 3. merge queue so combined results are tested before landing
# 4. contract tests between services, and no cross-team shared mutable types without an owner
# 5. if the coupling is real and constant, that is a signal to split the repo
```
Senior framing: frequent cross-team breakage in a monorepo is an **architecture** problem surfaced by
the branching model, not a Git problem.

## Scenario 8
Management asks: "prove trunk-based is better than what we did before."
```bash
# before/after metrics, all derivable from Git + the deploy system:
git log --first-parent --oneline --since="6 months" main | wc -l       # integration frequency
gh pr list --state merged --json mergedAt,createdAt,additions | jq '[.[]|(.additions)]|add/length'   # avg PR size
# plus: deploy frequency, lead time (first commit → prod), change-failure rate, MTTR,
#       PR cycle time, revert rate, incident count attributable to releases
```
Present it as a trend with the DORA four keys, and be honest about the costs you paid (flag debt,
CI investment, review discipline). Claiming "no downsides" is the junior answer.
