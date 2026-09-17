# Pattern: Creating files and folders

```bash
mkdir projects                        # create one folder
mkdir -p a/b/c                        # -p creates parents as needed — a, then a/b, then a/b/c
mkdir dir1 dir2 dir3                  # create several at once
mkdir -p src/{app,lib,test}           # brace expansion makes src/app, src/lib, src/test in one shot
mkdir "my folder"                     # quotes handle spaces in the name
touch notes.txt                       # create an EMPTY file (or update timestamp if it exists)
touch file{1..5}.txt                  # creates file1.txt ... file5.txt (sequence expansion)
touch -d "2026-01-01 10:00" old.txt   # create with a specific date (useful for testing)
> empty.txt                           # fastest way to make an empty file (> truncates/creates)
cat > notes.md                        # type text, then press Ctrl+D to save and exit
echo "hello" > hi.txt                 # write one line into a new file
nano newfile.txt                      # open a friendly editor; Ctrl+O save, Ctrl+X exit
```

## Safe habits

```bash
mkdir -p newdir && cd newdir          # create and enter in one line
test -e file.txt && echo "exists"     # -e tests existence without erroring out
ls                                    # always verify what you just created
```

## Practice

Build this in one command: `course/week1/{notes,code}`, plus an empty `course/README.md`.
