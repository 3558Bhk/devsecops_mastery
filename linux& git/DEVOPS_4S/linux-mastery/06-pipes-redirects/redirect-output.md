# Pattern: Redirecting output to files

Linux has 3 standard streams:
`stdin` (0) = keyboard input, `stdout` (1) = normal output, `stderr` (2) = error messages.

```bash
echo "hello" > out.txt                # > writes stdout to a file, OVERWRITING it
echo "world" >> out.txt               # >> APPENDS to the end of the file (keeps old content)
command 2> errors.txt                 # send only ERRORS (stream 2) to a file
command > all.txt 2>&1                # send BOTH stdout and errors to all.txt (2>&1 = "2 goes where 1 goes")
command &> all.txt                    # shorter modern form of the line above
command > /dev/null                   # throw normal output away (/dev/null is the black hole)
command > /dev/null 2>&1              # throw EVERYTHING away — silent success
command 2> /dev/null                  # keep output, hide errors (very common with find)
sort < names.txt                      # < feeds a file IN as stdin
command < input.txt > output.txt      # redirect in and out in the same line
ls nosuchfile 2> err.log; cat err.log # prove that the error message went into the file, not the screen
```

## Here-docs — multi-line input without a file

```bash
cat > config.ini <<'CONF'             # everything until the CONF marker becomes the file's content
[section]
key = value
CONF                                  # this closing marker must be at the line start, alone
```

## Order matters

```bash
command 2>&1 > file.txt               # WRONG: errors still go to the screen
command > file.txt 2>&1               # RIGHT: point 1 at the file first, then 2 follows 1
```

## Practice

Run `ls /root` as a normal user, capture the permission error into `err.txt`, and display it.
