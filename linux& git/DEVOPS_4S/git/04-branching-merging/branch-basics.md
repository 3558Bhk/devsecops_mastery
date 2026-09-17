# Pattern: Creating, listing and deleting branches

A branch is just a movable pointer to a commit — that's why creating one is instant and free.

```bash
git branch                              # list local branches (* marks the one you are on)
git branch -v                           # list with the latest commit of each
git branch -vv                          # also show the upstream remote branch and ahead/behind
git branch -a                           # list local AND remote-tracking branches
git branch -r                           # list only remote-tracking branches (origin/main etc.)
git branch --merged main                # branches already merged into main (safe to delete)
git branch --no-merged main             # branches NOT yet merged (do not delete blindly)
git branch feature/login                # create a branch (you stay where you are)
git switch -c feature/login             # create AND move to it (modern command)
git checkout -b feature/login           # the older equivalent of the line above
git switch -c feature/login main        # create it starting from main instead of from HEAD
git switch feature/login                # move to an existing branch
git checkout feature/login              # older equivalent
git switch -                            # jump back to the previous branch (like cd -)
git branch -m oldname newname           # rename a branch (the current one if you omit oldname)
git branch -d feature/login             # delete it — REFUSES if it is not merged (safe)
git branch -D feature/login             # force delete even if unmerged (⚠️ commits become unreachable)
git branch --show-current               # print the name of the branch you are on
git branch --contains a1b2c3d           # which branches contain this commit?
git log --oneline --graph --all --decorate   # see all branches drawn together
```

## Branch naming conventions that teams use

```bash
git switch -c feature/user-login        # feature/... new functionality
git switch -c fix/cart-total-rounding   # fix/... a bug fix
git switch -c hotfix/payment-outage     # hotfix/... urgent production fix
git switch -c release/1.5.0             # release/... preparing a version
git switch -c chore/upgrade-deps        # chore/... maintenance, no user-visible change
git switch -c 1234-add-coupon-field     # ticket-number-first, so it sorts with the issue tracker
```
Use `/` and `-` only. Never use spaces, `~ ^ : ? * [ \` or a leading/trailing `.`.

## Detached HEAD — what it means

```bash
git switch --detach a1b2c3d             # look at an old commit without being on a branch
git switch --detach v1.0                # inspect a release tag safely
git log --oneline -3                    # you can look around freely
git switch main                         # come back — commits made while detached are left behind
git switch -c experiment                # or SAVE your detached work on a new branch first
```
Detached HEAD is not an error: you are simply not on a branch, so new commits belong to no branch.

## Worktrees — several branches checked out at once

```bash
git worktree add ../hotfix hotfix/x     # a second working folder on another branch, sharing one .git
git worktree add -b review ../review origin/feature   # create a branch in a new worktree
git worktree list                       # see all of them
git worktree remove ../hotfix           # clean up when done
git worktree prune                      # drop stale entries for folders you deleted manually
```
Perfect for reviewing a colleague's branch or fixing production without stashing your work.
