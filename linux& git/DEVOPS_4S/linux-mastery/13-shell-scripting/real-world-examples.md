# Pattern: Small scripts that solve real problems

## 1. Rename every `.jpeg` to `.jpg` in a folder

```bash
#!/usr/bin/env bash
set -euo pipefail
for f in *.jpeg; do                        # loop over the matches
    [ -e "$f" ] || continue                # if nothing matched, the glob stays literal — skip it
    mv -v "$f" "${f%.jpeg}.jpg"            # ${f%.jpeg} strips the old extension, then add the new one
done
```

## 2. Watch a folder and report new files

```bash
#!/usr/bin/env bash
watch -n 5 'ls -lt /tmp/incoming | head'   # re-run the listing every 5 seconds
# or for a one-shot diff, keep a list and compare:
ls /tmp/incoming > /tmp/now.txt            # current state
diff /tmp/before.txt /tmp/now.txt          # "<" = removed, ">" = newly added
```

## 3. Backup + verify + rotate (production-style)

```bash
#!/usr/bin/env bash
set -euo pipefail
SRC="$HOME/projects"; DEST="$HOME/backups"; KEEP=7        # what, where, how many copies to keep
mkdir -p "$DEST"
STAMP=$(date +%Y%m%d-%H%M%S)                               # unique timestamp
ARCHIVE="$DEST/projects-$STAMP.tar.gz"
tar -czf "$ARCHIVE" "$SRC"                                 # create the archive quietly
sha256sum "$ARCHIVE" > "$ARCHIVE.sha256"                   # write its checksum
sha256sum -c "$ARCHIVE.sha256"                             # verify it immediately
ls -1t "$DEST"/projects-*.tar.gz | tail -n +$((KEEP+1)) | xargs -r rm -v   # delete all but the newest $KEEP
echo "OK: $ARCHIVE"
```
- `ls -1t` → newest first, one per line
- `tail -n +8` → skip the first 7 lines
- `xargs -r rm` → delete what's left; `-r` means "do nothing if the list is empty"

## 4. Health check you can run any morning

```bash
#!/usr/bin/env bash
echo "== Host ==";   hostnamectl --static 2>/dev/null || hostname
echo "== Uptime =="; uptime -p
echo "== Disk ==";   df -h --output=target,pcent,avail -x tmpfs 2>/dev/null || df -h
echo "== Memory =="; free -h | head -2
echo "== Load ==";   cat /proc/loadavg
echo "== Top CPU =="; ps aux --sort=-%cpu | head -4
echo "== Errors (24h) =="; sudo journalctl -p err --since "24 hours ago" --no-pager | tail -10
```

## 5. Find and fix bad permissions

```bash
find . -type f -perm 777 -exec chmod 644 {} +   # world-writable FILES → normal 644
find . -type d -perm 777 -exec chmod 755 {} +   # world-writable DIRECTORIES → normal 755
find . -type f -name "*.sh" -exec chmod +x {} + # make all shell scripts executable
```

## Practice

Save example 4 as `health.sh`, `chmod +x` it, and run it.
