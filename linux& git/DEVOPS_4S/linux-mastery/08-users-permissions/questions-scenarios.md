# 08 Users & Permissions — Scenario Questions

## Scenario 1
`./deploy.sh` says "Permission denied" even though the file exists.
```bash
ls -l deploy.sh                # check for the x bit and who owns it
chmod +x deploy.sh             # add execute permission
./deploy.sh                    # try again
bash deploy.sh                 # workaround: run it through bash (no +x needed)
```

## Scenario 2
You extracted an archive as root and now cannot edit the files as your normal user.
```bash
ls -l extracted/ | head        # confirm the owner is root
sudo chown -R $USER:$USER extracted/   # take ownership back, recursively
```
Better habit: extract into your own home as your own user in the first place.

## Scenario 3
Three developers need to share `/srv/project`, and files they create must stay group-editable.
```bash
sudo groupadd devteam                     # 1. a shared group
sudo usermod -aG devteam alex bob carol   # 2. add all three (they must re-login)
sudo chgrp -R devteam /srv/project        # 3. group ownership
sudo chmod -R g+rwX /srv/project          # 4. group read/write; X = execute on directories only
sudo chmod g+s /srv/project               # 5. setgid so new files inherit the group
```

## Scenario 4
A junior admin needs to restart nginx but must not have full root.
```bash
sudo visudo -f /etc/sudoers.d/nginx       # a dedicated drop-in file (never edit /etc/sudoers by hand)
```
```text
junior ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart nginx
```
```bash
sudo -l -U junior                         # verify exactly what that user is now allowed to do
```

## Scenario 5
Your SSH key is rejected with "UNPROTECTED PRIVATE KEY FILE".
```bash
ls -l ~/.ssh/id_ed25519                   # probably 644 or worse
chmod 600 ~/.ssh/id_ed25519               # owner-only read/write
chmod 700 ~/.ssh                          # the directory too
ssh -v user@host                          # -v shows verbose debugging if it still fails
```

## Scenario 6
A web server (running as `www-data`) cannot read your uploaded files.
```bash
sudo -u www-data cat /var/www/uploads/a.txt   # reproduce the failure AS that user
namei -l /var/www/uploads/a.txt               # check x permission on every parent directory
sudo chown -R www-data:www-data /var/www/uploads   # fix ownership
sudo chmod 755 /var/www /var/www/uploads          # directories must be traversable
```

## Scenario 7
You suspect someone's account was used for an attack. Investigate and lock it.
```bash
sudo grep "alex" /var/log/auth.log | tail -30     # their login and sudo activity
last alex                                         # their login history
sudo usermod -L alex                              # lock the account immediately
sudo pkill -u alex                                # end any of their running processes
sudo passwd -S alex                               # confirm it now shows "L" (locked)
```

## Scenario 8
Audit the system for risky permissions before a security review.
```bash
find / -xdev -type f -perm 777 2>/dev/null              # world-writable files
find / -xdev -perm -4000 -type f 2>/dev/null            # setuid binaries
find /home -maxdepth 2 -name ".ssh" -type d ! -perm 700 # loose SSH directories
sudo grep -v '^#' /etc/sudoers /etc/sudoers.d/* 2>/dev/null | grep -v '^$'   # active sudo rules
```

## Scenario 9
A shared folder must be readable by everyone but writable by nobody except root.
```bash
sudo chmod 755 /opt/data          # rwx for owner, r-x for group and others
sudo chown root:root /opt/data    # owned by root
find /opt/data -type f -exec chmod 644 {} +   # files readable, not writable
find /opt/data -type d -exec chmod 755 {} +   # directories traversable
```

## Scenario 10
New files you create are readable by other users and you want them private by default.
```bash
umask                 # see the current mask, probably 022
umask 077             # now new files are 600 and new folders 700
echo 'umask 077' >> ~/.bashrc   # make it permanent for your account
```
