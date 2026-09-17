# 04 Viewing Files — Scenario Questions

## Scenario 1
Your web app crashed. You need the last thing it logged before dying.
```bash
tail -n 100 app.log                     # last 100 lines is usually enough context
grep -n -i "error\|exception" app.log | tail -20   # jump straight to the failures
less +G app.log                         # or open it scrolled to the very end (G = go to bottom)
```

## Scenario 2
A service is writing to `app.log` right now and you want to watch it live while reproducing a bug.
```bash
tail -f app.log                         # follow the file
tail -F app.log                         # -F also survives log ROTATION (the file being replaced)
```
Use `-F` for long sessions: when logrotate swaps the file, plain `-f` silently follows the old one.

## Scenario 3
You `cat` a huge file and your terminal is now full of unreadable garbage (it was binary).
```bash
reset                                   # restores the terminal to a sane state
clear                                   # or Ctrl+L for a simpler screen clear
file thatfile                           # check the type BEFORE catting next time
```

## Scenario 4
You need to know how big a report is before emailing it: lines, words, size.
```bash
wc -lw report.txt                       # lines and words in one go
ls -lh report.txt                       # human-readable file size
du -h report.txt                        # actual disk space used
```

## Scenario 5
A config file is 2000 lines and you only care about the non-comment settings.
```bash
grep -vE '^\s*(#|$)' config.conf        # drop comment lines and blank lines
grep -vE '^\s*(#|$)' config.conf | less # and page through the result
grep -n "port" config.conf              # find one specific setting with its line number
```

## Scenario 6
You want a quick snapshot of a growing log saved to a file for a bug report.
```bash
tail -n 500 app.log > snapshot.txt      # capture the last 500 lines
wc -l snapshot.txt                      # confirm you got them
gzip snapshot.txt                       # compress before attaching (snapshot.txt.gz)
```

## Scenario 7
Two versions of a file exist and you need to see what changed, page by page.
```bash
diff -u old.conf new.conf | less        # unified diff, scrollable
diff -y old.conf new.conf | less        # side-by-side columns
diff -r dir1/ dir2/                     # compare two whole folders
```

## Scenario 8
A process is stuck and you want to see what it is currently writing, without knowing the filename.
```bash
sudo lsof -p 1234 | grep -i reg         # list the regular files that PID has open
sudo tail -f /proc/1234/fd/1            # follow its stdout stream directly
```
