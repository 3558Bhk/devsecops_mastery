# Pattern: Links — hard vs symbolic

```bash
ln -s /etc/hosts ~/hosts              # SOFT (symbolic) link: a shortcut pointing to a path
ln source.txt hard.txt                # HARD link: a second name for the SAME data on disk (no -s)
ls -l ~/hosts                         # soft links show as: hosts -> /etc/hosts
readlink -f ~/hosts                   # follow a soft link and print its real final path
stat -c %h source.txt                 # show the hard-link COUNT (2 = two names, one file)
rm ~/hosts                            # deleting a soft link never touches the original file
unlink hard.txt                       # removes one hard link; data survives until the last link goes
ln -s ../shared/config.yml .          # very common in dev projects: link shared config into a folder
```

## Difference in one line each

| | Soft link (`ln -s`) | Hard link (`ln`) |
|---|---|---|
| Stores | a path (text) | the same inode/data |
| Original deleted | link breaks (dangling) | file still fully accessible |
| Across disks | ✅ yes | ❌ no |
| To folders | ✅ yes | ❌ normally no |
| Everyday use | shortcuts, versions | dedupe, safe backups |

## Real-world example

```bash
sudo ln -s /usr/bin/python3.12 /usr/local/bin/python   # make "python" mean python3.12
python --version                        # now this works thanks to the link
```

## Practice

Make a soft link called `home_link` in `/tmp` pointing to your home folder, then `cd` into it.
