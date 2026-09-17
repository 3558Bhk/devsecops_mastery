# Pattern: Deleting safely (`rm`, `rmdir`)

⚠️ Linux has NO recycle bin. `rm` is permanent. Read this file twice.

```bash
rm file.txt                           # delete one file, no confirmation
rm -i file.txt                        # -i ask YES/NO before deleting (use this while learning)
rm -f file.txt                        # -f force: never ask, ignore missing files
rm -r mydir/                          # -r recursive: required to delete a folder with contents
rm -rf build/                         # -rf force+recursive: the standard "delete this build folder"
rmdir empty_dir                       # delete a folder ONLY if it's empty (safe by design)
rm file1 file2 file3                  # delete several at once
rm *.log                              # delete all .log files in the current folder
rm -I *.txt                           # -I ask ONCE if more than 3 files match (nice middle ground)
find . -name "*.tmp" -delete          # delete by pattern across subfolders
```

## The disaster commands — never type these

```bash
# rm -rf /                            # deletes your ENTIRE system. Never.
# rm -rf ~                            # deletes your whole home folder
# rm -rf "$FOLDER"/                   # if $FOLDER is empty this becomes "rm -rf /"
echo "${FOLDER:?must be set}/"        # safer: :? aborts if the variable is empty or unset
```

## Recover-by-habit techniques

```bash
ls *.log                              # STEP 1: list exactly what the wildcard matches
rm -i *.log                           # STEP 2: delete those same matches WITH prompts
trash-put file.txt                    # real recycle bin if you install the "trash-cli" package
cp -a important/ important_backup/    # before risky bulk edits, make a copy first
```

## Practice

Create 3 junk files, list them with `ls`, then delete them with `rm -i` and answer each prompt.
