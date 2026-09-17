# Pattern: Functions, menus, and arguments

```bash
#!/usr/bin/env bash

greet() {                                 # define a function: name() { ... }
    echo "Hello, $1"                      # inside a function, $1 is the function's OWN first argument
}
greet Alex                                # call it → prints "Hello, Alex"

add() { echo $(( $1 + $2 )); }            # functions "return" values by PRINTING them
result=$(add 3 4)                         # capture that output with $( )
echo "$result"                            # → 7

fail() { echo "ERROR: $*" >&2; return 1; } # >&2 sends the message to stderr; return 1 = failure code
fail "disk is full" || exit 1             # if fail returns non-zero, stop the whole script

usage() {                                 # the conventional help text
    cat <<HELP                            # print a block of text (a here-document)
Usage: $0 [-v] [-o OUTFILE] INPUT
  -v        verbose output
  -o FILE   write results to FILE
HELP
}

# ---------- Parsing flags with getopts ----------
verbose=0; out="result.txt"               # defaults
while getopts "vo:h" opt; do              # the string lists valid flags; ":" after a letter means it takes a value
    case $opt in
        v) verbose=1 ;;                   # -v sets verbose
        o) out="$OPTARG" ;;               # -o stores its argument ($OPTARG)
        h) usage; exit 0 ;;               # -h prints help and exits successfully
        *) usage; exit 1 ;;               # anything else = mistake
    esac
done
shift $((OPTIND - 1))                     # remove the parsed flags, leaving only positional arguments
input="${1:?an INPUT file is required}"   # :? aborts with this message if $1 is missing

# ---------- A menu with select ----------
select choice in "Backup" "Cleanup" "Quit"; do   # select auto-builds a numbered menu from a list
    case $choice in
        "Backup")  echo "running backup..." ;;   # case matches the exact text chosen
        "Cleanup") echo "cleaning..." ;;
        "Quit")    break ;;                       # break exits the loop
        *)         echo "invalid option" ;;       # * is the default/catch-all
    esac
done
```

## `case` in one line each

```bash
case "$1" in
    start)   echo "starting" ;;           # each pattern ends with ;; 
    stop)    echo "stopping" ;;
    status)  echo "checking" ;;
    *)       echo "usage: $0 {start|stop|status}"; exit 1 ;;   # * = anything else
esac                                      # esac = "case" backwards
```

## Practice

Write a script with `-v` and `-o FILE` flags plus a `usage()` function, then run it with `-h`.
