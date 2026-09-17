# Pattern: Routine cleanup (free space safely)

```bash
sudo apt update && sudo apt upgrade -y    # refresh package lists, then install all updates
sudo apt autoremove -y                    # remove old kernels/libs no longer needed (safe, big win)
sudo apt clean                            # empty /var/cache/apt/archives (downloaded .deb files)
dpkg -l | grep '^rc' | awk '{print $2}' | xargs -r sudo apt purge -y   # purge leftover config of removed packages
sudo journalctl --disk-usage              # how much space do systemd logs use?
sudo journalctl --vacuum-time=7d          # keep only the last 7 days of logs
sudo journalctl --vacuum-size=200M        # or cap logs at 200 MB
rm -rf ~/.cache/thumbnails/*              # clear thumbnail cache (it regenerates automatically)
find ~ -name "node_modules" -type d -prune -exec du -sh {} +    # find heavy node_modules folders
find ~ -name "node_modules" -type d -prune -exec rm -rf {} +    # then delete them (reinstall later with npm i)
docker system df                          # Docker's space usage
docker system prune -af --volumes         # remove unused images/containers/volumes (⚠️ check first)
pip cache purge                           # clear the Python package cache
npm cache clean --force                   # clear the Node package cache
```

## Find what to delete, don't guess

```bash
du -h --max-depth=1 ~ | sort -rh | head    # rank your home subfolders by size
find ~ -type f -size +200M -exec ls -lh {} +    # list every file over 200 MB with its path
find /var/log -name "*.gz" -mtime +30 -delete   # delete compressed logs older than 30 days
```

## Safe order

1. `df -h` → confirm which disk is full.
2. `du -sh` → locate the big folders.
3. Package cleanups (`apt autoremove`, `apt clean`).
4. Log shrinking (`journalctl --vacuum-*`).
5. Only then delete your own files.

## Practice

Run the `du` ranking command on your home folder and write down the top 3 space users.
