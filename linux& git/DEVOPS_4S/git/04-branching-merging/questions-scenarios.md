# 04 Branching & Merging — Scenario Questions

## Scenario 1
Production is broken. You must fix it without losing the half-finished feature you are writing.
```bash
git status                              # see your uncommitted work
git stash push -u -m "wip feature"      # -u also stashes untracked files
git switch main && git pull             # get the latest main
git switch -c hotfix/payment-crash      # branch off the up-to-date main
# ...fix, test, commit, push, open a PR...
git switch feature/login && git stash pop   # return and resume exactly where you were
```

## Scenario 2
You committed your new feature directly onto `main` by mistake (not pushed yet).
```bash
git log --oneline -3                    # confirm the bad commits are on main
git switch -c feature/my-work           # 1. branch here — it carries the commits with it
git switch main                         # 2. go back to main
git reset --hard origin/main            # 3. rewind main to the remote state (⚠️ discards local commits)
git switch feature/my-work              # 4. your work is safe on the new branch
```

## Scenario 3
A merge produced conflicts in 12 files and you want to give up and start over.
```bash
git status -s | grep '^UU'              # see the conflicted files
git merge --abort                       # cancel the merge entirely — back to the pre-merge state
git switch main && git pull             # get the newest main instead
git merge feature                       # try again with an up-to-date base (usually fewer conflicts)
```

## Scenario 4
Your team wants the feature branch to appear as ONE commit in main's history.
```bash
git switch main && git pull
git merge --squash feature/login        # stage everything, commit nothing
git commit -m "feat(auth): add login with JWT"
git log --oneline -3                    # one clean commit instead of 27 WIP ones
git branch -D feature/login             # delete the local branch
git push origin --delete feature/login  # and the remote one
```

## Scenario 5
You need to review a colleague's branch while your own branch has a long-running build.
```bash
git worktree add ../review-pr-42 origin/feature/search   # a second folder on their branch
cd ../review-pr-42 && npm ci && npm test                 # test it in isolation
cd - && git worktree remove ../review-pr-42              # remove it when done
```
Your original folder and its build are untouched the whole time.

## Scenario 6
`git branch -d feature` refuses with "not fully merged" — but you know it was merged via a squash.
```bash
git branch --merged main | grep feature   # empty: squash merges change hashes, so Git cannot see it
git log main --oneline --grep "login"     # find the squashed commit to confirm it landed
git branch -D feature                     # safe to force-delete now
```

## Scenario 7
You merged a bad feature into main and it is already pushed. Undo it properly.
```bash
git log --oneline --merges -3             # find the merge commit hash
git revert -m 1 <merge-hash>              # create a NEW commit that undoes it (history stays intact)
git push                                  # publish the revert
```
Never `reset --hard` a pushed shared branch — it rewrites history other people already have.

## Scenario 8
Your branch is 40 commits behind main and every merge conflicts. Reduce the pain.
```bash
git fetch origin
git log --oneline HEAD..origin/main | wc -l   # how far behind you are
git switch main && git pull                   # update main first
git switch feature && git merge main          # merge main INTO your feature (resolve conflicts here,
git mergetool                                 # not on main), or use a visual tool
git config --global rerere.enabled true       # remember your conflict resolutions and reuse them
```

## Scenario 9
You need a branch that starts from an old release, not from the current code.
```bash
git fetch --tags                          # make sure you have the tags
git switch -c hotfix/1.4-security v1.4.0  # branch from the release tag
git log --oneline -1                      # confirm you are on the old commit
# ...fix, commit...
git switch -c feature/port-fix-to-main    # then port the same fix forward if needed
git cherry-pick <fix-commit>              # apply that one commit onto the new branch
```

## Scenario 10
Two people are working in the same folder on different branches and keep colliding.
```bash
git worktree list                         # see if worktrees are already in use
git worktree add ../proj-b feature/b      # give each person (or task) its own folder
```
One `.git` object store, several working folders — no more stash-switching dance.
