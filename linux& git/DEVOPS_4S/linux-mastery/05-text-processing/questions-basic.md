# 05 Text Processing — Basic Questions

**Q1.** Print every line containing "error" from a log.
```bash
grep "error" app.log     # grep prints matching lines
```

**Q2.** Make that search case-insensitive.
```bash
grep -i "error" app.log  # matches error, Error, ERROR
```

**Q3.** Count how many lines contain "error".
```bash
grep -c "error" app.log  # -c prints only the count
```

**Q4.** Show lines that do NOT contain "debug".
```bash
grep -v "debug" app.log  # -v inverts the match
```

**Q5.** Search every file in a project folder recursively.
```bash
grep -r "api_key" ./src  # -r walks into all subfolders
```

**Q6.** Replace the first "cat" with "dog" on each line (display only).
```bash
sed 's/cat/dog/' pets.txt   # s = substitute; without -i the file is untouched
```

**Q7.** Replace ALL occurrences and save the change to the file.
```bash
sed -i 's/cat/dog/g' pets.txt   # g = global (every match per line), -i = edit the file in place
```

**Q8.** Print only column 1 of a space-separated file.
```bash
awk '{print $1}' file.txt   # awk splits each line into $1, $2, ... fields
```

**Q9.** Extract column 2 of a CSV file.
```bash
awk -F, '{print $2}' data.csv   # -F, sets the field separator to a comma
```

**Q10.** Sort a file alphabetically, then numerically.
```bash
sort names.txt             # alphabetical (text order)
sort -n numbers.txt        # -n numeric: otherwise "10" sorts before "9"
```

**Q11.** Remove duplicate lines from a file.
```bash
sort file.txt | uniq       # uniq only sees ADJACENT duplicates, so sort first
sort -u file.txt           # or do both in one step
```

**Q12.** Count how many times each line appears.
```bash
sort file.txt | uniq -c    # -c prefixes each unique line with its count
```

**Q13.** Cut field 2 out of a colon-separated file.
```bash
cut -d: -f2 /etc/passwd    # -d delimiter, -f field number
```

**Q14.** Convert a file's text to upper case.
```bash
tr 'a-z' 'A-Z' < file.txt  # tr translates characters; < feeds the file in as input
```
