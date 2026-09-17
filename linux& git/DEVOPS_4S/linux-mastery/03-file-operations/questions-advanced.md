# 03 File Operations — Advanced Questions

**Q1.** Copy a folder while preserving permissions, timestamps and owner.
```bash
cp -a src/ dst/          # -a = archive: recursive + preserve everything; the right choice for backups
cp -p file.txt keep.txt  # -p preserves attributes for a single file
```

**Q2.** What is the difference between `cp -r src dest` and `cp -r src/. dest`?
```bash
cp -r src dest           # if dest exists, you get dest/src (the folder itself is copied inside)
cp -r src/. dest         # copies the CONTENTS of src directly into dest
```

**Q3.** Move a file but never overwrite an existing one.
```bash
mv -n file.txt docs/     # -n = no-clobber: skips silently instead of replacing
mv -i file.txt docs/     # -i = asks you first
```

**Q4.** Rename every `.jpeg` in a folder to `.jpg` using a loop.
```bash
for f in *.jpeg; do mv "$f" "${f%.jpeg}.jpg"; done   # ${f%.jpeg} strips the old extension
```

**Q5.** Explain the difference between a hard link and a symbolic link.
```bash
ln target.txt hard.txt   # hard link: a second name for the SAME data (same inode)
ln -s target.txt soft.txt  # soft link: a small file containing a PATH to the target
ls -li target.txt hard.txt soft.txt   # -i shows inodes: hard shares the number, soft does not
stat -c %h target.txt    # hard-link count: 2 means two names point at one file
```
Delete the original: the hard link still gives full access; the soft link becomes dangling.

**Q6.** Resolve a symlink chain to its final real path.
```bash
readlink -f ~/hosts      # -f follows every link until it reaches a real file
realpath ~/hosts         # modern equivalent, also works on directories
```

**Q7.** Why is `rm -rf "$DIR"/` dangerous, and how do you protect against it?
```bash
# if $DIR is empty the command becomes rm -rf /
echo "${DIR:?DIR must be set}/"   # :? aborts immediately when the variable is empty or unset
```

**Q8.** Create a file that is guaranteed empty, using three different methods.
```bash
> empty.txt              # truncation redirection — fastest
: > empty.txt            # the ":" builtin does nothing, so only the truncation happens
truncate -s 0 empty.txt  # explicit "set size to 0"
```

**Q9.** Copy only files matching a pattern into a folder, preserving structure.
```bash
cp *.txt docs/                       # flat: all matching files into docs/
rsync -av --include='*/' --include='*.txt' --exclude='*' src/ dst/   # keeps the folder layout
```

**Q10.** Make a backup copy of a file with a date in its name.
```bash
cp config.yml "config-$(date +%F).yml"   # $(date +%F) inserts e.g. 2026-09-14
```

**Q11.** What does `rm -I *.txt` do differently from `rm -i *.txt`?
```bash
rm -I *.txt              # asks ONCE if more than 3 files match (bulk-friendly)
rm -i *.txt              # asks for EVERY single file (tedious but safest)
```

**Q12.** Delete all files in a folder but keep the folder itself.
```bash
rm -rf mydir/*           # remove the contents (does not match hidden dotfiles)
rm -rf mydir/{*,.[!.]*}  # also remove hidden files, but not . and ..
find mydir -mindepth 1 -delete   # the cleanest way: everything inside, folder preserved
```
