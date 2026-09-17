# Pattern: Checking disk space (`df`, `du`)

`df` = disk FREE (per filesystem). `du` = disk USED (per folder).

```bash
df -h                                 # -h human-readable sizes for every mounted filesystem
df -h /home                           # space left on the filesystem containing /home
df -i                                 # show INODE usage (you can run out of inodes with tiny files)
df -h --total                         # add a total row at the bottom
du -sh mydir/                         # -s summary only, -h human size → total size of one folder
du -h --max-depth=1 .                 # size of each subfolder one level down
du -sh * | sort -rh | head -10        # TOP 10 biggest items here (sort -rh = reverse human sizes)
du -ah . | sort -rh | head -20        # include files (-a), not just folders
du -sh /var/log/*                     # which logs are eating the disk?
ncdu /                                # interactive disk browser (sudo apt install ncdu) — best tool
```

## "My disk is full" — the standard drill

```bash
df -h                                 # 1. which filesystem is at 100%?
du -h --max-depth=1 / | sort -rh      # 2. which top-level folder is biggest?
sudo du -sh /var/log/* | sort -rh     # 3. drill into the usual suspects (logs, caches)
sudo journalctl --vacuum-size=200M    # 4. shrink systemd logs to 200 MB
sudo apt clean                        # 5. clear the downloaded package cache
docker system prune -af               # 6. if you use Docker, this often reclaims gigabytes
find / -xdev -type f -size +500M 2>/dev/null   # 7. -xdev stays on one disk; list giant files
```

## Practice

Find your 5 largest home subfolders with `du -sh ~/* | sort -rh | head -5`.
