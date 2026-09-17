# Pattern: Handling text and files inside scripts

```bash
#!/usr/bin/env bash
set -euo pipefail                         # safe mode: stop on any error or unset variable

file="data.csv"

if [[ -f "$file" ]]; then                 # check existence before touching it
    lines=$(wc -l < "$file")              # < reads the file into wc so the filename isn't printed too
    echo "$file has $lines lines"
fi

while IFS=, read -r col1 col2 col3; do    # IFS=, splits each line on commas into 3 variables
    echo "$col1 -> $col3"                 # use the columns
done < "$file"

mapfile -t arr < "$file"                  # read a whole file into an array, one line per element (-t strips newlines)
echo "${#arr[@]} lines loaded"            # count them

names="alice bob carol"
for n in $names; do echo "$n"; done       # unquoted $names splits on spaces (intended here)

printf "%-10s %5d\n" "alice" 42           # formatted output: left-align 10 chars, right-align a number
printf "%s\n" *.txt                       # print each matching filename on its own line (safer than echo)

tmp=$(mktemp)                             # create a unique temporary file
echo "scratch space: $tmp"
trap 'rm -f "$tmp"' EXIT                  # trap: when the script EXITS for any reason, delete the temp file

sed -i.bak 's/old/new/g' "$file"          # edit a file but keep a .bak copy
awk -F, '$3 > 100 {print $1}' "$file"     # filter rows by a numeric column

find . -name "*.log" -print0 | xargs -0 rm    # -print0 / -0 handle filenames with spaces or newlines safely
ls -1 | tr '\n' ' '                       # join a list into one space-separated line

echo "done" >&2                           # write to stderr (for messages that aren't real output)
command 2>/dev/null                       # discard errors inside a script
```

## Reading user input

```bash
read -r -p "Enter your name: " name       # -p prints a prompt, -r keeps backslashes literal
read -r -s -p "Password: " pass; echo     # -s hides what is typed (for passwords)
read -r -t 10 answer                      # -t times out after 10 seconds
read -r -p "Delete? [y/N] " ok            # convention: capital letter = the default
[[ "$ok" =~ ^[Yy]$ ]] && echo "deleting"  # =~ is a regex match inside [[ ]]
```

## Practice

Write a script that reads a CSV of `name,score` and prints only the names with a score above 50.
