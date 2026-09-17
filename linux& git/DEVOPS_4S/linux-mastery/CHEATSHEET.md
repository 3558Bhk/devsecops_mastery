# One-page Linux Cheatsheet

Print this. Every command below is explained in detail in its topic folder.

## Navigation
```bash
pwd                       # where am I
cd /path | cd .. | cd - | cd ~   # go to path / up / back / home
ls -lhA                   # list everything, human sizes
tree -L 2                 # visual folder diagram
```

## Files
```bash
mkdir -p a/b/c            # create nested folders
touch f.txt               # create an empty file
cp -r src/ dst/           # copy (folder needs -r)
mv old new                # rename / move
rm -i f | rm -rf dir/     # delete (carefully)
ln -s target link         # make a shortcut
```

## Read & search
```bash
cat f | less f            # print / page through
head -n 20 f | tail -f f  # first lines / live last lines
wc -l f                   # count lines
grep -rin "text" .        # recursive, case-insensitive, with line numbers
find . -name "*.log" -mtime +7   # old log files
```

## Text surgery
```bash
sort f | uniq -c | sort -rn      # frequency report
cut -d, -f2 data.csv             # column 2 of a CSV
awk '{print $1, $3}' f           # columns 1 and 3
sed -i.bak 's/old/new/g' f       # replace everywhere, with backup
tr 'a-z' 'A-Z' < f               # uppercase
```

## Combine
```bash
cmd1 | cmd2               # pipe: output of 1 becomes input of 2
cmd > out.txt             # overwrite file
cmd >> out.txt            # append to file
cmd > all.txt 2>&1        # output + errors together
cmd < in.txt              # read input from a file
cmd | tee out.txt         # show AND save
```

## Processes
```bash
ps aux | grep name        # find a process
top / htop                # live monitor
kill 1234 | kill -9 1234  # stop politely / forcefully
cmd &  jobs  fg %1  bg %1 # background job control
nohup cmd > log 2>&1 &    # survives logout
```

## Permissions & users
```bash
chmod +x script.sh        # make executable
chmod 755 dir | 644 file  # standard folder / file permissions
sudo chown -R $USER:$USER dir    # take back ownership
id | whoami | groups      # who am I
sudo !!                   # repeat last command as root
```

## Disk
```bash
df -h                     # free space per filesystem
du -sh * | sort -rh | head        # biggest items here
lsblk -f                  # disks and partitions
sudo mount /dev/sdb1 /mnt/usb     # attach a drive
```

## System
```bash
uname -a                  # kernel info
cat /etc/os-release       # distro and version
free -h | uptime          # memory | load and uptime
sudo journalctl -u nginx -f       # live service logs
sudo systemctl status nginx       # is the service running?
```

## Network
```bash
ip -br a                  # my IP addresses
ss -tulnp                 # listening ports and their processes
ping -c 3 host            # reachability
curl -I url               # HTTP headers only
wget -c url               # download (resumable)
rsync -avz src/ user@host:/dst/   # sync to a server
ssh user@host             # remote terminal
```

## Archives
```bash
tar -czvf a.tar.gz dir/   # create compressed archive
tar -xzvf a.tar.gz        # extract
tar -tzvf a.tar.gz        # list contents
zip -r a.zip dir/ ; unzip a.zip   # zip and unzip
gzip -k f ; zcat f.gz     # compress one file, keeping the original
```

## Speed
```bash
Tab / Tab Tab             # complete / show options
Ctrl+R                    # search history
Ctrl+C / Ctrl+D / Ctrl+L  # cancel / exit-input / clear screen
Alt+.                     # last argument of the previous command
!! / !$                   # last command / last argument
alias ll='ls -lhA'        # your own shortcut
man cmd | cmd --help      # documentation
```
