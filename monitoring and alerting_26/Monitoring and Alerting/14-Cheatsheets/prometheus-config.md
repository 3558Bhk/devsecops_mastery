# Cheatsheet · Prometheus configuration

## Minimal `prometheus.yml`

```yaml
global:
  scrape_interval: 15s
  scrape_timeout: 10s        # must be <= scrape_interval
  evaluation_interval: 15s
  external_labels:
    cluster: prod-1
    replica: prom-0

rule_files:
  - /etc/prometheus/rules/*.yaml

alerting:
  alertmanagers:
    - static_configs: [{targets: ['alertmanager:9093']}]
      timeout: 10s
      api_version: v2

scrape_configs:
  - job_name: prometheus
    static_configs: [{targets: ['localhost:9090']}]

remote_write:
  - url: https://mimir.example.com/api/v1/push
```

## Per-scrape-config options

| Key | Purpose |
|---|---|
| `job_name` | **Required.** Becomes the `job` label |
| `scrape_interval` / `scrape_timeout` | Override global |
| `metrics_path` | Default `/metrics`; `/probe` for blackbox, `/federate` for federation |
| `params` | URL query params, e.g. `module: [http_2xx]` |
| `scheme` | `http` (default) / `https` |
| `honor_labels` | Keep the target's own `job`/`instance` instead of overwriting (use for federation & Pushgateway) |
| `honor_timestamps` | Accept the target's timestamps |
| `basic_auth` / `authorization` / `bearer_token_file` / `tls_config` / `oauth2` / `proxy_url` | Auth & transport |
| `static_configs` / `*_sd_configs` / `file_sd_configs` | Target discovery |
| `relabel_configs` | **Pre-scrape**: filter/relabel targets |
| `metric_relabel_configs` | **Post-scrape**: filter/relabel samples — your cardinality weapon |
| `sample_limit` | Refuse a scrape that returns more samples (protects you) |
| `target_limit` | Max targets from this config |
| `label_limit` / `label_name_length_limit` / `label_value_length_limit` | Cardinality guardrails |
| `body_size_limit` | Max response body |
| `native_histograms_bucket_limit` | Cap native histogram buckets |
| `keep_dropped_targets` | How many dropped targets to keep visible for debugging (Prometheus 3) |

## Relabeling

**Actions:** `replace` (default) · `keep` · `drop` · `hashmod` · `labelmap` · `labeldrop` · `labelkeep` · `lowercase` · `uppercase` · `keepequal` · `dropequal`

**Fields:** `source_labels` · `separator` (default `;`) · `target_label` · `regex` (default `(.*)`, fully anchored) · `modulus` · `replacement` (default `$1`) · `action`

```yaml
relabel_configs:
  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
    action: keep
    regex: "true"
  - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_name]
    target_label: app
  - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
    action: replace
    regex: ([^:]+)(?::\d+)?;(\d+)
    replacement: $1:$2
    target_label: __address__
  - source_labels: [__meta_kubernetes_namespace]
    target_label: namespace
  - regex: meta_(.+)
    action: labelmap
    replacement: $1
  - regex: 'pod_template_hash|controller_revision_hash'
    action: labeldrop

metric_relabel_configs:
  - source_labels: [__name__]
    action: drop
    regex: 'go_gc_.*|go_memstats_.*|container_blkio_.*'
  - action: labeldrop
    regex: 'id|uid|image_id|container_id'
  - source_labels: [path]
    action: replace
    regex: '/users/\d+'
    replacement: '/users/:id'
    target_label: path
```

**Meta labels available before scraping:** `__address__` · `__scheme__` · `__metrics_path__` · `__scrape_interval__` · `__scrape_timeout__` · `__param_<name>` · `__meta_<sd>_<...>`. All `__`-prefixed labels are **discarded** after relabeling.

## Blackbox probe pattern (memorise this)

```yaml
- job_name: blackbox-http
  metrics_path: /probe
  params: {module: [http_2xx]}
  static_configs:
    - targets: ['https://example.com/healthz']
  relabel_configs:
    - source_labels: [__address__]
      target_label: __param_target
    - source_labels: [__param_target]
      target_label: instance
    - target_label: __address__
      replacement: blackbox-exporter:9115
```

## Federation pattern

```yaml
- job_name: federate
  scrape_interval: 60s
  honor_labels: true
  metrics_path: /federate
  params:
    'match[]':
      - '{job="node"}'
      - '{__name__=~".+:.+"}'      # recording rules only
  static_configs: [{targets: ['prometheus-edge:9090']}]
```

## Service discovery keys

`static_configs` · `file_sd_configs` · `kubernetes_sd_configs` (`role: node|pod|service|endpoints|endpointslice|ingress`) · `ec2_sd_configs` · `azure_sd_configs` · `gce_sd_configs` · `consul_sd_configs` · `dns_sd_configs` · `eureka_sd_configs` · `openstack_sd_configs` · `hetzner_sd_configs` · `digitalocean_sd_configs` · `linode_sd_configs` · `docker_sd_configs` · `docker_swarm_sd_configs` · `uyuni_sd_configs` · `ionos_sd_configs` · `vultr_sd_configs` · `ovhcloud_sd_configs` · `scaleway_sd_configs` · `puppetdb_sd_configs` · `lightsail_sd_configs`

```yaml
file_sd_configs:
  - files: ['/etc/prometheus/targets/*.json', '/etc/prometheus/targets/*.yml']
    refresh_interval: 30s
```

## CLI flags

```bash
--config.file=/etc/prometheus/prometheus.yml
--storage.tsdb.path=/prometheus
--storage.tsdb.retention.time=15d          # default
--storage.tsdb.retention.size=80GB         # set BOTH
--storage.tsdb.wal-compression=true
--storage.tsdb.no-lockfile=false
--storage.tsdb.max-block-chunk-segment-size=512
--storage.exemplars.exemplars-limit=100000
--web.listen-address=0.0.0.0:9090
--web.external-url=https://prom.example.com
--web.route-prefix=/
--web.enable-lifecycle                     # POST /-/reload
--web.enable-admin-api                     # snapshots, delete_series
--web.enable-remote-write-receiver         # accept inbound remote_write
--web.enable-otlp-receiver                 # accept OTLP at /api/v1/otlp/v1/metrics
--web.config.file=/etc/prometheus/web.yml  # TLS + basic auth for the web endpoint
--query.log-file=/var/log/prometheus/queries.log
--query.max-concurrency=20
--query.timeout=2m
--query.max-samples=50000000
--query.lookback-delta=5m
--enable-feature=native-histograms
--enable-feature=exemplar-storage
--enable-feature=auto-gomemlimit
--enable-feature=expand-external-labels
--agent.mode                               # scrape + remote_write only
--log.level=info|debug
--log.format=logfmt|json
```

## `web.yml` — TLS & basic auth for the Prometheus endpoint

```yaml
basic_auth_users:
  prom: $2y$10$...bcrypt-hash...     # htpasswd -nBC 10 "" | tr -d ':\n'
tls_server_config:
  cert_file: /etc/prometheus/tls/tls.crt
  key_file: /etc/prometheus/tls/tls.key
  client_auth_type: RequireAndVerifyClientCert   # optional mTLS
  client_ca_file: /etc/prometheus/tls/ca.crt
```
```bash
promtool tsdb create-blocks-from ... ; promtool check web-config web.yml
```

## `otlp:` block (Prometheus 3)

```yaml
otlp:
  translation_strategy: NoUTF8EscapingWithSuffixes
  # UnderscoreEscapingWithSuffixes (default) | UnderscoreEscapingWithoutSuffixes
  # | NoUTF8EscapingWithSuffixes | NoTranslation
  promote_resource_attributes:
    - service.name
    - service.namespace
    - service.version
    - deployment.environment
    - k8s.cluster.name
    - k8s.namespace.name
    - k8s.pod.name
  keep_identifying_resource_attributes: false
```

## `remote_write` tuning

```yaml
remote_write:
  - url: ...
    send_native_histograms: true
    metadata_config: {send: true, send_interval: 1m}
    queue_config:
      capacity: 10000
      max_shards: 50
      min_shards: 1
      max_samples_per_send: 2000
      batch_send_deadline: 5s
      min_backoff: 30ms
      max_backoff: 5s
    write_relabel_configs: [ ... ]
```
Watch: `prometheus_remote_storage_samples_pending`, `..._shards`, `rate(..._samples_dropped_total[5m])`, `rate(..._samples_failed_total[5m])`.

## HTTP API

```bash
GET/POST /api/v1/query?query=&time=
GET/POST /api/v1/query_range?query=&start=&end=&step=
GET /api/v1/query_exemplars?query=&start=&end=
GET /api/v1/series?match[]=&start=&end=
GET /api/v1/labels   /  /api/v1/label/<name>/values
GET /api/v1/targets?state=active|dropped|any
GET /api/v1/rules?type=alert|record
GET /api/v1/alerts   /  /api/v1/alertmanagers
GET /api/v1/metadata  /  /api/v1/scan_for_updates
GET /api/v1/status/config|flags|runtimeinfo|buildinfo|tsdb|walreplay
GET /federate?match[]={...}
POST /api/v1/admin/tsdb/snapshot            (needs --web.enable-admin-api)
POST /api/v1/admin/tsdb/delete_series?match[]=x&start=&end=
POST /api/v1/admin/tsdb/clean_tombstones
POST /-/reload   /-/quit                    (reload needs --web.enable-lifecycle)
GET  /-/healthy  /-/ready
```

## Sizing maths

```
samples/sec  = active_series / scrape_interval
disk         ≈ samples/sec × retention_seconds × ~1.5 bytes
head RAM     ≈ active_series × 1–3 KB   (+3–8 GB total for queries/GC)
chunks       = samples/sec × 7200       (2h block)
```

## Validation (put these in CI)

```bash
promtool check config prometheus.yml
promtool check rules rules/*.yaml
promtool check metrics metrics.txt          # lint an exposition-format file
promtool check web-config web.yml
promtool check service-discovery prometheus.yml <job-name>
promtool test rules tests/*.yaml
promtool query instant http://localhost:9090 'up'
promtool tsdb analyze /prometheus
promtool tsdb list /prometheus
promtool tsdb create-blocks-from openmetrics in.txt out/
```
