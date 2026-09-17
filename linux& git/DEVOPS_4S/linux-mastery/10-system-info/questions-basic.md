# 10 System Info & Monitoring — Basic Questions

**Q1.** Show the kernel version.
```bash
uname -r                 # just the release, e.g. 6.8.0-45-generic
uname -a                 # everything: kernel, hostname, architecture
```

**Q2.** Which Linux distribution and version is this?
```bash
cat /etc/os-release      # NAME, VERSION_ID and PRETTY_NAME for any distro
lsb_release -a           # formatted version, where installed
```

**Q3.** Is this a 64-bit Intel/AMD or an ARM machine?
```bash
uname -m                 # x86_64 = Intel/AMD 64-bit, aarch64 = ARM
```

**Q4.** How long has the machine been up, and how busy is it?
```bash
uptime                   # up-time plus 1/5/15-minute load averages
uptime -p                # pretty form: "up 3 days, 4 hours"
```

**Q5.** How much memory is free?
```bash
free -h                  # total, used, free, shared, buff/cache and AVAILABLE (the number that matters)
```

**Q6.** How many CPU cores do I have?
```bash
nproc                    # number of usable cores
lscpu                    # model, cores, threads, architecture, cache
```

**Q7.** Who is logged in right now?
```bash
who                      # users and their terminals
w                        # the same plus what each of them is running
```

**Q8.** What is the machine called?
```bash
hostname                 # short name
hostnamectl              # name + OS + kernel + whether it is a VM
```

**Q9.** Show the current date in a filename-friendly format.
```bash
date                     # human-readable date and time
date +"%Y-%m-%d_%H-%M"   # custom format, e.g. 2026-09-14_16-30
```

**Q10.** Which command shows recent logins and reboots?
```bash
last -5                  # the last 5 login/reboot events
```

**Q11.** Read the systemd logs for one service.
```bash
sudo journalctl -u nginx -n 50 --no-pager   # last 50 lines, printed without a pager
```

**Q12.** Follow system messages live.
```bash
sudo journalctl -f       # everything, live
sudo dmesg -w            # kernel messages only, live (hardware, USB, OOM kills)
```

**Q13.** Is a service running?
```bash
systemctl status nginx   # state, PID, memory use and the last log lines
```

**Q14.** Re-run a monitoring command every 2 seconds automatically.
```bash
watch -n 2 free -h       # watch refreshes the command on an interval
```
