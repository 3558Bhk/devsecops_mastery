# Pattern: Changing permissions (`chmod`)

Permissions are 3 characters × 3 groups:
**owner**, **group**, **others** — each can have **r**ead(4), **w**rite(2), e**x**ecute(1).

```bash
ls -l script.sh                       # look first: -rwxr-xr-- means owner rwx, group r-x, others r--
chmod +x script.sh                    # give EXECUTE permission to everyone (needed to run a script)
chmod 755 script.sh                   # 7=rwx, 5=r-x, 5=r-x → owner full, others read+execute
chmod 644 file.txt                    # 6=rw-, 4=r--, 4=r-- → normal file: owner edits, others read
chmod 600 ~/.ssh/id_rsa               # private key: only YOU can read/write (SSH demands this)
chmod 700 mydir/                      # only the owner can enter or list this folder
chmod 777 file                        # everyone can do anything — AVOID, it's a security hole
chmod u+x file                        # u=user/owner: add execute for the owner only
chmod g-w file                        # g=group: REMOVE write from the group
chmod o-r file                        # o=others: remove read
chmod a+r file                        # a=all three groups: add read
chmod -R 755 mydir/                   # -R recursive: apply to a folder and everything inside
chmod --reference=a.txt b.txt         # copy the permissions of a.txt onto b.txt
```

## Number table (memorise 4/2/1)

| Digit | Binary | Meaning |
|---|---|---|
| 4 | r-- | read |
| 2 | -w- | write |
| 1 | --x | execute |
| 7 | rwx | 4+2+1 = everything |
| 6 | rw- | 4+2 = read+write (typical file) |
| 5 | r-x | 4+1 = read+execute (typical folder/script) |

## Folders need `x`

```bash
chmod 700 mydir                       # without x you cannot even cd INTO a directory
```

## Practice

Create `run.sh`, try `./run.sh` (it fails), then `chmod +x run.sh` and run it again.
