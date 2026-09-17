# 14 Productivity — Basic Questions

**Q1.** Repeat the previous command.
```bash
!!                       # expands to the last command you ran
sudo !!                  # re-run it with sudo — the classic "forgot sudo" fix
```

**Q2.** Search your command history interactively.
```bash
# press Ctrl+R, then type a few letters    # reverse search; Enter runs it, arrows edit it
history                  # print the whole history with numbers
history | grep git       # search it non-interactively
!123                     # run history entry number 123
```

**Q3.** Create a shortcut for a long command.
```bash
alias ll='ls -lhA'       # now "ll" runs the long listing
unalias ll               # remove it
alias                    # list every alias currently defined
```

**Q4.** Make an alias permanent.
```bash
echo "alias ll='ls -lhA'" >> ~/.bashrc   # add it to your shell's startup file
source ~/.bashrc                        # reload it in the current terminal
```

**Q5.** Which key cancels a running command?
```bash
# Ctrl+C               # sends SIGINT — stops the command
# Ctrl+Z               # suspends it; resume with bg or fg
```

**Q6.** Auto-complete a filename.
```bash
# type a few letters, then press Tab        # completes it; Tab twice lists all possibilities
```

**Q7.** Clear the screen.
```bash
clear                    # or press Ctrl+L (keeps your half-typed command)
```

**Q8.** Reuse the last argument of the previous command.
```bash
mkdir -p /opt/app/data   # ...long path...
cd !$                    # !$ = the last argument of the previous command
# Alt+. does the same thing interactively
```

**Q9.** Install a package on Ubuntu/Debian.
```bash
sudo apt update          # refresh the package index first
sudo apt install htop    # then install
```

**Q10.** Search for a package by keyword.
```bash
apt search "json"        # searches names and descriptions
apt show htop            # details about one package
```

**Q11.** Remove a package and its leftover configuration.
```bash
sudo apt remove htop     # uninstall, keep config
sudo apt purge htop      # uninstall AND delete config
sudo apt autoremove -y   # clean up dependencies nothing needs any more
```

**Q12.** Schedule a command to run every day at 2 AM.
```bash
crontab -e               # opens your schedule for editing
```
```text
0 2 * * * /home/alex/backup.sh >> /home/alex/backup.log 2>&1
```

**Q13.** List your scheduled jobs.
```bash
crontab -l               # show them
```

**Q14.** Run a one-off command 5 minutes from now.
```bash
at now + 5 minutes       # type the command, then Ctrl+D to schedule it
atq                      # list pending at jobs
```
