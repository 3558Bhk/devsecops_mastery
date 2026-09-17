# Pattern: The three areas — working directory, index, repository

```text
WORKING DIRECTORY        STAGING AREA (index)        REPOSITORY (.git/objects)
files you edit     ──►   snapshot of what will    ──►   permanent commits with
                         go into the next commit         history and parents

        git add ──────────►│
                           │──── git commit ──────►│
        ◄───── git restore (discard edits) ────────│
                           │◄─ git restore --staged (unstage)
```

## See each area separately

```bash
git status                              # all three areas summarised in one screen
git diff                                # working directory vs staging area (UNSTAGED changes)
git diff --staged                       # staging area vs last commit (what WILL be committed)
git diff HEAD                           # working directory vs last commit (everything)
git diff --stat                         # just the file names and +/- counts
git ls-files                            # list everything currently TRACKED in the index
git ls-files --others --exclude-standard   # list untracked files that are not ignored
git show HEAD:file.txt                  # the file's content as stored in the last commit
```

## Moving data between the areas

```bash
git add file.txt                        # working directory → staging area
git restore --staged file.txt           # staging area → back to unstaged (file content untouched)
git restore file.txt                    # working directory → discard your edits (DANGEROUS, no undo)
git commit -m "msg"                     # staging area → repository
git reset --soft HEAD~1                 # repository → staging (undo the commit, keep changes staged)
git reset --mixed HEAD~1                # repository → working directory (undo commit AND unstage)
git reset --hard HEAD~1                 # throw it all away (⚠️ unrecoverable for uncommitted work)
```

## Why staging exists at all

```bash
git add -p buggy.js                     # answer y/n to each hunk: commit ONLY the fix, not your debug prints
git diff --staged                       # verify you staged exactly what you meant
git commit -m "fix: off-by-one in pagination"
```
The index lets one file's changes be split across several logical commits.

## The four file states in Git's vocabulary

| State | Meaning | Command that shows it |
|---|---|---|
| Untracked | Git has never seen it | `git status` → "Untracked files" |
| Unmodified | Tracked and identical to the last commit | nothing listed in `git status` |
| Modified | Tracked but changed on disk | `git diff` |
| Staged | Change placed in the index | `git diff --staged` |
