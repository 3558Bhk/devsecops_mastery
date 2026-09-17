# 11 Networking — Basic Questions

**Q1.** What is my IP address?
```bash
ip -br a                 # brief view: one line per interface with its address
hostname -I              # just the IP addresses, nothing else
```

**Q2.** What is my public (internet-facing) IP?
```bash
curl -s ifconfig.me      # asks an external service what address it sees
```

**Q3.** Test whether a host is reachable.
```bash
ping -c 4 google.com     # -c sends exactly 4 packets and stops (otherwise it runs forever)
```

**Q4.** Which ports is my machine listening on?
```bash
ss -tuln                 # t=tcp, u=udp, l=listening, n=numeric (no name lookups = faster)
```

**Q5.** Find which program owns a port.
```bash
sudo ss -tulnp | grep :8080    # p shows the process (needs root for other users' processes)
sudo lsof -i :8080             # alternative view
```

**Q6.** Resolve a domain name to an IP.
```bash
dig +short example.com   # just the address
getent hosts example.com # uses the system resolver, so it honours /etc/hosts too
```

**Q7.** Which DNS servers does this machine use?
```bash
cat /etc/resolv.conf     # the "nameserver" lines
```

**Q8.** Add a local hostname mapping for testing.
```bash
echo "127.0.0.1 myapp.local" | sudo tee -a /etc/hosts   # append a line to the hosts file
```

**Q9.** Download a file.
```bash
wget https://example.com/file.zip        # saves with the remote name
curl -O https://example.com/file.zip     # -O = use the remote filename
curl -o mine.zip https://example.com/f   # -o = choose your own filename
```

**Q10.** Check just the HTTP status of a URL.
```bash
curl -I https://example.com    # -I fetches headers only
```

**Q11.** Log into a remote machine.
```bash
ssh alex@192.168.1.50          # user@host
ssh -p 2222 alex@example.com   # -p for a non-standard port
```

**Q12.** Copy a file to a remote machine.
```bash
scp file.txt alex@server:/home/alex/    # secure copy over SSH
```

**Q13.** Sync a folder to a server efficiently.
```bash
rsync -avz mydir/ alex@server:/backup/mydir/   # a=archive, v=verbose, z=compress
```

**Q14.** Show the route packets take to a host.
```bash
traceroute google.com    # every hop along the way
ip r                     # the local routing table
```
