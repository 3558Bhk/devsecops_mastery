# Pattern: Where am I? (`pwd`)

The terminal always has a "current location". Every relative command depends on it.

```bash
pwd                                   # Print Working Directory — shows your exact current location
pwd -P                                # same, but resolves symlinks (shortcuts) to the real physical path
cd /tmp && pwd                        # move to /tmp, then show location (&& = run next only if previous succeeded)
echo $PWD                             # the shell variable that always holds the current directory
echo ${PWD##*/}                       # prints only the LAST folder name (## strips the longest prefix)
echo $HOME                            # your home folder, usually /home/yourname
```

## Why it matters

```bash
pwd                                   # say: /home/alex/projects
rm data.txt                           # this deletes /home/alex/projects/data.txt — pwd tells you WHERE
```

Always run `pwd` before a dangerous command (`rm`, `mv`, `chmod -R`).

## Practice

Open a terminal, run `pwd`, then type `echo $HOME`. Are you inside your home folder?
