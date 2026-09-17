# Pattern: Reading file contents

```bash
cat notes.txt                         # print the WHOLE file to the screen
cat -n notes.txt                      # add line numbers (great for sed/awk work later)
cat -A notes.txt                      # reveal hidden characters: $ = end of line, ^I = tab
cat file1.txt file2.txt               # print several files one after another
cat header.txt body.txt > all.txt     # glue files together into a new one
less bigfile.log                      # page through a file: arrows/PgUp scroll, / searches, q quits
less +F bigfile.log                   # "follow" mode: like tail -f, Ctrl+C stops following
head notes.txt                        # first 10 lines
head -n 3 notes.txt                   # first 3 lines
tail notes.txt                        # last 10 lines
tail -n 5 notes.txt                   # last 5 lines
tail -f /var/log/syslog               # FOLLOW: live-stream new lines as they're written (logs!)
tail -n 100 -f app.log                # show the last 100 lines first, then keep streaming
wc -l notes.txt                       # count LINES
wc -w notes.txt                       # count WORDS
wc -c notes.txt                       # count BYTES (characters)
wc -l *.txt                           # count lines in every .txt file
```

## Inside `less` (memorise these keys)

```text
q        quit            /word    search forward     ?word   search backward
n / N    next / previous match    g        jump to top   G   jump to bottom
F        follow the file live      Ctrl+C   stop following
```

## Practice

`tail -f` one log file in a terminal, then write to it from a second terminal with
`echo "test" >> /var/log/thatfile` and watch the line appear.
