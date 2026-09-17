# 04 Branching & Merging — Basic Questions

**Q1.** List all local branches and see which one you are on.
```bash
git branch                     # the * marks the current branch
git branch --show-current      # prints just the current branch name
```

**Q2.** Create a new branch.
```bash
git branch feature/login       # creates it but you STAY where you are
```

**Q3.** Create a branch and switch to it in one step.
```bash
git switch -c feature/login    # modern command
git checkout -b feature/login  # older equivalent
```

**Q4.** Switch to an existing branch.
```bash
git switch main                # move your working tree to main
```

**Q5.** Jump back to the branch you were just on.
```bash
git switch -                   # like "cd -" for branches
```

**Q6.** Merge a feature branch into main.
```bash
git switch main                # go to the RECEIVING branch first
git merge feature              # then merge the other one into it
```

**Q7.** See the branch structure as a picture.
```bash
git log --oneline --graph --all
```

**Q8.** Rename a branch.
```bash
git branch -m oldname newname  # -m = move/rename
```

**Q9.** Delete a branch safely.
```bash
git branch -d feature          # refuses if the branch is not merged yet
```

**Q10.** Delete a branch even if it has unmerged commits.
```bash
git branch -D feature          # force delete — those commits become hard to reach
```

**Q11.** What is a "fast-forward" merge?
```bash
git merge --ff-only feature    # succeeds only when main has not moved since the branch point
```
Git simply slides the `main` pointer forward; no merge commit is created.

**Q12.** Discard your uncommitted edits to one file.
```bash
git restore file.txt           # restores it from the index/HEAD (⚠️ no undo)
```

**Q13.** Unstage a file without losing your edits.
```bash
git restore --staged file.txt  # removes it from the staging area only
```

**Q14.** List branches that are already merged into main.
```bash
git branch --merged main       # these are safe to delete
```

**Q15.** Look at an old commit or tag without being on a branch.
```bash
git switch --detach v1.0       # detached HEAD: read-only exploration
git switch main                # come back
```
