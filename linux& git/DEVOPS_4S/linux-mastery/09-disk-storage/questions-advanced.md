# 09 Disk & Storage — Advanced Questions

**Q1.** `df` says the disk is full but `du` cannot account for the space. Why?
```bash
sudo lsof +L1                       # lists DELETED files still held open by a process
sudo lsof | grep -i deleted         # the space is freed only when that process closes them
sudo systemctl restart theservice   # or reboot to release it
```

**Q2.** Identify a partition reliably, even if device names change.
```bash
sudo blkid                          # shows UUID and TYPE for every partition
ls -l /dev/disk/by-uuid/            # the same UUIDs as symlinks
```
Use `UUID=...` in `/etc/fstab` — `/dev/sdb1` can become `/dev/sdc1` after a reboot.

**Q3.** Add a permanent mount to `/etc/fstab` without breaking boot.
```bash
sudo cp /etc/fstab /etc/fstab.bak   # ALWAYS back it up first — a typo can stop the system booting
echo "UUID=1234-ABCD /mnt/data ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
sudo mount -a                       # test immediately: errors appear now, not at next boot
findmnt /mnt/data                   # confirm it is mounted
```
`nofail` lets the system boot even if that disk is missing.

**Q4.** Resize a filesystem after growing its partition.
```bash
lsblk                                        # check the new partition size
sudo growpart /dev/sda 2                     # extend partition 2 into free space
sudo resize2fs /dev/sda2                     # ext4: grow the filesystem online
sudo xfs_growfs /                            # xfs: grow the mounted filesystem
df -h                                        # verify
```

**Q5.** Monitor disk I/O and find the process hammering the disk.
```bash
iostat -x 1 3                                # per-device stats: %util near 100 = saturated
iotop -oP                                    # live view of which processes are doing I/O (-o = only active)
pidstat -d 1                                 # per-process I/O sampling (sysstat package)
```

**Q6.** Check a filesystem's health.
```bash
sudo smartctl -a /dev/sda                    # SMART data: reallocated sectors, temperature, health
sudo fsck -n /dev/sda2                       # -n = check only, never write (run on unmounted filesystems)
sudo dmesg | grep -i -E "i/o error|ext4|xfs" # kernel complaints about the disk
```

**Q7.** Create and format a new partition from scratch.
```bash
lsblk                                        # 1. identify the empty device, e.g. /dev/sdb
sudo parted /dev/sdb mklabel gpt             # 2. create a GPT partition table
sudo parted /dev/sdb mkpart primary ext4 0% 100%   # 3. one partition using the whole disk
sudo mkfs.ext4 -L data /dev/sdb1             # 4. format it (⚠️ destroys existing data)
sudo mkdir -p /mnt/data && sudo mount /dev/sdb1 /mnt/data   # 5. mount and use
```

**Q8.** Set up swap space on a machine with no swap.
```bash
sudo fallocate -l 2G /swapfile      # create a 2 GB file
sudo chmod 600 /swapfile            # swap files must be private
sudo mkswap /swapfile               # mark it as swap
sudo swapon /swapfile               # activate it now
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab   # activate at every boot
free -h                             # confirm swap appears
```

**Q9.** Use quotas to stop one user filling the disk.
```bash
sudo apt install quota                       # install the tools
sudo edquota -u alex                         # set soft and hard limits for user alex
sudo repquota -a                             # report everybody's usage
```

**Q10.** Find which folder grew overnight.
```bash
du -h --max-depth=2 / 2>/dev/null | sort -rh | head -20   # rank folders two levels deep
find / -xdev -type f -mtime -1 -size +100M -exec ls -lh {} +   # big files modified in the last day
```

**Q11.** What does the "available" column in `df -h` really mean?
```bash
df -h                        # ext filesystems reserve 5% for root, so Available < (Size - Used)
sudo tune2fs -l /dev/sda2 | grep -i "reserved block count"   # inspect the reserve
sudo tune2fs -m 1 /dev/sda2  # reduce the reserve to 1% to reclaim space on data disks
```
