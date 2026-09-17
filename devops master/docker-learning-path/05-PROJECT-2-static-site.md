# 🐣 PROJECT 2 — Static Website (`COPY`, `ADD`, `WORKDIR`, `.dockerignore`)

> **Part of the Docker Learning Path.** Do Project 1 first.
>
> ⏱️ **Time:** 30–40 minutes · 🎓 **Level:** beginner
> 🎯 **Instructions learned:** `WORKDIR`, `COPY`, `ADD`, `EXPOSE`, `LABEL` · **Concepts:** build context, trailing slashes, port publishing vs exposing, bind mounts

---

## 1. The idea

Serve your own multi-page website out of an nginx container. This is the project where `COPY` stops being abstract: you will see your files land inside a Linux filesystem you did not install, and you will learn the difference between `EXPOSE` and `-p` by breaking it on purpose.

---

## 2. Files to create

```
02-static-site-copy/
├── Dockerfile
├── .dockerignore
└── site/
    ├── index.html
    ├── about.html
    ├── style.css
    └── images/
        └── logo.svg
```

### `site/index.html`

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>My Docker Site</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <header>
    <img src="images/logo.svg" alt="logo" width="64" height="64">
    <h1>🐳 It works! Served from inside a container</h1>
  </header>
  <main>
    <p>This HTML file lives on my computer. It was <strong>COPIED into an image</strong>
       at build time, and nginx is serving it to my browser right now.</p>
    <ul>
      <li><a href="/about.html">About this project</a></li>
      <li><a href="/missing.html">A page that does not exist (404 test)</a></li>
    </ul>
  </main>
  <footer><small>Built with <code>COPY</code> + <code>nginx:alpine</code></small></footer>
</body>
</html>
```

### `site/about.html`

```html
<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><title>About</title><link rel="stylesheet" href="style.css"></head>
<body>
  <h1>About</h1>
  <p>Every file you see was placed in this image by a single <code>COPY site/ ./</code> instruction.</p>
  <p><a href="/">← back home</a></p>
</body>
</html>
```

### `site/style.css`

```css
:root { color-scheme: light dark; }
* { box-sizing: border-box; }
body {
  font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
  max-width: 720px; margin: 3rem auto; padding: 0 1.25rem; line-height: 1.6;
}
header { display: flex; align-items: center; gap: 1rem; border-bottom: 2px solid #2496ed; padding-bottom: 1rem; }
h1 { font-size: 1.6rem; margin: 0; }
a { color: #2496ed; }
code { background: rgba(127,127,127,.18); padding: .15em .4em; border-radius: 4px; }
footer { margin-top: 3rem; opacity: .6; border-top: 1px solid rgba(127,127,127,.3); padding-top: 1rem; }
```

### `site/images/logo.svg`

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">
  <rect width="64" height="64" rx="14" fill="#2496ed"/>
  <text x="32" y="43" font-size="34" text-anchor="middle">🐳</text>
</svg>
```

### `.dockerignore`

```gitignore
# version control
.git
.gitignore

# dependencies (they get installed INSIDE the image, never copied)
node_modules
**/node_modules
__pycache__
.venv
venv

# build output & logs
dist
build
*.log

# editor / OS junk
.vscode
.idea
.DS_Store
Thumbs.db

# SECRETS — must never enter a build context
.env
*.pem
*.key

# Docker's own files (no need to ship them into the image)
Dockerfile
.dockerignore
docker-compose*.yml

# project-local stuff
site/secret-notes.txt
*.tar.gz
```

### `Dockerfile`

```dockerfile
FROM nginx:1.29-alpine

LABEL org.opencontainers.image.title="My Static Site" \
      org.opencontainers.image.description="Learning COPY, ADD and WORKDIR" \
      org.opencontainers.image.version="1.0.0"

# WORKDIR sets the current directory AND creates it if it doesn't exist.
# For nginx:alpine this is the default document root.
WORKDIR /usr/share/nginx/html

# Copy the CONTENTS of ./site into the WORKDIR.
# Note: COPY copies contents, NOT the folder itself.
COPY site/ ./

# Documentation only — does NOT publish the port. `docker run -p` does that.
EXPOSE 80

# No CMD / ENTRYPOINT here on purpose:
# nginx:alpine already ships an ENTRYPOINT + CMD that start nginx in the foreground.
# If we wrote our own CMD we would REPLACE it and nginx would never start.
```

---

## 3. Build and run

```bash
cd 02-static-site-copy

docker build -t mysite:v1 .
docker run -d --name mysite -p 8080:80 mysite:v1
#            │              │
#            │              └─ host port 8080  →  container port 80
#            └─ detached (background)
```

🌐 Open **http://localhost:8080** in your browser.

```bash
docker ps                                  # STATUS: Up
docker port mysite                         # 80/tcp -> 0.0.0.0:8080
docker logs mysite                         # nginx startup + access logs
docker exec -it mysite sh                  # go inside
  ls -la /usr/share/nginx/html             # ← your copied files!
  ls -la /usr/share/nginx/html/images
  cat /etc/nginx/conf.d/default.conf       # ← the nginx config in use
  nginx -t                                 # ← test config syntax
  wget -qO- http://localhost/ | head -5    # ← the container fetching ITSELF
  exit
curl -I http://localhost:8080/             # HTTP headers from your host
curl -I http://localhost:8080/missing.html # → 404
```

Stop and clean up:
```bash
docker stop mysite && docker rm mysite
```

---

## 4. 🔬 Three experiments that teach more than any explanation

### Experiment A — `EXPOSE` is only documentation

Delete the `EXPOSE 80` line, rebuild, and run **with** `-p 8080:80`:

```bash
docker build -t mysite:noexpose .
docker run -d --name t1 -p 8080:80 mysite:noexpose
curl -I http://localhost:8080/     # ✅ STILL WORKS
docker rm -f t1
```

### Experiment B — `-p` is what actually opens the port

Run the **original** image (with `EXPOSE 80`) but **without** `-p`:

```bash
docker run -d --name t2 mysite:v1
curl -I http://localhost:8080/          # ❌ connection refused
docker exec t2 wget -qO- http://localhost/ | head -3   # ✅ works INSIDE the container
docker rm -f t2
```

> 🎯 **Conclusion:** `EXPOSE` = a note in the image's metadata ("my app listens here").
> `-p host:container` = the actual port mapping. **Only `-p` makes it reachable from your browser.**

### Experiment C — images are immutable

```bash
docker run -d --name t3 -p 8080:80 mysite:v1
# now edit site/index.html on your HOST, add a big <h1>CHANGED!</h1>
curl -s http://localhost:8080/ | grep CHANGED      # ❌ nothing — image is frozen
docker build -t mysite:v1 . && docker rm -f t3
docker run -d --name t3 -p 8080:80 mysite:v1
curl -s http://localhost:8080/ | grep CHANGED      # ✅ now it's there
docker rm -f t3
```

> 🎯 **A running container never sees changes to your source files.** Edit → **rebuild** → re-run. (Or use a bind mount — Task 2.4.)

---

## 5. ✅ Check yourself

1. Does `COPY site/ /usr/share/nginx/html/` create `/usr/share/nginx/html/site/index.html` or `/usr/share/nginx/html/index.html`?
2. Why is there no `CMD` in this Dockerfile?
3. What is the build context here, and how big is it?
4. If `COPY` can do everything, why does `ADD` exist?

<details>
<summary>👉 Answers</summary>

1. `/usr/share/nginx/html/index.html`. **`COPY` copies the *contents* of a source directory, never the directory itself as a subfolder.** (Different from Linux `cp -r`, which is why everyone gets this wrong once.)
2. `nginx:alpine` already defines `ENTRYPOINT ["/docker-entrypoint.sh"]` and `CMD ["nginx","-g","daemon off;"]`. Adding our own `CMD` would **replace** theirs and nginx would never start. Inheriting the base image's CMD is often exactly right.
3. The folder you passed as `.` to `docker build` — everything in it except what `.dockerignore` excludes. Watch the `transferring context: XXkB` line in the build output.
4. `ADD` has two extra powers: **downloading from a URL** and **auto-extracting local `.tar`/`.tar.gz` archives**. Docker's official guidance is: use `COPY` unless you specifically need one of those.
</details>

---

## 6. 🔨 Extra Tasks (do all 5)

### ▶ Task 2.1 — Add a new page the wrong way, then the right way

1. Create `site/contact.html` (copy `about.html`, change the text).
2. Start the container **without rebuilding** and request `/contact.html`.
3. Rebuild, restart, request it again.
4. Write **one sentence** in a comment at the top of your Dockerfile about what you learned.

<details>
<summary>👉 Answer</summary>

Step 2 → **404 Not Found**. Step 3 → works.
**The sentence:** *"An image is a frozen snapshot — files added on my host after the build do not exist inside it, so any content change requires a rebuild."*
This is the core of immutable infrastructure: you never patch a running container, you build a **new image version** and deploy that. It's also why `COPY . .` near the **bottom** of a Dockerfile matters — it's the layer that invalidates most often.
</details>

---

### ▶ Task 2.2 — Use `ADD` to auto-extract a tarball (its one real superpower)

```bash
cd site && tar czf ../bundle.tar.gz . && cd ..
ls -lh bundle.tar.gz
```

**Version 1 — with `ADD`:**
```dockerfile
FROM nginx:1.29-alpine
ADD bundle.tar.gz /usr/share/nginx/html/
EXPOSE 80
```
```bash
docker build -f Dockerfile.add -t mysite:add .
docker run --rm -d --name a1 -p 8080:80 mysite:add
curl -s http://localhost:8080/ | head -3      # ✅ site works — the tar was EXTRACTED
docker exec a1 ls /usr/share/nginx/html       # ✅ index.html, style.css, images/
docker rm -f a1
```

**Version 2 — with `COPY`:**
```dockerfile
FROM nginx:1.29-alpine
COPY bundle.tar.gz /usr/share/nginx/html/
EXPOSE 80
```
```bash
docker build -f Dockerfile.copy -t mysite:copy .
docker run --rm -d --name a2 -p 8080:80 mysite:copy
curl -sI http://localhost:8080/ | head -1     # 403 or a directory listing — no index.html!
docker exec a2 ls /usr/share/nginx/html       # ❌ only "bundle.tar.gz" — NOT extracted
docker rm -f a2
```

**Question:** Which would you use in production, and why?

<details>
<summary>👉 Answer</summary>

`ADD` extracted the archive automatically; `COPY` just copied the raw `.tar.gz` file.
**In production, prefer neither — use an explicit `RUN`:**
```dockerfile
COPY bundle.tar.gz /tmp/
RUN tar xzf /tmp/bundle.tar.gz -C /usr/share/nginx/html && rm /tmp/bundle.tar.gz
```
Why? Because `ADD`'s magic is **invisible**: a reader can't tell whether a file will be extracted or not, there's no checksum verification, no control over permissions, and remote `ADD` URLs bypass layer caching in confusing ways. Being explicit is auditable and lets you verify integrity:
```dockerfile
ADD --checksum=sha256:abc123... bundle.tar.gz /app/     # Dockerfile 1.6+
```
**The rule I follow:** `COPY` by default; `ADD` only for local tar auto-extraction when I've decided the magic is worth it; `RUN curl|tar` for anything remote.
</details>

---

### ▶ Task 2.3 — Prove `.dockerignore` works (and measure it)

```bash
# create 50 MB of junk inside the build context
dd if=/dev/zero of=site/bigfile.bin bs=1M count=50

# build WITHOUT ignoring it — watch "transferring context"
docker build --progress=plain -t mysite:fat . 2>&1 | grep -i "transferring context"
docker run --rm mysite:fat ls -lh /usr/share/nginx/html/bigfile.bin    # ✅ it's in the image!
```

Now add this line to `.dockerignore`:
```
site/bigfile.bin
```
```bash
docker build --progress=plain -t mysite:lean . 2>&1 | grep -i "transferring context"
docker run --rm mysite:lean ls -lh /usr/share/nginx/html/bigfile.bin   # ❌ No such file
docker images mysite
rm site/bigfile.bin
```

**Bonus:** add `secret.txt` containing `MY_PASSWORD=hunter2` to `site/`, rebuild **without** ignoring it, then run:
```bash
docker history mysite:fat --no-trunc | grep -i password
docker run --rm mysite:fat cat /usr/share/nginx/html/secret.txt   # your secret, in the image 😱
```
Then add `*.txt` or `site/secret.txt` to `.dockerignore` and rebuild.

<details>
<summary>👉 Answer / why it matters</summary>

The `transferring context` number drops from **~50 MB to a few kB**, and the build gets dramatically faster — especially on the second and later builds, and much more so in CI where the context is uploaded to a remote builder.
Three concrete benefits of `.dockerignore`:
1. **Speed** — smaller context to transfer and hash.
2. **Cache correctness** — without it, a `COPY . .` layer is invalidated by *any* file change (a log file, a `.git` commit), causing pointless rebuilds.
3. **Security** — `.env`, private keys, credentials and `.git` history never enter the image. Anything in an image layer can be recovered by anyone who pulls it, **forever**, even if you delete it in a later layer.
</details>

---

### ▶ Task 2.4 — Live editing with a bind mount

```bash
docker run -d --name devsite -p 8081:80 \
  -v "$(pwd)/site:/usr/share/nginx/html:ro" \
  mysite:v1
```

1. Edit `site/index.html` on your **host** → refresh **http://localhost:8081** → the change appears **with no rebuild**. ✅
2. Now try to write from inside the container:
   ```bash
   docker exec devsite sh -c 'echo hacked >> /usr/share/nginx/html/index.html'
   ```
3. Remove `:ro`, restart, and try again.

**Questions:** What does `:ro` do? When would you use a bind mount vs baking files in with `COPY`?

<details>
<summary>👉 Answer</summary>

`:ro` = **read-only** mount. Step 2 fails with `Read-only file system` — the container can see your files but cannot modify them. Removing `:ro` makes it read-write and step 3 succeeds (and now the container has edited your source file on your host!).

**Bind mount (`-v $(pwd)/site:/...`)** — the host directory is mounted live over the image path:
- ✅ Instant feedback, no rebuild. Perfect for **local development**.
- ✅ Great for config files and for reading host data.
- ❌ The image is no longer self-contained — it won't work on another machine without that folder.

**`COPY` (baked in)** — files become part of the immutable image:
- ✅ Portable, reproducible, versioned, works anywhere. **Required for production.**
- ❌ Every change needs a rebuild.

**Rule of thumb:** `COPY` for the app; bind mounts for development and for host-provided configuration/secrets.
Note also that a bind mount **hides** whatever was at that path in the image — mounting over `/usr/share/nginx/html` makes the `COPY`'d files invisible while the container runs.
</details>

---

### ▶ Task 2.5 — Custom nginx config, gzip, and a custom 404

**`nginx.conf`** (create next to the Dockerfile):
```nginx
server {
    listen       80;
    server_name  _;
    root         /usr/share/nginx/html;
    index        index.html;

    # compression
    gzip on;
    gzip_types text/css application/javascript image/svg+xml application/json;
    gzip_min_length 512;

    # security headers
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;

    # custom error page
    error_page 404 /404.html;
    location = /404.html { internal; }

    location / { try_files $uri $uri/ =404; }

    location /healthz { return 200 "ok\n"; add_header Content-Type text/plain; }
}
```

**`site/404.html`:**
```html
<!doctype html><html><head><meta charset="utf-8"><title>404</title>
<link rel="stylesheet" href="/style.css"></head>
<body><h1>🧭 404 — lost at sea</h1>
<p>That page isn't in this image. <a href="/">Go home</a>.</p></body></html>
```

**Dockerfile — note the order:**
```dockerfile
FROM nginx:1.29-alpine
WORKDIR /usr/share/nginx/html
COPY site/ ./
COPY nginx.conf /etc/nginx/conf.d/default.conf     # ← second COPY, AFTER the site
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s CMD wget -q --spider http://localhost/healthz || exit 1
```

```bash
docker build -t mysite:v2 .
docker run -d --name mysite2 -p 8082:80 mysite:v2

curl -s  http://localhost:8082/healthz                       # ok
curl -sI http://localhost:8082/style.css | grep -i encoding  # gzip: Content-Encoding: gzip
curl -sI http://localhost:8082/nope.html | head -1           # 404
curl -s  http://localhost:8082/nope.html | grep "lost at sea"

docker exec mysite2 nginx -t                                 # syntax is ok
docker exec mysite2 nginx -s reload                          # reload WITHOUT restarting
docker ps                                                    # STATUS shows (healthy)
docker rm -f mysite2
```

<details>
<summary>👉 Notes & gotchas</summary>

- The config `COPY` goes **after** the site `COPY` so that editing HTML doesn't invalidate the config layer (and vice versa) — order layers from least to most frequently changed.
- `nginx -s reload` re-reads config in a running container without downtime. If the config is invalid, `nginx -t` catches it first — always test before reloading.
- `error_page 404 /404.html;` + `location = /404.html { internal; }` means the custom page is served with a real **404 status code** (important for SEO) but the URL can't be requested directly.
- `HEALTHCHECK` here uses `wget`, which exists in alpine's BusyBox. `curl` does **not** exist in `nginx:alpine` by default — a very common beginner error.
- `gzip` only kicks in above `gzip_min_length`, so test with the CSS file, not a tiny HTML page.
</details>

---

## 7. 🧹 Clean up

```bash
docker rm -f mysite mysite2 devsite t1 t2 t3 a1 a2 2>/dev/null
docker rmi mysite:v1 mysite:v2 mysite:add mysite:copy mysite:fat mysite:lean mysite:noexpose 2>/dev/null
```

---

## ➡️ Next

**`06-PROJECT-3-config-and-env.md`** — `ENV`, `ARG`, `LABEL`: making one image behave differently in dev, staging and production.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
