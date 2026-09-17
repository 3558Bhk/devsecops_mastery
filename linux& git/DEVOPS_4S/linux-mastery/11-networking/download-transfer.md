# Pattern: Downloading and transferring files

```bash
curl -O https://example.com/file.zip          # -O save using the remote filename
curl -o myname.zip https://example.com/f.zip  # -o save under a name YOU choose
curl -L https://bit.ly/abc -O                 # -L follow redirects (most real URLs need this)
curl -C - -O https://example.com/big.iso      # -C - RESUME a half-finished download
curl -s https://api.github.com                # -s silent: no progress bar (good in scripts)
wget https://example.com/file.zip             # classic downloader, saves with remote name
wget -c https://example.com/big.iso           # -c continue/resume an interrupted download
wget -r -np https://example.com/docs/         # -r recursive, -np don't go up to the parent dir
wget -i urls.txt                              # download every URL listed in a text file
scp file.txt alex@192.168.1.50:/home/alex/    # copy a file TO a remote machine over SSH
scp alex@192.168.1.50:/home/alex/log.txt .    # copy a file FROM remote to here (. = current folder)
scp -r mydir/ alex@server:/backup/            # -r copy a whole folder
rsync -avz mydir/ alex@server:/backup/mydir/  # a=archive, v=verbose, z=compress — smart sync, resumes
rsync -avz --delete src/ dest/                # make dest an EXACT mirror of src (deletes extras!)
rsync -avz --progress big.iso user@host:/data # show per-file progress
sftp alex@server                              # interactive file browser over SSH (get/put/ls/cd)
```

## `cp` vs `rsync` for backups

```bash
cp -a src/ dest/                       # simple copy: re-copies everything every time
rsync -a src/ dest/                    # copies only what CHANGED — much faster for repeated backups
```

## Test the network first

```bash
curl -I https://example.com            # reachable? which status code?
ping -c 3 example.com                  # basic reachability and latency
```

## Practice

Download a small file with `wget`, then verify it exists with `ls -lh`.
