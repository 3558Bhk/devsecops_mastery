# 05 Undo & Fix Mistakes — Advanced Questions

**Q1.** Compare the three reset modes by what they touch.
```bash
git reset --soft  HEAD~1       # moves HEAD/branch only — index and working tree untouched
git reset --mixed HEAD~1       # moves HEAD + resets the INDEX — working tree untouched (default)
git reset --hard  HEAD~1       # moves HEAD + index + WORKING TREE — everything discarded
```

**Q2.** Collapse the last five commits into one, keeping all changes.
```bash
git reset --soft HEAD~5                        # unwind five commits, leave everything staged
git commit -m "feat: complete checkout flow"   # one clean commit
git log --oneline -3                           # verify
```

**Q3.** Undo a merge commit that is already on a shared branch.
```bash
git log --oneline --merges -1                  # find the merge hash and confirm parent order
git show --format='%P' -s <merge>              # prints the parents: first = the branch you merged INTO
git revert -m 1 <merge>                        # keep parent 1 (usually main), undo the rest
git push
```
Afterwards, re-merging that same branch will do nothing — Git thinks it is already merged.
Re-apply with `git revert <the-revert-commit>` or rebase the feature branch to new hashes.

**Q4.** Fix a typo inside a commit that is five commits old.
```bash
git commit --fixup <old-hash>                  # commit the fix, marked for that target
git config --global rebase.autoSquash true     # optional: always autosquash
GIT_SEQUENCE_EDITOR=: git rebase -i --autosquash <old-hash>~1   # non-interactive squash
git rebase -i --autosquash --root              # if the target is the very first commit
```

**Q5.** Recover a commit lost to `git reset --hard`.
```bash
git reflog                                     # find the hash from before the reset
git switch -c rescue <hash>                    # save it on a new branch
git cherry-pick <hash>                         # or copy just that commit onto your current branch
git fsck --lost-found                          # if the reflog entry is gone, look for dangling commits
```

**Q6.** Recover a branch you deleted with `git branch -D`.
```bash
git reflog | grep "checkout: moving from feature"   # find the last time you were on it
git branch feature <hash>                           # recreate the branch at that commit
git log --oneline feature -3                        # verify
```

**Q7.** Undo only PART of a commit.
```bash
git revert -n <hash>                           # stage the reversal without committing
git restore --staged --worktree path/to/keep   # drop the parts you want to keep reverted-as-was
git commit -m "partially revert <hash>"
```

**Q8.** Undo the changes a single file received in one commit.
```bash
git restore --source=<hash>^ --staged --worktree src/app.js   # restore the pre-commit version
git commit -m "revert src/app.js changes from <hash>"
```

**Q9.** A rebase went badly wrong halfway through.
```bash
git rebase --abort                             # still in progress: cancel and return to the start
git reflog | head -5                           # already finished: find the pre-rebase hash
git reset --hard ORIG_HEAD                     # ORIG_HEAD is set automatically before a rebase/merge
```

**Q10.** You dropped a stash you needed.
```bash
git fsck --unreachable | grep commit           # dropped stashes survive as unreachable commits
git stash apply <hash>                         # re-apply it
git stash list                                 # check whether it is still listed at all
```

**Q11.** Undo a `git add` of a huge or secret file before committing.
```bash
git restore --staged secret.key                # unstage it
echo "secret.key" >> .gitignore                # stop it happening again
git status -s                                  # confirm it is untracked (??) again
```

**Q12.** Reset one file to HEAD while leaving the rest of your work alone.
```bash
git restore --source=HEAD --staged --worktree src/app.js   # both areas, one file
git checkout HEAD -- src/app.js                            # older equivalent
```
