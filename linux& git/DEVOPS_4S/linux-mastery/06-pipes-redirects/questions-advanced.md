# 06 Pipes & Redirects — Advanced Questions

**Q1.** Why does `command 2>&1 > file` fail to capture errors?
```bash
command 2>&1 > file      # WRONG: 2 is pointed at the current stdout (the screen) BEFORE 1 moves
command > file 2>&1      # RIGHT: 1 goes to the file, then 2 is pointed at wherever 1 now is
```
Redirections are processed strictly left to right.

**Q2.** What are the three standard streams and their numbers?
```bash
command 0< in.txt 1> out.txt 2> err.txt   # 0 = stdin, 1 = stdout, 2 = stderr
```

**Q3.** Filter out the `grep` process from your own grep results.
```bash
ps aux | grep -v grep | grep node   # the first grep removes the line for the grep command itself
pgrep -a node                       # cleaner: pgrep never lists itself
```

**Q4.** Handle filenames that contain spaces or newlines through a pipe.
```bash
find . -name "*.log" -print0 | xargs -0 rm   # -print0/-0 use NUL separators instead of whitespace
```

**Q5.** Save output AND errors to different files in one command.
```bash
command > out.txt 2> err.txt        # stdout to one file, stderr to another
command &> all.txt                  # or both merged
```

**Q6.** Send a command's output to two different processing stages at once.
```bash
ls -l | tee files.txt | grep "\.sh$"   # tee writes the full list to a file and passes it onward
```

**Q7.** What is a here-document and when would you use one?
```bash
cat > config.ini <<'CONF'    # everything until the CONF marker becomes the file's content
[section]
key = value
CONF                         # quoting the marker ('CONF') prevents variable expansion inside
```
Perfect for writing multi-line files from a script without echo on every line.

**Q8.** Send a here-string (single line) into a command.
```bash
grep -c "a" <<< "banana"     # <<< feeds the string as stdin
bc <<< "3 * 7"               # quick calculator use
```

**Q9.** Run two commands and combine their outputs into one file.
```bash
{ date; uname -r; df -h; } > report.txt   # braces group commands; note the spaces and the ;
(date; uname -r) > report.txt             # parentheses run them in a SUBSHELL — safer side effects
```

**Q10.** Pipe only errors onward, keeping normal output on screen.
```bash
command 2>&1 >/dev/null | grep "denied"   # 1 → /dev/null, 2 → the pipe
```

**Q11.** Append both output and errors to a log.
```bash
./backup.sh >> backup.log 2>&1   # the standard cron line: append everything to a log
```

**Q12.** Why is `cat file | grep x` considered wasteful?
```bash
cat file | grep x        # useless use of cat: spawns an extra process
grep x file              # grep reads files directly — faster and simpler
```
Pipes are for connecting DIFFERENT tools, not for feeding a file to a tool that accepts filenames.

**Q13.** Split a command's output to both a file and `wc -l` simultaneously.
```bash
ls -l | tee listing.txt | wc -l   # count what flowed through while saving all of it
```
