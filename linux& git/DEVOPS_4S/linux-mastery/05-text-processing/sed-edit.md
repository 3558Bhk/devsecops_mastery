# Pattern: Editing text in place (`sed`)

`sed` = stream editor. It rewrites lines as they flow past.

**Format:** `sed 's/OLD/NEW/flags'` — s means substitute.

```bash
sed 's/cat/dog/' pets.txt             # replace the FIRST "cat" on each line (screen only, file unchanged)
sed 's/cat/dog/g' pets.txt            # g = GLOBAL: replace every "cat" on the line
sed 's/cat/dog/gi' pets.txt           # i = ignore case too
sed -i 's/cat/dog/g' pets.txt         # -i edits the FILE ITSELF (in place). No undo!
sed -i.bak 's/old/new/g' file.txt     # -i.bak edits in place AND keeps a file.txt.bak backup (recommended)
sed -n '5,10p' big.txt                # -n prints nothing by default; p prints only lines 5 to 10
sed '3d' file.txt                     # delete line 3
sed '/^#/d' config.conf               # delete every line starting with # (remove comments)
sed '/^$/d' file.txt                  # delete all blank lines (^$ = empty line)
sed 's|/usr/local|/opt|g' paths.txt   # use | as the separator when your text contains / (no escaping)
sed '2i\NEW LINE' file.txt            # insert text BEFORE line 2
sed '2a\NEW LINE' file.txt            # append text AFTER line 2
sed 's/[0-9]\+/NUM/g' log.txt         # regex: replace any run of digits with the word NUM
echo "hello world" | sed 's/world/Linux/'   # sed works on piped input, not just files
```

## Capture groups (advanced but short)

```bash
sed -E 's/([a-z]+)@([a-z]+)/USER=\1 DOMAIN=\2/' emails.txt   # \1 \2 = the 1st and 2nd ( ) matches
```

## Safety rule

```bash
sed 's/x/y/g' file.txt                # 1) run WITHOUT -i and check the output
sed -i.bak 's/x/y/g' file.txt         # 2) only then run with -i.bak so a backup exists
```

## Practice

Take a copy of any text file and remove all its blank lines with `sed '/^$/d'`.
