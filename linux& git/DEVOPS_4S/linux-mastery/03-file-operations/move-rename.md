# Pattern: Moving and renaming (`mv`)

In Linux, renaming IS moving — same command.

```bash
mv old.txt new.txt                    # rename a file
mv file.txt /tmp/                     # move a file into another folder
mv -i file.txt /tmp/                  # ask before overwriting an existing file
mv -v file.txt docs/                  # verbose: show what was moved
mv -n file.txt docs/                  # no-clobber: NEVER overwrite (skips silently)
mv *.log /var/log/archive/            # move many files using a wildcard
mv mydir /opt/                        # move a whole folder (no -r needed for mv)
mv "my file.txt" myfile.txt           # fix a bad filename with spaces
```

## Mass rename without `mv` in a loop

```bash
rename 's/\.jpeg$/\.jpg/' *.jpeg      # rename all .jpeg to .jpg (needs the "rename" package)
for f in *.txt; do mv "$f" "${f%.txt}.md"; done   # shell loop: ${f%.txt} strips the extension
```

## ⚠️ The classic beginner accident

```bash
mv important.txt /tmp/                # fine
mv important.txt important_notes.txt  # fine (rename)
mv important.txt /tmp                 # DANGER: if /tmp were a FILE, this overwrites it. Add the trailing /
```

Rule: always end a destination folder with `/`.

## Practice

Create `a.txt`, rename it to `b.txt`, then move it into `/tmp` — all in three commands.
