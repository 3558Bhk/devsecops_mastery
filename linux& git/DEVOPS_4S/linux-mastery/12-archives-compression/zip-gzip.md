# Pattern: `zip`, `gzip`, and single-file compression

```bash
zip archive.zip file1.txt file2.txt   # zip specific files together
zip -r archive.zip mydir/             # -r recursive: REQUIRED to zip a whole folder
zip -r -9 best.zip mydir/             # -9 maximum compression level
zip -e secret.zip file.txt            # -e password-protect it (you'll be prompted)
zip -x "*.log" -r clean.zip mydir/    # -x EXCLUDE files matching a pattern
unzip archive.zip                     # extract into the current folder
unzip archive.zip -d /tmp/out/        # -d extract into a specific destination folder
unzip -l archive.zip                  # list contents without extracting
unzip -o archive.zip                  # -o overwrite existing files without asking
gzip file.txt                         # compress to file.txt.gz (the ORIGINAL is removed)
gunzip file.txt.gz                    # decompress back to file.txt
gzip -k file.txt                      # -k KEEP the original file too
gzip -9 big.log                       # maximum compression
zcat file.txt.gz                      # cat a gzip file WITHOUT decompressing it first
zless big.log.gz                      # page through a compressed log
zgrep "error" app.log.gz              # grep inside a compressed file — very handy for old logs
gzip -d file.gz                       # -d is the same as gunzip
bzip2 file.txt / bunzip2 file.txt.bz2 # the same idea with a different algorithm
xz -k big.iso                         # best ratio; -k keeps the original
```

## Which should I use?

| Tool | Extension | Choose it when |
|---|---|---|
| `tar -czvf` | `.tar.gz` | Linux servers, backups, keeping permissions |
| `zip` | `.zip` | Sharing with Windows/Mac users |
| `gzip` | `.gz` | Compressing ONE file or log rotation |
| `xz` | `.xz` | Maximum compression, time is not a problem |

## Practice

Zip a folder, list its contents with `unzip -l`, then extract it elsewhere.
