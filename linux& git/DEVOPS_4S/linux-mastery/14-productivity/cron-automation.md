# Pattern: Scheduling tasks (`cron`, `at`, systemd timers)

```bash
crontab -l                              # LIST your scheduled jobs
crontab -e                              # EDIT your jobs (opens in your editor)
crontab -r                              # REMOVE all your jobs (⚠️ no confirmation!)
sudo crontab -e                         # edit root's schedule instead
at 15:30                                # run a one-off job at a specific time (type commands, Ctrl+D)
at now + 5 minutes                      # run something 5 minutes from now
atq                                     # list pending "at" jobs
atrm 2                                  # cancel at-job number 2
systemctl list-timers                   # the modern alternative: systemd timers
```

## Cron format (5 time fields, then the command)

```text
 ┌ minute        (0-59)
 │ ┌ hour        (0-23)
 │ │ ┌ day of month (1-31)
 │ │ │ ┌ month      (1-12)
 │ │ │ │ ┌ day of week (0-7, both 0 and 7 = Sunday)
 │ │ │ │ │
 * * * * *  command to run
```

## Recipes

```text
*/5 * * * *  /home/alex/check.sh        # every 5 minutes (*/5 = "every 5th minute")
0 2 * * *    /home/alex/backup.sh       # every day at 02:00
30 8 * * 1-5 /home/alex/report.sh       # 08:30 on Monday–Friday
0 0 1 * *    /home/alex/monthly.sh      # midnight on the 1st of every month
0 3 * * 0    /home/alex/weekly.sh       # 03:00 every Sunday
@reboot      /home/alex/startup.sh      # run once when the machine boots
@daily       /home/alex/backup.sh       # shortcut words: @hourly @daily @weekly @monthly @yearly
```

## Rules that trip up beginners

```text
0 2 * * * /home/alex/backup.sh >> /home/alex/backup.log 2>&1   # cron sends no output anywhere by default → log it yourself
* * * * * cd /home/alex && ./script.sh                          # cron's working directory is NOT yours → cd first
* * * * * /usr/local/bin/mytool                                 # cron has a minimal PATH → use full paths
%                                                               # must be escaped as \% inside a command (e.g. date +\%F)
```

```bash
which backup.sh                         # get the full path to paste into crontab
grep CRON /var/log/syslog               # check that cron actually ran your job (Debian/Ubuntu)
sudo journalctl -u cron -f              # or watch cron live (systemd systems)
```

## Practice

Add `*/1 * * * * date >> /tmp/cron-test.log`, wait 2 minutes, then `cat /tmp/cron-test.log`.
Remove it afterwards with `crontab -e`.
