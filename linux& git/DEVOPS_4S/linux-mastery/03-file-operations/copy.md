# Pattern: Copying (`cp`)

```bash
cp file.txt backup.txt                # copy a file to a new name in the same folder
cp file.txt /tmp/                     # copy into another folder, keeping the same name
cp -r mydir/ mydir_backup/            # -r = RECURSIVE: required to copy a whole folder
cp -i file.txt /tmp/                  # -i asks before overwriting (safe mode while learning)
cp -v file.txt /tmp/                  # -v verbose: prints each file as it copies
cp -p file.txt keep.txt               # -p preserve timestamps, owner, permissions
cp -a mydir/ mydir_copy/              # -a archive: recursive + preserve everything (best for backups)
cp *.txt docs/                        # copy all .txt files into docs/
cp -r src/. dest/                     # copy CONTENTS of src (note the /.) into dest
cp file{,.bak}                        # neat trick: makes file.bak (brace expands to "file file.bak")
```

## Renaming while copying

```bash
cp report.pdf report_2026.pdf         # the second name can be anything = copy + rename
cp /etc/hosts ~/hosts.copy            # copying system files you don't own may need sudo
```

## Verify

```bash
diff file.txt backup.txt              # no output = files are identical
md5sum file.txt backup.txt            # same hash = same content (for big files)
```

## Practice

Copy your home folder's `.bashrc` to `.bashrc.backup` and confirm with `diff`.
