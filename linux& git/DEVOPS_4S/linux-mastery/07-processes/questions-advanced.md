# 07 Processes — Advanced Questions

**Q1.** Show custom columns for one specific PID.
```bash
ps -o pid,ppid,%cpu,%mem,etime,cmd -p 1234   # etime = how long it has been running
```

**Q2.** Explain the STAT codes you see in `ps aux`.
```bash
ps -eo pid,stat,cmd | head   # R running, S sleeping, D uninterruptible (usually disk I/O),
                             # T stopped, Z zombie, + means foreground process group
```

**Q3.** A process is in state `D` and `kill -9` does not remove it. Why?
```bash
ps -eo pid,stat,wchan,cmd | awk '$2 ~ /D/'   # wchan shows which kernel call it is blocked in
```
`D` means uninterruptible sleep — typically stuck on NFS or a dying disk. The kernel cannot
deliver a signal until the I/O completes. Fix the underlying storage or reboot.

**Q4.** What is a zombie process and how do you clear one?
```bash
ps aux | awk '$8 ~ /Z/'          # find zombies (state Z)
ps -o ppid= -p <zombie_pid>      # get its PARENT's PID
kill -HUP <parent_pid>           # ask the parent to reap its children
```
A zombie is already dead; only its exit status remains. Killing the parent (or making it wait) removes it.

**Q5.** Find which files a running process has open.
```bash
sudo lsof -p 1234                # every open file, socket and pipe of that PID
sudo lsof -c nginx               # same, filtered by command name
```

**Q6.** Limit how much CPU or memory a process may use.
```bash
systemd-run --scope -p MemoryMax=500M ./task.sh   # cap memory at 500 MB
systemd-run --scope -p CPUQuota=50% ./task.sh     # cap CPU at half a core
ulimit -v 1000000                                 # cap your shell's virtual memory (KB) before launching
nice -n 19 ./task.sh                              # lowest scheduling priority (polite background work)
renice -n 10 -p 1234                              # lower the priority of an already-running process
ionice -c3 ./task.sh                              # idle I/O priority: only use the disk when free
```

**Q7.** Send a signal to a whole process group.
```bash
kill -TERM -1234         # note the MINUS: signals the process GROUP whose PGID is 1234
ps -o pid,pgid,cmd       # see which group each process belongs to
```

**Q8.** Reload a service's configuration without restarting it.
```bash
sudo kill -HUP 1234      # many daemons re-read their config on SIGHUP
sudo systemctl reload nginx   # the proper way when systemd manages it
```

**Q9.** Run a task detached from the terminal and come back to it later.
```bash
tmux new -s work         # create a named session
# Ctrl+B then D          # detach (the session keeps running)
tmux attach -t work      # reattach whenever you like
tmux ls                  # list sessions
```

**Q10.** Find and kill every process whose command line contains a string, safely.
```bash
pgrep -af "python train.py"          # 1. LOOK at what would be killed
pkill -f "python train.py"           # 2. then kill it
pkill -9 -u alex -f "python train"   # variants: -9 force, -u restrict to one user
```

**Q11.** Which processes are children of a given parent?
```bash
ps --ppid 1234 -o pid,cmd            # direct children only
pstree -p 1234                       # the whole subtree
```

**Q12.** Detect an OOM (out-of-memory) kill after a process vanished.
```bash
sudo dmesg | grep -i "out of memory"          # kernel messages record the OOM killer's victims
sudo journalctl -k --since "1 hour ago" | grep -i oom   # same from the journal
```
