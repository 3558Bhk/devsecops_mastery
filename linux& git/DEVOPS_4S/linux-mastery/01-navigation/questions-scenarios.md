# 01 Navigation — Scenario Questions

## Scenario 1
You are deep inside `/var/log/nginx/2026/09/` after checking logs, and you need to jump
straight back to the folder you were in before. You don't remember its path.
```bash
cd -                     # jumps back to $OLDPWD — no need to remember anything
```

## Scenario 2
`ls` clearly shows a folder called `data`, but `cd data` says "Permission denied".
```bash
ls -ld data              # inspect the folder itself: permissions and owner
```
Output like `drwx------ 2 root root` means only root may enter it.
```bash
sudo ls data             # look inside with admin rights, or
sudo chmod +rx data      # grant read+enter (only if you own/admin this folder)
```
A directory needs the `x` bit for you to `cd` into it and `r` to list it.

## Scenario 3
You `cd` into `/opt/app`, run a backup script, and the files land somewhere unexpected.
`/opt/app` turns out to be a symlink.
```bash
pwd                      # logical: /opt/app (what you typed)
pwd -P                   # physical: /srv/storage/app (the real place)
readlink -f /opt/app     # resolve the symlink completely
```
Use `pwd -P` (or `cd "$(pwd -P)"`) in scripts so paths match reality.

## Scenario 4
You must send a colleague a path to a file that works no matter which folder they are in.
```bash
pwd                      # get your current absolute location
echo "$(pwd)/report.pdf" # build the absolute path to send them
realpath report.pdf      # or let realpath print the full absolute path directly
```
Relative paths like `./report.pdf` would break on their machine.

## Scenario 5
You typed `cd my project files` and the shell complained. The folder is named `my project files`.
```bash
cd "my project files"    # quotes group the three words into one name
cd my\ project\ files    # equivalent: escape each space
cd my<TAB>               # best habit: start typing and let Tab complete it
```

## Scenario 6
Your terminal looks empty and every command seems to hang — you may have pressed Ctrl+S.
```bash
# press Ctrl+Q          # unfreeze terminal output (Ctrl+S pauses it, Ctrl+Q resumes)
clear                    # or Ctrl+L to redraw a clean screen
pwd                      # confirm you are still where you think you are
```

## Scenario 7
You need to work in a new nested folder structure that does not exist yet.
```bash
mkdir -p course/week1/notes   # -p creates every missing parent folder
cd course/week1/notes         # then walk in
tree -L 3 ~/course            # verify the structure you just made
```

## Scenario 8
You are on a shared server and want to know who else is logged in and where they are working.
```bash
who                      # lists users and their terminals
w                        # the same plus the command each one is running
echo $PWD                # and your own location for comparison
```
