# Pattern: Sorting, de-duplicating, slicing (`sort`, `uniq`, `cut`, `tr`, `xargs`)

```bash
sort names.txt                        # sort lines alphabetically
sort -n numbers.txt                   # -n NUMERIC sort (otherwise "10" comes before "9")
sort -r names.txt                     # -r reverse order
sort -rn numbers.txt                  # biggest numbers first
sort -u names.txt                     # -u unique: sort and remove duplicates in one step
sort -t, -k2 data.csv                 # -t separator ",", -k2 sort by field 2
sort -k3 -n file.txt                  # sort numerically by column 3
uniq file.txt                         # remove ADJACENT duplicates only → so almost always use sort first
sort file.txt | uniq                  # the correct pair: sort, then de-duplicate
sort file.txt | uniq -c               # -c COUNT occurrences of each line
sort file.txt | uniq -c | sort -rn    # count, then sort by count → "most frequent" report
sort file.txt | uniq -d               # -d show only the lines that ARE duplicated
cut -d, -f2 data.csv                  # -d delimiter ",", -f field 2 → extract column 2 of a CSV
cut -d' ' -f1,3 file.txt              # extract fields 1 and 3 (space-delimited)
cut -c1-10 file.txt                   # -c cut by CHARACTER position: first 10 characters of each line
tr 'a-z' 'A-Z' < file.txt             # translate characters: lowercase → UPPERCASE
tr -d ' ' < file.txt                  # -d delete all spaces
tr -s '\n' < file.txt                 # -s squeeze repeated newlines into one
echo "a b c" | tr ' ' '\n'            # turn spaces into newlines (one word per line)
```

## Top-N frequency report (memorise this pipeline)

```bash
awk '{print $1}' access.log | sort | uniq -c | sort -rn | head -10   # 10 most common IPs
```
- `awk` → keep only the first column
- `sort` → group identical values together (uniq needs this)
- `uniq -c` → count how many times each appears
- `sort -rn` → order those counts, biggest first
- `head -10` → show only the top 10

## Practice

Find the 5 most frequently used commands in your shell history:
`history | awk '{$1="";print}' | sort | uniq -c | sort -rn | head -5`
