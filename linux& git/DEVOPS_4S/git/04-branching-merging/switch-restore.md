# Pattern: Moving between branches and undoing file changes

Git 2.23 split the overloaded `checkout` into two clearer commands:
**`switch`** = change branch, **`restore`** = fix files.

```bash
git switch main                         # change to another branch
git switch -c newbranch                 # create and change to a new branch
git switch -C newbranch                 # create/reset it even if it already exists (force)
git switch -                            # go back to the branch you were just on
git switch --detach v1.0                # look at a commit/tag without a branch
git switch -m main                      # -m carries your uncommitted changes over via a 3-way merge

git checkout main                       # the classic command that does both jobs (still works)
git checkout -b newbranch               # create + switch (the old way)
git checkout file.txt                   # ⚠️ DISCARD your edits to this file (old, dangerous form)
git checkout a1b2c3d -- src/app.js      # restore one file's content from an old commit
```

## `restore` — the safe, explicit way to fix files

```bash
git restore file.txt                    # discard unstaged edits (restores from the index/HEAD)
git restore .                           # discard edits to EVERY file here (⚠️ unrecoverable)
git restore --staged file.txt           # UNSTAGE a file, keeping your edits on disk
git restore --staged --worktree file.txt   # unstage AND discard: back to HEAD completely
git restore --source=HEAD~2 file.txt    # bring back the version from two commits ago
git restore --source=a1b2c3d src/app.js # bring back a specific commit's version
git restore -p file.txt                 # interactive: choose which hunks to restore
git restore --worktree --staged :/      # :/ means "from the repo root", everywhere
```

## Before you switch branches

```bash
git status                              # 1. anything uncommitted? Git may refuse to switch
git stash push -m "wip before switch"   # 2. save your work if you are not ready to commit
git switch otherbranch                  # 3. now switch cleanly
git switch -                            # 4. come back
git stash pop                           # 5. restore your work
```

## Clean up untracked files (⚠️ permanent)

```bash
git clean -n                            # -n DRY RUN: list what would be deleted
git clean -f                            # delete untracked FILES
git clean -fd                           # delete untracked files AND directories
git clean -fdx                          # also delete IGNORED files (node_modules, build output)
git clean -fdX                          # ONLY ignored files (keep your new source files)
```
`clean` has no undo — always run `-n` first.

## Which files would a branch switch touch?

```bash
git diff --name-only main otherbranch   # what differs between them
git checkout main 2>&1                  # if it refuses, Git lists the files that would be overwritten
```
