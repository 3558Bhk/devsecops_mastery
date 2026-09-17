# 14 Productivity — Scenario Questions

## Scenario 1
You keep typing the same long docker command 20 times a day.
```bash
alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'   # add to ~/.bashrc
source ~/.bashrc                       # apply it now
dps                                    # use it
```
If the command needs arguments, use a function instead of an alias:
```bash
dex() { docker exec -it "$1" bash; }   # dex mycontainer
```

## Scenario 2
You typed a very long command and need to fix something in the middle.
```bash
# press Ctrl+X then Ctrl+E    # opens the whole command line in $EDITOR (vim/nano)
export EDITOR=nano            # set your preferred editor in ~/.bashrc
```
Or navigate without the mouse: `Ctrl+A` (start), `Ctrl+E` (end), `Alt+B`/`Alt+F` (word by word).

## Scenario 3
A command failed and you want to know exactly what went wrong and what the exit code means.
```bash
somecommand
echo $?                        # 0 = success; 126 = not executable; 127 = command not found; 130 = Ctrl+C
man somecommand | grep -A5 -i "exit"   # many tools document their exit codes
somecommand --help             # check for a verbose/debug flag
```

## Scenario 4
You need the same setup steps on every new machine you get.
```bash
cat > setup.sh <<'SCRIPT'      # one idempotent script you can re-run safely
#!/usr/bin/env bash
set -euo pipefail
sudo apt update && sudo apt install -y git curl htop tmux jq
mkdir -p ~/bin ~/projects
grep -q 'alias ll' ~/.bashrc 2>/dev/null || echo "alias ll='ls -lhA'" >> ~/.bashrc
grep -q 'HOME/bin' ~/.bashrc 2>/dev/null || echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc
echo "setup complete — open a new terminal"
SCRIPT
chmod +x setup.sh && ./setup.sh
```
`grep -q ... || echo ...` makes the script safe to run twice.

## Scenario 5
You ran a command, it produced a huge mess on screen, and now the terminal behaves oddly.
```bash
reset                          # fully re-initialises the terminal
clear                          # or just clear the screen (Ctrl+L)
stty sane                      # fix garbled input after catting a binary file
# press Ctrl+Q                 # if output seems frozen, you probably hit Ctrl+S
```

## Scenario 6
You want to be warned whenever a disk passes 85% — automatically, every 15 minutes.
```bash
sudo nano /usr/local/bin/diskwarn
```
```bash
#!/usr/bin/env bash
df -h -x tmpfs | awk 'NR>1 && $5+0 > 85 {print "LOW SPACE on", $6, ":", $5, "used"}'
```
```bash
sudo chmod +x /usr/local/bin/diskwarn
crontab -e
```
```text
*/15 * * * * out=$(/usr/local/bin/diskwarn); [ -n "$out" ] && echo "$out" | mail -s "disk alert" you@example.com
```

## Scenario 7
Find the command you ran three days ago but cannot remember.
```bash
history | grep -i docker       # search the whole history text
# Ctrl+R then type "dock"     # interactive reverse search — press Ctrl+R again for older matches
cat ~/.bash_history | less     # the raw history file
```
If it is missing, enable bigger history in `~/.bashrc` (see the advanced file, Q5).

## Scenario 8
Speed up a repetitive workflow of "edit, run, check logs".
```bash
alias t='npm test 2>&1 | tail -30'          # run tests and show only the summary
alias logs='tail -n 50 -f /var/log/app.log' # jump straight to live logs
watch -n 2 'npm test 2>&1 | tail -5'        # re-run tests automatically every 2 seconds
```

## Scenario 9
You must work on a server where you cannot install anything. Use only built-ins.
```bash
type -a jq 2>/dev/null || echo "no jq"       # check what is available
awk '{print $1}' file                        # awk/sed/grep exist on every Linux system
bash -c 'echo $BASH_VERSION'                 # confirm which shell features you can rely on
python3 -c 'import json,sys; print(json.load(sys.stdin))' < data.json   # python3 as a JSON tool
```

## Scenario 10
Diagnose why your `~/.bashrc` changes are not taking effect.
```bash
echo $SHELL                     # is your login shell actually bash? (maybe it is zsh → use ~/.zshrc)
bash -lic 'alias' | grep ll     # does an interactive login bash see your alias?
ls -la ~/.bash_profile ~/.profile ~/.bashrc   # ~/.bash_profile can SHADOW ~/.bashrc on login shells
grep -n bashrc ~/.bash_profile  # a login shell only reads .bashrc if .bash_profile sources it
source ~/.bashrc                # reload manually to test
```
