# Pattern: Finding files by name (`find`)

`find` walks the disk for you. Format: `find WHERE WHAT_TO_DO`

```bash
find . -name "notes.txt"              # search current folder (.) for an exact name
find /home -name "*.log"              # *.log = any name ending in .log, quotes stop the shell expanding it
find . -iname "readme.md"             # -i = ignore CASE (README.md matches too)
find / -name "passwd" 2>/dev/null     # search whole disk, hide "permission denied" errors
find . -maxdepth 1 -name "*.md"       # only this folder, do not dive into subfolders
find . -name "tmp*" -delete           # find AND delete them in one step (dangerous — test without -delete first)
find . -name "*.txt" -exec ls -l {} \;  # run ls -l on every match; {} = the found file, \; ends the command
find . -name "*.tmp" -exec rm {} +    # same idea, + batches files (much faster than \;)
```

## `locate` — the instant alternative

```bash
sudo updatedb                         # build/refresh the filename database first
locate notes.txt                      # instant search of that database (may be slightly out of date)
locate -i readme                      # case-insensitive locate
```

## `which` / `type` — finding *programs*

```bash
which python3                         # full path of the program that runs when you type "python3"
type ls                               # tells you if it's a binary, alias, or shell function
```

## Practice

Find every `.sh` file in your home folder and print their paths.
