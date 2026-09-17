# 🛠️ DOCKER CLI — Complete Real-Time Command Reference

> A **production-first** command reference, not just a list. Everything a DevOps/SRE actually types, plus the less-common commands so you have no gaps, plus the real troubleshooting scenarios interviewers ask about.
>
> **How to use it:** sections 2–12 and 21 are the daily drivers — learn those cold. Sections 13–32 are reference. **Sections 33–41 are the interview gold**: they map commands to *scenarios*, which is what "real-world experience" actually means.
>
> Companion files: [`01-DOCKERFILE-GUIDE.md`](01-DOCKERFILE-GUIDE.md) (Dockerfile instructions) · [`03-CHEATSHEET.md`](03-CHEATSHEET.md) (one-page revision) · [`00-ONE-DAY-MASTER-PLAN.md`](00-ONE-DAY-MASTER-PLAN.md)

---

## 📑 Contents

| § | Section | § | Section |
|---|---|---|---|
| [1](#1-docker-command-structure) | Command structure | [22](#22-compose-file-selection) | Compose file selection |
| [2](#2-container-lifecycle--most-frequently-used) | **Container lifecycle** ⭐ | [23](#23-docker-system-management) | System management |
| [3](#3-container-listing) | Container listing + filters | [24](#24-docker-volume-drivers) | Volume drivers |
| [4](#4-start--stop--restart) | Start / stop / restart | [25](#25-docker-context) | Context (remote Docker) |
| [5](#5-execute-commands-inside-containers--very-important) | **`exec`** ⭐ | [26](#26-docker-scout--image-security) | Scout / security |
| [6](#6-container-logs--very-important-in-production) | **Logs** ⭐ | [27](#27-docker-manifest--multi-architecture) | Manifest / multi-arch |
| [7](#7-inspect--debug-containers--very-important) | **Inspect / debug** ⭐ | [28](#28-docker-plugins) | Plugins |
| [8](#8-copy-files) | Copy files | [29](#29-docker-swarm--know-for-interviews) | Swarm |
| [9](#9-remove-containers) | Remove containers | [30](#30-docker-secrets) | Secrets |
| [10](#10-docker-images--most-important) | **Images** ⭐ | [31](#31-docker-configs--swarm) | Configs |
| [11](#11-image-filtering--cleanup) | Image filtering / cleanup | [32](#32-docker-events--real-time-troubleshooting) | Events |
| [12](#12-build-images--very-important) | **Build** ⭐ | [33](#33-commands-worth-knowing-that-most-lists-miss) | Commands most lists miss |
| [13](#13-docker-buildx) | Buildx | [34–40](#40-real-time-scenario-container-is-down) | **7 real-time scenarios** ⭐ |
| [14](#14-docker-registry--docker-hub) | Registry / Hub | [41](#41-dockerfile-commands-vs-docker-cli) | Dockerfile vs CLI |
| [15](#15-docker-networking) | Networking | [42](#42-most-important-flags-to-memorize) | Flags to memorise |
| [16](#16-port-mapping) | Port mapping | [43](#43-the-commands-you-should-be-able-to-use-without-thinking) | Muscle-memory list |
| [17](#17-docker-volumes--storage) | **Volumes / storage** ⭐ | [44](#44-exit-codes-and-signal-reference) | Exit codes & signals |
| [18](#18-resource-limits) | Resource limits | [45](#45-go-template---format-recipes) | `--format` recipes |
| [19](#19-environment-variables) | Environment variables | [46](#46--the-real-interview-mastery-sequence) | **The 10 workflows** ⭐ |
| [20](#20-labels) | Labels | | |
| [21](#21-docker-compose--very-important) | **Compose** ⭐ | | |

---

## 1. Docker command structure

Every Docker command follows the same shape. Internalise it and you can guess any command you've never used.

```
docker [GLOBAL OPTIONS]  COMMAND  [COMMAND OPTIONS]  [ARGUMENTS]

docker  --debug          run      --detach --publish 8080:80   nginx:1.29
        └─ global ─┘     └cmd┘    └──── flags ────┘            └─ arg ─┘
```

Modern Docker also has **object-oriented** form — the same commands, grouped by noun. Both work; the object form is clearer in scripts:

```
docker container run   ==  docker run
docker container ls    ==  docker ps
docker image ls        ==  docker images
docker image build     ==  docker build
docker network create  ==  (no legacy equivalent)
docker volume create   ==  (no legacy equivalent)
docker system prune    ==  (no legacy equivalent)
```

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| Global help | `docker --help` | Lists every available command group and command | `docker --help` |
| Command help | `docker COMMAND --help` | Flags and arguments for one command — **read this more than any doc** | `docker run --help` |
| Management help | `docker container --help` | Lists subcommands of an object | `docker container --help` |
| Version | `docker version` | Client + Server/Engine versions, API version, Go version | `docker version` |
| Short version | `docker --version` | One line, for scripts and CI logs | `docker --version` |
| Full info | `docker info` | Engine, storage driver, containers, images, runtimes, cgroup driver, registries, warnings | `docker info` |
| Debug mode | `docker -D COMMAND` | Verbose client debug output (API calls) | `docker -D ps` |
| Log level | `docker -l debug COMMAND` | Sets the client log level | `docker -l debug info` |
| Custom host | `docker -H tcp://host:2375 COMMAND` | Talks to a remote Docker daemon | `docker -H ssh://user@srv ps` |
| Custom format | `docker COMMAND --format '{{...}}'` | Go-template output — essential for scripting | `docker ps --format '{{.Names}}\t{{.Status}}'` |
| Quiet | `docker COMMAND -q` | IDs only, so you can pipe into other commands | `docker rm -f $(docker ps -aq)` |
| No truncation | `docker COMMAND --no-trunc` | Full 64-char IDs and full command lines | `docker history --no-trunc app` |

> 🔑 **The `-q` + `$( )` pattern is the backbone of Docker scripting:**
> ```bash
> docker rm  -f $(docker ps -aq)          # remove every container
> docker rmi -f $(docker images -q)       # remove every image
> docker volume rm $(docker volume ls -q) # remove every volume
> docker stop $(docker ps -q)             # stop everything running
> ```

---

## 2. Container lifecycle — MOST FREQUENTLY USED

### `docker run` — the flag reference

```
docker run [OPTIONS] IMAGE[:TAG|@DIGEST] [COMMAND] [ARG...]
                    └─────────── overrides CMD/ENTRYPOINT ───────────┘
```

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| Basic | `docker run IMAGE` | Creates **and** starts a container from an image | `docker run nginx` |
| Detached | `docker run -d IMAGE` | Runs in the background; prints the container ID | `docker run -d nginx` |
| Interactive | `docker run -it IMAGE sh` | `-i` keeps STDIN open, `-t` allocates a TTY → a real shell | `docker run -it ubuntu bash` |
| Named | `docker run --name NAME IMAGE` | Gives the container a stable name (DNS name on user networks) | `docker run -d --name web nginx` |
| Auto-remove | `docker run --rm IMAGE` | Deletes the container when it exits — perfect for one-shot tasks | `docker run --rm alpine echo hi` |
| Restart policy | `docker run --restart POLICY IMAGE` | `no` \| `on-failure[:N]` \| `always` \| `unless-stopped` | `docker run -d --restart unless-stopped nginx` |
| Env var | `docker run -e KEY=VALUE IMAGE` | Sets one environment variable | `docker run -e ENV=prod nginx` |
| Pass-through env | `docker run -e KEY IMAGE` | Forwards the **host's** variable of that name | `docker run -e AWS_REGION app` |
| Env file | `docker run --env-file FILE IMAGE` | Loads many variables from a `KEY=VALUE` file | `docker run --env-file .env app` |
| Publish port | `docker run -p HOST:CTR IMAGE` | Maps a host port to a container port | `docker run -p 8080:80 nginx` |
| Publish all | `docker run -P IMAGE` | Publishes every `EXPOSE`d port to a **random** host port | `docker run -P nginx` |
| Volume | `docker run -v NAME:/path IMAGE` | Mounts a named volume (or a host path if it starts with `/` or `.`) | `docker run -v db:/var/lib/mysql postgres` |
| Bind mount | `docker run -v $(pwd):/app IMAGE` | Mounts your current host folder | `docker run -v $(pwd):/app node` |
| Explicit mount | `docker run --mount type=bind,src=...,dst=... IMAGE` | Verbose but unambiguous; fails loudly if the source is missing | see [§17](#17-docker-volumes--storage) |
| Network | `docker run --network NET IMAGE` | Attaches to a user-defined network → DNS by name works | `docker run --network app-net web` |
| Hostname | `docker run --hostname NAME IMAGE` | Sets the container's own hostname | `docker run --hostname web01 nginx` |
| Network alias | `docker run --network-alias ALIAS IMAGE` | Extra DNS name for this container on the network | `docker run --network app-net --network-alias api-v2 web` |
| Work dir | `docker run -w DIR IMAGE` | Overrides `WORKDIR` for this run | `docker run -w /app node npm test` |
| User | `docker run -u USER IMAGE` | Overrides the image's `USER` (name or `uid:gid`) | `docker run -u 1000:1000 app` |
| Override entrypoint | `docker run --entrypoint CMD IMAGE` | **The debugging escape hatch** — replaces ENTRYPOINT | `docker run -it --entrypoint sh myapp` |
| Read-only root FS | `docker run --read-only IMAGE` | Container can't write anywhere except mounted volumes/tmpfs | `docker run --read-only --tmpfs /tmp app` |
| tmpfs | `docker run --tmpfs /path IMAGE` | Writable in-memory filesystem that vanishes on stop | `docker run --read-only --tmpfs /tmp app` |
| Init process | `docker run --init IMAGE` | Injects **tini** as PID 1 → proper signal forwarding + zombie reaping | `docker run --init myapp` |
| Memory limit | `docker run -m 512m IMAGE` | Hard memory ceiling; exceeding it → OOM kill (exit 137) | `docker run -m 512m app` |
| CPU limit | `docker run --cpus 1.5 IMAGE` | CPU quota (throttles, never kills) | `docker run --cpus=1.5 app` |
| PID limit | `docker run --pids-limit N IMAGE` | Fork-bomb protection | `docker run --pids-limit 200 app` |
| Capabilities | `docker run --cap-drop ALL --cap-add NET_BIND_SERVICE IMAGE` | Least privilege — drop everything, add back only what's needed | see [§18](#18-resource-limits) |
| No new privileges | `docker run --security-opt no-new-privileges IMAGE` | Blocks setuid escalation inside the container | `docker run --security-opt no-new-privileges:true app` |
| Privileged | `docker run --privileged IMAGE` | Nearly all host capabilities + devices. ⚠️ **Avoid** — it defeats container isolation | `docker run --privileged ubuntu` |
| Labels | `docker run --label k=v IMAGE` | Metadata you can filter on later | `docker run --label env=prod nginx` |
| Log driver | `docker run --log-driver loki IMAGE` | Where stdout goes | `docker run --log-driver json-file --log-opt max-size=10m app` |
| DNS | `docker run --dns 1.1.1.1 IMAGE` | Custom resolver | `docker run --dns 8.8.8.8 app` |
| Add host entry | `docker run --add-host name:ip IMAGE` | Extra `/etc/hosts` line | `docker run --add-host db:10.0.0.5 app` |
| Extra hosts file | `docker run -v /etc/hosts:/etc/hosts:ro IMAGE` | Share the host's resolution | — |
| Ulimits | `docker run --ulimit nofile=65535:65535 IMAGE` | Raise file-descriptor limits (Cassandra/ES need this) | `docker run --ulimit nofile=100000 cassandra` |
| Sysctls | `docker run --sysctl net.core.somaxconn=1024 IMAGE` | Kernel tuning, namespaced | `docker run --sysctl net.ipv4.ip_forward=1 app` |
| Device | `docker run --device /dev/video0 IMAGE` | Pass a host device through | `docker run --device /dev/ttyUSB0 app` |
| GPU | `docker run --gpus all IMAGE` | NVIDIA GPU access (needs the nvidia-container-toolkit) | `docker run --gpus all nvidia/cuda nvidia-smi` |
| Platform | `docker run --platform linux/amd64 IMAGE` | Force an architecture (Apple Silicon ↔ amd64) | `docker run --platform linux/amd64 node` |
| Health off | `docker run --no-healthcheck IMAGE` | Disables the image's `HEALTHCHECK` | `docker run --no-healthcheck app` |
| Secret | `docker run --secret id=mysecret,src=./s.txt IMAGE` | Mounts a file at `/run/secrets/mysecret` (never in a layer) | `docker run --secret id=aws,src=$HOME/.aws app` |
| Stop signal | `docker run --stop-signal SIGQUIT IMAGE` | Overrides the image's `STOPSIGNAL` | `docker run --stop-signal SIGQUIT nginx` |
| Stop timeout | `docker run --stop-timeout 30 IMAGE` | Grace period before SIGKILL | `docker run --stop-timeout 30 app` |
| Runtime | `docker run --runtime runsc IMAGE` | Use gVisor/Kata/etc. instead of runc | `docker run --runtime=runsc app` |
| CID file | `docker run --cidfile /tmp/id IMAGE` | Writes the container ID to a file for scripts | `docker run -d --cidfile web.cid nginx` |
| Attach control | `docker run -d --attach=false IMAGE` | Don't attach STDIN/STDOUT even in foreground | — |
| Entrypoint+args | `docker run IMAGE cmd arg1` | Anything after the image **replaces CMD** | `docker run --rm alpine ls /etc` |

> ⚠️ **`--privileged` vs `--cap-add`:** `--privileged` grants *all* capabilities, disables seccomp/AppArmor and exposes every host device — a container escape is one kernel bug away. Almost always you need one specific capability (`NET_ADMIN`, `SYS_PTRACE`, `NET_BIND_SERVICE`) or a specific device. **Drop ALL, add back the minimum.**

### The other lifecycle verbs

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| Create only | `docker create IMAGE` | Creates a container **without starting** it | `docker create --name web nginx` |
| Start | `docker start CONTAINER` | Starts a created/stopped container | `docker start web` |
| Start attached | `docker start -a CONTAINER` | Starts **and** attaches to its output | `docker start -a web` |
| Start interactive | `docker start -ai CONTAINER` | Starts and attaches interactively | `docker start -ai ubuntu` |
| Attach | `docker attach CONTAINER` | Attaches to the **main** process (PID 1) — Ctrl+C kills it! | `docker attach web` |
| Detach from attach | `Ctrl-P` then `Ctrl-Q` | Leaves an attached container running | — |
| Rename | `docker rename OLD NEW` | Renames a container | `docker rename web web-old` |
| Wait | `docker wait CONTAINER` | Blocks until it exits, then prints the **exit code** | `docker wait job1` |
| Update live | `docker update --memory 1g CONTAINER` | Changes limits/restart policy on a **running** container | `docker update --cpus 2 api` |
| Pause | `docker pause CONTAINER` | Freezes all processes via cgroup freezer | `docker pause web` |
| Unpause | `docker unpause CONTAINER` | Resumes a frozen container | `docker unpause web` |

---

## 3. Container listing

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| Running | `docker ps` | Currently running containers | `docker ps` |
| All | `docker ps -a` | Running **and** stopped/exited | `docker ps -a` |
| Latest | `docker ps -l` | Only the most recently created container | `docker ps -l` |
| Last N | `docker ps -n 5` | The last five created | `docker ps -n 5` |
| Quiet | `docker ps -q` | IDs only (pipe-friendly) | `docker stop $(docker ps -q)` |
| Filter | `docker ps -f FILTER` | Filter by status/name/label/ancestor/network/volume | `docker ps -f status=exited` |
| Size | `docker ps -s` | Adds the **writable-layer** size per container | `docker ps -s` |
| No truncation | `docker ps --no-trunc` | Full IDs and full commands | `docker ps --no-trunc` |
| Custom columns | `docker ps --format '{{.Names}}\t{{.Status}}'` | Exactly the fields you want | see [§45](#45-go-template---format-recipes) |
| Digests | `docker ps --format '{{.Names}} {{.Image}}'` | Name + image reference | — |

### Most useful `docker ps` filters

| Filter | Example | Use |
|---|---|---|
| `status` | `docker ps -af status=exited` | Crashed/stopped containers (`created`, `running`, `paused`, `restarting`, `removing`, `exited`, `dead`) |
| `status=exited` + code | `docker ps -af exited=137` | Find OOM-killed containers specifically |
| `name` | `docker ps -af name=api` | Substring/regex match on the name |
| `id` | `docker ps -af id=abc123` | By ID prefix |
| `ancestor` | `docker ps -af ancestor=nginx:1.29` | Every container from this image |
| `label` | `docker ps -af label=env=prod` | By label key or key=value |
| `before` | `docker ps -af before=web` | Created before this container |
| `since` | `docker ps -af since=web` | Created after this container |
| `network` | `docker ps -af network=app-net` | Attached to this network |
| `volume` | `docker ps -af volume=db-data` | Using this volume |
| `publish` | `docker ps -af publish=8080` | Publishing this host port |
| `expose` | `docker ps -af expose=80/tcp` | Exposing this container port |
| `health` | `docker ps -af health=unhealthy` | Failing their healthcheck |
| Combine | `docker ps -af status=running -af label=tier=web` | Filters are **AND**ed |

---

## 4. Start / Stop / Restart

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| Stop | `docker stop CONTAINER` | `SIGTERM` → wait 10 s → `SIGKILL`. Graceful. | `docker stop web` |
| Stop timeout | `docker stop -t 30 CONTAINER` | Custom grace period before the kill | `docker stop -t 30 web` |
| Stop many | `docker stop web api db` | Accepts multiple names/IDs | `docker stop $(docker ps -q)` |
| Kill | `docker kill CONTAINER` | Immediate `SIGKILL` — **no cleanup, can corrupt data** | `docker kill web` |
| Custom signal | `docker kill -s SIGTERM CONTAINER` | Send any signal (e.g. `SIGHUP` to reload nginx config) | `docker kill -s HUP nginx-proxy` |
| Restart | `docker restart CONTAINER` | Stop + start, honouring the stop timeout | `docker restart web` |
| Restart timeout | `docker restart -t 30 CONTAINER` | Custom grace period on restart | `docker restart -t 30 web` |
| Remove | `docker rm CONTAINER` | Deletes a **stopped** container (and its writable layer) | `docker rm web` |
| Force remove | `docker rm -f CONTAINER` | Stops **and** deletes a running container | `docker rm -f web` |
| Remove + anon volumes | `docker rm -v CONTAINER` | Also removes **anonymous** volumes (named volumes survive) | `docker rm -v web` |
| Prune stopped | `docker container prune` | Deletes every stopped container (asks first) | `docker container prune -f` |
| Prune with filter | `docker container prune --filter "until=24h"` | Only containers older than 24 h | `docker container prune -f --filter until=24h` |
| Prune by label | `docker container prune --filter "label!=keep"` | Keep containers you labelled | `docker container prune -f --filter label=temp` |

> 🔑 **`stop` vs `kill` vs `rm`:**
> - `stop` is polite — your app can close DB connections, flush buffers, finish in-flight requests.
> - `kill` is a gunshot — use it only when `stop` hangs. Databases can be corrupted.
> - `rm` deletes the container's writable layer forever. **Named volumes survive `rm`; anonymous ones don't (unless `-v`).**

> 🔑 **If `docker stop` always takes the full 10 seconds**, your image uses **shell-form** `CMD`/`ENTRYPOINT`: `/bin/sh` is PID 1 and doesn't forward `SIGTERM`. Fix with exec form (`CMD ["app"]`) or `exec` in your entrypoint script. See [`07-PROJECT-4-cli-entrypoint.md`](07-PROJECT-4-cli-entrypoint.md).

---

## 5. Execute commands inside containers — VERY IMPORTANT

`docker exec` starts a **new** process inside an **already running** container. It does not touch PID 1.

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| One-shot | `docker exec CONTAINER CMD` | Runs a command, prints output, exits | `docker exec web ls /app` |
| Shell | `docker exec -it CONTAINER bash` | Interactive shell (Debian/Ubuntu-based images) | `docker exec -it web bash` |
| POSIX shell | `docker exec -it CONTAINER sh` | When bash isn't installed (alpine, slim images) | `docker exec -it alpine sh` |
| As root | `docker exec -u 0 -it CONTAINER sh` | Escalate even when the image has `USER appuser` | `docker exec -u 0 -it web sh` |
| As another user | `docker exec -u 1000:1000 CONTAINER id` | Run as a specific uid:gid | `docker exec -u 1000 web id` |
| With env | `docker exec -e DEBUG=1 CONTAINER env` | Env var for that process only | `docker exec -e LOG=debug web printenv` |
| In a directory | `docker exec -w /app CONTAINER ls` | Sets the working directory | `docker exec -w /app web pwd` |
| Detached | `docker exec -d CONTAINER CMD` | Fire and forget, no output | `docker exec -d web touch /tmp/x` |
| With TTY only | `docker exec -t CONTAINER top` | TTY without keeping stdin | `docker exec -t web top` |
| Privileged | `docker exec --privileged CONTAINER CMD` | Extra capabilities for that process | `docker exec --privileged web tcpdump -i eth0` |
| In a Compose service | `docker compose exec SERVICE CMD` | Same thing, addressed by service name | `docker compose exec api sh` |
| One-off container | `docker compose run --rm SERVICE CMD` | Starts a **new** container from the service definition | `docker compose run --rm api pytest` |

**Inside-the-container toolkit** (what to actually run once you're in):

```sh
whoami; id                          # am I root? what uid?
env | sort                          # the real configuration
pwd; ls -la                         # did COPY land where I think?
cat /etc/os-release                 # which distro / base image
ps aux        # or: ps -ef          # what's PID 1? (busybox: ps -o pid,comm)
netstat -tulpn # or: ss -tulpn      # what's actually listening, on which address?
wget -qO- http://localhost:8000/health    # can it reach ITSELF?
getent hosts db                     # does Docker DNS resolve the service name?
ping -c1 db ; nc -zv db 5432        # reachability + port open?
cat /proc/meminfo ; cat /sys/fs/cgroup/memory.max   # cgroup limits as seen from inside
df -h                               # are the volumes mounted where expected?
mount | grep -E 'app|data'          # ro or rw?
```

> ⚠️ **`exec` needs a RUNNING container.** If yours crash-loops you cannot `exec` in. Use instead:
> ```bash
> docker run --rm -it --entrypoint sh myimage     # explore the image itself
> docker debug <container>                        # ephemeral debug container sharing its namespaces
> docker run -it --rm --pid=container:X --net=container:X nicolaka/netshoot bash
> ```

---

## 6. Container logs — VERY IMPORTANT IN PRODUCTION

Containers should log to **stdout/stderr** (12-factor). `docker logs` reads that stream from the log driver.

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| All logs | `docker logs CONTAINER` | Prints the full stdout/stderr history | `docker logs web` |
| Follow | `docker logs -f CONTAINER` | Tails live; `Ctrl-C` stops following (**not** the container) | `docker logs -f web` |
| Tail | `docker logs --tail 100 CONTAINER` | Last N lines only | `docker logs --tail 200 web` |
| Follow + tail | `docker logs -f --tail 100 CONTAINER` | **The production default** — recent context, then live | `docker logs -f --tail 100 web` |
| Since duration | `docker logs --since 1h CONTAINER` | Everything from the last hour (`10m`, `30s`, `2h`) | `docker logs --since 10m api` |
| Since timestamp | `docker logs --since 2026-09-08T20:00:00 CONTAINER` | Absolute RFC3339 start | `docker logs --since 2026-09-08T09:00:00Z db` |
| Until | `docker logs --until 10m CONTAINER` | Stop 10 minutes ago | `docker logs --since 1h --until 30m api` |
| Timestamps | `docker logs -t CONTAINER` | Prefix each line with the daemon's timestamp | `docker logs -t web` |
| Details | `docker logs --details CONTAINER` | Shows extra log attributes | `docker logs --details web` |
| Restart boundary | `docker logs --since 5m -f CONTAINER` | Combine with `docker restart` to watch a reboot | — |
| Log file location | `docker inspect -f '{{.LogPath}}' CONTAINER` | The actual json-file on the host | `docker inspect -f '{{.LogPath}}' web` |
| Log driver | `docker inspect -f '{{.HostConfig.LogConfig.Type}}' CONTAINER` | Which driver is collecting | `docker inspect -f '{{.HostConfig.LogConfig.Type}}' web` |

> 💀 **The #1 logging mistake:** no rotation. The default `json-file` driver grows **unboundedly** and will fill your disk. Fix it globally in `/etc/docker/daemon.json`:
> ```json
> { "log-driver": "json-file",
>   "log-opts": { "max-size": "10m", "max-file": "3", "compress": "true" } }
> ```
> then `sudo systemctl restart docker`. Per-container: `--log-opt max-size=10m --log-opt max-file=3`. Per-service in Compose: the `logging:` block.

> 🔑 **No logs at all?** Usually one of: the app logs to a *file* instead of stdout · output is buffered (`PYTHONUNBUFFERED=1` fixes Python) · the container died before printing (check `docker inspect --format '{{.State.ExitCode}} {{.State.Error}}'`) · you're looking at the wrong driver (`--log-driver none`).

---

## 7. Inspect / Debug containers — VERY IMPORTANT

`docker inspect` returns the **complete** low-level JSON: config, state, network, mounts, health, restart count. `--format` extracts one field.

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| Full JSON | `docker inspect CONTAINER\|IMAGE\|VOLUME\|NETWORK` | Everything, for containers *and* images *and* volumes | `docker inspect web` |
| Pretty JSON | `docker inspect CONTAINER \| python3 -m json.tool` | Readable instead of one giant line | `docker inspect web \| jq .` |
| Single field | `docker inspect -f '{{.State.Status}}' CONTAINER` | Go template extraction | `docker inspect -f '{{.State.Status}}' web` |
| Exit code | `docker inspect -f '{{.State.ExitCode}}' CONTAINER` | **Why did it die?** | `docker inspect -f '{{.State.ExitCode}}' web` |
| OOM? | `docker inspect -f '{{.State.OOMKilled}}' CONTAINER` | `true` = the cgroup OOM killer struck | `docker inspect -f '{{.State.OOMKilled}}' api` |
| Runtime error | `docker inspect -f '{{.State.Error}}' CONTAINER` | Docker's own failure message | `docker inspect -f '{{.State.Error}}' web` |
| Started/finished | `docker inspect -f '{{.State.StartedAt}} → {{.State.FinishedAt}}' C` | Timeline | — |
| Restart count | `docker inspect -f '{{.RestartCount}}' CONTAINER` | How many times the policy restarted it | `docker inspect -f '{{.RestartCount}}' api` |
| Command | `docker inspect -f '{{json .Config.Cmd}}' IMAGE` | What the image will run | `docker inspect -f '{{json .Config.Cmd}}' myapp` |
| Entrypoint | `docker inspect -f '{{json .Config.Entrypoint}}' IMAGE` | Shell vs exec form is visible here | `docker inspect -f '{{json .Config.Entrypoint}}' myapp` |
| User | `docker inspect -f '{{.Config.User}}' IMAGE` | Empty = **root** ⚠️ | `docker inspect -f '{{.Config.User}}' myapp` |
| Env | `docker inspect -f '{{json .Config.Env}}' IMAGE` | Every baked-in ENV (and any leaked secret!) | `docker inspect -f '{{json .Config.Env}}' myapp` |
| Working dir | `docker inspect -f '{{.Config.WorkingDir}}' IMAGE` | The effective `WORKDIR` | — |
| Exposed ports | `docker inspect -f '{{json .Config.ExposedPorts}}' IMAGE` | What `EXPOSE` declared | — |
| Health | `docker inspect -f '{{json .State.Health}}' CONTAINER` | Status, failing streak, last 5 check results | `docker inspect -f '{{.State.Health.Status}}' api` |
| IP address | `docker inspect -f '{{.NetworkSettings.IPAddress}}' C` | Only set on the **default** bridge | — |
| IP on a network | `docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' C` | Works on user-defined networks | see below |
| Networks | `docker inspect -f '{{json .NetworkSettings.Networks}}' C` | Every attached network + its config | — |
| Mounts | `docker inspect -f '{{json .Mounts}}' CONTAINER` | Volumes/bind mounts: source, destination, mode (rw/ro) | — |
| Limits | `docker inspect -f '{{.HostConfig.Memory}} {{.HostConfig.NanoCpus}}' C` | Effective resource limits in bytes / nanocpus | — |
| Read-only? | `docker inspect -f '{{.HostConfig.ReadonlyRootfs}}' C` | Root filesystem immutability | — |
| Capabilities | `docker inspect -f '{{json .HostConfig.CapDrop}}' C` | What was dropped | — |
| Log path | `docker inspect -f '{{.LogPath}}' CONTAINER` | Host file with the raw logs | — |
| Processes | `docker top CONTAINER` | Host-visible process list (real PIDs!) | `docker top web` |
| Live resources | `docker stats` | Streaming CPU / MEM / NET / BLOCK I/O per container | `docker stats` |
| One-shot stats | `docker stats --no-stream` | Single snapshot — scriptable | `docker stats --no-stream --format '{{.Name}} {{.MemUsage}}'` |
| Specific stats | `docker stats web api` | Only the containers you name | `docker stats api` |
| File changes | `docker diff CONTAINER` | Files **A**dded / **C**hanged / **D**eleted vs the image | `docker diff web` |
| Port mappings | `docker port CONTAINER` | Host ↔ container port table | `docker port web` |
| Events | `docker events` | Live daemon event stream (create/start/die/oom/…) | `docker events --filter type=container` |
| Debug container | `docker debug CONTAINER` | Ephemeral toolbelt container sharing PID+net namespaces | `docker debug --image nicolaka/netshoot web` |

```bash
# the four one-liners that answer 90% of "why is this broken?"
docker inspect -f 'status={{.State.Status}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}} restarts={{.RestartCount}} err={{.State.Error}}' web
docker inspect -f '{{range .NetworkSettings.Networks}}net={{.NetworkID}} ip={{.IPAddress}} gw={{.Gateway}}{{println}}{{end}}' web
docker inspect -f '{{range .Mounts}}{{.Type}} {{.Source}} -> {{.Destination}} ({{if .RW}}rw{{else}}ro{{end}}){{println}}{{end}}' web
docker inspect -f 'cmd={{json .Config.Cmd}} entry={{json .Config.Entrypoint}} user={{.Config.User}} wd={{.Config.WorkingDir}}' myimage
```

---

## 8. Copy files

`docker cp` works on **running and stopped** containers, in both directions, and preserves UID/GID.

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| Container → host | `docker cp CONTAINER:SRC DEST` | Pull a file/dir out | `docker cp web:/app/log.txt .` |
| Host → container | `docker cp SRC CONTAINER:DEST` | Push a file/dir in | `docker cp config.yml web:/app/` |
| Directory | `docker cp ./app web:/opt/` | Recursive by default | `docker cp ./site web:/usr/share/nginx/html/` |
| From a stopped container | `docker cp deadbox:/app/out.json .` | Works even if it exited | `docker cp $(docker ps -alq):/tmp/x .` |
| Archive (no auto-extract) | `docker cp backup.tar db:/tmp/` | Tarballs are copied as files — **`docker cp` does not extract** | `docker cp app.tar.gz web:/tmp/` |
| Follow symlinks | `docker cp -L web:/link/file .` | Copy the target, not the link | `docker cp -L web:/etc/localtime .` |
| Quiet | `docker cp -q ...` | Suppress progress | — |
| Stream from stdin | `tar c files \| docker cp - web:/dest` | `-` means read a tar stream | `tar czf - dir \| docker cp - web:/tmp/` |
| Stream to stdout | `docker cp web:/dir - \| tar xzf -` | `-` as destination writes a tar stream | `docker cp db:/var/lib/mysql - > db.tar` |
| From an image (no container) | `docker create IMG && docker cp c:/f . && docker rm c` | Images can't be `cp`'d directly — create a throwaway container | see snippet below |

```bash
# extract a file straight out of an IMAGE (very useful for debugging)
cid=$(docker create --rm myimage:1.0)
docker cp "$cid":/app/config.json ./config.json
docker rm "$cid"

# alternative without creating anything:
docker run --rm --entrypoint cat myimage:1.0 /app/config.json > config.json
```

> ⚠️ **Trailing-slash semantics differ from `cp -r`:**
> `docker cp web:/app ./out` → if `./out` doesn't exist, it becomes **a copy of `/app`**. If `./out` exists as a directory, you get `./out/app`. Add `/.` to copy *contents*: `docker cp web:/app/. ./out`.

---

## 9. Remove containers

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| Remove | `docker rm CONTAINER` | Removes a **stopped** container | `docker rm web` |
| Force remove | `docker rm -f CONTAINER` | Stops + removes a running one | `docker rm -f web` |
| Remove + anonymous volumes | `docker rm -v CONTAINER` | Deletes attached **anonymous** volumes too | `docker rm -v web` |
| Remove several | `docker rm web api db` | Multiple targets in one call | `docker rm $(docker ps -aq)` |
| Remove all stopped | `docker container prune` | Every exited container (prompts first) | `docker container prune` |
| Prune forced | `docker container prune -f` | No prompt — CI-friendly | `docker container prune -f` |
| Prune by age | `docker container prune -f --filter until=24h` | Only containers older than 24 h | `docker container prune -f --filter until=1h` |
| Prune by label | `docker container prune -f --filter label=ci=true` | Only labelled ones | `docker container prune -f --filter label!=keep` |

> 🔑 **`docker rm` fails with "container is running"** → use `-f`, or `docker stop` first.
> **`docker rm` fails with "image is being used by stopped container"** → that's `docker rmi` complaining; remove the containers first, or use `docker rmi -f`.

---

## 10. Docker images — MOST IMPORTANT

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| List | `docker images` | Local images: repo, tag, ID, age, size | `docker images` |
| Modern form | `docker image ls` | Identical, object-oriented syntax | `docker image ls` |
| Include intermediates | `docker images -a` | Also shows intermediate/build layers | `docker images -a` |
| Quiet | `docker images -q` | IDs only | `docker rmi $(docker images -q)` |
| Digests | `docker images --digests` | Shows the registry content digest | `docker images --digests nginx` |
| Full IDs | `docker images --no-trunc` | Un-truncated 64-char IDs | `docker images --no-trunc` |
| Filter | `docker images -f FILTER` | dangling / reference / label / before / since | `docker images -f dangling=true` |
| Format | `docker images --format '{{.Repository}}:{{.Tag}} {{.Size}}'` | Custom columns | see [§45](#45-go-template---format-recipes) |
| Pull | `docker pull IMAGE` | Download from a registry | `docker pull nginx:1.29-alpine` |
| Pull platform | `docker pull --platform linux/amd64 IMAGE` | Force an architecture | `docker pull --platform linux/arm64 alpine` |
| Pull all tags | `docker pull -a IMAGE` | Every tag of that repository | `docker pull -a redis` |
| Pull quietly | `docker pull -q IMAGE` | Suppress progress | `docker pull -q nginx` |
| Inspect | `docker image inspect IMAGE` | Full config JSON: env, cmd, layers, arch, os | `docker image inspect nginx` |
| Architecture | `docker image inspect -f '{{.Os}}/{{.Architecture}}' IMAGE` | **The `exec format error` diagnostic** | `docker image inspect -f '{{.Os}}/{{.Architecture}}' app` |
| Layers | `docker image inspect -f '{{len .RootFS.Layers}}' IMAGE` | Layer count | `docker image inspect -f '{{len .RootFS.Layers}}' app` |
| Size | `docker image inspect -f '{{.Size}}' IMAGE` | Bytes | `docker image inspect -f '{{.Size}}' app` |
| History | `docker history IMAGE` | Every layer, its size, and the command that made it | `docker history nginx` |
| History readable | `docker history --human --format 'table {{.Size}}\t{{.CreatedBy}}' IMAGE` | Where the megabytes went | `docker history --human app` |
| History full | `docker history --no-trunc IMAGE` | Untruncated commands — **how you audit a third-party image for leaked secrets** | `docker history --no-trunc app \| grep -i pass` |
| Tag | `docker tag SRC DST` | Adds another name pointing to the same image ID | `docker tag app:1.0 me/app:1.0` |
| Remove | `docker rmi IMAGE` | Deletes a local image (by name:tag or ID) | `docker rmi nginx` |
| Force remove | `docker rmi -f IMAGE` | Untags even if a container references it | `docker rmi -f app` |
| Remove many | `docker rmi a b c` | Multiple references | `docker rmi $(docker images -q)` |
| Export image | `docker save IMAGE -o FILE.tar` | Full image with **all layers + metadata** → portable to another daemon | `docker save nginx -o nginx.tar` |
| Import image | `docker load -i FILE.tar` | Restores a `save`d image | `docker load -i nginx.tar` |
| Stream save/load | `docker save IMAGE \| ssh host docker load` | Transfer without touching disk | `docker save app \| gzip \| ssh h 'gunzip \| docker load'` |
| Export container FS | `docker export CONTAINER -o FILE.tar` | Flat filesystem snapshot — **loses history, ENV, CMD, layers** | `docker export web -o web.tar` |
| Import to image | `docker import FILE.tar IMAGE` | Turns an exported FS into an image | `docker import rootfs.tar myimage:1.0` |
| Scan | `docker scout cves IMAGE` | Vulnerability report | `docker scout cves app:1.0` |

> 🔑 **`save`/`load` vs `export`/import`** — a classic interview question:
>
> | | `docker save` / `load` | `docker export` / `import` |
> |---|---|---|
> | Operates on | an **image** | a **container** |
> | Keeps | all layers, history, tags, `ENV`, `CMD`, `ENTRYPOINT`, `EXPOSE` | only the flattened filesystem |
> | Result size | larger | smaller |
> | Use when | moving an image to an air-gapped machine | capturing the *current state* of a container you modified by hand |
> | Restored image runs? | ✅ exactly as before | ⚠️ you must re-specify `CMD` (`docker import --change 'CMD ["/app"]'`) |

---

## 11. Image filtering / cleanup

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| Dangling | `docker images -f dangling=true` | Untagged images (`<none>:<none>`) left behind by rebuilds | `docker images -f dangling=true` |
| By reference | `docker images -f reference='nginx:*'` | Glob on repo:tag | `docker images -f reference='app:1.*'` |
| By label | `docker images -f label=stage=prod` | Image labels | `docker images -f label=maintainer=me` |
| Before/since | `docker images -f before=app:1.0` | Relative age | `docker images -f since=alpine` |
| Prune dangling | `docker image prune` | Removes `<none>` images (safe) | `docker image prune -f` |
| Prune all unused | `docker image prune -a` | Removes **every** image not used by a container ⚠️ | `docker image prune -af` |
| Prune by age | `docker image prune -af --filter until=168h` | Only images older than 7 days | `docker image prune -af --filter until=24h` |
| Prune by label | `docker image prune -af --filter label!=keep` | Keep what you labelled | — |

> ⚠️ **`docker image prune -a` on a laptop means re-pulling everything next time you build.** On CI runners it's exactly what you want. Know which machine you're on.

---

## 12. Build images — VERY IMPORTANT

```
docker build [OPTIONS] PATH | URL | -
                     └── the BUILD CONTEXT
```

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| Basic | `docker build .` | Builds from the `Dockerfile` in the current context | `docker build .` |
| Tag | `docker build -t NAME:TAG .` | Names the result (always do this) | `docker build -t myapp:1.0 .` |
| Multiple tags | `docker build -t app:1.0 -t app:latest .` | One build, several references | `docker build -t app:1.0 -t app:latest .` |
| Specific file | `docker build -f FILE .` | Use a non-default Dockerfile (context stays `.`) | `docker build -f Dockerfile.prod -t app:prod .` |
| No cache | `docker build --no-cache -t app .` | Ignore every cached layer — rebuild from zero | `docker build --no-cache -t app .` |
| Force-pull base | `docker build --pull -t app .` | Re-pull the `FROM` images even if present locally | `docker build --pull -t app .` |
| Build arg | `docker build --build-arg K=V -t app .` | Supplies a Dockerfile `ARG` | `docker build --build-arg VERSION=1.2 -t app .` |
| Arg from env | `docker build --build-arg VERSION -t app .` | Forwards the host variable of that name | `docker build --build-arg HTTP_PROXY -t app .` |
| Stage target | `docker build --target STAGE -t app .` | Stop at a named multi-stage stage — **essential for debugging** | `docker build --target builder -t app:debug .` |
| Verbose output | `docker build --progress=plain .` | Full BuildKit logs, no collapsing — the debugging default | `docker build --progress=plain --no-cache .` |
| TTY output | `docker build --progress=tty .` | Pretty collapsing output (the default) | — |
| Quiet | `docker build -q -t app .` | Prints only the final image ID — great in scripts | `IMG=$(docker build -q .)` |
| Platform | `docker build --platform linux/amd64 -t app .` | Build for another architecture (via QEMU) | `docker build --platform linux/arm64 -t app .` |
| Secret | `docker build --secret id=X,src=FILE .` | File mounted at `/run/secrets/X` for one `RUN`; **never stored in a layer** | `docker build --secret id=aws,src=$HOME/.aws/credentials .` |
| Env secret | `docker build --secret id=X,env=VAR .` | Secret from an environment variable | `docker build --secret id=tok,env=GH_TOKEN .` |
| SSH agent | `docker build --ssh default .` | Forward your SSH agent so `RUN git clone git@…` works without baking keys | `docker build --ssh default -t app .` |
| Network mode | `docker build --network=host .` | Build-time `RUN` uses host networking (corp proxies, local registries) | `docker build --network=host .` |
| Isolated network | `docker build --network=none .` | No internet during the build — proves reproducibility | `docker build --network=none .` |
| Labels | `docker build --label k=v -t app .` | Adds image labels without editing the Dockerfile | `docker build --label build=ci -t app .` |
| Cache from | `docker build --cache-from type=registry,ref=me/app:cache .` | Reuse cache exported elsewhere (CI) | `--cache-from type=gha` |
| Cache to | `docker build --cache-to type=registry,ref=me/app:cache,mode=max .` | Export the cache for the next build | `--cache-to type=gha,mode=max` |
| Dockerfile from stdin | `cat Dockerfile \| docker build -t app -` | `-` as the context/Dockerfile source | `docker build -t app - < Dockerfile.prod` |
| Remote context | `docker build -t app https://github.com/me/repo.git#branch:dir` | Build straight from a Git URL | `docker build -t app github.com/me/app#v1.0:docker` |
| Squash (experimental) | `docker build --squash -t app .` | Collapse all new layers into one | requires `experimental: true` |
| BuildKit toggle | `DOCKER_BUILDKIT=1 docker build .` | Force BuildKit on old Docker (<23) | `DOCKER_BUILDKIT=1 docker build --progress=plain .` |

**The three build-debugging commands, in order:**

```bash
docker build --progress=plain --no-cache -t app .   # 1. see EVERY line, no cache lies
docker build --target builder -t app:debug .        # 2. stop before the failure and go inside
docker run --rm -it --entrypoint sh app:debug       # 3. poke around the intermediate filesystem
```

---

## 13. Docker Buildx

Buildx is the extended builder: multi-platform images, remote/clustered builders, real cache import/export, and `bake` for reproducible multi-image builds. It's what CI uses.

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| Version | `docker buildx version` | Buildx plugin version | `docker buildx version` |
| List builders | `docker buildx ls` | All builder instances, their drivers and supported platforms | `docker buildx ls` |
| Create builder | `docker buildx create --name multiarch` | New builder (docker-container driver by default) | `docker buildx create --name multiarch --driver docker-container` |
| Create + use | `docker buildx create --use --name b1` | Create and immediately select | `docker buildx create --use --name ci` |
| Use | `docker buildx use NAME` | Switch the active builder | `docker buildx use multiarch` |
| Inspect | `docker buildx inspect` | Builder details + platform list | `docker buildx inspect` |
| Bootstrap | `docker buildx inspect --bootstrap` | Starts the builder container (needed once) | `docker buildx inspect --bootstrap` |
| Build | `docker buildx build -t app:1.0 .` | Build with Buildx | `docker buildx build -t app:1.0 .` |
| Load locally | `docker buildx build --load -t app .` | Put the result into your local image store (single-platform only) | `docker buildx build --load -t app:1.0 .` |
| Push | `docker buildx build --push -t REG/APP:TAG .` | Build and push in one step (required for multi-platform) | `docker buildx build --push -t ghcr.io/me/app:1.0 .` |
| Multi-platform | `docker buildx build --platform linux/amd64,linux/arm64 ...` | One tag, several architectures (a manifest list) | `docker buildx build --platform linux/amd64,linux/arm64 -t me/app:1.0 --push .` |
| Three platforms | `--platform linux/amd64,linux/arm64,linux/arm/v7` | Add ARMv7 for Raspberry Pi | — |
| OCI layout | `docker buildx build -o type=oci,dest=app.tar .` | Export an OCI image archive instead of pushing | `docker buildx build -o type=docker,dest=app.tar .` |
| Registry cache | `--cache-from type=registry,ref=me/app:cache --cache-to type=registry,ref=me/app:cache,mode=max` | Share cache through the registry | — |
| GitHub Actions cache | `--cache-from type=gha --cache-to type=gha,mode=max` | Cache in the GHA runner | — |
| Local cache dir | `--cache-from type=local,src=/tmp/.buildx --cache-to type=local,dest=/tmp/.buildx` | Cache on disk (GitLab/self-hosted) | — |
| Secrets | `--secret id=mysecret,src=./secret.txt` | Same as `docker build --secret` | — |
| SSH | `--ssh default` | Agent forwarding for private repos | — |
| Attestations | `--provenance=true --sbom=true` | Attach build provenance + an SBOM to the image | `docker buildx build --provenance --sbom --push -t me/app .` |
| QEMU install | `docker run --privileged --rm tonistiigi/binfmt --install all` | Enables cross-arch emulation on a runner | — |
| Bake (file) | `docker buildx bake -f docker-bake.hcl` | Build many targets in parallel from one definition | `docker buildx bake --push` |
| Bake from Compose | `docker buildx bake -f docker-compose.yml` | Compose files are valid bake definitions | `docker buildx bake -f compose.yml --set *.platform=linux/amd64` |
| Bake list targets | `docker buildx bake --print` | Show the resolved bake config | `docker buildx bake --print api web` |
| Remove builder | `docker buildx rm NAME` | Delete a builder and its cache | `docker buildx rm multiarch` |
| Prune cache | `docker buildx prune` | Clears BuildKit cache for the current builder | `docker buildx prune -af` |
| Inspect a pushed manifest | `docker buildx imagetools inspect REG/APP:TAG` | See every platform in a manifest list — **modern replacement for `docker manifest inspect`** | `docker buildx imagetools inspect me/app:1.0` |

```bash
# the complete multi-arch ceremony (memorise for CI)
docker run --privileged --rm tonistiigi/binfmt --install all
docker buildx create --use --name multiarch --driver docker-container
docker buildx inspect --bootstrap
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --cache-from type=gha --cache-to type=gha,mode=max \
  --provenance --sbom \
  -t ghcr.io/me/app:1.0.0 -t ghcr.io/me/app:latest \
  --push .
docker buildx imagetools inspect ghcr.io/me/app:1.0.0
```

> ⚠️ **`--load` cannot load a multi-platform image** into the local store (the store holds one architecture). Use `--push`, or build `--platform` for a single arch when you want it locally.

---

## 14. Docker Registry / Docker Hub

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| Login (Hub) | `docker login` | Prompts for username + **token/password** | `docker login` |
| Login (registry) | `docker login REGISTRY` | Authenticate against a specific registry | `docker login ghcr.io` |
| Non-interactive | `echo $TOKEN \| docker login -u USER --password-stdin REG` | **The CI way** — no password in shell history or `ps` | `echo "$GH_PAT" \| docker login ghcr.io -u me --password-stdin` |
| Logout | `docker logout [REGISTRY]` | Removes stored credentials | `docker logout ghcr.io` |
| Tag for registry | `docker tag app:1.0 REG/USER/app:1.0` | Adds the registry-qualified name | `docker tag app:1.0 ghcr.io/me/app:1.0` |
| Push | `docker push REG/USER/app:1.0` | Upload the image | `docker push ghcr.io/me/app:1.0` |
| Push all tags | `docker push -a REG/USER/app` | Every local tag of that repo | `docker push -a me/app` |
| Pull | `docker pull REG/USER/app:1.0` | Download | `docker pull ghcr.io/me/app:1.0` |
| Search Hub | `docker search TERM` | Searches **Docker Hub only** | `docker search redis` |
| Search filtered | `docker search --filter stars=100 nginx` | Minimum stars / official only | `docker search --filter is-official=true nginx` |
| Manifest inspect | `docker manifest inspect IMAGE` | Manifest / platform variants (experimental feature) | `docker manifest inspect nginx:latest` |
| Manifest create | `docker manifest create LIST IMG...` | Assemble a manifest list by hand | `docker manifest create app:latest app:amd64 app:arm64` |
| Manifest annotate | `docker manifest annotate LIST IMG --arch X` | Attach platform metadata | `docker manifest annotate app:latest app:arm64 --arch arm64` |
| Manifest push | `docker manifest push LIST` | Publish the list | `docker manifest push app:latest` |
| Content trust | `export DOCKER_CONTENT_TRUST=1` | Require signed images (Notary) | `DOCKER_CONTENT_TRUST=1 docker pull app` |
| Sign | `docker trust sign REG/APP:TAG` | Sign a tag | `docker trust sign me/app:1.0` |
| Inspect signatures | `docker trust inspect --pretty REG/APP:TAG` | Who signed it | `docker trust inspect --pretty me/app:1.0` |
| Cosign (modern) | `cosign sign --key cosign.key REG/APP@DIGEST` | Sigstore signing — what CI actually uses today | `cosign verify --certificate-identity ... REG/APP` |

**Run your own registry in 30 seconds:**

```bash
docker run -d --name registry -p 5000:5000 -v registry-data:/var/lib/registry \
  --restart unless-stopped registry:2
docker tag app:1.0 localhost:5000/app:1.0
docker push localhost:5000/app:1.0
curl -s localhost:5000/v2/_catalog
curl -s localhost:5000/v2/app/tags/list
```

> 🔑 **Naming rules:** `docker push` requires the tag to start with the registry host (`ghcr.io/…`, `123456789.dkr.ecr.us-east-1.amazonaws.com/…`) or a `USER/` prefix for Docker Hub. No host and no slash = Docker Hub library image, which you can't push to.

---

## 15. Docker networking

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| List | `docker network ls` | All networks (bridge, host, none + your own) | `docker network ls` |
| Inspect | `docker network inspect NET` | Config **and every connected container with its IP** | `docker network inspect app-net` |
| Just the containers | `docker network inspect -f '{{range .Containers}}{{.Name}} {{end}}' NET` | Who's on this network | see below |
| Create | `docker network create NAME` | New **user-defined bridge** → DNS by container name works | `docker network create app-net` |
| Driver | `docker network create -d DRIVER NAME` | `bridge` \| `host` \| `overlay` \| `macvlan` \| `none` \| plugin | `docker network create -d overlay prod-net` |
| Subnet | `docker network create --subnet CIDR NAME` | Fixed address space (avoids collisions with your VPN) | `docker network create --subnet 172.20.0.0/16 app-net` |
| Gateway | `docker network create --gateway IP NAME` | Explicit gateway | `docker network create --subnet 172.20.0.0/16 --gateway 172.20.0.1 app-net` |
| IP range | `docker network create --ip-range CIDR NAME` | Restrict dynamic allocation | `docker network create --subnet 172.20.0.0/16 --ip-range 172.20.5.0/24 app-net` |
| Internal only | `docker network create --internal NAME` | **No outbound internet** — great for DB tiers | `docker network create --internal db-net` |
| IPv6 | `docker network create --ipv6 --subnet fd00::/64 NAME` | Enable IPv6 | — |
| DNS options | `docker network create --opt com.docker.network.bridge.name=br-app NAME` | Low-level bridge options | — |
| Static IP | `docker run --network NET --ip IP IMAGE` | Pin a container's address | `docker run -d --network app-net --ip 172.20.0.10 nginx` |
| Connect | `docker network connect NET CONTAINER` | Attach a **running** container to another network | `docker network connect app-net web` |
| Connect with alias | `docker network connect --alias api NET CONTAINER` | Extra DNS name on that network | `docker network connect --alias api-v2 app-net web` |
| Disconnect | `docker network disconnect NET CONTAINER` | Detach | `docker network disconnect app-net web` |
| Force disconnect | `docker network disconnect -f NET CONTAINER` | Even if the container is gone | — |
| Remove | `docker network rm NET` | Deletes a network (must be empty) | `docker network rm app-net` |
| Prune | `docker network prune` | Removes unused custom networks | `docker network prune -f` |
| Prune by age | `docker network prune -f --filter until=24h` | Only older ones | — |
| Host networking | `docker run --network host IMAGE` | No isolation — shares the host's stack. `-p` is ignored. | `docker run --network host nginx` |
| No networking | `docker run --network none IMAGE` | Loopback only. Total isolation. | `docker run --network none alpine ip a` |
| Container networking | `docker run --network container:OTHER IMAGE` | Shares another container's net namespace (sidecars, debug pods) | `docker run --network container:web nicolaka/netshoot` |

```bash
# the DNS + isolation demo every beginner should run once
docker network create demo
docker run -d --name a --network demo alpine sleep 300
docker run -d --name b --network demo alpine sleep 300
docker exec b ping -c1 a                  # ✅ resolves by NAME
docker exec b getent hosts a              # → its IP
docker run -d --name c alpine sleep 300   # default bridge
docker exec c ping -c1 a                  # ❌ unresolvable — different network
docker network connect demo c && docker exec c ping -c1 a   # ✅ now it works
docker network inspect demo -f '{{range .Containers}}{{.Name}}={{.IPv4Address}} {{end}}'
docker rm -f a b c && docker network rm demo
```

> 🔑 **Interview point:** containers on the **same user-defined bridge network** resolve each other by **container name / alias** via Docker's embedded DNS (`127.0.0.11`). Never hard-code IPs — they change on every restart. The **default** `bridge` network does *not* do DNS by name (only `--link`, which is deprecated), which is why you should always create your own network.

---

## 16. Port mapping

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| Host → container | `-p HOST:CONTAINER` | Publishes a container port on all host interfaces (`0.0.0.0`) | `docker run -p 8080:80 nginx` |
| Localhost only | `-p 127.0.0.1:HOST:CONTAINER` | **Binds to loopback only** — not reachable from your LAN | `docker run -p 127.0.0.1:8080:80 nginx` |
| Specific interface | `-p IP:HOST:CONTAINER` | Bind to one host IP (multi-NIC servers) | `docker run -p 10.0.0.5:8080:80 nginx` |
| TCP explicit | `-p HOST:CONTAINER/tcp` | TCP is the default; be explicit for clarity | `docker run -p 8080:80/tcp nginx` |
| UDP | `-p HOST:CONTAINER/udp` | For DNS, metrics, game servers, QUIC | `docker run -p 5353:53/udp dns` |
| Both | `-p 53:53/tcp -p 53:53/udp` | Publish the same port over both protocols | — |
| Random host port | `-p CONTAINER_PORT` | Docker picks a free ephemeral host port | `docker run -p 80 nginx` |
| Port range | `-p 8000-8010:8000-8010` | Publish a range | `docker run -p 6000-6100:6000-6100 app` |
| Publish all exposed | `-P` | Every `EXPOSE`d port → a random host port | `docker run -P nginx` |
| Multiple | `-p 8080:80 -p 8443:443` | Repeat the flag | `docker run -p 8080:80 -p 9000:9000 app` |
| View mapping | `docker port CONTAINER` | Shows host ↔ container for each port | `docker port web` |
| View one | `docker port CONTAINER 80/tcp` | Mapping for a specific container port | `docker port web 80` |
| From inspect | `docker inspect -f '{{json .NetworkSettings.Ports}}' C` | The raw binding table | — |

```bash
# the classic error and its fix
docker run -d -p 8080:80 nginx
docker run -d -p 8080:80 nginx
# → Error response from daemon: driver failed programming external connectivity:
#   Bind for 0.0.0.0:8080 failed: port is already allocated
docker ps -a --filter publish=8080        # who has it?
docker rm -f <that container>             # free it
```

> 🔑 **`EXPOSE` ≠ `-p`.** `EXPOSE` in a Dockerfile is documentation (it affects `-P` and container-to-container discovery). Only `-p` makes a port reachable from your host/browser. Proven hands-on in [`05-PROJECT-2-static-site.md`](05-PROJECT-2-static-site.md) §4.
>
> 🔑 **The app must bind to `0.0.0.0`, not `127.0.0.1`.** If it listens on loopback *inside* the container, `-p` maps to nothing and you get "connection refused" — the most common Docker networking bug after `localhost` misuse.

---

## 17. Docker volumes / storage

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| List | `docker volume ls` | All volumes (named + anonymous) | `docker volume ls` |
| Filter | `docker volume ls -f dangling=true` | Unused volumes — the usual disk-space culprit | `docker volume ls -f dangling=true` |
| By name | `docker volume ls -q -f name=myapp` | Quiet + filtered for scripts | — |
| Create | `docker volume create NAME` | Explicit named volume | `docker volume create db-data` |
| With driver | `docker volume create -d local NAME` | Specify the driver | `docker volume create -d local db-data` |
| With options | `docker volume create --opt type=none --opt device=/srv/data --opt o=bind NAME` | A named volume backed by a specific host path (bind-mount semantics, volume lifecycle) | see below |
| NFS volume | `docker volume create --driver local --opt type=nfs --opt o=addr=10.0.0.1,rw --opt device=:/exported/path nfs-data` | Mount NFS through the local driver | — |
| Inspect | `docker volume inspect NAME` | Driver, options, and **`Mountpoint`** (host path) | `docker volume inspect db-data` |
| Mountpoint only | `docker volume inspect -f '{{.Mountpoint}}' NAME` | Where it lives on the host | `docker volume inspect -f '{{.Mountpoint}}' db-data` |
| Remove | `docker volume rm NAME` | ☠️ **Deletes the data permanently** | `docker volume rm db-data` |
| Remove several | `docker volume rm a b c` | Multiple names | `docker volume rm $(docker volume ls -qf dangling=true)` |
| Prune | `docker volume prune` | Removes volumes not used by any container ⚠️ | `docker volume prune -f` |
| Prune anonymous only | `docker volume prune -a --filter all=0` | Modern Docker: keep named volumes | `docker volume prune --filter label!=keep` |
| Named volume mount | `-v NAME:/container/path` | Docker-managed persistent storage | `docker run -v db-data:/var/lib/mysql postgres` |
| Bind mount | `-v /host/path:/container/path` | Your real host directory | `docker run -v /srv/html:/usr/share/nginx/html:ro nginx` |
| Relative bind | `-v $(pwd)/src:/app/src` | Current folder (use `$PWD` in compose) | `docker run -v "$PWD":/app node` |
| Read-only | `-v SRC:DST:ro` | Container can read but not write | `docker run -v $(pwd)/conf:/etc/app:ro app` |
| Writable override | `-v SRC:DST:rw` | Explicit read-write (the default) | — |
| SELinux relabel | `-v SRC:DST:z` / `:Z` | Fixes "permission denied" on RHEL/Fedora | `docker run -v $(pwd):/app:z app` |
| `--mount` volume | `--mount type=volume,source=NAME,target=/data` | Explicit; fails if the volume doesn't exist and `volume-nocopy` is set | `docker run --mount type=volume,src=db,dst=/var/lib/mysql postgres` |
| `--mount` bind | `--mount type=bind,source=$PWD,target=/app,readonly` | **Errors immediately if the source path is missing** (unlike `-v`, which silently creates a directory) | `docker run --mount type=bind,src=$PWD/app,dst=/app app` |
| `--mount` tmpfs | `--mount type=tmpfs,target=/tmp,tmpfs-size=100m` | RAM-backed scratch space | `docker run --read-only --mount type=tmpfs,dst=/tmp app` |
| Anonymous volume | `-v /container/path` (no source) | Docker creates a random-named volume | `docker run -v /var/lib/mysql postgres` |
| Volume from container | `--volumes-from CONTAINER` | Share another container's mounts | `docker run --volumes-from db-data-holder alpine ls /data` |
| Inspect mounts | `docker inspect -f '{{json .Mounts}}' CONTAINER` | Every mount: type, source, destination, RW | — |
| Read a volume without a container | `docker run --rm -v NAME:/d alpine ls -la /d` | The standard "what's in my volume?" trick | `docker run --rm -v db-data:/d alpine cat /d/notes.json` |
| Back up a volume | `docker run --rm -v NAME:/data -v $(pwd):/backup alpine tar czf /backup/name.tgz -C /data .` | Portable volume backup | see [§40 scenario 5](#40-real-time-scenario-container-is-down) |
| Restore a volume | `docker run --rm -v NAME:/data -v $(pwd):/backup alpine tar xzf /backup/name.tgz -C /data` | Undo the above | — |
| Storage driver | `docker info -f '{{.Driver}}'` | `overlay2` on every modern install | `docker info -f '{{.Driver}}'` |

```bash
# a named volume pinned to a specific host directory (best of both worlds)
docker volume create --driver local \
  --opt type=none --opt device=/srv/mydata --opt o=bind \
  app-data
docker run -d -v app-data:/app/data myapp
# → Docker-managed lifecycle (prune/inspect/rm) + a predictable host path
```

> 🔑 **`-v` vs `--mount` — which to use?**
> | | `-v` / `--volume` | `--mount` |
> |---|---|---|
> | Syntax | `src:dst[:opts]` — terse | `type=…,source=…,target=…` — explicit |
> | Missing host path | **silently creates** an empty directory | **errors out** |
> | Missing named volume | creates it (pre-populated from the image) | creates it |
> | Best for | quick runs, bind-mounting the cwd | Compose/production, where a typo must fail loudly |
>
> Docker's own docs recommend `--mount` for new work. In Compose, the `volumes:` list uses `-v` syntax and the `mounts`/long-form uses `--mount` semantics.

> ⚠️ **Anonymous volumes leak.** Every `docker run` of an image with a `VOLUME` instruction creates one with a 64-hex-char name, and `docker rm` doesn't delete it. That's how a laptop ends up with 40 GB of orphaned volumes. Audit with `docker volume ls -f dangling=true` and `docker system df -v`.

---

## 18. Resource limits

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| Memory (hard) | `--memory` / `-m` | Hard ceiling → exceeding it triggers the **OOM killer** (exit 137) | `docker run -m 512m app` |
| Memory (soft) | `--memory-reservation` | Soft limit honoured under host memory pressure | `docker run -m 1g --memory-reservation 512m app` |
| Memory + swap | `--memory-swap` | Total of memory **and** swap. `-m 512m --memory-swap 512m` = **swap disabled** | `docker run -m 512m --memory-swap 1g app` |
| Swappiness | `--memory-swappiness 0` | 0 = avoid swapping entirely | `docker run -m 1g --memory-swappiness 0 app` |
| Kernel memory | `--kernel-memory` | Kernel-only memory cap | `docker run -m 1g --kernel-memory 128m app` |
| OOM score | `--oom-score-adj -500` | Make this container less likely to be killed | `docker run --oom-score-adj=-500 db` |
| Disable OOM kill | `--oom-kill-disable` | Container hangs instead of dying. ⚠️ Dangerous — use only with `-m` | `docker run -m 512m --oom-kill-disable app` |
| CPUs (fractional) | `--cpus` | CPU quota in cores; **throttles**, never kills | `docker run --cpus=1.5 app` |
| CPU shares | `--cpu-shares` | Relative weight under contention (default 1024) | `docker run --cpu-shares=512 app` |
| CPU period | `--cpu-period` | CFS period in µs (default 100000) | `docker run --cpu-period=100000 app` |
| CPU quota | `--cpu-quota` | µs of CPU per period. `quota/period = cpus` | `docker run --cpu-quota=50000 app` → 0.5 CPU |
| Pin cores | `--cpuset-cpus` | Restrict to specific cores (NUMA, latency-sensitive work) | `docker run --cpuset-cpus="0,1" app` |
| Pin NUMA nodes | `--cpuset-mems` | Restrict memory nodes | `docker run --cpuset-mems="0" app` |
| PID limit | `--pids-limit` | Fork-bomb protection | `docker run --pids-limit=200 app` |
| Block IO weight | `--blkio-weight` | Relative disk priority (10–1000) | `docker run --blkio-weight=500 app` |
| Device read bps | `--device-read-bps` | Cap read throughput on a device | `docker run --device-read-bps /dev/sda:10mb app` |
| Device write bps | `--device-write-bps` | Cap write throughput | `docker run --device-write-bps /dev/sda:5mb app` |
| Device read IOPS | `--device-read-iops` | Cap read IOPS | — |
| Ulimits | `--ulimit nofile=65535:65535` | Soft:hard limits (Cassandra, Elasticsearch, MongoDB need this) | `docker run --ulimit nofile=100000:100000 cassandra` |
| Ulimit nproc | `--ulimit nproc=8192:8192` | Max processes | `docker run --ulimit nproc=8192 app` |
| Change live | `docker update --cpus 2 --memory 1g CONTAINER` | Adjust a **running** container without a restart | `docker update --memory 1g --memory-swap 1g api` |
| Inspect limits | `docker inspect -f '{{.HostConfig.Memory}} {{.HostConfig.NanoCpus}} {{.HostConfig.PidsLimit}}' C` | Bytes / nanocpus / pids | — |
| Live usage | `docker stats --no-stream` | Actual CPU% and memory vs limit | `docker stats --no-stream --format '{{.Name}} {{.CPUPerc}} {{.MemUsage}} {{.MemPerc}}'` |

```bash
# reproduce an OOM kill in 20 seconds (do this once — it demystifies exit 137 forever)
docker run --rm -m 64m alpine sh -c 'dd if=/dev/zero bs=1M count=200 | tail -c 1'
# → Killed
docker run -d --name oom -m 64m alpine sh -c 'x=$(head -c 200m /dev/zero | tr "\0" "a"); sleep 60'
sleep 5
docker inspect oom -f 'ExitCode={{.State.ExitCode}} OOMKilled={{.State.OOMKilled}}'
# → ExitCode=137 OOMKilled=true
docker rm -f oom
```

> 🔑 **Memory is a hard wall (kill); CPU is a soft wall (throttle).** Exceeding `--memory` → OOM kill, exit **137**. Exceeding `--cpus` → the container just runs slower, no crash. This asymmetry causes most "why did my container randomly die?" tickets.
>
> 🔑 **JVM/Go/Node inside a limit:** modern runtimes read the cgroup limit, but you must tell them to use it — `-XX:MaxRAMPercentage=75` (Java), `GOMEMLIMIT=200MiB` (Go 1.19+), `--max-old-space-size` (Node). Leave ~25% headroom for off-heap. See [`12-PROJECT-9-java-backend.md`](12-PROJECT-9-java-backend.md) Task 9.4.

---

## 19. Environment variables

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| One variable | `-e KEY=value` | Sets one env var | `docker run -e DB_HOST=db app` |
| Many variables | `-e A=1 -e B=2` | Repeat the flag | `docker run -e ENV=prod -e PORT=8080 app` |
| Forward from host | `-e KEY` | Passes the host's variable of that name (no `=value`) | `docker run -e AWS_REGION -e AWS_PROFILE app` |
| From a file | `--env-file FILE` | Loads `KEY=VALUE` lines | `docker run --env-file .env app` |
| Compose env file | `docker compose --env-file .env.prod up -d` | Which file feeds `${VAR}` interpolation | — |
| Inspect (image) | `docker image inspect -f '{{json .Config.Env}}' IMG` | Every ENV baked in — **where leaked secrets show up** | `docker image inspect -f '{{json .Config.Env}}' app` |
| Inspect (container) | `docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' C` | One per line, readable | `docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' web` |
| See at runtime | `docker exec CONTAINER env \| sort` | The truth, from inside | `docker exec api env \| sort` |
| For one exec | `docker exec -e K=V CONTAINER CMD` | Adds a var to that process only | `docker exec -e DEBUG=1 api python -c 'import os;print(os.environ["DEBUG"])'` |
| Build-time arg | `docker build --build-arg K=V -t app .` | Feeds a Dockerfile `ARG` | `docker build --build-arg VERSION=1.2 -t app .` |

**`--env-file` gotchas (these bite everyone):**

```bash
# .env
APP_NAME=My App          # ✅ spaces are fine, NO quotes needed
PATH_VAR=$HOME/bin       # ❌ NOT expanded — literally "$HOME/bin"
WITH_QUOTES="quoted"     # ❌ the quotes become PART of the value
# this is a comment      # ✅ full-line comments work
KEY=value # trailing     # ❌ "# trailing" becomes part of the value
export FOO=bar           # ❌ "export" is not stripped — key becomes "export FOO"
EMPTY=                   # ✅ empty string
```

> 🔑 **Precedence, lowest → highest:** base image `ENV` → your Dockerfile `ENV` → `--env-file` → individual `-e` flags. So `-e` always wins.
>
> 🔑 **Secrets:** `-e` and `--env-file` values are visible to anyone who can run `docker inspect` on that container, and to any process inside it. For real secrets use `--secret` (mounted at `/run/secrets/`, never in env or layers) or a vault. See [`09-PROJECT-6-multistage-build.md`](09-PROJECT-6-multistage-build.md) Task 6.5.

---

## 20. Labels

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| Container label | `docker run --label KEY=VALUE IMAGE` | Metadata on the container | `docker run --label env=prod nginx` |
| Many labels | `--label a=1 --label b=2` | Repeat the flag | `docker run --label team=devops --label tier=web nginx` |
| Label file | `--label-file FILE` | Bulk labels from a file | `docker run --label-file labels.txt nginx` |
| Build-time label | `docker build --label k=v -t app .` | Adds image labels without editing the Dockerfile | `docker build --label build=ci -t app .` |
| In a Dockerfile | `LABEL key=value` | Image metadata (multiple can share one layer) | `LABEL org.opencontainers.image.version="1.0"` |
| Filter containers | `docker ps -f label=env=prod` | Find by label | `docker ps -af label=tier=db` |
| Filter images | `docker images -f label=stage=prod` | Find images by label | — |
| Read labels | `docker inspect -f '{{json .Config.Labels}}' TARGET` | Dump them all | `docker inspect -f '{{json .Config.Labels}}' app` |
| One label | `docker inspect -f '{{index .Config.Labels "env"}}' TARGET` | Read a single one | — |
| Prune by label | `docker container prune -f --filter label=ci=true` | Clean up only what you labelled | `docker system prune -f --filter label!=keep` |

**The OCI label standard** (registries, SBOM tools and scanners read these):

```dockerfile
LABEL org.opencontainers.image.title="tasknest-api" \
      org.opencontainers.image.version="1.0.0" \
      org.opencontainers.image.revision="a1b2c3d" \
      org.opencontainers.image.created="2026-09-08T10:00:00Z" \
      org.opencontainers.image.authors="you@example.com" \
      org.opencontainers.image.vendor="Your Team" \
      org.opencontainers.image.source="https://github.com/you/repo" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.description="Task management API"
```

> 📌 `MAINTAINER` is a **deprecated Dockerfile instruction**. Use `LABEL maintainer=` or `org.opencontainers.image.authors`.

---

## 21. Docker Compose — VERY IMPORTANT

Compose v2 is a **plugin**: `docker compose` (space), not `docker-compose` (hyphen). The hyphenated v1 binary is end-of-life.

### Lifecycle

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| Validate + render | `docker compose config` | Merges files, interpolates `${VAR}`, prints the final YAML — **run this first, always** | `docker compose config` |
| Quiet validate | `docker compose config -q` | Exit code only, no output | `docker compose config -q && echo OK` |
| Build | `docker compose build` | Builds all `build:` services | `docker compose build` |
| Build one | `docker compose build api` | Only that service | `docker compose build api` |
| Build no cache | `docker compose build --no-cache` | From scratch | `docker compose build --no-cache api` |
| Build parallel | `docker compose build --parallel` | Build services concurrently | `docker compose build --parallel` |
| Pull | `docker compose pull` | Downloads images for `image:` services | `docker compose pull` |
| Pull + ignore failures | `docker compose pull --ignore-pull-failures` | Don't fail if one image is missing | — |
| Up | `docker compose up` | Create + start everything, **foreground**, logs interleaved | `docker compose up` |
| Up detached | `docker compose up -d` | Background — the daily driver | `docker compose up -d` |
| Up + build | `docker compose up -d --build` | Rebuild images first | `docker compose up -d --build` |
| Up + wait | `docker compose up -d --wait` | **Blocks until every healthcheck passes** — essential in CI | `docker compose up -d --wait --timeout 180` |
| Up one service + deps | `docker compose up -d api` | Starts `api` and everything it `depends_on` | `docker compose up -d api` |
| No dependencies | `docker compose up -d --no-deps api` | Only that service | `docker compose up -d --no-deps web` |
| Force recreate | `docker compose up -d --force-recreate` | Recreate containers even if config is unchanged | `docker compose up -d --force-recreate api` |
| No recreate | `docker compose up -d --no-recreate` | Reuse existing containers | `docker compose up -d --no-recreate` |
| No start | `docker compose up --no-start` | Create but don't start | — |
| Remove orphans | `docker compose up -d --remove-orphans` | Delete containers for services you removed from the YAML | `docker compose up -d --remove-orphans` |
| Scale | `docker compose up -d --scale api=3` | N replicas (no `container_name`, no fixed host port) | `docker compose up -d --scale api=3` |
| Start | `docker compose start [SVC]` | Starts existing **stopped** containers (no recreate) | `docker compose start` |
| Stop | `docker compose stop [SVC]` | Stops without removing — volumes and containers persist | `docker compose stop api` |
| Restart | `docker compose restart [SVC]` | Stop + start | `docker compose restart api` |
| Pause / unpause | `docker compose pause` / `unpause` | Freeze via cgroups | `docker compose pause api` |
| Kill | `docker compose kill [-s SIG]` | Immediate signal | `docker compose kill -s SIGINT api` |
| Down | `docker compose down` | Stop + remove containers, networks, **anonymous** volumes. **Named volumes survive.** | `docker compose down` |
| Down + volumes | `docker compose down -v` | ☠️ Also removes named volumes → **permanent data loss** | `docker compose down -v` |
| Down + images | `docker compose down --rmi local` | Also removes images Compose built (`local`) or all (`all`) | `docker compose down --rmi local` |
| Down + orphans | `docker compose down --remove-orphans` | Also removes containers not defined in the file | `docker compose down --remove-orphans` |
| Down + timeout | `docker compose down -t 30` | Grace period per container | `docker compose down -t 30` |

### Inspect & interact

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| Status | `docker compose ps` | Services, status, ports, **health** | `docker compose ps` |
| Status all | `docker compose ps -a` | Includes stopped/exited and one-shot jobs | `docker compose ps -a` |
| Quiet | `docker compose ps -q` | Container IDs | `docker inspect $(docker compose ps -q api)` |
| Services list | `docker compose config --services` | Just the service names | `docker compose config --services` |
| Logs | `docker compose logs` | All services, prefixed with the service name | `docker compose logs` |
| Follow | `docker compose logs -f` | Live, all services | `docker compose logs -f` |
| One service | `docker compose logs -f api` | Follow just one | `docker compose logs -f --tail=100 api` |
| Timestamps | `docker compose logs -t` | Add timestamps | `docker compose logs -t db` |
| Since | `docker compose logs --since 10m` | Time-windowed | `docker compose logs --since 1h api` |
| No prefix | `docker compose logs --no-log-prefix` | Clean output for piping | `docker compose logs --no-log-prefix api \| jq .` |
| Exec | `docker compose exec SERVICE CMD` | Inside the **running** service container | `docker compose exec api sh` |
| Exec as root | `docker compose exec -u 0 api sh` | Escalate | `docker compose exec -u 0 db bash` |
| Exec in dir | `docker compose exec -w /app api ls` | Set working directory | — |
| Run one-off | `docker compose run --rm SERVICE CMD` | A **new** container from the service definition (migrations, tests, shells) | `docker compose run --rm api pytest` |
| Run without deps | `docker compose run --rm --no-deps api sh` | Skip `depends_on` | — |
| Run with service ports | `docker compose run --rm --service-ports api sh` | Publish ports for the one-off container | — |
| Top | `docker compose top` | Processes inside each service container | `docker compose top api` |
| Images | `docker compose images` | Images in use per service | `docker compose images` |
| Events | `docker compose events` | Live event stream for the project | `docker compose events --json` |
| Stats | `docker compose stats` | Not native in older versions — use `docker stats $(docker compose ps -q)` | `docker stats --no-stream $(docker compose ps -q)` |
| Port | `docker compose port SERVICE PRIVATE_PORT` | The published host port (great in scripts) | `docker compose port web 80` |
| Watch (auto-reload) | `docker compose watch` | Rebuild/sync on file changes (Compose v2.22+) | `docker compose watch` |
| Down + prune | `docker compose down && docker system prune -f` | Full local reset | — |

---

## 22. Compose file selection

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| Default file | `docker compose up -d` | Auto-finds `compose.yaml` → `compose.yml` → `docker-compose.yml` | `docker compose up -d` |
| Specific file | `docker compose -f FILE up -d` | Use a named file | `docker compose -f compose.prod.yml up -d` |
| **Merged files** | `docker compose -f base.yml -f prod.yml up -d` | Later files **override** earlier ones key-by-key — the standard dev/prod pattern | `docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d` |
| Project name | `docker compose -p NAME up -d` | Namespace for containers, networks, volumes | `docker compose -p ecommerce up -d` |
| Env file | `docker compose --env-file FILE up -d` | Which file feeds `${VAR}` interpolation | `docker compose --env-file .env.prod up -d` |
| Profile | `docker compose --profile dev up -d` | Starts services tagged with that profile | `docker compose --profile dev --profile tools up -d` |
| Multiple profiles | `COMPOSE_PROFILES=dev,tools docker compose up -d` | Via environment instead of flags | — |
| Directory | `docker compose --project-directory DIR up` | Sets the context root (relative paths resolve there) | `docker compose --project-directory ./infra up -d` |
| Show resolution | `docker compose config` | **Always** check which files/profiles/env actually applied | `docker compose -f a.yml -f b.yml config` |

```bash
# the canonical multi-environment setup
docker compose -f docker-compose.yml                        up -d   # production defaults
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d   # + hot reload, JDK stage, debug ports
docker compose -f docker-compose.yml -f docker-compose.test.yml run --rm api pytest
COMPOSE_FILE=docker-compose.yml:docker-compose.monitoring.yml docker compose up -d   # : separated (Linux)
```

> 🔑 **Merge rules:** scalars are replaced, `environment`/`labels` are merged key-wise, and **sequences like `ports:` and `volumes:` are appended** (which surprises people — a dev override can't *remove* a published port, only add another). Use `!reset` / `!override` YAML tags (Compose v2.24+) when you need to replace a list.

---

## 23. Docker system management

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| Disk usage | `docker system df` | Totals for images, containers, volumes, build cache (+ reclaimable) | `docker system df` |
| Detailed | `docker system df -v` | Per-image, per-container, per-volume breakdown — **find the actual hog** | `docker system df -v` |
| Prune (safe) | `docker system prune` | Stopped containers + unused networks + **dangling** images + build cache | `docker system prune` |
| Prune (aggressive) | `docker system prune -a` | The above + **every image not used by a container** ⚠️ | `docker system prune -a` |
| Include volumes | `docker system prune -a --volumes` | ☠️ Also removes unused volumes → **DATA LOSS** | never run blindly |
| No prompt | `docker system prune -af` | CI/cron usage | `docker system prune -af` |
| By age | `docker system prune -af --filter until=168h` | Only resources older than 7 days | `docker system prune -af --filter until=24h` |
| By label | `docker system prune -af --filter label!=keep` | Protect labelled resources | — |
| Per-category prune | `docker container prune` / `image prune` / `volume prune` / `network prune` / `builder prune` | Targeted cleanup | `docker builder prune -af` |
| Build cache | `docker builder prune` | Clears BuildKit cache (slows the next build!) | `docker builder prune -af --filter until=168h` |
| Build cache size | `docker buildx du` | Cache usage per builder | `docker buildx du --verbose` |
| Daemon info | `docker info` | Storage driver, root dir, runtimes, cgroup driver, warnings | `docker info` |
| Daemon root dir | `docker info -f '{{.DockerRootDir}}'` | Usually `/var/lib/docker` | — |
| Version detail | `docker version` | Client + Server + API versions | `docker version` |
| Events | `docker events --since 1h` | What the daemon did recently — **forensics** | `docker events --since 1h --until 30m` |
| Disk pressure alarm | `docker system df --format '{{.Type}} {{.Size}} {{.Reclaimable}}'` | Scriptable alerting | — |

> ⚠️ **PRODUCTION WARNING.** `docker system prune -a --volumes` deletes: every stopped container, every image not attached to a *running* container, every unused network, the whole build cache, **and every volume not mounted by a running container** — including your database. There is no undo and no recycle bin.
>
> Safe production recipe:
> ```bash
> docker system df -v | head -40                        # LOOK first
> docker image prune -af --filter until=168h            # images only, 7 days old
> docker builder prune -af --filter until=168h          # build cache only
> docker container prune -f --filter until=24h          # stopped containers only
> # NEVER automate `docker volume prune` on a host with databases
> ```

---

## 24. Docker volume drivers

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| Default driver | `docker volume create NAME` | Uses `local` | `docker volume create app-data` |
| Explicit driver | `docker volume create -d DRIVER NAME` | `local`, or a plugin driver (`rexray/ebs`, `nfs`, `local-persist`) | `docker volume create -d local app-data` |
| Bind-backed volume | `docker volume create --opt type=none --opt device=/srv/data --opt o=bind NAME` | A named volume pointing at a fixed host path | `docker volume create --driver local --opt type=none --opt device=/srv/pgdata --opt o=bind pgdata` |
| NFS volume | `docker volume create -d local --opt type=nfs --opt o=addr=10.0.0.10,rw,nolock --opt device=:/exports/data nfs-data` | Mount NFS on every node that uses it | — |
| tmpfs volume | `docker volume create -d local --opt type=tmpfs --opt device=tmpfs --opt o=size=100m ramdisk` | RAM-backed | — |
| CIFS/SMB | `docker volume create -d local --opt type=cifs --opt device=//server/share --opt o=username=u,password=p,rw smb-data` | Windows shares | — |
| Label it | `docker volume create --label keep=true NAME` | So `prune --filter label!=keep` spares it | `docker volume create --label tier=database pgdata` |
| Inspect driver | `docker volume inspect -f '{{.Driver}} {{json .Options}}' NAME` | Which driver and what options | `docker volume inspect -f '{{.Driver}} {{json .Options}}' nfs-data` |
| List by driver | `docker volume ls -f driver=local` | Filter | — |
| List plugins | `docker plugin ls` | Installed volume/auth/network plugins | `docker plugin ls` |

---

## 25. Docker context

Contexts let one CLI talk to **many Docker daemons** — your laptop, a remote server over SSH, a cloud VM — without changing `DOCKER_HOST` by hand.

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| List | `docker context ls` | All contexts; `*` marks the active one | `docker context ls` |
| Current | `docker context show` | Which daemon you're talking to right now | `docker context show` |
| Inspect | `docker context inspect NAME` | Endpoint, TLS material, description | `docker context inspect default` |
| Create over SSH | `docker context create NAME --docker host=ssh://USER@HOST` | **Zero setup** — uses your SSH key, no open 2375 port | `docker context create prod --docker host=ssh://ops@10.0.0.5` |
| Create over TCP | `docker context create NAME --docker host=tcp://HOST:2376 --ca ... --cert ... --key ...` | TLS-enabled remote daemon | — |
| Create from env | `docker context create NAME --from=default --description "ci"` | Clone an existing context | — |
| Switch | `docker context use NAME` | All subsequent `docker` commands hit that daemon | `docker context use prod` |
| Per-command | `docker --context prod ps` | One-off, without switching | `docker --context prod ps -a` |
| Update | `docker context update NAME --description "..."` | Change metadata/endpoint | `docker context update prod --docker host=ssh://ops@new-ip` |
| Remove | `docker context rm NAME` | Deletes the context (not the remote daemon) | `docker context rm prod` |
| Export | `docker context export NAME > FILE` | Share a context with a teammate | `docker context export prod > prod.dockercontext` |
| Import | `docker context import NAME FILE` | Load someone else's context | `docker context import prod prod.dockercontext` |

```bash
# the workflow this enables
docker context create laptop   --docker host=unix:///var/run/docker.sock
docker context create staging  --docker host=ssh://deploy@staging.example.com
docker context create prod     --docker host=ssh://deploy@prod.example.com

docker context use staging && docker compose up -d --build
docker context use prod    && docker ps && docker stats --no-stream
docker context use laptop
```

> 🔑 `ssh://` contexts require: SSH key auth set up, and `docker` installed on the remote host. No firewall holes, no TLS certificates to manage — this is the right way to drive remote Docker.

---

## 26. Docker Scout / image security

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| Quick view | `docker scout quickview IMAGE` | High-level security + base-image overview | `docker scout quickview nginx:latest` |
| CVEs | `docker scout cves IMAGE` | Full vulnerability list with severities and fixes | `docker scout cves myapp:1.0` |
| Only critical | `docker scout cves --only-severity critical,high IMAGE` | What you'd gate a build on | `docker scout cves --only-severity critical,high -q app` |
| JSON for CI | `docker scout cves --format json IMAGE` | Machine-readable | `docker scout cves --format json app > cves.json` |
| Recommendations | `docker scout recommendations IMAGE` | Suggested base-image refreshes | `docker scout recommendations myapp:1.0` |
| Compare | `docker scout compare NEW --to OLD` | What got better/worse between two images | `docker scout compare app:2.0 --to app:1.0` |
| Base refresh | `docker scout cves --only-fixable IMAGE` | CVEs with an available fix | — |
| SBOM | `docker scout sbom IMAGE` | Software bill of materials | `docker scout sbom --format spdx app:1.0` |
| Policy | `docker scout policy IMAGE` | Evaluate against your org's Scout policies | `docker scout policy me/app:1.0` |
| Watch | `docker scout watch IMAGE` | Monitor for newly disclosed CVEs | — |

**Third-party scanners you'll meet in CI:**

```bash
trivy image --severity CRITICAL,HIGH --exit-code 1 myapp:1.0     # fails the build
trivy image --format json -o trivy.json myapp:1.0
grype myapp:1.0 --fail-on high
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  aquasec/trivy image myapp:1.0
```

> 🔑 **Gate the build, not the deploy.** In GitHub Actions: run Trivy with `--exit-code 1 --severity CRITICAL,HIGH` as a step — the pipeline fails and the image never reaches the registry. See the capstone's CI workflow in [`02-CAPSTONE-END-TO-END.md`](02-CAPSTONE-END-TO-END.md) §C.10.

---

## 27. Docker manifest / multi-architecture

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| Inspect | `docker manifest inspect IMAGE` | Shows the manifest / manifest list and every platform | `docker manifest inspect nginx:latest` |
| Create | `docker manifest create LIST IMG...` | Assemble a manifest list from per-arch images | `docker manifest create app:latest app:amd64 app:arm64` |
| Amend | `docker manifest create --amend LIST IMG` | Add to an existing list | `docker manifest create --amend app:latest app:armv7` |
| Annotate | `docker manifest annotate LIST IMG --arch A --os O` | Attach platform metadata | `docker manifest annotate app:latest app:arm64 --arch arm64 --os linux` |
| Push | `docker manifest push LIST` | Publish the list to the registry | `docker manifest push app:latest` |
| Remove | `docker manifest rm LIST` | Delete the local list | `docker manifest rm app:latest` |
| **Modern equivalent** | `docker buildx imagetools inspect IMAGE` | Read a manifest list from a registry — **no experimental flag needed** | `docker buildx imagetools inspect ghcr.io/me/app:1.0` |
| Create via buildx | `docker buildx build --platform A,B --push` | Builds *and* publishes the list in one step | see [§13](#13-docker-buildx) |

> ⚠️ `docker manifest` is an **experimental** client feature: enable it with `{"experimental": "enabled"}` in `~/.docker/config.json`, or set `DOCKER_CLI_EXPERIMENTAL=enabled`. In practice **everyone uses `docker buildx build --platform ... --push`** instead — one command, no experimental flag, cache support.

```bash
# how to tell whether an image is multi-arch
docker buildx imagetools inspect nginx:1.29-alpine | grep -A20 'Manifests'
docker image inspect -f '{{.Os}}/{{.Architecture}}' nginx:1.29-alpine   # what YOU pulled
```

---

## 28. Docker plugins

Plugins extend Docker with volume drivers (EBS, Ceph, NFS), network drivers (Calico, Weave) and authorisation drivers.

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| List | `docker plugin ls` | Installed plugins, enabled state | `docker plugin ls` |
| Inspect | `docker plugin inspect NAME` | Config, mounts, env, capabilities | `docker plugin inspect vieux/sshfs` |
| Install | `docker plugin install NAME` | Pulls **and** enables (prompts for privileges) | `docker plugin install vieux/sshfs` |
| Install disabled | `docker plugin install --disable NAME` | Install without enabling | `docker plugin install --disable storidge/cio` |
| Install with grants | `docker plugin install --grant-all-permissions NAME` | Non-interactive (CI) ⚠️ | `docker plugin install --grant-all-permissions vieux/sshfs` |
| Enable | `docker plugin enable NAME` | Activate a disabled plugin | `docker plugin enable vieux/sshfs` |
| Enable with timeout | `docker plugin enable --timeout 60 NAME` | Wait longer for slow plugins | — |
| Disable | `docker plugin disable NAME` | Deactivate (must not be in use) | `docker plugin disable vieux/sshfs` |
| Set config | `docker plugin set NAME KEY=VALUE` | Change plugin settings | `docker plugin set vieux/sshfs DEBUG=1` |
| Push | `docker plugin push NAME` | Publish a plugin you built | `docker plugin push me/myplugin:1.0` |
| Create | `docker plugin create NAME DIR` | Build a plugin from a `config.json` + rootfs | `docker plugin create me/myplugin ./plugin-dir` |
| Upgrade | `docker plugin upgrade NAME NEW` | Replace with a newer version | `docker plugin upgrade vieux/sshfs vieux/sshfs:latest` |
| Remove | `docker plugin rm NAME` | Uninstall | `docker plugin rm -f vieux/sshfs` |
| Inspect privileges | `docker plugin inspect -f '{{json .Config.Interface}}' NAME` | What it hooks into (volume/network/auth) | — |

```bash
# a plugin-backed volume in practice
docker plugin install vieux/sshfs --grant-all-permissions
docker volume create -d vieux/sshfs sshvol \
  -o sshcmd=user@host:/path -o password=secret
docker run --rm -v sshvol:/mnt alpine ls /mnt
```

---

## 29. Docker Swarm — KNOW FOR INTERVIEWS

Swarm is Docker's built-in orchestrator: multi-node, with a **routing mesh**, rolling updates, and native secrets/configs. Simpler than Kubernetes; far less common in new systems — but still asked about.

### Cluster & nodes

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| Init manager | `docker swarm init` | Turns this engine into a single-node Swarm manager | `docker swarm init --advertise-addr 10.0.0.5` |
| Init multi-NIC | `docker swarm init --advertise-addr IP` | Choose which interface peers use | `docker swarm init --advertise-addr 192.168.1.10` |
| Worker token | `docker swarm join-token worker` | Prints the exact join command for workers | `docker swarm join-token worker` |
| Manager token | `docker swarm join-token manager` | Join command for additional managers | `docker swarm join-token manager` |
| Rotate token | `docker swarm join-token --rotate worker` | Invalidate the old token (leaked?) | `docker join-token --rotate manager` |
| Join | `docker swarm join --token TOKEN MANAGER:2377` | Adds this node to the cluster | `docker swarm join --token SWMTKN-1-xxx 10.0.0.5:2377` |
| Leave (worker) | `docker swarm leave` | Removes this node | `docker swarm leave` |
| Leave (manager) | `docker swarm leave --force` | Required on managers ⚠️ | `docker swarm leave --force` |
| List nodes | `docker node ls` | From a manager: every node, role, status, availability | `docker node ls` |
| Inspect node | `docker node inspect NODE` | Full metadata (IP, platform, engine, TLS) | `docker node inspect worker1 --pretty` |
| Drain a node | `docker node update --availability drain NODE` | Evacuate tasks before maintenance — **the safe way** | `docker node update --availability drain worker1` |
| Re-activate | `docker node update --availability active NODE` | Bring it back into rotation | `docker node update --availability active worker1` |
| Pause scheduling | `docker node update --availability pause NODE` | Keep existing tasks, schedule nothing new | — |
| Promote | `docker node promote NODE` | Worker → manager (HA) | `docker node promote worker2` |
| Demote | `docker node demote NODE` | Manager → worker | `docker node demote manager2` |
| Label a node | `docker node update --label-add zone=eu-west NODE` | For placement constraints | `docker node update --label-add disk=ssd worker1` |
| Remove a node | `docker node rm NODE` | Drop it from the cluster | `docker node rm -f worker3` |

### Services

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| Create | `docker service create --name web --publish 80:80 nginx` | A replicated, self-healing service | `docker service create --name web --replicas 3 -p 8080:80 nginx` |
| With replicas | `--replicas N` | Desired task count | `docker service create --replicas 5 --name web nginx` |
| Global mode | `--mode global` | One task **per node** (log agents, node exporters) | `docker service create --mode global --name node-exporter prom/node-exporter` |
| Env / secrets / configs | `-e K=V`, `--secret src=X,target=/run/secrets/X`, `--config src=nginx.conf,target=/etc/nginx.conf` | Configuration injection | see [§30](#30-docker-secrets), [§31](#31-docker-configs--swarm) |
| Constraints | `--constraint 'node.labels.zone==eu-west'` | Placement rules | `--constraint 'node.role==worker'` |
| Preferences | `--placement-pref 'spread=node.labels.zone'` | Spread tasks evenly | — |
| Healthcheck | `--health-cmd 'curl -f http://localhost/ \|\| exit 1' --health-interval 10s` | Per-service health | — |
| Limits | `--limit-cpu 0.5 --limit-memory 256M --reserve-cpu 0.25 --reserve-memory 128M` | Resources | `docker service create --limit-memory 512m app` |
| Update policy | `--update-parallelism 1 --update-delay 10s --update-order start-first --update-failure-action rollback` | Zero-downtime rolling updates | see below |
| Restart policy | `--restart-condition on-failure --restart-delay 5s --restart-max-attempts 3` | Task-level restarts | — |
| Mounts | `--mount type=volume,source=dbdata,target=/var/lib/mysql` | Volumes/bind mounts | — |
| Networks | `--network my-overlay` | Attach to an **overlay** network | `docker service create --network prod-net app` |
| List | `docker service ls` | All services, replicas, image, ports | `docker service ls` |
| Inspect | `docker service inspect SERVICE` | Full spec | `docker service inspect web --pretty` |
| Tasks | `docker service ps SERVICE` | **Every task**, which node, current and past states, errors | `docker service ps web` |
| Tasks no truncate | `docker service ps --no-trunc web` | See the full error message for a failing task | `docker service ps --no-trunc web` |
| Logs | `docker service logs SERVICE` | Aggregated logs across all replicas | `docker service logs -f web` |
| Scale | `docker service scale SERVICE=N` | Change replicas | `docker service scale web=5` |
| Scale several | `docker service scale web=5 api=3` | Multiple in one call | — |
| Update image | `docker service update --image nginx:1.29 web` | Rolling image upgrade | `docker service update --image app:2.0 api` |
| Update anything | `docker service update --env-add K=V --publish-add 8443:443 web` | Any spec change triggers a rolling update | — |
| Force redeploy | `docker service update --force web` | Recreate tasks without a spec change | `docker service update --force api` |
| Rollback | `docker service rollback SERVICE` | Revert to the previous spec — **one command** | `docker service rollback web` |
| Health on update | `docker service update --health-cmd ... --update-order start-first web` | New task must be healthy before the old one dies | — |
| Remove | `docker service rm SERVICE` | Deletes the service and all its tasks | `docker service rm web` |

### Overlay networks, stacks, secrets, configs

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| Overlay network | `docker network create -d overlay --attachable prod-net` | Spans all nodes; `--attachable` lets standalone containers join too | `docker network create -d overlay --attachable backend` |
| Encrypted overlay | `docker network create -d overlay --opt encrypted=true secret-net` | IPsec between nodes — required for sensitive traffic | — |
| Ingress mesh | automatic | Swarm's built-in routing mesh: **any node's IP** on a published port reaches any replica | `curl http://ANY-NODE:8080` |
| Deploy stack | `docker stack deploy -c FILE NAME` | Deploy a Compose-format file to Swarm | `docker stack deploy -c docker-stack.yml app` |
| Deploy with secrets | `docker stack deploy -c stack.yml --with-registry-auth app` | Passes your registry credentials to all nodes | — |
| List stacks | `docker stack ls` | Deployed stacks and service counts | `docker stack ls` |
| Stack services | `docker stack services STACK` | Services in one stack | `docker stack services app` |
| Stack tasks | `docker stack ps STACK` | Tasks across the stack | `docker stack ps app` |
| Remove stack | `docker stack rm STACK` | Deletes the whole stack | `docker stack rm app` |

```bash
# the full Swarm demo in 8 commands (single node is enough to learn it)
docker swarm init
docker network create -d overlay --attachable demo-net
echo "s3cr3t" | docker secret create db_password -
docker service create --name db --network demo-net \
  --secret db_password -e MYSQL_ROOT_PASSWORD_FILE=/run/secrets/db_password \
  --mount type=volume,source=dbdata,target=/var/lib/mysql mysql:8.4
docker service create --name web --network demo-net --replicas 3 -p 8080:80 nginx
docker service ps web
docker service scale web=6
docker service update --image nginx:1.29-alpine --update-delay 5s --update-parallelism 2 web
docker service rollback web
docker service rm web db && docker secret rm db_password && docker network rm demo-net
```

> 🔑 **Swarm vs Kubernetes, in one breath:** Swarm's routing mesh means any node accepts traffic for any service (no Ingress object needed); Compose files deploy as-is; secrets and configs are first-class. Kubernetes offers far more extensibility, a much bigger ecosystem, declarative GitOps, and CRDs — which is why it won the market. Swarm is still excellent for small teams and single-host-to-3-host deployments.

---

## 30. Docker secrets

Swarm secrets are encrypted at rest (Raft log), delivered over TLS, and mounted as **tmpfs files** at `/run/secrets/<name>` — never in env vars, never in image layers.

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| List | `docker secret ls` | All secrets (names + IDs, **never** values) | `docker secret ls` |
| Create from file | `docker secret create NAME FILE` | Reads the file's contents as the secret | `docker secret create db_password ./password.txt` |
| Create from stdin | `printf '%s' "$PASS" \| docker secret create NAME -` | **The CI way** — no file on disk | `echo -n 's3cr3t' \| docker secret create db_password -` |
| Inspect | `docker secret inspect NAME` | Metadata only (labels, created) — the value is not returned | `docker secret inspect db_password --pretty` |
| Remove | `docker secret rm NAME` | Deletes it | `docker secret rm db_password` |
| Attach to service | `docker service create --secret NAME ...` | Mounts at `/run/secrets/NAME` | `docker service create --secret db_password app` |
| Custom target | `--secret source=db_password,target=mysql_pass,uid=100,mode=0400` | Rename, change owner/permissions | — |
| In a stack file | `secrets:` at top level + `secrets:` per service | Declarative secrets | see below |
| Rotate | create a new version, update the service | `docker secret create db_password_v2 ...` then `docker service update --secret-rm old --secret-add new` | — |
| Non-Swarm equivalent | `docker run --secret id=X,src=./f.txt app` | BuildKit/run secret — same mount path, single container | `docker run --secret id=aws,src=$HOME/.aws/credentials app` |
| Build-time secret | `RUN --mount=type=secret,id=X ...` | Available for one `RUN`, never stored | `docker build --secret id=npmrc,src=$HOME/.npmrc .` |

```yaml
# docker-stack.yml
version: "3.9"
services:
  db:
    image: mysql:8.4
    environment:
      MYSQL_ROOT_PASSWORD_FILE: /run/secrets/db_root_password    # ← *_FILE convention
    secrets: [db_root_password]
  api:
    image: me/api:1.0
    secrets:
      - source: db_password
        target: db_password          # → /run/secrets/db_password
        mode: 0400
secrets:
  db_root_password:
    external: true                   # created out-of-band with `docker secret create`
  db_password:
    file: ./secrets/db_password.txt  # or: created by Swarm from this file
```

> 🔑 **The `*_FILE` convention:** official images (mysql, postgres, redis, mongo) accept `MYSQL_ROOT_PASSWORD_FILE`, `POSTGRES_PASSWORD_FILE` etc. — a path to a file containing the value. That's what makes secrets work with them. **Always prefer `*_FILE` over the plain env var.**
>
> 🔑 In your own apps, read the secret from the file at startup:
> ```python
> password = open(os.environ["DB_PASSWORD_FILE"]).read().strip()
> ```

---

## 31. Docker configs — Swarm

Configs are the same mechanism as secrets but for **non-sensitive** configuration: they're stored unencrypted in Raft and can be updated without recreating the image.

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| List | `docker config ls` | All configs | `docker config ls` |
| Create | `docker config create NAME FILE` | Stores the file's contents | `docker config create nginx_conf ./nginx.conf` |
| From stdin | `cat app.properties \| docker config create app_props -` | CI-friendly | — |
| Inspect | `docker config inspect NAME` | Metadata (and the data, base64 — it isn't secret) | `docker config inspect nginx_conf --pretty` |
| Remove | `docker config rm NAME` | Deletes it | `docker config rm nginx_conf` |
| Attach | `docker service create --config NAME ...` | Mounts at `/NAME` (root of the filesystem!) | `docker service create --config nginx_conf nginx` |
| Custom target | `--config source=nginx_conf,target=/etc/nginx/conf.d/app.conf,mode=0444` | Place it exactly where the app expects | — |
| Update a service | `docker service update --config-rm nginx_conf --config-add source=nginx_conf_v2,target=/etc/nginx.conf nginx` | Rolling config change | — |
| In a stack file | `configs:` top level + per service | Declarative | see below |

```yaml
services:
  web:
    image: nginx:1.29-alpine
    configs:
      - source: nginx_conf
        target: /etc/nginx/conf.d/default.conf
        mode: 0444
configs:
  nginx_conf:
    file: ./nginx.conf
```

> 🔑 **Secrets vs configs — the one-line distinction:** *secrets* are encrypted, mounted at `/run/secrets/`, mode `0400` by default, for credentials/keys/TLS material. *Configs* are plaintext, mounted where you say, mode `0444` by default, for `.conf`/`.properties`/`.yaml` files. Both beat baking configuration into images, because you can change them without a rebuild.

---

## 32. Docker events / real-time troubleshooting

`docker events` streams **everything the daemon does** — the single best tool for "what just happened?"

| Pattern | Command | One-line explanation | Example |
|---|---|---|---|
| All events | `docker events` | Live stream of every daemon event | `docker events` |
| By type | `docker events --filter type=container` | `container` \| `image` \| `volume` \| `network` \| `daemon` \| `plugin` \| `service` \| `node` \| `secret` \| `config` | `docker events --filter type=container` |
| By event | `docker events --filter event=die` | `create`, `start`, `die`, `stop`, `kill`, `oom`, `destroy`, `restart`, `pause`, `unpause`, `health_status` | `docker events --filter event=oom` |
| By container | `docker events --filter container=web` | One container only | `docker events --filter container=api` |
| By image | `docker events --filter image=nginx` | Events for containers of an image | — |
| By label | `docker events --filter label=env=prod` | Only labelled resources | — |
| Since | `docker events --since 1h` | Replay recent history (`30m`, `2026-09-08T09:00:00`) | `docker events --since 2h` |
| Until | `docker events --until 10m` | Bound the window | `docker events --since 1h --until 30m` |
| Non-streaming | `docker events --since 1h --until 1m` | Bounded window → returns and exits (scriptable!) | `docker events --since 24h --until now > events.log` |
| JSON | `docker events --format '{{json .}}'` | Machine-readable | `docker events --format '{{json .}}' \| jq .` |
| Decode exit codes | `docker events --filter event=die --format '{{.Actor.Attributes.exitCode}} {{.Actor.Attributes.name}}'` | Live crash watch | see below |

```bash
# watch crashes live, with the exit code, in another terminal
docker events --filter event=die \
  --format '{{.Time}} DIED {{.Actor.Attributes.name}} exit={{.Actor.Attributes.exitCode}}'

# watch OOM kills specifically
docker events --filter event=oom --format '{{.Time}} OOM {{.Actor.Attributes.name}}'

# forensics: what happened to this container overnight?
docker events --since 12h --until now --filter container=api --format '{{.Time}} {{.Action}}'
```

> 🔑 **`event=die` with `exitCode`** is how you catch a crash-loop in the act without tailing logs. Combined with `docker inspect --format '{{.RestartCount}}'`, it tells you whether the restart policy is fighting a real bug.

---

## 33. Commands worth knowing that most lists miss

| Command | What it does | When you need it |
|---|---|---|
| `docker wait C` | Blocks until the container exits, prints the **exit code** | CI jobs: `docker wait myjob` then branch on the code |
| `docker attach C` | Attaches STDIN/STDOUT to **PID 1** (unlike `exec`, which starts a new process) | Watching a foreground app; `Ctrl-P Ctrl-Q` to detach without killing |
| `docker rename OLD NEW` | Renames a container | Freeing a name, fixing conventions |
| `docker update --cpus 2 -m 1g C` | Changes limits/restart policy on a **running** container | Tuning without a redeploy |
| `docker debug C` | Ephemeral debug container sharing the target's namespaces, with a preloaded toolbelt | Debugging distroless/scratch images |
| `docker builder prune` | Clears BuildKit cache only | Disk pressure from CI builds |
| `docker buildx du` | Shows build cache usage | Deciding what to prune |
| `docker checkpoint create/ls/start` | CRIU checkpoint/restore (experimental) | Fast snapshot/restore, live migration experiments |
| `docker trust inspect/sign` | Docker Content Trust signatures | Signed-image policies |
| `docker system events` | Alias of `docker events` | — |
| `docker info -f '{{json .}}'` | Whole daemon config as JSON | Auditing a host |
| `docker version -f '{{.Server.Version}}'` | Server version only | CI matrix decisions |
| `docker container prune --filter label!=keep` | Label-aware cleanup | Protecting long-lived containers in cron jobs |
| `docker run --cidfile f.id` | Writes the container ID to a file | Scripting without parsing stdout |
| `docker logs --details` | Shows extra log attributes | When your driver adds metadata |
| `docker inspect --format` on **any** object | Works for containers, images, volumes, networks, nodes, services, secrets | One skill, seven objects |

---

## 40. Real-time scenario: "Container is down"

| Step | Command | Purpose |
|---|---|---|
| 1 | `docker ps -a` | Is it `Exited`, `Dead`, `Created`, or `Restarting`? Note the exit code shown in `STATUS`. |
| 2 | `docker logs --tail 200 CONTAINER` | **The answer is usually right here.** Application stack trace, missing file, bind error. |
| 3 | `docker inspect -f 'exit={{.State.ExitCode}} oom={{.State.OOMKilled}} err={{.State.Error}}' CONTAINER` | Exit code + whether the kernel OOM-killed it + Docker's own error. |
| 4 | `docker inspect -f '{{json .Config.Cmd}} {{json .Config.Entrypoint}}' CONTAINER` | Is the command what you think it is? (Shell form shows `/bin/sh -c …`.) |
| 5 | `docker inspect -f '{{json .Mounts}}' CONTAINER` | Are the volumes/bind mounts present, correct, and writable? |
| 6 | `docker inspect -f '{{json .NetworkSettings.Networks}}' CONTAINER` | Is it on the network it needs? |
| 7 | `docker diff CONTAINER` | Files the container wrote — reveals where it tried to write and failed. |
| 8 | `docker start CONTAINER` | Try again now that you've looked. |
| 9 | `docker start -ai CONTAINER` | Start **in the foreground** so the failure prints immediately. |
| 10 | `docker exec -it CONTAINER sh` | If it stays up even briefly, get inside before it dies. |
| 11 | `docker run --rm -it --entrypoint sh IMAGE` | If it can't stay up at all, explore the **image** instead. |
| 12 | `docker events --since 10m --filter container=CONTAINER` | Timeline of what the daemon did to it. |

**Exit-code decoder (the fastest triage there is):**

| Code | Meaning | First thing to check |
|---|---|---|
| `0` | Clean exit — the process **finished** | Your CMD is a one-shot command, not a server. Needs a foreground long-running process. |
| `1` | Application error | `docker logs` — the app told you why |
| `2` | Shell misuse / bad argument | The command line or entrypoint script |
| `125` | `docker run` itself failed | Your flags (bad `-v` path, invalid `--name`) |
| `126` | Command found but **not executable** | Missing `chmod +x`, or `COPY --chmod=755` |
| `127` | **Command not found** | Typo, wrong `WORKDIR`, binary not in `PATH`, or missing dependency |
| `137` | 128+9 = `SIGKILL` | **OOM kill** (check `OOMKilled=true`) or `docker kill` or a `stop` timeout expiry |
| `143` | 128+15 = `SIGTERM` | A normal `docker stop` — usually not an error at all |
| `159` | 128+31 = `SIGSYS` | Seccomp blocked a syscall |
| `255` | Exit status out of range / generic | Often a shell script exiting badly |

---

## 35. Real-time scenario: "Container keeps restarting"

| Step | Command | Purpose |
|---|---|---|
| 1 | `docker ps -a --filter name=CONTAINER` | `STATUS` shows `Restarting (N) X seconds ago` and the exit code |
| 2 | `docker logs --tail 200 CONTAINER` | The repeated failure reason |
| 3 | `docker inspect -f 'policy={{.HostConfig.RestartPolicy.Name}} max={{.HostConfig.RestartPolicy.MaximumRetryCount}} count={{.RestartCount}}' CONTAINER` | Which policy is fighting you, and how many times |
| 4 | `docker inspect -f 'exit={{.State.ExitCode}} oom={{.State.OOMKilled}}' CONTAINER` | Crash reason |
| 5 | `docker inspect -f '{{json .Config.Cmd}}' CONTAINER` / `'{{json .Config.Entrypoint}}'` | Is the command even correct? |
| 6 | `docker update --restart=no CONTAINER` | **Stop the loop** so you can investigate in peace |
| 7 | `docker start -ai CONTAINER` | Run it in the foreground and watch it fail live |
| 8 | `docker run --rm -it --entrypoint sh IMAGE` | Get inside the image and run the command manually |
| 9 | `docker events --filter container=CONTAINER --since 5m` | Confirm the restart/die cycle |
| 10 | `docker update --restart=unless-stopped CONTAINER` | Restore the policy once fixed |

**The four usual causes:**
1. **OOM** (`ExitCode=137`, `OOMKilled=true`) → raise `--memory`, or fix the leak, or lower the JVM heap percentage.
2. **A dependency isn't ready** (DB connection refused on boot) → add a `HEALTHCHECK` + `depends_on: {condition: service_healthy}`, and retry-with-backoff in the app.
3. **The main process exits** (a script that finishes, or a daemon that forks to the background) → keep it in the **foreground** (`nginx -g 'daemon off;'`, `mongod --fork=false`).
4. **Bad config/env** (typo'd `DATABASE_URL`) → `docker inspect -f '{{json .Config.Env}}'`.

---

## 36. Real-time scenario: "Container has high CPU / memory"

| Command | Explanation |
|---|---|
| `docker stats` | Live per-container CPU%, MEM usage/limit, NET and BLOCK I/O |
| `docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}'` | One snapshot, sortable — **the command to memorise** |
| `docker top CONTAINER` | Processes inside, with **host PIDs** |
| `docker exec -it CONTAINER top` | The container's *own* view (busybox `top`: `top -b -n1`) |
| `docker inspect -f 'mem={{.HostConfig.Memory}} cpu={{.HostConfig.NanoCpus}} pids={{.HostConfig.PidsLimit}}' CONTAINER` | Are limits even set? (`0` = unlimited ⚠️) |
| `docker inspect -f '{{.State.OOMKilled}}' CONTAINER` | Has it already been killed once? |
| `docker exec CONTAINER cat /sys/fs/cgroup/memory.max` | The limit **as the container sees it** (cgroup v2) |
| `docker exec CONTAINER cat /sys/fs/cgroup/memory.current` | Current usage from inside |
| `docker exec CONTAINER cat /proc/loadavg` | Load average inside |
| `docker events --filter event=oom --since 1h` | OOM history |
| `docker update --cpus 2 --memory 1g CONTAINER` | Raise limits live, no restart |
| `docker exec -it CONTAINER sh` then language-specific profiling | `jstack`/`jmap` (Java), `py-spy dump` (Python), `pprof`/`GODEBUG=gctrace=1` (Go), `--inspect` (Node) |

> 🔑 **`docker stats` MEM% is against the container's limit, not the host's.** 90% of 256 MB is fine; 90% of "no limit" means it's eating your host. Always check whether a limit exists first.

---

## 37. Real-time scenario: "Container cannot connect to another container"

| Command | Explanation |
|---|---|
| `docker network ls` | Which networks exist? Are both containers on the same one? |
| `docker network inspect NET -f '{{range .Containers}}{{.Name}} {{end}}'` | Who's actually attached |
| `docker inspect -f '{{json .NetworkSettings.Networks}}' CONTAINER` | Both sides — compare network names |
| `docker exec CONTAINER getent hosts SERVICE` | Does Docker DNS resolve the name? (Empty = wrong name or wrong network.) |
| `docker exec CONTAINER ping -c1 SERVICE` | ICMP reachability (note: some images have no `ping`) |
| `docker exec CONTAINER nc -zv SERVICE 5432` | **Is the port actually open?** (the real test — DNS can work while the port is closed) |
| `docker exec CONTAINER wget -qO- http://SERVICE:8000/health` | Application-level check |
| `docker port CONTAINER` | Published mappings (only relevant for host → container) |
| `docker exec CONTAINER cat /etc/resolv.conf` | Should point at `127.0.0.11` (Docker's embedded DNS) |
| `docker network connect NET CONTAINER` | Attach to the missing network — instant fix |
| `docker network disconnect NET CONTAINER` | Remove a wrong attachment |
| `docker run --rm --network NET nicolaka/netshoot bash` | A debug container **on that network** with dig/tcpdump/curl/nc/mtr |
| `docker exec CONTAINER ip route` | Routing table inside |
| `iptables -L -n \| grep DROP` (host) | Is a host firewall dropping inter-bridge traffic? |

**The diagnostic ladder, in order:**

```
1. Same network?          docker network inspect + docker inspect
2. DNS resolves?          getent hosts <service>
3. Port open?             nc -zv <service> <port>
4. App listening on 0.0.0.0 (not 127.0.0.1)?    ss -tulpn inside the target
5. App actually up?       docker ps → (healthy)?  docker logs
6. Firewall / iptables?   host-level
```

**The four causes, ranked by frequency:**

| # | Cause | Fix |
|---|---|---|
| 1 | The app uses `localhost` / `127.0.0.1` for the peer | Use the **service name** (`db`, `cache`) — `localhost` means "this container" |
| 2 | The two containers are on **different networks** (or one is on the default `bridge`, which has no name DNS) | `docker network connect`, or put both on a user-defined network |
| 3 | The target app binds to `127.0.0.1` inside its container | Bind to `0.0.0.0` (`--host 0.0.0.0`, `bind-address=0.0.0.0`, `listen 0.0.0.0:8000`) |
| 4 | The target isn't ready yet / crashed | Healthchecks + `depends_on: {condition: service_healthy}` |

> 🔑 **Interview point:** on a **user-defined bridge** network, containers resolve each other by **container name, service name, or network alias** through Docker's embedded DNS at `127.0.0.11`. Never hard-code container IPs — they change on every recreate. On the **default** `bridge` network, name resolution does **not** work (only the deprecated `--link`), which is exactly why you should always create your own network.

---

## 38. Real-time scenario: "Docker disk is full"

| Command | Explanation |
|---|---|
| `docker system df` | Totals + **reclaimable** for images, containers, volumes, build cache |
| `docker system df -v` | Per-object breakdown — find the actual hog |
| `docker buildx du` | Build cache usage per builder (often the surprise winner) |
| `docker ps -as` | Container **writable-layer** sizes (`-s`) — an app writing into its own FS |
| `docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}' \| sort -k3 -h` | Largest images |
| `docker volume ls -q \| xargs -I{} docker volume inspect -f '{{.Name}} {{.Mountpoint}}' {}` | Every volume and where it lives |
| `sudo du -sh /var/lib/docker/*` | Host-level truth: `overlay2`, `volumes`, `image`, `containers` |
| `docker inspect -f '{{.LogPath}}' C \| xargs sudo du -h` | **Unrotated json logs** — a very common culprit |
| `docker image prune -f` | Dangling `<none>` images (safe) |
| `docker container prune -f --filter until=24h` | Old stopped containers |
| `docker builder prune -af` | Build cache — usually frees the most |
| `docker network prune -f` | Unused networks |
| `docker volume prune -f` | ⚠️ Unused volumes — **check nothing important is orphaned first** |
| `docker system prune -af` | All of the above except volumes |

**Safe, ordered cleanup — run top to bottom and stop when you've reclaimed enough:**

```bash
docker system df                                   # 1. LOOK before you delete
sudo du -sh /var/lib/docker/overlay2 /var/lib/docker/volumes /var/lib/docker/containers
docker image prune -f                              # 2. dangling images (always safe)
docker container prune -f --filter until=24h       # 3. old stopped containers
docker builder prune -af                           # 4. build cache (biggest win, slows next build)
docker image prune -af --filter until=168h         # 5. unused images older than a week
docker volume ls -f dangling=true                  # 6. INSPECT orphaned volumes…
docker volume inspect <name>                       #    …confirm they're disposable…
docker volume prune -f                             #    …only then prune
docker system df                                   # 7. confirm you got the space back
```

**Then stop it recurring:**

```jsonc
// /etc/docker/daemon.json  →  sudo systemctl restart docker
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3", "compress": "true" },
  "storage-driver": "overlay2"
}
```
```bash
# cron: reclaim build cache weekly, never touch volumes
echo '0 4 * * 0 root docker builder prune -af --filter until=168h && docker image prune -af --filter until=336h' \
  | sudo tee /etc/cron.d/docker-cleanup
```

---

## 39. Real-time scenario: "Debug image layers"

| Command | Explanation |
|---|---|
| `docker history IMAGE` | Every layer with its size and the instruction that created it |
| `docker history --human --format 'table {{.Size}}\t{{.CreatedBy}}' IMAGE` | Sorted, readable — **where did the megabytes go?** |
| `docker history --no-trunc IMAGE` | Untruncated instructions — **finds secrets leaked into `RUN` lines** |
| `docker history --no-trunc IMAGE \| grep -iE 'password\|secret\|token\|key'` | The leak check |
| `docker image inspect IMAGE` | Config (Env, Cmd, Entrypoint, User, ExposedPorts, Labels) + `RootFS.Layers` digests |
| `docker image inspect -f '{{len .RootFS.Layers}}' IMAGE` | Layer count (each layer = HTTP overhead on pull) |
| `docker images --no-trunc` | Full image IDs (the digest, not the 12-char prefix) |
| `docker images --digests` | Registry content digests — what you'd pin for reproducibility |
| `docker build --progress=plain .` | Full BuildKit output: each step, its cache status, its duration |
| `docker build --no-cache .` | Proves whether the cache was hiding a real failure |
| `docker build --target STAGE -t x .` | Materialise an intermediate stage and inspect it |
| `docker save IMAGE \| tar -tvf -` | List the archive contents without extracting |
| `docker save IMAGE -o img.tar && mkdir x && tar xf img.tar -C x && cat x/manifest.json` | See layers as individual tarballs; `jq .` each `*/json` |
| `docker create IMAGE && docker export CID \| tar -tvf - \| sort -k3 -h` | The **flattened** filesystem sorted by size — the definitive "what's in my image" |
| `docker run --rm IMAGE du -sh /* 2>/dev/null \| sort -h` | Same thing from inside (if the image has `du`) |
| `dive IMAGE` | Interactive TUI layer explorer (third-party, brilliant) |
| `docker scout sbom IMAGE` | Every package in the image |

```bash
# the definitive "why is my image 900 MB?" one-liner
cid=$(docker create myimage:1.0)
docker export $cid | tar -tvf - | sort -k3 -n -r | head -25
docker rm $cid

# and "which LAYER added it?"
docker history --no-trunc --human myimage:1.0 | head -20
```

> 🔑 **The rule that explains 90% of image bloat:** layers are **read-only and additive**. A file deleted in a *later* layer still exists in the earlier one and is still transferred, stored and pulled. Install **and** clean up in the **same `RUN`** — or better, use a multi-stage build so the junk never enters the final image at all.

---

## 40. Real-time scenario: "Production cleanup"

| Command | What it removes | Safety |
|---|---|---|
| `docker container prune` | Stopped containers | ✅ Safe |
| `docker image prune` | Dangling (`<none>`) images | ✅ Safe |
| `docker image prune -a` | Every image not used by an existing container | ⚠️ You'll re-pull on next build |
| `docker network prune` | Unused custom networks | ✅ Safe (`bridge`/`host`/`none` are never removed) |
| `docker builder prune` | BuildKit build cache | ⚠️ Safe but the next build is slower |
| `docker volume prune` | Volumes not mounted by any container | ☠️ **Can destroy a database** that happens to be stopped |
| `docker system prune` | Stopped containers + unused networks + dangling images + build cache | ✅ Safe |
| `docker system prune -a` | …plus all unused images | ⚠️ Aggressive |
| `docker system prune -a --volumes` | …plus unused volumes | ☠️☠️ **Never run blindly in production** |

**The production-safe cleanup script:**

```bash
#!/usr/bin/env bash
set -euo pipefail
# Reclaim space WITHOUT risking data. Run from cron weekly.
echo "== before =="; docker system df

docker container prune -f --filter "until=24h"
docker image    prune -af --filter "until=168h"      # 7 days
docker builder  prune -af --filter "until=168h"
docker network  prune -f

# volumes are listed for a HUMAN to review — never auto-pruned
echo "== orphaned volumes (review manually) =="
docker volume ls -f dangling=true

echo "== after =="; docker system df
```

> 🔑 **Label what must survive:** `docker volume create --label keep=true pgdata`, then `docker volume prune -f --filter label!=keep`. Same trick for containers and images. It turns a dangerous global command into a safe one.

---

## 41. Dockerfile commands vs Docker CLI

**This distinction is very important in interviews.** A Dockerfile instruction is a *build-time recipe line*; a CLI command is something *you* type against the daemon.

| Dockerfile instruction | Purpose | Example | Equivalent / related CLI |
|---|---|---|---|
| `FROM` | Selects the base image | `FROM node:22-alpine` | `docker pull node:22-alpine` |
| `RUN` | Executes commands **while building** | `RUN npm ci` | *(no CLI equivalent — it happens inside the build)* |
| `CMD` | Default **runtime** command / args | `CMD ["node","server.js"]` | overridden by `docker run IMAGE cmd…` |
| `ENTRYPOINT` | The fixed executable; args are appended | `ENTRYPOINT ["node"]` | overridden by `docker run --entrypoint` |
| `COPY` | Files from the **build context** into the image | `COPY . /app` | `docker cp` (into a *container*, not an image) |
| `ADD` | `COPY` + URL download + local tar auto-extract | `ADD app.tar /app` | — |
| `WORKDIR` | Sets/creates the working directory | `WORKDIR /app` | `docker run -w /app` |
| `ENV` | Runtime environment variable (persists in the image) | `ENV NODE_ENV=production` | `docker run -e NODE_ENV=production` |
| `ARG` | **Build-time** variable (gone after the build) | `ARG VERSION=1.0` | `docker build --build-arg VERSION=1.0` |
| `EXPOSE` | **Documents** the listening port | `EXPOSE 8080` | actually published by `docker run -p 8080:8080` |
| `USER` | Default runtime user | `USER node` | `docker run -u 1000` |
| `VOLUME` | Declares a mount point | `VOLUME /data` | `docker run -v data:/data` |
| `HEALTHCHECK` | Container health test | `HEALTHCHECK CMD curl -f http://localhost:8080/health` | inspected via `docker inspect`; overridable with `--no-healthcheck` |
| `LABEL` | Image metadata | `LABEL app=backend` | `docker run --label`, `docker build --label` |
| `SHELL` | Changes the shell used by shell-form commands | `SHELL ["/bin/bash","-c"]` | — |
| `STOPSIGNAL` | Signal used to stop the container | `STOPSIGNAL SIGTERM` | `docker run --stop-signal`, `docker stop` |
| `ONBUILD` | Trigger executed when another image uses this one as a base | `ONBUILD COPY . /app` | — |
| `MAINTAINER` | ❌ **Deprecated** | — | use `LABEL maintainer=` |

**The mapping that matters most:**

| Dockerfile says | CLI decides |
|---|---|
| `EXPOSE 8080` | `-p 8080:8080` ← nothing is reachable without this |
| `ARG VERSION` | `--build-arg VERSION=2.0` ← build time only |
| `ENV VERSION` | `-e VERSION=2.0` ← overrides the image at run time |
| `CMD ["a","b"]` | `docker run img c d` ← **replaces** CMD |
| `ENTRYPOINT ["a"]` | `docker run img b` ← **appends** to ENTRYPOINT |
| `USER app` | `--user 0` ← overrides it (so `USER` is hygiene, not security) |
| `VOLUME /data` | `-v mydata:/data` ← names it, or Docker makes an anonymous one |
| `HEALTHCHECK` | `--no-healthcheck` ← can be disabled at run time |

---

## 42. Most important flags to memorize

### The everyday twelve

| Flag | Meaning | Real-world example |
|---|---|---|
| `-d` | Detached / background | `docker run -d nginx` |
| `-it` | Interactive + TTY | `docker exec -it web sh` |
| `-p` | Publish a port (`host:container`) | `-p 8080:80` |
| `-v` | Volume or bind mount (`src:dst[:ro]`) | `-v data:/data` |
| `-e` | Environment variable | `-e ENV=prod` |
| `--name` | Container name | `--name api` |
| `--rm` | Auto-remove on exit | `docker run --rm alpine echo hi` |
| `-f` | **Follow** (logs) *or* **filter** (ps/images) *or* **file** (build/compose) — depends on the command! | `docker logs -f` · `docker ps -f status=exited` · `docker build -f Dockerfile.prod` · `docker compose -f prod.yml` |
| `-q` | Quiet / IDs only | `docker ps -q` |
| `-a` | All | `docker ps -a` |
| `-t` | **Tag** (build) *or* **TTY** (run/exec) *or* **timestamps** (logs) *or* **timeout** (stop) | `docker build -t app .` · `docker exec -it` · `docker logs -t` · `docker stop -t 30` |
| `-P` | Publish **all** exposed ports to random host ports | `docker run -P nginx` |

> ⚠️ `-f`, `-t` and `-a` are **overloaded** — their meaning changes per command. That's the single biggest source of beginner flag confusion. When unsure: `docker COMMAND --help`.

### Build flags

| Flag | Meaning | Example |
|---|---|---|
| `-t` | Tag the result | `docker build -t app:1.0 .` |
| `-f` | Which Dockerfile | `docker build -f Dockerfile.prod .` |
| `--build-arg` | Feed an `ARG` | `--build-arg VERSION=1.2` |
| `--target` | Stop at a named stage | `--target builder` |
| `--no-cache` | Ignore all cached layers | `--no-cache` |
| `--pull` | Re-pull base images | `--pull` |
| `--progress=plain` | Full uncollapsed output | `--progress=plain` |
| `--platform` | Target architecture | `--platform linux/amd64` |
| `--secret` | BuildKit secret mount | `--secret id=npmrc,src=$HOME/.npmrc` |
| `--ssh` | BuildKit SSH agent forwarding | `--ssh default` |
| `--cache-from` / `--cache-to` | Registry/GHA/local cache | `--cache-to type=gha,mode=max` |
| `--load` / `--push` | buildx output destination | `buildx build --push` |

### Run / security flags

| Flag | Meaning | Example |
|---|---|---|
| `-u` / `--user` | Run as this uid[:gid] | `--user 1000:1000` |
| `-w` | Working directory | `-w /app` |
| `--entrypoint` | **Override ENTRYPOINT** — the debug escape hatch | `--entrypoint sh` |
| `--network` | Attach to a network | `--network app-net` |
| `--restart` | Restart policy | `--restart unless-stopped` |
| `--read-only` | Immutable root filesystem | `--read-only --tmpfs /tmp` |
| `--tmpfs` | Writable in-memory path | `--tmpfs /tmp:size=32m` |
| `--mount` | Explicit, fail-loud mount | `--mount type=bind,src=$PWD,dst=/app` |
| `--cap-drop` / `--cap-add` | Linux capabilities | `--cap-drop ALL --cap-add NET_BIND_SERVICE` |
| `--security-opt` | Security options | `--security-opt no-new-privileges:true` |
| `--privileged` | ⚠️ All capabilities + devices — avoid | `--privileged` |
| `--init` | Inject tini as PID 1 | `--init` |
| `-m` / `--memory` | Hard memory limit | `-m 512m` |
| `--memory-swap` | Memory + swap total | `--memory-swap 1g` |
| `--cpus` | CPU quota | `--cpus=1.5` |
| `--pids-limit` | Fork-bomb protection | `--pids-limit=200` |
| `--ulimit` | Raise fd/process limits | `--ulimit nofile=65535:65535` |
| `--log-opt` | Log rotation | `--log-opt max-size=10m --log-opt max-file=3` |
| `--stop-timeout` | Grace period before SIGKILL | `--stop-timeout 30` |
| `--secret` | Runtime secret file | `--secret id=aws,src=./creds` |
| `--env-file` | Bulk env vars | `--env-file .env` |
| `--label` | Metadata for filtering | `--label env=prod` |
| `--platform` | Force architecture | `--platform linux/amd64` |
| `--cidfile` | Write the ID to a file | `--cidfile web.cid` |

### Inspect / output flags

| Flag | Meaning | Example |
|---|---|---|
| `--format '{{...}}'` | Go template output | `docker ps --format '{{.Names}}\t{{.Status}}'` |
| `--no-trunc` | Full IDs and commands | `docker history --no-trunc` |
| `-f` / `--filter` | Filter the listing | `docker ps -f health=unhealthy` |
| `--digests` | Registry digests | `docker images --digests` |
| `-s` | Sizes | `docker ps -s` |
| `--pretty` | Human-readable inspect | `docker node inspect worker1 --pretty` |

---

## 43. The commands you should be able to use without thinking

For **3+ YOE interviews**, these are the highest-frequency commands. Type each one until it's muscle memory.

```text
# ── containers ────────────────────────────────────────────────
docker ps
docker ps -a
docker ps -af status=exited
docker run -d --name X -p 8080:80 -e K=V -v data:/data --restart unless-stopped IMAGE
docker run --rm -it --entrypoint sh IMAGE
docker exec -it CONTAINER sh
docker logs -f --tail 100 CONTAINER
docker inspect -f '{{.State.ExitCode}} {{.State.OOMKilled}}' CONTAINER
docker stats --no-stream
docker top CONTAINER
docker cp CONTAINER:/path ./
docker port CONTAINER
docker diff CONTAINER
docker stop -t 30 CONTAINER
docker start CONTAINER
docker restart CONTAINER
docker rm -f CONTAINER
docker container prune -f
docker events --filter event=die
docker update --memory 1g CONTAINER
docker wait CONTAINER

# ── images ────────────────────────────────────────────────────
docker images
docker pull IMAGE:TAG
docker build -t NAME:TAG .
docker build --progress=plain --no-cache -t NAME .
docker build --target STAGE -t NAME:debug .
docker build --build-arg K=V -t NAME .
docker build --secret id=X,src=./x -t NAME .
docker tag app:1.0 registry/user/app:1.0
docker push registry/user/app:1.0
docker rmi IMAGE
docker history --human IMAGE
docker image inspect -f '{{.Os}}/{{.Architecture}}' IMAGE
docker save IMAGE -o img.tar
docker load -i img.tar
docker image prune -af
docker scout cves IMAGE

# ── buildx / multi-arch ───────────────────────────────────────
docker buildx ls
docker buildx create --use --name multiarch
docker buildx inspect --bootstrap
docker buildx build --platform linux/amd64,linux/arm64 -t REG/APP:1.0 --push .
docker buildx imagetools inspect REG/APP:1.0
docker buildx prune -af

# ── networks ──────────────────────────────────────────────────
docker network ls
docker network create app-net
docker network inspect app-net
docker network connect app-net CONTAINER
docker network disconnect app-net CONTAINER
docker network prune -f

# ── volumes ───────────────────────────────────────────────────
docker volume ls
docker volume ls -f dangling=true
docker volume create db-data
docker volume inspect -f '{{.Mountpoint}}' db-data
docker volume rm db-data
docker run --rm -v db-data:/d alpine ls -la /d

# ── compose ───────────────────────────────────────────────────
docker compose config
docker compose build
docker compose up -d --wait
docker compose up -d --scale api=3
docker compose ps
docker compose logs -f api
docker compose exec api sh
docker compose run --rm api pytest
docker compose port web 80
docker compose restart api
docker compose down
docker compose down -v          # ☠️ know exactly when NOT to type this

# ── registry ──────────────────────────────────────────────────
docker login
echo "$TOKEN" | docker login ghcr.io -u me --password-stdin
docker logout

# ── system ────────────────────────────────────────────────────
docker version
docker info
docker system df
docker system df -v
docker system prune -af
docker context ls
docker context use prod

# ── swarm (interviews) ────────────────────────────────────────
docker swarm init
docker swarm join-token worker
docker node ls
docker node update --availability drain NODE
docker service create --name web --replicas 3 -p 8080:80 nginx
docker service ls
docker service ps --no-trunc web
docker service logs -f web
docker service scale web=6
docker service update --image nginx:1.29 web
docker service rollback web
docker stack deploy -c docker-stack.yml app
docker stack ls
docker stack ps app
docker stack rm app
docker secret create NAME -
docker config create NAME ./file
docker network create -d overlay --attachable prod-net
```

---

## 44. Exit codes and signal reference

### Exit codes

| Code | Formula | Meaning | Typical cause in Docker |
|---|---|---|---|
| `0` | — | Success / clean exit | Your `CMD` was a one-shot command, not a server → container "dies" immediately |
| `1` | — | Application error | Unhandled exception; read `docker logs` |
| `2` | — | Shell misuse / bad argument | Malformed entrypoint script |
| `125` | — | `docker run` command itself failed | Bad flag, invalid `-v` path, name conflict |
| `126` | — | Found but not executable | Missing `chmod +x`; use `COPY --chmod=755` |
| `127` | — | **Command not found** | Typo, wrong `WORKDIR`, binary not in `PATH`, missing package |
| `128` | — | Invalid exit argument | — |
| `134` | 128+6 `SIGABRT` | Abort | C/C++ assertion failure |
| `137` | 128+9 `SIGKILL` | **Killed** | 🥇 **OOM kill** (`OOMKilled=true`) · `docker kill` · `docker stop` grace period expired |
| `139` | 128+11 `SIGSEGV` | Segfault | Native library crash, architecture mismatch |
| `143` | 128+15 `SIGTERM` | Terminated | A **normal** `docker stop` — usually not an error |
| `159` | 128+31 `SIGSYS` | Bad syscall | Seccomp profile blocked a syscall |
| `255` | — | Out-of-range / generic | Shell script exiting badly |

```bash
docker inspect -f 'ExitCode={{.State.ExitCode}} OOMKilled={{.State.OOMKilled}} Error={{.State.Error}}' CONTAINER
docker ps -af exited=137          # every OOM-killed container on this host
```

### Signals

| Signal | Number | Sent by | Behaviour |
|---|---|---|---|
| `SIGHUP` | 1 | you (`docker kill -s HUP`) | Convention: **reload config** without restarting (nginx, haproxy) |
| `SIGINT` | 2 | `Ctrl-C` on an attached container | Interrupt — apps usually treat it like TERM |
| `SIGQUIT` | 3 | `docker stop` on nginx images | nginx **graceful** shutdown (why nginx sets `STOPSIGNAL SIGQUIT`) |
| `SIGKILL` | 9 | kernel OOM killer, `docker kill`, or `docker stop` after the grace period | **Cannot be caught.** Immediate death, no cleanup, data can be corrupted |
| `SIGTERM` | 15 | `docker stop` (the default `STOPSIGNAL`) | **Polite request to shut down.** Your app should catch it, drain, flush, exit 0 |
| `SIGUSR1/2` | 10/12 | you | App-defined — often "dump state" or "rotate logs" |

**The graceful-shutdown chain:**

```
docker stop C
   → sends STOPSIGNAL (default SIGTERM) to PID 1
   → waits --stop-timeout / -t N / stop_grace_period (default 10s)
   → sends SIGKILL (uncatchable) to everything in the cgroup
   → exit code 137 if it had to be killed
```

**Why your app never sees SIGTERM** — the PID 1 problem:

```dockerfile
CMD npm start          # shell form → PID 1 is /bin/sh -c, which does NOT forward signals → SIGKILL after 10s
CMD ["npm", "start"]   # exec form  → PID 1 is npm, which DOES receive SIGTERM → clean shutdown ✅
```
```sh
#!/bin/sh
node server.js         # sh stays PID 1, node is a child → signals lost
exec node server.js    # exec REPLACES sh → node becomes PID 1 → signals delivered ✅
```
Or let Docker handle it: `docker run --init` injects **tini** as PID 1, which forwards signals and reaps zombies.

---

## 45. Go-template `--format` recipes

`--format` uses Go templates. Works on `ps`, `images`, `inspect`, `volume ls`, `network ls`, `system df`, `service ls`, `node ls`, `stats`, `events`, `buildx ls`…

```bash
# ── containers ────────────────────────────────────────────────
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
docker ps -a --format '{{.Names}}|{{.State}}|{{.Status}}' | column -t -s'|'
docker ps -aq --format '{{.Names}}'                        # names only, for scripting
docker ps --format '{{.Names}} {{.RunningFor}}' --filter health=unhealthy

# ── images ────────────────────────────────────────────────────
docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedSince}}'
docker images --format '{{.Repository}}:{{.Tag}}' | grep -v '<none>'
docker images --format '{{.Size}}\t{{.Repository}}:{{.Tag}}' | sort -h | tail -10   # 10 biggest

# ── inspect: the debugging goldmine ───────────────────────────
docker inspect C --format 'status={{.State.Status}} exit={{.State.ExitCode}} oom={{.State.OOMKilled}} restarts={{.RestartCount}}'
docker inspect C --format 'started={{.State.StartedAt}} finished={{.State.FinishedAt}}'
docker inspect C --format 'cmd={{json .Config.Cmd}} entry={{json .Config.Entrypoint}} user="{{.Config.User}}"'
docker inspect C --format '{{range .Config.Env}}{{println .}}{{end}}'
docker inspect C --format '{{range .Mounts}}{{.Type}} {{.Source}} -> {{.Destination}} ({{if .RW}}rw{{else}}ro{{end}}){{println}}{{end}}'
docker inspect C --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} ip={{$v.IPAddress}} gw={{$v.Gateway}}{{println}}{{end}}'
docker inspect C --format 'mem={{.HostConfig.Memory}} nanoCpus={{.HostConfig.NanoCpus}} pids={{.HostConfig.PidsLimit}} readonly={{.HostConfig.ReadonlyRootfs}}'
docker inspect C --format '{{.State.Health.Status}} failing={{.State.Health.FailingStreak}}'
docker inspect C --format '{{json .State.Health.Log}}' | jq .
docker inspect C --format '{{.LogPath}}'

# ── images (inspect) ──────────────────────────────────────────
docker image inspect I --format '{{.Os}}/{{.Architecture}}  size={{.Size}}  layers={{len .RootFS.Layers}}'
docker image inspect I --format 'user="{{.Config.User}}" workdir={{.Config.WorkingDir}}'
docker image inspect I --format '{{json .Config.Labels}}' | jq .
docker image inspect I --format '{{json .Config.ExposedPorts}}'

# ── volumes & networks ────────────────────────────────────────
docker volume ls --format '{{.Name}}'
docker volume inspect V --format '{{.Driver}} {{.Mountpoint}} {{json .Options}}'
docker network ls --format 'table {{.Name}}\t{{.Driver}}\t{{.Scope}}'
docker network inspect N --format '{{range .Containers}}{{.Name}}={{.IPv4Address}} {{end}}'

# ── stats / events / system ───────────────────────────────────
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}'
docker events --format '{{.Time}} {{.Type}} {{.Action}} {{.Actor.Attributes.name}}'
docker system df --format 'table {{.Type}}\t{{.TotalCount}}\t{{.Size}}\t{{.Reclaimable}}'
docker container ls -s --format '{{.Names}} {{.Size}}'

# ── compose & swarm ───────────────────────────────────────────
docker compose ps --format 'table {{.Name}}\t{{.Service}}\t{{.Status}}\t{{.Ports}}'
docker service ls --format 'table {{.Name}}\t{{.Image}}\t{{.Replicas}}'
docker service ps S --format '{{.Name}} {{.CurrentState}} {{.Error}}'
docker node ls --format '{{.Hostname}} {{.Status}} {{.Availability}} {{.ManagerStatus}}'

# ── the "kill everything of mine" one-liner ───────────────────
docker rm -f $(docker ps -aq --filter "label=owner=me") 2>/dev/null
docker rmi -f $(docker images -q --filter "reference=tasknest-*") 2>/dev/null
```

**Template cheat:**
- `{{.Field}}` — a field · `{{json .Field}}` — as JSON (pipe to `jq`)
- `{{range .List}}…{{end}}` — loop · `{{range $k,$v := .Map}}{{$k}}={{$v}}{{end}}` — loop a map
- `{{if .RW}}rw{{else}}ro{{end}}` — conditional · `{{println}}` — newline
- `table ` prefix — auto-aligned columns with a header row
- `\t` — tab. In bash use single quotes so the shell doesn't eat the backslash.

---

## 46. 🔥 The real interview mastery sequence

Don't learn these as isolated commands. Learn them as **production workflows** — that's the command + flag + *scenario* relationship interviewers expect from someone claiming real-world Docker experience.

### 1. Build
```
Dockerfile  →  docker build -t app:1.0 .  →  docker images  →  docker history --human app
                    --progress=plain  --no-cache  --target  --build-arg
```

### 2. Run
```
docker run  →  -d  →  --name  →  -p 8080:80  →  -e / --env-file  →  -v / --mount
            →  --network  →  --restart unless-stopped  →  --read-only --tmpfs  →  -u 1000
```

### 3. Debug
```
docker ps -a  →  docker logs -f --tail 200  →  docker inspect -f '{{.State.ExitCode}} {{.State.OOMKilled}}'
             →  docker exec -it C sh  →  docker top C  →  docker stats  →  docker diff C
             →  docker run --rm -it --entrypoint sh IMAGE     ← when it won't stay up
```

### 4. Networking
```
docker network ls  →  create  →  inspect  →  run --network NET  →  exec getent hosts PEER
                   →  exec nc -zv PEER PORT  →  network connect / disconnect  →  docker port C
```

### 5. Storage
```
docker volume create  →  inspect -f '{{.Mountpoint}}'  →  run -v vol:/path  →  verify persistence
                      →  backup (tar via a helper container)  →  restore  →  ls -f dangling=true  →  prune
```

### 6. Compose
```
docker compose config  →  build  →  up -d --wait  →  ps  →  logs -f SERVICE  →  exec SERVICE sh
                       →  run --rm SERVICE pytest  →  restart  →  scale  →  down   (never -v by accident)
```

### 7. Registry
```
docker login (--password-stdin)  →  build -t REG/USER/app:1.0  →  push  →  pull on another machine
                                 →  buildx build --platform amd64,arm64 --push  →  imagetools inspect
                                 →  scout cves / trivy --exit-code 1
```

### 8. Production hardening
```
HEALTHCHECK (liveness vs readiness)  →  resource limits (-m, --cpus, --pids-limit)
   →  non-root USER  →  --read-only + --tmpfs  →  --cap-drop ALL  →  no-new-privileges
   →  secrets (--secret, /run/secrets, *_FILE)  →  log rotation (max-size/max-file)
   →  scanning in CI  →  pinned image tags/digests  →  stop_grace_period + SIGTERM handling
```

### 9. Multi-stage / BuildKit
```
docker build  →  --target STAGE (debug an intermediate)  →  --no-cache (is the cache lying?)
              →  --build-arg  →  RUN --mount=type=cache (fast rebuilds)
              →  RUN --mount=type=secret (no leaks)  →  buildx --platform (multi-arch)
              →  --cache-from/--cache-to type=gha (CI)  →  --provenance --sbom
```

### 10. Troubleshooting (the universal order)
```
docker ps -a                    →  what state is it in?
docker logs --tail 200          →  what did the app say?
docker inspect --format ...     →  exit code / OOM / mounts / networks / cmd
docker exec -it C sh            →  look inside (or --entrypoint sh if it won't start)
docker network inspect          →  can it reach its peers?
docker stats                    →  is it resource-starved?
docker events --since 1h        →  what did the daemon do?
docker system df -v             →  is the host out of disk?
docker history --no-trunc       →  is the image itself the problem?
```

---

## 🎯 The 20 lines that matter most

If you memorise nothing else from this file, memorise these:

```bash
docker build -t app:1.0 .                                     # make it
docker run -d --name app -p 8080:80 -e K=V -v data:/data app  # run it
docker ps -a                                                   # what's happening
docker logs -f --tail 200 app                                  # why
docker exec -it app sh                                         # go inside
docker inspect -f '{{.State.ExitCode}} {{.State.OOMKilled}}' app   # how it died
docker stats --no-stream                                       # what it costs
docker run --rm -it --entrypoint sh app                        # debug a broken image
docker history --human app                                     # where the size went
docker network inspect -f '{{range .Containers}}{{.Name}} {{end}}' net   # who can talk to whom
docker volume inspect -f '{{.Mountpoint}}' data                # where the data lives
docker compose config                                          # validate before you deploy
docker compose up -d --wait                                    # bring up the whole stack
docker compose ps && docker compose logs -f api                # watch it
docker compose exec api sh                                     # into a service
docker compose down                                            # take it down (data safe)
docker system df -v                                            # where did my disk go
docker image prune -af && docker builder prune -af             # reclaim it safely
docker buildx build --platform linux/amd64,linux/arm64 -t REG/app:1.0 --push .   # ship it
docker scout cves app:1.0                                      # is it safe
```

---

**Related files:** [`01-DOCKERFILE-GUIDE.md`](01-DOCKERFILE-GUIDE.md) · [`03-CHEATSHEET.md`](03-CHEATSHEET.md) · [`00-ONE-DAY-MASTER-PLAN.md`](00-ONE-DAY-MASTER-PLAN.md) · [`02-CAPSTONE-END-TO-END.md`](02-CAPSTONE-END-TO-END.md)

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
