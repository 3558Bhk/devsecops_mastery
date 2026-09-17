# 02 Listing & Finding — Scenario Questions

## Scenario 1
A build failed and you need to see what changed in the project in the last 10 minutes.
```bash
find . -mmin -10 -type f        # files modified in the last 10 minutes
find . -mmin -10 -type f -newer reference.txt   # or: newer than a known good file
ls -ltr                         # alternative: oldest → newest, so the last lines are the changes
```

## Scenario 2
Your home folder is huge but you have no idea what is taking the space.
```bash
du -sh ~/*                      # size of each item in home
du -sh ~/* | sort -rh | head    # biggest first (sort -rh understands human sizes)
find ~ -type f -size +200M -exec ls -lh {} +   # list every individual file over 200 MB
```

## Scenario 3
You must find every configuration file in a project that still contains a hard-coded password.
```bash
grep -rin "password" --include="*.conf" .      # recursive (-r), case-insensitive (-i), with line numbers (-n)
find . -name "*.conf" -exec grep -il "password" {} +   # same idea: -l prints only matching filenames
```

## Scenario 4
A log directory keeps filling the disk. Find and remove logs older than 30 days.
```bash
find /var/log/myapp -name "*.log" -mtime +30 -exec ls -lh {} +   # STEP 1: preview what matches
find /var/log/myapp -name "*.log" -mtime +30 -delete            # STEP 2: only now delete them
```
Always preview with `ls` before adding `-delete` — `find` deletion is permanent.

## Scenario 5
You installed a tool but the shell says `command not found`.
```bash
which mytool                    # is it on your PATH at all?
find / -name mytool -type f 2>/dev/null   # locate the binary anywhere on disk
ls -l /usr/local/bin/mytool     # check it exists and is executable
echo $PATH                      # the folders the shell actually searches
```
If `find` locates it in a folder missing from `$PATH`, add it: `export PATH="$PATH:/that/folder"`.

## Scenario 6
You need a list of all shell scripts in the repo to make them executable.
```bash
find . -name "*.sh" -type f                   # list them
find . -name "*.sh" -type f -exec chmod +x {} +   # make them all executable in one pass
find . -name "*.sh" -type f | xargs -r chmod +x   # equivalent; -r avoids running chmod with no input
```

## Scenario 7
A colleague says "the file is called something like report-final-v2". You don't know the extension.
```bash
find / -iname "*report*final*" 2>/dev/null    # wildcards on both sides, case-insensitive, errors hidden
locate -i report-final                        # instant, if the locate database is current
```

## Scenario 8
You want to know which folders in `/etc` you are allowed to read.
```bash
find /etc -maxdepth 1 -type d -readable       # -readable filters to directories you can actually open
find /etc -maxdepth 1 -type d ! -readable     # the ones you cannot (usually need sudo)
```

## Scenario 9
Show the 10 largest files on the system, skipping other mounted disks.
```bash
find / -xdev -type f -size +500M -exec ls -lhS {} + 2>/dev/null | head -10
```
`-xdev` keeps the search on a single filesystem, so it won't wander into network or USB mounts.
