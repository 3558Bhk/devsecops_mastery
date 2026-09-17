# Pattern: Admin rights (`sudo`, `su`)

`sudo` = "run this ONE command as root (the administrator)". Root can do anything, including destroy the system.

```bash
sudo apt update                       # run a package update with admin rights
sudo -l                               # list what YOU are allowed to run with sudo
sudo whoami                           # prints "root" — proves the command ran as root
sudo -i                               # open a full root SHELL (you stay root until you type exit)
sudo su -                             # same idea: become root with root's environment
su alex                               # switch to another user (asks for THAT user's password)
exit                                  # leave the root shell and go back to normal
sudo !!                               # !! = the previous command → re-run it with sudo (lifesaver)
sudo -u postgres psql                 # run a command as a DIFFERENT specific user
sudo visudo                           # edit the sudo rules file SAFELY (it checks syntax before saving)
echo "alex ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/alex   # allow sudo without a password
sudo -k                               # forget my cached password immediately
```

## The rules

```bash
sudo rm -rf /                         # NEVER run destructive commands as root unless 100% sure
pwd                                   # before any sudo rm/mv/chmod -R: confirm your location
```

- Use `sudo` per command, not a permanent root shell.
- If a command works only with `sudo`, first ask *why* — often the real fix is `chown` on your own files.
- Password prompts never show characters as you type. That's normal.

## Practice

Run `sudo -l` to see your privileges, then `sudo whoami`.
