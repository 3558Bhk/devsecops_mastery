# Pattern: Remote control with SSH

SSH = an encrypted terminal on another machine. The single most important skill for servers.

```bash
ssh alex@192.168.1.50                   # log in as user alex on that IP
ssh -p 2222 alex@example.com            # -p connect on a non-standard port
ssh alex@server 'df -h'                 # run ONE remote command and come straight back
ssh alex@server 'uptime && free -h'     # run several, chained remotely
ssh-keygen -t ed25519 -C "my laptop"    # create your key pair (press Enter to accept defaults)
ssh-copy-id alex@192.168.1.50           # upload your PUBLIC key → passwordless login from now on
ssh alex@server                         # now this logs in with no password
cat ~/.ssh/id_ed25519.pub               # your PUBLIC key (safe to share)
cat ~/.ssh/id_ed25519                   # your PRIVATE key — NEVER share or upload this
chmod 600 ~/.ssh/id_ed25519             # required permissions or SSH refuses to use the key
ssh -L 8080:localhost:80 server         # tunnel: my localhost:8080 → server's port 80
ssh -N -f -L 5432:localhost:5432 db     # background (-f) tunnel with no shell (-N) to a database
scp notes.md alex@server:~/             # push a file (see download-transfer.md)
sshfs alex@server:/data /mnt/data       # mount a remote folder as a local one (needs sshfs)
exit                                    # log out of the remote shell
```

## Make SSH pleasant: `~/.ssh/config`

```bash
cat >> ~/.ssh/config <<'CONF'           # append a host definition to your SSH config file
Host web
    HostName 192.168.1.50               # the real address
    User alex                           # the user to log in as
    Port 22                             # the port
    IdentityFile ~/.ssh/id_ed25519      # which private key to use
CONF
chmod 600 ~/.ssh/config                 # SSH requires this file to be private too
ssh web                                 # now one short word replaces the whole command
```

## Inside an SSH session (escape keys)

```text
~.     disconnect immediately (type ~ then . at the start of a line)
~^Z    suspend the SSH session
Enter then ~?    list all escape commands
```

## Practice

Generate a key pair with `ssh-keygen -t ed25519` and look at the public key file.
