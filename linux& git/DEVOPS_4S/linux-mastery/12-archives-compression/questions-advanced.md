# 12 Archives & Compression — Advanced Questions

**Q1.** Verify an archive is not corrupt before trusting it.
```bash
sha256sum backup.tar.gz > backup.sha256      # record the checksum at creation time
sha256sum -c backup.sha256                   # verify later: prints OK or FAILED
tar -tzf backup.tar.gz > /dev/null && echo "archive readable"   # structural check
```

**Q2.** Compress a folder while it is still being written (live backup).
```bash
tar -czf snap.tar.gz --warning=no-file-changed mydir/ ; echo "exit=$?"   # exit 1 = some file changed mid-read
```
Better: stop the writer, or snapshot the filesystem (LVM/ZFS/btrfs) and archive the snapshot.

**Q3.** Parallel compression — much faster on multi-core machines.
```bash
sudo apt install pigz                          # parallel gzip
tar -I pigz -cf backup.tar.gz mydir/           # -I names the compressor program
tar -I 'pigz -9' -cf backup.tar.gz mydir/      # maximum compression, still parallel
tar -I pxz -cf backup.tar.xz mydir/            # parallel xz equivalent
```

**Q4.** Archive only files newer than a reference (incremental backup).
```bash
tar -czf inc-$(date +%F).tar.gz -N last_backup.marker mydir/   # -N = newer than this file
touch last_backup.marker                                        # update the marker after each run
find mydir -newermt "1 day ago" -type f                         # see what would be included
```

**Q5.** Split a huge archive into 4 GB chunks (for upload limits).
```bash
tar -czf - mydir/ | split -b 4G - backup.tar.gz.part-    # stream tar into split
cat backup.tar.gz.part-* | tar -xzf -                    # reassemble and extract in one pipe
```

**Q6.** Archive straight over the network without writing an intermediate file.
```bash
tar -czf - mydir/ | ssh user@server 'tar -xzf - -C /backup/'    # compress → pipe → extract remotely
ssh user@server 'tar -czf - /data' | tar -xzf -                 # pull a remote folder down
```

**Q7.** Preserve hard links, ACLs and extended attributes.
```bash
tar --acls --xattrs -czf backup.tar.gz mydir/    # keep ACLs and xattrs
tar -czf backup.tar.gz --hard-dereference=no mydir/   # keep hard links as links
tar -xzpf backup.tar.gz                          # -p restore permissions on extract
```

**Q8.** Protect yourself from a malicious archive that extracts to `../../etc/passwd`.
```bash
tar -tzf suspicious.tar.gz | head              # LOOK for members starting with / or containing ..
mkdir sandbox && tar -xzf suspicious.tar.gz -C sandbox   # always extract untrusted archives into an empty folder
tar --no-same-owner -xzvf a.tar.gz             # do not restore foreign ownership
```

**Q9.** Compress logs on the fly in a pipeline.
```bash
mysqldump mydb | gzip > mydb-$(date +%F).sql.gz       # dump and compress without a huge temp file
zcat mydb-2026-09-01.sql.gz | mysql mydb              # restore directly from the compressed dump
```

**Q10.** Compare the contents of two archives.
```bash
diff <(tar -tzf a.tar.gz | sort) <(tar -tzf b.tar.gz | sort)   # <(...) is a process substitution
```

**Q11.** Choose the right compression level.
```bash
gzip -1 file      # fastest, weakest     gzip -9 file   # slowest, strongest
xz -9e file       # extreme xz compression (very slow, best ratio)
zstd -19 file     # modern: near-xz ratio at gzip-like speed (apt install zstd)
tar -I 'zstd -19' -cf a.tar.zst dir/    # zstd through tar
```

**Q12.** Estimate how big the archive will be before creating it.
```bash
du -sh mydir/                       # uncompressed size
tar -czf /dev/null mydir/ 2>/dev/null; echo done   # a dry run (still costs CPU time)
```
