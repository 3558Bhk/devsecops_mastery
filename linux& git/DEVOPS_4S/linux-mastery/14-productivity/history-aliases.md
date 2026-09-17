# Pattern: History, aliases, and your shell config

```bash
history                               # show your last commands with numbers
history | grep git                    # search your own history for git commands
history 20                            # just the last 20
!!                                    # repeat the PREVIOUS command
!123                                  # repeat command number 123 from history
!git                                  # repeat the most recent command starting with "git"
sudo !!                               # re-run the last command with sudo (the classic "oops")
Ctrl+R                                # REVERSE SEARCH: type a few letters, it finds the command
^old^new                              # re-run the last command with "old" replaced by "new"
```

## Aliases — your own shortcuts

```bash
alias ll='ls -lhA'                    # create an alias for this session only
alias ..='cd ..'                      # a very popular one
alias gs='git status'                 # shorten anything you type often
alias update='sudo apt update && sudo apt upgrade -y'   # aliases can hold whole command chains
unalias ll                            # remove an alias
alias                                 # list all currently defined aliases
type ll                               # find out whether "ll" is an alias, function, or program
```

## Make it permanent: `~/.bashrc`

```bash
nano ~/.bashrc                        # open your shell's startup file
```
```bash
# --- my aliases ---
alias ll='ls -lhA'                    # add your aliases at the end of the file
alias ..='cd ..'
export EDITOR=nano                    # set the default editor used by many tools
export PATH="$PATH:$HOME/scripts"     # let you run your own scripts from anywhere
```
```bash
source ~/.bashrc                      # reload the file right now (or just open a new terminal)
```
Other shells: `~/.zshrc` for zsh, `~/.profile` for login shells.

## Practice

Add an `ll` alias to `~/.bashrc`, reload it, and use it.
