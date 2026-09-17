# 03 History & Diff — Advanced Questions

**Q1.** What is the difference between `git diff main..feature` and `git diff main...feature`?
```bash
git diff main..feature         # two dots: everything that differs between the two tips
git diff main...feature        # three dots: only what feature changed SINCE it branched off
git merge-base main feature    # the common ancestor that the three-dot form starts from
```
Use three dots for code review — it hides changes that landed on `main` afterwards.

**Q2.** Find the commit that introduced a specific string.
```bash
git log -S"buggyFunction" --oneline      # pickaxe: commits that ADDED or REMOVED that text
git log -S"buggyFunction" -p -- src/app.js   # with the diff, limited to one file
git log -G"console\.log" --oneline       # -G matches a regex anywhere in the diff
```

**Q3.** Trace a file's history through a rename.
```bash
git log --follow --name-status -- src/app.js   # --follow keeps the trail across renames
git log --diff-filter=R --summary              # list every rename in the repo
```

**Q4.** Get a file's content as of an old commit without checking it out.
```bash
git show a1b2c3d:src/app.js            # print it to stdout
git show a1b2c3d:src/app.js > /tmp/old-app.js   # or save it
git diff a1b2c3d -- src/app.js         # compare that version with your current one
```

**Q5.** Understand `HEAD~2` versus `HEAD^2`.
```bash
git log --oneline --graph -6           # look at the shape first
git show HEAD~2                        # ~ = go back 2 generations following FIRST parents
git show HEAD^                         # ^ = the first parent
git show HEAD^2                        # ^2 = the SECOND parent — only exists on a MERGE commit
```

**Q6.** Ignore whitespace when reviewing a badly formatted diff.
```bash
git diff -w                            # ignore all whitespace changes
git diff --ignore-space-at-eol         # ignore only line-ending differences (CRLF noise)
git blame -w -C -M src/app.js          # cleaner blame: ignore whitespace, detect moved/copied code
```

**Q7.** Count commits per author for a report.
```bash
git shortlog -sn                       # sorted commit counts per author
git shortlog -sn --since="1 month ago" --no-merges   # last month, excluding merge commits
git log --pretty='%an' | sort | uniq -c | sort -rn   # the same with plain shell tools
```

**Q8.** List every file ever added to the repository.
```bash
git log --diff-filter=A --name-only --pretty=format: | sort -u | grep -v '^$'
# A = added files only; --pretty=format: suppresses commit headers; sort -u de-duplicates
```

**Q9.** Export the last three commits as patches to email someone.
```bash
git format-patch -3 HEAD               # creates 0001-*.patch, 0002-*.patch, 0003-*.patch
git format-patch main..feature -o /tmp/patches   # every commit the branch adds, into a folder
git am /tmp/patches/*.patch            # the recipient applies them, recreating the commits
```

**Q10.** See what changed between two tags.
```bash
git diff v1.0 v1.1 --stat              # summary of the release
git log v1.0..v1.1 --oneline           # the commits in that release (release notes!)
git log v1.0..v1.1 --pretty=format:'* %s (%an)'   # formatted as a changelog
```

**Q11.** Find which commit deleted a file.
```bash
git log --diff-filter=D --summary -- path/to/gone.txt   # D = deleted
git log --all --full-history -- path/to/gone.txt        # include branches where it still exists
```

**Q12.** Diff two files that are not in any repository.
```bash
git diff --no-index a.txt b.txt        # works anywhere; exit code 1 means "they differ"
git diff --no-index --stat dir1/ dir2/ # compare two whole folders
```

**Q13.** Search EVERY commit in history for a string (last resort — it is slow).
```bash
git grep "oldSecret" $(git rev-list --all)     # searches all revisions
git log --all -S"oldSecret" --oneline          # usually faster and enough
```
