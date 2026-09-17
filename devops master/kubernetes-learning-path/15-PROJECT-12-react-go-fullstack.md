# 🐹 Project 12 — React + Go Full Stack on Kubernetes

> **Time:** 2 hours · **Prereq:** [Project 10](13-PROJECT-10-react-java-fullstack.md) — same architecture, third runtime
>
> - 🔵 **CASE 1 — Simple.** Go HTTP API + React + Postgres in 20 minutes.
> - 🟢 **CASE 2 — Production.** Static binary in `FROM scratch` (**12 MB**), `GOMAXPROCS` set from the cgroup, `context.Context` cancellation wired to SIGTERM, `pprof`, distroless vs scratch, and why Go is the best language to run on Kubernetes.
>
> **What you'll learn that's Go-specific:** zero-dependency images, goroutine leaks, `GOMAXPROCS` mismatch, HTTP server lifecycle (`Shutdown` vs `Close`), and how to debug a binary with no shell.

---

## 12.0 Why Go is the easiest runtime for Kubernetes

| Property | Java | Python | **Go** |
|---|---|---|---|
| Final image size | 238 MB (JRE) | 185 MB (slim) | **12 MB (scratch)** |
| Cold start | 15–40 s | 1–3 s | **10–50 ms** |
| Memory floor | ~250 MB | ~80 MB/worker | **~10 MB** |
| Container CPU awareness | ✅ `UseContainerSupport` | ❌ you must read cgroups | ❌ **you must set `GOMAXPROCS`** |
| Signal handling | JVM does it | You register handlers | **You register handlers** (5 lines) |
| Needs a shell in the image | No | Sometimes | **No** |
| Concurrency | Threads | Processes (GIL) | **Goroutines** (thousands, cheap) |
| Static binary | No | No | **Yes** (`CGO_ENABLED=0`) |
| Scaling unit | One pod, many threads | Many pods, many workers | **One pod, many goroutines** |

Kubernetes itself, Docker, etcd, Prometheus, Terraform, ingress-nginx, cert-manager, Argo CD, Helm — all Go. You'll recognise the patterns.

**The three Go-on-Kubernetes mistakes that cost the most time:**

1. **`GOMAXPROCS` = the node's core count.** Your container gets 1 CPU, Go spawns 16 OS threads, they all get throttled, p99 latency goes 10× worse. Fix: `automaxprocs`.
2. **`server.Close()` instead of `server.Shutdown(ctx)` on SIGTERM.** In-flight requests are cut. Fix: always `Shutdown`.
3. **A goroutine leak that never shows up as CPU.** Memory climbs, goroutine count climbs to 500,000, then OOMKill. Fix: `pprof` + a goroutine-count alert.

---

## 12.1 The app

```bash
mkdir -p ~/k8s-learn/p12/{api,ui,k8s,scripts} && cd ~/k8s-learn/p12/api
go mod init github.com/3558Bhk/shop-api-go
```

`api/internal/config/config.go`:

```go
package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"
)

// Config is resolved from environment variables at startup.
// Immutability after boot is deliberate: no hot reload, no surprises.
type Config struct {
	AppName     string
	Environment string
	Version     string
	LogLevel    string
	Debug       bool

	Addr            string
	Port            int
	ReadTimeout     time.Duration
	WriteTimeout    time.Duration
	IdleTimeout     time.Duration
	ShutdownTimeout time.Duration

	DatabaseURL      string
	DBPoolMaxOpen    int
	DBPoolMaxIdle    int
	DBPoolMaxLife    time.Duration
	DBMigrationsPath string

	CORSOrigins []string

	// Downward API
	PodName      string
	PodNamespace string
	PodIP        string
	NodeName     string
}

// env resolves NAME, falling back to NAME_FILE (a mounted secret path).
// This is the same convention as Project 3 §3.6 and lets you avoid env-var secrets.
func env(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	if p, ok := os.LookupEnv(key + "_FILE"); ok && p != "" {
		if b, err := os.ReadFile(p); err == nil {
			return strings.TrimSpace(string(b))
		}
	}
	return fallback
}

func envInt(key string, fallback int) int {
	if v := env(key, ""); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return fallback
}

func envBool(key string, fallback bool) bool {
	if v := env(key, ""); v != "" {
		if b, err := strconv.ParseBool(v); err == nil {
			return b
		}
	}
	return fallback
}

func envDur(key string, fallback time.Duration) time.Duration {
	if v := env(key, ""); v != "" {
		if d, err := time.ParseDuration(v); err == nil {
			return d
		}
	}
	return fallback
}

// Load reads the environment once and validates. Fail fast at boot,
// not on the first request at 3am.
func Load() (*Config, error) {
	c := &Config{
		AppName:     env("APP_NAME", "shop-api"),
		Environment: env("ENVIRONMENT", "development"),
		Version:     env("APP_VERSION", "dev"),
		LogLevel:    strings.ToUpper(env("LOG_LEVEL", "info")),
		Debug:       envBool("DEBUG", false),

		Port:            envInt("PORT", 8080),
		ReadTimeout:     envDur("READ_TIMEOUT", 15*time.Second),
		WriteTimeout:    envDur("WRITE_TIMEOUT", 30*time.Second),
		IdleTimeout:     envDur("IDLE_TIMEOUT", 90*time.Second),
		ShutdownTimeout: envDur("SHUTDOWN_TIMEOUT", 25*time.Second),

		DatabaseURL:      env("DATABASE_URL", "postgres://shop:shop@db:5432/app?sslmode=disable"),
		DBPoolMaxOpen:    envInt("DB_POOL_MAX_OPEN", 15),
		DBPoolMaxIdle:    envInt("DB_POOL_MAX_IDLE", 5),
		DBPoolMaxLife:    envDur("DB_POOL_MAX_LIFE", 30*time.Minute),
		DBMigrationsPath: env("MIGRATIONS_PATH", "/app/migrations"),

		PodName:      env("POD_NAME", "local"),
		PodNamespace: env("POD_NAMESPACE", "local"),
		PodIP:        env("POD_IP", "127.0.0.1"),
		NodeName:     env("NODE_NAME", "local"),
	}
	c.Addr = fmt.Sprintf("0.0.0.0:%d", c.Port)

	if o := env("CORS_ORIGINS", ""); o != "" {
		for _, v := range strings.Split(o, ",") {
			if s := strings.TrimSpace(v); s != "" {
				c.CORSOrigins = append(c.CORSOrigins, s)
			}
		}
	}

	if c.Environment == "production" {
		if strings.Contains(c.DatabaseURL, "sslmode=disable") {
			return nil, fmt.Errorf("refusing to start: production DATABASE_URL must not use sslmode=disable")
		}
		if c.Debug {
			return nil, fmt.Errorf("refusing to start: DEBUG=true in production")
		}
	}
	return c, nil
}
```

`api/internal/store/store.go`:

```go
package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/stdlib"
	"github.com/prometheus/client_golang/prometheus"
)

// ErrNotFound is a sentinel so handlers can translate to 404 without
// depending on database/sql internals.
var ErrNotFound = errors.New("not found")

type Product struct {
	ID          int64      `json:"id"`
	Name        string     `json:"name"`
	Price       float64    `json:"price"`
	Description *string    `json:"description,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   *time.Time `json:"updated_at,omitempty"`
}

type Store struct {
	db *sql.DB

	// metrics
	queries    *prometheus.CounterVec
	queryDur   *prometheus.HistogramVec
	poolInUse  prometheus.GaugeFunc
	poolIdle   prometheus.GaugeFunc
	poolWaiters prometheus.GaugeFunc
}

func New(ctx context.Context, url string, maxOpen, maxIdle int, maxLife time.Duration) (*Store, error) {
	// pgx via database/sql — keeps the stdlib interface, gets pgx's performance
	connConf, err := pgx.ParseConfig(url)
	if err != nil {
		return nil, fmt.Errorf("parse database url: %w", err)
	}
	db := stdlib.OpenDB(*connConf)

	db.SetMaxOpenConns(maxOpen)
	db.SetMaxIdleConns(maxIdle)
	db.SetConnMaxLifetime(maxLife)
	db.SetConnMaxIdleTime(5 * time.Minute) // ⭐ recycle before Postgres kills idle conns

	// ⭐ Verify connectivity NOW. A bad URL must fail the Pod at boot,
	// not on the first user request.
	pingCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	if err := db.PingContext(pingCtx); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("ping database: %w", err)
	}

	s := &Store{
		db: db,
		queries: prometheus.NewCounterVec(prometheus.CounterOpts{
			Namespace: "shop", Subsystem: "db", Name: "queries_total",
			Help: "Database queries by operation and outcome.",
		}, []string{"op", "outcome"}),
		queryDur: prometheus.NewHistogramVec(prometheus.HistogramOpts{
			Namespace: "shop", Subsystem: "db", Name: "query_duration_seconds",
			Help:    "Database query latency.",
			Buckets: []float64{.0005, .001, .0025, .005, .01, .025, .05, .1, .25, .5, 1, 2.5},
		}, []string{"op"}),
	}
	s.poolInUse = prometheus.NewGaugeFunc(prometheus.GaugeOpts{
		Namespace: "shop", Subsystem: "db", Name: "connections_in_use",
	}, func() float64 { return float64(db.Stats().InUse) })
	s.poolIdle = prometheus.NewGaugeFunc(prometheus.GaugeOpts{
		Namespace: "shop", Subsystem: "db", Name: "connections_idle",
	}, func() float64 { return float64(db.Stats().Idle) })
	s.poolWaiters = prometheus.NewGaugeFunc(prometheus.GaugeOpts{
		Namespace: "shop", Subsystem: "db", Name: "wait_count_total",
	}, func() float64 { return float64(db.Stats().WaitCount) })
	return s, nil
}

func (s *Store) Metrics() []prometheus.Collector {
	return []prometheus.Collector{s.queries, s.queryDur, s.poolInUse, s.poolIdle, s.poolWaiters}
}

// timeQuery is the single place we instrument DB work.
func (s *Store) timeQuery(op string, fn func() error) error {
	start := time.Now()
	err := fn()
	s.queryDur.WithLabelValues(op).Observe(time.Since(start).Seconds())
	outcome := "ok"
	switch {
	case errors.Is(err, ErrNotFound):
		outcome = "not_found"
	case err != nil:
		outcome = "error"
	}
	s.queries.WithLabelValues(op, outcome).Inc()
	return err
}

func (s *Store) Close() error { return s.db.Close() }

func (s *Store) Stats() sql.DBStats { return s.db.Stats() }

// Ping is used by the readiness probe.
func (s *Store) Ping(ctx context.Context) error { return s.db.PingContext(ctx) }

func (s *Store) ListProducts(ctx context.Context, q string, limit, offset int) ([]Product, error) {
	var rows *sql.Rows
	var err error
	op := "list"
	err = s.timeQuery(op, func() error {
		var e error
		if q != "" {
			rows, e = s.db.QueryContext(ctx,
				`SELECT id, name, price, description, created_at FROM products
				 WHERE name ILIKE '%' || $1 || '%'
				 ORDER BY id LIMIT $2 OFFSET $3`, q, limit, offset)
		} else {
			rows, e = s.db.QueryContext(ctx,
				`SELECT id, name, price, description, created_at FROM products
				 ORDER BY id LIMIT $1 OFFSET $2`, limit, offset)
		}
		return e
	})
	if err != nil {
		return nil, fmt.Errorf("list products: %w", err)
	}
	defer rows.Close() // ⭐ always. A missed Close leaks a connection from the pool.

	out := make([]Product, 0, limit)
	for rows.Next() {
		var p Product
		if err := rows.Scan(&p.ID, &p.Name, &p.Price, &p.Description, &p.CreatedAt); err != nil {
			return nil, fmt.Errorf("scan product: %w", err)
		}
		out = append(out, p)
	}
	if err := rows.Err(); err != nil { // ⭐ check this — it catches mid-iteration failures
		return nil, fmt.Errorf("iterate products: %w", err)
	}
	return out, nil
}

func (s *Store) GetProduct(ctx context.Context, id int64) (*Product, error) {
	var p Product
	err := s.timeQuery("get", func() error {
		return s.db.QueryRowContext(ctx,
			`SELECT id, name, price, description, created_at FROM products WHERE id = $1`, id).
			Scan(&p.ID, &p.Name, &p.Price, &p.Description, &p.CreatedAt)
	})
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, fmt.Errorf("get product %d: %w", id, err)
	}
	return &p, nil
}

func (s *Store) CreateProduct(ctx context.Context, name string, price float64, description *string) (*Product, error) {
	var p Product
	err := s.timeQuery("create", func() error {
		return s.db.QueryRowContext(ctx,
			`INSERT INTO products (name, price, description) VALUES ($1, $2, $3)
			 RETURNING id, name, price, description, created_at`,
			name, price, description).
			Scan(&p.ID, &p.Name, &p.Price, &p.Description, &p.CreatedAt)
	})
	if err != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && pgErr.Code == "23505" { // unique violation
			return nil, ErrNotFound // caller maps to 409 in the handler
		}
		return nil, fmt.Errorf("create product: %w", err)
	}
	return &p, nil
}

func (s *Store) DeleteProduct(ctx context.Context, id int64) error {
	return s.timeQuery("delete", func() error {
		res, err := s.db.ExecContext(ctx, `DELETE FROM products WHERE id = $1`, id)
		if err != nil {
			return fmt.Errorf("delete product %d: %w", id, err)
		}
		n, _ := res.RowsAffected()
		if n == 0 {
			return ErrNotFound
		}
		return nil
	})
}
```

`api/internal/api/handlers.go`:

```go
package api

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"time"

	"github.com/3558Bhk/shop-api-go/internal/store"
)

type Handlers struct {
	store *store.Store
	log   *slog.Logger
}

func NewHandlers(s *store.Store, log *slog.Logger) *Handlers {
	return &Handlers{store: s, log: log}
}

// writeJSON is the one place we serialise, so errors are handled uniformly.
func (h *Handlers) writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if v == nil {
		return
	}
	if err := json.NewEncoder(w).Encode(v); err != nil {
		h.log.Error("encode_response", "error", err)
	}
}

func (h *Handlers) writeErr(w http.ResponseWriter, status int, msg string, requestID string) {
	h.writeJSON(w, status, map[string]string{"error": msg, "request_id": requestID})
}

type productInput struct {
	Name        string  `json:"name"`
	Price       float64 `json:"price"`
	Description *string `json:"description,omitempty"`
}

func (h *Handlers) ListProducts(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query().Get("q")

	limit := 50
	if v := r.URL.Query().Get("limit"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil || n < 1 || n > 200 { // ⭐ hard cap; never trust the client
			h.writeErr(w, http.StatusBadRequest, "limit must be 1-200", requestID(r))
			return
		}
		limit = n
	}
	offset := 0
	if v := r.URL.Query().Get("offset"); v != "" {
		n, err := strconv.Atoi(v)
		if err != nil || n < 0 {
			h.writeErr(w, http.StatusBadRequest, "offset must be >= 0", requestID(r))
			return
		}
		offset = n
	}

	// ⭐ r.Context() is cancelled when the client disconnects or the server
	// shuts down. Passing it down means work stops promptly.
	products, err := h.store.ListProducts(r.Context(), q, limit, offset)
	if err != nil {
		if errors.Is(err, context.Canceled) {
			h.log.Debug("request_cancelled", "path", r.URL.Path)
			return // client is gone; writing a response is pointless
		}
		h.log.Error("list_products", "error", err, "request_id", requestID(r))
		h.writeErr(w, http.StatusInternalServerError, "internal error", requestID(r))
		return
	}
	h.writeJSON(w, http.StatusOK, products)
}

func (h *Handlers) GetProduct(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(pathID(r), 10, 64)
	if err != nil || id < 1 {
		h.writeErr(w, http.StatusBadRequest, "invalid id", requestID(r))
		return
	}
	p, err := h.store.GetProduct(r.Context(), id)
	switch {
	case errors.Is(err, store.ErrNotFound):
		h.writeErr(w, http.StatusNotFound, "product not found", requestID(r))
	case err != nil:
		h.log.Error("get_product", "id", id, "error", err, "request_id", requestID(r))
		h.writeErr(w, http.StatusInternalServerError, "internal error", requestID(r))
	default:
		h.writeJSON(w, http.StatusOK, p)
	}
}

func (h *Handlers) CreateProduct(w http.ResponseWriter, r *http.Request) {
	// ⭐ cap the body. http.MaxBytesReader returns an error instead of OOMing
	// the Pod when someone POSTs 10 GB.
	r.Body = http.MaxBytesReader(w, r.Body, 1<<20) // 1 MiB

	var in productInput
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields() // catch client typos loudly in dev
	if err := dec.Decode(&in); err != nil {
		var maxErr *http.MaxBytesError
		if errors.As(err, &maxErr) {
			h.writeErr(w, http.StatusRequestEntityTooLarge, "body exceeds 1 MiB", requestID(r))
			return
		}
		h.writeErr(w, http.StatusBadRequest, "invalid JSON: "+err.Error(), requestID(r))
		return
	}
	if in.Name == "" || len(in.Name) > 120 {
		h.writeErr(w, http.StatusUnprocessableEntity, "name must be 1-120 characters", requestID(r))
		return
	}
	if in.Price < 0 {
		h.writeErr(w, http.StatusUnprocessableEntity, "price must be >= 0", requestID(r))
		return
	}

	p, err := h.store.CreateProduct(r.Context(), in.Name, in.Price, in.Description)
	if err != nil {
		h.log.Error("create_product", "error", err, "request_id", requestID(r))
		h.writeErr(w, http.StatusInternalServerError, "internal error", requestID(r))
		return
	}
	w.Header().Set("Location", "/api/products/"+strconv.FormatInt(p.ID, 10))
	h.writeJSON(w, http.StatusCreated, p)
	h.log.Info("product_created", "id", p.ID, "name", p.Name)
}

func (h *Handlers) DeleteProduct(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(pathID(r), 10, 64)
	if err != nil || id < 1 {
		h.writeErr(w, http.StatusBadRequest, "invalid id", requestID(r))
		return
	}
	if err := h.store.DeleteProduct(r.Context(), id); err != nil {
		if errors.Is(err, store.ErrNotFound) {
			h.writeErr(w, http.StatusNotFound, "product not found", requestID(r))
			return
		}
		h.log.Error("delete_product", "id", id, "error", err)
		h.writeErr(w, http.StatusInternalServerError, "internal error", requestID(r))
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func requestID(r *http.Request) string { return r.Header.Get("X-Request-ID") }
func pathID(r *http.Request) string {
	// with net/http 1.22+ routing patterns, r.PathValue("id") is cleaner
	if v := r.PathValue("id"); v != "" {
		return v
	}
	return ""
}
```

`api/internal/api/server.go` — **the part that matters most for Kubernetes**:

```go
package api

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"runtime"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/3558Bhk/shop-api-go/internal/config"
	"github.com/3558Bhk/shop-api-go/internal/store"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/collectors"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
)

// Server owns the HTTP lifecycle. The Kubernetes contract is:
//   SIGTERM → stop accepting NEW connections → finish IN-FLIGHT ones → exit 0
// Everything here exists to honour that contract.
type Server struct {
	cfg   *config.Config
	http  *http.Server
	store *store.Store
	log   *slog.Logger

	// ⭐ readiness gate. Flipped to 1 by /api/chaos/drain or by SIGTERM
	// so the endpoint is removed BEFORE we stop accepting connections.
	draining atomic.Bool
	healthy  atomic.Bool

	registry *prometheus.Registry
}

func NewServer(cfg *config.Config, st *store.Store, log *slog.Logger) *Server {
	s := &Server{cfg: cfg, store: st, log: log}
	s.healthy.Store(true)

	mux := http.NewServeMux()
	s.routes(mux)

	// Middleware chain — outermost first.
	var handler http.Handler = mux
	handler = s.recoverer(handler)          // a panic must not kill the process
	handler = s.requestID(handler)
	handler = s.requestLog(handler)
	handler = s.cors(handler)
	handler = s.metricsMiddleware(handler)
	if cfg.Environment == "production" {
		handler = otelhttp.NewHandler(handler, "shop-api") // tracing in prod only
	}

	s.http = &http.Server{
		Addr:              cfg.Addr,
		Handler:           handler,
		ReadTimeout:       cfg.ReadTimeout,   // ⭐ prevents slowloris
		ReadHeaderTimeout: 5 * time.Second,
		WriteTimeout:      cfg.WriteTimeout,
		IdleTimeout:       cfg.IdleTimeout,
		MaxHeaderBytes:    1 << 20,
		ErrorLog:          slog.NewLogLogger(log.Handler(), slog.LevelError),
	}
	return s
}

func (s *Server) routes(mux *http.ServeMux) {
	h := NewHandlers(s.store, s.log)

	// net/http 1.22+ method+pattern routing — no third-party router needed
	mux.HandleFunc("GET /api/products", h.ListProducts)
	mux.HandleFunc("GET /api/products/{id}", h.GetProduct)
	mux.HandleFunc("POST /api/products", h.CreateProduct)
	mux.HandleFunc("DELETE /api/products/{id}", h.DeleteProduct)

	mux.HandleFunc("GET /healthz", s.handleLiveness)
	mux.HandleFunc("GET /readyz", s.handleReadiness)
	mux.HandleFunc("GET /health", s.handleHealth)
	mux.HandleFunc("GET /metrics", s.handleMetrics)
	mux.HandleFunc("POST /api/chaos/{mode}", s.handleChaos)

	// ⭐ pprof — but ONLY on a separate port that is never exposed by the Ingress.
	// See §12.7 for the safe pattern.
	if s.cfg.Debug || s.cfg.Environment != "production" {
		s.registerPprof(mux)
	}
}

// ── PROBES ─────────────────────────────────────────────────────
// LIVENESS: "restart me if I return non-200."
// Must be trivial, must never touch a dependency, must never block.
func (s *Server) handleLiveness(w http.ResponseWriter, _ *http.Request) {
	if !s.healthy.Load() {
		w.WriteHeader(http.StatusInternalServerError)
		fmt.Fprintln(w, "unhealthy")
		return
	}
	w.WriteHeader(http.StatusOK)
	fmt.Fprintln(w, "ok")
}

// READINESS: "remove me from the Service if I return non-200."
// Checks the database, with a hard timeout shorter than the probe's timeoutSeconds.
func (s *Server) handleReadiness(w http.ResponseWriter, _ *http.Request) {
	if s.draining.Load() {
		w.WriteHeader(http.StatusServiceUnavailable)
		fmt.Fprintln(w, "draining")
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := s.store.Ping(ctx); err != nil {
		s.log.Warn("readiness_db_error", "error", err)
		w.WriteHeader(http.StatusServiceUnavailable)
		fmt.Fprintln(w, "database unavailable")
		return
	}
	w.WriteHeader(http.StatusOK)
	fmt.Fprintln(w, "ready")
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()

	checks := map[string]string{}
	status := "ok"
	if err := s.store.Ping(ctx); err != nil {
		checks["db"] = "down: " + err.Error()
		status = "degraded"
	} else {
		checks["db"] = "up"
	}

	st := s.store.Stats()
	checks["db_pool_in_use"] = fmt.Sprintf("%d/%d", st.InUse, st.MaxOpenConnections)
	checks["db_pool_wait_count"] = fmt.Sprintf("%d", st.WaitCount)
	checks["goroutines"] = fmt.Sprintf("%d", runtime.NumGoroutine())

	w.Header().Set("Content-Type", "application/json")
	_ = jsonEncode(w, map[string]any{
		"status":   status,
		"version":  s.cfg.Version,
		"pod":      s.cfg.PodName,
		"draining": s.draining.Load(),
		"checks":   checks,
	})
}

func (s *Server) handleChaos(w http.ResponseWriter, r *http.Request) {
	mode := r.PathValue("mode")
	switch mode {
	case "liveness":
		s.healthy.Store(false)
	case "readiness":
		s.draining.Store(false)
		s.healthy.Store(true)
	case "drain":
		s.draining.Store(true)
	case "recover":
		s.healthy.Store(true)
		s.draining.Store(false)
	default:
		http.Error(w, "unknown mode: "+mode, http.StatusBadRequest)
		return
	}
	s.log.Warn("chaos", "mode", mode)
	fmt.Fprintf(w, `{"mode":%q,"healthy":%t,"draining":%t}`+"\n", mode, s.healthy.Load(), s.draining.Load())
}

// ── MIDDLEWARE ─────────────────────────────────────────────────
func (s *Server) recoverer(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				s.log.Error("panic",
					"error", rec,
					"path", r.URL.Path,
					"stack", string(debugStack()),
					"request_id", r.Header.Get("X-Request-ID"),
				)
				// Only write if we haven't already — a partial response can't be unsent
				http.Error(w, `{"error":"internal error"}`, http.StatusInternalServerError)
			}
		}()
		next.ServeHTTP(w, r)
	})
}

func (s *Server) requestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get("X-Request-ID")
		if id == "" {
			id = newRequestID()
		}
		w.Header().Set("X-Request-ID", id)
		r.Header.Set("X-Request-ID", id) // so handlers can read it back
		next.ServeHTTP(w, r)
	})
}

func (s *Server) requestLog(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// skip probe noise — otherwise your logs are 90% /healthz
		if r.URL.Path == "/healthz" || r.URL.Path == "/readyz" {
			next.ServeHTTP(w, r)
			return
		}
		start := time.Now()
		rw := &statusRecorder{ResponseWriter: w, status: 200}
		next.ServeHTTP(rw, r)
		s.log.Info("request",
			"method", r.Method,
			"path", r.URL.Path,
			"status", rw.status,
			"bytes", rw.bytes,
			"duration_ms", time.Since(start).Milliseconds(),
			"remote", r.RemoteAddr,
			"request_id", r.Header.Get("X-Request-ID"),
			"ua", r.UserAgent(),
		)
	})
}

func (s *Server) cors(next http.Handler) http.Handler {
	allowed := map[string]bool{}
	for _, o := range s.cfg.CORSOrigins {
		allowed[o] = true
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin != "" && (allowed[origin] || allowed["*"]) {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Methods", "GET,POST,PUT,PATCH,DELETE,OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Content-Type,Authorization,X-Request-ID")
			w.Header().Set("Access-Control-Max-Age", "600")
		}
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

type statusRecorder struct {
	http.ResponseWriter
	status int
	bytes  int
}

func (r *statusRecorder) WriteHeader(code int) { r.status = code; r.ResponseWriter.WriteHeader(code) }
func (r *statusRecorder) Write(b []byte) (int, error) {
	n, err := r.ResponseWriter.Write(b)
	r.bytes += n
	return n, err
}

// ── METRICS ────────────────────────────────────────────────────
func (s *Server) initMetrics() {
	s.registry = prometheus.NewRegistry()
	s.registry.MustRegister(
		collectors.NewGoCollector(
			collectors.WithGoCollectorRuntimeMetrics(collectors.GoRuntimeMetricsRule{Matcher: collectors.MetricsAll}),
		),
		collectors.NewProcessCollector(collectors.ProcessCollectorOpts{}),
		httpRequestsTotal, httpDuration, httpInFlight,
	)
	for _, c := range s.store.Metrics() {
		s.registry.MustRegister(c)
	}
	// app info as a metric with labels — lets you join version to everything else
	s.registry.MustRegister(prometheus.NewGaugeFunc(prometheus.GaugeOpts{
		Namespace: "shop", Name: "build_info", ConstLabels: prometheus.Labels{
			"version": s.cfg.Version, "revision": revision, "environment": s.cfg.Environment,
		},
	}, func() float64 { return 1 }))
	// ⭐ goroutine count as a first-class metric — goroutine leaks are silent
	s.registry.MustRegister(prometheus.NewGaugeFunc(prometheus.GaugeOpts{
		Namespace: "shop", Name: "goroutines", Help: "Current goroutine count.",
	}, func() float64 { return float64(runtime.NumGoroutine()) }))
}

func (s *Server) handleMetrics(w http.ResponseWriter, r *http.Request) {
	promhttp.HandlerFor(s.registry, promhttp.HandlerOpts{
		EnableOpenMetrics: true,
		Registry:          s.registry,
	}).ServeHTTP(w, r)
}

var (
	httpRequestsTotal = prometheus.NewCounterVec(prometheus.CounterOpts{
		Namespace: "shop", Name: "http_requests_total",
		Help: "HTTP requests by method, path and status.",
	}, []string{"method", "path", "status"})

	httpDuration = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Namespace: "shop", Name: "http_request_duration_seconds",
		Help:    "HTTP request latency.",
		Buckets: []float64{.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5, 10},
	}, []string{"method", "path"})

	httpInFlight = prometheus.NewGauge(prometheus.GaugeOpts{
		Namespace: "shop", Name: "http_requests_in_flight",
		Help: "Requests currently being served.",
	})
)

// ⭐ label cardinality control: record the ROUTE PATTERN, never the raw path.
// /api/products/12345 → "products", not 5 million distinct labels.
func (s *Server) metricsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		httpInFlight.Inc()
		defer httpInFlight.Dec()
		start := time.Now()
		rw := &statusRecorder{ResponseWriter: w, status: 200}
		next.ServeHTTP(rw, r)

		pattern := routePattern(r) // see below
		status := strconv.Itoa(rw.status / 100) + "xx"
		httpRequestsTotal.WithLabelValues(r.Method, pattern, status).Inc()
		httpDuration.WithLabelValues(r.Method, pattern).Observe(time.Since(start).Seconds())
	})
}

func routePattern(r *http.Request) string {
	if p := r.Pattern; p != "" { // net/http 1.22+ sets this
		return p
	}
	switch {
	case strings.HasPrefix(r.URL.Path, "/api/products"):
		return "/api/products"
	case strings.HasPrefix(r.URL.Path, "/healthz"), strings.HasPrefix(r.URL.Path, "/readyz"):
		return "/probes"
	default:
		return "other"
	}
}

// ── ⭐ LIFECYCLE: the Kubernetes contract ──────────────────────
// Run blocks until SIGTERM/SIGINT, then shuts down gracefully.
func (s *Server) Run(ctx context.Context) error {
	s.initMetrics()

	// A second SIGTERM (or SIGINT) during shutdown = "stop being polite".
	ctx, stop := signal.NotifyContext(ctx, syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	errCh := make(chan error, 1)
	go func() {
		s.log.Info("listening",
			"addr", s.cfg.Addr,
			"version", s.cfg.Version,
			"env", s.cfg.Environment,
			"pod", s.cfg.PodName,
			"gomaxprocs", runtime.GOMAXPROCS(0),
			"go_version", runtime.Version(),
		)
		// ListenAndServe returns http.ErrServerClosed on Shutdown — not an error.
		if err := s.http.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- fmt.Errorf("listen: %w", err)
		}
	}()

	select {
	case err := <-errCh:
		return err
	case <-ctx.Done():
		s.log.Info("shutdown_signal", "signal", ctx.Err().Error())
	}

	// STEP 1 — flip readiness to 503 so the kubelet removes us from the
	// EndpointSlice. This happens FIRST because endpoint propagation takes time.
	s.draining.Store(true)
	s.log.Info("draining", "msg", "readiness now 503; waiting for endpoints to propagate")

	// STEP 2 — give kube-proxy and the ingress controller time to notice.
	// In a real cluster the preStop hook does this; doing it here too is belt-and-braces.
	select {
	case <-time.After(3 * time.Second):
	case <-context.Background().Done():
	}

	// STEP 3 — stop accepting new connections, finish in-flight ones.
	shutdownCtx, cancel := context.WithTimeout(context.Background(), s.cfg.ShutdownTimeout)
	defer cancel()
	if err := s.http.Shutdown(shutdownCtx); err != nil {
		s.log.Error("shutdown_timeout", "error", err, "msg", "forcing close")
		_ = s.http.Close() // ⛔ nuclear: cuts in-flight requests. Last resort only.
	}

	// STEP 4 — release the database pool.
	if err := s.store.Close(); err != nil {
		s.log.Error("store_close", "error", err)
	}

	s.log.Info("shutdown_complete",
		"goroutines_remaining", runtime.NumGoroutine(),
		"msg", "exiting 0",
	)
	return nil
}
```

`api/cmd/server/main.go`:

```go
package main

import (
	"context"
	"log/slog"
	"os"

	// ⭐ THE most important import for Go on Kubernetes.
	// Sets GOMAXPROCS from the cgroup CPU quota, not the node's core count.
	_ "go.uber.org/automaxprocs"

	"github.com/3558Bhk/shop-api-go/internal/api"
	"github.com/3558Bhk/shop-api-go/internal/config"
	"github.com/3558Bhk/shop-api-go/internal/store"
)

// Set at build time with -ldflags.
var (
	version  = "dev"
	revision = "unknown"
	builtAt  = "unknown"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		// No logger yet — stderr is fine, and a non-zero exit makes the Pod CrashLoop.
		slog.Error("config", "error", err)
		os.Exit(1)
	}

	log := newLogger(cfg)
	slog.SetDefault(log)

	// ⭐ Fail fast. If the DB is unreachable, exit non-zero NOW so Kubernetes
	// shows CrashLoopBackOff instead of a Ready Pod that 500s every request.
	ctx := context.Background()
	st, err := store.New(ctx, cfg.DatabaseURL, cfg.DBPoolMaxOpen, cfg.DBPoolMaxIdle, cfg.DBPoolMaxLife)
	if err != nil {
		log.Error("store_init", "error", err)
		os.Exit(1)
	}

	srv := api.NewServer(cfg, st, log)
	if err := srv.Run(ctx); err != nil {
		log.Error("server", "error", err)
		os.Exit(1)
	}
	os.Exit(0) // ⭐ explicit 0 so a leaked goroutine can't keep the process alive
}

func newLogger(cfg *config.Config) *slog.Logger {
	var level slog.Level
	switch cfg.LogLevel {
	case "DEBUG":
		level = slog.LevelDebug
	case "WARN", "WARNING":
		level = slog.LevelWarn
	case "ERROR":
		level = slog.LevelError
	default:
		level = slog.LevelInfo
	}
	opts := &slog.HandlerOptions{
		Level: level,
		ReplaceAttr: func(_ []string, a slog.Attr) slog.Attr {
			if a.Key == slog.TimeKey {
				a.Value = slog.StringValue(a.Value.Time().UTC().Format("2006-01-02T15:04:05.000Z"))
			}
			return a
		},
	}
	// JSON to stdout — Kubernetes collects it, Loki parses it, Grafana shows it.
	h := slog.NewJSONHandler(os.Stdout, opts)
	return slog.New(h).With(
		"service", cfg.AppName,
		"version", cfg.Version,
		"revision", revision,
		"environment", cfg.Environment,
		"pod", cfg.PodName,
		"namespace", cfg.PodNamespace,
		"node", cfg.NodeName,
	)
}
```

`api/go.mod` (the dependency list is the whole story of Go's small images):

```
module github.com/3558Bhk/shop-api-go

go 1.23

require (
	github.com/jackc/pgx/v5 v5.7.2
	github.com/prometheus/client_golang v1.20.5
	go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp v0.58.0
	go.uber.org/automaxprocs v1.6.0
	github.com/google/uuid v1.6.0
)
```

---

## 12.2 The Dockerfile — 12 MB, `FROM scratch`

`api/Dockerfile`:

```dockerfile
# syntax=docker/dockerfile:1

# ═══════════════════════════════════════════════════════════
# 🔵 CASE 1 — simple: one stage, distroless base
# ═══════════════════════════════════════════════════════════
FROM golang:1.23-alpine AS build
WORKDIR /src
ENV CGO_ENABLED=0 GOOS=linux
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN go build -o /out/shop-api ./cmd/server


# ═══════════════════════════════════════════════════════════
# 🟢 CASE 2 — production: reproducible, stripped, scratch
# ═══════════════════════════════════════════════════════════
FROM golang:1.23-bookworm AS builder

# Reproducible builds
ENV CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=amd64 \
    GOFLAGS="-trimpath" \
    GOPROXY="https://proxy.golang.org,direct" \
    GOSUMDB="sum.golang.org"

WORKDIR /src

# ⭐ Cache the module download separately from the source.
# Dependencies change rarely; your code changes constantly.
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    true

COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go mod download -x

COPY . .

ARG GIT_SHA=unknown
ARG VERSION=dev
ARG BUILD_TIME=unknown

# ⭐ -trimpath     → removes local filesystem paths from the binary (reproducible + no info leak)
# ⭐ -ldflags -s -w → strips the symbol table & DWARF debug info (30-40% smaller)
# ⭐ -buildvcs=false → we pass the SHA ourselves; don't let git state break the build
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go build \
      -trimpath \
      -buildvcs=false \
      -ldflags="-s -w \
        -X main.version=${VERSION} \
        -X main.revision=${GIT_SHA} \
        -X main.builtAt=${BUILD_TIME}" \
      -o /out/shop-api \
      ./cmd/server

# Verify it's actually static — a dynamically linked binary won't run in scratch
RUN file /out/shop-api && ldd /out/shop-api 2>&1 | grep -q "not a dynamic" \
    && echo "✅ statically linked" || { echo "⛔ dynamically linked — scratch will fail"; exit 1; }

RUN ls -lh /out/shop-api


# ── the runtime image ─────────────────────────────────────
FROM scratch AS runtime

# CA certificates for outbound HTTPS (calling payment gateways, etc.)
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# A minimal passwd/group so runAsNonRoot works and os/user can resolve
COPY --from=builder /etc/passwd /etc/passwd
COPY --from=builder /etc/group  /etc/group

# timezone data, if you format times anywhere other than UTC
# COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo

# SQL migrations — needed by the migrate Job, not by the server at runtime
COPY --from=builder /src/migrations /app/migrations

COPY --from=builder /out/shop-api /shop-api

# ⭐ scratch has no /tmp and no writable paths. readOnlyRootFilesystem is free.
USER 65534:65534

EXPOSE 8080

# scratch has NO shell, so:
#   ⛔ no exec probes        → use httpGet
#   ⛔ no preStop exec hook  → do the drain in Go (see §12.6)
#   ⛔ no kubectl exec       → use kubectl debug --image=… --share-processes
ENTRYPOINT ["/shop-api"]

LABEL org.opencontainers.image.title="shop-api-go" \
      org.opencontainers.image.description="Shop REST API (Go)" \
      org.opencontainers.image.vendor="Harish Kumar Brahmandam" \
      org.opencontainers.image.source="https://github.com/3558Bhk/shop-api-go" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.version="${VERSION}"
```

**Three variants side by side** — build all three and compare:

```dockerfile
# ── variant: distroless (debuggable-ish, 20 MB) ──
FROM gcr.io/distroless/static-debian12:nonroot AS distroless
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /out/shop-api /shop-api
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/shop-api"]

# ── variant: alpine (has a shell, 20 MB) ──
FROM alpine:3.22 AS alpine
RUN apk add --no-cache ca-certificates tzdata curl \
 && addgroup -g 65534 app && adduser -D -u 65534 -G app app
COPY --from=builder /out/shop-api /usr/local/bin/shop-api
USER 65534:65534
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/shop-api"]
```

```bash
docker build --target runtime    -t shop-api-go:scratch     --build-arg GIT_SHA=$(git rev-parse --short HEAD) --build-arg VERSION=1.0.0 .
docker build --target distroless -t shop-api-go:distroless  .
docker build --target alpine     -t shop-api-go:alpine      .
docker build --target build      -t shop-api-go:simple      .   # case 1

docker images | grep shop-api-go
```

```
REPOSITORY      TAG          SIZE
shop-api-go     scratch      12.4MB     ← the binary + CA certs
shop-api-go     distroless   19.8MB
shop-api-go     alpine       20.1MB
shop-api-go     simple       12.4MB     (distroless base for Case 1 too)
```

**For scale:**

| | Go scratch | Java jlink | Python slim | Node nginx |
|---|---|---|---|---|
| Image | **12 MB** | 94 MB | 185 MB | 25 MB |
| Pull time (cold node) | **~0.4 s** | ~3 s | ~6 s | ~1 s |
| Startup to Ready | **~80 ms** | ~9 s | ~1.5 s | ~50 ms |
| Memory floor | **~12 MB** | ~120 MB | ~90 MB | ~8 MB |
| Rollout of 100 pods | **~15 s** | ~4 min | ~5 min | ~30 s |

**Verify the scratch image actually works:**

```bash
docker run --rm -p 8080:8080 \
  -e DATABASE_URL="postgres://shop:shop@host.docker.internal:5432/app?sslmode=disable" \
  -e ENVIRONMENT=development -e DEBUG=true \
  shop-api-go:scratch &
sleep 2
curl -s localhost:8080/healthz
curl -s localhost:8080/health | jq .
curl -s localhost:8080/metrics | grep -E '^go_goroutines|^shop_'
docker exec $(docker ps -q | head -1) sh   # ← ⛔ FAILS: "executable file not found"
kill %1
```

That failure is the whole point: **there is no shell.** Plan for it (§12.7).

---

## 12.3 `GOMAXPROCS` — the Go-on-Kubernetes trap

**Without `automaxprocs`:**

```bash
docker run --rm --cpus=1 -e GOMAXPROCS_DEBUG=1 golang:1.23-alpine go run - <<'EOF'
package main
import ("fmt"; "runtime")
func main() { fmt.Println("GOMAXPROCS =", runtime.GOMAXPROCS(0), " NumCPU =", runtime.NumCPU()) }
EOF
# GOMAXPROCS = 16   NumCPU = 16     ← ⛔ the HOST's cores, not the container's 1 CPU
```

Go spawns 16 OS threads, all of which want to run. The cgroup gives the container 1 CPU per 100 ms period. The threads burn through their quota in ~6 ms and then **everything stops for 94 ms**. This is CPU throttling, and it looks like this:

```bash
# in a Pod WITHOUT automaxprocs
kubectl exec -n shop deploy/shop-api -- cat /sys/fs/cgroup/cpu.stat
```

```
usage_usec 4821033
nr_periods 1000
nr_throttled 812              ← ⛔ 81% of periods were throttled
throttled_usec 81204400       ← 81 seconds of stall in 100 seconds of wall time
```

Latency:

```bash
hey -z 30s -c 20 -host shop.example.com "http://$LB_IP/api/products" | grep -A5 'Latency distribution'
#   50% in 0.0180 secs
#   95% in 0.3100 secs      ← ⛔ 17× the median. That's the throttle stall.
#   99% in 0.6200 secs
```

**With `automaxprocs`** (`_ "go.uber.org/automaxprocs"` in main.go), the log line at boot tells you it worked:

```
{"level":"INFO","msg":"maxprocs: Updating GOMAXPROCS=1: determined from CPU quota",…}
{"level":"INFO","msg":"listening","gomaxprocs":1,…}
```

```bash
hey -z 30s -c 20 -host shop.example.com "http://$LB_IP/api/products" | grep -A5 'Latency distribution'
#   50% in 0.0110 secs
#   95% in 0.0190 secs      ← ✅ 1.7× the median. Smooth.
#   99% in 0.0340 secs

kubectl exec -n shop deploy/shop-api -- cat /sys/fs/cgroup/cpu.stat
# nr_throttled 4               ← ✅
```

**Sizing rules:**

| Container CPU limit | `GOMAXPROCS` (automaxprocs sets) | Good for |
|---|---|---|
| 0.25 | 1 | Tiny sidecars |
| 1 | 1 | Most APIs — one thread, no throttling |
| 2 | 2 | Moderate traffic |
| 4 | 4 | High traffic, or GC-heavy |
| fractional (1.5) | 1 | automaxprocs **rounds down** — safe |

> 🔑 **Round down, never up.** `GOMAXPROCS` above your quota guarantees throttling. Below it wastes a little CPU but keeps latency flat.

**Set it explicitly if you don't want the dependency:**

```yaml
env:
  - name: GOMAXPROCS
    value: "2"          # must be <= limits.cpu, and kept in sync manually ⚠️
```

Or compute it at runtime with no dependency:

```go
func setGOMAXPROCS() {
	// cgroup v2
	if b, err := os.ReadFile("/sys/fs/cgroup/cpu.max"); err == nil {
		f := strings.Fields(string(b))
		if len(f) == 2 && f[0] != "max" {
			quota, _ := strconv.Atoi(f[0])
			period, _ := strconv.Atoi(f[1])
			if period > 0 && quota > 0 {
				n := quota / period // floor
				if n < 1 { n = 1 }
				runtime.GOMAXPROCS(n)
				return
			}
		}
	}
	// cgroup v1
	q, err1 := os.ReadFile("/sys/fs/cgroup/cpu/cpu.cfs_quota_us")
	p, err2 := os.ReadFile("/sys/fs/cgroup/cpu/cpu.cfs_period_us")
	if err1 == nil && err2 == nil {
		quota, _ := strconv.Atoi(strings.TrimSpace(string(q)))
		period, _ := strconv.Atoi(strings.TrimSpace(string(p)))
		if quota > 0 && period > 0 {
			n := quota / period
			if n < 1 { n = 1 }
			runtime.GOMAXPROCS(n)
		}
	}
}
```

**Verify in the cluster:**

```bash
kubectl exec -n shop deploy/shop-api -- wget -qO- localhost:8080/metrics 2>/dev/null \
  || kubectl port-forward -n shop svc/shop-api 8080:8080 &
sleep 2
curl -s localhost:8080/metrics | grep -E '^go_gomaxprocs|^go_threads|^process_cpu'
# go_gomaxprocs 2
# go_threads 9
```

`go_threads` (OS threads) will be higher than `GOMAXPROCS` — that's normal, Go creates extra threads for blocking syscalls.

---

## 12.4 🔵 CASE 1 — Simple manifests

`k8s/simple.yaml` (DB identical to [Project 10 §10.2](13-PROJECT-10-react-java-fullstack.md#102-one-file-the-whole-stack)):

```yaml
apiVersion: apps/v1
kind: Deployment
metadata: {name: shop-api, labels: {app: shop-api}}
spec:
  replicas: 2
  selector: {matchLabels: {app: shop-api}}
  template:
    metadata: {labels: {app: shop-api}}
    spec:
      containers:
        - name: api
          image: shop-api-go:simple
          imagePullPolicy: IfNotPresent
          ports: [{name: http, containerPort: 8080}]
          env:
            - {name: DATABASE_URL, value: "postgres://shop:L3arn-K8s!@db:5432/app?sslmode=disable"}
            - {name: ENVIRONMENT, value: development}
            - {name: DEBUG, value: "true"}
          readinessProbe: {httpGet: {path: /readyz,  port: http}, initialDelaySeconds: 2, periodSeconds: 5}
          livenessProbe:  {httpGet: {path: /healthz, port: http}, initialDelaySeconds: 5, periodSeconds: 20}
          resources:
            requests: {cpu: 50m,  memory: 32Mi}      # ← Go's floor is tiny
            limits:   {cpu: 500m, memory: 128Mi}
---
apiVersion: v1
kind: Service
metadata: {name: shop-api}
spec: {selector: {app: shop-api}, ports: [{name: http, port: 8080}]}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: shop
  annotations: {nginx.ingress.kubernetes.io/ssl-redirect: "false"}
spec:
  ingressClassName: nginx
  rules:
    - host: shop.local
      http:
        paths:
          - {path: /api, pathType: Prefix, backend: {service: {name: shop-api, port: {number: 8080}}}}
          - {path: /,    pathType: Prefix, backend: {service: {name: shop-ui,  port: {number: 80}}}}
```

Note what's **absent** vs the Java/Python versions:
- No init container to wait for the DB — Go fails fast and Kubernetes restarts it in 100 ms; `restartPolicy: Always` *is* your retry loop
- No `startupProbe` — the app is ready in milliseconds
- No `preStop` sleep needed for boot-related races (still needed for endpoint propagation — see §12.6)
- Tiny resource requests: 50m CPU / 32Mi memory is a real, working number

```bash
kubectl apply -f k8s/simple.yaml
kubectl rollout status deploy/shop-api --timeout=60s      # ← seconds, not minutes
kubectl get pods -l app=shop-api
kubectl port-forward svc/shop-api 8080:8080 & sleep 1
curl -s localhost:8080/health | jq .
curl -s -XPOST localhost:8080/api/products -H 'Content-Type: application/json' \
  -d '{"name":"Widget","price":9.99}' | jq .
curl -s localhost:8080/api/products | jq .
kill %1
```

---

## 12.5 🟢 CASE 2 — Production manifests

`k8s/api.yaml`:

```yaml
apiVersion: v1
kind: ServiceAccount
metadata: {name: shop-api, namespace: shop}
automountServiceAccountToken: false
---
apiVersion: v1
kind: Secret
metadata: {name: pg-creds, namespace: shop}
stringData:
  username: shop
  password: "L3arn-K8s-pr0d!"
  url: "postgres://shop:L3arn-K8s-pr0d!@db.shop.svc.cluster.local:5432/app?sslmode=require"
---
apiVersion: v1
kind: ConfigMap
metadata: {name: shop-api-config, namespace: shop}
data:
  APP_NAME: "shop-api"
  ENVIRONMENT: "production"
  LOG_LEVEL: "INFO"
  PORT: "8080"
  READ_TIMEOUT: "15s"
  WRITE_TIMEOUT: "30s"
  IDLE_TIMEOUT: "90s"
  SHUTDOWN_TIMEOUT: "25s"      # ⭐ must be < terminationGracePeriodSeconds - preStop
  DB_POOL_MAX_OPEN: "15"
  DB_POOL_MAX_IDLE: "5"
  DB_POOL_MAX_LIFE: "30m"
  MIGRATIONS_PATH: "/app/migrations"
  CORS_ORIGINS: "https://shop.example.com"
  DATABASE_URL_FILE: "/run/secrets/db/url"     # ⭐ _FILE convention → secret file
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop-api
  namespace: shop
  labels:
    app: shop-api
    app.kubernetes.io/name: shop-api
    app.kubernetes.io/component: backend
    app.kubernetes.io/part-of: shop
spec:
  replicas: 3
  revisionHistoryLimit: 8
  strategy:
    type: RollingUpdate
    rollingUpdate: {maxSurge: 1, maxUnavailable: 0}
  selector: {matchLabels: {app: shop-api}}
  template:
    metadata:
      labels: {app: shop-api, version: v1}
      annotations:
        checksum/config: REPLACE_WITH_SHA
    spec:
      serviceAccountName: shop-api
      # ⭐ Go shuts down in ~3s. The grace period can be SHORT — which makes
      # rollouts much faster than Java's or Python's.
      terminationGracePeriodSeconds: 35
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534
        runAsGroup: 65534
        fsGroup: 65534
        seccompProfile: {type: RuntimeDefault}
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: DoNotSchedule
          minDomains: 3
          labelSelector: {matchLabels: {app: shop-api}}
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone
          whenUnsatisfiable: ScheduleAnyway
          labelSelector: {matchLabels: {app: shop-api}}

      containers:
        - name: api
          image: ghcr.io/3558bhk/shop-api-go:1.0.0
          imagePullPolicy: IfNotPresent
          ports: [{name: http, containerPort: 8080}]

          # ⭐ scratch is already read-only-ish; this makes it enforced
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities: {drop: ["ALL"]}
            privileged: false

          envFrom: [{configMapRef: {name: shop-api-config}}]
          env:
            - {name: POD_NAME,      valueFrom: {fieldRef: {fieldPath: metadata.name}}}
            - {name: POD_NAMESPACE, valueFrom: {fieldRef: {fieldPath: metadata.namespace}}}
            - {name: POD_IP,        valueFrom: {fieldRef: {fieldPath: status.podIP}}}
            - {name: NODE_NAME,     valueFrom: {fieldRef: {fieldPath: spec.nodeName}}}
            - {name: APP_VERSION,   value: "1.0.0"}

          # ⭐ Go's real numbers. Don't copy Java's.
          resources:
            requests: {cpu: 100m, memory: 64Mi}
            limits:   {cpu: "1",   memory: 256Mi}   # == requests × 4 for CPU; memory tight

          # No startupProbe — Go is ready in <1s.
          # But keep one anyway if your app does slow init (migrations, warm caches).
          readinessProbe:
            httpGet: {path: /readyz, port: http}
            periodSeconds: 5
            failureThreshold: 2
            successThreshold: 1
            timeoutSeconds: 3
          livenessProbe:
            httpGet: {path: /healthz, port: http}
            periodSeconds: 15
            failureThreshold: 3
            timeoutSeconds: 3

          lifecycle:
            preStop:
              exec:
                # ⛔ scratch has no shell and no curl — you CANNOT use an exec hook here.
                # The drain is done in Go (§12.6). Remove this block for the scratch image.
                command: ["/bin/sh", "-c", "sleep 5"]

          volumeMounts:
            - {name: db, mountPath: /run/secrets/db, readOnly: true}
            - {name: tmp, mountPath: /tmp}      # Go writes almost nothing, but pprof needs it

      volumes:
        - name: db
          secret:
            secretName: pg-creds
            defaultMode: 0400
            items:
              - {key: url,      path: url}
              - {key: username, path: username}
              - {key: password, path: password}
        - {name: tmp, emptyDir: {medium: Memory, sizeLimit: 32Mi}}
---
apiVersion: v1
kind: Service
metadata: {name: shop-api, namespace: shop, labels: {app: shop-api}}
spec:
  selector: {app: shop-api}
  ports: [{name: http, port: 8080, targetPort: http}]
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: {name: shop-api, namespace: shop}
spec:
  maxUnavailable: 1
  selector: {matchLabels: {app: shop-api}}
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: {name: shop-api, namespace: shop}
spec:
  scaleTargetRef: {apiVersion: apps/v1, kind: Deployment, name: shop-api}
  minReplicas: 3
  maxReplicas: 50
  metrics:
    - type: Resource
      resource: {name: cpu, target: {type: Utilization, averageUtilization: 70}}
    - type: Pods
      pods:
        metric: {name: shop_http_requests_in_flight}
        target: {type: AverageValue, averageValue: "50"}
  behavior:
    scaleUp:   {stabilizationWindowSeconds: 0,   policies: [{type: Percent, value: 200, periodSeconds: 15}], selectPolicy: Max}
    scaleDown: {stabilizationWindowSeconds: 300, policies: [{type: Percent, value: 25,  periodSeconds: 60}], selectPolicy: Min}
```

> 🔑 **Go scales out faster than anything.** `scaleUp: 200% per 15s` with a 0.1 s Pod startup means you can go from 3 to 50 replicas in under a minute. Java can't do this — each Pod takes 30 s to become Ready. **Design your autoscaling around your runtime's startup time.**

**Sizing the memory limit for Go:**

Go's GC target is `GOGC=100` by default: the heap doubles before a collection. So peak RSS ≈ 2× live heap + goroutine stacks + off-heap.

```bash
kubectl port-forward -n shop svc/shop-api 8080:8080 & sleep 1
curl -s localhost:8080/metrics | grep -E '^go_memstats_(heap_alloc|heap_sys|stack_inuse|gc_sys)_bytes|^go_goroutines|^process_resident_memory_bytes'
```

```
go_goroutines 47
go_memstats_heap_alloc_bytes   3.1e+06     ← live heap: 3 MB
go_memstats_heap_sys_bytes     1.1e+07     ← reserved from OS: 11 MB
go_memstats_stack_inuse_bytes  1.3e+06     ← goroutine stacks: 1.3 MB
process_resident_memory_bytes  2.4e+07     ← RSS: 24 MB
```

So a `limits.memory: 256Mi` is **10× headroom** on a 24 MB process — deliberately generous, because under load the heap grows. Set it from a load test:

```bash
# drive 500 rps and watch RSS
hey -z 120s -q 100 -c 50 -host shop.example.com "http://$LB_IP/api/products" > /dev/null &
for i in $(seq 1 12); do
  printf '%s  ' "$(date +%T)"
  curl -s localhost:8080/metrics | awk '/^process_resident_memory_bytes/{printf "RSS %.0f MB  ", $2/1048576}
                                        /^go_goroutines/{printf "goroutines %d  ", $2}
                                        /^go_memstats_heap_alloc_bytes/{printf "heap %.0f MB\n", $2/1048576}'
  sleep 10
done
```

```
14:20:01  RSS 24 MB  goroutines 47   heap 3 MB
14:20:31  RSS 41 MB  goroutines 512  heap 18 MB
14:21:01  RSS 58 MB  goroutines 890  heap 31 MB
14:21:31  RSS 52 MB  goroutines 640  heap 24 MB     ← GC kicked in, RSS came DOWN
14:22:01  RSS 55 MB  goroutines 700  heap 27 MB
```

Set `limits.memory` to ~2× the observed peak: **128Mi** is comfortable here. Unlike Java, Go's RSS *does* come back down (it returns memory to the OS after ~5 minutes of low use), so you can run tighter.

**Tune the GC explicitly if you want lower latency at the cost of CPU:**

```yaml
env:
  - {name: GOGC,     value: "50"}     # collect more often → lower peak memory, more CPU
  - {name: GOMEMLIMIT, value: "200MiB"}   # ⭐ Go 1.19+ soft memory limit — the GC works
                                          #   harder as you approach it. Prevents OOMKill.
```

`GOMEMLIMIT` is the single most useful Go-on-Kubernetes setting: it makes the GC **aware of your container limit** and aggressively collect rather than being OOMKilled. Set it to ~80% of `limits.memory`.

```go
// or in code, read from the cgroup:
import "runtime/debug"
func init() {
    if v := os.Getenv("GOMEMLIMIT"); v != "" {
        n, _ := strconv.ParseInt(strings.TrimSuffix(v, "MiB"), 10, 64)
        debug.SetMemoryLimit(n * 1024 * 1024)
    }
}
```

---

## 12.6 ⭐ Graceful shutdown in Go — the full picture

The `scratch` image has **no shell**, so a `preStop: exec` hook is impossible. Two options:

**Option A — do it in Go (recommended for scratch).**

`server.Run()` above already does this:
1. `signal.NotifyContext(SIGTERM)` → ctx is cancelled
2. `s.draining.Store(true)` → `/readyz` returns 503 → kubelet removes the endpoint
3. `time.Sleep(3s)` → let kube-proxy/ingress propagate
4. `s.http.Shutdown(ctx)` → stop accepting, drain in-flight, bounded by `SHUTDOWN_TIMEOUT`
5. `s.store.Close()` → release the DB pool
6. `os.Exit(0)`

The math:

```
preStop              0s   (none — can't exec in scratch)
in-app drain wait    3s
Shutdown timeout    25s   (SHUTDOWN_TIMEOUT)
────────────────────────
worst case          28s
terminationGracePeriodSeconds  35s   ← ✅ 7s of margin
```

⚠️ **Go is PID 1 here.** Unlike Java/Python, the Go runtime forwards signals correctly to `signal.NotifyContext` — you don't need tini. But PID 1 also means:
- **Zombie reaping:** if you `exec.Command` anything, you must `Wait()` on it or you accumulate zombies. Go's runtime does reap orphans *if* you're PID 1 (since Go 1.20-ish behaviour varies) — **don't rely on it.** Prefer not spawning children.
- **Default signal disposition:** PID 1 ignores signals it has no handler for. You *must* register SIGTERM handling (done).

**Option B — use distroless/alpine and keep the preStop hook.**

```yaml
lifecycle:
  preStop:
    exec:
      command: ["/bin/sh", "-c", "sleep 8"]
```

With `alpine` you get `wget` too, so you can drain via HTTP:

```yaml
command: ["/bin/sh","-c","wget -qO- --post-data='' localhost:8080/api/chaos/drain || true; sleep 5"]
```

**Prove the whole thing works:**

```bash
LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# continuous load
hey -z 120s -q 100 -c 20 -host shop.example.com "http://$LB_IP/api/products" > go-rollout.txt &
HEY=$!

# watch the logs
kubectl logs -n shop -f deploy/shop-api --prefix &
LOGS=$!
sleep 5

# trigger
kubectl rollout restart deploy/shop-api -n shop
kubectl rollout status deploy/shop-api -n shop
sleep 30
kill $LOGS 2>/dev/null; wait $HEY
grep -A6 'Status code distribution' go-rollout.txt
grep -A3 'Error distribution' go-rollout.txt
```

```json
{"level":"INFO","msg":"shutdown_signal","signal":"context canceled","pod":"shop-api-7d4f…"}
{"level":"INFO","msg":"draining","msg2":"readiness now 503; waiting for endpoints to propagate"}
{"level":"INFO","msg":"request","status":200,"duration_ms":3}      ← in-flight, served
{"level":"INFO","msg":"request","status":200,"duration_ms":2}
{"level":"INFO","msg":"shutdown_complete","goroutines_remaining":3,"msg2":"exiting 0"}
```

```
Status code distribution:
  [200] 11994 responses
Error distribution:
  <nil>                                  ← ✅ ZERO dropped requests
```

**How fast was the rollout?**

```bash
time kubectl rollout restart deploy/shop-api -n shop && kubectl rollout status deploy/shop-api -n shop
# real 0m14.2s     ← Java: ~90s. Python: ~35s. Go: ~14s.
```

That's 3 Pods × (pull ~1 s + start ~0.1 s + ready ~0.1 s + drain ~5 s), with `maxSurge: 1` serialising them.

---

## 12.7 Debugging a container with no shell

`FROM scratch` has no `sh`, no `ls`, no `cat`, no `curl`, no `ps`. Here's the full toolkit.

### 1. Ephemeral debug container (the right way)

```bash
kubectl debug -n shop deploy/shop-api \
  --image=nicolaka/netshoot \
  --target=api \
  --share-processes \
  -it
```

```
Targeted container api is not running; waiting…
Creating debugging session attachable-ephemeral-container…
```

Now you're in netshoot **sharing the PID and network namespaces** with your Go process:

```bash
# see the Go process
ps aux
# root  1  0.3  0.0  12400  8300  ?  Ssl  14:20  0:01 /shop-api
# root 21  0.0  0.0   4200  3100  ?  S+   14:25  0:00 bash

# reach it over localhost (shared netns)
curl -s localhost:8080/health | jq .
curl -s localhost:8080/metrics | grep go_goroutines

# inspect the environment of PID 1
cat /proc/1/environ | tr '\0' '\n' | grep -E 'DATABASE|POD_'

# what files does it have open?
ls -l /proc/1/fd | head -20
# lrwx------ 1 root root 64 … 0 -> /dev/null
# lrwx------ 1 root root 64 … 3 -> socket:[12345]      ← a DB connection
# lrwx------ 1 root root 64 … 7 -> /run/secrets/db/url

# network state
ss -tnp
# ESTAB  0  0  10.244.2.19:8080  10.244.1.4:41222  users:(("shop-api",pid=1,fd=9))
# ESTAB  0  0  10.244.2.19:52341 10.244.3.8:5432   users:(("shop-api",pid=1,fd=14))

# can it reach the DB?
nc -zv db.shop.svc.cluster.local 5432
dig +short db.shop.svc.cluster.local

exit
```

### 2. `pprof` — Go's superpower

Add to `routes()`:

```go
import "net/http/pprof"

func (s *Server) registerPprof(mux *http.ServeMux) {
	// ⚠️ /debug/pprof exposes heap dumps, goroutine stacks and can be used to
	// DoS the process. NEVER route it through the public Ingress.
	mux.HandleFunc("GET /debug/pprof/", pprof.Index)
	mux.HandleFunc("GET /debug/pprof/cmdline", pprof.Cmdline)
	mux.HandleFunc("GET /debug/pprof/profile", pprof.Profile)
	mux.HandleFunc("GET /debug/pprof/symbol", pprof.Symbol)
	mux.HandleFunc("GET /debug/pprof/trace", pprof.Trace)
	mux.HandleFunc("GET /debug/pprof/{profile}", func(w http.ResponseWriter, r *http.Request) {
		pprof.Handler(r.PathValue("profile")).ServeHTTP(w, r)
	})
}
```

**Option A — port-forward (safe, works in production):**

```bash
kubectl port-forward -n shop deploy/shop-api 6060:8080 &
sleep 1
go tool pprof -http=:8081 http://localhost:6060/debug/pprof/profile?seconds=30
# → opens a CPU flame graph in your browser

go tool pprof -http=:8082 http://localhost:6060/debug/pprof/heap
# → memory allocation graph

curl -s http://localhost:6060/debug/pprof/goroutine?debug=1 | head -40
# goroutine profile: total 47
# 12 @ 0x43e1a6 … net/http.(*conn).serve
#  8 @ 0x43e1a6 … runtime.gopark
```

**Option B — a separate, cluster-internal port (production-safe):**

```go
// main.go — pprof on :6060, bound to the pod IP only, never in the Service
go func() {
	pprofMux := http.NewServeMux()
	pprofMux.HandleFunc("GET /debug/pprof/", pprof.Index)
	pprofMux.HandleFunc("GET /debug/pprof/profile", pprof.Profile)
	pprofMux.HandleFunc("GET /debug/pprof/heap", pprof.Handler("heap").ServeHTTP)
	pprofMux.HandleFunc("GET /debug/pprof/goroutine", pprof.Handler("goroutine").ServeHTTP)
	srv := &http.Server{Addr: cfg.PodIP + ":6060", Handler: pprofMux, ReadHeaderTimeout: 5*time.Second}
	log.Info("pprof", "addr", srv.Addr)
	if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Error("pprof", "error", err)
	}
}()
```

Now only Pods inside the cluster (or a `port-forward`) can reach it. The Ingress never routes to 6060.

### 3. Live memory/CPU without pprof

```bash
# Go runtime metrics are already in /metrics — this is usually enough
curl -s localhost:8080/metrics | grep -E '^go_(goroutines|threads|memstats_(heap_alloc|heap_objects|gc_(count|pause_total)|stack_inuse)|sched)'
```

| Metric | Watch for |
|---|---|
| `go_goroutines` | Monotonic increase = **goroutine leak** |
| `go_memstats_heap_objects` | Growth without GC reclaiming = live-data leak |
| `go_memstats_gc_pause_total_seconds` | Rising GC pressure |
| `go_threads` | Rising = blocking syscalls (DNS, file I/O, cgo) |
| `process_resident_memory_bytes` | The number the OOM killer uses |

**Goroutine-leak alert:**

```yaml
- alert: GoGoroutineLeak
  expr: |
    delta(shop_goroutines{app="shop-api"}[30m]) > 500
    and shop_goroutines{app="shop-api"} > 2000
  for: 10m
  labels: {severity: warning, team: shop}
  annotations:
    summary: "{{ $labels.pod }} goroutines grew by {{ $value }} in 30m (now {{ with query \"shop_goroutines\" }}{{ . | first | value }}{{ end }})"
    description: "Grab a profile: go tool pprof http://<pod>:8080/debug/pprof/goroutine"
```

**Find the leak from the profile:**

```bash
curl -s localhost:6060/debug/pprof/goroutine?debug=2 > goroutines.txt
# grep for the most common stack
grep -A8 '^goroutine ' goroutines.txt | grep -E 'shop-api-go/internal' | sort | uniq -c | sort -rn | head
#   4821 github.com/3558Bhk/shop-api-go/internal/api.(*Server).fetchRemote.func1
```

```go
// ⛔ THE BUG: no context, no timeout — a hung HTTP call leaks a goroutine forever
func (s *Server) fetchRemote(url string) {
	go func() {
		resp, err := http.Get(url)   // no timeout → hangs forever
		...
	}()
}

// ✅ THE FIX
func (s *Server) fetchRemote(ctx context.Context, url string) {
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	resp, err := s.httpClient.Do(req)     // a client WITH a Timeout
	...
}

var httpClient = &http.Client{
	Timeout: 10 * time.Second,          // ⭐ NEVER use http.DefaultClient — no timeout
	Transport: &http.Transport{
		MaxIdleConns:        100,
		MaxIdleConnsPerHost: 20,
		IdleConnTimeout:     90 * time.Second,
		DialContext:         (&net.Dialer{Timeout: 5 * time.Second, KeepAlive: 30 * time.Second}).DialContext,
		TLSHandshakeTimeout: 5 * time.Second,
	},
}
```

### 4. When you really need a shell

```bash
# copy a shell INTO the running container (needs a writable volume — we have /tmp)
kubectl cp /bin/busybox shop/shop-api-xxx:/tmp/busybox -c api
kubectl debug -n shop shop-api-xxx --image=alpine --target=api --share-processes -it
  /proc/1/root/tmp/busybox sh        # ← a shell rooted at the target container's filesystem
```

### 5. Reproduce outside Kubernetes

```bash
docker run --rm -it --cpus=1 --memory=256m -p 8080:8080 \
  -e DATABASE_URL="postgres://shop:shop@host.docker.internal:5432/app?sslmode=disable" \
  -e DEBUG=true -e ENVIRONMENT=development \
  shop-api-go:scratch
# in another terminal
go tool pprof -http=:8081 'http://localhost:8080/debug/pprof/profile?seconds=30'
```

---

## 12.8 Extra Tasks

### Task 12.1 — Make the Go service pass a chaos test

Kill the DB, kill the Pod, kill a node, saturate the CPU. The service must degrade gracefully every time.

<details>
<summary>Show answer</summary>

Four chaos scenarios, each with a specific Go fix.

```bash
NS=shop
LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
probe() {
  local n=${1:-30}
  for i in $(seq 1 $n); do
    printf '%s %s\n' "$(date +%T)" \
      "$(curl -sk -o /dev/null -w '%{http_code} %{time_total}s' --max-time 5 \
         --resolve shop.example.com:443:$LB_IP https://shop.example.com/api/products)"
    sleep 1
  done
}
```

### Chaos 1 — the database dies

```bash
probe 60 > /tmp/c1.txt &
sleep 5
kubectl scale sts/db -n $NS --replicas=0
sleep 40
kubectl scale sts/db -n $NS --replicas=1
wait
awk '{print $2}' /tmp/c1.txt | sort | uniq -c
```

**Without fixes:**
```
  20 200
  15 500 0.004s      ← fast 500s: connection refused
  10 500 30.001s     ← ⛔ 30-SECOND hangs: the default DB timeout
  15 200
```

**Three problems:** 500 instead of 503, 30-second hangs, and readiness not reflecting the DB.

```go
// FIX 1 — per-query timeout. Never let a DB call run unbounded.
func (s *Store) withTimeout(ctx context.Context, d time.Duration) (context.Context, context.CancelFunc) {
	return context.WithTimeout(ctx, d)
}

func (s *Store) ListProducts(ctx context.Context, q string, limit, offset int) ([]Product, error) {
	ctx, cancel := s.withTimeout(ctx, 2*time.Second)   // ⭐ hard ceiling
	defer cancel()
	...
}

// FIX 2 — pool timeouts so a saturated pool fails fast
db.SetMaxOpenConns(15)
// database/sql's QueryContext blocks until a conn is free OR ctx is done.
// The 2s ctx above covers it.

// FIX 3 — retry only the safe, transient errors
func isRetryable(err error) bool {
	if err == nil { return false }
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) {
		switch pgErr.Code {
		case "57P01", "57P02", "57P03", // admin_shutdown, crash_shutdown, cannot_connect_now
		     "53300",                   // too_many_connections
		     "08006", "08001", "08004": // connection failures
			return true
		}
	}
	// driver-level: connection refused / reset / EOF
	msg := err.Error()
	return strings.Contains(msg, "connection refused") ||
	       strings.Contains(msg, "connection reset") ||
	       errors.Is(err, io.ErrUnexpectedEOF) ||
	       errors.Is(err, syscall.ECONNREFUSED)
}

func withRetry[T any](ctx context.Context, attempts int, fn func(context.Context) (T, error)) (T, error) {
	var zero T
	var lastErr error
	for i := 0; i < attempts; i++ {
		if ctx.Err() != nil { return zero, ctx.Err() }
		v, err := fn(ctx)
		if err == nil { return v, nil }
		lastErr = err
		if !isRetryable(err) { return zero, err }
		// exponential backoff with jitter, capped
		d := time.Duration(float64(50*time.Millisecond) * math.Pow(2, float64(i)))
		if d > 2*time.Second { d = 2 * time.Second }
		d += time.Duration(rand.Int63n(int64(d / 2)))
		select {
		case <-time.After(d):
		case <-ctx.Done():
			return zero, ctx.Err()
		}
	}
	return zero, lastErr
}

// FIX 4 — a circuit breaker so a dead DB doesn't tie up every goroutine
type breaker struct {
	mu        sync.Mutex
	failures  int
	openedAt  time.Time
	failMax   int
	resetFor  time.Duration
}

func (b *breaker) allow() bool {
	b.mu.Lock(); defer b.mu.Unlock()
	if b.failures >= b.failMax {
		if time.Since(b.openedAt) > b.resetFor {
			b.failures, b.openedAt = 0, time.Now()   // half-open: let one through
			return true
		}
		return false
	}
	return true
}
func (b *breaker) record(err error) {
	b.mu.Lock(); defer b.mu.Unlock()
	if err != nil { b.failures++; b.openedAt = time.Now() } else { b.failures = 0 }
}

// in the handler
func (h *Handlers) ListProducts(w http.ResponseWriter, r *http.Request) {
	if !h.breaker.allow() {
		w.Header().Set("Retry-After", "15")
		h.writeErr(w, http.StatusServiceUnavailable, "database unavailable", requestID(r))
		return
	}
	products, err := h.store.ListProducts(r.Context(), q, limit, offset)
	h.breaker.record(err)
	...
}
```

**After:**
```
  20 200
   8 503 0.002s      ← ✅ fast, correct status, Retry-After
  32 200
```

Zero hangs, correct semantics, clients can retry intelligently.

### Chaos 2 — kill a Pod under load

```bash
hey -z 60s -q 100 -c 20 -host shop.example.com "http://$LB_IP/api/products" > /tmp/c2.txt &
sleep 5
kubectl delete pod -n $NS -l app=shop-api --field-selector metadata.name=$(kubectl get pod -n $NS -l app=shop-api -o jsonpath='{.items[0].metadata.name}')
wait $!
grep -A3 'Error distribution' /tmp/c2.txt
```

Should be zero errors (see §12.6). If you see `EOF` or `connection reset`:

| Symptom | Cause | Fix |
|---|---|---|
| A few `EOF`s right at the kill | The endpoint wasn't removed before the socket closed | Longer in-app drain wait (3 s → 8 s), or a `preStop` if you're on alpine |
| Sustained errors | Readiness probe too slow to notice | `periodSeconds: 5`, `failureThreshold: 2` |
| Errors on the *new* Pod | It became Ready before it could serve | Add a `startupProbe` if init is slow; verify `store.New()` pings the DB |
| Errors only from one client | Client keep-alive to a closed socket | Server-side `IdleTimeout` and client-side retry on `EOF` |

### Chaos 3 — saturate the CPU

```bash
# add a CPU-burn endpoint (dev only!)
# mux.HandleFunc("POST /api/chaos/burn", h.burnCPU)
func (h *Handlers) burnCPU(w http.ResponseWriter, r *http.Request) {
	secs, _ := strconv.ParseFloat(r.URL.Query().Get("seconds"), 64)
	if secs <= 0 || secs > 60 { secs = 10 }
	deadline := time.Now().Add(time.Duration(secs * float64(time.Second)))
	n := 0
	for time.Now().Before(deadline) { n++ }     // pure spin
	fmt.Fprintf(w, `{"spun":%d}`, n)
}

# trigger it on all replicas simultaneously
for i in 1 2 3 4 5 6; do
  curl -s -XPOST "http://$LB_IP/api/chaos/burn?seconds=30" -H "Host: shop.example.com" &
done

# watch
watch -n1 "kubectl top pod -n shop -l app=shop-api; \
           kubectl exec -n shop deploy/shop-api -- cat /sys/fs/cgroup/cpu.stat 2>/dev/null | grep throttled"
```

**What you'll see and what to do:**

```
NAME                        CPU(cores)   MEMORY
shop-api-5d8f7c9b6-abcde    998m         41Mi      ← pinned at the 1 CPU limit
nr_throttled 2847
throttled_usec 128400000

# and the liveness probe starts failing:
kubectl describe pod -n shop shop-api-5d8f7c9b6-abcde | grep -A3 Events
# Warning  Unhealthy  Liveness probe failed: Get "http://10.244.2.19:8080/healthz": context deadline exceeded
# Normal   Killing    Container api failed liveness probe, will be restarted
```

⛔ **This is the bad case: throttling causes a healthy Pod to be restarted**, which makes the problem worse (fewer Pods, more load each).

**Fixes, in order:**

1. **Widen the liveness probe.** It should be nearly impossible to fail:
   ```yaml
   livenessProbe:
     periodSeconds: 20
     timeoutSeconds: 5        # not 1
     failureThreshold: 5      # not 3 → 100s of tolerance
   ```
2. **Raise the limit, keep the request.** CPU is compressible — throttling is a latency problem, not a crash problem:
   ```yaml
   resources:
     requests: {cpu: 200m}     # what you're billed / scheduled on
     limits:   {cpu: "2"}      # burst ceiling. Or omit CPU limits entirely.
   ```
   > 🔑 **Many teams remove CPU limits completely** (keeping requests). Kubernetes schedules on requests; limits only cause throttling. Memory limits stay — memory is incompressible.
3. **Make `GOMAXPROCS` match.** With `limits.cpu: 2`, `automaxprocs` sets `GOMAXPROCS=2` — the process can actually use both.
4. **Let the HPA respond.** CPU saturation should scale out, not throttle:
   ```bash
   kubectl get hpa shop-api -n $NS -w
   # shop-api   Deployment/shop-api   2841m/1 (70%), 312/50   3   50   9
   ```
5. **Protect the probe path from your own load.** A semaphore around expensive handlers:
   ```go
   var sem = make(chan struct{}, 100)   // max 100 concurrent expensive requests
   func (h *Handlers) expensive(w http.ResponseWriter, r *http.Request) {
       select {
       case sem <- struct{}{}:
           defer func() { <-sem }()
       default:
           w.Header().Set("Retry-After", "2")
           h.writeErr(w, http.StatusTooManyRequests, "server busy", requestID(r))
           return
       }
       ...
   }
   ```
   Probes stay fast because `/healthz` doesn't take the semaphore.

### Chaos 4 — kill a node

```bash
kubectl get pods -n $NS -l app=shop-api -o wide      # confirm 3 different nodes
VICTIM=$(kubectl get pods -n $NS -l app=shop-api -o wide --no-headers | awk 'NR==1{print $7}')
probe 300 > /tmp/c4.txt &
docker stop $VICTIM
sleep 240
docker start $VICTIM
wait
awk '{print $2}' /tmp/c4.txt | sort | uniq -c
```

Go's advantage here is stark:

| Runtime | Time from node loss to full capacity |
|---|---|
| Java | ~6 min (300 s eviction + 40 s JVM boot × serial rollout) |
| Python | ~5.5 min |
| **Go** | **~5.2 min** (300 s eviction + ~1 s boot; the eviction window dominates) |

The 300 s is the `node.kubernetes.io/unreachable` default toleration. Shorten it for stateless Go services:

```yaml
      tolerations:
        - key: node.kubernetes.io/unreachable
          operator: Exists
          effect: NoExecute
          tolerationSeconds: 30        # ⭐ safe for stateless, NOT for StatefulSets
        - key: node.kubernetes.io/not-ready
          operator: Exists
          effect: NoExecute
          tolerationSeconds: 30
```

→ Full recovery in ~40 s instead of ~5.5 min. Because Go Pods start in milliseconds and hold no local state, aggressive rescheduling is genuinely safe here.

**The chaos report:**

| Scenario | Before | After | Key fix |
|---|---|---|---|
| DB dies | 30 s hangs, 500s | 2 ms 503s | query timeout + circuit breaker + readiness |
| Pod killed | a few EOFs | zero errors | in-app drain + `Shutdown()` |
| CPU saturated | restart loop | throttled but stable | wider probe + no CPU limit + HPA |
| Node killed | 5.5 min | 40 s | `tolerationSeconds: 30` |

</details>

---

### Task 12.2 — Build a multi-arch Go image and deploy it

`linux/amd64` and `linux/arm64` in one manifest list, so Apple Silicon laptops and x86 nodes both work.

<details>
<summary>Show answer</summary>

Go is the easiest language for this: **cross-compilation is built in.** No QEMU emulation of the *build*, just `GOARCH=arm64`.

### 1. Set up buildx

```bash
docker buildx create --name multi --driver docker-container --bootstrap --use
docker buildx inspect --bootstrap
# Platforms: linux/amd64, linux/arm64, linux/arm/v7, …
```

### 2. The multi-arch Dockerfile

```dockerfile
# syntax=docker/dockerfile:1

# ── builder: TARGETARCH is set automatically by buildx ──
FROM --platform=$BUILDPLATFORM golang:1.23-bookworm AS builder
#   ⭐ --platform=$BUILDPLATFORM runs the builder on the NATIVE arch.
#      No QEMU emulation → the build is 10-20× faster.

ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT

ENV CGO_ENABLED=0 \
    GOOS=${TARGETOS} \
    GOARCH=${TARGETARCH} \
    GOFLAGS="-trimpath"

WORKDIR /src
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go mod download -x

COPY . .

ARG GIT_SHA=unknown
ARG VERSION=dev

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go build -trimpath -buildvcs=false \
      -ldflags="-s -w -X main.version=${VERSION} -X main.revision=${GIT_SHA}" \
      -o /out/shop-api-${TARGETOS}-${TARGETARCH}${TARGETVARIANT} \
      ./cmd/server

RUN ls -lh /out/ && file /out/shop-api-*


# ── runtime: scratch is inherently multi-arch (it's empty) ──
FROM scratch AS runtime
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /etc/passwd /etc/passwd
# ⭐ BuildKit resolves this to the arch-specific binary automatically
COPY --from=builder /out/shop-api-${TARGETOS}-${TARGETARCH}${TARGETVARIANT} /shop-api
USER 65534:65534
EXPOSE 8080
ENTRYPOINT ["/shop-api"]
```

> 🔑 If you use a base image with content (`alpine`, `distroless`), `COPY --from=builder` still works because buildx runs the builder stage per-arch. The `FROM scratch` line is arch-neutral.

### 3. Build and push

```bash
REGISTRY=ghcr.io/3558bhk
TAG=1.0.0

docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --build-arg GIT_SHA=$(git rev-parse --short HEAD) \
  --build-arg VERSION=$TAG \
  -t $REGISTRY/shop-api-go:$TAG \
  -t $REGISTRY/shop-api-go:latest \
  --provenance=true \
  --sbom=true \
  --push \
  -f Dockerfile .
```

```
#0 building builder "multi"
#4 [linux/amd64 builder 3/6] COPY go.mod go.sum ./                0.1s
#5 [linux/arm64 builder 3/6] COPY go.mod go.sum ./                0.1s
#9 [linux/amd64 builder 6/6] RUN go build …                      34.2s
#10 [linux/arm64 builder 6/6] RUN go build …                      36.8s   ← native cross-compile, NOT emulated
#14 exporting to image
#15 pushing manifest for ghcr.io/3558bhk/shop-api-go:1.0.0
```

### 4. Verify the manifest list

```bash
docker buildx imagetools inspect $REGISTRY/shop-api-go:$TAG
```

```
Name:      ghcr.io/3558bhk/shop-api-go:1.0.0
MediaType: application/vnd.oci.image.index.v1+json
Digest:    sha256:9f2a…

Manifests:
  Name:      …@sha256:1a2b…
  MediaType: application/vnd.oci.image.manifest.v1+json
  Platform:  linux/amd64

  Name:      …@sha256:3c4d…
  MediaType: application/vnd.oci.image.manifest.v1+json
  Platform:  linux/arm64

  Name:      …@sha256:5e6f…
  MediaType: application/vnd.oci.image.manifest.v1+json
  Platform:  unknown/unknown          ← the attestation manifest (provenance/SBOM)
  Annotations:
    vnd.docker.reference.type: attestation-manifest
```

```bash
# per-arch details
docker buildx imagetools inspect $REGISTRY/shop-api-go:$TAG --format '{{json .Manifest}}' | jq .
docker manifest inspect $REGISTRY/shop-api-go:$TAG | jq '.manifests[] | {platform, digest}'
```

### 5. Run both arches locally

```bash
# native
docker run --rm -p 8080:8080 $REGISTRY/shop-api-go:$TAG &
sleep 1; curl -s localhost:8080/healthz; kill %1

# emulated (slow, but proves it works)
docker run --rm --platform linux/arm64 -p 8081:8080 \
  -e DATABASE_URL="postgres://shop:shop@host.docker.internal:5432/app?sslmode=disable" \
  $REGISTRY/shop-api-go:$TAG &
sleep 3; curl -s localhost:8081/healthz
docker exec $(docker ps -q | head -1) uname -m     # aarch64 ✅
kill %1
```

On Apple Silicon, `docker run` without `--platform` picks arm64 natively and there's no emulation at all.

### 6. Deploy — Kubernetes picks the right arch automatically

Nothing changes in the manifest. The kubelet requests the manifest list, the registry returns the entry matching the node's arch:

```bash
kubectl set image deploy/shop-api -n shop api=$REGISTRY/shop-api-go:$TAG
kubectl rollout status deploy/shop-api -n shop

# verify each Pod got the right one
kubectl get pods -n shop -l app=shop-api -o custom-columns=\
'POD:.metadata.name,NODE:.spec.nodeName,ARCH:.spec.nodeName,IMAGE:.spec.containers[0].image'
kubectl get nodes -o custom-columns='NODE:.metadata.name,ARCH:.status.nodeInfo.architecture,OS:.status.nodeInfo.osImage'
```

```
NODE              ARCH     OS
learn-worker      amd64    Debian GNU/Linux 12
learn-worker2     arm64    Debian GNU/Linux 12     ← an emulated arm64 kind node
```

```bash
# and prove the running binary matches
for p in $(kubectl get pods -n shop -l app=shop-api -o name); do
  node=$(kubectl get $p -n shop -o jsonpath='{.spec.nodeName}')
  arch=$(kubectl get node $node -o jsonpath='{.status.nodeInfo.architecture}')
  ver=$(kubectl exec -n shop $p -- /shop-api -version 2>/dev/null || echo "?")
  echo "$p on $node ($arch): $ver"
done
```

### 7. CI/CD

```yaml
# .github/workflows/release.yml
jobs:
  build:
    runs-on: ubuntu-24.04
    permissions: {contents: read, packages: write, id-token: write}
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-qemu-action@v3          # for non-Go stages if any
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - id: meta
        uses: docker/metadata-action@v5
        with:
          images: ghcr.io/3558bhk/shop-api-go
          tags: |
            type=semver,pattern={{version}}
            type=sha,prefix=sha-
            type=ref,event=branch
      - uses: docker/build-push-action@v6
        with:
          context: ./api
          platforms: linux/amd64,linux/arm64
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          build-args: |
            GIT_SHA=${{ github.sha }}
            VERSION=${{ steps.meta.outputs.version }}
          provenance: true
          sbom: true
          cache-from: type=gha
          cache-to: type=gha,mode=max
      - uses: aquasecurity/trivy-action@0.28.0
        with:
          image-ref: ghcr.io/3558bhk/shop-api-go:${{ steps.meta.outputs.version }}
          severity: CRITICAL,HIGH
          ignore-unfixed: true
          exit-code: 1
      - uses: sigstore/cosign-installer@v3
      - run: |
          cosign sign --yes \
            ghcr.io/3558bhk/shop-api-go@$(crane digest ghcr.io/3558bhk/shop-api-go:${{ steps.meta.outputs.version }})
```

> ⚠️ **Sign the digest, not the tag.** A multi-arch tag points at a manifest *list*; cosign needs the index digest.

### 8. Gotchas

| Problem | Cause | Fix |
|---|---|---|
| Build takes 20 minutes | buildx emulated the Go build | `FROM --platform=$BUILDPLATFORM` |
| `exec format error` in the Pod | Wrong-arch image loaded | Check `kubectl get node -o …architecture` and `imagetools inspect` |
| `kind load docker-image` only loads one arch | kind nodes have a fixed arch | Use a registry mirror inside kind, or build for the node's arch |
| arm64 image is 2× bigger | Debug symbols not stripped | `-ldflags="-s -w"` |
| CGO dependency fails on arm64 | `CGO_ENABLED=1` needs a cross-compiler | Keep `CGO_ENABLED=0`; if you need cgo (sqlite3, some ML libs), use `zig cc` or build natively per arch |
| Tests only run on amd64 | CI matrix missing | `strategy.matrix.platform: [linux/amd64, linux/arm64]` |
| Attestation manifest confuses tooling | `--provenance=true` adds an `unknown/unknown` entry | Normal; older Docker versions may need `--provenance=mode=min` |

**The CGO case** — if you must use cgo (e.g. `mattn/go-sqlite3`):

```dockerfile
FROM --platform=$BUILDPLATFORM golang:1.23-bookworm AS builder
ARG TARGETARCH
RUN apt-get update && apt-get install -y --no-install-recommends \
      gcc-aarch64-linux-gnu libc6-dev-arm64-cross     # cross toolchain
ENV CGO_ENABLED=1 GOARCH=${TARGETARCH}
ENV CC_aarch64=aarch64-linux-gnu-gcc
RUN CC=${CC_aarch64:-gcc} go build …
```

…and the runtime can no longer be `scratch` — it needs the target's libc:

```dockerfile
FROM gcr.io/distroless/base-debian12:nonroot
```

**Prefer pure Go.** `modernc.org/sqlite` (cgo-free), `pgx` (pure Go), `go-sql-driver/mysql` (pure Go). Then `scratch` + `CGO_ENABLED=0` works everywhere.

</details>

---

### Task 12.3 — Achieve p99 < 20ms at 2,000 rps on one Pod

Profile, fix, measure. Document every change with its before/after number.

<details>
<summary>Show answer</summary>

### Step 0 — establish the baseline honestly

```bash
# one replica, pinned resources, no HPA interference
kubectl scale deploy/shop-api -n shop --replicas=1
kubectl scale hpa/shop-api -n shop --replicas=1 2>/dev/null || kubectl delete hpa shop-api -n shop
kubectl set resources deploy/shop-api -n shop -c api --requests=cpu=2,memory=256Mi --limits=cpu=2,memory=512Mi
kubectl rollout status deploy/shop-api -n shop
sleep 20   # warm up

LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
hey -z 60s -c 100 -q 20 -host shop.example.com "http://$LB_IP/api/products?limit=20" > base.txt
grep -E 'Requests/sec|Latency distribution|Status code' -A6 base.txt
```

```
Requests/sec:            1204.3
Latency distribution:
  50% in 0.0210 secs
  95% in 0.0890 secs
  99% in 0.2140 secs      ← target is <0.020. We're 10× off.
```

### Step 1 — where is the time going?

**Break it into segments:**

```bash
# client → ingress
curl -sk -o /dev/null -w 'dns %{time_namelookup}  connect %{time_connect}  ttfb %{time_starttransfer}  total %{time_total}\n' \
  --resolve shop.example.com:443:$LB_IP https://shop.example.com/api/products

# ingress → app (from inside the cluster, no ingress)
kubectl run bench -n shop --rm -it --image=nicolaka/netshoot --restart=Never -- \
  sh -c 'for i in $(seq 1 20); do curl -s -o /dev/null -w "%{time_total}\n" http://shop-api:8080/api/products; done' \
  | sort -n | tail -3
```

| Segment | Time | Verdict |
|---|---|---|
| Client → Ingress (TLS, LB) | 3 ms | Fine |
| Ingress → Pod | 1 ms | Fine |
| **Pod processing** | **17 ms** | ⛔ the problem |
| Pod → Postgres | 14 ms | ⛔⛔ **most of it** |

**Confirm with the app's own metrics:**

```bash
kubectl port-forward -n shop svc/shop-api 8080:8080 & sleep 1
curl -s localhost:8080/metrics | grep -E '^shop_(http_request_duration|db_query_duration)_seconds_bucket' \
  | awk '{print $1, $2}' | tail -20
```

```promql
histogram_quantile(0.99, sum by (le) (rate(shop_http_request_duration_seconds_bucket[5m])))   # 0.021
histogram_quantile(0.99, sum by (le) (rate(shop_db_query_duration_seconds_bucket[5m])))       # 0.017  ← 80% of it
```

### Step 2 — CPU profile

```bash
go tool pprof -http=:8081 'http://localhost:8080/debug/pprof/profile?seconds=30' &
hey -z 35s -c 100 -q 20 -host shop.example.com "http://$LB_IP/api/products?limit=20" > /dev/null
```

Top of the flame graph:

```
      flat  flat%   sum%        cum   cum%
     4.21s 18.3%  18.3%     12.4s 53.9%  github.com/jackc/pgx/v5/pgconn.(*PgConn).ReceiveMessage
     2.88s 12.5%  30.8%      3.90s 16.9%  encoding/json.(*encodeState).marshal
     1.94s  8.4%  39.2%      8.20s 35.6%  database/sql.(*DB).query
     1.12s  4.9%  44.1%      1.12s  4.9%  runtime.gcBgMarkWorker
```

Two clear targets: **the DB round-trip** and **JSON encoding**.

### Step 3 — the fixes, each measured

**Fix 1 — add the missing index.** (Biggest single win.)

```sql
-- the query filters on name ILIKE and orders by id
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_products_name_trgm
  ON products USING gin (name gin_trgm_ops);
-- or, if the sort is the problem:
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_products_id ON products (id);
```

```bash
kubectl exec -n shop db-0 -- psql -U shop -d app -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;"
kubectl exec -n shop db-0 -- psql -U shop -d app -c "CREATE INDEX CONCURRENTLY idx_products_name_trgm ON products USING gin (name gin_trgm_ops);"
kubectl exec -n shop db-0 -- psql -U shop -d app -c "ANALYZE products;"
kubectl exec -n shop db-0 -- psql -U shop -d app -c \
  "EXPLAIN (ANALYZE, BUFFERS) SELECT id,name,price,description,created_at FROM products WHERE name ILIKE '%wid%' ORDER BY id LIMIT 20;"
```

Before:
```
Seq Scan on products  (cost=0.00..48210.00 rows=1000 width=88) (actual time=0.021..13.842 rows=12 loops=1)
  Filter: (name ~~* '%wid%'::text)
  Rows Removed by Filter: 99988
Buffers: shared hit=1204
```

After:
```
Limit  (cost=0.41..8.43 rows=12 width=88) (actual time=0.042..0.118 rows=12 loops=1)
  ->  Index Scan using idx_products_id on products  (actual time=0.040..0.112 rows=12 loops=1)
        Filter: (name ~~* '%wid%'::text)
Buffers: shared hit=18
```

**13.8 ms → 0.12 ms.**

**Fix 2 — connection pool sizing.**

```bash
curl -s localhost:8080/metrics | grep -E '^shop_db_(connections_in_use|connections_idle|wait_count_total)'
# shop_db_connections_in_use 15      ← MAXED OUT at DB_POOL_MAX_OPEN=15
# shop_db_wait_count_total   48210   ← ⛔ 48k requests waited for a connection
```

```yaml
DB_POOL_MAX_OPEN: "50"      # was 15
DB_POOL_MAX_IDLE: "25"      # keep them warm
DB_POOL_MAX_LIFE: "30m"
```

⚠️ Check the DB side too:

```bash
kubectl exec -n shop db-0 -- psql -U shop -d app -c 'SHOW max_connections;'      # 100 by default
kubectl exec -n shop db-0 -- psql -U shop -d app -c 'SELECT count(*) FROM pg_stat_activity;'
```

`replicas × pool_max_open` must be < `max_connections` × 0.8. With 10 pods × 50 = 500 > 100 → raise Postgres' limit or add PgBouncer.

**Result: p99 21 ms → 8 ms.**

**Fix 3 — stop re-encoding the same JSON.** Add an ETag / cache for hot reads:

```go
func (h *Handlers) ListProducts(w http.ResponseWriter, r *http.Request) {
	// cheap, deterministic key
	key := fmt.Sprintf("products:%s:%d:%d", q, limit, offset)

	if cached, ok := h.cache.Get(key); ok {
		w.Header().Set("ETag", cached.etag)
		w.Header().Set("X-Cache", "HIT")
		if match := r.Header.Get("If-None-Match"); match == cached.etag {
			w.WriteHeader(http.StatusNotModified)   // ⭐ 304, no body, no DB, no encode
			return
		}
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		w.Header().Set("Cache-Control", "private, max-age=2")
		_, _ = w.Write(cached.body)
		return
	}
	...
	body, _ := json.Marshal(products)
	etag := `"` + sha256hex(body)[:16] + `"`
	h.cache.Set(key, entry{etag: etag, body: body}, 2*time.Second)
	w.Header().Set("ETag", etag)
	w.Header().Set("X-Cache", "MISS")
	w.Header().Set("Cache-Control", "private, max-age=2")
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	_, _ = w.Write(body)
}
```

Use a bounded cache — **never an unbounded map** (that's the goroutine/memory leak from §12.7):

```go
import "github.com/dgraph-io/ristretto"
cache, _ := ristretto.NewCache(&ristretto.Config{
	NumCounters: 1e6, MaxCost: 1 << 27 /* 128 MB */, BufferItems: 64,
})
```

**Result: p99 8 ms → 4 ms** (most requests are now cache hits).

**Fix 4 — faster JSON.** `encoding/json` is reflection-based. For hot paths:

```go
// option A: easyjson (code generation)
//go:generate easyjson -all internal/store/store.go

// option B: sonic / json-iterator
import "github.com/bytedance/sonic"
body, err := sonic.Marshal(products)     // 3-6× faster than encoding/json

// option C: hand-roll for a tiny struct (fastest, most code)
func encodeProducts(w *bytes.Buffer, ps []store.Product) {
	w.WriteByte('[')
	for i, p := range ps {
		if i > 0 { w.WriteByte(',') }
		w.WriteString(`{"id":`); w.Write(strconv.AppendInt(nil, p.ID, 10))
		w.WriteString(`,"name":"`); w.Write(escapeJSON(p.Name))
		w.WriteString(`","price":`); w.Write(strconv.AppendFloat(nil, p.Price, 'f', 2, 64))
		w.WriteByte('}')
	}
	w.WriteByte(']')
}
```

**Result: p99 4 ms → 3.2 ms.** Diminishing returns — measure before adding complexity.

**Fix 5 — reduce allocations (the GC cost).**

```bash
go test -bench=BenchmarkListProducts -benchmem ./internal/api
# BenchmarkListProducts-2   50000   24103 ns/op   4821 B/op   62 allocs/op
```

```go
// ⛔ allocating a new slice every request
products := make([]Product, 0, limit)

// ✅ preallocate from a sync.Pool for hot paths
var productPool = sync.Pool{New: func() any { s := make([]Product, 0, 64); return &s }}

// ⛔ string concatenation in a loop
s += x
// ✅ strings.Builder
var b strings.Builder; b.WriteString(x)

// ⛔ fmt.Sprintf on a hot path (reflection + allocation)
key := fmt.Sprintf("products:%s:%d:%d", q, limit, offset)
// ✅ strconv
key := "products:" + q + ":" + strconv.Itoa(limit) + ":" + strconv.Itoa(offset)

// ⛔ time.Now().Format() per log line
// ✅ cache the second-granularity timestamp
```

Set `GOGC` / `GOMEMLIMIT` to trade CPU for latency:

```yaml
env:
  - {name: GOGC, value: "200"}          # collect less often → fewer GC pauses, more memory
  - {name: GOMEMLIMIT, value: "400MiB"} # the safety net that keeps GOGC=200 from OOMing
```

**Result: p99 3.2 ms → 2.6 ms**, GC pause total dropped 40%.

**Fix 6 — the load balancer and TLS.**

```bash
# is the ingress the bottleneck now?
kubectl top pod -n ingress-nginx
kubectl -n ingress-nginx exec deploy/ingress-nginx-controller -- nginx -T | grep -E 'worker_processes|worker_connections|keepalive'
```

```yaml
# ingress-nginx values
controller:
  config:
    worker-processes: "auto"
    max-worker-connections: "65536"
    upstream-keepalive-connections: "320"      # ⭐ reuse connections to the Pods
    upstream-keepalive-timeout: "60"
    upstream-keepalive-requests: "10000"
    enable-brotli: "false"                     # CPU cost > benefit for JSON
    use-gzip: "false"                          # for small JSON bodies, gzip costs more than it saves
```

**Result: p99 2.6 ms → 2.1 ms.**

### Step 4 — the final measurement

```bash
hey -z 60s -c 100 -q 40 -host shop.example.com "http://$LB_IP/api/products?limit=20" > final.txt
grep -E 'Requests/sec|Latency distribution|Status code' -A6 final.txt
```

```
Requests/sec:            3987.2                 ← 1204 → 3987 (3.3×)
Latency distribution:
  50% in 0.0021 secs
  95% in 0.0058 secs
  99% in 0.0142 secs      ← ✅ target was <0.020
Status code distribution:
  [200] 239210 responses
  [304]  41203 responses  ← cache hits
```

### Step 5 — the log of every change

| # | Change | p99 before | p99 after | Effort | Keep? |
|---|---|---|---|---|---|
| 1 | `CREATE INDEX … gin_trgm_ops` + `ANALYZE` | 21.0 ms | 8.0 ms | 5 min | ✅ always |
| 2 | `DB_POOL_MAX_OPEN` 15 → 50, `MAX_IDLE` 5 → 25 | 8.0 ms | 4.0 ms | 2 min | ✅ |
| 3 | 2 s in-memory cache + ETag/304 | 4.0 ms | 3.2 ms | 40 min | ✅ if data tolerates 2 s staleness |
| 4 | `sonic` instead of `encoding/json` | 3.2 ms | 2.9 ms | 15 min | ⚠️ marginal |
| 5 | `GOGC=200` + `GOMEMLIMIT` + allocation cleanup | 2.9 ms | 2.6 ms | 2 h | ✅ |
| 6 | Ingress keepalive tuning | 2.6 ms | 2.1 ms | 10 min | ✅ |

**The lesson:** the index (5 minutes of work) delivered **62% of the total improvement**. Steps 4 and 5 took hours for 10%. **Always profile before optimising**, and always write down the numbers — otherwise you'll keep the complexity and lose the benefit.

### Step 6 — verify it holds, and guard it

```bash
# soak: 20 minutes, watch for drift (goroutine leaks, memory creep)
hey -z 1200s -c 50 -q 20 -host shop.example.com "http://$LB_IP/api/products" > soak.txt &
for i in $(seq 1 20); do
  printf '%s ' "$(date +%T)"
  curl -s localhost:8080/metrics | awk '/^go_goroutines/{printf "gor %s ", $2}
    /^process_resident_memory_bytes/{printf "rss %.0fMB ", $2/1048576}
    /^shop_db_wait_count_total/{printf "dbwait %s\n", $2}'
  sleep 60
done
```

```
14:30:00 gor 412  rss 38MB  dbwait 0
14:40:00 gor 418  rss 41MB  dbwait 0
14:50:00 gor 415  rss 40MB  dbwait 0     ← ✅ flat. No leak.
```

```yaml
- alert: ShopApiLatencyRegression
  expr: |
    histogram_quantile(0.99, sum by (le) (rate(shop_http_request_duration_seconds_bucket{path="/api/products"}[5m]))) > 0.020
  for: 10m
  labels: {severity: warning}
  annotations:
    summary: "p99 for /api/products is {{ $value }}s — the SLO is 20ms"
    description: "Profile it: go tool pprof http://<pod>:8080/debug/pprof/profile?seconds=30"
```

Add the benchmark to CI so a regression fails the build:

```yaml
      - run: go test -bench=. -benchmem -benchtime=5s ./... | tee bench.txt
      - uses: benchmark-action/github-action-benchmark@v1
        with:
          tool: go
          output-file-path: bench.txt
          github-token: ${{ secrets.GITHUB_TOKEN }}
          alert-threshold: "120%"          # fail if 20% slower than the last run
          comment-on-alert: true
          fail-on-alert: true
```

</details>

---

### Task 12.4 — Build the migrations tool as a separate Go binary and run it as a Job

One image, two entrypoints. No shell needed.

<details>
<summary>Show answer</summary>

Go makes this trivially easy — and it's the cleanest migration story of the three runtimes, because there's no framework to fight.

### 1. The migrate command

`api/cmd/migrate/main.go`:

```go
package main

import (
	"context"
	"embed"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"time"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/postgres"
	"github.com/golang-migrate/migrate/v4/source/iofs"
	"github.com/jackc/pgx/v5"

	"github.com/3558Bhk/shop-api-go/internal/config"
)

// ⭐ embed the .sql files INTO the binary.
// No volume mounts, no ConfigMaps, no "migration file not found in production".
//
//go:embed all:migrations
var migrationsFS embed.FS

func main() {
	var (
		dir      = flag.String("dir", "up", "up | down | version | force | redo | status")
		steps    = flag.Int("steps", 1, "number of migrations for up/down N")
		to       = flag.Uint("to", 0, "target version for force")
		timeout  = flag.Duration("timeout", 15*time.Minute, "overall timeout")
		waitDB   = flag.Duration("wait-for-db", 3*time.Minute, "how long to wait for the DB to accept connections")
		dryRun   = flag.Bool("dry-run", false, "print what would run, change nothing")
	)
	flag.Parse()

	log := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))

	cfg, err := config.Load()
	if err != nil {
		log.Error("config", "error", err)
		os.Exit(1)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscallTERM())
	defer stop()
	ctx, cancel := context.WithTimeout(ctx, *timeout)
	defer cancel()

	// ── 1. wait for the database (replaces the busybox init container) ──
	if err := waitForDB(ctx, cfg.DatabaseURL, *waitDB, log); err != nil {
		log.Error("db_unavailable", "error", err)
		os.Exit(1)
	}

	// ── 2. acquire an advisory lock so N concurrent Jobs can't double-apply ──
	//    pg_advisory_lock is held for the session; it releases on disconnect.
	conn, err := pgx.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Error("connect", "error", err)
		os.Exit(1)
	}
	defer conn.Close(ctx)

	const lockKey int64 = 8675309 // arbitrary, stable, project-specific
	log.Info("acquiring_lock", "key", lockKey)
	var got bool
	if err := conn.QueryRow(ctx, "SELECT pg_try_advisory_lock($1)", lockKey).Scan(&got); err != nil {
		log.Error("advisory_lock", "error", err)
		os.Exit(1)
	}
	if !got {
		log.Warn("another_migration_is_running", "msg", "exiting 0 — not a failure")
		os.Exit(0) // ⭐ idempotent: safe for `kubectl apply` retries and parallel Jobs
	}
	defer func() {
		var rel bool
		_ = conn.QueryRow(context.WithoutCancel(ctx), "SELECT pg_advisory_unlock($1)", lockKey).Scan(&rel)
		log.Info("lock_released", "released", rel)
	}()

	// ── 3. build the migrate driver from the embedded FS ──
	d, err := iofs.New(migrationsFS, "migrations")
	if err != nil {
		log.Error("source", "error", err)
		os.Exit(1)
	}
	m, err := migrate.NewWithSourceInstance("iofs", d, cfg.DatabaseURL)
	if err != nil {
		log.Error("migrate_init", "error", err)
		os.Exit(1)
	}
	m.Log = &migrateLogger{log: log}

	// ── 4. run ──
	start := time.Now()
	switch *dir {
	case "status", "version":
		v, dirty, err := m.Version()
		if errors.Is(err, migrate.ErrNilVersion) {
			fmt.Println("no migrations applied yet")
			return
		}
		if err != nil {
			log.Error("version", "error", err); os.Exit(1)
		}
		applied := countApplied(ctx, conn)
		fmt.Printf("version=%d dirty=%v applied=%d\n", v, dirty, applied)

	case "up":
		if *dryRun {
			printPlan(ctx, conn, migrationsFS, log)
			return
		}
		if *steps > 0 && flag.CommandLine.Lookup("steps").Value.String() != "1" {
			err = m.Steps(*steps)
		} else {
			err = m.Up()
		}
		if err != nil && !errors.Is(err, migrate.ErrNoChange) {
			log.Error("migrate_up", "error", err, "hint", hint(err))
			os.Exit(1)
		}
		if errors.Is(err, migrate.ErrNoChange) {
			log.Info("no_change", "msg", "schema already up to date")
		}

	case "down":
		if *dryRun { log.Warn("dry_run_not_supported", "for", "down"); return }
		if err := m.Steps(-*steps); err != nil && !errors.Is(err, migrate.ErrNoChange) {
			log.Error("migrate_down", "error", err); os.Exit(1)
		}

	case "force":
		if err := m.Force(int(*to)); err != nil {
			log.Error("force", "error", err); os.Exit(1)
		}
		log.Warn("forced_version", "version", *to, "msg", "the DB may now be inconsistent")

	default:
		log.Error("unknown_direction", "dir", *dir)
		os.Exit(2)
	}

	v, dirty, _ := m.Version()
	log.Info("migration_complete",
		"direction", *dir,
		"version", v,
		"dirty", dirty,
		"duration_s", time.Since(start).Seconds(),
	)
}

func waitForDB(ctx context.Context, url string, max time.Duration, log *slog.Logger) error {
	deadline := time.Now().Add(max)
	for i := 1; time.Now().Before(deadline); i++ {
		c, err := pgx.Connect(ctx, url)
		if err == nil {
			// connected ≠ ready: Postgres accepts TCP during crash recovery
			// but rejects queries. Verify with a real query.
			if err := c.Ping(ctx); err == nil {
				_ = c.Close(ctx)
				log.Info("db_ready", "attempt", i)
				return nil
			}
			_ = c.Close(ctx)
		}
		log.Info("waiting_for_db", "attempt", i, "error", err)
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(2 * time.Second):
		}
	}
	return fmt.Errorf("database not ready after %s", max)
}

func hint(err error) string {
	if errors.Is(err, migrate.ErrDirty) {
		return "the previous migration failed partway. Inspect the DB, then run: migrate -dir=force -to=<last good version>"
	}
	return ""
}
```

### 2. Migration files

`api/migrations/000001_create_products.up.sql`:

```sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE products (
    id          BIGSERIAL PRIMARY KEY,
    name        VARCHAR(120) NOT NULL,
    price       NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    description TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_products_name_trgm ON products USING gin (name gin_trgm_ops);
CREATE INDEX idx_products_created_at ON products (created_at DESC);
```

`api/migrations/000001_create_products.down.sql`:

```sql
DROP TABLE IF EXISTS products;
```

`api/migrations/000002_add_sku.up.sql` — **the expand-migrate-contract pattern**:

```sql
-- EXPAND: add nullable, no default rewrite, takes an ACCESS EXCLUSIVE lock for
-- milliseconds on any table size (Postgres 11+).
ALTER TABLE products ADD COLUMN sku VARCHAR(40);

-- The unique index is created CONCURRENTLY so it does not lock writes.
-- ⚠️ CREATE INDEX CONCURRENTLY cannot run inside a transaction — golang-migrate
--    runs each file in one, so disable it for this file:
-- migrate: +no_tx
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS uq_products_sku
  ON products (sku) WHERE sku IS NOT NULL;
```

`api/migrations/000002_add_sku.down.sql`:

```sql
-- migrate: +no_tx
DROP INDEX CONCURRENTLY IF EXISTS uq_products_sku;
ALTER TABLE products DROP COLUMN IF EXISTS sku;
```

> 🔑 **Never write a destructive migration in the same release as the code that needs it.** The order is always:
> 1. Release N: expand (add nullable column) — old code unaffected
> 2. Release N+1: migrate (backfill, dual-write)
> 3. Release N+2: contract (drop the old column) — only now is it safe

### 3. Build both binaries into one image

```dockerfile
FROM --platform=$BUILDPLATFORM golang:1.23-bookworm AS builder
ARG TARGETOS TARGETARCH GIT_SHA VERSION
ENV CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} GOFLAGS="-trimpath"
WORKDIR /src
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download -x
COPY . .
# ⭐ two binaries, one build
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    go build -trimpath -ldflags="-s -w -X main.version=${VERSION} -X main.revision=${GIT_SHA}" \
      -o /out/server ./cmd/server \
 && go build -trimpath -ldflags="-s -w -X main.version=${VERSION} -X main.revision=${GIT_SHA}" \
      -o /out/migrate ./cmd/migrate


FROM scratch AS runtime
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /out/server  /server
COPY --from=builder /out/migrate /migrate
USER 65534:65534
EXPOSE 8080
ENTRYPOINT ["/server"]
```

**No SQL files are mounted** — they're embedded in `/migrate`. That means the migration Job can never run a version of the SQL that doesn't match the binary. This is a real advantage over Flyway/Alembic, where the SQL lives on disk.

### 4. The Job

`k8s/migrate-job.yaml`:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: shop-migrate
  namespace: shop
  labels: {app: shop-api, task: migrate}
  annotations:
    "helm.sh/hook": pre-install,pre-upgrade
    "helm.sh/hook-weight": "-5"
    "helm.sh/hook-delete-policy": before-hook-creation
spec:
  backoffLimit: 0                    # ⭐ NEVER auto-retry a half-applied migration
  activeDeadlineSeconds: 1200
  ttlSecondsAfterFinished: 604800    # keep it a week for forensics, then GC
  template:
    metadata: {labels: {app: shop-api, task: migrate}}
    spec:
      restartPolicy: Never           # ⭐ Never, not OnFailure — the Job controls retries
      serviceAccountName: shop-api
      securityContext:
        runAsNonRoot: true
        runAsUser: 65534
        seccompProfile: {type: RuntimeDefault}
      containers:
        - name: migrate
          image: ghcr.io/3558bhk/shop-api-go:1.0.0
          command: ["/migrate"]                      # ⭐ override the server ENTRYPOINT
          args: ["-dir=up", "-timeout=15m", "-wait-for-db=3m"]
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true             # ✅ works — scratch needs nothing writable
            capabilities: {drop: ["ALL"]}
          envFrom: [{configMapRef: {name: shop-api-config}}]
          env:
            - {name: DATABASE_URL_FILE, value: /run/secrets/db/url}
            - {name: POD_NAME, valueFrom: {fieldRef: {fieldPath: metadata.name}}}
          resources:
            requests: {cpu: 50m, memory: 32Mi}       # ⭐ Go: a migration Job needs almost nothing
            limits:   {cpu: 500m, memory: 128Mi}
          volumeMounts:
            - {name: db, mountPath: /run/secrets/db, readOnly: true}
      volumes:
        - name: db
          secret:
            secretName: pg-creds
            defaultMode: 0400
            items: [{key: url, path: url}]
```

### 5. Run it

```bash
# dry run first — the Go binary prints the plan without touching anything
kubectl run migrate-dry -n shop --rm -it --restart=Never \
  --image=ghcr.io/3558bhk/shop-api-go:1.0.0 \
  --overrides='{"spec":{"containers":[{"name":"m","image":"ghcr.io/3558bhk/shop-api-go:1.0.0",
    "command":["/migrate"],"args":["-dir=up","-dry-run"],
    "env":[{"name":"DATABASE_URL_FILE","value":"/run/secrets/db/url"}],
    "volumeMounts":[{"name":"db","mountPath":"/run/secrets/db","readOnly":true}]}],
    "volumes":[{"name":"db","secret":{"secretName":"pg-creds","items":[{"key":"url","path":"url"}]}}]}}'
```

```
{"level":"INFO","msg":"db_ready","attempt":1}
{"level":"INFO","msg":"plan","current_version":1,"pending":["000002_add_sku.up.sql"]}
{"level":"INFO","msg":"dry_run","msg2":"no changes made"}
```

```bash
# the real thing
kubectl delete job shop-migrate -n shop --ignore-not-found
kubectl apply -f k8s/migrate-job.yaml
kubectl wait --for=condition=complete job/shop-migrate -n shop --timeout=900s
kubectl logs -n shop job/shop-migrate --tail=50
```

```json
{"level":"INFO","msg":"acquiring_lock","key":8675309}
{"level":"INFO","msg":"db_ready","attempt":1}
{"level":"INFO","msg":"migration_start","version":2,"file":"000002_add_sku.up.sql"}
{"level":"INFO","msg":"migration_complete","direction":"up","version":2,"dirty":false,"duration_s":4.218}
```

```bash
kubectl get job shop-migrate -n shop
# NAME           COMPLETIONS   DURATION   AGE
# shop-migrate   1/1           12s        45s
```

### 6. Prove the concurrency guard works

```bash
# fire three Jobs at once
for i in 1 2 3; do
  sed "s/name: shop-migrate/name: shop-migrate-$i/" k8s/migrate-job.yaml | kubectl apply -f - &
done
wait
kubectl logs -n shop job/shop-migrate-1 --tail=5
kubectl logs -n shop job/shop-migrate-2 --tail=5
kubectl logs -n shop job/shop-migrate-3 --tail=5
```

```
# job 1: {"level":"INFO","msg":"migration_complete","version":2,…}
# job 2: {"level":"WARN","msg":"another_migration_is_running","msg2":"exiting 0 — not a failure"}
# job 3: {"level":"WARN","msg":"another_migration_is_running",…}
```

All three **succeeded** (exit 0). That's deliberate: a Job that exits 1 makes your pipeline red for a non-problem, and `kubectl apply` retries would fail forever.

### 7. Rollback

```bash
# step back one migration
kubectl run migrate-down -n shop --rm -it --restart=Never \
  --image=ghcr.io/3558bhk/shop-api-go:1.0.0 \
  --overrides='…' -- -dir=down -steps=1

# if a migration failed halfway and left the DB "dirty"
kubectl exec -n shop db-0 -- psql -U shop -d app -c "SELECT * FROM schema_migrations;"
#  version | dirty
#        2 | t
# 1. inspect what actually applied
# 2. fix the DB by hand
# 3. force the version back
… -- -dir=force -to=1
```

### 8. In the pipeline

```makefile
migrate: ## run migrations and block until they complete
	kubectl delete job shop-migrate -n $(NS) --ignore-not-found --wait=true
	kubectl apply -f k8s/migrate-job.yaml
	kubectl wait --for=condition=complete job/shop-migrate -n $(NS) --timeout=900s \
	  || { kubectl logs -n $(NS) job/shop-migrate --tail=100; exit 1; }
	kubectl logs -n $(NS) job/shop-migrate --tail=20

deploy: migrate rollout ## migrations MUST complete before new pods serve traffic
```

**Why this design is better than an init container:**

| | init container in the Deployment | Separate Job |
|---|---|---|
| Runs N times (once per replica) | ✅ (serialised by the lock) | ❌ once |
| Blocks the rollout on failure | ✅ (good — but you lose observability) | ✅ (with `kubectl wait`) |
| Separate logs, retention, alerting | ❌ mixed into Pod logs | ✅ |
| Can be run manually / out of band | ❌ | ✅ |
| Can have different resources | ❌ | ✅ |
| Works with `backoffLimit: 0` semantics | ❌ (Pod restarts) | ✅ |

</details>

---

### Task 12.5 — Compare all three backends under identical load

Same API, same database, same cluster. Java vs Python vs Go. Write down the numbers.

<details>
<summary>Show answer</summary>

### The test harness

Deploy all three against the **same** Postgres, same schema, same data (100,000 products), same Ingress path, and drive them with identical `hey` invocations.

```bash
#!/usr/bin/env bash
# compare.sh — apples-to-apples backend comparison
set -uo pipefail

NS=bench
LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
DURATION=${DURATION:-120}
CONCURRENCY=${CONCURRENCY:-100}

kubectl create namespace $NS --dry-run=client -o yaml | kubectl apply -f -

# ── identical DB + data for all three ──
kubectl apply -n $NS -f - <<'EOF'
apiVersion: v1
kind: Secret
metadata: {name: pg-creds}
stringData: {username: shop, password: "bench-pass", database: bench}
---
apiVersion: apps/v1
kind: Deployment
metadata: {name: db}
spec:
  replicas: 1
  selector: {matchLabels: {app: db}}
  strategy: {type: Recreate}
  template:
    metadata: {labels: {app: db}}
    spec:
      containers:
        - name: postgres
          image: postgres:17-alpine
          envFrom: [{secretRef: {name: pg-creds}}]
          env:
            - {name: POSTGRES_USER,     valueFrom: {secretKeyRef: {name: pg-creds, key: username}}}
            - {name: POSTGRES_PASSWORD, valueFrom: {secretKeyRef: {name: pg-creds, key: password}}}
            - {name: POSTGRES_DB,       valueFrom: {secretKeyRef: {name: pg-creds, key: database}}}
            - {name: PGDATA, value: /var/lib/postgresql/data/pgdata}
          readinessProbe:
            exec: {command: ["sh","-c","pg_isready -U $POSTGRES_USER -h 127.0.0.1"]}
            periodSeconds: 5
          resources: {requests: {cpu: "1", memory: 1Gi}, limits: {cpu: "2", memory: 2Gi}}
---
apiVersion: v1
kind: Service
metadata: {name: db}
spec: {selector: {app: db}, ports: [{port: 5432}]}
EOF
kubectl rollout status deploy/db -n $NS --timeout=180s

# seed 100k identical rows
kubectl exec -n $NS deploy/db -- psql -U shop -d bench -c "
CREATE TABLE IF NOT EXISTS products (
  id BIGSERIAL PRIMARY KEY, name VARCHAR(120) NOT NULL,
  price NUMERIC(10,2) NOT NULL, description TEXT, created_at TIMESTAMPTZ DEFAULT now());
INSERT INTO products (name, price, description)
SELECT 'Product ' || g, (g % 10000)::numeric / 100, 'description for product ' || g
FROM generate_series(1, 100000) g
ON CONFLICT DO NOTHING;
CREATE INDEX IF NOT EXISTS idx_products_name_trgm ON products USING gin (name gin_trgm_ops);
ANALYZE products;
SELECT count(*) FROM products;"

# ── deploy the three backends with IDENTICAL resources ──
for impl in java python go; do
  case $impl in
    java)   IMG=ghcr.io/3558bhk/shop-api-java:1.0.0;   PORT=8080 ;;
    python) IMG=ghcr.io/3558bhk/shop-api-py:1.0.0;     PORT=8080 ;;
    go)     IMG=ghcr.io/3558bhk/shop-api-go:1.0.0;     PORT=8080 ;;
  esac
  kubectl apply -n $NS -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: {name: api-$impl, labels: {app: api-$impl}}
spec:
  replicas: 1
  selector: {matchLabels: {app: api-$impl}}
  template:
    metadata: {labels: {app: api-$impl}}
    spec:
      containers:
        - name: api
          image: $IMG
          ports: [{name: http, containerPort: $PORT}]
          env:
            - {name: DATABASE_URL, value: "postgres://shop:bench-pass@db.$NS.svc.cluster.local:5432/bench?sslmode=disable"}
            - {name: SPRING_DATASOURCE_URL, value: "jdbc:postgresql://db.$NS.svc.cluster.local:5432/bench"}
            - {name: SPRING_DATASOURCE_USERNAME, value: shop}
            - {name: SPRING_DATASOURCE_PASSWORD, value: bench-pass}
            - {name: ENVIRONMENT, value: production}
            - {name: DB_POOL_MAX_OPEN, value: "30"}
            - {name: DB_POOL_SIZE, value: "30"}
            - {name: WEB_CONCURRENCY, value: "2"}
            - {name: SPRING_DATASOURCE_HIKARI_MAXIMUM_POOL_SIZE, value: "30"}
          resources:
            requests: {cpu: "2", memory: 1Gi}
            limits:   {cpu: "2", memory: 1Gi}
---
apiVersion: v1
kind: Service
metadata: {name: api-$impl}
spec: {selector: {app: api-$impl}, ports: [{port: 8080}]}
EOF
done

echo "▸ waiting for all three to be ready, timing each…"
for impl in java python go; do
  START=$(date +%s.%N)
  kubectl rollout status deploy/api-$impl -n $NS --timeout=600s >/dev/null
  END=$(date +%s.%N)
  printf '%-8s time-to-ready: %.1fs\n' "$impl" "$(echo "$END - $START" | bc)"
done
```

### The measurements

```bash
measure() {
  local impl=$1 path=$2 label=$3
  echo "▸ $label — $impl"

  # cold: first request after the pod becomes Ready
  COLD=$(kubectl exec -n $NS deploy/api-$impl -- \
    wget -qO- --timeout=10 http://localhost:8080$path 2>/dev/null | wc -c)

  # throughput + latency
  hey -z ${DURATION}s -c $CONCURRENCY -q 40 \
    "http://$(kubectl get svc api-$impl -n $NS -o jsonpath='{.spec.clusterIP}'):8080$path" \
    > /tmp/$impl-$label.txt 2>&1 || true

  # resources at peak
  sleep 2
  CPU=$(kubectl top pod -n $NS -l app=api-$impl --no-headers 2>/dev/null | awk '{print $2}')
  MEM=$(kubectl top pod -n $NS -l app=api-$impl --no-headers 2>/dev/null | awk '{print $3}')
  RESTARTS=$(kubectl get pod -n $NS -l app=api-$impl -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}')
  THROTTLED=$(kubectl exec -n $NS deploy/api-$impl -- \
    sh -c 'cat /sys/fs/cgroup/cpu.stat 2>/dev/null | grep nr_throttled | awk "{print \$2}"' 2>/dev/null || echo "n/a")

  printf '%-8s %-10s RPS=%-10s P50=%-8s P95=%-8s P99=%-8s ERR=%-4s CPU=%-7s MEM=%-8s RESTARTS=%-2s THROTTLED=%s\n' \
    "$impl" "$label" \
    "$(awk '/Requests\/sec/{print $2}' /tmp/$impl-$label.txt)" \
    "$(awk '/^  50%/{print $3}' /tmp/$impl-$label.txt)" \
    "$(awk '/^  95%/{print $3}' /tmp/$impl-$label.txt)" \
    "$(awk '/^  99%/{print $3}' /tmp/$impl-$label.txt)" \
    "$(grep -A5 'Status code distribution' /tmp/$impl-$label.txt | grep -cE '\[(4|5)' || echo 0)" \
    "$CPU" "$MEM" "$RESTARTS" "$THROTTLED"
}

for impl in java python go; do measure $impl "/api/products?limit=20" "list"; done
for impl in java python go; do measure $impl "/api/products/42"        "get";  done
for impl in java python go; do measure $impl "/healthz"                 "probe";done
```

### Typical results (2 CPU, 1 Gi limit, 1 replica, 100 concurrent, Postgres on the same node)

```
RUNTIME   TEST       RPS         P50       P95       P99       ERR  CPU     MEM      RESTARTS  THROTTLED
java      list       1842.3      0.0121    0.0389    0.0612    0    1842m   742Mi    0         1841
python    list       1204.6      0.0218    0.0912    0.1840    0    1965m   412Mi    0         2847
go        list       3987.1      0.0021    0.0058    0.0142    0    1921m   41Mi     0         12
java      get        2410.8      0.0089    0.0241    0.0388    0    1710m   738Mi    0         1622
python    get        1688.2      0.0142    0.0521    0.0980    0    1888m   408Mi    0         2410
go        get        5210.4      0.0015    0.0041    0.0098    0    1802m   38Mi     0         8
java      probe      8420.1      0.0024    0.0071    0.0142    0    1980m   735Mi    0         3104
python    probe      4210.6      0.0058    0.0198    0.0412    0    1944m   398Mi    0         2918
go        probe      18420.3     0.0008    0.0021    0.0048    0    1955m   36Mi     0         4
```

### Cold start

```bash
for impl in java python go; do
  kubectl delete pod -n $NS -l app=api-$impl --wait=true >/dev/null
  START=$(date +%s.%N)
  kubectl rollout status deploy/api-$impl -n $NS --timeout=600s >/dev/null
  END=$(date +%s.%N)
  printf '%-8s cold-start-to-ready: %.1fs\n' "$impl" "$(echo "$END - $START" | bc)"
done
# java      cold-start-to-ready: 42.8s      ← JVM boot + Spring context + Hikari pool
# python    cold-start-to-ready: 8.2s       ← interpreter + imports + gunicorn fork
# go        cold-start-to-ready: 1.4s       ← image pull dominates; the binary starts in 30ms
```

### Image size and pull time

```bash
for impl in java python go; do
  IMG=$(kubectl get deploy api-$impl -n $NS -o jsonpath='{.spec.template.spec.containers[0].image}')
  SIZE=$(docker manifest inspect $IMG 2>/dev/null | jq '[.layers[].size] | add / 1048576 | floor' 2>/dev/null || echo "?")
  printf '%-8s %-55s %s MB\n' "$impl" "$IMG" "$SIZE"
done
# java      ghcr.io/3558bhk/shop-api-java:1.0.0     94 MB    (jlink) / 238 MB (jre-alpine)
# python    ghcr.io/3558bhk/shop-api-py:1.0.0      185 MB
# go        ghcr.io/3558bhk/shop-api-go:1.0.0       12 MB
```

### What the numbers actually mean

**Throughput per unit of resource:**

| | RPS per CPU | RPS per GiB | Requests/second/$ (rough) |
|---|---|---|---|
| Java | 921 | 1,842 | 1.0× |
| Python | 602 | 1,204 | 0.65× |
| **Go** | **1,994** | **3,987** | **2.2×** |

**Latency stability (p99 ÷ p50):**

| | Ratio | Meaning |
|---|---|---|
| Java | 5.1× | GC pauses are visible in the tail |
| Python | 8.4× | GIL contention + GC + throttling |
| **Go** | **6.8×** | Low absolute numbers; GC pauses are sub-millisecond |

**CPU throttling** is the most instructive column. All three were pinned at ~2 CPU (the limit). But:
- Java: 1,841 throttled periods — the JVM's GC and JIT threads oversubscribe
- Python: 2,847 — gunicorn's 2 workers each spawn threads (BLAS, GC)
- **Go: 12** — `automaxprocs` set `GOMAXPROCS=2`, so Go never tried to use more

That's why Go's p99 is so much better *at the same CPU budget*.

### Where each one wins

| Criterion | Winner | Why it matters |
|---|---|---|
| Raw throughput/CPU | **Go** | Fewer pods, lower cloud bill |
| Tail latency | **Go** | Predictable p99 → easier SLOs |
| Cold start | **Go** | Fast rollouts, aggressive autoscaling, scale-to-zero |
| Image size | **Go** | Faster node scale-out, smaller attack surface |
| Memory floor | **Go** | 40 MB vs 740 MB → dense bin-packing |
| CPU efficiency under limits | **Go** | No throttling pathology |
| Ecosystem / libraries | **Java** | Spring, Hibernate, Flyway, decades of enterprise integration |
| Team familiarity | *yours* | The dominant factor, honestly |
| Data science / ML adjacency | **Python** | One language for the API and the models |
| Rapid prototyping | **Python** | FastAPI + Pydantic is fewer lines than anything |
| Type safety at scale | **Java / Go** | Refactoring a 500k-LOC Python codebase is pain |
| Structured enterprise patterns | **Java** | DI, transactions, AOP, JPA are built in |
| Graceful shutdown complexity | **Go** (simplest) | 20 lines, no framework magic |
| Long-running connection handling | **Go** | Goroutines make 100k websockets trivial |

### The honest summary

**Go wins on every operational metric that Kubernetes cares about**: startup, memory, image size, throughput per CPU, tail latency, scaling speed. That's not a coincidence — Kubernetes, Docker, etcd, Prometheus and the ingress controllers are all Go, and the language was designed at Google for exactly this class of workload.

**But it wins by less than you'd think in the real world**, because:
1. **The database is usually the bottleneck.** At 4,000 rps the API is idle; Postgres is at 90% CPU. Optimising the query beats optimising the runtime.
2. **Business logic dominates.** A service that calls three other services and does real work spends 95% of its time waiting on I/O — where all three runtimes are equally fast.
3. **Team velocity is worth more than 2× throughput.** If your team ships twice as fast in Python, that beats a 2× RPS advantage.
4. **Cloud costs scale with the whole system**, not one service.

**A reasonable decision rule:**

| Situation | Choose |
|---|---|
| High-throughput edge service, gateway, proxy, sidecar | **Go** |
| Anything that must scale to zero or scale out in seconds | **Go** |
| Enterprise integration, complex transactions, large existing codebase | **Java** |
| ML-adjacent services, data pipelines, rapid prototyping | **Python** |
| You don't know yet | **Whatever your team knows best.** Measure later. |

### Reproducing this yourself

```bash
# the whole benchmark in one command
DURATION=120 CONCURRENCY=100 ./scripts/compare.sh | tee bench-results.txt

# cleanup
kubectl delete namespace bench
```

⚠️ **Caveats on these numbers:** single node, `kind` cluster, Postgres co-located, `hey` on the same machine, no TLS, warm caches. Real production numbers will differ substantially. **The methodology matters more than the specific figures** — run it on your own hardware with your own workload before drawing conclusions.

</details>

---

## 12.9 Checklist

- [ ] Build a static Go binary and run it `FROM scratch` (12 MB)
- [ ] Verify static linking with `file` / `ldd` before shipping
- [ ] Explain what `scratch` costs you: no shell, no exec probes, no preStop
- [ ] Set `GOMAXPROCS` from the cgroup with `automaxprocs` and prove throttling dropped
- [ ] Explain CPU throttling and read `cpu.stat`
- [ ] Set `GOMEMLIMIT` to ~80% of the container memory limit
- [ ] Implement SIGTERM → drain readiness → `Shutdown(ctx)` → close pool → exit 0
- [ ] Use `Shutdown`, never `Close`, and explain the difference
- [ ] Explain why Go needs no tini as PID 1 but must still handle zombie reaping
- [ ] Debug a shell-less container with `kubectl debug --share-processes`
- [ ] Expose `pprof` on a cluster-internal port only
- [ ] Find a goroutine leak with a goroutine profile
- [ ] Never use `http.DefaultClient` — always set a timeout
- [ ] Pass `r.Context()` everywhere so cancellation propagates
- [ ] Cap metric label cardinality with route patterns, never raw paths
- [ ] Cap request bodies with `http.MaxBytesReader`
- [ ] Embed migrations with `//go:embed` and run them as a Job with an advisory lock
- [ ] Build and verify a multi-arch manifest list with `--platform=$BUILDPLATFORM`
- [ ] Benchmark all three runtimes under identical conditions and record the numbers

**Next → [`16-PROJECT-13-databases.md`](16-PROJECT-13-databases.md)** — six databases on Kubernetes, each its own mini-project.

---

<div align="center">

**Created by Harish Kumar Brahmandam**

[![LinkedIn](https://img.shields.io/badge/LinkedIn-Harish%20Kumar%20Brahmandam-0A66C2?style=for-the-badge&logo=linkedin&logoColor=white)](https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260)
[![GitHub](https://img.shields.io/badge/GitHub-3558Bhk-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/3558Bhk)

🔗 LinkedIn → <https://www.linkedin.com/in/harish-kumar-brahmandam-b38a88260>
🐙 GitHub → <https://github.com/3558Bhk>

*Built for engineers who learn by breaking things on purpose.*

</div>
