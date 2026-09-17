# 10 System Info & Monitoring — Scenario Questions

## Scenario 1
You inherit an unknown server. Build a complete picture in 2 minutes.
```bash
hostnamectl                       # name, distro, kernel, virtual or physical
cat /etc/os-release               # exact OS version
uptime && nproc                   # load and how many cores to compare it against
free -h                           # memory and swap
df -h                             # disk usage per filesystem
ip -br a                          # network addresses
systemctl list-units --failed     # anything broken
sudo journalctl -p err -b --no-pager | tail -20   # errors since boot
```

## Scenario 2
Users report the app is slow between 2 and 4 PM. Capture evidence.
```bash
sar -u -s 14:00:00 -e 16:00:00       # CPU history for that window (sysstat must be installed)
sar -r -s 14:00:00 -e 16:00:00       # memory history
sar -b -s 14:00:00 -e 16:00:00       # disk I/O history
sar -n DEV -s 14:00:00 -e 16:00:00   # network traffic history
```
If sysstat was not installed, the data is gone — install it now so next time you have history.

## Scenario 3
The server rebooted itself overnight. Find out why.
```bash
last -x reboot shutdown | head          # when exactly did it go down and come back?
sudo journalctl -b -1 -e --no-pager | tail -50   # the END of the previous boot's log
sudo journalctl -b -1 -p err --no-pager | tail -30   # errors from that boot
sudo dmesg -T | grep -i -E "temperature|thermal|mce"  # hardware warnings
sudo grep -i "out of memory" /var/log/kern.log 2>/dev/null   # an OOM kill?
```
An abrupt stop with no shutdown messages usually means power loss or a hard crash.

## Scenario 4
A monitoring alert says "memory 95% used". Is it real?
```bash
free -h                                 # check AVAILABLE, not "free"; check buff/cache
ps aux --sort=-%mem | head -6           # who is actually using it
vmstat 1 5                              # si/so columns: is it swapping?
cat /proc/meminfo | grep -E "MemAvailable|SwapFree"   # the kernel's own numbers
```
High buff/cache with plenty of `available` and no swapping = normal, not an incident.

## Scenario 5
You must confirm a kernel/package update actually applied.
```bash
uname -r                                # running kernel version
dpkg -l | grep linux-image              # installed kernel packages
sudo grep upgrade /var/log/dpkg.log | tail   # what was upgraded and when
sudo journalctl --list-boots | tail -3  # did we reboot since then?
```

## Scenario 6
Something is writing to disk constantly and you cannot find it.
```bash
iotop -oP                               # live per-process I/O (needs root)
pidstat -d 1 5                          # sample per-process I/O for 5 seconds
sudo lsof +D /var/log | head            # which processes have files open in /var/log
iostat -x 1 3                           # confirm which DEVICE is busy (%util)
```

## Scenario 7
Prepare a health report to email your team every morning.
```bash
cat > ~/health.sh <<'SCRIPT'            # here-doc writes the script file
#!/usr/bin/env bash
echo "== $(hostname) $(date) =="
uptime -p; echo
df -h -x tmpfs | awk 'NR==1 || $5+0>70'  # only disks above 70% used
free -h | head -2
systemctl list-units --failed --no-legend
sudo journalctl -p err --since "24 hours ago" --no-pager | tail -10
SCRIPT
chmod +x ~/health.sh && ~/health.sh     # make it executable and test it
crontab -e                              # then schedule it: 0 8 * * * ~/health.sh | mail -s health you@x.com
```

## Scenario 8
Check whether the machine's clock is correct (TLS errors often come from clock drift).
```bash
timedatectl                             # shows timezone and "System clock synchronized: yes/no"
date -u                                 # UTC time right now
sudo timedatectl set-ntp true           # enable NTP synchronisation
sudo systemctl status systemd-timesyncd # the time-sync service
```
