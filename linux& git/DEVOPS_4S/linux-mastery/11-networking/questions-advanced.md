# 11 Networking — Advanced Questions

**Q1.** Set up passwordless SSH login.
```bash
ssh-keygen -t ed25519 -C "my laptop"   # create a key pair (Enter to accept the defaults)
ssh-copy-id alex@server                # upload your PUBLIC key to the server
ssh alex@server                        # now logs in with no password
```
Never share `~/.ssh/id_ed25519` (the private key). The `.pub` file is safe to distribute.

**Q2.** Simplify repeated SSH logins with a config file.
```bash
cat >> ~/.ssh/config <<'CONF'      # append a host block
Host web
    HostName 192.168.1.50          # the real address
    User alex
    IdentityFile ~/.ssh/id_ed25519 # which key to use
CONF
chmod 600 ~/.ssh/config            # SSH requires this file to be private
ssh web                            # now one short name is enough
```

**Q3.** Reach a service that only listens on a remote machine's localhost.
```bash
ssh -L 8080:localhost:80 server    # my localhost:8080 is forwarded to server's port 80
ssh -N -f -L 5432:localhost:5432 dbserver   # -N no shell, -f background: a pure tunnel
```

**Q4.** Expose a local dev server to a remote machine (reverse tunnel).
```bash
ssh -R 3000:localhost:3000 server  # server's port 3000 now forwards to MY machine's 3000
```

**Q5.** Diagnose DNS versus connectivity problems.
```bash
ping -c 3 8.8.8.8              # 1. if this fails → routing/link problem, not DNS
ping -c 3 google.com           # 2. if this fails but the above works → DNS problem
dig google.com @8.8.8.8        # 3. query a specific DNS server directly
cat /etc/resolv.conf           # 4. check which servers you are configured to use
```

**Q6.** Capture traffic to see what an app is really sending.
```bash
sudo tcpdump -i any -n port 443          # show packets on port 443, no name resolution
sudo tcpdump -i eth0 -w capture.pcap     # save to a file for Wireshark
sudo tcpdump -A -s 0 'tcp port 80'       # print packet payloads as ASCII (plain HTTP only)
```

**Q7.** Test whether a remote port is open without a browser.
```bash
nc -zv server 443              # z = don't send data, v = report the result
timeout 3 bash -c '</dev/tcp/server/443' && echo open   # pure-bash port check, no extra tools
curl -sS --connect-timeout 5 -o /dev/null -w "%{http_code}\n" http://server/   # HTTP-level test
```

**Q8.** Mirror a whole documentation site locally.
```bash
wget -r -np -k https://example.com/docs/   # -r recursive, -np no parent dirs, -k fix links for offline use
```

**Q9.** Resume a large interrupted download.
```bash
wget -c https://example.com/big.iso        # -c continues a partial file
curl -C - -O https://example.com/big.iso   # curl's equivalent
```

**Q10.** Find every established connection to your database.
```bash
ss -tnp state established '( dport = :5432 or sport = :5432 )'   # filter by state and port
sudo ss -tnp | grep :5432                                        # simpler grep version
```

**Q11.** Check bandwidth and interface errors.
```bash
ip -s link show eth0        # packet/byte counters plus errors and drops
sar -n DEV 1 5              # per-interface throughput samples (sysstat)
iftop -i eth0               # live per-connection bandwidth (if installed)
```

**Q12.** Harden SSH on a public server.
```bash
sudo nano /etc/ssh/sshd_config
```
```text
PermitRootLogin no               # never allow direct root login
PasswordAuthentication no        # keys only, after ssh-copy-id works
Port 2222                        # optional: reduces log noise from bots
AllowUsers alex                  # optional: whitelist of users
```
```bash
sudo sshd -t                     # validate the config BEFORE restarting
sudo systemctl restart ssh       # apply it (keep your current session open as a fallback!)
```
