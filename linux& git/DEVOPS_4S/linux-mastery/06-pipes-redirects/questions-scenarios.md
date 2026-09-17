# 06 Pipes & Redirects — Scenario Questions

## Scenario 1
You need a report: hostname, kernel, disk usage and memory, saved to a file for a ticket.
```bash
{ hostname; uname -r; df -h; free -h; } > report.txt   # group commands, redirect the lot to a file
cat report.txt                                          # verify it
```

## Scenario 2
A nightly script must run silently, but you still need to know when it fails.
```bash
./job.sh > /dev/null 2> /var/log/job-errors.txt   # normal output discarded, errors captured
test -s /var/log/job-errors.txt && echo "check the log"   # -s = file exists and is not empty
```

## Scenario 3
Port 3000 is in use and you need to find and stop the culprit.
```bash
sudo ss -tulnp | grep :3000            # find the PID listening on the port
sudo lsof -i :3000                     # alternative view with full command lines
ps -p <PID> -o pid,user,cmd            # confirm what it actually is before killing
sudo kill <PID>                        # stop it politely
```

## Scenario 4
You must search 50 000 log files for a string, and filenames may contain spaces.
```bash
find /var/log -type f -name "*.log" -print0 | xargs -0 grep -l "payment failed"
# -print0 emits NUL-separated names; xargs -0 reads them safely; grep -l lists matching files
```

## Scenario 5
You want to watch a long-running command live but also keep a full copy for later.
```bash
./long_task.sh 2>&1 | tee run.log      # merge errors into stdout, then tee to screen + file
tail -f run.log                        # in another terminal, follow the saved copy
```

## Scenario 6
Convert a list of usernames in `users.txt` into one `useradd` command per line.
```bash
cat users.txt                          # inspect the list first
xargs -a users.txt -I{} echo sudo useradd -m {}   # dry run: print the commands instead of running them
xargs -a users.txt -I{} sudo useradd -m {}        # real run: -I{} substitutes each name
```

## Scenario 7
A command writes progress to stderr and results to stdout. Save only the results.
```bash
tool > results.csv                     # stdout (the data) goes to the file
tool > results.csv 2> progress.log     # or keep the progress messages separately
tool 2>/dev/null > results.csv         # or throw the progress away
```

## Scenario 8
Disk is full and you want to rank the top-level folders without filling the screen.
```bash
sudo du -h --max-depth=1 / 2>/dev/null | sort -rh | head -10
# du's errors (unreadable dirs) are hidden, sizes are sorted descending, top 10 shown
```

## Scenario 9
You need to run a command as another user and capture its output into your own file.
```bash
sudo -u postgres psql -c "SELECT 1" > /tmp/out.txt 2>&1   # redirection happens in YOUR shell, so the file is yours
sudo sh -c 'psql -c "SELECT 1" > /tmp/out.txt'            # if root must own the file, redirect INSIDE sudo
```

## Scenario 10
Find every process using more than 5% memory and save the list.
```bash
ps aux | awk 'NR>1 && $4+0 > 5 {print $2, $4, $11}' | sort -k2 -rn > mem-hogs.txt
# skip header → filter column 4 (MEM%) → print PID, MEM%, command → sort → save
```
