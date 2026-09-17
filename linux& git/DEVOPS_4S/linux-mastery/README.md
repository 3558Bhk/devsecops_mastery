# Linux Mastery — Pattern-Based Course for Complete Beginners

One topic per folder. Inside each folder: **pattern files** (reusable command recipes) plus
**three question files** — basic, advanced and scenario-based — each with answers and
inline comments so you understand *why*, not just *what*.

```text
07-processes/
├── view-processes.md         ← PATTERN: how to see what is running
├── kill-stop.md              ← PATTERN: how to stop things
├── background-jobs.md        ← PATTERN: how to run things detached
├── questions-basic.md        ← 12–14 warm-up questions + answers
├── questions-advanced.md     ← 8–15 harder questions + answers
└── questions-scenarios.md    ← 6–10 real-world incidents to solve
```

**93 files · ~1000 documented commands · 645 tested code blocks**

---

## How to use this course

1. **Read the pattern files** in the folder, top to bottom.
2. **Type every command yourself** in a terminal — never copy-paste blindly. Typing builds muscle memory.
3. **Solve `questions-basic.md`** without looking at the answers, then check yourself.
4. **Solve `questions-advanced.md`** — these add flags, combos and the "why".
5. **Solve `questions-scenarios.md`** — real incidents: full disk, dead process, broken SSH.
6. Move to the next folder only when the scenarios feel easy.

> Rule: if you get a question wrong, re-read the matching pattern file, then **re-type** the
> command in a terminal. Reading alone doesn't stick; typing does.


**Where to practice (no risk of breaking anything):**

```bash
# Easiest on Windows
wsl --install -d Ubuntu            # installs Ubuntu inside Windows (needs a restart)

# On Mac
brew install --cask orbstack       # lightweight Linux VM + terminal

# Anywhere, in the browser
# open https://bellard.org/jslinux or https://jslinux.org
```

---

## Learning order (follow exactly)

| # | Folder | What you master | Key commands |
|---|--------|-----------------|--------------|
| 1 | `01-navigation` | Moving around the filesystem | `pwd` `cd` `ls` `tree` |
| 2 | `02-listing-finding` | Finding files fast | `find` `locate` `which` |
| 3 | `03-file-operations` | Create, copy, move, delete, links | `mkdir` `cp` `mv` `rm` `ln` `touch` |
| 4 | `04-viewing-files` | Reading file contents | `cat` `less` `head` `tail` `wc` |
| 5 | `05-text-processing` | The 4 killer tools | `grep` `sed` `awk` `sort/uniq/cut` |
| 6 | `06-pipes-redirects` | Combining commands (the Linux superpower) | `|` `>` `>>` `2>&1` `xargs` |
| 7 | `07-processes` | Running, watching, killing programs | `ps` `top` `kill` `nohup` `&` |
| 8 | `08-users-permissions` | Who can touch what | `chmod` `chown` `sudo` `useradd` |
| 9 | `09-disk-storage` | Space, mounts, USB drives | `df` `du` `mount` |
| 10 | `10-system-info` | Health checks & logs | `uname` `free` `uptime` `journalctl` |
| 11 | `11-networking` | IP, ports, downloads, SSH | `ip` `ss` `curl` `ssh` `scp` |
| 12 | `12-archives-compression` | Zip / tar / gzip | `tar` `zip` `gzip` |
| 13 | `13-shell-scripting` | Automating everything | variables, loops, `if`, functions |
| 14 | `14-productivity` | Speed: history, aliases, shortcuts | `history` `alias` Ctrl-key combos |

**Every folder also contains the same three question files** — `questions-basic.md`,
`questions-advanced.md` and `questions-scenarios.md` — so each topic is: learn → drill → apply.

---

## The 3 mental models that make Linux "click"

**1. Everything is a file.** Directories, devices, even running programs' info — all appear as files. So file tools work on everything.

**2. Small tools, glued together.** Each command does ONE job well. `|` (pipe) sends one command's output into the next. That's how you build powerful one-liners from simple pieces.

**3. Paths.**
```bash
/home/you/notes.txt        # absolute path: starts with / (the root of everything)
./notes.txt                # relative path: . means "right here"
../                        # parent folder: .. means "go up one level"
~/                         # your home folder: ~ is short for /home/you
```

---

## Golden rules

```bash
man ls                     # manual page for ANY command — press q to quit
ls --help                  # faster, shorter help for most commands
sudo <command>             # run as the administrator (asks for your password)
```

- Never run a command you don't understand as `sudo`.
- `rm` has **no recycle bin** — deleted is gone. Prefer `rm -i` while learning.
- Spaces in file names cause pain: use `my_file.txt`, not `my file.txt`.
- Linux is case-sensitive: `File.txt` ≠ `file.txt`.
