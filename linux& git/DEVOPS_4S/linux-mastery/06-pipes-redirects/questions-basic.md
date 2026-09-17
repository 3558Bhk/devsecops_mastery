# 06 Pipes & Redirects — Basic Questions

**Q1.** What does the `|` symbol do?
```bash
ls -l | less             # sends the output of ls into less as its input
```

**Q2.** Count the number of entries in a folder.
```bash
ls | wc -l               # ls produces one name per line; wc -l counts the lines
```

**Q3.** Find a running process by name.
```bash
ps aux | grep firefox    # list all processes, keep the matching lines
```

**Q4.** Write command output to a file, overwriting it.
```bash
echo "hello" > out.txt   # > creates or truncates the file
```

**Q5.** Append to a file instead of overwriting.
```bash
echo "more" >> out.txt   # >> adds to the end, keeping existing content
```

**Q6.** Send only error messages to a file.
```bash
command 2> errors.txt    # 2 is the stderr stream; 1 (stdout) still goes to the screen
```

**Q7.** Send both normal output and errors to the same file.
```bash
command > all.txt 2>&1   # 1 goes to the file first, then 2 follows 1
command &> all.txt       # shorter modern equivalent
```

**Q8.** Discard all output from a command (run it silently).
```bash
command > /dev/null 2>&1   # /dev/null is the black hole device
```

**Q9.** Feed a file into a command as standard input.
```bash
sort < names.txt         # < redirects the file into sort's stdin
```

**Q10.** Show output on screen AND save it to a file at the same time.
```bash
command | tee out.txt    # tee splits the stream in two directions
command | tee -a out.txt # -a appends instead of overwriting
```

**Q11.** Search your own command history.
```bash
history | grep ssh       # pipe history into grep
```

**Q12.** Chain three commands: list, sort, take the first five.
```bash
ls | sort | head -5      # data flows left to right through each stage
```

**Q13.** Which command turns a list of filenames into arguments for another command?
```bash
find . -name "*.log" | xargs rm   # xargs builds "rm file1 file2 file3 ..." from the list
```
