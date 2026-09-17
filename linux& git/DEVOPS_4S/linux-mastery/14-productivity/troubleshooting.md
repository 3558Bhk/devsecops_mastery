# Pattern: Fixing the 10 errors every beginner meets

## 1. `command not found`

```bash
which mytool                            # is it installed and on your PATH?
echo $PATH                              # the folders the shell searches, separated by colons
sudo apt install mytool                 # install it (Debian/Ubuntu)
export PATH="$PATH:/opt/mytool/bin"     # or add the folder where it actually lives
```

## 2. `Permission denied`

```bash
ls -l thefile                           # look at the permission bits and the owner
chmod +x script.sh                      # missing execute permission on a script?
sudo command                            # genuinely needs admin rights?
sudo chown -R $USER:$USER ~/project     # root owns YOUR files? take them back
```

## 3. `No such file or directory` (but the file IS there)

```bash
ls -b weirdname                         # -b reveals hidden characters in the name
cat -A thefile                          # Windows line endings show as ^M$
sed -i 's/\r$//' script.sh              # fix CRLF → LF (the usual cause of "bad interpreter")
file script.sh                          # identify what kind of file it really is
```

## 4. Disk is full

```bash
df -h                                   # which filesystem is at 100%?
sudo du -h --max-depth=1 / | sort -rh | head    # which folder is biggest?
sudo journalctl --vacuum-size=200M      # shrink the logs
sudo apt clean && sudo apt autoremove -y    # clear package caches
```

## 5. A process won't die

```bash
ps aux | grep stuck                     # get the PID
kill 1234                               # polite first
kill -9 1234                            # then force
sudo lsof -p 1234                       # what files is it holding open?
```

## 6. A port is already in use

```bash
sudo ss -tulnp | grep :3000             # find the process listening on 3000
sudo kill <PID>                         # stop it, or run your app on another port
```

## 7. The internet doesn't work

```bash
ping -c 3 8.8.8.8                       # 1. can you reach an IP at all? (link/routing problem)
ping -c 3 google.com                    # 2. can you resolve a NAME? (if not → DNS problem)
cat /etc/resolv.conf                    # 3. check the DNS servers
ip a                                    # 4. do you even have an IP address?
```

## 8. A service won't start

```bash
systemctl status nginx                  # the exact error and last log lines
sudo journalctl -u nginx -n 50 --no-pager   # more of its log
sudo nginx -t                           # test the config syntax
```

## 9. A package install broke

```bash
sudo apt --fix-broken install           # repair dependencies
sudo dpkg --configure -a                # finish configuring half-installed packages
sudo apt clean && sudo apt update       # clear the cache, refresh the index
```

## 10. You did something and don't know what

```bash
history 20                              # your last 20 commands
echo $?                                 # exit code of the last command (0 = it succeeded)
sudo journalctl -b -p warning           # warnings since this boot
last -5                                 # recent logins and reboots
```

## The universal debugging loop

```text
1. Read the ENTIRE error message — the answer is usually in it.
2. Copy the exact error into a search engine (quote it).
3. man <command>  or  <command> --help
4. Check the logs: journalctl, /var/log
5. Change ONE thing, test, repeat.
```
