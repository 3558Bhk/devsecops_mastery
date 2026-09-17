# 08 Users & Permissions — Basic Questions

**Q1.** Read this permission string: `-rwxr-xr--`.
```bash
ls -l script.sh          # - = regular file | rwx = owner | r-x = group | r-- = others
```

**Q2.** What do the numeric permissions 755 and 644 mean?
```bash
chmod 755 dir            # 7=rwx 5=r-x 5=r-x → owner full, everyone else read+enter
chmod 644 file           # 6=rw- 4=r-- 4=r-- → owner reads/writes, everyone else reads only
```

**Q3.** Make a script runnable.
```bash
chmod +x script.sh       # adds execute permission
./script.sh              # now it can be run directly
```

**Q4.** Give read and write to the owner only (like an SSH private key).
```bash
chmod 600 ~/.ssh/id_rsa  # 6=rw- then 0 and 0 = nothing for group and others
```

**Q5.** Change the owner of a file.
```bash
sudo chown alex file.txt # chown usually needs sudo — only root can give files away
```

**Q6.** Change owner and group together.
```bash
sudo chown alex:devs file.txt   # user:group in one step
```

**Q7.** Change only the group.
```bash
sudo chgrp devs file.txt
```

**Q8.** Apply permissions to a folder and everything inside it.
```bash
chmod -R 755 mydir/      # -R = recursive
sudo chown -R $USER:$USER mydir/   # fix ownership of a whole tree
```

**Q9.** Run one command as the administrator.
```bash
sudo apt update          # sudo = run THIS command as root, then drop back to normal
```

**Q10.** Find out who you are and which groups you belong to.
```bash
whoami                   # your username
id                       # your uid, gid and all group memberships
groups                   # just the group names
```

**Q11.** Add a user to an extra group without removing their existing groups.
```bash
sudo usermod -aG devs alex   # -a APPEND; without it, the group list is REPLACED
```

**Q12.** Create a new user with a home folder.
```bash
sudo useradd -m -s /bin/bash alex   # -m makes /home/alex, -s sets the login shell
sudo passwd alex                     # then set the password
```

**Q13.** Symbolic form: give the group write access, remove read from others.
```bash
chmod g+w file           # u=owner, g=group, o=others, a=all; + adds, - removes
chmod o-r file
```

**Q14.** List all user accounts on the system.
```bash
getent passwd            # every account known to the system
cat /etc/passwd          # the raw file (fields separated by colons)
```
