# 13 Shell Scripting — Scenario Questions

## Scenario 1
Write a script that takes a folder name as an argument and archives it with today's date.
```bash
cat > archive.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
src="${1:?usage: archive.sh FOLDER}"          # abort with a message if no argument was given
[ -d "$src" ] || { echo "not a directory: $src" >&2; exit 1; }   # validate before archiving
out="${src##*/}-$(date +%F).tar.gz"           # ${src##*/} strips the path, leaving the folder name
tar -czf "$out" "$src" && echo "created $out"
SCRIPT
chmod +x archive.sh && ./archive.sh ~/projects
```

## Scenario 2
Your script works when you run it by hand but fails in cron.
```bash
which mytool                        # cron has a minimal PATH — find the tool's FULL path
crontab -l                          # inspect the cron entry
```
```text
0 2 * * * /home/alex/scripts/backup.sh >> /home/alex/backup.log 2>&1
```
Fixes: use absolute paths everywhere, `cd` into the working directory explicitly, log output
yourself, and remember `%` must be written `\%` in crontab.

## Scenario 3
A script deleted files it should not have. Find the bug.
```bash
rm -rf "$DIR"/                      # if DIR is empty this becomes rm -rf / — the classic disaster
```
Defensive rewrite:
```bash
set -euo pipefail                            # -u stops on the unset variable immediately
: "${DIR:?DIR must be set and non-empty}"    # explicit guard with a clear message
[[ "$DIR" == /* && "$DIR" != "/" ]] || { echo "refusing: bad DIR" >&2; exit 1; }   # sanity check
find "$DIR" -mindepth 1 -maxdepth 1 -name '*.tmp' -delete   # delete only what you mean to
```

## Scenario 4
Process a CSV report and email only the rows where column 4 exceeds a threshold.
```bash
#!/usr/bin/env bash
set -euo pipefail
input="${1:-sales.csv}"; limit="${2:-1000}"
awk -F, -v lim="$limit" 'NR>1 && $4+0 > lim {printf "%s | %s | %s\n", $1, $2, $4}' "$input" > /tmp/alerts.txt
# -v lim= passes a shell variable INTO awk safely; NR>1 skips the header
if [ -s /tmp/alerts.txt ]; then                 # -s = the file exists and is not empty
    mail -s "Sales alerts" you@example.com < /tmp/alerts.txt
fi
```

## Scenario 5
Restart a service only if its health endpoint fails, and log every decision.
```bash
#!/usr/bin/env bash
url="http://localhost:8080/health"; log="/var/log/healthcheck.log"
if curl -fsS --max-time 5 "$url" > /dev/null; then     # -f fails on HTTP errors, -s silent, -S show errors
    echo "$(date -Is) OK" >> "$log"
else
    echo "$(date -Is) FAIL — restarting" >> "$log"
    sudo systemctl restart myapp
fi
```
Schedule it with `* * * * * /usr/local/bin/healthcheck.sh`.

## Scenario 6
You must run the same maintenance command on 20 servers.
```bash
#!/usr/bin/env bash
set -uo pipefail                 # note: no -e, so one failing host does not abort the whole run
hosts=$(cat servers.txt)
for h in $hosts; do
    echo "=== $h ==="
    ssh -o ConnectTimeout=5 -o BatchMode=yes "deploy@$h" 'df -h / | tail -1' || echo "UNREACHABLE: $h"
done
# BatchMode=yes = never prompt for a password, fail fast instead (requires SSH keys)
```

## Scenario 7
Rename 500 photos from `IMG_2831.JPG` to `2026-09-14_beach_001.jpg`.
```bash
#!/usr/bin/env bash
set -euo pipefail
prefix="${1:?usage: rename.sh PREFIX}"; i=1
for f in *.JPG; do
    [ -e "$f" ] || continue                              # nothing matched — skip
    new="$(date +%F)_${prefix}_$(printf '%03d' "$i").jpg"   # printf zero-pads the counter to 3 digits
    mv -vn "$f" "$new"                                   # -n never overwrite an existing file
    i=$((i+1))
done
```

## Scenario 8
Write a script with proper `-h` help, a `-v` verbose flag and validation.
```bash
#!/usr/bin/env bash
set -euo pipefail
usage() { cat <<HELP
Usage: $0 [-v] [-o OUTFILE] INPUT
  -v        verbose output
  -o FILE   write results to FILE (default: result.txt)
  -h        show this help
HELP
}
verbose=0; out="result.txt"
while getopts "vo:h" opt; do
    case $opt in
        v) verbose=1 ;;
        o) out="$OPTARG" ;;
        h) usage; exit 0 ;;
        *) usage; exit 1 ;;
    esac
done
shift $((OPTIND - 1))                       # drop the parsed flags
input="${1:?an INPUT file is required}"     # positional argument check
[ "$verbose" = 1 ] && echo "input=$input out=$out" >&2
wc -l < "$input" > "$out"                   # the actual work
```

## Scenario 9
Debug a script that "sometimes" fails.
```bash
bash -x ./script.sh 2> trace.log          # record every executed command with expanded values
shellcheck ./script.sh                     # static analysis catches quoting and portability bugs
set -Eeuo pipefail; trap 'echo "FAILED at line $LINENO (exit $?)" >&2' ERR   # pinpoint the failing line
```
