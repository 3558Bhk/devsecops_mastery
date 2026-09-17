# Pattern: The `reflog` — recovering "lost" work

Almost nothing in Git is truly deleted. Every move of HEAD is recorded in the reflog for ~90 days.

```bash
git reflog                              # list every HEAD movement: commits, checkouts, resets, merges
git reflog -20                          # the last 20 entries
git reflog show main                    # the reflog of one specific branch
git reflog --date=iso                   # with readable timestamps
git reflog --all                        # reflogs of every ref
git log -g --oneline                    # the reflog rendered as a log
```

## Reading a reflog line

```text
dd3545e HEAD@{2}: commit: add login form
│       │         │       └ what happened and the commit subject
│       │         └ the action: commit / reset / checkout / merge / rebase / pull
│       └ how far back: {0} = now, {1} = one step ago, or use a date: HEAD@{yesterday}
└ the commit hash you can go back to
```

## Recover a commit you destroyed with `reset --hard`

```bash
git reflog                              # 1. find the hash from BEFORE the reset
git reset --hard a1b2c3d                # 2. move the branch back to it
git switch -c rescue a1b2c3d            # 2b. or save it on a new branch, keeping main where it is
git cherry-pick a1b2c3d                 # 2c. or copy just that one commit onto your current branch
```

## Recover a branch you deleted

```bash
git reflog | grep -i "checkout: moving from feature"   # find when you left the branch
git branch feature a1b2c3d                             # recreate it pointing at that commit
git log --oneline feature -3                           # verify it looks right
```

## Recover from a botched rebase or merge

```bash
git reflog                              # look for the entry just before "rebase (start)"
git reset --hard HEAD@{5}               # jump back to that point
git rebase --abort                      # if the rebase is still in progress, this is simpler
git merge --abort                       # same for an in-progress merge
```

## Finding commits with no branch pointing at them

```bash
git fsck --lost-found                   # list dangling/unreachable commits
git show <hash>                         # inspect one
git switch -c recovered <hash>          # rescue it onto a new branch
ls .git/lost-found/commit/              # where fsck copies them
```

## Stashes are recoverable too

```bash
git stash list                          # stashes you dropped may still appear here
git fsck --unreachable | grep commit    # a dropped stash shows up as an unreachable commit
git stash apply <hash>                  # re-apply it by hash
```

## Rules of thumb

- Run `git reflog` **before panicking** — 90% of "I lost my work" stories end there.
- `reset --hard`, `clean -fd` and `rebase` on uncommitted work ARE unrecoverable. Stash first.
- Committed work is nearly always recoverable; uncommitted work is not.
