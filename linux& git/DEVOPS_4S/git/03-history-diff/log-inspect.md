# Pattern: Reading history with `git log` and `git show`

```bash
git log                                 # full history, newest first (q quits the pager)
git log --oneline                       # one line per commit: short hash + subject
git log -5                              # only the last 5 commits
git log --oneline --graph --all         # ASCII graph of every branch — the best overview
git log --graph --decorate --oneline --all --boundary   # with branch/tag labels and boundaries
git log --stat                          # each commit plus the files and +/- line counts
git log -p                              # each commit with its full diff (p = patch)
git log --author="alex"                 # only commits by this author (substring, case-sensitive)
git log --grep="fix login"              # only commits whose MESSAGE contains this text
git log -S"api_key"                     # "pickaxe": commits that ADDED or REMOVED this string
git log -G"TODO"                        # commits whose DIFF matches this regex
git log -- src/app.js                   # history of one file
git log --follow -- src/app.js          # ...including from before it was renamed
git log --since="2 weeks ago"           # time filters
git log --until="2026-09-01"            # up to a date
git log --since=yesterday --author=alex --oneline   # combine filters
git log main..feature                   # commits on feature that are NOT on main (what a PR contains)
git log --merges                        # only merge commits
git log --no-merges                     # hide merge commits
git log --pretty=format:'%h %an %ad %s' --date=short   # fully custom output
git log --name-only --pretty=format:    # just the file names touched by each commit
git shortlog -sn                        # commit count per author, sorted (great for stats)
git shortlog -sn --since="1 month ago"  # same, for the last month only
```

## Inspecting one commit

```bash
git show                                # the most recent commit (HEAD) with its diff
git show a1b2c3d                        # any commit by hash — the first 7 characters are enough
git show --stat a1b2c3d                 # just the file list and change counts
git show a1b2c3d:src/app.js             # that file's FULL content as of that commit
git show a1b2c3d^                       # the commit's PARENT (^ = one back)
git show HEAD~3                         # three commits back from HEAD (~3 = three generations back)
git diff a1b2c3d HEAD                   # everything that changed between two commits
```

## Useful `--pretty` placeholders

```text
%H full hash      %h short hash     %an author name     %ae author email
%ad author date   %cd commit date   %s subject          %b body
%d ref names      %C(auto)...%Creset colours
```
```bash
git log --pretty=format:'%C(yellow)%h%Creset %ad %C(green)%an%Creset %s' --date=short
```

## Counting and summarising

```bash
git rev-list --count HEAD               # total number of commits on this branch
git rev-list --count main..feature      # commits the feature branch adds
git log --oneline | wc -l               # same count via a pipe
git log --diff-filter=A --name-only --pretty=format: | sort -u   # every file ever ADDED
```
