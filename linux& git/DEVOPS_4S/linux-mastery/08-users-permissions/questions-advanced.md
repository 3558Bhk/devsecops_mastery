# 08 Users & Permissions — Advanced Questions

**Q1.** A directory has mode 700. What exactly can other users do?
```bash
ls -ld dir               # drwx------ → others cannot list it, enter it, or read anything inside
```
For a directory: `r` = list names, `w` = create/delete entries, `x` = enter and access files by name.

**Q2.** Convert `-rw-r-x--x` into its octal number.
```bash
stat -c "%a %A %n" file  # prints e.g. "651 -rw-r-x--x file"
```
rw- = 6, r-x = 5, --x = 1 → 651.

**Q3.** Make new files in a shared folder automatically belong to the team's group.
```bash
sudo chgrp devs shared/          # set the group
sudo chmod 2775 shared/          # the leading 2 = SETGID: new files inherit the folder's group
ls -ld shared/                   # shows drwxrwsr-x — the "s" marks setgid
```

**Q4.** What are the setuid, setgid and sticky bits?
```bash
ls -l /usr/bin/passwd    # -rwsr-xr-x → the "s" = setuid: runs with the owner's (root's) privileges
ls -ld /tmp              # drwxrwxrwt → the "t" = sticky bit: only the file's owner may delete it
chmod 4755 prog          # 4 = setuid, 2 = setgid, 1 = sticky
```

**Q5.** Allow a user to run only ONE command with sudo.
```bash
sudo visudo              # always edit sudoers through visudo — it validates syntax before saving
```
```text
alex ALL=(ALL) /usr/sbin/reboot        # alex may sudo-run only /usr/sbin/reboot
%devs ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart nginx   # a whole group, no password, one command
```

**Q6.** Check why access is denied, layer by layer.
```bash
namei -l /var/www/app/config.yml   # shows the permissions of EVERY directory along the path
```
You need `x` on every parent directory, not just on the target file.

**Q7.** Create a user's SSH setup correctly.
```bash
chmod 700 ~/.ssh                 # the directory must be private
chmod 600 ~/.ssh/id_ed25519      # the private key: owner read/write only
chmod 644 ~/.ssh/id_ed25519.pub  # the public key may be readable
chmod 600 ~/.ssh/authorized_keys # who may log in
```
SSH refuses to use a key whose permissions are too open.

**Q8.** Temporarily switch to another user to test their permissions.
```bash
sudo -u www-data bash        # open a shell AS that user (no password needed for root)
sudo su - alex               # full login shell for alex
```

**Q9.** Find world-writable files, which are a security risk.
```bash
find / -xdev -type f -perm -o+w 2>/dev/null    # files anyone can write
find / -xdev -perm -4000 -type f 2>/dev/null   # every setuid binary on the system
```

**Q10.** Give a user access to a folder without making it world-readable.
```bash
sudo groupadd webteam                       # 1. create a group
sudo usermod -aG webteam alex               # 2. add the user (they must log in again)
sudo chgrp -R webteam /srv/app              # 3. group-own the folder
sudo chmod -R g+rX /srv/app                 # 4. capital X adds execute to DIRECTORIES only
```

**Q11.** What does `umask` do?
```bash
umask                    # e.g. 022: new files get 644, new folders 755 (666/777 minus the mask)
umask 077                # stricter: new files 600, folders 700 — private by default
```

**Q12.** Lock and unlock an account.
```bash
sudo usermod -L alex     # lock (prefixes the password hash with !)
sudo usermod -U alex     # unlock
sudo passwd -S alex      # show the password/account status
```
