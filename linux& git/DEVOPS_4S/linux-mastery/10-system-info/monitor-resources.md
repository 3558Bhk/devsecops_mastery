# Pattern: Monitoring CPU, memory, disk I/O

```bash
top                                   # live overview; P=sort by CPU, M=sort by memory, 1=per-core, q=quit
htop                                  # nicer top with colour bars and mouse support (install it)
free -h                               # memory usage: total / used / free / available, human sizes
free -m                               # same in megabytes
watch -n 2 free -h                    # re-run "free -h" every 2 seconds (watch = auto-refresh)
vmstat 1                              # one line per second: CPU, memory, swap, I/O, context switches
vmstat 1 5                            # same but stop after 5 samples
iostat -x 1                           # per-disk I/O statistics (needs the sysstat package)
mpstat -P ALL 1                       # per-CPU-core usage (also sysstat)
sar -u 1 5                            # sample CPU utilisation 5 times
ps aux --sort=-%mem | head -6         # top 5 memory-hungry processes
ps aux --sort=-%cpu | head -6         # top 5 CPU-hungry processes
dstat -cmdn 1                         # combined live view (if installed)
cat /proc/loadavg                     # raw load averages straight from the kernel
nproc                                 # how many CPU cores you have
lsmem                                 # memory block layout
```

## Is my server overloaded? (30-second check)

```bash
uptime                                # load avg 1/5/15 min
nproc                                 # number of cores
free -h                               # is "available" memory near zero? is swap growing?
ps aux --sort=-%cpu | head            # who is eating the CPU?
```
Rule of thumb: if the load average is much higher than `nproc`, the machine is overloaded.

## Practice

Run `watch -n 1 'free -h'` for a few seconds, then stop it with Ctrl+C.
