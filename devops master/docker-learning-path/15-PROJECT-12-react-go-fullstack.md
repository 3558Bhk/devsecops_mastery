# PROJECT 12 · ⚛️ React + 🐹 Go — Full Stack

> **Part of the Docker Learning Path.** Previous: [`14-PROJECT-11-react-python-fullstack.md`](14-PROJECT-11-react-python-fullstack.md) — Project 11 — React + Python.
>
> 🎯 **Instructions & techniques:** multi-stage · `CGO_ENABLED=0` · `-ldflags="-s -w"` · `-trimpath` · `FROM scratch` · cross-compilation
>
> 📚 **What you learn:** Static binaries, the smallest possible production image, debugging a container that has no shell
>
> 🔁 **Every project here is written TWICE:**
> - **🔵 CASE 1 — a SIMPLE Dockerfile.** Easy to read, easy to get working, usually too big for production.
> - **🟢 CASE 2 — a MULTI-STAGE Dockerfile.** The production version: smaller, faster to rebuild, more secure, tests can fail the build.
>
> **Build Case 1 first**, run it, understand it — then build Case 2 and **measure the difference**. That comparison *is* the lesson.

---

# D.5 — PROJECT 12 · ⚛️ React + 🐹 Go (Full Stack)

**🎯 What you learn:** the smallest possible production stack — a **static** Go binary in `FROM scratch` behind nginx. Cross-compilation, `CGO_ENABLED=0`, build caching for Go modules, and debugging an image that has no shell.

## 12.0 Structure

```
12-react-go-fullstack/
├── docker-compose.yml
├── Makefile
├── .env.example
├── frontend/                ← Project 8 (Case 2)
└── backend/
    ├── go.mod
    ├── main.go
    ├── handlers.go
    ├── store.go
    ├── Dockerfile           ← CASE 1 (simple)
    ├── Dockerfile.multistage← CASE 2
    ├── Dockerfile.scratch   ← CASE 2 extreme
    └── main_test.go
```

### `backend/go.mod`

```
module github.com/example/tasknest-go

go 1.23
```

### `backend/store.go`

```go
package main

import (
	"sort"
	"sync"
	"time"
)

type Task struct {
	ID        int64     `json:"id"`
	Title     string    `json:"title"`
	Priority  string    `json:"priority"`
	Tags      []string  `json:"tags"`
	Done      bool      `json:"done"`
	CreatedAt time.Time `json:"created_at"`
}

type Store struct {
	mu    sync.RWMutex
	seq   int64
	tasks map[int64]Task
}

func NewStore() *Store {
	s := &Store{tasks: make(map[int64]Task)}
	s.Create("Learn FROM, RUN and CMD", "high", []string{"docker", "basics"})
	s.Create("Master ENTRYPOINT vs CMD", "medium", []string{"docker"})
	s.Create("Ship a Go binary in scratch", "high", []string{"docker", "go"})
	return s
}

func (s *Store) Create(title, priority string, tags []string) Task {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.seq++
	if priority == "" {
		priority = "medium"
	}
	if tags == nil {
		tags = []string{}
	}
	t := Task{ID: s.seq, Title: title, Priority: priority, Tags: tags, CreatedAt: time.Now().UTC()}
	s.tasks[t.ID] = t
	return t
}

func (s *Store) List(status, priority string, limit int) []Task {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]Task, 0, len(s.tasks))
	for _, t := range s.tasks {
		if status == "done" && !t.Done {
			continue
		}
		if status == "todo" && t.Done {
			continue
		}
		if priority != "" && t.Priority != priority {
			continue
		}
		out = append(out, t)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Done != out[j].Done {
			return !out[i].Done
		}
		return out[i].ID > out[j].ID
	})
	if limit > 0 && len(out) > limit {
		out = out[:limit]
	}
	return out
}

func (s *Store) Get(id int64) (Task, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	t, ok := s.tasks[id]
	return t, ok
}

func (s *Store) Toggle(id int64) (Task, bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	t, ok := s.tasks[id]
	if !ok {
		return t, false
	}
	t.Done = !t.Done
	s.tasks[id] = t
	return t, true
}

func (s *Store) Delete(id int64) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.tasks[id]; !ok {
		return false
	}
	delete(s.tasks, id)
	return true
}

func (s *Store) Stats() map[string]any {
	s.mu.RLock()
	defer s.mu.RUnlock()
	total, done, high := len(s.tasks), 0, 0
	for _, t := range s.tasks {
		switch {
		case t.Done:
			done++
		case t.Priority == "high":
			high++
		}
	}
	pct := 0.0
	if total > 0 {
		pct = float64(int(float64(done)/float64(total)*1000)) / 10
	}
	return map[string]any{"total": total, "done": done, "todo": total - done,
		"urgent_high": high, "completion_pct": pct}
}
```

### `backend/handlers.go`

```go
package main

import (
	"encoding/json"
	"net/http"
	"os"
	"runtime"
	"strconv"
	"strings"
	"time"
)

var (
	store     = NewStore()
	startTime = time.Now()
	version   = envOr("APP_VERSION", "0.0.0-dev")
	commit    = envOr("GIT_COMMIT", "unknown")
)

func envOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("X-App-Version", version)
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func errJSON(w http.ResponseWriter, code int, msg string) {
	writeJSON(w, code, map[string]string{"error": msg})
}

// stripPrefix lets the same handler answer /api/tasks and /tasks
func stripPrefix(p string) string {
	return strings.TrimPrefix(p, "/api")
}

func infoHandler(w http.ResponseWriter, r *http.Request) {
	host, _ := os.Hostname()
	writeJSON(w, http.StatusOK, map[string]any{
		"service": "tasknest-go", "version": version, "commit": commit,
		"go": runtime.Version(), "hostname": host, "pid": os.Getpid(),
		"uptime_seconds": int64(time.Since(startTime).Seconds()),
		"server":         "net/http (stdlib)",
		"routes": []string{"/api/health", "/api/ready", "/api/info", "/api/tasks",
			"/api/tasks/{id}", "/api/tasks/{id}/toggle", "/api/stats"},
	})
}

func healthHandler(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"status": "ok", "uptime_seconds": int64(time.Since(startTime).Seconds()),
	})
}

func readyHandler(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"ready": true, "checks": map[string]bool{"database": true, "cache": true},
	})
}

func tasksHandler(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		q := r.URL.Query()
		limit, _ := strconv.Atoi(q.Get("limit"))
		if limit <= 0 {
			limit = 100
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"source": "database",
			"tasks":  store.List(q.Get("status"), q.Get("priority"), limit),
		})
	case http.MethodPost:
		var body struct {
			Title    string   `json:"title"`
			Priority string   `json:"priority"`
			Tags     []string `json:"tags"`
		}
		if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
			return errJSON(w, http.StatusBadRequest, "invalid JSON")
		}
		body.Title = strings.TrimSpace(body.Title)
		if body.Title == "" {
			return errJSON(w, http.StatusBadRequest, "'title' is required")
		}
		if len(body.Title) > 300 {
			return errJSON(w, http.StatusBadRequest, "'title' must be <= 300 chars")
		}
		switch strings.ToLower(body.Priority) {
		case "", "low", "medium", "high":
		default:
			return errJSON(w, http.StatusBadRequest, "'priority' must be low|medium|high")
		}
		writeJSON(w, http.StatusCreated, store.Create(body.Title, strings.ToLower(body.Priority), body.Tags))
	default:
		errJSON(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}

func taskIDHandler(w http.ResponseWriter, r *http.Request) {
	p := stripPrefix(r.URL.Path)
	parts := strings.Split(strings.Trim(p, "/"), "/") // tasks/{id}[/toggle]
	if len(parts) < 2 {
		return errJSON(w, http.StatusNotFound, "no such route")
	}
	id, err := strconv.ParseInt(parts[1], 10, 64)
	if err != nil {
		return errJSON(w, http.StatusBadRequest, "id must be an integer")
	}
	toggle := len(parts) == 3 && parts[2] == "toggle"

	switch {
	case toggle && r.Method == http.MethodPost:
		t, ok := store.Toggle(id)
		if !ok {
			return errJSON(w, http.StatusNotFound, "task not found")
		}
		writeJSON(w, http.StatusOK, t)

	case r.Method == http.MethodGet:
		t, ok := store.Get(id)
		if !ok {
			return errJSON(w, http.StatusNotFound, "task not found")
		}
		writeJSON(w, http.StatusOK, t)

	case r.Method == http.MethodDelete:
		if !store.Delete(id) {
			return errJSON(w, http.StatusNotFound, "task not found")
		}
		writeJSON(w, http.StatusOK, map[string]int64{"deleted": id})

	default:
		errJSON(w, http.StatusMethodNotAllowed, "method not allowed")
	}
}

func statsHandler(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, store.Stats())
}
```

### `backend/main.go`

```go
package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"os/signal"
	"runtime"
	"syscall"
	"time"
)

func runtimeVersion() string { return runtime.Version() }

func main() {
	addr := ":" + envOr("PORT", "8000")

	mux := http.NewServeMux()
	mux.HandleFunc("/api/info", infoHandler)
	mux.HandleFunc("/api/health", healthHandler)
	mux.HandleFunc("/api/ready", readyHandler)
	mux.HandleFunc("/api/tasks", tasksHandler)
	mux.HandleFunc("/api/tasks/", taskIDHandler)
	mux.HandleFunc("/api/stats", statsHandler)
	// un-prefixed aliases
	mux.HandleFunc("/info", infoHandler)
	mux.HandleFunc("/health", healthHandler)
	mux.HandleFunc("/ready", readyHandler)
	mux.HandleFunc("/tasks", tasksHandler)
	mux.HandleFunc("/tasks/", taskIDHandler)
	mux.HandleFunc("/stats", statsHandler)

	srv := &http.Server{
		Addr:              addr,
		Handler:           logMiddleware(mux),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      20 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	// 🔑 graceful shutdown: drain in-flight requests on SIGTERM (docker stop)
	go func() {
		sig := make(chan os.Signal, 1)
		signal.Notify(sig, syscall.SIGTERM, syscall.SIGINT)
		s := <-sig
		log.Printf("received %s — draining…", s)
		ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		if err := srv.Shutdown(ctx); err != nil {
			log.Printf("graceful shutdown failed: %v", err)
		}
	}()

	log.Printf("🚀 tasknest-go %s (%s) listening on %s, pid=%d, go=%s",
		version, commit, addr, os.Getpid(), runtime.Version())
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("server error: %v", err)
	}
	log.Println("shutdown complete")
}

func logMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("%s %s %s", r.Method, r.URL.Path, time.Since(start).Round(time.Microsecond))
	})
}
```

### `backend/main_test.go`

```go
package main

import "testing"

func TestStoreCreateIncrements(t *testing.T) {
	s := NewStore()
	base := int64(len(s.tasks))
	a := s.Create("a", "low", nil)
	b := s.Create("b", "high", nil)
	if b.ID != a.ID+1 {
		t.Fatalf("expected consecutive ids, got %d and %d", a.ID, b.ID)
	}
	if int64(len(s.tasks)) != base+2 {
		t.Fatalf("expected %d tasks, got %d", base+2, len(s.tasks))
	}
}

func TestStoreToggle(t *testing.T) {
	s := NewStore()
	x := s.Create("t", "medium", nil)
	if x.Done {
		t.Fatal("new task should not be done")
	}
	got, ok := s.Toggle(x.ID)
	if !ok || !got.Done {
		t.Fatal("toggle should mark done")
	}
	got, _ = s.Toggle(x.ID)
	if got.Done {
		t.Fatal("second toggle should unmark")
	}
}

func TestStoreDelete(t *testing.T) {
	s := NewStore()
	x := s.Create("d", "low", nil)
	if !s.Delete(x.ID) {
		t.Fatal("delete should succeed")
	}
	if s.Delete(x.ID) {
		t.Fatal("second delete should fail")
	}
	if _, ok := s.Get(x.ID); ok {
		t.Fatal("task should be gone")
	}
}

func TestStoreFilters(t *testing.T) {
	s := NewStore()
	x := s.Create("f", "high", nil)
	s.Toggle(x.ID)
	if len(s.List("done", "", 0)) == 0 {
		t.Fatal("expected at least one done task")
	}
	if len(s.List("", "high", 0)) == 0 {
		t.Fatal("expected at least one high-priority task")
	}
}

func TestEnvOr(t *testing.T) {
	t.Setenv("X_TEST_VAR", "value")
	if envOr("X_TEST_VAR", "def") != "value" {
		t.Fatal("should read env")
	}
	if envOr("X_MISSING_VAR", "def") != "def" {
		t.Fatal("should fall back to default")
	}
}
```

---

## 🔵 CASE 1 — SIMPLE Dockerfile

```dockerfile
# CASE 1: one stage. The whole Go SDK ships in the final image.
FROM golang:1.23-alpine

WORKDIR /app

COPY go.mod ./
RUN go mod download

COPY . .
RUN go build -o /app/server .

EXPOSE 8000
CMD ["/app/server"]
```

```bash
cd 12-react-go-fullstack/backend
docker build -t go-simple:v1 .
docker run -d --name go -p 8000:8000 go-simple:v1
curl -s localhost:8000/api/info | python3 -m json.tool
curl -s localhost:8000/api/tasks | python3 -m json.tool
docker images go-simple:v1                # ~380 MB  😬
docker exec -it go sh -c 'which go gcc; ls /usr/local/go | head'   # the whole SDK is in there
docker rm -f go
```

---

## 🟢 CASE 2 — MULTI-STAGE Dockerfile

```dockerfile
# syntax=docker/dockerfile:1

ARG GO_IMAGE=golang:1.23-alpine

# ══════════════ STAGE 1: modules (cached until go.mod changes) ══════════════
FROM ${GO_IMAGE} AS modules
WORKDIR /src
COPY backend/go.mod backend/go.sum* ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download


# ══════════════ STAGE 2: build + test ══════════════
FROM ${GO_IMAGE} AS build
WORKDIR /src

# 🔑 --platform=$BUILDPLATFORM keeps the COMPILER native (fast) while we
#    cross-compile the OUTPUT for the target architecture.
ARG TARGETOS TARGETARCH
ARG APP_VERSION=0.0.0-dev
ARG GIT_COMMIT=unknown

COPY --from=modules /go/pkg/mod /go/pkg/mod
COPY backend/ .

# run the tests FIRST — a failure aborts the build
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go test ./... -v

# CGO_ENABLED=0  → a fully STATIC binary with no libc dependency (required for scratch)
# -ldflags="-s -w" → strip symbols & DWARF debug info: 25-30% smaller
# -trimpath → removes absolute build paths: reproducible builds, no leaked usernames
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH:-amd64} \
    go build -trimpath -ldflags="-s -w \
      -X main.version=${APP_VERSION} -X main.commit=${GIT_COMMIT}" \
    -o /out/server .


# ══════════════ STAGE 3: debug (not the default target) ══════════════
FROM ${GO_IMAGE} AS debug
COPY --from=build /out/server /server
RUN apk add --no-cache curl bind-tools strace vim
EXPOSE 8000
CMD ["/server"]


# ══════════════ STAGE 4: runtime — distroless-style, tiny ══════════════
FROM alpine:3.22 AS runtime

ARG APP_VERSION=0.0.0-dev
LABEL org.opencontainers.image.title="tasknest-go" \
      org.opencontainers.image.version="${APP_VERSION}"

ENV APP_VERSION=${APP_VERSION} \
    PORT=8000 \
    APP_ENV=production

# curl is ONLY here for the healthcheck — see the scratch variant to drop it entirely
RUN apk add --no-cache curl \
 && addgroup -S -g 101 app && adduser -S -u 100 -G app -g 101 app

COPY --from=build --chown=app:app /out/server /usr/local/bin/server

USER app
EXPOSE 8000
STOPSIGNAL SIGTERM

HEALTHCHECK --interval=15s --timeout=2s --start-period=5s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8000/api/health || exit 1

ENTRYPOINT ["/usr/local/bin/server"]
```

## 🪶 CASE 2-EXTREME — `FROM scratch`

```dockerfile
# syntax=docker/dockerfile:1
FROM golang:1.23-alpine AS build
WORKDIR /src
COPY backend/go.mod ./
RUN go mod download
COPY backend/ .
RUN go test ./... && \
    CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/server .

# 🔑 FROM scratch = a COMPLETELY EMPTY filesystem. Your binary is the only file.
FROM scratch

# HTTPS calls need CA certificates — scratch has none, so copy them in
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# a minimal /etc/passwd so os/user lookups and `USER` by name work
COPY --from=build /etc/passwd /etc/passwd
COPY --from=build /etc/group  /etc/group

COPY --from=build /out/server /server

ENV PORT=8000
USER 1000:1000
EXPOSE 8000

# No shell, no curl, no wget → no HEALTHCHECK CMD is possible.
# The orchestrator must probe over TCP/HTTP from OUTSIDE (Kubernetes httpGet probe).

ENTRYPOINT ["/server"]
```

### Build and compare all three

```bash
cd 12-react-go-fullstack

docker build -f backend/Dockerfile            -t go-simple:v1 .
docker build -f backend/Dockerfile.multistage -t go-multi:v1  --build-arg APP_VERSION=1.0.0 .
docker build -f backend/Dockerfile.scratch    -t go-scratch:v1 .

docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep go-
```

| Image | Typical size | Contains |
|---|---|---|
| `go-simple:v1` | **~380 MB** | the entire Go SDK, source, module cache, a shell |
| `go-multi:v1` | **~18 MB** | alpine + curl + your binary |
| `go-scratch:v1` | **~9 MB** | your binary + CA certs. **Nothing else.** |

```bash
# run the scratch image
docker run -d --name gos -p 8000:8000 go-scratch:v1
curl -s localhost:8000/api/info  | python3 -m json.tool
curl -s localhost:8000/api/tasks | python3 -m json.tool

# 🔬 it has NO shell — this is the lesson
docker exec -it gos sh                            # ❌ OCI runtime exec failed: "sh": executable file not found
docker run --rm -it --entrypoint sh go-scratch:v1  # ❌ same
ls -la /                                          # on the HOST: nothing to look at

# ✅ the correct way to debug a scratch image
docker build -f backend/Dockerfile.multistage --target debug -t go-debug:v1 .
docker run --rm -it -p 8000:8000 go-debug:v1 sh
  curl -s localhost:8000/api/health
  strace -f /server &     # trace syscalls
  nslookup db

# ✅ or attach to the running scratch container's namespaces
docker run -it --rm --pid=container:gos --net=container:gos nicolaka/netshoot /bin/bash
docker rm -f gos
```

### The full stack (`docker-compose.yml`)

```yaml
name: tasknest-go

x-logging: &logging
  driver: json-file
  options: { max-size: "10m", max-file: "3" }

services:
  api:
    build:
      context: .
      dockerfile: backend/Dockerfile.multistage
      target: runtime
      args:
        APP_VERSION: ${APP_VERSION:-1.0.0}
        GIT_COMMIT:  ${GIT_COMMIT:-local}
    image: tasknest-go-api:${APP_VERSION:-1.0.0}
    restart: unless-stopped
    logging: *logging
    environment: { PORT: "8000", APP_ENV: production }
    read_only: true
    tmpfs: [/tmp:size=8M]
    cap_drop: [ALL]
    security_opt: ["no-new-privileges:true"]
    deploy:
      resources: { limits: { cpus: "0.50", memory: 64M } }   # ← 64 MB! try that with a JVM
    networks: [backend]
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://127.0.0.1:8000/api/health"]
      interval: 10s
      timeout: 2s
      retries: 3
      start_period: 5s
    stop_grace_period: 25s

  web:
    build:
      context: ./frontend
      dockerfile: Dockerfile
      args: { VITE_API_URL: /api }
    image: tasknest-go-web:${APP_VERSION:-1.0.0}
    restart: unless-stopped
    logging: *logging
    depends_on:
      api: { condition: service_healthy }
    ports: ["${WEB_PORT:-8080}:8080"]
    read_only: true
    tmpfs: [/var/cache/nginx:size=16M, /var/run:size=1M, /tmp:size=8M]
    cap_drop: [ALL]
    networks: [frontend, backend]

networks: { frontend: {}, backend: {} }
```

```bash
cp .env.example .env
docker compose up -d --build --wait
docker compose ps
docker compose stats --no-stream        # ← look at the api's memory: ~10 MB actual
open http://localhost:8080
```

### Cross-compile from any machine

```bash
docker buildx build -f backend/Dockerfile.scratch \
  --platform linux/amd64,linux/arm64 \
  -t <your-username>/tasknest-go:1.0.0 --push .

docker buildx imagetools inspect <your-username>/tasknest-go:1.0.0
```

---

## 🔬 Three-way comparison of the whole path

| | ☕ Java (Project 9) | 🐍 Python (Project 11) | 🐹 Go (Project 12) |
|---|---|---|---|
| Simple image | ~600 MB | ~190 MB | ~380 MB |
| Multi-stage image | ~195 MB | ~155 MB | ~18 MB |
| Smallest possible | ~55 MB (GraalVM native) | ~50 MB (`python:slim` + no deps) | **~9 MB (`scratch`)** |
| Cold start | 2–6 s | 0.3–1 s | **~10 ms** |
| Idle RAM | 150–400 MB | 40–90 MB | **5–15 MB** |
| Needs a runtime in the image | JRE | Python interpreter | **nothing** (static binary) |
| Shell available in `scratch`? | n/a | n/a | **no** — plan your debugging |
| Concurrency model | threads | asyncio + processes | **goroutines** |

---

## 🔨 Tasks for Project 12

> **12.1** Build all three Go images and record exact sizes. Then `docker history --human` each and identify which single layer accounts for most of `go-simple`'s size. Why can't a `RUN rm -rf /usr/local/go` at the end fix it?

> **12.2** Prove `CGO_ENABLED=0` is required for scratch. Build the scratch image with `CGO_ENABLED=1` and run it. What exact error do you get, and why is it so misleading? (Hint: it says "no such file or directory" about a file that **exists**.)

> **12.3** Remove the CA certificates line from the scratch Dockerfile, then add an outbound HTTPS call to the Go code (`http.Get("https://api.github.com")`) and run it. What fails? Restore the line and confirm it works. What else commonly needs copying into a scratch image?

> **12.4** Memory-limit shootout. Run the Go, Python and Java APIs each with `-m 64m` and hit them with 200 concurrent requests. Which survive? Which get OOM-killed (exit 137)? Record actual `docker stats` memory for each at idle.

> **12.5** Debug the undebuggable. Your scratch container crash-loops with no logs. Write down **four** different techniques to find out why, and try at least two of them.

> **12.6** Wire the frontend. Bring up the full stack, confirm `http://localhost:8080` works with **no CORS headers anywhere**, and prove the api port is not reachable from your host. Then `docker compose up -d --scale api=3` and show nginx distributing requests.

<details>
<summary>👉 Answers</summary>

**12.1** The `FROM golang:1.23-alpine` base layer (~370 MB) — the Go toolchain, standard library sources, and `pkg/mod`. A later `RUN rm -rf /usr/local/go` **cannot help**: layers are read-only and additive, so the deleted files still exist in the earlier layer and are still transferred, stored and pulled. Only **not including them in the first place** (i.e. a separate build stage whose filesystem is discarded) reduces the image. This is the core insight of multi-stage builds.

**12.2** With `CGO_ENABLED=1` the binary is **dynamically linked** against musl libc. In `scratch` there is no `/lib/ld-musl-x86_64.so.1` dynamic loader, so the kernel cannot start the program and reports **`exec /server: no such file or directory`** — about a file that demonstrably exists. It's confusing because the error names the *binary*, but the missing thing is the *interpreter* recorded in its ELF header. Confirm with `file server` (statically linked vs dynamically linked) or `ldd server`. **`CGO_ENABLED=0` produces a static binary with no loader requirement.**

**12.3** You get `x509: certificate signed by unknown authority` — `scratch` has no `/etc/ssl/certs/ca-certificates.crt`, so TLS verification fails. Other things commonly copied in: `/etc/passwd` + `/etc/group` (for `os/user` and name-based `USER`), timezone data (`/usr/share/zoneinfo` from `tzdata`) if you format local times, and any static config files. Distroless images (`gcr.io/distroless/static-debian12`) ship all of these pre-configured, which is why most teams prefer them over raw `scratch`.

**12.4** At `-m 64m`: **Go survives easily** (idle ~8 MB, 200 concurrent requests ≈ 15 MB). **Python survives** but tight (idle ~45 MB with FastAPI+uvicorn; 2 gunicorn workers may exceed 64 MB → OOM). **Java is killed instantly** — a JVM with Spring Boot needs 150 MB+ before serving anything; you'll see `OOMKilled=true, ExitCode=137`. Practical minima: Go ≈ 16–32 MB, Python ≈ 128 MB, Java ≈ 384–512 MB. This drives real cost at scale: the same traffic needs ~10× fewer Go containers.

**12.5** Four techniques:
1. **`docker logs`** first — if the app logs to stdout before crashing, you already have the answer. (In `scratch`, panics still reach stdout.)
2. **Build to the debug stage**: `docker build --target debug -t x .` gives you the same binary plus a shell, curl, strace and nslookup. Run it and reproduce.
3. **Ephemeral sidecar sharing namespaces**: `docker run -it --rm --pid=container:X --net=container:X nicolaka/netshoot bash` → `ps aux`, `curl localhost:8000`, `tcpdump`, all against the *live* broken container.
4. **Add a temporary stage that copies the binary into alpine** and run it there with `strace -f ./server` to see the failing syscall, or `GOTRACEBACK=crash` / `GODEBUG=inittrace=1` env vars for Go-specific diagnostics.
   (Bonus 5th: `docker inspect --format '{{.State.ExitCode}} {{.State.OOMKilled}} {{.State.Error}}'` and `dmesg | tail` on the host for OOM/segfault records.)

**12.6** Works because nginx proxies `/api/` → `http://api:8000/`, so the browser only ever sees origin `http://localhost:8080`. Verify with `curl -sI localhost:8080/api/tasks | grep -i access-control` → **nothing**, and `curl -s --max-time 2 localhost:8000/api/health` → **connection refused** (the api publishes no host port). For `--scale api=3` the api service must have no `container_name` and no fixed host port; nginx's `upstream { server api:8000; }` then works via Docker DNS round-robin, and `proxy_next_upstream error timeout http_502 http_503` provides failover.
</details>

---

---

## ➡️ Next

**[`16-PROJECT-13-databases.md`](16-PROJECT-13-databases.md)** — Project 13.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
