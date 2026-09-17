# Pattern: `git stash` — save work-in-progress temporarily

A stash is a stack of saved changes you can put aside and pick up later.

```bash
git stash                               # save tracked modifications, leaving a clean tree
git stash push -m "wip login form"      # save WITH a message so you recognise it later
git stash push -u -m "wip"              # -u also stash UNTRACKED files (new files)
git stash push -a -m "everything"       # -a also stash IGNORED files (node_modules, build output)
git stash push src/app.js               # stash only ONE file
git stash push -- src/ tests/           # stash only these paths
git stash push -p                       # interactive: choose which hunks to stash (like add -p)
git stash push --keep-index             # stash everything but leave the STAGED changes in place
git stash list                          # list your stashes: stash@{0} is the newest
git stash show stash@{0}                # summary of what that stash changed
git stash show -p stash@{0}             # the full diff of the stash
git stash apply                         # re-apply the newest stash, KEEPING it in the list
git stash apply stash@{2}               # apply an older one
git stash pop                           # apply the newest AND remove it from the list
git stash pop stash@{1}                 # apply and drop a specific one
git stash drop stash@{0}                # delete one stash
git stash clear                         # delete ALL stashes (⚠️ no confirmation)
git stash branch newbranch stash@{0}    # create a branch from the stash's base commit and apply it
git checkout stash@{0} -- src/app.js    # restore just one file from a stash
git stash push -m "keep for later" && git switch main   # the classic "switch branch quickly" move
```

## `apply` vs `pop`

| Command | Effect |
|---|---|
| `git stash apply` | reapplies the changes and KEEPS the stash entry (safe, repeatable) |
| `git stash pop` | reapplies and DROPS the entry — but if there is a conflict, the entry is KEPT |

## Typical uses

```bash
git stash push -u -m "wip"              # 1. urgent bug report arrives mid-task
git switch main && git pull             # 2. get a clean, current main
git switch -c hotfix/bug-1234           # 3. fix, commit, push
git switch feature/login                # 4. back to your task
git stash pop                           # 5. resume exactly where you left off
```

## Notes and gotchas

```bash
git status                              # a stash requires something to stash — check first
git stash list --date=local             # see when each stash was created
git config --global rebase.autoStash true   # let rebase stash/unstash for you automatically
git fsck --unreachable | grep commit    # recover a stash you dropped by accident
git stash apply <hash>                  # and re-apply it by its hash
```
- Stashes are **not** pushed: they live only in your local `.git`.
- Untracked files are NOT stashed unless you pass `-u`.
- Prefer committing to a WIP branch over stashing for anything you might keep for days.
