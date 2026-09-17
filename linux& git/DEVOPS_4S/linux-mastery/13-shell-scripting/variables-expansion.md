# Pattern: Variables and expansion

```bash
name="Alex"                             # NO spaces around = ; quotes protect spaces in the value
echo $name                              # read it
echo "$name"                            # ALWAYS quote: keeps the value as one piece
echo "${name}_backup"                   # braces show exactly where the variable name ends
readonly PI=3.14                        # cannot be changed afterwards
unset name                              # delete the variable
count=5; count=$((count + 1))           # $(( )) does INTEGER arithmetic
total=$((3 * 4 + 1))                    # = 13
files=$(ls)                             # $( ) captures a COMMAND's output into a variable
today=$(date +%F)                       # e.g. 2026-09-14
echo "Path: ${PWD##*/}"                 # ## removes the LONGEST matching prefix → last folder name
echo "Path: ${PWD%/*}"                  # % removes the SHORTEST matching suffix → parent path
f="report.pdf"; echo "${f%.pdf}"        # strip the extension → report
f="report.pdf"; echo "${f#*.}"          # keep only the extension → pdf
s="  hi  "; echo "${s// /_}"            # replace ALL spaces with underscores
v="${UNSET_VAR:-default}"               # use "default" if the variable is empty or unset
v="${UNSET_VAR:=default}"               # same, but ALSO assign the default to the variable
v="${CRITICAL:?must be set}"            # abort the script if this variable is missing
echo "${#name}"                         # length of the string in characters
arr=(one two three)                     # an ARRAY
echo "${arr[0]}"                        # first element (index starts at 0)
echo "${arr[@]}"                        # all elements
echo "${#arr[@]}"                       # how many elements
```

## Single vs double quotes — the #1 beginner confusion

```bash
x=world
echo "hello $x"                         # double quotes EXPAND variables → hello world
echo 'hello $x'                         # single quotes are LITERAL → hello $x
echo hello \$x                          # backslash escapes one character
```

## Useful built-in variables

```bash
echo $HOME $USER $SHELL                 # home folder, username, default shell
echo $PATH                              # the list of folders searched for commands (colon separated)
echo $PWD                               # current directory
echo $?                                 # exit code of the last command (0 = success)
echo $$                                 # this shell's own process ID
export MY_VAR="value"                   # export makes a variable visible to CHILD processes too
PATH="$PATH:/opt/mytools"               # the standard way to add a folder to your command search path
```

## Practice

Store `date +%F` in a variable and create a folder named `backup-$TODAY` using it.
