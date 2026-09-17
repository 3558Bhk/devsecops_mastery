# 02 Repo Basics — Advanced Questions

**Q1.** Stage only PART of a file's changes.
```bash
git add -p file.js             # walks through each hunk: y=stage, n=skip, s=split, e=edit manually
git add -p                     # do it for every modified file
```

**Q2.** What is the exact difference between `git add .`, `git add -A` and `git add -u`?
```bash
git add .                      # everything under the CURRENT directory (modern Git: includes deletions)
git add -A                     # everything in the WHOLE repository, regardless of where you stand
git add -u                     # only already-TRACKED files: modifications and deletions, no new files
```

**Q3.** See what `git add -A` WOULD stage, without staging anything.
```bash
git add -An                    # -n = dry run: prints the list and changes nothing
git status                     # cross-check
```

**Q4.** Compare the working tree against the index AND the index against HEAD in one view.
```bash
git diff                       # working tree vs index (unstaged)
git diff --staged              # index vs HEAD (staged)
git diff HEAD                  # working tree vs HEAD (both combined)
git status -sb                 # compact version of the same information
```

**Q5.** List exactly which files Git is tracking.
```bash
git ls-files                   # every tracked file in the index
git ls-files -m                # only the modified ones
git ls-files --others --exclude-standard   # untracked and not ignored
git ls-files --stage           # with mode, hash and stage number (needed during conflicts)
```

**Q6.** Commit a snapshot without changing the working tree — inspect what's really in the index.
```bash
git show HEAD:src/app.js       # the committed version of a file
git cat-file -p HEAD^{tree}    # the tree object: the folder listing inside the commit
git write-tree                 # print the tree hash the index currently represents
```

**Q7.** Add the last commit's changes to a new commit — i.e. fix the previous one.
```bash
git commit --amend --no-edit   # fold staged changes into HEAD, keep the message
git commit --amend -m "new message"   # also rewrite the message
git log --oneline -2           # verify: still the same number of commits, new hash
```
Never amend a commit you already pushed to a shared branch.

**Q8.** Understand `git init --bare` and when you need it.
```bash
git init --bare /srv/git/project.git   # no working tree — only the .git contents at the top level
git remote add origin /srv/git/project.git   # other machines push to it
```
A bare repo is a push target (a private "server"); you cannot edit files inside it.

**Q9.** Clone a huge repo but only work with the latest snapshot.
```bash
git clone --depth 1 <url>              # one commit deep: fast, small
git fetch --unshallow                  # later: download the full history if you need it
```

**Q10.** Make an empty commit that still triggers CI.
```bash
git commit --allow-empty -m "chore: retrigger pipeline"
```

**Q11.** Detect whether a script is running inside a Git repository.
```bash
git rev-parse --is-inside-work-tree 2>/dev/null || echo "not a repo"
git rev-parse --show-toplevel        # the repo root, useful for absolute paths in scripts
```

**Q12.** Why did `git commit -am` not include my new file?
```bash
git status -s                        # new files show as ?? — -a only handles TRACKED files
git add newfile.txt && git commit -m "add newfile"   # add new files explicitly
```
