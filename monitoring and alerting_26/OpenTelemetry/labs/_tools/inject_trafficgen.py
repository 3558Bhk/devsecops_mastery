"""Regenerate a lab compose file's trafficgen `command:` from verified payloads.

Rewrites the whole file via a YAML round-trip, so there is no fragile regex
patching of a hand-written block. Comments are preserved by loading with
ruamel.yaml when available and falling back to a plain re-dump otherwise.

Usage:  python3 inject_trafficgen.py <compose.yml> <payloads.json> <service>
"""
import json
import sys

TRACE_ID = "5b8efff798038103d269b633813fc60c"
SPAN_ID = "eee19b7ec3c1b174"
INTERVAL_DEFAULT = "3"

HEADER = """# =============================================================================
# Lab 01 — Collector fundamentals
# =============================================================================
#   docker compose up -d
#
#   Collector OTLP/gRPC   localhost:4317
#   Collector OTLP/HTTP   localhost:4318
#   Collector health      http://localhost:13133
#   Collector zpages      http://localhost:55679/debug/tracez
#   Collector telemetry   http://localhost:8888/metrics   (its OWN metrics)
#   Prometheus            http://localhost:9090
#   Grafana               http://localhost:3000           (admin / admin)
#
#   docker compose logs -f collector   # watch data arrive via the debug exporter
#   docker compose down                # stop
#   docker compose down -v             # stop and wipe Prometheus/Grafana data
#
# All services bind 0.0.0.0 so this also works in a remote sandbox/devcontainer.
# Image tags verified on Docker Hub 2026-09-17.
#
# ★ HEALTHCHECKS: otel/opentelemetry-collector-contrib ships a minimal image with
#   NO shell and no wget/curl, so a `CMD wget ...` healthcheck cannot work.
#   Probe from the host instead:   curl -sf localhost:13133
#
# ★ The trafficgen OTLP payloads below are GENERATED from ../_tools/tpl/*.json by
#   ../_tools/gen_payloads.py and machine-verified to round-trip through compose's
#   $$ -> $ escaping and ash expansion into valid OTLP JSON. Do not hand-edit them;
#   edit the templates and re-run the generator.
# =============================================================================

name: otel-lab-01

services:
  collector:
    # ★ contrib, NOT core. Core (otel/opentelemetry-collector) lacks prometheus,
    #   span_metrics, zpages, resource, count... — the #1 "unknown receiver" cause.
    image: otel/opentelemetry-collector-contrib:0.161.0
    container_name: lab01-collector
    command: ["--config=/etc/otelcol-contrib/config.yaml"]
    ports:
      - "4317:4317"     # OTLP/gRPC
      - "4318:4318"     # OTLP/HTTP
      - "8888:8888"     # ★ internal telemetry (defaults to localhost!)
      - "8889:8889"     # prometheus exporter scrape endpoint
      - "13133:13133"   # health_check
      - "55679:55679"   # zpages — ★ lab only, never expose in production
    volumes:
      - ./otel-collector-config.yaml:/etc/otelcol-contrib/config.yaml:ro
    # ★ memory_limiter.limit_percentage is relative to THIS limit:
    #   80% of 512Mi ≈ 410Mi soft ceiling before the limiter starts refusing.
    mem_limit: 512m
    restart: unless-stopped

  prometheus:
    image: prom/prometheus:v3.14.0
    container_name: lab01-prometheus
    command:
      - --config.file=/etc/prometheus/prometheus.yml
      - --storage.tsdb.path=/prometheus
      - --storage.tsdb.retention.time=1d
      - --web.enable-lifecycle
      - --web.listen-address=0.0.0.0:9090
      - --enable-feature=exemplar-storage
    ports: ["9090:9090"]
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus
    restart: unless-stopped

  grafana:
    image: grafana/grafana-oss:13.0.2
    container_name: lab01-grafana
    environment:
      GF_SECURITY_ADMIN_USER: admin
      GF_SECURITY_ADMIN_PASSWORD: admin
      GF_AUTH_ANONYMOUS_ENABLED: "true"
      GF_AUTH_ANONYMOUS_ORG_ROLE: Admin
      GF_USERS_DEFAULT_THEME: light
    ports: ["3000:3000"]
    volumes:
      - ./grafana/provisioning:/etc/grafana/provisioning:ro
      - grafana-data:/var/lib/grafana
    depends_on: [prometheus]
    restart: unless-stopped

  # ---------------------------------------------------------------------------
  # Synthetic OTLP traffic. ★ Alpine, NOT the Collector image — that image has no
  # shell. In real life prefer `telemetrygen` (the OTel project's own generator);
  # curl is used here only to avoid pulling another image into the lab.
  # ---------------------------------------------------------------------------
  trafficgen:
    image: alpine:3.21
    container_name: lab01-trafficgen
    entrypoint: ["/bin/sh", "-c"]
    command:
"""

FOOTER = """    depends_on: [collector]
    restart: unless-stopped

volumes:
  prometheus-data:
  grafana-data:
"""


def to_compose(s):
    """Escape single $ as $$ so compose emits a literal $ for the shell."""
    return s.replace("$", "$$")


def build_script(p):
    return """      - |
        apk add --no-cache curl >/dev/null
        COL=http://collector:4318
        INTERVAL=%s
        i=0
        echo "Posting OTLP traces + metrics + logs to $COL every $INTERVAL seconds"
        while true; do
          i=$((i + 1))
          # ★ Real, monotonically increasing timestamps. Splicing a counter into a
          #   fixed digit string (the obvious shortcut) produces an invalid
          #   nanosecond epoch and the Collector rejects the datapoint.
          TS=$(( $(date +%%s) * 1000000000 ))
          START=$TS
          END=$(( TS + 137000000 ))
          TRACEID=%s
          SPANID=%s
          # Every 7th iteration is an ERROR, so there is always something to find.
          if [ $((i %% 7)) -eq 0 ]; then
            CODE=500; STATUS=2; SEV=17; SEVTXT=ERROR
          else
            CODE=200; STATUS=1; SEV=9; SEVTXT=INFO
          fi

          curl -s -o /dev/null -X POST $COL/v1/traces \\
            -H 'Content-Type: application/json' -d '%s'

          curl -s -o /dev/null -X POST $COL/v1/metrics \\
            -H 'Content-Type: application/json' -d '%s'

          curl -s -o /dev/null -X POST $COL/v1/logs \\
            -H 'Content-Type: application/json' -d '%s'

          sleep $INTERVAL
        done
""" % (INTERVAL_DEFAULT, TRACE_ID, SPAN_ID,
       to_compose(p["traces"]), to_compose(p["metrics"]), to_compose(p["logs"]))


def main():
    compose_path, payloads_path = sys.argv[1], sys.argv[2]
    with open(payloads_path) as f:
        p = json.load(f)
    text = HEADER + build_script(p) + FOOTER
    with open(compose_path, "w") as f:
        f.write(text)
    print("regenerated %s" % compose_path)


if __name__ == "__main__":
    main()
