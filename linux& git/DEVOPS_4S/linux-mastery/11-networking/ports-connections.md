# Pattern: Ports, sockets, connectivity

```bash
ss -tulnp                             # THE command: t=tcp, u=udp, l=listening, n=numbers, p=which process
ss -tuln                              # listening ports without process names (no sudo needed)
ss -s                                 # socket summary: how many connections of each type
ss -tn state established              # only currently established TCP connections
ss -tnp | grep :443                   # who is talking on HTTPS port 443
sudo lsof -i :8080                    # which program owns port 8080
sudo lsof -i -P -n | grep LISTEN      # all listening sockets with PIDs (no name resolution)
sudo netstat -tulnp                   # older equivalent of ss (still common in tutorials)
ping -c 4 google.com                  # send 4 test packets: is the network reachable? latency?
ping -c 4 192.168.1.1                 # ping your router directly (tests the local link only)
traceroute google.com                 # every hop your packets take to get there
mtr google.com                        # ping + traceroute combined, live
nc -zv localhost 8080                 # z=don't send data, v=verbose → "is this port open?"
nc -l 9000                            # listen on port 9000 (a tiny test server)
echo "hi" | nc localhost 9000         # connect to it and send a line (from another terminal)
curl -I https://example.com           # fetch just the HTTP HEADERS (status code, server, etc.)
curl -s -o /dev/null -w "%{http_code}\n" https://example.com   # print only the HTTP status code
```

## "Port already in use" — fix it in 3 steps

```bash
sudo ss -tulnp | grep :3000           # 1. find the PID holding port 3000
ps -p 4242 -o pid,cmd                 # 2. confirm what that process actually is
sudo kill 4242                        # 3. stop it (or start your app on another port)
```

## Practice

List every port your machine is listening on right now.
