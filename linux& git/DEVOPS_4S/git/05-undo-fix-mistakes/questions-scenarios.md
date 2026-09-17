# 05 Undo & Fix Mistakes — Scenario Questions

## Scenario 1
You committed a password in `config.py` two commits ago. It is NOT pushed yet.
```bash
git log --oneline -5                        # locate the bad commit
git rebase -i HEAD~3                        # mark that commit as "edit"
# ...remove the password, then:
git add config.py && git commit --amend --no-edit
git rebase --continue
git log -p --all -S"password" -- config.py   # verify the secret is gone from all reachable history
```

## Scenario 2
The same mistake, but it IS already pushed to a shared branch.
```bash
git revert <hash>                           # rewrite nothing — add a reversing commit
git push
```
Then **rotate the password immediately**. It is still in history and in everyone's clones.
To purge it properly you need `git filter-repo` plus a coordinated force-push and re-clone.

## Scenario 3
`git reset --hard` just wiped two hours of work. Get it back.
```bash
git reflog                                  # 1. find the last commit hash BEFORE the reset
git reset --hard HEAD@{1}                   # 2. if that entry is the right one, jump back
git switch -c rescue HEAD@{1}               # 2b. or rescue it onto a branch, leaving main alone
git fsck --lost-found                       # 3. if the reflog has nothing, look for dangling commits
```
Uncommitted edits are NOT recoverable. Prevention: `git stash` or commit often (even WIP commits).

## Scenario 4
You meant to commit on a feature branch but committed on `main`, and already pushed.
```bash
git log --oneline -3                        # identify your commit(s)
git switch -c feature/my-work               # 1. keep the work on a proper branch
git switch main
git revert <hash>                           # 2. undo it on main with a new commit (safe, pushed)
git push origin main
git push -u origin feature/my-work          # 3. push the feature branch and open a PR
```
If main is protected, the revert must itself go through a PR.

## Scenario 5
A merge brought in half-finished code and broke the build. Undo the whole feature.
```bash
git log --oneline --merges -3               # find the merge commit
git revert -m 1 <merge-hash>                # undo everything the branch introduced
git push
git log --oneline -3                        # the revert sits on top; history is intact
```

## Scenario 6
You accidentally deleted a branch that had unmerged work.
```bash
git reflog | grep -i "moving from that-branch"   # find the hash of its tip
git branch that-branch <hash>                    # recreate the branch there
git log --oneline that-branch -5                 # confirm the commits are back
```

## Scenario 7
You want to undo the last three commits but keep all the code changes for a re-do.
```bash
git reset --soft HEAD~3                     # commits gone, everything still staged
git status -s                               # review what you have to work with
git restore --staged .                      # optionally unstage it all to re-select hunks
git add -p                                  # re-stage only what belongs in the new commit
git commit -m "feat: redo checkout flow"
```

## Scenario 8
You ran `git clean -fd` and it deleted a new source file you never committed.
```bash
ls -la                                      # confirm it is gone
git fsck --lost-found                       # only committed objects can be recovered — this won't help
```
Prevention:
```bash
git clean -nd                               # ALWAYS dry-run first
git add -N newfile.js                       # -N registers the file as "intent to add" so clean skips it
git stash push -u -m "wip"                  # or stash untracked files before cleaning
```

## Scenario 9
Your commit message has a typo and the branch is shared.
```bash
git log -1 --format='%H %s'                 # confirm which commit and who has it
git commit --amend -m "corrected message"   # fine if you have NOT pushed it
git push --force-with-lease                 # if you already pushed to YOUR OWN feature branch
```
On a shared branch (main/develop), leave the typo — rewriting history costs the whole team.

## Scenario 10
You pulled and the merge went wrong; you want the state from before the pull.
```bash
git reflog | head -5                        # find the entry just before "pull"
git reset --hard ORIG_HEAD                  # Git sets ORIG_HEAD before merge/pull/rebase
git reset --hard HEAD@{1}                   # equivalent, via the reflog
git config --global pull.rebase false       # decide how pull should behave in future
```
