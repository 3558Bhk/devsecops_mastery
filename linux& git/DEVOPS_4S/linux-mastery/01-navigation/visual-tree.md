# Pattern: Seeing the folder structure (`tree`)

```bash
tree                                  # draw the whole current folder as a diagram
tree -L 2                             # only go 2 levels deep (prevents huge output)
tree -d                               # show DIRECTORIES only, skip files
tree -a                               # show hidden files too (names starting with .)
tree -h                               # show human-readable sizes (4.2K, 1.1M, 2G)
tree /etc -L 1                        # visualise a specific folder, one level only
tree -L 2 -d > structure.txt          # save the diagram into a text file for notes
sudo apt install tree                 # install it if "command not found" (Debian/Ubuntu)
```

## Sample output

```text
projects
├── notes                             # a folder
│   └── day1.md                       # a file inside it
└── script.sh                         # a file at the top level
```

## Without `tree`, using plain `ls`

```bash
ls -R                                 # recursive list — same info, less pretty
find . -maxdepth 2 -type d            # list folders up to 2 levels deep (portable, always installed)
```

## Practice

Run `tree -L 2 -h ~` and find your largest subfolder.
