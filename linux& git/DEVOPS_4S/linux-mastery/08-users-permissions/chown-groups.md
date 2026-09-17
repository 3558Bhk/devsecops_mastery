# Pattern: Ownership and groups

```bash
ls -l file.txt                        # columns 3 and 4 show the OWNER and the GROUP
sudo chown alex file.txt              # change the owner to user alex (needs sudo)
sudo chown alex:devs file.txt         # change owner AND group in one step
sudo chgrp devs file.txt              # change only the group
sudo chown -R alex:alex /var/www      # -R recursive: fix ownership of a whole folder tree
sudo chown -R www-data:www-data site/ # common web-server fix
id                                    # who am I? shows your uid, gid and ALL your groups
id alex                               # same info for another user
whoami                                # just your username
groups                                # just the group names you belong to
```

## Managing users and groups (admin tasks)

```bash
sudo useradd -m -s /bin/bash alex     # -m create the home folder, -s set the default shell
sudo userdel -r alex                  # -r also delete the home folder and mail spool
sudo passwd alex                      # set or change a user's password
sudo groupadd devs                    # create a group
sudo usermod -aG devs alex            # -aG APPEND to groups (-a is vital: without it, groups are replaced)
sudo usermod -L alex                  # lock an account
getent passwd                         # list all user accounts known to the system
getent group devs                     # show a group and its members
```

## Why this matters

```bash
sudo chown -R $USER:$USER ~/project   # fix "permission denied" after extracting files as root
```
`$USER` is a variable holding your own username — so this command always works for you.

## Practice

Run `id` and note your groups. Then create a file and check its owner with `ls -l`.
