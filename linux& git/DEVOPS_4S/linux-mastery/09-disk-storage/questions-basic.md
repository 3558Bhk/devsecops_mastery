# 09 Disk & Storage — Basic Questions

**Q1.** How much free space is left on each filesystem?
```bash
df -h                    # -h = human-readable sizes (G, M, K)
```

**Q2.** Check free space for one specific folder.
```bash
df -h /home              # reports the filesystem that CONTAINS /home
```

**Q3.** How big is one folder in total?
```bash
du -sh mydir/            # -s = summary only, -h = human sizes
```

**Q4.** Show the size of each subfolder, biggest first.
```bash
du -sh * | sort -rh      # sort -rh understands human sizes like 1.2G
```

**Q5.** List all disks and partitions.
```bash
lsblk                    # a tree of block devices
lsblk -f                 # adds filesystem type, UUID and mount point
```

**Q6.** What is currently mounted where?
```bash
mount | column -t        # all active mounts, aligned in columns
findmnt /home            # details for one mount point
```

**Q7.** Mount a USB stick.
```bash
lsblk -f                        # 1. find its device name, e.g. /dev/sdb1
sudo mkdir -p /mnt/usb          # 2. create a mount point folder
sudo mount /dev/sdb1 /mnt/usb   # 3. attach it there
```

**Q8.** Unmount that USB stick safely.
```bash
sudo umount /mnt/usb     # spelled "umount" — no "n"; always unmount before pulling it out
```

**Q9.** What does `df -i` show?
```bash
df -i                    # INODE usage — millions of tiny files can exhaust inodes with space left over
```

**Q10.** Find files larger than 500 MB.
```bash
find / -xdev -type f -size +500M 2>/dev/null   # -xdev stays on one filesystem
```

**Q11.** Clear the package manager's download cache.
```bash
sudo apt clean           # empties /var/cache/apt/archives
sudo apt autoremove -y   # removes packages nothing depends on any more
```

**Q12.** Shrink the systemd journal logs.
```bash
sudo journalctl --disk-usage         # how much space they take
sudo journalctl --vacuum-size=200M   # cap them at 200 MB
```

**Q13.** Which command gives an interactive disk-usage browser?
```bash
ncdu /                   # arrow-key navigation through folder sizes (install: apt install ncdu)
```
