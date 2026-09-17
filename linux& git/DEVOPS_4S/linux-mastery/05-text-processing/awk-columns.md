# Pattern: Working with columns (`awk`)

`awk` splits every line into fields ($1, $2, ...) separated by whitespace. Think of it as
"Excel for text files". `$0` = the whole line.

```bash
awk '{print $1}' file.txt             # print column 1 of every line
awk '{print $1, $3}' file.txt         # print columns 1 and 3
awk '{print $NF}' file.txt            # NF = number of fields, so $NF = the LAST column
awk -F: '{print $1}' /etc/passwd      # -F sets the separator — here ":" instead of spaces
awk -F, '{print $2}' data.csv         # read column 2 of a CSV file
ls -l | awk '{print $9, $5}'          # after ls -l, show filename ($9) and size ($5)
awk '$3 > 100 {print $1, $3}' f.txt   # condition: only rows where column 3 is greater than 100
awk '/error/ {print $2}' app.log      # only lines matching "error", then print their column 2
awk '{sum += $1} END {print sum}' n.txt   # add up column 1; END block runs once after all lines
awk '{sum+=$1; n++} END {print sum/n}' n.txt   # average of column 1
awk 'NR==5' file.txt                  # NR = current record (line) number → print only line 5
awk 'NR>=2 && NR<=4' file.txt         # print lines 2 through 4
awk '!seen[$0]++' file.txt            # remove duplicate lines while keeping the first (classic idiom)
df -h | awk 'NR>1 {print $6, $5}'     # skip the header row (NR>1), show mount point and usage %
ps aux | awk '{print $11}' | sort | uniq -c | sort -rn | head    # top running program names
```

## One real example, fully explained

```bash
df -h | awk 'NR>1 && $5+0 > 80 {print "LOW SPACE:", $6, $5}'   # warn on disks over 80% full
```
- `df -h` → list disks with human sizes
- `NR>1` → skip the header line
- `$5+0` → turn the "83%" text into a number for comparison
- `> 80` → only rows above 80%
- `{print ...}` → what to output for those rows

## Practice

Use `awk` to print just the usernames (column 1) from `/etc/passwd`.
