# 01 Navigation — Advanced Questions

**Q1.** Print only the LAST folder name of your current path.
```bash
echo ${PWD##*/}          # ## removes the longest matching prefix, leaving just the last part
```

**Q2.** Print the parent path (everything except the last folder).
```bash
echo ${PWD%/*}           # % removes the shortest matching suffix from the end
```

**Q3.** `pwd` and `pwd -P` disagree. Why?
```bash
pwd                      # logical path: follows symlinks as you typed them
pwd -P                   # physical path: resolves symlinks to the real location on disk
```

**Q4.** Which variable remembers the folder `cd -` will take you back to?
```bash
echo $OLDPWD             # the shell stores your previous directory here
```

**Q5.** Why is `cd` a shell builtin instead of a normal program?
```bash
type cd                  # reports "cd is a shell builtin"
```
A separate program would get its own copy of the working directory and exit — it could never
change the directory of the shell that called it. Only a builtin can.

**Q6.** What is the difference between `ls /tmp` and `ls -ld /tmp`?
```bash
ls /tmp                  # lists the CONTENTS of /tmp
ls -ld /tmp              # -d shows info about the folder ITSELF (permissions, owner)
```

**Q7.** Explain what these two quoting styles print differently.
```bash
x=world
echo "path/$x"           # double quotes expand the variable → path/world
echo 'path/$x'           # single quotes are literal → path/$x
```

**Q8.** List a folder tree two levels deep on a system that has no `tree`.
```bash
find . -maxdepth 2 -type d    # find is always installed; -type d = directories only
```

**Q9.** You typed `cd folder1 folder2` and got an error. What happened and what did you mean?
```bash
cd folder1 folder2       # error: cd accepts only ONE destination
mkdir -p folder1/folder2 && cd folder1/folder2   # you probably meant a nested path
```

**Q10.** Enter a folder, do something, and return — all in one command that fails safely.
```bash
cd /etc && grep root passwd && cd -    # && runs the next step only if the previous one succeeded
```

**Q11.** Which path variable controls where the shell looks for commands, and how do you extend it?
```bash
echo $PATH                          # colon-separated list of folders searched for programs
export PATH="$PATH:$HOME/scripts"   # append your own folder (keep $PATH or you lose everything)
```

**Q12.** What is the difference between `$HOME`, `$PWD` and `~`?
```bash
echo "$HOME"             # variable: your home folder path
echo "$PWD"              # variable: current folder path
echo ~                   # tilde expansion: same as $HOME, but also works as ~username
```
