# Pattern: Installing software

Each distribution has its own package manager. Find yours:

```bash
cat /etc/os-release                     # tells you which distro → which command set below
```

## Debian / Ubuntu / Mint (`apt`)

```bash
sudo apt update                         # refresh the list of available packages (do this FIRST)
sudo apt upgrade                        # install updates for everything already installed
sudo apt install htop git curl          # install one or more packages
sudo apt install -y htop                # -y answers "yes" automatically (for scripts)
sudo apt remove htop                    # uninstall, keeping its configuration files
sudo apt purge htop                     # uninstall AND delete its configuration
sudo apt autoremove                     # remove packages nothing depends on any more
sudo apt search "json parser"           # search package names and descriptions
apt show htop                           # details: version, size, dependencies, homepage
apt list --installed                    # everything currently installed
apt list --upgradable                   # what updates are waiting
dpkg -i package.deb                     # install a downloaded .deb file directly
sudo apt --fix-broken install           # repair a broken half-finished install
```

## RHEL / Fedora / CentOS (`dnf` or `yum`)

```bash
sudo dnf install htop                   # install
sudo dnf update                         # update everything
sudo dnf remove htop                    # uninstall
sudo dnf search htop                    # search
sudo dnf list installed                 # what's installed
```

## Arch (`pacman`)

```bash
sudo pacman -Syu                        # sync + upgrade the whole system (one command)
sudo pacman -S htop                     # install
sudo pacman -Rns htop                   # remove with its unneeded dependencies
pacman -Ss htop                         # search
```

## Language-specific tools (used alongside the system manager)

```bash
pip install requests                    # Python packages
npm install -g typescript               # Node.js packages
cargo install ripgrep                   # Rust tools
snap install code --classic             # Snap packages (Ubuntu's app store format)
flatpak install flathub org.gimp.GIMP   # Flatpak sandboxed desktop apps
```

## Golden rule

```bash
sudo apt update && sudo apt install <name>   # always update the index before installing
```

## Practice

Install `htop`, run it, then remove it with `apt purge`.
