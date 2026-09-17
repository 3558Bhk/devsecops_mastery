# Pattern: Who wrote this, and when? (`blame`, archaeology)

```bash
git blame src/app.js                    # every line prefixed with its commit, author and date
git blame -L 20,35 src/app.js           # only lines 20 to 35 (much more readable)
git blame -L :functionName src/app.js   # only the lines of a named function (regex-based)
git blame -w src/app.js                 # -w ignore whitespace-only changes
git blame -C -M src/app.js              # -C detect code COPIED from other files, -M moved within a file
git blame -L 10,10 HEAD~5 src/app.js    # blame as it looked five commits ago
git blame --line-porcelain src/app.js | grep "^author " | sort | uniq -c | sort -rn   # lines per author
git log -1 a1b2c3d                      # after blaming, inspect the commit behind a line
git show a1b2c3d -- src/app.js          # see exactly what that commit changed in this file
```

## Trace a file's full life

```bash
git log --follow -p -- src/app.js       # -p shows every change; --follow survives renames
git log --follow --name-status -- src/app.js   # see the rename events themselves
git log --diff-filter=R --name-status --summary   # every rename in the repo
```

## Search the codebase and its history

```bash
git grep "TODO"                         # search the WORKING TREE (much faster than grep -r, respects .gitignore)
git grep -n "api_key"                   # with line numbers
git grep -i "error" -- '*.js'           # case-insensitive, limited to .js files
git grep "oldFunction" $(git rev-list --all)   # search EVERY commit ever (slow but thorough)
git grep "oldFunction" v1.0             # search inside one tag/commit
git log -S"oldFunction" --oneline       # commits that added or removed that string (pickaxe)
git log -G"console\.log" --oneline      # commits whose diff matches a regex
git log --all --oneline --grep "revert" # search commit MESSAGES across all branches
```

## Answer "when did this break?"

```bash
git log -S"brokenCall" --oneline -- src/app.js   # find the commit that introduced it
git bisect start                                 # binary-search the history automatically
git bisect bad                                   # mark the current (broken) commit
git bisect good v1.0                             # mark a known-good older commit
git bisect run ./test.sh                         # let Git find the culprit by running your test
git bisect reset                                 # return to where you started
```

## Find out what a colleague has been doing

```bash
git log --author="alex" --since="1 week ago" --stat     # their commits this week with file stats
git shortlog -sn --author="alex"                        # their total commit count
git log --all --author="alex" --oneline --graph         # across every branch
```
