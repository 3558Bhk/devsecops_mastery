# Rapid-fire — 60 one-line answers for the last 10 minutes before the interview

## Definitions

| Q | A |
|---|---|
| What is a branch? | A 41-byte file containing a commit SHA — a movable pointer. |
| Long-lived branches? | `main`, `develop`, `release/*`, environment branches. |
| Short-lived branch max age? | Under 1–2 days in trunk-based; under a week anywhere. |
| Fast-forward merge? | Main hasn't moved → the ref just slides forward, no merge commit. |
| 3-way merge? | Uses the merge base + both tips to combine; conflicts only on same-line edits. |
| Rebase vs merge? | Rebase replays commits (linear, rewrites history); merge preserves history (merge commit). |
| Squash merge? | Collapses a PR into one commit on main. |
| `git cherry-pick -x` | Copies a commit and records "(cherry picked from …)" for traceability. |
| Merge base? | `git merge-base A B` — the common ancestor used by merges/rebases. |
| Detached HEAD? | HEAD points at a commit, not a branch — commits are lost unless you branch. |

## The four main models, in one line each

| Model | One line |
|---|---|
| GitFlow | `main` + `develop` + feature/release/hotfix branches; versioned, scheduled releases. |
| GitHub Flow | `main` + short-lived branches + PR; deploy from main continuously. |
| GitLab Flow | GitHub Flow + environment/release branches; one-way promotion. |
| Trunk-Based | one trunk, integrate daily, flags for unfinished work, tiny batches. |

## Numbers that make you sound senior

| Metric | Healthy value |
|---|---|
| Branch lifetime | < 1–2 days |
| PR size | < ~400 lines, < 20 files |
| CI duration | < 10 minutes to merge |
| Integration frequency | ≥ once per developer per day |
| Revert / change-failure rate | < 15% |
| PR review turnaround | < 1 business day |
| Supported versions | 2–3 (N, N-1, maybe N-2 security only) |

## Command one-liners

```bash
git switch -c feat/PROJ-1-thing main              # create branch off main (NOT -b with switch)
git switch main && git pull --rebase              # sync with trunk
git push -u origin feat/PROJ-1-thing              # publish + set upstream
gh pr create --draft --fill                       # open the PR on day one
git rebase origin/main && git push --force-with-lease   # re-sync, safely
gh pr merge --squash --delete-branch              # merge + cleanup
git revert --no-edit <sha> && git push            # roll back a bad merge (forward fix)
git revert -m 1 --no-edit <merge-sha>             # roll back a MERGE commit (mainline = 1)
git branch -d merged-branch                       # delete locally (-D to force)
git push origin --delete old-branch               # delete on the remote
git branch --merged main | grep -vE 'main|master' # branches safe to delete
git for-each-ref --merged main refs/heads --format='%(refname:short)'
git log --oneline --graph --all --decorate -20    # see the shape of everything
git describe --tags --always --dirty              # build stamp
git tag --contains <sha>                          # which releases contain this fix
git branch -a --contains <sha>                    # which branches contain this fix
git rev-list --count main..develop                # how far two branches have diverged
git rev-list --left-right --count main...develop  # divergence in both directions
git reflog --date=iso | head                      # recover from almost any mistake
git config --global pull.rebase true              # keep the trunk linear
git config --global rerere.enabled true           # replay conflict resolutions
git config --global rebase.autoStash true         # stash around rebase automatically
```

## "What would you say when…" — instant answers

| Situation | Say this |
|---|---|
| main is broken | "Revert first to restore green, then diagnose. Never force-push a shared branch." |
| 3-week feature | "Strangler fig: merge the seam, then the new impl behind a flag, migrate in slices, delete the old path." |
| Release takes 3 weeks to stabilise | "Releases are too big. Shrink the train, automate back-merges, add flags — in that order." |
| Hotfix on an old version | "Fix on trunk with a failing test, then `cherry-pick -x` down to each supported line, verify with `git tag --contains`." |
| Two people, same file | "3-way merge against the merge base; conflict only if both touched the same line." |
| Force-push destroyed work | "`git reflog` / `git fsck --lost-found`, pin it in a branch; the real fix is branch protection." |
| Nobody knows the model | "Read the refs, write one page, encode it in CI, delete the clutter, re-measure in 30 days." |
| Flaky CI, people merge anyway | "Quarantine flakes with owners, split merge-gates from deploy-gates, add a merge queue." |
| Regulated promotion needed | "GitLab Flow: one-way promotion, protected environments, signed tags, immutable artefacts." |
| Which strategy do you use? | Pick → Justify → Trade-off → Adapt. Never open with "it depends." |

## The three sentences that close any branching question

```text
1. "Merge is not release — flags let us ship dark and roll back in seconds."
2. "Small batches are the whole game: short-lived branches, small PRs, fast CI."
3. "The branching model is downstream of your deploy capability — pick what your pipeline can support."
```
