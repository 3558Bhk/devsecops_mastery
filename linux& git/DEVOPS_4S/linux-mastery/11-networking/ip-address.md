# Pattern: Addresses, interfaces, DNS

```bash
ip a                                  # show all network interfaces and their IP addresses
ip -br a                              # brief version: one line per interface (easiest to read)
ip addr show eth0                     # details for one interface only
ip r                                  # the routing table — how packets leave this machine
ip route get 8.8.8.8                  # which interface/gateway would be used for that destination
hostname -I                           # just my IP addresses, nothing else
hostname -f                           # my fully qualified domain name
cat /etc/resolv.conf                  # which DNS servers this machine uses
cat /etc/hosts                        # local hostname → IP overrides
getent hosts google.com               # resolve a name using the system resolver (hosts file + DNS)
dig example.com                       # detailed DNS lookup (needs dnsutils)
dig +short example.com                # just the IP address
nslookup example.com                  # simpler DNS query
host example.com                      # another simple resolver tool
ip link set eth0 down                 # disable an interface (admin only, temporary)
sudo ip link set eth0 up              # re-enable it
nmcli device status                   # NetworkManager view of connections (desktop systems)
```

## The two IPs you'll be asked for

```bash
ip -br a                              # PRIVATE IP (192.168.x.x / 10.x.x.x) — inside your network
curl -s ifconfig.me                   # PUBLIC IP — how the internet sees you
```

## Practice

Find your private IP with `hostname -I` and your public IP with `curl ifconfig.me`.
