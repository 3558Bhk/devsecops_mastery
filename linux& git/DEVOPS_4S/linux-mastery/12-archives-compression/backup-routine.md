# Pattern: A repeatable backup routine

```bash
DATE=$(date +%Y-%m-%d)                          # store today's date in a variable for filenames
tar -czvf ~/backups/home-$DATE.tar.gz ~/documents   # archive one folder with a dated name
rsync -av --delete ~/documents/ /mnt/backup/documents/   # mirror to an external drive (exact copy)
sha256sum ~/backups/home-$DATE.tar.gz > ~/backups/home-$DATE.sha256   # record a checksum
sha256sum -c ~/backups/home-$DATE.sha256        # later: verify the backup is still intact
ls -lh ~/backups/                               # confirm the size and date look right
tar -tzf ~/backups/home-$DATE.tar.gz | head     # sanity check: peek inside without extracting
```

## Rotating backups with `cron` (automatic, daily at 2 AM)

```bash
crontab -e                                      # open YOUR cron schedule in an editor
```
```text
# m h day month weekday  command
0 2 * * * /home/alex/scripts/backup.sh >> /home/alex/backups/backup.log 2>&1
```
- `0 2 * * *` = minute 0, hour 2, every day of every month, any weekday
- `>> log 2>&1` = append output AND errors to a log so you can check it later

## The backup script

```bash
#!/usr/bin/env bash                             # tell Linux to run this file with bash
set -euo pipefail                               # e=stop on error, u=stop on unset vars, pipefail=catch pipe errors
SRC="$HOME/documents"                           # what to back up
DEST="$HOME/backups"                            # where to put it
mkdir -p "$DEST"                                # make sure the destination exists
STAMP=$(date +%Y-%m-%d_%H%M)                    # unique timestamp so backups never overwrite each other
tar -czf "$DEST/docs-$STAMP.tar.gz" "$SRC"      # create the archive (no v = quiet output)
find "$DEST" -name "docs-*.tar.gz" -mtime +14 -delete   # delete backups older than 14 days
echo "Backup done: docs-$STAMP.tar.gz"          # confirmation line for the log
```
```bash
chmod +x ~/scripts/backup.sh                    # make the script executable
~/scripts/backup.sh                             # test it by hand first, before trusting cron with it
```

## The 3-2-1 rule

3 copies of your data, on 2 different media, 1 of them offsite (cloud or another building).

## Practice

Write the backup script above, `chmod +x` it, and run it once. Check that the `.tar.gz` appears.
