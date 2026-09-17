# Pattern: What system am I on?

```bash
uname -a                              # ALL info: kernel name, version, architecture, in one line
uname -r                              # just the kernel release (e.g. 6.8.0-45-generic)
uname -m                              # architecture: x86_64 (Intel/AMD 64-bit) or aarch64 (ARM)
cat /etc/os-release                   # which DISTRO and version (Ubuntu 24.04, Debian 12, ...)
lsb_release -a                        # the same, formatted (not installed everywhere)
hostname                              # this machine's name
hostnamectl                           # hostname + OS + kernel + virtualization info, all together
uptime                                # how long since boot + load averages
uptime -p                             # pretty: "up 3 days, 4 hours"
who                                   # who is logged in right now
w                                     # who is logged in AND what they're running
last -5                               # the last 5 logins/reboots
date                                  # current date and time
date +"%Y-%m-%d_%H-%M"                # custom format, perfect for naming backup files
timedatectl                           # timezone, NTP sync status
lscpu                                 # CPU model, cores, threads
lsb_release -cs                       # just the codename (e.g. "noble")
```

## The one-liner to identify any machine

```bash
echo "$(hostnamectl --static) | $(uname -r) | $(. /etc/os-release && echo $PRETTY_NAME)"
```
- `$(...)` runs the inner command and inserts its output
- `.` sources the file so `$PRETTY_NAME` becomes available

## Practice

Run `cat /etc/os-release` and note your VERSION_ID.
