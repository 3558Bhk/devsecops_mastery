# Pattern: Undoing changes — `restore` and `reset`

## Undo in the working directory (before staging)

```bash
git restore file.txt                    # discard your edits to one file (⚠️ no undo)
git restore .                           # discard edits to every file in this folder
git restore --staged file.txt           # unstage a file, KEEPING your edits on disk
git restore --staged .                  # unstage everything you added
git restore --source=HEAD~1 file.txt    # bring back an older version of one file
git checkout -- file.txt                # the old syntax for "discard edits"
```

## `git reset` — move the branch pointer backwards

Three modes, all move HEAD/branch; they differ in what happens to your files.

```bash
git reset --soft HEAD~1                 # undo the commit, changes stay STAGED (ready to re-commit)
git reset --mixed HEAD~1                # undo the commit AND unstage (changes stay on disk) — the DEFAULT
git reset --hard HEAD~1                 # undo the commit AND THROW AWAY the changes (⚠️ unrecoverable)
git reset HEAD~3                        # go back three commits, keeping edits in the working tree
git reset --hard origin/main            # make your branch identical to the remote's (discards local work)
git reset file.txt                      # no commit given = unstage this file (same as restore --staged)
git reset HEAD -- src/                  # unstage a whole folder
```

## Choosing the right one

| Goal | Command |
|---|---|
| Un-stage a file, keep edits | `git restore --staged f` |
| Discard edits to a file | `git restore f` |
| Undo the last commit, keep changes staged | `git reset --soft HEAD~1` |
| Undo the last commit, keep changes unstaged | `git reset HEAD~1` |
| Undo the last commit and its changes | `git reset --hard HEAD~1` |
| Undo a commit that is ALREADY PUSHED | `git revert <hash>` (never reset) |
| Delete untracked new files | `git clean -fd` (dry run with `-n` first) |

## Combine reset with re-committing

```bash
git reset --soft HEAD~3                 # collapse the last three commits into staged changes
git commit -m "feat: complete user profile page"   # one clean commit instead of three
git log --oneline -3                    # verify
```

## Safety first

```bash
git status                              # always look before you reset
git stash push -u -m "before hard reset"   # save untracked + modified work in case you regret it
git log --oneline -5                    # note the current hash so reflog recovery is easy
git reflog                              # your safety net: every HEAD movement is recorded here
```
