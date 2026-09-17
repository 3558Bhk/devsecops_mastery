# 04 Branching & Merging — Advanced Questions

**Q1.** Force a merge commit even when a fast-forward is possible. Why would you?
```bash
git merge --no-ff feature -m "Merge feature/login"
```
It records that the work happened as a unit, so `git log --graph` shows the feature's shape and
`git revert -m 1 <merge>` can undo the whole feature later.

**Q2.** Turn ten WIP commits into one clean commit on main.
```bash
git switch main
git merge --squash feature              # stages all of feature's changes, commits nothing
git commit -m "feat: add coupon codes"  # you author the single commit
git branch -D feature                   # -d will refuse (hashes differ), -D is normal here
```

**Q3.** What is the "merge base" and why does it matter?
```bash
git merge-base main feature             # the last common ancestor of the two branches
git diff $(git merge-base main feature) feature   # exactly what the feature changed
git diff main...feature                 # the same thing, written with three dots
```
Conflicts are computed against this base, so an old base means more conflicts.

**Q4.** Undo a merge that you already committed.
```bash
git revert -m 1 <merge-commit>          # -m 1 keeps the FIRST parent (main) and undoes the rest
git reset --hard HEAD~1                 # if NOT pushed yet: simply delete the merge commit
```
Reverting a merge means Git considers that branch "already merged" — you must revert the revert
(`git revert <revert-commit>`) before merging it again.

**Q5.** Carry uncommitted changes across a branch switch.
```bash
git switch -m otherbranch               # -m performs a three-way merge of your local edits
git stash push -m wip && git switch otherbranch && git stash pop   # the explicit, safer route
```

**Q6.** Restore a single file from another branch or an old commit.
```bash
git restore --source=main src/app.js    # take main's version into your working tree
git restore --source=HEAD~3 --staged --worktree src/app.js   # both areas, three commits back
git checkout a1b2c3d -- src/app.js      # older syntax, same effect
```

**Q7.** Test a colleague's branch without disturbing your own working folder.
```bash
git fetch origin
git worktree add ../review origin/feature/login   # second folder, same .git, different branch
cd ../review && npm test
git worktree remove ../review                     # clean up afterwards
```

**Q8.** Delete every local branch that is already merged, in one command.
```bash
git branch --merged main | grep -vE '^\*|main|master' | xargs -r git branch -d
# --merged lists candidates; grep removes the current branch and the protected ones; xargs deletes
```

**Q9.** Clean untracked build output but never your new source files.
```bash
git clean -nd                           # dry run: what WOULD be removed
git clean -fdX                          # capital X = only IGNORED files (node_modules, dist)
git clean -fdx                          # lowercase x = ignored AND untracked (destroys new files!)
```

**Q10.** Find which branch introduced a bug.
```bash
git branch --contains a1b2c3d           # every branch that includes the suspect commit
git log --all --oneline --source -S"badCall"   # --source shows which ref each commit came from
```

**Q11.** Create a branch from a specific old commit, not from HEAD.
```bash
git switch -c hotfix a1b2c3d            # branch starting at that commit
git switch -c hotfix v1.4.0             # branch starting at a tag
git branch hotfix origin/main           # branch from the REMOTE's main, not your local copy
```

**Q12.** Protect a branch from accidental deletion or rewriting.
```bash
git config branch.main.mergeoptions "--ff-only"   # refuse to create merge commits on main locally
git config receive.denyDeletes true               # server-side: reject branch deletions on push
# Real protection lives on the host (GitHub/GitLab "protected branches"), not in Git itself.
```

**Q13.** Understand the refspec behind remote branches.
```bash
git branch -r                           # origin/main is a local CACHE of the remote's branch
git fetch origin                        # refresh those caches
git log origin/main --oneline -3        # what the remote has, without switching to it
git rev-parse HEAD origin/main          # compare hashes directly
```
