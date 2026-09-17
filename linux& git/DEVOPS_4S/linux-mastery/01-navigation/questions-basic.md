# 01 Navigation — Basic Questions

> Try each question in your terminal first. Answers show the command plus what it does.

**Q1.** Which command prints your exact current location?
```bash
pwd                      # Print Working Directory — shows the folder you are standing in
```

**Q2.** How do you go to your home folder in two different ways?
```bash
cd                       # no argument = home
cd ~                     # ~ is the shortcut for /home/yourname
```

**Q3.** How do you move up one level? Up two levels?
```bash
cd ..                    # .. means the parent folder
cd ../..                 # up two levels in one step
```

**Q4.** Which command returns you to the folder you were in just before?
```bash
cd -                     # toggles between the current and the previous folder
```

**Q5.** What is the difference between an absolute and a relative path?
```bash
cd /etc/hosts            # absolute: starts with / — works no matter where you are
cd hosts                 # relative: measured FROM your current folder
```

**Q6.** What does `~` mean, and what does `~alex` mean?
```bash
cd ~                     # your own home folder
cd ~alex                 # the home folder of the user named alex
```

**Q7.** What is the very top of the whole filesystem called?
```bash
cd /                     # / is the root — every other path lives under it
```

**Q8.** How do you enter a folder whose name contains a space?
```bash
cd "my docs"             # quotes keep the name as one piece
cd my\ docs              # or escape the space with a backslash — identical result
```

**Q9.** Which command lists what is inside the current folder?
```bash
ls                       # list names
```

**Q10.** In a path, what do `.` and `..` mean?
```bash
cd .                     # . = this folder (so this changes nothing)
cd ..                    # .. = one folder up
```

**Q11.** Which folder holds system-wide configuration files?
```bash
ls /etc                  # /etc = configuration for the whole system
```

**Q12.** How do you see the folder structure as a diagram, only 2 levels deep?
```bash
tree -L 2                # -L limits the depth so the output stays readable
```

**Q13.** Which key auto-completes a partially typed folder name?
```bash
cd /et<TAB>              # Tab finishes it to /etc; press Tab twice to see all matches
```

**Q14.** You are lost. Which two commands get you safe again?
```bash
pwd                      # find out where you are
cd ~                     # reset to home — you can never be too lost
```
