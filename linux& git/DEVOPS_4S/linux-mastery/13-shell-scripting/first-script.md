# Pattern: Your first shell script

```bash
nano hello.sh                           # create the file in a simple editor
```

```bash
#!/usr/bin/env bash                       # shebang: line 1 tells Linux "run this with bash"
echo "Hello, $USER"                       # $USER is expanded to your username automatically
echo "Today is $(date)"                   # $(...) runs a command and inserts its output
echo "You are in $(pwd)"                  # same trick for the current directory
```

```bash
chmod +x hello.sh                         # give it EXECUTE permission — required to run it
./hello.sh                                # run it (the ./ means "in this folder")
bash hello.sh                             # alternative: run it via bash, no +x needed
sh hello.sh                               # run with the minimal "sh" (some bash features won't work)
which bash                                # find bash's real path (what the shebang points to)
echo $0                                   # inside a script: the script's own name
echo $1 $2                                # the 1st and 2nd ARGUMENTS passed to the script
echo $#                                   # how many arguments were given
echo "$@"                                 # all arguments, each kept separate (always quote it)
shift                                     # drop $1, so $2 becomes the new $1
exit 0                                    # finish successfully (0 = success, anything else = failure)
echo $?                                   # the exit code of the PREVIOUS command — 0 means it worked
```

## Arguments in action

```bash
#!/usr/bin/env bash                       # script named greet.sh
echo "Hello $1, you have $# args"         # $1 = first argument, $# = count
./greet.sh Alex extra                     # prints: Hello Alex, you have 2 args
```

## Safe headers (copy this into every script)

```bash
#!/usr/bin/env bash
set -euo pipefail                         # abort on errors, unset variables, and pipe failures
IFS=$'\n\t'                               # make word-splitting predictable (spaces in names are safe)
```

## Practice

Write a script that prints your username, the date, and how many arguments you passed it.
