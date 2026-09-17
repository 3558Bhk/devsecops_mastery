# 14 Productivity — Advanced Questions

**Q1.** Why does `alias ll='ls -lhA'` not work inside a script?
```bash
shopt -s expand_aliases   # aliases are disabled in non-interactive shells by default
```
In scripts, prefer a function or a variable: `ll() { ls -lhA "$@"; }` — functions take arguments properly.

**Q2.** Make a command run automatically whenever you change directory.
```bash
cd() { builtin cd "$@" && ls; }   # wrap the real cd (builtin) so "cd x" also lists the folder
```
Add that to `~/.bashrc`. `builtin` prevents infinite recursion.

**Q3.** Use brace expansion and process substitution — two features people miss.
```bash
diff <(ls dir1) <(ls dir2)         # compare command outputs directly, no temp files
cp config.yml{,.bak}               # brace expansion: copies to config.yml.bak
mkdir -p project/{src,tests}/{unit,integration}   # creates four nested folders at once
echo file{1..10}.txt               # sequence expansion
```

**Q4.** Customise your prompt so it always shows the current folder and git branch.
```bash
PS1='\u@\h:\w\$ '                  # \u user, \h host, \w full path, \$ prompt char
PS1='\[\e[32m\]\w\[\e[0m\] \$ '    # coloured version: green path
export PS1                         # put it in ~/.bashrc to keep it
```

**Q5.** Enable better history behaviour.
```bash
# add to ~/.bashrc
HISTSIZE=100000                    # keep many entries in memory
HISTFILESIZE=200000                # and in the file
HISTCONTROL=ignoreboth:erasedups   # ignore duplicates/space-prefixed, remove old duplicates
shopt -s histappend                # append instead of overwriting (so parallel terminals don't clash)
shopt -s cdspell                   # autocorrect small typos in cd
shopt -s globstar                  # enables ** recursive globs: ls **/*.py
PROMPT_COMMAND="history -a"        # write each command to disk immediately
```

**Q6.** Re-run the previous command with one word replaced.
```bash
^old^new                # quick substitution on the last command
!!:gs/old/new           # global substitution in the last command
echo !$                 # last argument of the previous command
echo !*                 # all arguments of the previous command
```

**Q7.** Write cron entries that actually work.
```bash
which mytool                     # cron has a minimal PATH — you need full paths
```
```text
*/5 * * * *  /usr/local/bin/check.sh >> /var/log/check.log 2>&1   # every 5 minutes
0 3 * * 1-5  cd /srv/app && ./report.sh                            # cron's cwd is your home, so cd first
0 0 1 * *    /bin/date +\%F >> /var/log/monthly.log                # % must be escaped as \% in crontab
@reboot      /usr/local/bin/startup.sh                              # run once after boot
```
```bash
grep CRON /var/log/syslog        # confirm cron actually fired (Debian/Ubuntu)
sudo journalctl -u cron -f       # or watch it live on systemd systems
```

**Q8.** Prefer systemd timers over cron for services.
```bash
sudo systemctl list-timers       # what is already scheduled
```
```text
# /etc/systemd/system/backup.timer
[Unit]
Description=Nightly backup
[Timer]
OnCalendar=*-*-* 02:00:00         # human-readable schedule
Persistent=true                 # run a missed job after the machine wakes up
[Install]
WantedBy=timers.target
```
```bash
sudo systemctl enable --now backup.timer   # activate it
systemctl status backup.timer              # check the next run time
```

**Q9.** Build a personal `bin` folder available everywhere.
```bash
mkdir -p ~/bin && echo 'export PATH="$HOME/bin:$PATH"' >> ~/.bashrc   # put your scripts first on PATH
source ~/.bashrc
printf '#!/usr/bin/env bash\necho hello from $0\n' > ~/bin/hi && chmod +x ~/bin/hi
hi                               # now runnable from any directory
```

**Q10.** Useful readline tricks beyond the basics.
```bash
# Ctrl+X Ctrl+E   open the current command line in your $EDITOR (great for long commands)
# Alt+U           uppercase the word after the cursor     Alt+L  lowercase it
# Ctrl+W          delete the previous word                Ctrl+Y  paste it back
# Alt+.           insert the last argument again (repeatable, walks backwards)
bind -p | grep -i 'ctrl-r'       # list your current key bindings
```
