# Pattern: Mounting drives and USB sticks

"Mounting" = attaching a storage device to a folder so you can read it. The folder is called a mount point.

```bash
lsblk                                 # list all block devices (disks, partitions) as a tree
lsblk -f                              # also show filesystem type, UUID and mount point
df -h                                 # what is currently mounted
mount | column -t                     # pretty-print all active mounts
sudo mkdir -p /mnt/usb                # 1. create a mount point folder
sudo mount /dev/sdb1 /mnt/usb         # 2. attach partition sdb1 to that folder
ls /mnt/usb                           # 3. now the USB's files are visible here
sudo umount /mnt/usb                  # 4. detach it (spelled "umount", no "n")
sudo mount -o ro /dev/sdb1 /mnt/usb   # mount READ-ONLY (safe for recovery work)
sudo mount -t vfat /dev/sdb1 /mnt/usb # -t forces the filesystem type (vfat = typical USB stick)
sudo blkid                            # list UUIDs — the stable way to identify a partition
findmnt /home                         # details about one specific mount point
```

## Mount automatically at boot (`/etc/fstab`)

```bash
sudo cp /etc/fstab /etc/fstab.bak     # ALWAYS back up fstab first — a typo can stop the system booting
echo "UUID=1234-ABCD /mnt/usb vfat defaults 0 0" | sudo tee -a /etc/fstab   # add the entry
sudo mount -a                         # test it: mount everything in fstab now (errors show immediately)
```

## Unmount is busy?

```bash
sudo umount /mnt/usb                  # "target is busy" means some process is inside it
sudo lsof +D /mnt/usb                 # find which process holds files open there
cd /                                  # or simply leave that folder and try again
sudo umount -l /mnt/usb               # lazy unmount: detach now, clean up when free
```

## Practice

Run `lsblk -f` and identify which partition holds your `/` filesystem.
