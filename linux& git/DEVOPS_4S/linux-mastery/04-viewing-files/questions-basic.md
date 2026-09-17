# 04 Viewing Files — Basic Questions

**Q1.** Print an entire small file to the screen.
```bash
cat notes.txt            # concatenate/print the whole file
```

**Q2.** Show line numbers while printing a file.
```bash
cat -n notes.txt         # -n numbers every line (useful before sed/awk work)
```

**Q3.** Read a huge log file without flooding your terminal.
```bash
less bigfile.log         # page through it; q quits, / searches, arrows scroll
```

**Q4.** Show only the first 10 lines of a file.
```bash
head notes.txt           # 10 lines by default
head -n 3 notes.txt      # or exactly 3
```

**Q5.** Show only the last 20 lines.
```bash
tail -n 20 notes.txt     # -n sets how many lines from the end
```

**Q6.** Watch a log file update live while your program runs.
```bash
tail -f app.log          # -f = follow: new lines appear as they are written
```

**Q7.** Count how many lines a file has.
```bash
wc -l notes.txt          # -l = lines
```

**Q8.** Count words and characters in a file.
```bash
wc -w notes.txt          # -w = words
wc -c notes.txt          # -c = bytes/characters
```

**Q9.** Glue two files together into a new one.
```bash
cat part1.txt part2.txt > all.txt   # > writes the combined output into a new file
```

**Q10.** Which key quits `less`, and which searches inside it?
```bash
less file                # /word searches forward, ?word backward, n/N next/previous, q quits
```

**Q11.** Reveal hidden characters such as tabs and line endings.
```bash
cat -A file.txt          # $ marks the end of each line, ^I is a tab
```

**Q12.** Show the last 100 lines of a log and then keep following it.
```bash
tail -n 100 -f app.log   # history first, then live updates
```

**Q13.** How many lines does each `.txt` file in this folder have?
```bash
wc -l *.txt              # wc accepts many files and prints a total at the end
```
