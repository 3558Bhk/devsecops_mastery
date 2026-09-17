# Pattern: Searching inside files (`grep`)

`grep` = "print lines that match". The most-used command in Linux.

```bash
grep "error" app.log                  # print every line containing "error"
grep -i "error" app.log               # -i ignore case: matches Error, ERROR, error
grep -n "TODO" main.py                # -n show LINE NUMBERS so you can jump to them
grep -c "error" app.log               # -c just COUNT the matching lines
grep -v "debug" app.log               # -v INVERT: print lines that do NOT match
grep -r "api_key" ./src               # -r recursive: search every file in every subfolder
grep -rl "TODO" .                     # -l list only FILE NAMES that match (l = list)
grep -w "cat" file.txt                # -w whole word only: won't match "concatenate"
grep -A 3 "Exception" app.log         # -A show 3 lines AFTER each match (context)
grep -B 2 "Exception" app.log         # -B show 2 lines BEFORE each match
grep -C 2 "Exception" app.log         # -C show 2 lines before AND after
grep -E "error|fail|warn" app.log     # -E extended regex: | means OR
grep -o "[0-9]\{3\}-[0-9]\{4\}" f.txt # -o print ONLY the matched part (e.g. phone numbers)
grep "root" /etc/passwd               # grep works on system files too — they're just text
grep -c "" file.txt                   # trick: count lines (same as wc -l)
find . -name "*.py" -exec grep -l "import os" {} +   # grep + find = search only certain files
```

## The 5 you'll actually type every day

```bash
grep -i "pattern" file                # case-insensitive search
grep -rn "pattern" .                  # recursive search with line numbers (code hunting)
grep -v "^#" config.conf              # drop comment lines (^# = starts with #)
grep -E "^(GET|POST)" access.log      # lines starting with GET or POST
ps aux | grep nginx                   # find a running process by name (pipe from ps)
```

## Practice

Search your home folder recursively for the word "TODO", listing only filenames.
