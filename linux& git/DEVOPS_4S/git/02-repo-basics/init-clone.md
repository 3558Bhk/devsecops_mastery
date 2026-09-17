# Pattern: Creating and getting a repository

```bash
git init                                # turn the CURRENT folder into a repository (creates .git/)
git init myproject                      # create the folder AND initialise it in one step
git init --bare /srv/repo.git           # a repo with no working tree — used as a push target/server
mkdir app && cd app && git init -b main # -b main sets the initial branch name explicitly
git clone https://github.com/user/repo.git        # download a full copy of a remote repo
git clone git@github.com:user/repo.git            # same over SSH (needs your key installed)
git clone https://github.com/user/repo.git myname # clone into a folder called "myname"
git clone --depth 1 <url>               # shallow clone: latest commit only (fast, for CI or reading)
git clone -b release <url>              # clone and check out a specific branch
git clone --single-branch -b main <url> # fetch only that one branch's history
git clone --recurse-submodules <url>    # also fetch nested submodules
ls -a                                   # you should see the hidden .git folder
du -sh .git                             # how much history you just downloaded
```

## What `git init` actually creates

```bash
ls .git                                 # HEAD (where you are), objects (all data), refs (branch pointers)
cat .git/HEAD                           # "ref: refs/heads/main" — HEAD points at a branch
cat .git/config                         # this repo's local settings
```
Everything Git knows lives inside `.git/`. Delete that folder and the project is no longer a repo
(your files stay untouched).

## Verify you are in a repository

```bash
git status                              # works → you are inside a repo; errors → you are not
git rev-parse --show-toplevel           # print the repo's root folder, wherever you are inside it
git rev-parse --is-inside-work-tree     # true/false test, useful in scripts
```
