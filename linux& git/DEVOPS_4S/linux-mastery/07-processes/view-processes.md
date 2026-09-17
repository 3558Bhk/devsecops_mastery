# Pattern: Seeing what is running

```bash
ps aux                                # list EVERY process: a=all users, u=user-friendly, x=no terminal
ps aux | head -1                      # show the header row so you know what each column means
ps aux | grep -v grep | grep node     # find processes whose command contains "node"
ps -ef                                # System-V style listing, includes PPID (parent process id)
ps -u alex                            # only processes owned by user alex
ps -o pid,ppid,%cpu,%mem,cmd -p 1234  # custom columns for one specific PID
top                                   # live view, refreshing: P sort by CPU, M sort by memory, q quit
htop                                  # colourful, mouse-friendly top (sudo apt install htop)
pgrep -a firefox                      # list PIDs whose name matches, -a shows the full command
pgrep -u alex -c                      # count how many processes user alex owns
pidof nginx                           # get the PID of a program by exact name
pstree                                # tree view showing parent → child relationships
pstree -p                             # same tree, with PIDs shown
uptime                                # load averages for the last 1, 5 and 15 minutes
```

## Reading `ps aux` columns

```text
USER  PID  %CPU  %MEM   VSZ   RSS  TTY  STAT  START  TIME   COMMAND
alex  1234  2.5   1.1  ...   ...  ?    S     10:02  0:15   node app.js
      └ the number you need for kill
                          └ STAT: R running, S sleeping, Z zombie, D stuck on I/O
```

## Practice

Find the PID of your own shell with `echo $$`, then look it up with `ps -p $$`.
