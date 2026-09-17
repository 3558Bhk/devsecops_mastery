# 03 File Operations — Scenario Questions

## Scenario 1
You edited `nginx.conf`, saved it, and the service broke. You want to compare against the backup.
```bash
diff nginx.conf nginx.conf.bak         # shows exactly which lines differ
diff -u nginx.conf nginx.conf.bak      # -u unified format: clearer + and - markers
cp nginx.conf.bak nginx.conf           # restore the working version
```

## Scenario 2
You need to hand a project folder to a teammate, keeping all permissions and timestamps.
```bash
cp -a project/ /shared/project/        # -a preserves everything, recursively
diff -r project/ /shared/project/      # -r compares two directory trees to confirm the copy
```

## Scenario 3
You ran `rm -rf build/` from the wrong directory and need to know what happened.
```bash
pwd                                    # where were you standing?
history 5                              # what did you actually type?
ls                                     # what is left here now?
```
Lesson: `rm` is permanent. Prevention habits:
```bash
ls build/                              # 1. always LIST what the target contains first
rm -ri build/                          # 2. delete with prompts while learning
trash-put build/                       # 3. or install trash-cli for a real recycle bin
```

## Scenario 4
A download produced 200 files named `IMG_0001.jpeg`. Rename them all to `.jpg`.
```bash
ls *.jpeg | head                       # preview the matches first
for f in *.jpeg; do mv -v "$f" "${f%.jpeg}.jpg"; done   # -v prints each rename so you can watch
```

## Scenario 5
Two different programs must read the same config file, but each expects it at a different path.
```bash
sudo ln -s /etc/app/config.yml /opt/app/conf/config.yml   # symlink: one real file, two paths
readlink -f /opt/app/conf/config.yml                      # verify it resolves to the real file
```
Now editing either path edits the same file — no copies to keep in sync.

## Scenario 6
You copied a folder from a USB stick and every file is owned by `root`; you cannot edit them.
```bash
ls -l mydir/ | head                    # confirm the owner really is root
sudo chown -R $USER:$USER mydir/       # -R recursive; $USER is your own username
```

## Scenario 7
You must delete everything inside `/tmp/myapp` but the folder has to stay (a service recreates files there).
```bash
find /tmp/myapp -mindepth 1 -delete    # -mindepth 1 skips the folder itself
ls -la /tmp/myapp                      # verify it is now empty but still exists
```

## Scenario 8
Create a full project skeleton in one go: `app/{src,tests,docs}` plus an empty README.
```bash
mkdir -p app/{src,tests,docs}          # brace expansion creates all three subfolders
touch app/README.md                    # empty starter file
tree app                               # confirm the structure
```

## Scenario 9
You want a safety net before running a risky bulk edit across a folder.
```bash
cp -a important/ important_backup_$(date +%F)/   # snapshot with today's date in the name
ls -d important_backup_*                          # confirm the snapshot exists
# ...now do the risky operation...
diff -r important/ important_backup_2026-09-14/   # check what changed afterwards
```
