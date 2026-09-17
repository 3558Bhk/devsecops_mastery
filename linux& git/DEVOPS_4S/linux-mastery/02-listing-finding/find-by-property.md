# Pattern: Finding files by size, age, owner, type

```bash
find . -type f                        # only regular FILES
find . -type d                        # only DIRECTORIES (folders)
find . -type l                        # only symbolic links (shortcuts)
find . -size +100M                    # files BIGGER than 100 megabytes
find . -size -10k                     # files SMALLER than 10 kilobytes
find . -size +1G -exec ls -lh {} \;   # find huge files and show them nicely
find . -mtime -1                      # MODIFIED in the last 1 day (24 hours)
find . -mtime +7                      # modified more than 7 days ago
find . -mmin -10                      # modified in the last 10 MINUTES (handy: "what just changed?")
find . -newer reference.txt           # newer than some other file
find . -empty                         # zero-byte files and empty folders
find . -user alex                     # owned by user "alex"
find . -perm 777                      # exact permission bits 777 (world-writable = risky)
find . -perm -u+x                     # permission includes: owner can execute (- means "at least")
```

## Combining conditions (the powerful part)

```bash
find . -name "*.log" -size +10M                 # AND is implicit: both must be true
find . -name "*.log" -mtime +30 -delete         # old logs over 30 days → delete (classic cleanup)
find . \( -name "*.jpg" -o -name "*.png" \)     # OR: -o, brackets need escaping from the shell
find . -name "*.bak" -not -path "*/node_modules/*"   # exclude a folder with -not -path
find /var/log -type f -size +50M -mtime +7      # real-world: big old logs worth archiving
```

## Practice

List files in your home folder bigger than 50 MB, sorted by size.
