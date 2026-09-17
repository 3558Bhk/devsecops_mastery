"""
Lab demo service.

Endpoints
---------
GET  /               -> normal request (recorded as path="/")
GET  /health         -> liveness probe
GET  /orders         -> a "business" endpoint (recorded as path="/orders")
GET  /slow           -> forces a slow response (LATENCY_MS * 8)
GET  /fail           -> forces a 500 response
GET  /metrics        -> Prometheus exposition format

Environment
-----------
FAILURE_RATE  probability that a normal request returns 500   (default 0.0)
LATENCY_MS    artificial latency added to normal requests     (default 20)

Deliberate teaching points / flaws to find in Lab 3
---------------------------------------------------
1. Histogram buckets are the client_golang/prometheus_client DEFAULTS
   (0.005 .. 10). They are far too coarse around a 300ms SLO — fix them.
2. `RAW_PATH_ENABLED=1` switches the `path` label to the raw URL path, which
   explodes cardinality when you hit /orders/<random>. Do not do this in prod.
"""
import os
import random
import time
import uuid

from flask import Flask, Response, jsonify, request
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Gauge,
    Histogram,
    Info,
    generate_latest,
)

FAILURE_RATE = float(os.environ.get("FAILURE_RATE", "0.0"))
LATENCY_MS = int(os.environ.get("LATENCY_MS", "20"))
RAW_PATH_ENABLED = os.environ.get("RAW_PATH_ENABLED", "0") == "1"

app = Flask(__name__)

# --------------------------------------------------------------------------
# Metrics
# --------------------------------------------------------------------------
REQUESTS = Counter(
    "http_requests_total",
    "Total HTTP requests served by the demo app.",
    ["method", "path", "status"],
)

# FLAW #1: default buckets. Replace with something aligned to your SLO:
#   buckets=(0.01, 0.05, 0.1, 0.2, 0.3, 0.4, 0.5, 1.0, 2.5, 5.0)
LATENCY = Histogram(
    "http_request_duration_seconds",
    "Request latency in seconds.",
    ["method", "path"],
)

IN_FLIGHT = Gauge("http_requests_in_flight", "Requests currently being served.")
FAILURES_FORCED = Counter("demo_forced_failures_total", "Requests failed on purpose via /fail.")
BUILD = Info("demo_build", "Build metadata for the demo app.")
BUILD.info(
    {
        "version": os.environ.get("APP_VERSION", "0.1.0"),
        "revision": os.environ.get("APP_REVISION", "lab"),
    }
)


def route_label(path: str) -> str:
    """Normalise the path to a route template so cardinality stays bounded."""
    if RAW_PATH_ENABLED:  # FLAW #2 — cardinality bomb
        return path
    if path.startswith("/orders/"):
        return "/orders/:id"
    return path


# --------------------------------------------------------------------------
# Instrumentation
# --------------------------------------------------------------------------
@app.before_request
def _before():
    request._start = time.perf_counter()
    IN_FLIGHT.inc()


@app.after_request
def _after(response):
    IN_FLIGHT.dec()
    path = route_label(request.path)
    REQUESTS.labels(request.method, path, response.status_code).inc()
    LATENCY.labels(request.method, path).observe(time.perf_counter() - request._start)
    return response


def _simulate_work(multiplier: float = 1.0):
    time.sleep((LATENCY_MS / 1000.0) * multiplier)
    if random.random() < FAILURE_RATE:
        return jsonify({"error": "synthetic upstream failure"}), 500
    return None


# --------------------------------------------------------------------------
# Routes
# --------------------------------------------------------------------------
@app.get("/")
def index():
    failure = _simulate_work()
    if failure:
        return failure
    return jsonify({"ok": True, "service": "demo-app"})


@app.get("/health")
def health():
    return Response("ok\n", mimetype="text/plain")


@app.get("/orders")
def orders():
    failure = _simulate_work()
    if failure:
        return failure
    return jsonify({"orders": [{"id": str(uuid.uuid4()), "total": 1299} for _ in range(3)]})


@app.get("/orders/<order_id>")
def order(order_id):
    failure = _simulate_work()
    if failure:
        return failure
    return jsonify({"id": order_id, "total": 1299, "status": "paid"})


@app.get("/slow")
def slow():
    time.sleep((LATENCY_MS / 1000.0) * 8)
    return jsonify({"ok": True, "slow": True})


@app.get("/fail")
def fail():
    FAILURES_FORCED.inc()
    return jsonify({"error": "forced failure"}), 500


@app.get("/metrics")
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000, threaded=True)
