# 11 Networking — Scenario Questions

## Scenario 1
Your app cannot reach its database. Diagnose layer by layer.
```bash
ping -c 3 db.internal            # 1. is the host reachable at all?
getent hosts db.internal         # 2. does the name resolve? (if not → DNS or /etc/hosts)
nc -zv db.internal 5432          # 3. is the port open? (if not → firewall or the DB is down)
ip r                             # 4. which route/gateway would be used
sudo traceroute db.internal      # 5. where does the path stop
```

## Scenario 2
You cannot SSH into a server that was working yesterday.
```bash
ping -c 3 server                 # is it up and on the network?
nc -zv server 22                 # is the SSH port open?
ssh -vvv alex@server             # -vvv verbose: shows exactly where the handshake fails
ip -br a                         # is MY network even working?
curl -s ifconfig.me              # do I have internet at all?
```

## Scenario 3
Your web app on port 3000 will not start: "address already in use".
```bash
sudo ss -tulnp | grep :3000      # find the PID holding the port
ps -p <PID> -o pid,user,cmd      # confirm what it is (maybe your own earlier run)
sudo kill <PID>                  # stop it
PORT=3001 node app.js            # or just use a different port
```

## Scenario 4
You need to browse a remote server's internal admin panel that only listens on its localhost.
```bash
ssh -L 9000:localhost:9000 user@server   # forward your localhost:9000 to the server's 9000
# then open http://localhost:9000 in your own browser
```

## Scenario 5
Copy 20 GB of logs from a server to your laptop, over a flaky connection.
```bash
rsync -avz --progress --partial user@server:/var/log/myapp/ ~/logs/
# --partial keeps incomplete files so a retry resumes instead of restarting
rsync -avz --partial --append-verify user@server:/big/file ~/big/   # resume one huge file
```

## Scenario 6
The office network works but no domain name resolves.
```bash
cat /etc/resolv.conf                  # are the nameserver lines present and correct?
dig google.com @8.8.8.8               # test a known-good public resolver directly
ping -c 3 8.8.8.8                     # IP-level connectivity still fine?
sudo systemctl status systemd-resolved   # is the local resolver service running?
```
If `@8.8.8.8` works but normal resolution fails, your configured DNS server is the problem.

## Scenario 7
Deploy a new build to a server in one command.
```bash
tar -czf build.tar.gz dist/                       # package the build locally
scp build.tar.gz user@server:/tmp/                # upload it
ssh user@server 'cd /var/www && tar -xzf /tmp/build.tar.gz && systemctl reload nginx'   # unpack and reload
```

## Scenario 8
You suspect something on your machine is talking to an unknown server.
```bash
ss -tnp state established            # every outbound established connection with its process
sudo lsof -i -P -n | grep -v LISTEN  # all network activity, numeric
sudo tcpdump -i any -n -c 50         # sample 50 packets to see the traffic
ps aux | grep <suspicious_pid>       # identify the owning process
```

## Scenario 9
Check whether a website is down for everyone or just for you.
```bash
curl -I -sS --connect-timeout 5 https://example.com   # headers from your machine
dig +short example.com                                # does DNS resolve here?
ping -c 3 example.com                                 # is the host answering ICMP?
sudo traceroute example.com                           # where does the path die?
```
If DNS resolves and the connection times out at your gateway, the problem is local.

## Scenario 10
Set up a repeatable, key-based deployment identity for a CI job.
```bash
ssh-keygen -t ed25519 -f ~/.ssh/ci_deploy -N ""       # -N "" = no passphrase (needed for automation)
ssh-copy-id -i ~/.ssh/ci_deploy.pub deploy@server     # install the public key
ssh -i ~/.ssh/ci_deploy deploy@server 'hostname'      # test the login
printf 'Host ci\n HostName server\n User deploy\n IdentityFile ~/.ssh/ci_deploy\n' >> ~/.ssh/config
ssh ci 'hostname'                                     # now a one-word login
```
