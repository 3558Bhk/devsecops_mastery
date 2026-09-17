# Pattern: `revert` (safe undo) and `--amend` (fix the last commit)

## `git revert` — undo by ADDING a new commit

```bash
git revert a1b2c3d                      # create a new commit that undoes a1b2c3d
git revert --no-edit a1b2c3d            # do it without opening the editor
git revert HEAD                         # undo the most recent commit
git revert HEAD~3..HEAD                 # undo the last three commits (three new commits)
git revert -n a1b2c3d                   # -n = no commit: stage the reversal so you can adjust it
git revert -m 1 <merge-commit>          # undo a MERGE: -m 1 keeps parent 1 (usually main)
git revert --continue                   # after resolving conflicts during a revert
git revert --abort                      # cancel a conflicted revert
git log --oneline -3                    # history grows, nothing is rewritten — safe for shared branches
```

**`reset` rewrites history; `revert` adds to it.** On a pushed/shared branch, always use `revert`.

## `git commit --amend` — improve the last commit

```bash
git commit --amend -m "better message"  # rewrite only the message
git commit --amend --no-edit            # keep the message, fold in newly staged changes
git add forgotten-file.txt && git commit --amend --no-edit   # the classic "I forgot a file"
git commit --amend --reset-author       # update author/committer to your current identity
git commit --amend --date="2026-09-01T10:00:00"   # fix a wrong commit date
git show --stat HEAD                    # verify the amended result
```
⚠️ Amending changes the commit's HASH. If you already pushed it, the next push needs
`--force-with-lease`, and teammates must re-sync. Amend only your own unpushed commits.

## Fix a mistake in an OLDER commit (not the last one)

```bash
git commit --fixup a1b2c3d              # create a commit marked "fixup! <that subject>"
git rebase -i --autosquash a1b2c3d~1    # reorder and squash the fixups into their targets automatically
git rebase -i --autosquash --root       # ...use --root instead if a1b2c3d is the VERY FIRST commit
git commit --squash a1b2c3d             # same, but lets you edit the combined message
git config --global rebase.autoSquash true   # make --autosquash the default for every interactive rebase
```

## Undo the undo

```bash
git reflog                              # find the hash from before your mistake
git reset --hard HEAD@{2}               # go back to that exact state
git revert <revert-commit>              # revert the revert to re-apply the original change
```

## Cheat table

| Situation | Command |
|---|---|
| Wrong commit message (not pushed) | `git commit --amend -m "new"` |
| Forgot a file in the last commit | `git add f && git commit --amend --no-edit` |
| Last commit was a bad idea (not pushed) | `git reset --hard HEAD~1` |
| Bad commit ALREADY pushed | `git revert <hash>` |
| Undo a merge commit | `git revert -m 1 <merge-hash>` |
| Fix a typo in a commit from last week | `git commit --fixup <hash>` + autosquash rebase |
