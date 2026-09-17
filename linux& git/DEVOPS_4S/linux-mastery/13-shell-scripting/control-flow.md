# Pattern: `if`, loops, and tests

```bash
#!/usr/bin/env bash                       # a script demonstrating every control structure

# ---------- IF ----------
if [ -f notes.txt ]; then                 # -f true if it's a regular file that exists
    echo "file exists"                    # indentation is cosmetic; bash ignores it, humans don't
elif [ -d notes.txt ]; then               # -d true if it's a directory
    echo "it is a folder"
else
    echo "not found"
fi                                        # fi = "if" backwards; every if needs one

[ -e path ]                               # exists (any type)        [ -r f ] readable
[ -w f ]                                  # writable                [ -x f ] executable
[ -s f ]                                  # file exists and is NOT empty
[ -z "$VAR" ]                             # string is EMPTY         [ -n "$VAR" ] string is NOT empty
[ "$a" = "$b" ]                           # strings equal           [ "$a" != "$b" ] not equal
[ "$n" -eq 5 ]                            # numbers: -eq equal, -ne not equal
[ "$n" -gt 5 ]                            # -gt greater, -lt less, -ge >=, -le <=
[ "$a" = "x" ] && [ "$b" = "y" ]          # AND inside [ ]
[ "$a" = "x" ] || [ "$b" = "y" ]          # OR inside [ ]
[[ $n -gt 5 && $name == A* ]]             # [[ ]] is the modern form: && || and patterns work inside
if command -v git >/dev/null; then echo yes; fi   # check whether a program is installed

# ---------- FOR ----------
for f in *.txt; do echo "$f"; done        # loop over every .txt file in this folder
for i in 1 2 3; do echo "$i"; done        # loop over an explicit list
for i in {1..5}; do echo "$i"; done       # loop over a numeric range
for i in $(seq 1 10 2); do echo "$i"; done   # seq START STEP END → 1 3 5 7 9
for f in "$@"; do echo "$f"; done         # loop over the arguments given to the script

# ---------- WHILE ----------
while read -r line; do                    # read a file line by line; -r stops backslash mangling
    echo ">> $line"
done < data.txt                           # < feeds the file into the loop
n=0; while [ $n -lt 3 ]; do               # classic counter loop
    echo $n; n=$((n+1))                   # increment (bash has no n++)
done
until [ -f ready.flag ]; do sleep 1; done  # repeat UNTIL a condition becomes true

# ---------- C-style loop ----------
for ((i=0; i<5; i++)); do echo $i; done   # familiar to programmers of C/Java/JS
```

## The three classic beginner bugs

```bash
[ $VAR = "x" ]                            # BREAKS if $VAR is empty → syntax error
[ "$VAR" = "x" ]                          # FIXED: always quote your variables
for f in $(ls); do ...; done              # BREAKS on filenames with spaces
for f in *; do ...; done                  # FIXED: use the glob directly
#!/bin/sh with [[ ]]                      # BREAKS: [[ ]] is bash-only, so use #!/usr/bin/env bash
```

## Practice

Write a script that loops over all `.md` files here and prints each filename plus its line count
(`wc -l < "$f"`).
