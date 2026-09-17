# 09 Disk & Storage — Scenario Questions

## Scenario 1 — "No space left on device"
```bash
df -h                                        # 1. WHICH filesystem is at 100%?
df -i                                        # 2. also check inodes — they can run out too
sudo du -h --max-depth=1 / 2>/dev/null | sort -rh | head    # 3. biggest top-level folders
sudo du -h --max-depth=1 /var 2>/dev/null | sort -rh | head # 4. drill into the usual suspect
sudo journalctl --vacuum-size=200M           # 5. shrink logs
sudo apt clean && sudo apt autoremove -y     # 6. clear package caches
find / -xdev -type f -size +500M 2>/dev/null # 7. locate individual giant files
```

## Scenario 2
A user plugged in a USB drive and it does not appear in their file manager.
```bash
lsblk -f                                     # does the kernel see the device at all?
sudo dmesg | tail -20                        # look for the plug-in event and any filesystem errors
sudo mkdir -p /mnt/usb && sudo mount /dev/sdb1 /mnt/usb   # mount it manually
sudo mount -t exfat /dev/sdb1 /mnt/usb       # if it complains about the type, specify it
```

## Scenario 3
The disk shows 90% full but the total of all folders is much smaller.
```bash
sudo lsof +L1                                # deleted-but-still-open files hold space hostage
sudo systemctl restart rsyslog               # restarting the writer releases it
```
This is extremely common with log files that were deleted while a process kept writing to them.

## Scenario 4
You must add a new 100 GB disk to a production server and mount it permanently at `/data`.
```bash
lsblk                                        # 1. identify it (probably /dev/sdb)
sudo parted /dev/sdb mklabel gpt             # 2. partition table
sudo parted /dev/sdb mkpart primary ext4 0% 100%   # 3. one full-size partition
sudo mkfs.ext4 -L data /dev/sdb1             # 4. format (destroys anything already there)
sudo blkid /dev/sdb1                         # 5. get its UUID
sudo mkdir -p /data                          # 6. mount point
sudo cp /etc/fstab /etc/fstab.bak            # 7. back up fstab
echo "UUID=<paste-uuid> /data ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab   # 8. add the entry
sudo mount -a && findmnt /data               # 9. test it now — do NOT just reboot and hope
```

## Scenario 5
Docker is consuming 60 GB and you need space back fast.
```bash
docker system df                             # breakdown: images, containers, volumes, build cache
docker system prune -a                       # remove unused images/containers/networks (⚠️ check first)
docker system prune -a --volumes             # also unused volumes — THIS DELETES DATA
sudo du -sh /var/lib/docker/*                # see which part of Docker's directory is biggest
```

## Scenario 6
One user keeps filling a shared disk. Give everyone else room and set limits.
```bash
sudo du -sh /shared/* | sort -rh | head      # who is using what
sudo apt install quota && sudo edquota -u bob   # set a hard limit for that user
sudo repquota -a                             # verify the limits are in effect
find /shared -mtime +60 -type f | head       # candidate old files to archive
```

## Scenario 7
The system is slow and you suspect the disk, not the CPU.
```bash
iostat -x 1 3                                # look at %util and await (ms per request)
iotop -oP                                    # which process is generating the I/O
vmstat 1 5                                   # high "wa" column = time spent waiting on I/O
sudo smartctl -H /dev/sda                    # is the disk itself failing?
```

## Scenario 8
Back up a 50 GB folder to an external drive with minimal downtime.
```bash
rsync -av --progress /data/ /mnt/backup/data/    # first pass: copies everything
rsync -av --delete /data/ /mnt/backup/data/      # later passes: only the changes (fast)
sha256sum /mnt/backup/data/bigfile > /tmp/sum && sha256sum -c /tmp/sum   # verify integrity
```
