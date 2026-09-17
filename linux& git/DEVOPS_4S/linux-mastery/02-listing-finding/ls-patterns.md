# Pattern: Listing files (`ls`)

```bash
ls                                    # plain list of names in the current folder
ls -l                                 # long format: permissions, owner, size, date, name
ls -a                                 # ALL files, including hidden ones (names starting with .)
ls -h                                 # human sizes: 4.0K / 2.1M / 1.3G (needs -l to show size)
ls -lh                                # combo: long + human sizes — the one you'll use daily
ls -lt                                # sort by modified TIME, newest first
ls -ltr                               # newest LAST (reverse) — best for "what changed just now?"
ls -lS                                # sort by SIZE, biggest first
ls -R                                 # recursive: list every subfolder too
ls -l /etc                            # list a folder other than the current one
ls -ld /tmp                           # -d shows info about the FOLDER itself, not its contents
ls -i                                 # show inode number (the file's unique ID on disk)
ls -la --color=auto                   # colourise output (folders blue, executables green)
alias ll='ls -lhA'                    # create a shortcut so you can type "ll" forever
```

## Reading one line of `ls -l`

```text
-rw-r--r--  1  alex  staff  2048  Sep 14 10:22  notes.txt
 │└──┬──┘    │  │     │      │      └──┬──┘      └──┬──┘
 │   │       │   │     │      │        │            └ name
 │   │       │   │     │      │        └ last modified
 │   │       │   │     │      └ size in bytes
 │   │       │   │     └ group that owns it
 │   │       │   └ user (owner)
 │   │       └ number of hard links
 │   └ permissions: r=read w=write x=execute, in 3 groups: owner/group/others
 └ file type: - normal file, d directory, l symlink
```

## Practice

Find the 5 most recently modified files in your home folder. (`ls -ltr ~`)
