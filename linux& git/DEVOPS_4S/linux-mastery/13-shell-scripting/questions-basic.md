# 13 Shell Scripting — Basic Questions

**Q1.** What must be on line 1 of a bash script, and why?
```bash
#!/usr/bin/env bash      # the shebang tells Linux which interpreter runs this file
```

**Q2.** Make a script executable and run it.
```bash
chmod +x hello.sh        # add the execute bit
./hello.sh               # ./ means "in this folder" — required because . is not on PATH
bash hello.sh            # alternative: run it through bash, no +x needed
```

**Q3.** Assign and read a variable.
```bash
name="Alex"              # NO spaces around the = sign
echo "$name"             # always quote when reading it
```

**Q4.** Put a command's output into a variable.
```bash
today=$(date +%F)        # $( ) runs the command and captures its output
```

**Q5.** Do arithmetic.
```bash
total=$((3 * 4 + 1))     # $(( )) evaluates integers → 13
n=1; n=$((n + 1))        # increment
```

**Q6.** Use the first argument passed to a script.
```bash
echo "$1"                # $1 = first argument, $2 = second, $# = how many, $@ = all of them
```

**Q7.** Write an if statement.
```bash
if [ -f notes.txt ]; then echo "exists"; fi   # -f tests for a regular file
```

**Q8.** Loop over every `.txt` file.
```bash
for f in *.txt; do echo "$f"; done   # the glob expands to the matching filenames
```

**Q9.** Loop a fixed number of times.
```bash
for i in {1..5}; do echo "$i"; done  # brace range
for ((i=0; i<5; i++)); do echo $i; done   # C-style loop
```

**Q10.** Read a file line by line.
```bash
while read -r line; do echo "$line"; done < data.txt   # -r stops backslash mangling
```

**Q11.** Ask the user for input.
```bash
read -r -p "Your name: " name   # -p prints a prompt, -r keeps input literal
```

**Q12.** Define and call a function.
```bash
greet() { echo "Hello, $1"; }   # definition
greet Alex                      # call → prints "Hello, Alex"
```

**Q13.** Exit a script with a success or failure code.
```bash
exit 0                   # 0 = success; any other number = failure
echo $?                  # in the shell: the exit code of the previous command
```

**Q14.** Print text to stderr instead of stdout.
```bash
echo "warning" >&2       # >&2 sends the message to the error stream
```
