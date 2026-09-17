# 05 Text Processing — Advanced Questions

**Q1.** Show 3 lines of context after every match.
```bash
grep -A 3 "Exception" app.log   # -A after, -B before, -C both sides
```

**Q2.** Search for either "error", "fail" or "warn" in one pass.
```bash
grep -E "error|fail|warn" app.log   # -E enables extended regex where | means OR
```

**Q3.** Print only the matched part (e.g. every email address), not the whole line.
```bash
grep -oE "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}" file.txt   # -o outputs each match alone
```

**Q4.** Delete every comment line and every blank line from a config file.
```bash
sed -e '/^#/d' -e '/^$/d' config.conf   # two -e expressions applied in order; add -i to save
```

**Q5.** Safely edit a file in place while keeping a backup.
```bash
sed 's/old/new/g' file.txt          # 1. dry run: check the output on screen first
sed -i.bak 's/old/new/g' file.txt   # 2. then edit in place and keep file.txt.bak
```

**Q6.** Use `|` as the sed separator to avoid escaping slashes in paths.
```bash
sed 's|/usr/local|/opt|g' paths.txt  # any character can be the delimiter
```

**Q7.** Swap captured groups with sed (turn `user@domain` into `domain/user`).
```bash
sed -E 's/([^@]+)@(.+)/\2\/\1/' emails.txt   # -E for regex groups; \1 and \2 are the captures
```

**Q8.** Sum all numbers in column 3 and print the average.
```bash
awk '{sum+=$3; n++} END {print sum, sum/n}' data.txt   # END block runs once after the last line
```

**Q9.** Print only lines where column 3 is greater than 100.
```bash
awk '$3 > 100 {print $1, $3}' data.txt   # a condition before { } filters the rows
```

**Q10.** Skip a header row and warn about disks over 80% full.
```bash
df -h | awk 'NR>1 && $5+0 > 80 {print "LOW SPACE:", $6, $5}'   # NR>1 skips the header; $5+0 forces numeric
```

**Q11.** Remove duplicate lines while preserving the original order.
```bash
awk '!seen[$0]++' file.txt   # prints a line only the first time it appears
```

**Q12.** Build a top-10 frequency report from a column.
```bash
awk '{print $1}' access.log | sort | uniq -c | sort -rn | head -10
# extract column → group identical values → count → sort counts descending → keep 10
```

**Q13.** Print the last column of every line, whatever the column count.
```bash
awk '{print $NF}' file.txt   # NF = number of fields on this line, so $NF is the last one
```

**Q14.** Convert a one-word-per-line list into a comma-separated line.
```bash
paste -sd, list.txt          # -s serialise into one line, -d use comma as the delimiter
tr '\n' ',' < list.txt       # or translate newlines into commas
```

**Q15.** Edit only the 5th line of a file with sed.
```bash
sed -i '5s/old/new/' file.txt   # the leading 5 restricts the substitution to line 5
```
