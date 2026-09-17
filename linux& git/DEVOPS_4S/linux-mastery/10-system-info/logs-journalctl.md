# Pattern: Reading logs (where Linux tells you what happened)

```bash
sudo journalctl                       # the systemd log of EVERYTHING
sudo journalctl -e                    # jump straight to the END (e = end)
sudo journalctl -f                    # FOLLOW live, like tail -f
sudo journalctl -n 50                 # only the last 50 lines
sudo journalctl -u nginx              # logs of ONE service (unit)
sudo journalctl -u ssh -f             # follow SSH login attempts live
sudo journalctl -b                    # only since the current BOOT
sudo journalctl -b -1                 # the PREVIOUS boot (why did it crash?)
sudo journalctl -p err -b             # only messages of priority "error" and worse
sudo journalctl --since "1 hour ago"  # human time filters
sudo journalctl --since today         # everything since midnight
sudo journalctl --until "2026-09-14 12:00"   # up to a specific moment
sudo journalctl -k                    # kernel messages only (hardware, drivers)
sudo journalctl _PID=1234             # everything logged by one process ID
sudo journalctl -o short-precise      # timestamps with milliseconds
sudo journalctl --disk-usage          # how much space the logs take
sudo journalctl --vacuum-time=7d      # delete logs older than 7 days
```

## Classic log files (when systemd journals aren't used)

```bash
sudo tail -f /var/log/syslog          # Ubuntu/Debian: general system messages
sudo tail -f /var/log/auth.log        # logins, sudo usage, SSH attempts (security!)
sudo less /var/log/dpkg.log           # what packages were installed and when
sudo tail -100 /var/log/nginx/error.log   # a typical application's own error log
sudo dmesg | tail -30                 # kernel ring buffer: USB plugged in, OOM kills, disk errors
sudo dmesg -w                         # follow kernel messages live
```

## Debugging a failed service

```bash
systemctl status nginx                # 1. is it running? exit code? last lines?
sudo journalctl -u nginx -n 100 --no-pager   # 2. its last 100 log lines, printed without a pager
sudo nginx -t                         # 3. app-specific config test
```

## Practice

Look at the last 20 logins with `sudo journalctl -u ssh -n 20 --no-pager` (or `/var/log/auth.log`).
