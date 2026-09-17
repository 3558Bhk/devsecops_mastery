# Pattern: `tar` — the archive workhorse

`tar` bundles many files into one. Add compression and you get `.tar.gz` / `.tar.xz`.

**Remember the order:** `tar OPTIONS ARCHIVE FILES`

```bash
tar -czvf backup.tar.gz mydir/        # CREATE: c=create, z=gzip, v=verbose, f=the archive filename
tar -cjvf backup.tar.bz2 mydir/       # same with bzip2 (smaller, slower)
tar -cJvf backup.tar.xz mydir/        # same with xz (smallest, slowest)
tar -xzvf backup.tar.gz               # EXTRACT: x=extract, z=gzip, v=verbose, f=file
tar -xzvf backup.tar.gz -C /opt/      # extract INTO a specific folder (-C = change directory first)
tar -tzvf backup.tar.gz               # LIST contents (t=list) WITHOUT extracting — always do this first
tar -xzvf backup.tar.gz mydir/a.txt   # extract just ONE file from the archive
tar -czvf logs-$(date +%F).tar.gz /var/log/*.log   # name the archive with today's date
tar --exclude='*.tmp' -czvf b.tar.gz mydir/        # skip files matching a pattern
tar -xzvf archive.tar.gz && rm archive.tar.gz      # extract, then delete the archive if that succeeded
tar -cvf uncompressed.tar mydir/      # no z/j/J = bundle only, no compression (fastest)
```

## Decoding the letters

| Letter | Meaning |
|---|---|
| `c` | create an archive |
| `x` | extract an archive |
| `t` | list the contents |
| `z` | gzip (`.gz`) |
| `j` | bzip2 (`.bz2`) |
| `J` | xz (`.xz`) |
| `v` | verbose: print each file |
| `f` | the next word is the archive FILENAME (always put f last) |

## Practice

Tar+gzip your home folder's `.bashrc` into `/tmp/backup.tar.gz`, then list its contents with `-t`.
