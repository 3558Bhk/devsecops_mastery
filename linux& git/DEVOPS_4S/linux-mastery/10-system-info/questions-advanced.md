# 10 System Info & Monitoring — Advanced Questions

**Q1.** Is my load average actually a problem?
```bash
uptime                   # e.g. load average: 4.10, 3.20, 1.05
nproc                    # e.g. 4 cores
```
Load ≈ number of runnable processes. Load 4 on 4 cores is fully busy but fine; load 20 on 4 cores is a queue.
Compare the 1/5/15 numbers: rising 1-min = getting worse right now.

**Q2.** `free` shows little "free" memory but the system is healthy. Explain.
```bash
free -h                  # look at buff/cache and AVAILABLE, not "free"
```
Linux uses spare RAM as disk cache and gives it back instantly. `available` is the real answer.

**Q3.** Find what is consuming memory, per process.
```bash
ps aux --sort=-%mem | head -6                      # top memory users
ps -eo pid,user,%mem,rss,cmd --sort=-rss | head    # RSS = actual resident kilobytes
sudo smem -tk -r 2>/dev/null | head                # proportional set size, if installed
```

**Q4.** Read raw kernel statistics without extra tools.
```bash
cat /proc/loadavg        # load averages + running/total processes + last PID
cat /proc/meminfo        # full memory breakdown
cat /proc/cpuinfo        # per-core CPU details
cat /proc/uptime         # seconds since boot
vmstat 1 5               # 5 one-second samples: r (run queue), wa (I/O wait), si/so (swap)
```

**Q5.** Detect swapping before it becomes an outage.
```bash
vmstat 1 5               # si/so columns non-zero = actively swapping (bad)
free -h                  # swap "used" growing over time
cat /proc/sys/vm/swappiness   # 0-100: how eagerly the kernel swaps
```

**Q6.** Collect a full system snapshot for a support ticket.
```bash
{ date; uname -a; cat /etc/os-release; uptime; free -h; df -h; lsblk; ip -br a;
  systemctl list-units --failed; sudo dmesg | tail -30; } > snapshot.txt 2>&1
```

**Q7.** Check whether the machine is physical or virtual.
```bash
hostnamectl              # the "Virtualization" line names KVM/VMware/WSL etc.
systemd-detect-virt      # prints the platform, or "none" for bare metal
sudo dmidecode -s system-product-name   # hardware-level product name
```

**Q8.** Find out what changed recently — was something installed or updated?
```bash
sudo grep " install " /var/log/dpkg.log | tail -20    # Debian/Ubuntu package history
sudo journalctl --since "2 hours ago" -p notice --no-pager | tail -30   # recent notable events
ls -lt /etc | head                                    # recently touched config files
```

**Q9.** List failed services after a reboot.
```bash
systemctl list-units --failed            # everything that failed to start
systemctl status <name>                  # why
sudo journalctl -u <name> -b --no-pager  # its logs since this boot
```

**Q10.** Check hardware health and temperatures.
```bash
sudo smartctl -H /dev/sda         # disk: PASSED/FAILED
sensors                           # CPU temperatures and fan speeds (lm-sensors package)
sudo lshw -short                  # compact inventory of all hardware
lspci                             # PCI devices (GPU, network cards)
lsusb                             # USB devices
```

**Q11.** Compare this boot against the previous one after a crash.
```bash
sudo journalctl -b -1 -p err --no-pager | tail -30   # errors from the PREVIOUS boot
sudo journalctl -b 0 -p err --no-pager | tail -30    # errors from this boot
last -x reboot shutdown | head                       # boot/shutdown history
```

**Q12.** Set up long-term resource history instead of eyeballing `top`.
```bash
sudo apt install sysstat                 # installs sar
sudo systemctl enable --now sysstat      # start collecting
sar -u                                   # CPU history for today
sar -r                                   # memory history
sar -b                                   # I/O history
```
