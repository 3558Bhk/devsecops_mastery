# Pattern: The pipe `|` — chaining commands

`|` takes the OUTPUT of the left command and feeds it as INPUT to the right command.
This is the core Linux idea: tiny tools glued into powerful ones.

```bash
ls -l | less                          # long listing, pageable (no scrolling off the screen)
ls -l | wc -l                         # count how many items are in the folder
cat app.log | grep "error"            # show only error lines
grep "error" app.log | wc -l          # count error lines (grep reads the file directly — better)
ps aux | grep chrome                  # list processes, keep only ones matching "chrome"
ps aux | grep -v grep | grep chrome   # -v grep removes the grep command itself from the results
history | grep ssh                    # search your own command history
df -h | grep -v tmpfs                 # disk usage, hiding temporary filesystems
ls | sort | head -5                   # chain 3: list → sort → first 5 names
cat file | tr 'a-z' 'A-Z' | less      # chain more: read → uppercase → page
find . -name "*.log" | xargs rm       # xargs turns a LIST of filenames into ARGUMENTS for rm
find . -name "*.txt" | xargs grep -l "TODO"    # search only the files that find produced
ls -l | awk '{print $9}' | grep "\.py$"        # just the Python filenames
```

## `tee` — pipe AND save at the same time

```bash
command | tee output.txt              # show on screen AND write to a file
command | tee -a output.txt           # -a appends instead of overwriting
ls -l | tee listing.txt | grep ".sh"  # save everything, but continue filtering only .sh
```

## Reading it out loud

```bash
ps aux | grep nginx | wc -l           # "list processes, keep nginx ones, count them"
```
Read pipelines left → right, like a sentence.

## Practice

Count how many files in `/etc` end with `.conf`.
