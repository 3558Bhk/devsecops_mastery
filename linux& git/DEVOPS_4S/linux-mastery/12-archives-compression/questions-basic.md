# 12 Archives & Compression — Basic Questions

**Q1.** Create a compressed archive of a folder.
```bash
tar -czvf backup.tar.gz mydir/   # c=create, z=gzip, v=verbose, f=the archive name (f goes LAST)
```

**Q2.** Extract that archive.
```bash
tar -xzvf backup.tar.gz          # x=extract; the other letters are the same
```

**Q3.** Look inside an archive WITHOUT extracting it.
```bash
tar -tzvf backup.tar.gz          # t=list contents — always do this first with unknown archives
```

**Q4.** Extract into a specific folder.
```bash
tar -xzvf backup.tar.gz -C /opt/   # -C changes directory first, then extracts there
```

**Q5.** What do the letters z, j and J mean?
```bash
tar -czvf a.tar.gz dir/          # z = gzip   (.tar.gz) — fast, standard
tar -cjvf a.tar.bz2 dir/         # j = bzip2  (.tar.bz2) — smaller, slower
tar -cJvf a.tar.xz dir/          # J = xz     (.tar.xz) — smallest, slowest
```

**Q6.** Zip a folder for a Windows user.
```bash
zip -r archive.zip mydir/        # -r recursive: required for folders
```

**Q7.** Unzip an archive.
```bash
unzip archive.zip                # extracts into the current folder
unzip archive.zip -d /tmp/out/   # -d extracts into a chosen destination
```

**Q8.** List a zip's contents without extracting.
```bash
unzip -l archive.zip             # -l = list
```

**Q9.** Compress one single file.
```bash
gzip file.txt                    # produces file.txt.gz and REMOVES the original
gunzip file.txt.gz               # decompresses it back
gzip -k file.txt                 # -k KEEPS the original file too
```

**Q10.** Read a compressed file without decompressing it.
```bash
zcat file.txt.gz                 # cat a .gz file
zless big.log.gz                 # page through it
zgrep "error" app.log.gz         # search inside it
```

**Q11.** Extract only one file from a big archive.
```bash
tar -xzvf backup.tar.gz mydir/config.yml   # name the member you want after the archive
```

**Q12.** Exclude some files while archiving.
```bash
tar --exclude='*.tmp' --exclude='node_modules' -czvf b.tar.gz mydir/
```

**Q13.** Password-protect a zip.
```bash
zip -e secret.zip file.txt       # -e prompts you for a password
```

**Q14.** Which archive type should you use for a Linux server backup, and why?
```bash
tar -czvf backup.tar.gz dir/     # tar preserves permissions, owners, symlinks and timestamps; zip does not
```
