# RTIQ — Real-Time Interview Questions (Linux)

**Target roles:** Senior DevOps Engineer · Senior Systems Administrator · SDE-3 · SRE
**Format:** topic-wise, matching the folders in this course. Each entry gives the question,
*what the interviewer is really testing*, a senior-level answer with the actual commands,
the follow-ups they will ask, and the signal that separates senior from mid-level.

> **How to answer in a real interview:** state the diagnosis path out loud, name the command,
> explain *why* that command, and end with the fix plus how you'd prevent recurrence.
> Interviewers grade the reasoning loop, not memorised flags.

---

## Topic 1 — Filesystem, paths & navigation

### Q1. Explain the Linux filesystem hierarchy. Where would you put a third-party app, a log, and a config?

**Testing:** whether you know the FHS well enough to make defensible decisions.

```bash
ls -l /usr/local/bin      # locally installed software binaries (not from the package manager)
ls -l /opt                # self-contained third-party applications
ls -l /etc                # host-wide configuration (text only, no binaries)
ls -l /var/log            # logs and spool data — must survive reboots
ls -l /var/lib            # persistent state: databases, container images
ls -l /tmp /var/tmp       # /tmp may be cleared on boot, /var/tmp must not be
ls -l /proc /sys          # virtual filesystems: kernel and device state, no disk usage
```

**Answer structure:** `/` root · `/bin`+`/usr/bin` binaries · `/etc` config · `/home` users ·
`/var` variable data (log, lib, cache, spool) · `/opt` add-on software · `/usr/local` locally
compiled/installed · `/tmp` scratch · `/proc`,`/sys`,`/dev` virtual.
Third-party self-contained app → `/opt/<vendor>` with a symlink in `/usr/local/bin`.
Log → `/var/log/<app>/`. Config → `/etc/<app>/`.

**Follow-ups:** Why is `/usr` sometimes a separate mount? → historically read-only shareable across
hosts; today it means `/usr` can be on a different volume and must be mounted before most services.
What's the difference between `/run` and `/var/run`? → `/run` is tmpfs for runtime state (PIDs,
sockets) cleared at boot; `/var/run` is a symlink to it.

**Senior signal:** you mention that anything under `/proc` and `/sys` is kernel-generated and costs
no disk, so `du /` reporting "huge" numbers there is meaningless.

---

### Q2. What is an inode? A user says "disk is 60% full but I cannot create a file". Explain and diagnose.

**Testing:** inode exhaustion — a classic that separates people who have actually run servers.

```bash
df -h /data                       # shows 60% used — space is not the problem
df -i /data                       # IUse% at 100% → inode exhaustion
find /data -xdev -type f -size -1k | wc -l    # millions of tiny files?
du -sh /data/* | sort -rh | head  # space distribution for comparison
find /data -xdev -printf '%h\n' | cut -d/ -f1-4 | sort | uniq -c | sort -rn | head   # which dir has the file explosion
```

**Answer:** An inode is the metadata record for a file: permissions, owner, size, timestamps, and
pointers to data blocks — but *not* the filename. Filenames live in the directory entry, which is
why hard links are multiple names for one inode. Inodes are allocated at filesystem creation
(`mkfs.ext4 -N` / bytes-per-inode), so a filesystem can run out of inodes while plenty of blocks
remain free. Typical cause: session/cache/tmp junk, mail spool, or a runaway job writing millions
of small files.

**Fix:** delete or archive the small-file pile; long-term, move that workload to XFS (allocates
inodes dynamically) or restructure into tarballs/databases.

**Follow-ups:** How do you find a file's inode? `ls -i file`, `stat file`.
Why can't hard links cross filesystems? → an inode number is only meaningful within one filesystem.
Why can't you hard-link a directory? → it would create cycles in the directory tree.

---

### Q3. `rm` a file, but `df` still shows the space used. What happened?

**Testing:** deleted-but-open file handles — very common in production.

```bash
sudo lsof +L1                     # files with link count 0 that are still open
sudo lsof | grep -i deleted       # alternative view
sudo ls -l /proc/<pid>/fd/ | grep -i deleted   # the exact fd of the holding process
sudo systemctl restart rsyslog    # restart the writer to release the space
: > /proc/<pid>/fd/3              # truncate it through /proc without restarting (careful!)
```

**Answer:** `rm` unlinks the directory entry. The data blocks are freed only when the link count
*and* the open-file-descriptor count both reach zero. A daemon still holding the file (a log that was
`rm`'d instead of rotated) keeps the space allocated, and keeps writing into an invisible file.

**Senior signal:** you say the correct fix is `logrotate` with `copytruncate` or postrotate
`systemctl reload`, not `rm`; and that `: > /proc/PID/fd/N` is an emergency truncation trick that
avoids a restart.

---

### Q4. Symlink vs hard link — production implications?

```bash
ln -s /etc/app/config.yml /opt/app/config.yml   # soft: stores a path
ln /data/file /backup/file                      # hard: stores the same inode
ls -li /data/file /backup/file                  # identical inode numbers
readlink -f /opt/app/config.yml                 # resolve the soft link fully
stat -c '%h %n' /data/file                      # link count
```

| | Hard link | Soft link |
|---|---|---|
| What it stores | the same inode | a path string |
| Survives original deletion | yes | no — becomes dangling |
| Crosses filesystems | no | yes |
| Can point at a directory | no (normally) | yes |
| Broken by moving the target | no | yes, if the path changes |

**Real-world gotcha:** `tar`, `rsync -a` and `cp -a` preserve symlinks as symlinks. If you back up a
directory whose symlink targets live *outside* the backup, restoring elsewhere produces dangling
links. Also: many editors (vim, sed -i) write a new file and rename it over the old one, which
**breaks hard links** and replaces a symlink with a regular file — that's why `sed -i` on a symlink
can silently change the link into a file.

---

## Topic 2 — Permissions, users, ACLs & security

### Q5. Explain `-rwsr-x---` on `/usr/bin/passwd`. Why is it needed?

**Testing:** setuid — the single most misunderstood permission bit.

```bash
ls -l /usr/bin/passwd            # -rwsr-x--- 1 root root
ls -ld /tmp                      # drwxrwxrwt  → sticky bit
stat -c '%a %A %n' /usr/bin/passwd   # 4750 — the leading 4 is setuid
find / -xdev -perm -4000 -type f 2>/dev/null   # audit every setuid binary
```

**Answer:** The `s` in the owner-execute position is **setuid**: the program runs with the
*file owner's* privileges (root), not the caller's. `passwd` must write `/etc/shadow`, which is
root-only, so an unprivileged user needs temporary elevation. The **sticky bit** (`t`) on `/tmp`
means only a file's owner may delete or rename it, even though the directory is world-writable.
**setgid** on a directory makes new files inherit the directory's group — used for shared team folders.

**Follow-ups:** Why is setuid dangerous? → any bug in that binary is a local root exploit; audit
them regularly and remove unused ones. Does setuid work on shell scripts? → no, the kernel ignores it
for interpreted scripts (a deliberate security decision). What's the numeric for setgid+sticky?
2 and 1 respectively, so 7777 is the maximum.

**Senior signal:** you mention `chmod g+s shared/` plus `umask 002` as the correct shared-team-folder
recipe, and that `umask 077` is the default-private recipe.

---

### Q6. A web server running as `www-data` gets "Permission denied" reading `/var/www/app/config.yml`, but the file is 644. Why?

**Testing:** path traversal permissions — juniors check the file, seniors check every parent.

```bash
sudo -u www-data cat /var/www/app/config.yml    # reproduce AS the failing user — the key move
namei -l /var/www/app/config.yml                # permissions of every directory along the path
ls -ld /var /var/www /var/www/app
```

**Answer:** To read a file you need `x` (search) on **every** parent directory, plus `r` on the file.
A 644 file inside a `750 root:root` directory is unreadable by `www-data`. Other usual suspects:
the file is on a mount with `noexec`/`nosuid`/`ro`, SELinux/AppArmor is denying it (check
`ausearch -m avc -ts recent` or `dmesg | grep -i denied`), or an ACL overrides the mode bits
(`getfacl`).

**Follow-ups:** How do you check for an ACL? `getfacl file` — a `+` appears in `ls -l` (e.g. `-rw-r--r--+`).
How do you grant one extra user access without opening it to everyone?
```bash
sudo setfacl -m u:deploy:r /etc/app/config.yml     # grant read to one user
sudo setfacl -m d:g:devs:rx /srv/project           # default ACL: inherited by new files
getfacl /etc/app/config.yml
```
SELinux: `ls -Z`, `restorecon -Rv /var/www`, `semanage fcontext -a -t httpd_sys_content_t '/var/www(/.*)?'`.

---

### Q7. You must give three developers write access to `/srv/app` — files they create must stay group-editable — without giving anyone root.

```bash
sudo groupadd devteam                             # 1. shared group
sudo usermod -aG devteam dev1 dev2 dev3           # 2. add users (-a is critical: append, not replace)
sudo chgrp -R devteam /srv/app                    # 3. group ownership
sudo chmod -R g+rwX /srv/app                      # 4. capital X = execute on DIRECTORIES only
sudo chmod g+s /srv/app                           # 5. setgid: new files inherit the group
# 6. make sure umask doesn't strip group write on new files:
echo 'umask 002' | sudo tee -a /etc/profile.d/devteam.sh
```

**Why each step:** `-aG` without `-a` would *replace* the user's group list. Capital `X` avoids
making plain data files executable. setgid handles group inheritance for new files but *not* the
permission bits — that's what `umask 002` fixes. For finer control use default ACLs
(`setfacl -d -m g:devteam:rwx /srv/app`), which survive regardless of umask.

**Follow-ups:** How do you verify? `sudo -u dev1 touch /srv/app/t && ls -l /srv/app/t` →
should be `-rw-rw-r-- dev1 devteam`. What if the app runs as a service user? Add that user to
`devteam` too. Newgrp vs re-login? `newgrp devteam` applies the group in the current shell only.

---

### Q8. Audit a server for security misconfigurations. What do you check, in order?

```bash
# accounts & access
awk -F: '($3==0){print $1}' /etc/passwd          # any UID 0 account besides root?
sudo grep -v '^#' /etc/sudoers /etc/sudoers.d/* 2>/dev/null | grep -v '^$'   # active sudo rules
sudo awk -F: '($2==""){print $1}' /etc/shadow    # accounts with EMPTY passwords
sudo passwd -S -a | grep -v '^#' | head          # locked/expired status
# ssh
sudo sshd -T | grep -Ei 'permitrootlogin|passwordauthentication|permitemptypasswords|x11forwarding'
# network exposure
sudo ss -tulnp                                   # what is listening, and on 0.0.0.0 or 127.0.0.1?
# permissions
find / -xdev -type f -perm 777 2>/dev/null | head
find / -xdev -perm -4000 -type f 2>/dev/null     # setuid binaries
find /home -maxdepth 3 -name '.ssh' -type d ! -perm 700 2>/dev/null
find / -xdev -name id_rsa -o -name '*.pem' 2>/dev/null | head   # private keys lying around
# patching & integrity
sudo apt list --upgradable 2>/dev/null | wc -l
sudo journalctl -p warning -b --no-pager | tail -20
sudo grep -h "Failed password" /var/log/auth.log | awk '{print $(NF-3)}' | sort | uniq -c | sort -rn | head
```

**Answer as a narrative:** identity/access → network exposure → filesystem permissions → secrets →
patch level → audit trail. Then close with prevention: CIS benchmark, `aide` for file integrity,
fail2ban/SSH key-only, `sudo` least-privilege drop-ins, and centralised log shipping.

**Senior signal:** you mention that findings without remediation ownership are worthless — you'd
produce a risk-ranked report with owners and dates, and automate the check into CI/compliance scanning.

---

### Q9. An SSH key is rejected with "UNPROTECTED PRIVATE KEY FILE". Also: how does key auth actually work?

```bash
ls -l ~/.ssh                    # must be 700
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_ed25519     # private key: owner-only
chmod 644 ~/.ssh/id_ed25519.pub
chmod 600 ~/.ssh/authorized_keys
chmod 755 ~                     # the HOME directory must not be group/world-writable
ssh -vvv user@host              # verbose handshake shows exactly where it fails
sudo tail -f /var/log/auth.log  # server side: why it refused
```

**Handshake explanation:** the server sends a random challenge; the client signs it with the
*private* key; the server verifies with the *public* key from `authorized_keys`. The private key
never leaves the client. SSH refuses to use a key that other users can read, because reading it
means impersonating you.

**Follow-ups:** `PermitRootLogin`, `PasswordAuthentication no`, `AllowUsers`, `Match` blocks for
per-user rules. ed25519 vs RSA-4096 → ed25519 is smaller, faster, no parameter-choice pitfalls.
What's an SSH agent and `ssh-add`? → holds decrypted keys in memory; `SSH_AUTH_SOCK` forwarding with
`ssh -A` (risky on untrusted hosts — prefer `ssh -J` jump hosts or agent forwarding off).
What does `~` mean in ssh config? → per-user config; also mention `/etc/ssh/ssh_config` (client)
vs `/etc/ssh/sshd_config` (server) — a classic mix-up.

---

## Topic 3 — Processes, signals & resource control

### Q10. A process is in `D` state and `kill -9` does not remove it. Explain.

**Testing:** the single best signal/internals question for senior roles.

```bash
ps -eo pid,ppid,stat,wchan:32,cmd | awk '$3 ~ /^D/'   # wchan = the kernel function it is blocked in
sudo cat /proc/<pid>/stack                            # kernel stack of the blocked task
sudo lsof -p <pid> | head                             # what it is waiting on (NFS mount? disk?)
mount | grep -E 'nfs|cifs'                            # remote mounts are the usual culprit
sudo dmesg -T | grep -iE "nfs|hung task|i/o error"    # "task blocked for more than 120 seconds"
```

**Answer:** `D` = uninterruptible sleep: the task is inside a kernel call that cannot accept signals
(typically blocking I/O on a stalled NFS/CIFS mount or a failing disk). Signals are delivered only
when the process returns to user space, so `SIGKILL` is queued and never acted on. You cannot kill it;
you fix the underlying I/O (restore the mount, `umount -f -l`, replace the disk) or reboot.

**Follow-ups:** What about `Z` (zombie)? → the process is dead; only its exit status remains in the
process table until the parent `wait()`s. Kill the *parent*, or let init reap it. Zombies consume a
PID slot, not memory. What is `T`? → stopped (SIGSTOP/Ctrl+Z), resume with SIGCONT.
What does `+` mean in STAT? → foreground process group. `s` → session leader. `l` → multi-threaded.

**Senior signal:** you mention that in Kubernetes, D-state processes are a common cause of pods stuck
in `Terminating`, and the fix is at the node level (force-delete the pod is cosmetic; the kubelet
waits on the same uninterruptible task).

---

### Q11. Load average is 40 on a 4-core box but CPU is 15% idle-ish. Diagnose.

```bash
uptime; nproc                          # load vs core count
vmstat 1 5                             # r=run queue, b=blocked, wa=iowait, si/so=swap
ps -eo pid,stat,wchan,cmd | awk '$2 ~ /^D/' | head   # blocked tasks
iostat -x 1 3                          # %util, await, r_await/w_await per device
iotop -oP                              # per-process I/O (needs root)
free -h; cat /proc/meminfo | grep -E 'MemAvailable|SwapFree'
sar -q 1 5                             # historical load and run queue
sudo cat /sys/fs/cgroup/cpu.stat 2>/dev/null   # nr_throttled → container CPU throttling
```

**Answer:** Load average counts tasks that are *runnable or uninterruptible*. High load with idle CPU
⇒ I/O wait or a huge number of blocked tasks. Steps: confirm with `vmstat`'s `wa` and `b` columns →
identify the device with `iostat -x` (`%util` ~100, high `await`) → identify the process with
`iotop` → check hardware health with `smartctl -a` and `dmesg` for I/O errors → check for NFS stalls.

**Container twist (very common follow-up):** inside a container, `/proc/loadavg` reflects the **host**,
and CPU limits cause throttling that looks like slowness with low utilisation. Check
`cpu.stat: nr_throttled / throttled_usec` in the cgroup, and raise the CPU limit or reduce requests.

**Follow-ups:** What do the three load numbers mean? → exponentially damped averages over 1, 5 and
15 minutes; compare 1-min against 15-min to see the trend direction. Is load 4 bad on 4 cores? → it
means fully utilised but not queued; sustained load above core count means a queue.

---

### Q12. Your app was killed randomly. Prove it was the OOM killer.

```bash
sudo dmesg -T | grep -iE "out of memory|oom-kill|killed process"
sudo journalctl -k --since "2 hours ago" | grep -i oom
sudo grep -i oom /var/log/kern.log 2>/dev/null
sudo journalctl -u myapp -b | tail -50       # did the service log a clean shutdown? (no → killed)
cat /proc/<pid>/oom_score_adj                # tunable per process, -1000..1000
free -h; vmstat 1 5                          # si/so non-zero → swapping before the kill
```

**Answer:** The kernel's OOM killer selects a victim by `oom_score` (driven by RSS, `oom_score_adj`
and cgroup memory limits) when memory plus swap are exhausted and allocation fails. `dmesg` shows a
block listing total-vm, rss and the chosen PID — that's your evidence. In containers, an OOM kill is
usually the **cgroup limit**, not host memory: check `memory.events: oom_kill` and
`memory.max` in the cgroup, and Kubernetes `Last State: Terminated, Reason: OOMKilled (137)`.

**Fixes:** raise the limit / fix the leak (heap dump, `valgrind`, profiling) · set
`vm.overcommit_memory` policy deliberately · add `oom_score_adj=-500` for critical daemons ·
configure swap and `vm.swappiness` · set `MemoryMax=` in the systemd unit so a leak kills the
service, not the host.

**Follow-ups:** Exit code 137 = 128+9 = SIGKILL; 143 = 128+15 = SIGTERM. What does
`vm.overcommit_memory=1` do? → always allow overcommit (common for Redis, which forks for RDB saves).

---

### Q13. Write a systemd unit for a service that must restart on failure, run as a non-root user, and log to the journal.

**Testing:** modern service management — most admins still only know `nohup`.

```ini
# /etc/systemd/system/myapp.service
[Unit]
Description=My App
After=network-online.target          # start only once networking is genuinely up
Wants=network-online.target
Documentation=https://internal/myapp

[Service]
Type=simple                          # or forking / notify depending on how it daemonises
User=myapp                           # never root if avoidable
Group=myapp
WorkingDirectory=/opt/myapp
ExecStart=/opt/myapp/bin/server --config /etc/myapp/config.yml
ExecReload=/bin/kill -HUP $MAINPID   # what "systemctl reload" does
Restart=on-failure                   # restart on non-zero exit / signal
RestartSec=5s
StartLimitIntervalSec=60             # give up after too many rapid restarts
StartLimitBurst=5
Environment=ENV=production
EnvironmentFile=-/etc/myapp/env      # leading - = optional file
LimitNOFILE=65536                    # file-descriptor limit
MemoryMax=1G                         # cgroup memory cap
CPUQuota=150%
NoNewPrivileges=true                 # hardening
ProtectSystem=strict                 # /usr /boot /etc read-only
ReadWritePaths=/var/lib/myapp
PrivateTmp=true
ProtectHome=true

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload                # after creating or editing any unit
sudo systemctl enable --now myapp           # start now and at boot
systemctl status myapp                      # state, PID, memory, last log lines
sudo journalctl -u myapp -f                 # live logs
systemd-analyze verify myapp.service        # validate the unit
systemctl show myapp -p Restart,MemoryMax   # confirm effective settings
systemctl cat myapp                         # the merged unit + drop-ins
sudo systemctl edit myapp                   # create an override drop-in (never edit the vendor unit)
```

**Follow-ups:** `Type=notify` vs `simple` → notify waits for `sd_notify(READY=1)` so dependencies
start in the right order. Why `After=network-online.target` and not just `network.target`? → the
latter only means the network stack is configured, not that interfaces are up. How do you debug a
unit that fails instantly? `systemctl status`, `journalctl -u`, then `systemd-analyze verify`, then
run the `ExecStart` command manually as that user with `sudo -u myapp`.

---

### Q14. Run a long job that must survive your SSH session dying, be rate-limited, and log properly.

```bash
# best: a transient systemd scope with resource limits
sudo systemd-run --unit=migrate --scope -p MemoryMax=2G -p CPUQuota=200% \
     --working-directory=/opt/app /usr/local/bin/migrate.sh

systemctl status migrate                       # watch it
sudo journalctl -u migrate -f                  # its output, in the journal
sudo systemctl stop migrate                    # kill it cleanly

# alternatives
tmux new -s migrate                            # reattachable interactive session
nohup ./migrate.sh > /var/log/migrate.log 2>&1 &   # survives logout, logs to a file
setsid ./migrate.sh < /dev/null > log 2>&1 &   # fully detached new session
ionice -c3 nice -n 19 ./migrate.sh             # lowest disk and CPU priority
flock -n /tmp/migrate.lock ./migrate.sh        # guarantee only one copy runs (cron-safe)
```

**Senior signal:** you prefer `systemd-run` for anything important (limits, journal, clean stop,
survives logout), `tmux` for interactive work, and `flock` for cron idempotency. You also mention
that `nohup` alone doesn't detach stdin, which can cause surprises.

---

## Topic 4 — Text processing & real one-liners

### Q15. "Given a 20 GB nginx access log, give me the top 10 IPs by request count." Then: "make it memory-safe."

```bash
awk '{print $1}' access.log | sort | uniq -c | sort -rn | head -10
```
**Why it's safe:** `sort` uses external merge sort with temp files, so it does not need the whole
file in RAM. But `sort` on 20 GB is slow and disk-heavy.

**Faster / lower-memory variants:**
```bash
LC_ALL=C sort -T /mnt/scratch --parallel=4 -S 2G access.log | ...   # C locale = byte sort, much faster
cut -d' ' -f1 access.log | LC_ALL=C sort | uniq -c | sort -rn | head    # cut is cheaper than awk
awk '{c[$1]++} END {for (ip in c) print c[ip], ip}' access.log | sort -rn | head   # single pass, RAM = unique IPs
mawk '{print $1}' access.log | ...        # mawk is several times faster than gawk
zcat access.log.*.gz | ...                # handle rotated compressed logs too
```

**Follow-ups:** How would you do it on 100 files across 10 hosts? → `parallel`/`xargs -P` per host,
partial counts, then merge sums (`awk '{c[$2]+=$1} END{...}'`).
Why does `LC_ALL=C` matter? → skips locale-aware collation; often 2–10× faster and changes ordering
for non-ASCII.
What if a line has the IP in a different field? → parse properly (`awk -F'"'` for quoted fields) or
use a real parser; don't guess field numbers on logs you didn't design.

**Senior signal:** you mention that at this scale the right answer is usually "don't grep 20 GB —
ship logs to Loki/Elasticsearch/ClickHouse and query them", and you can quantify when a one-liner
is still the better tool (ad-hoc, no infra, one-off).

---

### Q16. Find every line that changed between two large files, ignoring order and whitespace.

```bash
diff <(sort -u a.txt) <(sort -u b.txt)          # process substitution, no temp files
comm -3 <(sort a.txt) <(sort b.txt)             # column 1 = only in a, column 2 = only in b
diff -w -B a.txt b.txt                          # ignore whitespace and blank lines
diff -u a.txt b.txt | grep -E '^[+-]' | grep -v '^[+-][+-]'   # just the changed lines
sdiff -W 120 a.txt b.txt                        # side-by-side, width-limited
```

**Follow-ups:** How do you verify two big files are identical quickly? `cmp -s a b` (byte compare,
stops at first difference) then `sha256sum`. When is a checksum not enough? → when you need to know
*what* differs, or when comparing across a network with different block sizes.

---

### Q17. Parse `/etc/passwd` and print users with a real shell, sorted by UID.

```bash
awk -F: '$7 !~ /(nologin|false)$/ {printf "%-6s %-16s %s\n", $3, $1, $7}' /etc/passwd | sort -n
getent passwd | awk -F: '$3>=1000 && $3<65534 {print $1, $3}'   # normal human users (UID >= 1000)
```
**Why `getent` and not `cat /etc/passwd`:** `getent` goes through NSS, so it also returns users from
LDAP/SSSD/AD. Reading `/etc/passwd` directly misses them entirely — a very common audit mistake.

**Follow-ups:** What is field 2 in `/etc/passwd`? → `x`, meaning the hash lives in `/etc/shadow`
(readable only by root). What are `/etc/nsswitch.conf` and PAM? → NSS decides *where* user/group data
comes from; PAM decides *how* authentication/authorisation happens. What is the `nologin` shell for?

---

### Q18. Extract the third column of a CSV that contains quoted commas. `cut -d,` is wrong — what do you use?

```bash
awk -F, '{print $3}' data.csv                  # WRONG when fields contain "a,b" or embedded quotes
python3 -c 'import csv,sys; [print(r[2]) for r in csv.reader(sys.stdin)]' < data.csv   # correct
csvcut -c 3 data.csv                           # csvkit, if available
mlr --icsv --onidx cut -f 3 data.csv           # miller: fast, schema-aware
q -H -d, "SELECT * FROM data.csv"              # q: SQL over CSV
```

**Answer:** CSV is not a delimited-text format — it has quoting and escaping rules (RFC 4180).
Field-splitting tools break on quoted separators, embedded newlines and doubled quotes. Use a real
CSV parser. For simple, known-clean exports, `awk -F,` is acceptable; state that assumption out loud.

**Senior signal:** you say "I'd first check whether the file is actually RFC-compliant with
`head -1` and a row count, because most real-world 'CSV' problems are upstream export bugs."

---

## Topic 5 — Disk, storage, LVM & RAID

### Q19. The root filesystem hit 100% and a database is misbehaving. Walk me through the incident.

```bash
df -h; df -i                              # 1. which mount, and is it inodes or blocks?
sudo lsof +L1                             # 2. deleted-but-open files holding space
sudo du -xh --max-depth=1 / | sort -rh | head    # 3. biggest dirs ON THIS FILESYSTEM (-x = don't cross mounts)
sudo du -xh --max-depth=1 /var | sort -rh | head # 4. drill down (logs, spool, docker, db)
find / -xdev -type f -size +500M -exec ls -lh {} + 2>/dev/null   # 5. individual giants
sudo journalctl --disk-usage              # 6. journal size
```
**Fast, safe wins:**
```bash
sudo journalctl --vacuum-size=200M        # shrink journals
sudo apt clean && sudo apt autoremove -y  # package caches and orphaned kernels
docker system df && docker system prune -af --filter "until=168h"   # docker is often the culprit
find /var/log -name "*.gz" -mtime +30 -delete    # old rotated logs
: > /proc/$(pgrep -f myapp | head -1)/fd/1       # emergency truncate of a live log fd (no restart)
```
**Then the DB angle:** a full filesystem makes databases fail in ugly ways — Postgres/MySQL will
refuse writes, WAL/redo segments stall, and InnoDB can crash. Order matters: free space *first*,
then check DB health (`systemctl status`, error log, replication lag), then restart only if needed.

**Prevention (this is what they want to hear):** `df`-based alerting at 75/85/95%, log rotation with
size caps (`maxsize` in logrotate), `journalctl` SystemMaxUse in `/etc/systemd/journald.conf`,
Docker log driver limits (`max-size`/`max-file`), separate mounts for `/var`, `/var/log`, `/var/lib/docker`
so one runaway workload can't take the root FS, and quota/XFS project quotas for shared dirs.

---

### Q20. Explain LVM. You need to grow `/var` on a live production server with zero downtime — how?

```bash
lsblk -f; sudo pvs; sudo vgs; sudo lvs    # physical volumes → volume group → logical volumes
sudo lvextend -L +20G /dev/vg0/var        # 1. grow the logical volume
sudo resize2fs /dev/vg0/var               # 2a. ext4: grow online (mounted)
sudo xfs_growfs /var                      # 2b. xfs: grow the mounted filesystem (xfs cannot shrink)
df -h /var                                # 3. verify
```
**If the VG has no free space, add a disk first:**
```bash
lsblk                                     # find the new device, e.g. /dev/sdb
sudo pvcreate /dev/sdb                    # make it a physical volume
sudo vgextend vg0 /dev/sdb                # add it to the volume group
sudo vgs                                  # confirm VFree increased
```
**One-liner version:** `sudo lvextend -l +100%FREE -r /dev/vg0/var` — `-r` resizes the filesystem too.

**Follow-ups:** Can you shrink XFS? → no, never; shrink means backup → recreate → restore.
What is a snapshot and when would you use one?
```bash
sudo lvcreate -s -n var_snap -L 10G /dev/vg0/var   # copy-on-write snapshot
mount /dev/vg0/var_snap /mnt/snap                   # consistent read of a live filesystem
sudo lvremove /dev/vg0/var_snap                     # remove when done
```
Snapshots are for crash-consistent backups and risky upgrades. Caveats: they consume VG space as
blocks change (overfilling a snapshot invalidates it — monitor with `lvs` "Snap%"), and they cost
write performance. For databases use the DB's own backup/`FLUSH TABLES WITH READ LOCK` for
*application*-consistency.

**Thin provisioning:** `lvcreate -V 50G --thinpool pool0 -n thinvol` — over-allocate, but monitor
`Data%`/`Meta%` or the pool fills and the volumes go read-only.

---

### Q21. RAID 5 vs 6 vs 10 for a database server. Also: a disk failed — walk me through the replacement.

**Answer:** RAID 10 (mirror+stripe) for databases: best random read/write IOPS, survives one disk per
mirror, fast rebuild. RAID 5 has the write penalty (read-modify-write for parity) and a dangerous
rebuild window — with multi-TB drives, rebuild stress plus a single parity means a second failure
during rebuild loses everything. RAID 6 (double parity) is acceptable for capacity/archive tiers.
Also mention: hardware RAID needs a BBU/cache policy; ZFS/mdraid give you checksums and self-healing
that hardware RAID cannot; and backups are not RAID.

```bash
cat /proc/mdstat                          # mdraid state: [UUU_] means one disk is out
sudo mdadm --detail /dev/md0              # which device failed, and its slot
sudo smartctl -a /dev/sdb                 # confirm the disk is actually dying (reallocated sectors)
sudo mdadm /dev/md0 -f /dev/sdb           # mark it failed
sudo mdadm /dev/md0 -r /dev/sdb           # remove it
# physically replace the drive, then:
sudo mdadm /dev/md0 -a /dev/sdb           # add the new disk
watch cat /proc/mdstat                    # rebuild progress
sudo mdadm --detail --scan >> /etc/mdadm/mdadm.conf   # persist the array config
sudo update-initramfs -u                  # make sure the array assembles at boot
```
**Follow-ups:** What is a hot spare? `mdadm --add /dev/sdc` as spare; auto-rebuild on failure.
Why is rebuild risky? → sustained read load on already-stressed siblings (URE probability per TB read);
that's the argument for RAID 6/10 on large disks. How do you get notified? → `mdmonitor` +
`MAILADDR` in mdadm.conf, or node_exporter's `mdraid` collector.
`smartctl` thresholds worth alerting on: `Reallocated_Sector_Ct`, `Current_Pending_Sector`,
`Offline_Uncorrectable`, `Wear_Leveling_Count` (SSD), and `SMART overall-health: FAILED`.

---

### Q22. A mount that should exist at boot is missing after a reboot. How do you make mounts robust?

```bash
cat /etc/fstab; findmnt -a                # compare intent vs reality
sudo mount -a                             # reproduce the error interactively (never just reboot and hope)
sudo blkid; ls -l /dev/disk/by-uuid/      # get the stable UUID
sudo journalctl -b -p err | grep -i mount # what systemd reported
systemctl status local-fs.target          # did the local filesystem target fail?
```
**Robust fstab entry:**
```text
UUID=1234-ABCD  /data  ext4  defaults,nofail,x-systemd.device-timeout=10  0  2
```
- `nofail` → boot continues even if the device is absent (critical for network/iSCSI/NFS storage)
- `UUID=` or `LABEL=` → survives device renaming (`/dev/sdb` becoming `/dev/sdc`)
- `x-systemd.automount` → mount on first access instead of at boot
- `_netdev` → treat as a network filesystem, ordered after network-online
- last two columns: dump flag and fsck order (0 = don't fsck, 1 = root, 2 = others)

**NFS specifics:** `vers=4.2`, `hard` vs `soft` (hard = block forever and retry — correct for data
integrity; soft = return EIO after timeout, risks corruption), `intr`, `timeo`, `retrans`, and
`_netdev,nofail` so a down NFS server cannot hang the boot. Hung NFS is the classic cause of
D-state processes and unbootable machines.

---

## Topic 6 — Networking

### Q23. "The app can't reach the database." Give me your full diagnostic path.

```bash
# Layer 1-3: reachability
ip -br a; ip r                            # do I have an address and a default route?
ping -c3 db.internal                      # ICMP (may be blocked — don't over-trust it)
sudo traceroute -T -p 5432 db.internal    # TCP traceroute to the actual port (ICMP is often filtered)
mtr -T -P 5432 db.internal                # live per-hop loss and latency
# Layer 3 (DNS)
getent hosts db.internal                  # uses NSS: honours /etc/hosts and search domains
dig +short db.internal; dig db.internal @127.0.0.53   # which resolver answered?
cat /etc/resolv.conf; resolvectl status   # search domains, DNS servers, DNSSEC
# Layer 4 (port/firewall)
nc -zv -w3 db.internal 5432               # is the port open?
timeout 3 bash -c '</dev/tcp/db.internal/5432' && echo open   # no nc? pure bash
sudo nmap -p5432 db.internal              # filtered vs closed vs open — different meanings
# Local egress path
sudo iptables -L OUTPUT -n -v; sudo nft list ruleset | head -40
sudo ss -tnp state syn-sent               # my stuck connection attempts
# Server side
sudo ss -tulnp | grep 5432                # is it listening on 0.0.0.0 or only 127.0.0.1?
sudo tcpdump -ni any host db.internal and port 5432   # do packets arrive? is there a RST?
```
**Interpretation matrix (this is the part they grade):**
| Symptom | Likely cause |
|---|---|
| DNS fails, IP ping works | resolver/search-domain/DNS outage |
| `Connection refused` (RST) | nothing listening, or wrong port |
| Timeout, no response | firewall DROP, security group, routing |
| `No route to host` | routing/ARP or ICMP-unreachable from a firewall |
| Connects then resets mid-transfer | MTU/PMTUD black hole, or an idle-timeout LB |
| Works by IP, not by name | DNS |
| Works from host, not from container | network namespace / CNI / kube-proxy / iptables |

**Follow-ups:** MTU black holes: `ping -M do -s 1472 host` to find the path MTU; fix with
`ip link set dev eth0 mtu 1400` or TCP MSS clamping. `ss -s` for socket summary. TIME_WAIT floods:
`ss -tan state time-wait | wc -l`, tune `ip_local_port_range`, use keepalives/connection pooling
(don't just enable `tcp_tw_reuse` blindly).

---

### Q24. What is listening on this machine, and how do you find an unknown process holding a port?

```bash
sudo ss -tulnp                             # t=tcp u=udp l=listening n=numeric p=process
sudo ss -tunap state established | head    # established connections too
sudo lsof -i :8080 -P -n                   # who owns port 8080
sudo lsof -i -P -n | grep LISTEN           # all listeners
sudo fuser -n tcp 8080                     # PID owning a port (and -k to kill it)
sudo netstat -tulnp                        # legacy equivalent
ss -o state established '( dport = :443 )' # filter by state/port with native ss syntax
```
**Reading the output:** `Local Address:Port` `0.0.0.0:80` = all interfaces; `127.0.0.1:5432` = local
only (a common "why can't the app connect from another host" answer); `[::]:80` = IPv6 wildcard.

**Follow-ups:** Why `ss` over `netstat`? → `ss` reads netlink/`tcp_diag` directly; `netstat` walks
`/proc`, which is far slower on hosts with many sockets. What is `SO_REUSEADDR`/`SO_REUSEPORT`?
How do you find connections per remote IP? `ss -tn state established | awk '{print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head`.

---

### Q25. Explain what happens when you `curl https://example.com` — end to end.

**Answer (structure it, don't ramble):**
1. **URL parse** → scheme, host, port 443, path.
2. **DNS** → resolver library (glibc/NSS) → `/etc/hosts`, then stub resolver → recursive resolver
   → root → TLD → authoritative; A/AAAA records, TTL caching, CNAME chains.
3. **Routing/socket** → route lookup (`ip r get <ip>`), source address selection, `socket()`,
   `connect()` → TCP 3-way handshake (SYN, SYN-ACK, ACK). Possibly NAT/conntrack on the way.
4. **TLS** → ClientHello (SNI = the hostname, cipher suites, ALPN for h2) → ServerHello + cert chain
   → certificate validation against the CA store, hostname and expiry checks → key exchange
   (ECDHE) → Finished → symmetric session keys. Optionally TLS 1.3 0-RTT/session resumption.
5. **HTTP** → request line, headers (Host, User-Agent, Accept-Encoding), possibly auth →
   server/LB/CDN → response status, headers, body (chunked/gzip). Redirects if `-L`.
6. **Teardown** → TLS close_notify, TCP FIN/ACK → TIME_WAIT on the closer for 2×MSL.

**Where it can break, per layer:** DNS (NXDOMAIN/SERVFAIL/stale TTL) · firewall/security group
(timeout) · nothing listening (RST/refused) · TLS (expired cert, hostname mismatch, missing
intermediate, clock skew, TLS version mismatch) · HTTP (4xx/5xx, WAF block, 429) · MTU (hangs after
handshake on large responses).

```bash
curl -v https://example.com                       # see every step
curl -o /dev/null -sS -w 'dns:%{time_namelookup} conn:%{time_connect} tls:%{time_appconnect} ttfb:%{time_starttransfer} total:%{time_total} code:%{http_code}\n' https://example.com
openssl s_client -connect example.com:443 -servername example.com </dev/null   # TLS + cert chain
echo | openssl s_client -connect example.com:443 2>/dev/null | openssl x509 -noout -dates -subject -issuer
dig +trace example.com                            # the full resolution path
```
**Senior signal:** you use the `-w` timing breakdown to localise latency (DNS vs connect vs TLS vs
TTFB) instead of guessing, and you mention that clock skew breaks TLS validation.

---

### Q26. `iptables` vs `nftables` vs a firewalld/ufw — and how do you debug a dropped packet?

```bash
sudo nft list ruleset                     # nftables: the whole ruleset in one view
sudo iptables -L -n -v --line-numbers     # legacy view (often a translation layer over nft)
sudo iptables -t nat -L -n -v             # NAT table (Docker and Kubernetes live here)
sudo iptables -t mangle -L -n -v
sudo ufw status verbose                   # Ubuntu frontend
sudo firewall-cmd --list-all              # RHEL/firewalld frontend
sudo conntrack -L | head                  # connection-tracking table
sudo sysctl net.netfilter.nf_conntrack_count net.netfilter.nf_conntrack_max
```
**Debugging a drop:**
```bash
sudo iptables -I INPUT 1 -s 10.0.0.5 -j LOG --log-prefix "DBG-IN: "   # temporary logging rule
sudo dmesg -w | grep DBG-IN                                          # watch it
sudo iptables -L INPUT -n -v --line-numbers   # packet counters tell you which rule matched
sudo tcpdump -ni eth0 host 10.0.0.5          # did it even arrive? (tcpdump sees pre-netfilter)
sudo nft monitor trace                        # nftables packet tracing
```
**Key points:** rule order matters (first match wins); counters incrementing on a DROP rule is your
proof; `tcpdump` shows packets *before* netfilter, so "tcpdump sees it but the app doesn't" =
firewall/iptables. Docker inserts its own chains (`DOCKER-ISOLATION`, `DOCKER`) into `FORWARD`, and
Docker-published ports bypass `ufw`/`firewalld` INPUT rules — a famous security gotcha. Kubernetes
uses iptables or IPVS rules generated by kube-proxy; a full `nat` table on a big cluster is a
known performance issue (hence IPVS/eBPF/Cilium).

**conntrack exhaustion** is a top-tier production issue: `nf_conntrack: table full, dropping packet`
in dmesg → raise `nf_conntrack_max`, reduce timeouts, or bypass conntrack for high-volume flows.

---

## Topic 7 — Performance, monitoring & benchmarking

### Q27. A server is "slow". Give me a 60-second triage you'd actually run.

**Testing:** a systematic method (USE method), not a bag of tricks.

```bash
uptime                                    # load 1/5/15 → trend direction
dmesg -T | tail -20                       # OOM kills, I/O errors, hung tasks, NIC resets
vmstat 1 5                                # r, b, si/so, wa, us/sy/id in ONE view
mpstat -P ALL 1 3                         # per-core: is one core pegged (single-threaded bottleneck)?
pidstat -u 1 3; pidstat -d 1 3            # per-process CPU and I/O
iostat -xz 1 3                            # per-device util/await/queue depth
free -h                                   # available memory, swap usage
sar -n DEV 1 3                            # NIC throughput and errors
sar -q 1 3                                # run queue and load history
ps -eo pid,ppid,stat,%cpu,%mem,wchan,cmd --sort=-%cpu | head
sudo perf top                             # where the CPU time actually goes (flame-graph territory)
```
**The USE method (say this phrase):** for every resource — CPU, memory, disk, network — check
**U**tilisation, **S**aturation, **E**rrors. Saturation is what most people forget: run queue length,
`await`/queue depth, swap in/out, NIC drops, `ListenOverflows`/`ListenDrops` for sockets.

```bash
sudo ss -lnt sport = :80                  # Recv-Q on a LISTEN socket = accept-queue backlog
sudo netstat -s | grep -iE 'listen|overflow|retrans'   # TCP retransmits and queue overflows
cat /proc/pressure/cpu /proc/pressure/memory /proc/pressure/io   # PSI: the modern saturation signal
```
**Senior signal:** you mention PSI (pressure stall information) and that it's what `systemd`'s
`MemoryPressure`/OOM policies and cgroup v2 controllers use; and that `top`'s load and `%wa` are
host-wide, misleading inside containers.

---

### Q28. CPU is 90% `%sy` (system) instead of `%us`. What does that mean and how do you chase it?

```bash
vmstat 1 5                                # cs (context switches) and in (interrupts) columns
pidstat -w 1 3                            # per-process voluntary/involuntary context switches
sudo perf top -g                          # kernel-side hot paths
sudo perf record -a -g -- sleep 10 && sudo perf report    # where the kernel time goes
mpstat -P ALL 1                           # softirq distribution (%soft, %irq)
cat /proc/interrupts | head               # interrupt affinity — one core taking all NIC IRQs
sudo cat /proc/softirqs | grep -E 'NET_RX|NET_TX'
```
**Answer:** High `%sy` means time in kernel space: syscalls, networking, memory management, locks,
or interrupt handling. Common causes: excessive syscalls from a chatty app (strace it),
context-switch storms (too many threads), network softirq load pinned to one CPU (fix with RSS/RPS/
IRQ affinity), page-fault/THP compaction stalls, heavy `fork()` (e.g. a PHP/CGI model), or
conntrack/iptables overhead on a busy NAT host.

```bash
sudo strace -c -p <pid> -f                # syscall histogram: which call dominates?
sudo strace -tt -T -p <pid> -e trace=network   # timing of network syscalls
sudo perf stat -p <pid> -- sleep 10       # instructions/cycle, cache misses, page faults
```
**Follow-ups:** When is `strace` dangerous in production? → it ptrace-stops the process, adding huge
overhead; never attach to a latency-critical or multi-threaded process for long. Safer: `perf`, eBPF
(`bpftrace`, `bcc` tools like `syscount`, `funclatency`, `biolatency`, `tcplife`).

---

### Q29. Memory looks full but the app isn't leaking. Explain Linux memory management to me.

```bash
free -h                                   # look at "available", NOT "free"
cat /proc/meminfo | grep -E 'MemTotal|MemAvailable|Cached|Buffers|Slab|SReclaimable|SUnreclaim|Dirty|AnonPages|Shmem|Huge'
vmstat 1 5                                # si/so (swap in/out) and bi/bo
sudo smem -tk -r -P myapp                 # PSS: proportional set size — the honest per-process number
ps -eo pid,rss,vsz,cmd --sort=-rss | head
cat /proc/<pid>/status | grep -E 'VmRSS|VmSwap|VmPeak'
sudo slabtop -o | head                    # kernel slab consumers (dentry/inode cache is usually #1)
cat /proc/sys/vm/swappiness /proc/sys/vm/vfs_cache_pressure /proc/sys/vm/overcommit_memory
sar -B 1 3                                # paging and major-fault statistics
```
**Answer:** Linux uses free RAM as page cache and reclaims it on demand, so "free" is almost always
small and that's healthy. What matters is **MemAvailable** and whether you're swapping or taking
**major page faults**. Distinguish:
- **Page cache/buffers** → reclaimable, good (faster file reads)
- **Slab (SReclaimable)** → dentry/inode caches, reclaimable
- **SUnreclaim / kernel memory** → not reclaimable; growth here means a driver/kernel leak
- **AnonPages + Shmem** → real application memory; this is what forces swap/OOM
- **Dirty** → pages awaiting writeback; a large value plus I/O stalls means writeback pressure
  (`vm.dirty_ratio`, `dirty_background_ratio`)

RSS vs VSZ vs PSS: VSZ includes mapped-but-untouched address space (huge for JVMs); RSS double-counts
shared pages across processes; **PSS** divides shared pages proportionally and is the right number for
capacity planning.

**Follow-ups:** Transparent Huge Pages — why do DBAs disable them? → `khugepaged` compaction causes
latency spikes; Redis/Mongo/Oracle recommend `THP=never`. How do you cap a process?
`systemd-run -p MemoryMax=2G`, cgroup v2 `memory.max`, `ulimit -v` (crude, counts VSZ).

---

### Q30. How do you benchmark a change without fooling yourself?

```bash
# CPU / syscall micro
sysbench cpu --threads=4 run
# Disk — ALWAYS disable the page cache or you measure RAM
fio --name=randwrite --ioengine=libaio --direct=1 --rw=randwrite --bs=4k \
    --size=1G --numjobs=4 --iodepth=32 --runtime=60 --time_based --group_reporting
fio --name=seqread --direct=1 --rw=read --bs=1M --size=4G --runtime=30 --time_based
# Network
iperf3 -s                       # server side
iperf3 -c <server> -P 4 -t 30   # 4 parallel streams
# HTTP
wrk -t8 -c200 -d60s --latency http://host/      # or hey/ab/vegeta/k6
# General
hyperfine 'cmd1' 'cmd2'         # statistical comparison of two commands
```
**Methodology points they're grading:**
- warm-up runs, then N iterations; report median and p95/p99, never just the mean
- change ONE variable at a time; keep a control
- `--direct=1` in fio (bypass page cache), `--size` larger than RAM for realistic disk numbers
- test at the right queue depth: latency at QD1 vs throughput at QD32 are different questions
- measure at the tier that matters (from the client, not on the server)
- beware noisy neighbours, CPU frequency scaling (`cpupower frequency-info`), turbo, and thermal throttling
- pin with `taskset -c`, disable IRQ balance interference, note the kernel version
- **p99 latency is the SLA**, average latency is a lie

---

## Topic 8 — Logging, journald & observability

### Q31. Where do logs live on a modern systemd system, and how do you find why a service failed at 3 AM?

```bash
sudo journalctl -u myapp --since "03:00" --until "04:00" --no-pager   # time-boxed
sudo journalctl -u myapp -b -1 -p err --no-pager | tail -50           # PREVIOUS boot, errors only
sudo journalctl --list-boots                                          # boot IDs and times
sudo journalctl -k -b                                                 # kernel messages this boot
sudo journalctl -p warning --since "1 hour ago"                       # all units, warnings+
sudo journalctl _PID=4242                                             # everything from one PID
sudo journalctl -u myapp -o verbose | head -40                        # all structured fields
sudo journalctl -u myapp --since today -o json | jq -r '.MESSAGE'     # machine-readable export
sudo journalctl -D /var/log/journal                                   # read another host's journal
```
**Classic files (rsyslog/syslog-ng):** `/var/log/syslog`|`messages` (general), `auth.log`|`secure`
(auth/sudo/sshd), `kern.log`, `dpkg.log`/`yum.log`, `dmesg` (kernel ring buffer, not a file), and
per-app logs under `/var/log/<app>/`.

**Answer the incident properly:** correlate across sources — app logs, the unit's journal, kernel
(`journalctl -k`: OOM, I/O errors, TCP resets), auth log (was there a deploy/login at 3 AM?),
package log (did an auto-update run?), and metrics (what did the dashboards show at 03:00?).
Then produce a timeline. That's the difference between "I looked at the logs" and a senior answer.

**Follow-ups:**
```bash
# journald sizing and persistence — the defaults surprise people
grep -E '^#?(Storage|SystemMaxUse|MaxRetentionSec)' /etc/systemd/journald.conf
sudo journalctl --disk-usage
# Storage=auto + no /var/log/journal dir = volatile logs, lost on reboot
sudo mkdir -p /var/log/journal && sudo systemd-tmpfiles --create --prefix /var/log/journal
sudo systemctl restart systemd-journald
sudo journalctl --vacuum-time=30d --vacuum-size=2G     # manual trimming
```
Forwarding: `ForwardToSyslog=yes`, or better ship with promtail/vector/fluent-bit to Loki/ES.
Rate limiting: `RateLimitIntervalSec`/`RateLimitBurst` — a log storm can silently drop messages,
and `journalctl` will tell you "Suppressed N messages".

---

### Q32. Design log rotation for a chatty app writing 20 GB/day.

```text
# /etc/logrotate.d/myapp
/var/log/myapp/*.log {
    daily
    rotate 14                 # keep 14 generations
    maxsize 1G                # also rotate early if it grows past 1G within the day
    compress                  # gzip old logs
    delaycompress             # compress on the NEXT rotation (the app may still hold the fd)
    missingok                 # don't fail if the file vanished
    notifempty                # don't rotate an empty file
    copytruncate              # copy then truncate: for apps that can't reopen their log fd
    # OR, preferred:
    create 0640 myapp adm     # new file with these permissions/owner
    postrotate
        systemctl kill -s HUP myapp >/dev/null 2>&1 || true   # tell the app to reopen logs
    endscript
}
```
```bash
sudo logrotate -d /etc/logrotate.d/myapp     # dry run — always do this first
sudo logrotate -f /etc/logrotate.d/myapp     # force a rotation now
sudo logrotate -v /etc/logrotate.d/myapp     # verbose, to debug
cat /var/lib/logrotate/status                # when each file was last rotated
systemctl list-timers | grep logrotate       # it runs as a timer on modern systems, not cron
```
**Key discussion points:** `copytruncate` loses data written between copy and truncate and breaks
apps that track offsets — prefer `create` + a reload signal, or have the app log to stdout and let
journald/the container runtime handle it. In containers, the runtime handles rotation:
Docker `log-opts: {max-size: "50m", max-file: "3"}`, Kubernetes `containerLogMaxSize`/`containerLogMaxFiles`.
Compression choice: `compresscmd /usr/bin/zstd` is much faster than gzip.

---

## Topic 9 — Shell scripting & automation (SDE-flavoured)

### Q33. Write a script that restarts a service only if its health check fails, safely and idempotently.

```bash
#!/usr/bin/env bash
# healthcheck-restart.sh — restart myapp only when unhealthy, at most once per window.
set -Eeuo pipefail                     # E: ERR trap inherits; e: exit on error; u: unset var = error
IFS=$'\n\t'                            # predictable word splitting

readonly URL="${URL:-http://127.0.0.1:8080/healthz}"
readonly SVC="${SVC:-myapp}"
readonly LOCK="/run/lock/healthcheck-${SVC}.lock"
readonly COOLDOWN=300                  # seconds between restarts
readonly LOGTAG="healthcheck[$SVC]"

log()  { logger -t "$LOGTAG" -- "$*"; echo "$(date -Is) $*" >&2; }   # syslog AND stderr
die()  { log "FATAL: $*"; exit 1; }

cleanup() { local rc=$?; [ "$rc" -ne 0 ] && log "exited with rc=$rc at line $LINENO"; }
trap cleanup EXIT
trap 'log "interrupted"; exit 130' INT TERM

# single-instance guarantee (cron/systemd-timer safe)
exec 9>"$LOCK"
flock -n 9 || { log "another check is running; skipping"; exit 0; }

# rate limit restarts
if [ -f "$LOCK.last" ] && [ $(( $(date +%s) - $(stat -c %Y "$LOCK.last") )) -lt $COOLDOWN ]; then
    log "in cooldown; not restarting"; exit 0
fi

if curl -fsS --max-time 5 --retry 2 --retry-delay 2 "$URL" >/dev/null; then
    exit 0                             # healthy: exit quietly (no log spam)
fi

log "health check FAILED for $URL"
systemctl is-active --quiet "$SVC" || log "unit already inactive"
sudo systemctl restart "$SVC" || die "restart failed"
touch "$LOCK.last"
sleep 5
curl -fsS --max-time 5 "$URL" >/dev/null && log "recovered after restart" \
    || log "STILL UNHEALTHY after restart — escalating"
```
**What they're looking for:** `set -Eeuo pipefail` · quoting everywhere · `readonly` config from env ·
`flock` for mutual exclusion · cooldown to avoid restart storms · `curl -f` (fail on HTTP errors) and
`--max-time` (never hang) · logging to syslog with a tag · traps for cleanup/signals · idempotency ·
non-zero exit on failure so the scheduler can alert.

**Follow-ups:** Why `exec 9>file` + `flock -n 9` instead of `flock -n file cmd`? → the fd form holds
the lock for the whole script lifetime. Why not use `curl | grep OK`? → `curl` exits 0 on HTTP 500
unless `-f` is given. How do you test it? → `bats-core` unit tests plus a mock HTTP server; shellcheck
in CI. How would you do this in production properly? → don't: use the platform (Kubernetes liveness
probes with `failureThreshold`, systemd `Restart=on-failure` + `WatchdogSec=`, or Prometheus alerts
with a runbook), because a shell script restarting services is a monitoring anti-pattern that hides
root causes.

---

### Q34. Explain the bugs in this script. (They will hand you bad code.)

```bash
#!/bin/sh
cd /var/log
FILES=`ls *.log`
for f in $FILES; do
  if [ $f = "app.log" ]; then
    rm $f
  fi
done
echo "done" >> $LOG
```
**Bugs:**
1. `#!/bin/sh` but the author may assume bash features → use `#!/usr/bin/env bash` and `set -euo pipefail`.
2. **Parsing `ls`** — breaks on spaces/newlines in filenames, and `ls` output is locale-dependent. Use a glob.
3. Backticks are legacy; `$( )` nests properly.
4. Unquoted `$f` and `$LOG` → word splitting and globbing.
5. `[ $f = ... ]` errors out if `$f` is empty; always quote: `[ "$f" = ... ]`, or use `[[ ]]`.
6. `cd /var/log` unchecked — if it fails, `rm *.log` runs in the *original* directory. Use
   `cd /var/log || exit 1`, and prefer absolute paths with `--`.
7. `rm $f` with no `--` → a file named `-rf` becomes a flag. Use `rm -- "$f"`.
8. `$LOG` is never set → with `set -u` it fails loudly; without it, `>> ` to an empty filename errors.
9. No error handling, no logging of failures, no `set -e`, no trap.
10. Deleting the active log of a running service → space isn't freed (see Q3); use logrotate.

**Corrected:**
```bash
#!/usr/bin/env bash
set -Eeuo pipefail
readonly LOGDIR=/var/log
readonly DONE_LOG="${LOGFILE:-/var/log/cleanup.log}"
for f in "$LOGDIR"/*.log; do
    [ -e "$f" ] || continue                       # no match → the glob stays literal
    [ "$(basename -- "$f")" = "app.log" ] && rm -f -- "$f"
done
printf 'done at %s\n' "$(date -Is)" >> "$DONE_LOG"
```
**Senior signal:** you run `shellcheck` and say so; you mention that "the real answer is a config
management tool (Ansible `find`+`file` module, or logrotate) — a hand-rolled cleanup script is
unowned code."

---

### Q35. How do you run a command on 500 servers? Compare the options.

| Approach | Good for | Notes |
|---|---|---|
| `ansible -m shell -a ...` / playbook | config drift, idempotent changes, inventory at scale | agentless over SSH; **desired-state** model |
| `pdsh -w node[001-500] 'cmd'` | quick parallel one-liners | needs a node list, no state |
| `parallel-ssh` / `clush` | same as pdsh | |
| `for h in $(cat hosts); do ssh -o BatchMode=yes $h 'cmd' & done; wait` | ad-hoc, no tooling | unbounded parallelism can melt your laptop; add `-P` via xargs |
| Salt / Puppet / Chef | agent-based, very large fleets, fast fan-out | agents, PKI, more ops overhead |
| Configuration management + image bake | the *right* answer | immutable infrastructure: bake AMI/image, roll out |
| Kubernetes DaemonSet / operator | container fleets | declarative, self-healing |

```bash
# a sane ad-hoc version with bounded parallelism and per-host logs
xargs -a hosts.txt -P 20 -I{} sh -c \
  'ssh -o BatchMode=yes -o ConnectTimeout=5 {} "uptime" > results/{}.txt 2>&1 || echo FAIL: {} >> failures.txt'
ansible all -m shell -a 'df -h /' -f 50 --become | tee fleet-df.txt
ansible all -m ping -f 100                    # reachability across the fleet
ansible-playbook -i inventory/prod site.yml --check --diff   # dry run before applying
ansible-playbook -i inventory/prod site.yml --limit 'web*&!canary'   # targeting
```
**Follow-ups:** How do you make it safe? → idempotency, `--check --diff` dry run, canary/rolling
with `serial: 10%` and `max_fail_percentage`, version-controlled playbooks, and a change ticket.
How do you handle a partial failure? → collect results, report per-host status, never `set -e` your
way into silence; Ansible's `ignore_errors`/`failed_when` and retry logic.
What's SSH `ControlMaster`? → connection multiplexing (`ControlMaster auto`, `ControlPersist 60s`),
which removes per-command handshake cost — massive speedup for loops over many hosts.

---

### Q36. Bash vs Python for automation — when do you use which?

**Answer:** Bash for *glue* — process orchestration, filesystem plumbing, bootstrapping before a
runtime exists, systemd units, one-off ops. Python (or Go) when you need: data structures, JSON/YAML
parsing, real error handling, tests, libraries/APIs, anything over ~100 lines, or anything a
non-shell person must maintain.

**Red flags in bash that mean "switch to Python":** parsing JSON with `grep`/`awk`, nested quoting,
arithmetic on floats, associative-array gymnastics, needing unit tests, handling HTTP with retries
and auth, or multi-line strings full of `$`.

```bash
jq -r '.items[] | "\(.name) \(.status)"' resp.json      # if jq is available, bash+jq is often fine
python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["items"][0]["name"])' < resp.json
```
**Also mention:** `set -Eeuo pipefail` is non-negotiable in bash; bash arrays are 1-dimensional and
word-splitting is a footgun; `shellcheck` + `bats` in CI; and the modern alternatives
(`xonsh`, `elvish`, or writing the tool in Go and shipping a static binary).

---

## Topic 10 — Namespaces, cgroups & containers (the Linux underneath Kubernetes)

### Q37. What actually *is* a container? Explain with Linux primitives.

**Answer:** A container is an ordinary process with three things applied:
1. **Namespaces** isolate what it can *see*: `mnt` (filesystem tree), `pid` (process IDs — it gets
   PID 1), `net` (interfaces, routing table, iptables, ports), `ipc`, `uts` (hostname), `user`
   (UID/GID mapping), `cgroup`, `time`.
2. **cgroups** limit what it can *use*: CPU, memory, I/O bandwidth, PIDs, and provide accounting.
3. **Security layers**: capabilities (drop `CAP_SYS_ADMIN` etc.), seccomp (syscall filter),
   LSMs (AppArmor/SELinux), rootless UID maps, and read-only mounts.
Plus **overlayfs** for the layered image (lowerdir=read-only image layers, upperdir=writable layer,
workdir), and `pivot_root`/`chroot` to switch the root filesystem.

```bash
sudo lsns                                    # list all namespaces on the host
sudo ls -l /proc/<pid>/ns/                   # the namespace inodes a process belongs to
sudo cat /proc/<pid>/cgroup                  # its cgroup paths
sudo nsenter -t <pid> -n -m -u -i -p ss -tulnp   # enter a container's namespaces to debug it
sudo nsenter -t <pid> -n ip a                # just the network namespace
sudo unshare --net --map-root-user bash      # create a fresh net namespace interactively
sudo cgexec / cat /sys/fs/cgroup/<path>/memory.max   # cgroup v2 limits
cat /sys/fs/cgroup/cpu.stat                  # nr_throttled, throttled_usec
```
**Follow-ups:** Why does `top` inside a container show host CPUs/memory? → `/proc` is not namespaced;
that's why JVM/Go/Node need cgroup-aware flags (`-XX:+UseContainerSupport`, `GOMAXPROCS` via
`automaxprocs`) and why naive thread pools over-provision and get throttled.
cgroup v1 vs v2? → v2 is a single unified hierarchy with all controllers; v1 had per-controller trees.
Check with `stat -fc %T /sys/fs/cgroup` (`cgroup2fs` = v2).
What is PID 1's special job? → reaping zombies and forwarding signals; that's why containers need
`tini`/`dumb-init` or `docker run --init`, otherwise `SIGTERM` may be ignored and the container is
SIGKILLed after the grace period.

---

### Q38. A pod/container is CPU-throttled but shows low CPU usage. Explain.

```bash
# on the node, for the container's cgroup:
cat /sys/fs/cgroup/.../cpu.max        # "200000 100000" = 2 CPUs of quota per 100ms period
cat /sys/fs/cgroup/.../cpu.stat       # nr_periods, nr_throttled, throttled_usec
kubectl top pod <pod>; kubectl describe pod <pod> | grep -A3 Limits
```
**Answer:** `cpu.max` grants quota per 100 ms period. A multi-threaded app can burn its whole 2-CPU
quota in 40 ms, then be frozen for the remaining 60 ms — average utilisation looks like 80% while
p99 latency explodes. This is the classic "low CPU but slow" container symptom.
**Fixes:** raise the CPU limit (or remove it and rely on requests/shares), reduce thread-pool sizes to
match the quota, make the runtime cgroup-aware, spread load across more replicas, and monitor
`container_cpu_cfs_throttled_periods_total / container_cpu_cfs_periods_total`.

**Senior signal:** you mention that CPU *requests* (shares) affect scheduling and relative weight
under contention, while *limits* (quota) cause hard throttling — and the well-known argument for
setting CPU requests but no CPU limits for latency-sensitive services, while always limiting memory
(because memory is not compressible → OOMKill).

---

### Q39. Debug "no space left on device" inside a container, but the node has 60% free disk.

```bash
kubectl describe node | grep -A6 Conditions        # DiskPressure? PIDPressure?
df -h; df -i                                        # node-level check
sudo du -xh --max-depth=1 /var/lib/containerd | sort -rh | head    # images and layers
sudo du -xh --max-depth=1 /var/lib/kubelet/pods | sort -rh | head  # emptyDir volumes!
sudo crictl images | wc -l; sudo crictl ps -a | wc -l
sudo journalctl -u kubelet --since "1 hour ago" | grep -iE "evict|diskpressure|garbage"
kubectl get events -A --field-selector reason=Evicted
cat /sys/fs/cgroup/.../pids.max; cat /sys/fs/cgroup/.../pids.current   # PID limit hit → same error text
```
**Answer:** the error is often not disk at all:
- **inode exhaustion** on the node (`df -i`)
- **emptyDir / ephemeral-storage limit** exceeded → pod evicted
- **PID cgroup limit** (`pids.max`) → `fork: retry: Resource temporarily unavailable` / "no space left"
- **conntrack table full** (`nf_conntrack: table full`) → also surfaces as a bizarre syscall error
- **overlayfs exhaustion** or too many image layers (125-layer limit on ext4-backed overlay2)
- kubelet GC not keeping up: check `imageGCHighThresholdPercent` and `evictionHard`

---

## Topic 11 — Kernel, boot & deep internals

### Q40. Walk me through the Linux boot sequence. Then: the machine hangs at boot — how do you recover?

**Boot sequence:** firmware (BIOS/UEFI) → POST → bootloader (GRUB2, from the ESP) → kernel +
initramfs (early userspace with the storage/network drivers needed to mount the real root) →
`switch_root` to the real root → PID 1 (`systemd`) → targets: `sysinit` → `basic` →
`multi-user.target`/`graphical.target`, with units ordered by `After=`/`Requires=`/`Wants=`.

```bash
systemd-analyze                             # total boot time and the userspace breakdown
systemd-analyze blame | head -20            # slowest units
systemd-analyze critical-chain              # the critical path
systemd-analyze plot > boot.svg             # visual timeline
systemd-analyze verify /etc/systemd/system/*.service
lsinitramfs /boot/initrd.img-$(uname -r) | head    # what's inside the initramfs (Debian/Ubuntu)
sudo dracut -f                              # regenerate initramfs (RHEL family)
```
**Recovery paths:**
```bash
# 1. boot into rescue/emergency from GRUB: press 'e', append to the linux line:
systemd.unit=rescue.target        # minimal, root FS mounted
systemd.unit=emergency.target     # even more minimal, root mounted read-only
init=/bin/bash                    # last resort: raw shell as PID 1
# then, inside:
mount -o remount,rw /             # emergency gives you a read-only root
systemctl list-jobs               # what is blocking?
systemctl status local-fs.target  # a failing fstab entry is the #1 cause
# fix /etc/fstab (add nofail), then:
systemctl daemon-reload; systemctl default
```
**Top causes of boot hangs:** bad `/etc/fstab` entry (fix: `nofail`, correct UUID), missing network
storage without `_netdev`, a failing `After=` dependency, full `/boot` preventing kernel updates,
broken initramfs after a driver change, disk failing SMART, or an fsck running on a huge volume
(`tune2fs -c/-i` controls mount-count/time-based checks).

---

### Q41. Which sysctls would you tune on a high-traffic web server, and why?

```bash
sysctl -a 2>/dev/null | grep -E 'somaxconn|tcp_max_syn_backlog|file-max|nf_conntrack_max'
sudo sysctl -w net.core.somaxconn=4096                    # accept-queue length (listen backlog cap)
sudo sysctl -w net.ipv4.tcp_max_syn_backlog=8192          # half-open (SYN) queue
sudo sysctl -w net.ipv4.tcp_fin_timeout=15                # FIN_WAIT2 timeout
sudo sysctl -w net.ipv4.ip_local_port_range="1024 65535"  # ephemeral ports for outbound conns
sudo sysctl -w net.ipv4.tcp_tw_reuse=1                    # reuse TIME_WAIT for OUTBOUND only (safe-ish)
sudo sysctl -w net.netfilter.nf_conntrack_max=1048576     # conntrack table (if NAT/iptables is used)
sudo sysctl -w fs.file-max=2097152                        # system-wide open files
sudo sysctl -w vm.swappiness=10                           # prefer reclaiming page cache over swapping
sudo sysctl -w vm.overcommit_memory=1                     # needed by Redis (fork for RDB/BGSAVE)
sudo sysctl -w vm.dirty_background_ratio=5 -w vm.dirty_ratio=20   # writeback pressure
sudo sysctl -w kernel.pid_max=4194304                     # more PIDs for dense container hosts
```
```bash
# persistence and the per-process half of the story
echo 'net.core.somaxconn=4096' | sudo tee -d /etc/sysctl.d/99-tuning.conf && sudo sysctl --system
ulimit -n                                   # per-process fd limit — must ALSO be raised
# systemd services: LimitNOFILE=1048576 in the unit (ulimit does not apply to systemd services)
sudo systemctl show nginx -p LimitNOFILE
```
**The reasoning they want:** tune only against a measured bottleneck (`ss -lnt` Recv-Q overflow,
`netstat -s | grep -i listen`, conntrack drops in dmesg). Blind tuning is worse than none. And know
that `somaxconn` caps the app's `listen(backlog)`, so both must be raised together.

---

### Q42. `strace` shows thousands of `stat()` calls on a missing file. What's happening?

**Answer:** classic library/locale/NSS search-path behaviour: e.g. glibc searching every
`LD_LIBRARY_PATH` entry, locale archive lookups, `nsswitch` probing modules, or an app polling a
config file. Also common: `ENOENT` storms from a Python import path, or `inotify` fallback polling.

```bash
sudo strace -c -f -p <pid>                  # syscall histogram: which call, how many, total time
sudo strace -f -e trace=file -p <pid> 2>&1 | grep ENOENT | head   # which paths are missing
sudo ltrace -p <pid>                        # library-level calls
sudo perf trace -p <pid> -s                 # lower-overhead syscall summary
sudo bpftrace -e 'tracepoint:raw_syscalls:sys_enter /pid == PID/ { @[comm] = count(); }'
ls -l /proc/<pid>/fd | wc -l                # fd count (leak check) vs /proc/<pid>/limits
sudo lsof -p <pid> | awk '{print $5}' | sort | uniq -c | sort -rn   # fd types: REG/IPv4/unix
```
**Follow-ups:** How do you find an fd leak? → monitor `/proc/<pid>/limits` "Max open files" vs
`ls /proc/<pid>/fd | wc -l`; `EMFILE` = per-process limit, `ENFILE` = system-wide.
Why is `strace` unsafe in prod? → ptrace serialises syscalls; 10–100× slowdown. Use `perf`, eBPF, or
`strace -c` briefly.

---

## Topic 12 — Real-time incident scenarios (the "war stories" round)

> Format for these: **symptom → hypothesis → verification command → fix → prevention.** Always say
> what you'd alert on afterwards. Interviewers score the loop, not the trivia.

### Q43. 3 AM page: website returns 502s. Nginx is up, the app is not responding.

```bash
# 1. Scope: is it everything or one instance?
kubectl get pods -o wide; curl -sS -o /dev/null -w '%{http_code}\n' http://each-instance/healthz
sudo tail -50 /var/log/nginx/error.log          # "connect() failed (111: Connection refused) while connecting to upstream"
# 2. Is the app listening?
sudo ss -ltnp | grep 8080                       # nothing → the process died or is still booting
sudo systemctl status myapp; sudo journalctl -u myapp -n 100 --no-pager
# 3. Why did it die?
sudo dmesg -T | grep -iE "oom|killed process"   # OOM?
sudo journalctl -k -b | grep -i oom
# 4. Or is it alive but hung?
sudo jstack <pid> > /tmp/threads.txt            # JVM: deadlock/exhausted pool?
sudo py-spy dump --pid <pid>                    # Python: where is it stuck?
sudo gdb -p <pid> -batch -ex 'thread apply all bt'   # native
sudo lsof -p <pid> | wc -l                      # fd exhaustion?
sudo ss -tn state established '( sport = :8080 )' | wc -l   # connection pile-up?
# 5. Also check the unglamorous things
df -h; df -i                                    # full disk → app cannot write
free -h                                         # swap thrash
sudo systemctl list-units --failed              # did a dependency (DB, redis) fail?
sudo conntrack -S 2>/dev/null | head            # conntrack drops
date                                            # clock skew → TLS/auth failures
```
**Mitigate first, diagnose second** (senior judgement): roll back the last deploy
(`kubectl rollout undo` / redeploy previous artefact), scale out, or fail over — *then* investigate
with the evidence you captured. Say explicitly: "I'd capture a thread dump, heap/`jmap` or py-spy
profile, and the logs **before** restarting, because a restart destroys the evidence."

**Prevention:** liveness vs readiness probes (readiness removes it from the LB; liveness restarts it),
`Restart=on-failure` with `StartLimitBurst`, deploy gating on health checks, canary/progressive
delivery, memory limits with headroom, and alerts on 5xx rate + upstream latency, not just "process down".

---

### Q44. Deployment worked yesterday; today every server reports "command not found" for your tool.

```bash
which mytool; type -a mytool                    # is it on PATH? shadowed by an alias/function?
echo $PATH                                      # did something overwrite PATH instead of appending?
ls -l /usr/local/bin/mytool                     # exists? executable? correct shebang?
head -1 /usr/local/bin/mytool | cat -A          # a CRLF shebang (#!/bin/bash^M) fails confusingly
file /usr/local/bin/mytool                      # wrong architecture? "ELF 64-bit ARM" on x86?
ldd /usr/local/bin/mytool                       # missing shared libraries
sudo ldd -r /usr/local/bin/mytool 2>&1 | grep -i "undefined"
grep -r "mytool" /etc/profile.d/ ~/.bashrc      # who set the PATH?
ansible all -m stat -a 'path=/usr/local/bin/mytool' | grep -E 'exists|mode'   # fleet-wide check
```
**Likely causes:** PATH set with `=` instead of `PATH="$PATH:..."`, a cron/systemd context without
the interactive shell's PATH, an unattended-upgrade removing the package, a broken symlink after a
version bump, image rebuild without the install step, or the tool was installed manually and never
codified.
**Senior signal:** the root cause is *"it was never in configuration management"* — the fix is a
package/repo, a baked image, or an Ansible role, plus a test that asserts `mytool --version` works.

---

### Q45. SSL certificate expired in production. Fix it now, then fix the process.

```bash
# assess the blast radius
echo | openssl s_client -connect host:443 -servername host 2>/dev/null | openssl x509 -noout -dates -subject -issuer -ext subjectAltName
for h in $(cat hosts.txt); do echo -n "$h "; echo | timeout 5 openssl s_client -connect $h:443 -servername $h 2>/dev/null | openssl x509 -noout -enddate; done
openssl x509 -in cert.pem -noout -checkend 0 && echo valid || echo EXPIRED
openssl verify -CAfile chain.pem cert.pem       # is the intermediate chain complete? (very common cause)
# remediate
sudo certbot renew --force-renewal -d host      # or install the new cert/key
sudo nginx -t && sudo systemctl reload nginx    # RELOAD, not restart (no dropped connections)
sudo systemctl reload haproxy
curl -vI https://host 2>&1 | grep -E 'expire date|issuer|subject'   # verify from outside
```
**Prevention (the real answer):** ACME automation (certbot/lego/acme.sh) with a DNS-01 challenge for
wildcards · a monitoring probe that checks expiry and alerts at 30/14/7 days
(`probe_ssl_earliest_cert_expiry` in blackbox_exporter) · cert-manager in Kubernetes · centralised
inventory of every certificate · documented reload procedure per service · and a check that the
*chain* is served, not just the leaf.

---

### Q46. Rapid-fire: name the first command you'd run for each symptom.

| Symptom | First command(s) |
|---|---|
| Server unreachable | `ping`, then console/IPMI/iLO; `ip -br a`, `ip r` from a neighbour; cloud: security groups, `systemctl status sshd`, `journalctl -u sshd`, `fail2ban-client status sshd` (you may be banned) |
| Extremely slow SSH login | `sshd -T | grep -i usedns` (UseDNS yes → reverse-DNS stalls), check `/etc/nsswitch.conf`, LDAP/SSSD timeout |
| 100% CPU | `top`/`pidstat -u 1`, then `perf top` |
| Disk full but `du` doesn't add up | `df -i`, `sudo lsof +L1` |
| Random reboots | `last -x reboot shutdown`, `journalctl -b -1 -e`, IPMI SEL / `ipmitool sel list`, `dmesg | grep -i mce` |
| Time drift / TLS errors | `timedatectl`, `chronyc tracking` / `ntpq -p` |
| DNS intermittent failures | `dig +tries=1 +time=2 @resolver`, `resolvectl statistics`, check `systemd-resolved` and the 5-second glibc timeout, conntrack race on UDP (the famous parallel A/AAAA NAT race) |
| Too many open files | `ulimit -n`, `cat /proc/<pid>/limits`, `ls /proc/<pid>/fd | wc -l`, systemd `LimitNOFILE` |
| Cron job not running | `grep CRON /var/log/syslog`, `systemctl status cron`, `crontab -l` **as the right user**, PATH in cron, `%` escaping, `flock` blocking |
| Kernel panic | `kdump`/`crash`, `journalctl -k -b -1`, `/var/crash`, serial console |
| NFS mount hangs everything | `mount | grep nfs`, D-state processes, `umount -f -l`, `nfsstat -c`, server-side `exportfs -v` |
| Package install fails | `sudo dpkg --configure -a`, `sudo apt --fix-broken install`, `df -h /var`, disk/inode space, `dpkg -l | grep ^..` states |
| Zombie processes | `ps -eo pid,ppid,stat,cmd | awk '$3 ~ /Z/'` → inspect/kill the PARENT |
| Network drops every ~5 min | `dmesg | grep -iE 'link|nic'`, STP/DHCP lease, `ethtool -S eth0 | grep -i err`, conntrack full, cloud LB idle timeout (350 s on ALB) |

---

## Topic 13 — SDE-3 / Senior-level design & judgement questions

### Q47. Design a patching strategy for 2,000 Linux servers with a 99.95% SLA.

**Structure your answer:** *inventory → risk ranking → rollout rings → automation → verification → rollback → metrics.*
- **Inventory & classification:** CMDB/service catalogue, OS version, criticality tier, customer-facing or not.
- **Rings:** dev → staging → canary (1–5% of prod, low-traffic region) → 10% → 25% → 50% → 100%,
  with soak time and automatic gates between rings.
- **Mechanism:** immutable is best (bake a new AMI/image, roll the fleet with ASG instance refresh /
  rolling replacement). Mutable fallback: Ansible with `serial: 10%`, `max_fail_percentage: 0`,
  pre/post health checks, drain-from-LB hooks.
- **Health gates:** app-level synthetic check + error rate + p99 latency, not just "the process is up".
- **Maintenance windows & SLA math:** 99.95% ≈ 21.9 min/month of allowed downtime — so zero-downtime
  rolling updates are mandatory; capacity headroom (N+1 per AZ) must exist to drain nodes.
- **Kernel/live patching:** `kpatch`/`livepatch`/`ksplice` for critical CVEs without reboots;
  otherwise schedule reboots with `needs-restarting -r` (RHEL) / `checkrestart` (Debian).
- **Exceptions:** long-lived stateful systems (databases, Kafka) get their own runbooks.
- **Metrics:** MTTR-to-patch, % fleet patched within 7/30 days, CVE exposure window, reboot success rate.
- **Rollback:** previous AMI id kept, blue/green or `kubectl rollout undo`, and a documented abort criteria.

### Q48. How would you eliminate SSH-based ops entirely? Why is that the goal?

**Answer:** SSH is unscalable, unauditable, and a lateral-movement vector. Move to:
declarative configuration management (Ansible/Terraform) in CI · immutable infrastructure with image
baking · a control plane (Kubernetes) with RBAC and admission control · short-lived certificates
instead of long-lived keys (SPIFFE/SPIRE, HashiCorp Vault SSH CA, AWS SSM Session Manager) ·
just-in-time access with approval and session recording (Teleport) · break-glass SSH as a documented,
alerted exception. Everything else follows: no humans on boxes ⇒ reproducible, auditable, and safe.

### Q49. "You have root on a machine you've never seen. Give me a 10-minute orientation."

```bash
hostnamectl; cat /etc/os-release; uname -r; uptime          # identity, OS, kernel, age
nproc; free -h; df -h; lsblk -f                             # capacity and storage
ip -br a; ip r; ss -tulnp                                   # network exposure and listeners
systemctl list-units --type=service --state=running         # what it actually does
systemctl list-units --failed; journalctl -p err -b | tail  # anything broken
ps aux --sort=-%mem | head; docker ps 2>/dev/null; crictl ps 2>/dev/null   # workloads
crontab -l; ls /etc/cron.d/; systemctl list-timers          # scheduled work
last -10; sudo grep -c "Accepted" /var/log/auth.log         # who uses it
sudo grep -v '^#' /etc/sudoers.d/* 2>/dev/null              # privileged access
ls -la /opt /srv /home /var/www 2>/dev/null                 # where the app lives
which ansible puppet chef salt 2>/dev/null; ls /etc/ansible 2>/dev/null   # is it managed?
```
Then you'd say: "my output is a one-page document — purpose, owner, dependencies, patch state,
monitoring coverage, and whether it's under config management. Unmanaged hosts are the risk."

### Q50. Behavioural questions senior panels always ask (and how to frame them)

Use **STAR-L**: Situation, Task, Action, Result, **Learning**. Quantify results (minutes of downtime,
% cost, MTTR). Have 6 stories ready:

1. **Hardest production incident you resolved** → focus on diagnosis method, mitigation vs root cause,
   and the blameless postmortem you drove.
2. **A time you broke production** → own it completely, describe the detection, the fix, and the
   systemic change (guardrail, test, rollout gate) that made it impossible to repeat. *Never blame others.*
3. **A disagreement with a senior/architect** → data over opinion, the experiment you ran, and how you
   committed to the decision even if it wasn't yours ("disagree and commit").
4. **Automating yourself out of a job** → the toil you measured, what you built, hours saved per week.
5. **Mentoring / raising the bar** → runbooks, game days, code review culture, onboarding time reduced.
6. **Saying no to a deadline** → the risk you quantified, the compromise you proposed, the outcome.

**Anti-patterns that fail senior panels:** trivia-dumping without structure, no metrics, blaming
"legacy" or other teams, no prevention story, and refusing to say "I don't know — here's how I'd find out."

---

## Answering technique — the loop interviewers grade

```text
1. RESTATE the symptom and its blast radius (who is affected, since when, what changed?)
2. HYPOTHESISE out loud: "most likely X, Y or Z — I'd check X first because it's cheapest to rule out"
3. VERIFY with a named command and say what output would confirm/deny the hypothesis
4. MITIGATE before root-causing when users are impacted (rollback, drain, scale, fail over)
5. FIX, then PREVENT: alert, runbook, automation, test, or design change
6. QUANTIFY: p99, MTTR, % error, cost, hours saved
```

**Phrases that signal seniority:** "what changed?" · "let me confirm before I act" ·
"mitigate first, preserve evidence, then root-cause" · "the alert should have caught this at 75%" ·
"the fix is systemic, not a script someone has to remember" · "I'd want a blameless postmortem with
action items and owners".

**Phrases that signal junior:** guessing a command without explaining why · `rm -rf` / `--force` as a
first move · rebooting before collecting evidence · tuning sysctls without a measurement ·
"I'd just give it more RAM" · no prevention story.

---

## Related files in this course

| Need | File |
|---|---|
| Command reference by topic | the pattern files in each `NN-*/` folder |
| Drill questions with answers | `NN-*/questions-basic.md`, `questions-advanced.md`, `questions-scenarios.md` |
| One-page revision before the interview | `CHEATSHEET.md` |
| Git interview questions | `../git/RTIQ.md` |
