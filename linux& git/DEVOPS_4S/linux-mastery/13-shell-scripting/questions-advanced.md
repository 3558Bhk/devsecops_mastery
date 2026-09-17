# 13 Shell Scripting — Advanced Questions

**Q1.** What does the safe-mode header do?
```bash
set -euo pipefail
# -e  exit immediately if any command fails
# -u  treat an unset variable as an error (catches typos)
# -o pipefail  a pipeline fails if ANY stage fails, not just the last one
```

**Q2.** Single vs double quotes — which one breaks this?
```bash
rm "$file"               # correct: one file, even with spaces in its name
rm $file                 # broken: word-splits, so "my file.txt" becomes two arguments
rm '$file'               # broken: literal text $file, not the variable
```

**Q3.** Loop over filenames safely, including names with spaces.
```bash
for f in *; do echo "$f"; done              # glob + quoted variable = safe
find . -name "*.log" -print0 | while IFS= read -r -d '' f; do echo "$f"; done   # NUL-safe version
ls | while read -r f; do echo "$f"; done    # UNSAFE: breaks on spaces and hides errors
```

**Q4.** Expand a variable's value safely with defaults.
```bash
out="${OUTPUT:-/tmp/out}"        # use /tmp/out if OUTPUT is unset or empty
: "${CONFIG:=/etc/app.conf}"     # assign the default to CONFIG as well
path="${DIR:?DIR must be set}"   # abort with this message if DIR is missing
```

**Q5.** Compare strings vs numbers — the classic bug.
```bash
[ "$a" = "$b" ]          # string comparison
[ "$a" -eq "$b" ]        # numeric comparison (fails if either side isn't a number)
[[ $a == b* ]]           # pattern match — only inside [[ ]]
[[ $a =~ ^[0-9]+$ ]]     # regex match; results land in the BASH_REMATCH array
```

**Q6.** Clean up temporary files no matter how the script exits.
```bash
tmp=$(mktemp)                                  # create a unique temp file
trap 'rm -f "$tmp"; echo cleaned' EXIT         # runs on normal exit, errors AND Ctrl+C
trap 'echo "interrupted"; exit 130' INT TERM   # custom handling for specific signals
```

**Q7.** Make a script work regardless of where it is called from.
```bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1   # move to the script's own folder
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # or store that folder in a variable
```

**Q8.** Pass an array of arguments correctly to a function or command.
```bash
files=("my file.txt" "other.txt")
myfunc "${files[@]}"     # [@] with quotes keeps each element separate — always use this form
echo "${#files[@]}"      # element count
```

**Q9.** Debug a misbehaving script.
```bash
bash -x script.sh        # print every command as it runs (with values expanded)
set -x                   # or turn tracing on inside the script
set +x                   # and off again
shellcheck script.sh     # static analysis: catches most beginner bugs automatically
bash -n script.sh        # syntax check without executing
```

**Q10.** Capture output and exit status separately.
```bash
if out=$(some_command 2>&1); then          # $() captures stdout+stderr; if tests the exit code
    echo "ok: $out"
else
    echo "failed: $out" >&2
fi
```
Note: `out=$(cmd); echo $?` gives the exit code of cmd, but `local out=$(cmd)` gives the exit code of `local`.

**Q11.** Read key=value pairs from a config file.
```bash
while IFS='=' read -r key value; do
    [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue   # skip comments and blank lines
    declare "$key=$value"                            # create a variable for each pair
done < config.env
```

**Q12.** Run several jobs in parallel and wait for all of them.
```bash
for host in web1 web2 db1; do
    ssh "$host" 'uptime' &      # launch each check in the background
done
wait                            # block until every background job finishes
```

**Q13.** Handle a lock so two copies cannot run at once.
```bash
exec 200>/tmp/myjob.lock        # open file descriptor 200 on the lock file
flock -n 200 || { echo "already running"; exit 1; }   # -n = do not wait, fail immediately
```
