# 02 Listing & Finding — Advanced Questions

**Q1.** Find all `.log` files older than 30 days AND bigger than 10 MB.
```bash
find . -name "*.log" -mtime +30 -size +10M   # conditions next to each other = AND
```

**Q2.** Find `.jpg` OR `.png` files. Why must the brackets be escaped?
```bash
find . \( -name "*.jpg" -o -name "*.png" \)  # -o = OR; \( \) are escaped so find, not the shell, groups them
```

**Q3.** Search everywhere except the `node_modules` folders.
```bash
find . -name "*.js" -not -path "*/node_modules/*"   # -not -path excludes a subtree
```

**Q4.** Run `ls -lh` on every file `find` locates — and explain `{}` and `+`.
```bash
find . -name "*.conf" -exec ls -lh {} +   # {} is replaced by each found path; + batches them (fast)
find . -name "*.conf" -exec ls -lh {} \;  # \; runs the command once per file (slower)
```

**Q5.** Delete every `*.tmp` file you find, but let `find` do the deleting efficiently.
```bash
find . -name "*.tmp" -delete        # built-in delete, faster than -exec rm
find . -name "*.tmp" -exec rm {} +  # equivalent, and works on systems without -delete
```

**Q6.** Find files whose permissions include "owner can execute".
```bash
find . -perm -u+x          # leading - means "at least these bits are set"
find . -perm 777           # no dash = an EXACT match of 777 (dangerous world-writable files)
```

**Q7.** Sort a long listing by size, biggest first, showing human sizes.
```bash
ls -lhS                    # -S sorts by size descending
ls -lhS | head -6          # top 5 largest entries (line 1 is the "total" line)
```

**Q8.** Show the 5 most recently modified files, including hidden ones.
```bash
ls -lhat | head -6         # -a hidden, -t by time; the head count includes the "total" line
```

**Q9.** `locate` finds a file you just deleted. Why?
```bash
sudo updatedb              # locate reads a prebuilt DATABASE; refresh it to match reality
locate -e notes.txt        # -e verifies each result exists before printing it
```

**Q10.** Count how many files `find` matched, without printing them all.
```bash
find . -name "*.md" | wc -l              # pipe the list into a line count
find . -name "*.md" -printf '.' | wc -c  # safer with odd filenames: one dot per match
```

**Q11.** Find files modified in the last 10 minutes (not days).
```bash
find . -mmin -10           # -mmin = minutes; perfect for "what did I just change?"
```

**Q12.** Find all empty files and empty directories.
```bash
find . -empty              # matches zero-byte files and folders with nothing inside
```

**Q13.** Why does `find . -name *.txt` sometimes fail while `-name "*.txt"` works?
```bash
find . -name *.txt         # if the current folder already contains a .txt file, the shell expands the glob first
find . -name "*.txt"       # quotes pass the pattern to find intact — always quote globs in find
```
