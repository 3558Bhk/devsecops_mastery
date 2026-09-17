# 07 Processes — Scenario Questions

## Scenario 1
The server feels slow. Diagnose it in under a minute.
```bash
uptime                                # 1. load average vs number of cores
nproc                                 #    (load much higher than cores = overloaded)
free -h                               # 2. is "available" memory near zero? is swap growing?
ps aux --sort=-%cpu | head -6         # 3. top CPU consumers
ps aux --sort=-%mem | head -6         # 4. top memory consumers
iostat -x 1 3                         # 5. is the disk saturated (%util near 100)?
```

## Scenario 2
A script you started is still running but you closed the terminal by accident. Is it alive?
```bash
ps aux | grep myscript.sh             # look for it among all processes
pgrep -af myscript                    # cleaner check
```
If it is gone, next time use:
```bash
nohup ./myscript.sh > run.log 2>&1 &  # survives logout and logs everything
tmux new -s job                       # or run it inside a reattachable session
```

## Scenario 3
A process ignores `kill` and refuses to die.
```bash
ps -o pid,stat,wchan,cmd -p 1234      # check the state: Z (zombie) or D (uninterruptible I/O)?
sudo kill -9 1234                     # if it is in state R or S, force it
sudo lsof -p 1234                     # if it survives, see what it is blocked on
```
`D` state means it is stuck in the kernel on I/O — no signal can help until the I/O returns.

## Scenario 4
Your training job must run overnight over SSH without dying when you disconnect.
```bash
tmux new -s train                     # start a persistent session
python train.py 2>&1 | tee train.log  # run it inside, logging as you go
# Ctrl+B then D to detach safely
tmux attach -t train                  # reattach the next morning
```

## Scenario 5
A cron job seems to start twice and they collide. Prevent overlapping runs.
```bash
flock -n /tmp/myjob.lock ./myjob.sh   # flock takes a lock file; -n = exit immediately if already locked
pgrep -c -f myjob.sh                  # or check how many copies are running
```

## Scenario 6
A runaway process is eating 100% CPU and you must lower its impact without killing it.
```bash
ps aux --sort=-%cpu | head -3         # identify the PID
sudo renice -n 19 -p 1234             # drop it to the lowest CPU priority
sudo ionice -c3 -p 1234               # and to idle disk priority
```

## Scenario 7
A program vanished and you suspect the OOM killer.
```bash
sudo dmesg -T | grep -i -E "killed process|out of memory"   # -T gives human-readable timestamps
free -h && cat /proc/meminfo | head -5                      # current memory picture
```
Then reduce the workload or add memory/swap.

## Scenario 8
You need to restart a service properly instead of killing it.
```bash
systemctl status nginx                # is it managed by systemd?
sudo systemctl restart nginx          # proper restart (kills and respawns cleanly)
sudo systemctl reload nginx           # or reload config without dropping connections
sudo journalctl -u nginx -n 50 --no-pager   # check the logs afterwards
```

## Scenario 9
Find everything a misbehaving process is touching on disk.
```bash
sudo lsof -p 1234                     # all open files and sockets
sudo ls -l /proc/1234/cwd             # its current working directory
sudo cat /proc/1234/cmdline | tr '\0' ' '   # the exact command line it was started with
```
