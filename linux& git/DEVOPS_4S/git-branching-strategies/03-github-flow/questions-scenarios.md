# 03 GitHub Flow — Scenario Questions

## Scenario 1
You must ship a half-built checkout redesign over three weeks without blocking main.
```bash
git switch main && git pull --ff-only
git switch -c feat/checkout-v2
# merge incrementally behind a flag, default OFF
gh pr create --draft --title "feat(checkout): v2 skeleton [flagged off]"
# each PR: small, reviewed, merged to main, invisible to users
```
Rollout: enable for internal users → 1% → 10% → 100% → delete the legacy path in a final PR.
The alternative (a 3-week branch) guarantees a painful merge and zero user feedback.

## Scenario 2
A bad PR merged 20 minutes ago and error rate is climbing. Respond.
```bash
git log --oneline -8                        # identify the suspect merge
git revert --no-edit <sha> && git push      # forward-fix: fastest safe rollback
# watch the deploy pipeline, then verify:
curl -sS -o /dev/null -w '%{http_code}\n' https://api/healthz
```
If the change was a data migration, reverting code is not enough — you need a data remediation plan.
Afterwards: was it caught by tests? Add the missing test in the follow-up PR (never in the revert).

## Scenario 3
Two engineers both need to change the same 1,500-line file, and their PRs conflict repeatedly.
```bash
git fetch origin && git rebase origin/main  # rebase early and often
git config --global rerere.enabled true     # remember conflict resolutions across rebases
git config --global merge.conflictStyle zdiff3   # show the base version in conflicts
```
Systemic fix: split the file (it is a merge magnet), add CODEOWNERS so one person sequences the
changes, or agree an order and stack the second PR on the first:
```bash
git switch -c feat/b feat/a                 # stack: B reviews only its own delta
git log --oneline feat/a..HEAD              # confirm only B's commits show
```

## Scenario 4
CI is green but the PR breaks production. Improve the gate.
```bash
git diff --stat origin/main...HEAD          # PR size gate (fail above N lines)
git diff --check origin/main...HEAD         # conflict markers / whitespace
```
Add: integration tests against a real dependency (testcontainers), a preview environment per PR,
contract tests for API changes, canary analysis on deploy, and an automatic revert on SLO burn.
Track change-failure rate — that is the metric this scenario is about.

## Scenario 5
The team wants versioned releases for an on-prem customer but keeps GitHub Flow for the SaaS product.
```bash
# trunk stays main for SaaS; cut a release branch only for the on-prem line
git switch -c release/2.4 main
# stabilise, then tag
git tag -a v2.4.0 -m "on-prem release" && git push origin release/2.4 --follow-tags
# security fixes go to BOTH lines
git switch release/2.4 && git cherry-pick -x <fix>
git switch main        && git cherry-pick -x <fix>
```
This hybrid (GitHub Flow + a release branch per supported version) is very common and a good answer
to "which strategy do you use?".

## Scenario 6
A new joiner pushed directly to main and it is now broken and unprotected.
```bash
git log --oneline -3                        # find the direct commit
git revert --no-edit <sha> && git push      # undo it
# then immediately:
#  Settings → Branches → protect main: require PR, required checks, no force push, no deletion
git config receive.denyNonFastForwards true # equivalent on a self-hosted server
```
Blameless: the mechanism allowed it. The fix is protection rules plus a CI check, plus onboarding docs.

## Scenario 7
You need to review a colleague's PR locally and run it, without disturbing your own work.
```bash
gh pr checkout 42                           # checks out their branch
git fetch origin pull/42/head:pr-42         # or the raw ref, no gh needed
git worktree add ../pr-42 pr-42             # best: separate folder, your tree untouched
cd ../pr-42 && npm ci && npm test
git worktree remove ../pr-42                # clean up
```

## Scenario 8
Deploy frequency dropped from 20/day to 2/day. Diagnose the process.
```bash
git log --oneline --since="30 days" --first-parent main | wc -l   # merges per month
gh pr list --state merged --json mergedAt,closedAt,additions,deletions | jq '.[] | .additions+.deletions' | sort -n | tail
gh pr list --state open --json createdAt,title | head             # are PRs ageing?
```
Typical causes: CI got slow (>15 min), PRs got big, reviewers are a bottleneck, deploys became manual
or scary, or a merge queue with low throughput. Fix the constraint you find — usually CI time or PR size.
