# 05 Text Processing — Scenario Questions

## Scenario 1
A 2 GB access log. Which 10 IP addresses hit the server most?
```bash
awk '{print $1}' access.log | sort | uniq -c | sort -rn | head -10
```
- `awk '{print $1}'` → keep only the IP column
- `sort` → group identical IPs together (uniq requires this)
- `uniq -c` → count each group
- `sort -rn` → order by count, biggest first
- `head -10` → top 10 only

## Scenario 2
Your app writes `status=OK` / `status=FAIL` lines. Count each status.
```bash
grep -o 'status=[A-Z]*' app.log | sort | uniq -c    # -o isolates just the status token
awk -F'status=' '{print $2}' app.log | cut -d' ' -f1 | sort | uniq -c   # same via field splitting
```

## Scenario 3
A config file was deployed with the wrong database host everywhere. Fix it safely.
```bash
cp app.conf app.conf.bak                              # backup first
grep -n "db.internal" app.conf                        # see every line that will change
sed 's/db\.internal/db-prod.internal/g' app.conf      # DRY RUN: inspect the output
sed -i 's/db\.internal/db-prod.internal/g' app.conf   # then apply it to the file
grep -n "db-prod.internal" app.conf                   # verify the change took effect
```
Note the escaped dots: in regex `.` means "any character", so `\.` means a literal dot.

## Scenario 4
Extract usernames and home directories from `/etc/passwd` as a readable table.
```bash
awk -F: '{printf "%-15s %s\n", $1, $6}' /etc/passwd   # field 1 = user, field 6 = home; printf aligns columns
cut -d: -f1,6 /etc/passwd | column -t -s:             # same idea: cut the fields, then align them
```

## Scenario 5
Find every Python file in the repo that imports `os` but not `sys`.
```bash
grep -rl "import os" --include="*.py" .              # -l lists matching filenames only
grep -rl "import os" --include="*.py" . | xargs grep -L "import sys"   # -L lists files that DON'T match
```

## Scenario 6
Strip all comment and blank lines from a config to see the real settings, then save it.
```bash
grep -vE '^\s*(#|;|$)' config.ini > config.clean.ini  # drop #/; comments and empty lines
wc -l config.ini config.clean.ini                     # compare before and after
```

## Scenario 7
A CSV export has 5 columns; you need column 4 sorted numerically, top 5.
```bash
cut -d, -f4 sales.csv | tail -n +2 | sort -rn | head -5   # tail -n +2 skips the header row
awk -F, 'NR>1 {print $4}' sales.csv | sort -rn | head -5  # the awk equivalent
```

## Scenario 8
Convert a Windows-generated text file to proper Unix format.
```bash
file notes.txt                    # confirms "with CRLF line terminators"
sed -i 's/\r$//' notes.txt        # delete the trailing carriage return on every line
cat -A notes.txt | head           # verify: lines should end with $ and no ^M
```

## Scenario 9
You need the total size of all `.log` files reported by `ls -l`, in bytes.
```bash
ls -l *.log | awk '{sum+=$5} END {print sum " bytes"}'   # column 5 of ls -l is the size
du -ch *.log | tail -1                                   # or let du total it for you (-c = grand total)
```

## Scenario 10
Find which user ran `sudo` most often today.
```bash
sudo grep "$(date +%b\ %e)" /var/log/auth.log | grep sudo | awk '{print $5}' | sort | uniq -c | sort -rn
# filter today's date → keep sudo lines → take the username column → count → rank
```
