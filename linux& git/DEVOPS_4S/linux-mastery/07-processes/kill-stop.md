# Pattern: Stopping and killing processes

```bash
kill 1234                             # politely ask PID 1234 to shut down (sends SIGTERM = signal 15)
kill -9 1234                          # SIGKILL: forced instant kill, the process cannot refuse
kill -HUP 1234                        # SIGHUP: many services reload their config on this
kill -l                               # list all signal names and numbers
killall firefox                       # kill every process named firefox
pkill -f "python train.py"            # -f matches the FULL command line, not just the name
pkill -u alex node                    # kill all node processes owned by user alex
kill -9 $(pgrep node)                 # combine: pgrep finds PIDs, $(...) passes them to kill
xkill                                 # GUI: click any window to kill its app (desktop only)
```

## Signals cheat sheet

| Signal | Number | Meaning |
|---|---|---|
| SIGTERM | 15 | "please stop" — default, allows cleanup |
| SIGKILL | 9 | "stop now" — cannot be caught or ignored |
| SIGHUP | 1 | "terminal gone / reload config" |
| SIGSTOP | 19 | freeze the process |
| SIGCONT | 18 | resume a frozen process |

## Order of operations (always)

```bash
ps aux | grep myapp                   # 1. find the exact PID first
kill 1234                             # 2. try the polite default
ps -p 1234                            # 3. check whether it's really gone
kill -9 1234                          # 4. only then force it
```

⚠️ Never `kill -9 1` — PID 1 is the system's init process.

## Practice

Start `sleep 300 &`, find its PID with `ps`, then stop it with `kill`.
