# 05 Undo & Fix Mistakes — Basic Questions

**Q1.** Discard your uncommitted edits to one file.
```bash
git restore file.txt           # restores it from HEAD (⚠️ your edits are gone for good)
```

**Q2.** Unstage a file you added by accident, keeping your edits.
```bash
git restore --staged file.txt  # removes it from the staging area only
```

**Q3.** Undo your last commit but keep the changes staged.
```bash
git reset --soft HEAD~1        # HEAD moves back one commit; the index keeps everything
```

**Q4.** Undo your last commit and unstage the changes (files stay on disk).
```bash
git reset HEAD~1               # --mixed is the default mode
```

**Q5.** Undo your last commit AND delete its changes.
```bash
git reset --hard HEAD~1        # ⚠️ unrecoverable for anything not committed elsewhere
```

**Q6.** Change the message of the commit you just made.
```bash
git commit --amend -m "new, correct message"
```

**Q7.** Add a file you forgot to the last commit.
```bash
git add forgotten.txt          # stage it
git commit --amend --no-edit   # fold it in without touching the message
```

**Q8.** Safely undo a commit that you already pushed.
```bash
git revert a1b2c3d             # adds a NEW commit that reverses it — history is not rewritten
```

**Q9.** Undo your most recent commit safely (without rewriting history).
```bash
git revert HEAD                # or git revert --no-edit HEAD to skip the editor
```

**Q10.** List every action Git recorded, so you can find "lost" work.
```bash
git reflog                     # commits, checkouts, resets, merges — with hashes
```

**Q11.** Go back to the exact state from two reflog steps ago.
```bash
git reset --hard HEAD@{2}      # HEAD@{n} counts back through the reflog
```

**Q12.** Delete untracked files you created by mistake.
```bash
git clean -n                   # DRY RUN first: shows what would be deleted
git clean -fd                  # then delete untracked files and directories
```

**Q13.** Cancel a merge that has conflicts.
```bash
git merge --abort              # returns you to the state before the merge started
```

**Q14.** Make your local branch identical to the remote's, discarding local commits.
```bash
git fetch origin                       # refresh the remote-tracking branches
git reset --hard origin/main           # ⚠️ your local-only commits become unreachable
```
