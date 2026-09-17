# 04 Viewing Files — Advanced Questions

**Q1.** Show lines 5 through 10 of a very large file without reading it all.
```bash
sed -n '5,10p' big.txt   # -n suppresses default output; p prints only the selected range
awk 'NR>=5 && NR<=10' big.txt   # NR = current line number
```

**Q2.** Read a gzip-compressed log without decompressing it first.
```bash
zcat app.log.gz          # cat a .gz file
zless app.log.gz         # page through it
zgrep "error" app.log.gz # search inside it directly
```

**Q3.** Follow a log, but also keep a local copy of everything you see.
```bash
tail -f app.log | tee watch.log    # tee writes to the file AND passes it to the screen
```

**Q4.** Follow a file in `less` instead of `tail`.
```bash
less +F app.log          # starts in follow mode; Ctrl+C stops following, F resumes, q quits
```

**Q5.** Count non-empty, non-comment lines in a config file.
```bash
grep -vcE '^\s*(#|$)' config.conf   # -v invert, -c count, -E regex: skip blank and # lines
```

**Q6.** Show the last 5 lines of every `.log` file in a folder, with headers.
```bash
tail -n 5 -v *.log       # -v always prints the ==> filename <== headers
```

**Q7.** A file has Windows line endings and looks wrong. Inspect and fix it.
```bash
cat -A file.txt          # you will see ^M$ at the end of every line
sed -i 's/\r$//' file.txt    # strip the carriage returns
```

**Q8.** Show the middle of a file: skip the first 100 lines, then take 20.
```bash
tail -n +101 big.txt | head -n 20   # tail -n +101 starts AT line 101; head cuts 20 lines
```

**Q9.** Check whether a file is text or binary before catting it.
```bash
file mystery.dat         # reports "ASCII text", "gzip compressed data", "ELF executable", etc.
```

**Q10.** Print only lines 1 and the last line of a file.
```bash
head -n 1 file.txt       # first line
tail -n 1 file.txt       # last line
```

**Q11.** Search a 10 GB log for a word and show 3 lines of context around each hit.
```bash
grep -C 3 "OutOfMemory" huge.log    # -C 3 = 3 lines before and after
grep -m 5 "OutOfMemory" huge.log    # -m 5 = stop after 5 matches (fast on giant files)
```

**Q12.** Count how many times a word appears (not how many lines contain it).
```bash
grep -o "error" app.log | wc -l   # -o prints each match on its own line, so wc counts occurrences
```
