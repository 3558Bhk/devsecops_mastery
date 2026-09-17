# 02 GitFlow — Scenario Questions

## Scenario 1
A bug fixed during `release/1.4.0` stabilisation reappears in `release/1.5.0`. Diagnose.
```bash
git log --oneline --all --grep "fix" | head -20                  # find the original fix
git branch -a --contains <fix-hash>                              # which branches have it?
git log --oneline release/1.4.0..develop | grep -i "back-merge"  # was it ever back-merged? (no → root cause)
```
**Fix now:** `git switch develop && git cherry-pick -x <fix-hash>`, test, push.
**Fix forever:** automate the back-merge in CI (see advanced Q2) and add a release checklist item.

## Scenario 2
Production runs v1.4.0 and needs an urgent patch, but develop already contains v1.5 features.
```bash
git switch -c hotfix/1.4.1 v1.4.0        # from the TAG — never from develop
# minimal fix only, plus version bump
git commit -am "fix(auth): token expiry; release 1.4.1"
git switch main && git merge --no-ff hotfix/1.4.1 -m "hotfix 1.4.1"
git tag -a v1.4.1 -m "hotfix 1.4.1" && git push origin main --follow-tags
git switch develop && git merge --no-ff hotfix/1.4.1 -m "hotfix 1.4.1 back-merge" && git push
git branch -d hotfix/1.4.1
git log --oneline -1 v1.5.0-rc1 2>/dev/null   # confirm develop still has the v1.5 work intact
```
Then verify the fix is present in BOTH lines: `git branch -a --contains <fix-hash>`.

## Scenario 3
A developer opened 14 feature PRs against `main` instead of `develop`. Remediate and prevent.
```bash
gh pr list --base main --json number,title,headRefName        # inventory the mistakes
gh pr edit <n> --base develop                                 # re-target each PR (GitHub CLI)
# GitLab: edit the merge request's target branch in the UI or via API
git branch -vv                                                # check local tracking branches
```
**Prevent:** host-level ruleset making `main` PRs require a label/approval; a CI check that fails PRs
targeting main unless the source is `release/*` or `hotfix/*`; and `git config branch.autoSetupMerge`
defaults documented in CONTRIBUTING.md.

## Scenario 4
You must support v1.2 for one more customer while the team ships v1.6.
```bash
git switch -c support/1.2.x v1.2.9          # dedicated maintenance line
# security fix on the old line:
git commit -am "fix: CVE-2026-1234"
git tag -a v1.2.10 -m "security release" && git push origin support/1.2.x --follow-tags
# port forward to every newer line:
for b in release/1.5 develop main; do
  git switch "$b" && git cherry-pick -x <hash> || { echo "conflict on $b"; git cherry-pick --abort; }
done
git tag --contains <hash>                    # prove which releases include the fix
```
Document an EOL date for `support/1.2.x`, and add it to your CVE-response runbook.

## Scenario 5
The release manager asks "what exactly is in v1.4.0?" — produce the answer in 30 seconds.
```bash
git log --oneline v1.3.0..v1.4.0 --no-merges                 # the commits in this release
git log v1.3.0..v1.4.0 --no-merges --pretty='* %s (%an)'     # formatted as release notes
git log v1.3.0..v1.4.0 --no-merges --grep '^feat' --oneline  # features only
git log v1.3.0..v1.4.0 --no-merges --grep '^fix' --oneline   # fixes only
git diff --stat v1.3.0 v1.4.0 | tail -1                      # size of the release
git tag --list 'v1.4*' --format='%(refname:short) %(creatordate:short)'   # related tags
```

## Scenario 6
The team wants to move from GitFlow to trunk-based development. Plan the migration.
```bash
# 1. measure the current pain
git rev-list --count main..develop                 # unreleased backlog
git for-each-ref --sort=committerdate refs/heads --format='%(committerdate:short) %(refname:short)' | head
git log --oneline --since="3 months" --merges | wc -l    # merge-commit noise
# 2. prerequisites before touching anything
#    - feature flags in place, CI under ~10 min, deploy pipeline from main, rollback tested
# 3. migrate incrementally
git switch main && git merge --no-ff develop -m "absorb develop into main"   # collapse the two branches
git push origin main
# 4. stop creating develop; features now branch from main and PR into main
# 5. keep release/* branches only if you truly ship versioned artefacts
git branch -d develop && git push origin --delete develop     # do this LAST, after a soak period
```
Key point for the interview: you migrate by **first building the safety nets** (flags, fast CI,
progressive delivery, rollback), then collapsing the branches — not the other way round.

## Scenario 7
Two release branches are being stabilised simultaneously (1.4 and 1.5) and a fix belongs in both.
```bash
git switch release/1.4.0 && git cherry-pick -x <hash> && git push
git switch release/1.5.0 && git cherry-pick -x <hash> && git push
git switch develop       && git cherry-pick -x <hash> && git push
git branch -a --contains <hash>       # verify all three got it
```
Automate with a "backport" label in CI: on merge, cherry-pick to every branch carrying the label.

## Scenario 8
`git flow release finish` failed halfway: main is merged and tagged but develop was not back-merged.
```bash
git status && git log --oneline --graph --all -10      # establish exactly what completed
git tag --list 'v1.4*'                                 # was the tag created?
git log --oneline develop -3                           # is the back-merge present?
# finish the missing steps manually:
git switch develop && git merge --no-ff v1.4.0 -m "release 1.4.0 back-merge" && git push origin develop
git branch -d release/1.4.0 2>/dev/null; git push origin --delete release/1.4.0
git reflog | head -20                                  # if anything looks wrong, this is your undo
```
Lesson: tooling that performs multi-step operations needs a resumable/verifiable design — which is why
CI-driven releases beat local `git flow` invocations.
