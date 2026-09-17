# One-page Git Cheatsheet

Print this. Every command is explained in detail in its topic folder.

## Setup
```bash
git config --global user.name "Alex"          # who you are
git config --global user.email "a@b.com"      # commit email (match your GitHub)
git config --global init.defaultBranch main   # modern default branch
git config --global pull.rebase true          # pull = fetch + rebase (linear history)
git config --global rebase.autoStash true     # stash automatically around rebases
git config --global rerere.enabled true       # remember conflict resolutions
git config --global merge.conflictStyle zdiff3 # show the base version inside conflicts
git config --list --show-origin               # what is set, and where
```

## Start or get a repo
```bash
git init                        # make this folder a repository
git clone <url>                 # download an existing one
git clone --depth 1 <url>       # latest commit only (fast)
git status                      # THE command: what state am I in?
```

## Daily loop
```bash
git status -s                   # compact view of changes
git add file | git add -A       # stage one file | everything
git add -p                      # stage hunk by hunk (pro move)
git diff                        # unstaged changes
git diff --staged               # what the next commit will contain
git commit -m "feat: subject"   # snapshot it
git commit --amend --no-edit    # fold staged changes into the last commit
git log --oneline --graph --all # the shape of history
```

## Branches
```bash
git branch                      # list branches
git switch -c feature/x         # create and switch (git checkout -b is the old form)
git switch main                 # switch
git switch -                    # back to the previous branch
git branch -m old new           # rename
git branch -d merged-branch     # delete if merged (-D forces)
git worktree add ../dir branch  # a second folder on another branch
```

## Merging
```bash
git switch main && git merge feature       # merge feature INTO main
git merge --no-ff feature                  # always create a merge commit
git merge --squash feature && git commit   # collapse the branch into one commit
git merge --abort                          # cancel a conflicted merge
git merge-base main feature                # the common ancestor
git diff main...feature                    # what the feature changed (3 dots)
```

## Undo
```bash
git restore file                # discard unstaged edits (no undo!)
git restore --staged file       # unstage, keep edits
git reset --soft HEAD~1         # undo commit, keep changes staged
git reset HEAD~1                # undo commit, keep changes unstaged (default --mixed)
git reset --hard HEAD~1         # undo commit AND changes (destructive)
git revert <hash>               # safe undo of a PUSHED commit (adds a new commit)
git revert -m 1 <merge-hash>    # undo a merge commit
git clean -nd                   # dry-run removal of untracked files (-fd to actually delete)
git reflog                      # your safety net: every HEAD movement
```

## Stash & tags
```bash
git stash push -u -m "wip"      # save work including untracked files
git stash list                  # what you have saved
git stash pop                   # apply newest and drop it
git stash apply stash@{1}       # apply one, keep it in the list
git stash branch name stash@{0} # resume a stash on a new branch
git tag -a v1.0.0 -m "release"  # annotated tag (use for releases)
git push origin v1.0.0          # publish a tag
git describe --tags --always --dirty   # version string from Git
```

## Remotes
```bash
git remote -v                   # list remotes
git remote add origin <url>     # add one
git fetch --prune               # download refs, change nothing locally (always safe)
git pull --rebase               # fetch + rebase your commits on top
git push -u origin feature      # first push, sets upstream
git push                        # afterwards
git push --force-with-lease     # safe force push after a rebase
git push origin --delete branch # delete a remote branch
git status -sb                  # shows [ahead 2, behind 1]
git branch -vv                  # branch → upstream mapping
```

## Rebase & archaeology
```bash
git rebase origin/main          # replay your commits onto newer main
git rebase -i HEAD~5            # edit/squash/reword/drop the last 5 commits
git rebase --continue           # after resolving conflicts
git rebase --abort              # give up, back to the start
git rebase --onto new old branch # move a commit range to a new base
git cherry-pick <hash>          # copy one commit here (-n = don't commit, -x = record source)
git bisect start HEAD v1.4.0 && git bisect run ./test.sh   # find the breaking commit
git blame -L 20,40 file         # who wrote these lines
git log -S"string"              # commits that added/removed this text
git log -L :func:file           # history of one function
```

## Conflicts
```bash
git status                                   # which files are unmerged (UU)
git diff --name-only --diff-filter=U          # just their names
# edit the file: <<<<<<< HEAD (ours) ======= (theirs) >>>>>>> branch
git checkout --ours file | --theirs file      # take one side wholesale
git mergetool                                 # visual three-way tool
git add file                                  # mark resolved
git merge --continue | git rebase --continue  # finish
git diff --check                              # any leftover conflict markers?
```
⚠️ In a **rebase** conflict the sides are swapped: HEAD is the new base, not your branch.

## Emergencies
```bash
git reflog                                  # find the hash from before your mistake
git reset --hard HEAD@{2}                   # go back to that state
git fsck --lost-found                       # find dangling commits
git branch backup <hash>                    # rescue lost work onto a branch
git filter-repo --path secret.yml --invert-paths   # purge a file from all history
```

## Golden rules
```bash
git status                                  # run it before AND after everything
git fetch                                   # safe; pull modifies your branch
```
- Commit often; small commits are easy to undo.
- Never rewrite history that is already pushed to a shared branch.
- `reset --hard`, `clean -fd` and uncommitted work are unrecoverable — stash first.
- Rotating a leaked secret matters more than purging it from history.
