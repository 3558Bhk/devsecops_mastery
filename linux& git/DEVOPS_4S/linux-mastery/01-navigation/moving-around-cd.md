# Pattern: Moving around (`cd`)

```bash
cd                                    # go to your home folder (no argument = home)
cd ~                                  # same thing, ~ is the shortcut for home
cd /                                  # go to the root — the very top of the whole filesystem
cd /etc                               # absolute path: jump anywhere directly, starts with /
cd projects                           # relative path: enter the "projects" folder inside the current one
cd ..                                 # go UP one level (to the parent folder)
cd ../..                              # go up two levels at once
cd -                                  # jump back to the PREVIOUS folder (a super handy toggle)
cd /home/alex/projects/src && cd -    # go deep, then bounce back to where you started
ls                                    # list contents so you know what you can cd into next
```

## Tab completion (the #1 speed skill)

```bash
cd /et<TAB>                           # press Tab and /et becomes /etc automatically
cd /etc/sys<TAB>                       # if many match, Tab twice shows all options
```

## Getting unstuck

```bash
pwd                                   # lost? print where you are
cd ~                                  # and reset to home — you can never be "too lost"
```

## Practice

From home, reach `/etc/hosts`'s folder, then return home with a single command (`cd -`).
