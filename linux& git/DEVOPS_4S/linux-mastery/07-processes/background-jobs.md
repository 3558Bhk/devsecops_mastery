# Pattern: Background jobs & keeping things alive

```bash
./long_task.sh &                      # trailing & starts it in the BACKGROUND, terminal stays free
jobs                                  # list background jobs of THIS shell
jobs -l                               # same, with PIDs
fg %1                                 # bring job 1 to the FOREGROUND
bg %1                                 # resume a stopped job in the background
Ctrl+Z                                # SUSPEND (pause) the current foreground job
kill %1                               # kill job number 1
disown %1                             # detach a job so closing the terminal won't kill it
nohup ./long_task.sh &                # nohup = ignore hangup: survives logout; output goes to nohup.out
nohup ./long_task.sh > run.log 2>&1 & # keep running AND log everything into run.log
setsid ./long_task.sh &               # start it in a brand-new session, fully detached
sleep 60 && echo done &               # chain commands in the background
screen -S work                        # or: start a persistent terminal session (reattach later)
screen -r work                        # reattach to that session
tmux new -s work                      # modern alternative to screen
```

## Background vs nohup vs tmux

| Need | Use |
|---|---|
| Free the terminal briefly | `cmd &` |
| Survive logging out | `nohup cmd > log 2>&1 &` |
| Come back and watch it live | `tmux` or `screen` |
| Run on a schedule | `cron` (see 14-productivity) |

## Practice

Run `nohup sleep 120 &`, close the terminal, reopen it, and check with `ps aux | grep sleep`.
