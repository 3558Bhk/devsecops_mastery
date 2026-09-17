# 12 Archives & Compression — Scenario Questions

## Scenario 1
Ship a project to a client, excluding build junk and version control.
```bash
tar --exclude='.git' --exclude='node_modules' --exclude='*.log' \
    -czf project-$(date +%F).tar.gz project/     # backslashes continue the command onto the next line
tar -tzf project-*.tar.gz | head                 # verify what actually got included
ls -lh project-*.tar.gz                          # check the size
```

## Scenario 2
Restore a single accidentally deleted file from last night's backup.
```bash
tar -tzf /backup/home-2026-09-13.tar.gz | grep "report.pdf"   # 1. find its exact path inside
mkdir /tmp/restore && tar -xzf /backup/home-2026-09-13.tar.gz -C /tmp/restore \
    home/alex/documents/report.pdf                            # 2. extract only that member
cp /tmp/restore/home/alex/documents/report.pdf ~/documents/    # 3. put it back
```

## Scenario 3
`/var/log` is 40 GB. Compress old logs without touching the active ones.
```bash
sudo find /var/log -name "*.log" -mtime +7 -exec gzip -9 {} +   # compress logs not modified for 7+ days
sudo find /var/log -name "*.gz" -mtime +90 -delete              # delete archives older than 90 days
zgrep "payment failed" /var/log/app.log.*.gz                    # old compressed logs remain searchable
```

## Scenario 4
Migrate a website from one server to another with minimal downtime.
```bash
# on the OLD server
tar -czf - /var/www/mysite | ssh user@newserver 'tar -xzf - -C /'    # stream straight across, no temp file
rsync -avz --progress /var/www/mysite/ user@newserver:/var/www/mysite/   # or a resumable sync
# then verify
ssh user@newserver 'du -sh /var/www/mysite && find /var/www/mysite | wc -l'   # compare size and file count
```

## Scenario 5
You must upload a 12 GB backup but the host limits files to 4 GB.
```bash
split -b 4G backup.tar.gz backup.tar.gz.part-       # split into 4 GB chunks
sha256sum backup.tar.gz > backup.sha256             # record the checksum for reassembly
ls -lh backup.tar.gz.part-*                         # upload all the parts
cat backup.tar.gz.part-* > restored.tar.gz          # on the other side: concatenate them back
sha256sum -c backup.sha256                          # prove the result is byte-identical
```

## Scenario 6
You downloaded `software.tar.gz` from the internet. Install it safely.
```bash
sha256sum software.tar.gz                    # compare against the checksum published on the site
tar -tzf software.tar.gz | head -20          # inspect members: look for absolute paths or ".."
mkdir /tmp/inspect && tar -xzf software.tar.gz -C /tmp/inspect   # extract into a sandbox first
less /tmp/inspect/*/install.sh               # READ the installer before running it
```

## Scenario 7
Nightly backups must keep 7 days of history and clean up automatically.
```bash
cat > ~/backup.sh <<'SCRIPT'                 # write the script with a here-doc
#!/usr/bin/env bash
set -euo pipefail
SRC="$HOME/projects"; DEST="$HOME/backups"; KEEP=7
mkdir -p "$DEST"
STAMP=$(date +%Y%m%d-%H%M%S)
tar -czf "$DEST/projects-$STAMP.tar.gz" "$SRC"                 # create
sha256sum "$DEST/projects-$STAMP.tar.gz" > "$DEST/projects-$STAMP.sha256"   # checksum
ls -1t "$DEST"/projects-*.tar.gz | tail -n +$((KEEP+1)) | xargs -r rm -v     # delete all but the newest 7
SCRIPT
chmod +x ~/backup.sh && ~/backup.sh            # test by hand before scheduling it with cron
```

## Scenario 8
A Windows colleague emailed you `data.zip` and the filenames look broken.
```bash
unzip -l data.zip                        # inspect the listing
unzip -O cp437 data.zip -d out/          # -O forces a different filename encoding
7z x data.zip -oout/                     # p7zip often handles odd encodings better
```

## Scenario 9
You need the fastest possible archive of a 200 GB folder on an 8-core box.
```bash
sudo apt install pigz
time tar -I 'pigz -1' -cf backup.tar dir/     # -1 = lowest compression level, maximum speed
time tar -I 'zstd -3 -T0' -cf backup.tar.zst dir/   # zstd multithreaded: often the best speed/ratio balance
```
