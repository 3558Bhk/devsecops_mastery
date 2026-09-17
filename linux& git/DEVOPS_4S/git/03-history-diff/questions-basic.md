# 03 History & Diff — Basic Questions

**Q1.** Show the commit history one line per commit.
```bash
git log --oneline              # short hash + subject line
```

**Q2.** Show the last 3 commits only.
```bash
git log -3                     # or: git log --oneline -3
```

**Q3.** Draw the branch structure as a graph.
```bash
git log --oneline --graph --all   # --all includes every branch, not just the current one
```

**Q4.** See which files each commit touched.
```bash
git log --stat                 # file names with insertion/deletion counts
git log --name-only            # just the names
```

**Q5.** See the actual code changes of every commit.
```bash
git log -p                     # p = patch: the full diff per commit
```

**Q6.** Inspect the most recent commit in detail.
```bash
git show                       # HEAD's message plus its diff
git show a1b2c3d               # any other commit by its short hash
```

**Q7.** Show your uncommitted edits.
```bash
git diff                       # working directory vs staging area
```

**Q8.** Show what the next commit will contain.
```bash
git diff --staged              # staging area vs HEAD
```

**Q9.** Compare two branches.
```bash
git diff main feature          # full difference between the two tips
```

**Q10.** Limit the log to one file.
```bash
git log -- src/app.js          # only commits that touched this path
```

**Q11.** Find commits by a specific author.
```bash
git log --author="alex"        # matches the author name or email as a substring
```

**Q12.** Find commits whose message mentions a word.
```bash
git log --grep="login"         # searches commit messages
```

**Q13.** See commits from the last two weeks.
```bash
git log --since="2 weeks ago"  # also accepts --until, or absolute dates
```

**Q14.** Find out who last changed a specific line.
```bash
git blame src/app.js           # annotates every line with commit, author and date
git blame -L 20,35 src/app.js  # only lines 20-35, so the output stays readable
```

**Q15.** Search for a string in the current code.
```bash
git grep "api_key"             # faster than grep -r and it skips ignored files
```
