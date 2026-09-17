# 02 Repo Basics — Basic Questions

**Q1.** Turn the current folder into a Git repository.
```bash
git init                       # creates the hidden .git/ folder that holds all history
```

**Q2.** Download an existing project from GitHub.
```bash
git clone https://github.com/user/repo.git   # full history + working copy
```

**Q3.** See what has changed since your last commit.
```bash
git status                     # the summary: modified, staged, untracked
```

**Q4.** Put a modified file into the next commit.
```bash
git add file.txt               # stage one file
git add .                      # stage everything under the current folder
```

**Q5.** Record a snapshot with a message.
```bash
git commit -m "add login form" # -m supplies the message on the command line
```

**Q6.** Stage and commit already-tracked files in one command.
```bash
git commit -am "fix typo"      # -a stages modified/deleted TRACKED files (not new untracked ones)
```

**Q7.** Show the difference between your edits and the last commit.
```bash
git diff                       # unstaged changes only
git diff --staged              # what is already staged and will be committed
```

**Q8.** Remove a file from the project and stage the removal.
```bash
git rm file.txt                # deletes it from disk AND stages the deletion
```

**Q9.** Stop tracking a file but keep it on disk.
```bash
git rm --cached file.txt       # removes it from the index only
```

**Q10.** Rename a file the Git way.
```bash
git mv old.txt new.txt         # rename + stage in one step
```

**Q11.** See your last five commits.
```bash
git log --oneline -5           # one line per commit, most recent first
```

**Q12.** What does `??` mean in `git status -s`?
```bash
git status -s                  # ?? = untracked file Git has never seen before
```

**Q13.** Check exactly what you staged before committing.
```bash
git diff --staged              # review the staged diff
git status -s                  # or the compact two-column view
```

**Q14.** Write a one-line-plus-body commit message from the command line.
```bash
git commit -m "subject line" -m "explanation of why this change was needed"
```
