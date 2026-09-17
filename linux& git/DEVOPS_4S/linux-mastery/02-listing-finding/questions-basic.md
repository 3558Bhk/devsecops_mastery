# 02 Listing & Finding — Basic Questions

**Q1.** Which `ls` option shows permissions, owner, size and date?
```bash
ls -l                    # long listing format
```

**Q2.** How do you see hidden files (those starting with a dot)?
```bash
ls -a                    # -a = all, including dotfiles like .bashrc
```

**Q3.** Make file sizes readable (KB/MB/GB) in a long listing.
```bash
ls -lh                   # -h = human-readable sizes (needs -l to show size at all)
```

**Q4.** List files with the newest modification first.
```bash
ls -lt                   # -t sorts by modification time, newest on top
```

**Q5.** What does the `-d` flag do in `ls -ld /tmp`?
```bash
ls -ld /tmp              # show the folder ITSELF instead of its contents
```

**Q6.** Find a file by its exact name in the current folder and below.
```bash
find . -name "notes.txt" # . = start here; -name matches the filename exactly
```

**Q7.** Find all `.log` files anywhere under `/var`.
```bash
find /var -name "*.log"  # quotes stop your shell from expanding the * before find sees it
```

**Q8.** Make `find` ignore capital letters in the name.
```bash
find . -iname "readme.md"  # -i = case-insensitive: matches README.md too
```

**Q9.** Find only directories, not files.
```bash
find . -type d           # -type d = directories; -type f = regular files; -type l = symlinks
```

**Q10.** Find files bigger than 100 MB.
```bash
find . -size +100M       # + means "greater than"; use - for smaller than
```

**Q11.** Find files modified in the last 24 hours.
```bash
find . -mtime -1         # -mtime counts days; -1 = within the last day
```

**Q12.** Which command tells you the full path of an installed program?
```bash
which python3            # prints the executable that runs when you type "python3"
```

**Q13.** Search the whole disk for a file while hiding "Permission denied" noise.
```bash
find / -name "passwd" 2>/dev/null   # 2>/dev/null throws error messages away
```

**Q14.** List every file in the current folder and all subfolders (without `tree`).
```bash
ls -R                    # -R = recursive listing
```
