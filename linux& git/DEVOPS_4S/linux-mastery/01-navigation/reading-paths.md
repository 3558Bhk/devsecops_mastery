# Pattern: Reading paths & the filesystem map

```bash
echo "Absolute: /etc/hosts"           # starts with / — full address from the root, works from anywhere
echo "Relative: docs/report.pdf"      # no leading / — measured FROM your current folder
echo "Dot: ./report.pdf"              # . means "this folder" — same file as report.pdf
echo "Parent: ../report.pdf"          # .. means "one folder up"
echo "Home: ~/report.pdf"             # ~ means /home/yourname
echo "Home user: ~alex/report.pdf"    # ~username means another user's home folder
```

## The map you must memorise

```bash
ls /                                  # list the root — everything in Linux lives under here
ls /bin                               # essential programs (ls, cp, mv) — "bin" = binaries
ls /etc                               # configuration files for the whole system
ls /home                              # one folder per normal user
ls /var/log                           # system and app log files (great for debugging)
ls /tmp                               # temporary files, usually wiped on reboot
ls /usr/bin                           # most user-installed programs
ls /opt                               # third-party apps installed outside the package manager
```

## Escaping spaces (beginner trap)

```bash
touch "my file.txt"                   # quotes let a name contain a space
cd my\ file.txt                       # or escape the space with a backslash — same result
echo 'a $literal $string'             # single quotes = 100% literal, nothing is expanded
echo "home is $HOME"                  # double quotes = variables ARE expanded
```

## Practice

Write the absolute path of a file in your home folder without looking at `pwd`.
