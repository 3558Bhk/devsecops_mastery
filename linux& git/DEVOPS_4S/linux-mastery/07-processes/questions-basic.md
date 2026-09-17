# 07 Processes — Basic Questions

**Q1.** List every running process.
```bash
ps aux                   # a=all users, u=user-friendly columns, x=include processes without a terminal
```

**Q2.** Find the PID of a program by name.
```bash
pgrep -a firefox         # prints matching PIDs with their full command lines
pidof nginx              # prints the PID(s) of that exact program name
```

**Q3.** Watch processes live, updating every few seconds.
```bash
top                      # P sorts by CPU, M by memory, q quits
htop                     # colour version with mouse support (install it)
```

**Q4.** Stop a process politely, then forcefully.
```bash
kill 1234                # SIGTERM (15): asks the process to shut down cleanly
kill -9 1234             # SIGKILL (9): forced, cannot be ignored or caught
```

**Q5.** Kill every process with a given name.
```bash
killall firefox          # by exact name
pkill -f "python train.py"   # -f matches the whole command line, not just the name
```

**Q6.** Start a command in the background.
```bash
./task.sh &              # the trailing & returns your prompt immediately
```

**Q7.** List your shell's background jobs.
```bash
jobs                     # shows [1] Running ... etc.
jobs -l                  # same, including PIDs
```

**Q8.** Bring a background job back to the foreground.
```bash
fg %1                    # %1 refers to job number 1
```

**Q9.** Pause the running foreground job.
```bash
# press Ctrl+Z          # suspends the job (state T); resume with bg or fg
bg %1                    # resume it in the background
```

**Q10.** Make a command survive closing the terminal.
```bash
nohup ./task.sh &                 # ignores the hangup signal; output goes to nohup.out
nohup ./task.sh > run.log 2>&1 &  # and log everything into run.log
```

**Q11.** See the parent/child relationship between processes.
```bash
pstree -p                # tree view with PIDs
```

**Q12.** What does PID 1 mean?
```bash
ps -p 1 -o pid,cmd       # PID 1 is the init/systemd process — the ancestor of everything; never kill it
```

**Q13.** Check how loaded the system is.
```bash
uptime                   # load averages for the last 1, 5 and 15 minutes
```

**Q14.** Which signal number is SIGTERM, and which is SIGKILL?
```bash
kill -l                  # lists every signal name and number: TERM=15, KILL=9, HUP=1
```
