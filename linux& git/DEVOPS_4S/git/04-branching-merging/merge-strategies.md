# Pattern: Merging — fast-forward, three-way, squash

```bash
git switch main                         # 1. go to the branch that RECEIVES the changes
git merge feature                       # 2. merge the feature branch INTO it
git merge --no-ff feature -m "merge feature/login"   # force a merge commit even when fast-forward is possible
git merge --ff-only feature             # merge ONLY if it can fast-forward; otherwise fail
git merge --squash feature              # stage all of feature's changes as ONE, then you commit
git merge --no-commit --no-ff feature   # do the merge but stop before committing, so you can inspect
git merge feature1 feature2             # octopus merge: several branches at once
git merge --abort                       # cancel a conflicted merge and return to the pre-merge state
git merge --continue                    # after resolving conflicts, finish the merge
git log --oneline --graph --all         # see the result
```

## The two kinds of merge

```text
FAST-FORWARD (main has not moved since the branch point)
    before:  A---B---C (main)          after:  A---B---C---D (main, feature)
                      \                                     ↑ pointer just slides forward
                       D (feature)                          no merge commit is created

THREE-WAY MERGE (both branches moved — a real merge commit with 2 parents)
    before:  A---B---C---E (main)      after:  A---B---C---E---M (main)
                      \                             \         /
                       D (feature)                   \---D---/
```

```bash
git merge-base main feature             # the common ancestor Git uses for a three-way merge
git log --oneline --merges -5           # the merge commits in your history
git show --stat HEAD                    # inspect the merge you just made
```

## Squash merge — many commits become one

```bash
git switch main
git merge --squash feature              # feature's changes are STAGED but not committed
git commit -m "feat: add user login (squashed from feature)"   # you write the single commit
git branch -d feature                   # the branch is now "unmerged" by hash, so -d may refuse
git branch -D feature                   # force delete is normal after a squash merge
```

## Choose the right strategy

| Situation | Use |
|---|---|
| Solo work, keeping history linear | `git merge --ff-only` or rebase |
| Team feature branch, want to see it happened | `git merge --no-ff` |
| Messy WIP commits, want one clean commit | `git merge --squash` |
| Shared/public branch history must not change | never rebase it — merge instead |

## Merge drivers for files that always conflict

```text
# .gitattributes
package-lock.json merge=npm             # let npm regenerate it instead of merging by hand
CHANGELOG.md merge=union                # keep BOTH sides' lines (works out of the box)
```
```bash
git config merge.npm.driver "npm install --package-lock-only"   # you must DEFINE a custom driver
git config merge.npm.name "regenerate npm lockfile"             # or Git falls back to a normal merge
git config --global merge.conflictStyle zdiff3                  # show the base version inside conflicts
```

## After merging

```bash
git log --oneline --graph -8            # confirm the shape of history
git diff main feature                   # should now be empty if feature is fully merged
git branch -d feature                   # delete the merged branch locally
git push origin --delete feature        # and on the remote (see folder 06)
```
