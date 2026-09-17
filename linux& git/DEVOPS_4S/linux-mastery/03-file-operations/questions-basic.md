# 03 File Operations — Basic Questions

**Q1.** Create a folder called `projects` and, in another command, the nested `a/b/c`.
```bash
mkdir projects           # create one folder
mkdir -p a/b/c           # -p creates all missing parents along the way
```

**Q2.** Create an empty file without opening an editor.
```bash
touch notes.txt          # creates it if missing; otherwise updates its timestamp
```

**Q3.** Create five files at once: file1.txt … file5.txt.
```bash
touch file{1..5}.txt     # brace/sequence expansion generates all five names
```

**Q4.** Copy a file to a new name in the same folder.
```bash
cp file.txt backup.txt   # source first, destination second
```

**Q5.** Copy an entire folder.
```bash
cp -r mydir/ mydir_copy/ # -r = recursive; required whenever directories are involved
```

**Q6.** Rename a file.
```bash
mv old.txt new.txt       # in Linux, renaming IS moving — same command
```

**Q7.** Move a file into another folder.
```bash
mv file.txt /tmp/        # a trailing / makes it obvious the target is a folder
```

**Q8.** Delete a single file, and ask for confirmation while learning.
```bash
rm file.txt              # permanent — there is no recycle bin
rm -i file.txt           # -i prompts yes/no before deleting
```

**Q9.** Delete a folder that contains files.
```bash
rm -r mydir/             # -r = recursive
rm -rf mydir/            # -f also skips all prompts (use only when you are certain)
```

**Q10.** Delete a folder ONLY if it is empty (a safe alternative).
```bash
rmdir empty_dir          # refuses to delete a non-empty folder
```

**Q11.** Create a symbolic link (shortcut) to a file.
```bash
ln -s /etc/hosts ~/hosts # -s = symbolic link: a pointer to a path
```

**Q12.** Write one line of text into a new file from the command line.
```bash
echo "hello" > hi.txt    # > creates/overwrites the file with this content
```

**Q13.** Append a line to an existing file instead of overwriting it.
```bash
echo "more" >> hi.txt    # >> adds to the end and keeps what was there
```

**Q14.** Verify that a copy is identical to its original.
```bash
diff file.txt backup.txt # no output at all = the files are identical
```
