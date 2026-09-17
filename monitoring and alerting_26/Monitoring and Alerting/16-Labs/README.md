# 16 · Labs

**Level:** hands-on · **Time:** ~8 h across six labs · **Goal:** break things on purpose until the whole pipeline is muscle memory.

This folder is a complete, self-contained monitoring stack you can run with one command, plus six guided labs that map onto the deep-dive topics.

---

## What's in here

```
16-Labs/
├── README.md                  ← this file (6 guided labs)
├── docker-compose.yml         Prometheus 3.14 · Alertmanager 0.34 · node_exporter · blackbox · Grafana 13 · demo app · webhook sink
├── prometheus.yml             scrape configs incl. blackbox probing + relabeling exercises
├── alertmanager.yml           routing tree, inhibition, time_intervals, receivers (webhook-based, no credentials needed)
├── blackbox.yml               http_2xx / tcp_connect / dns / icmp / grpc modules
├── rules/
│   └── lab.yaml               recording rules + the alerts the labs trigger
├── templates/
│   └── base.tmpl              Slack / email / PagerDuty / plain-text notification templates
├── app/                       a tiny Flask service that exports RED metrics — and can be told to fail or slow down
│   ├── app.py
│   ├── requirements.txt
│   └── Dockerfile
├── grafana/
│   ├── provisioning/          data source + dashboard provider (config as code)
│   └── dashboards/            lab-service.json (RED+SLO) · lab-targets.json (Prometheus internals)
└── JOURNAL.md                 ← create this; one line per session (see 00-Start-Here)
```

## Quick start

```bash
cd "Monitoring and Alerting/16-Labs"
docker compose up -d --build

# wait ~30s for the demo app and Grafana provisioning
docker compose ps
```

| URL | What |
|---|---|
| http://localhost:9090 | Prometheus (Status → Targets, Rules, Alerts, TSDB Status) |
| http://localhost:9093 | Alertmanager (Alerts, Silences, Status → cluster) |
| http://localhost:3000 | Grafana (`admin` / `admin`; anonymous viewer also enabled) → folder **Labs** |
| http://localhost:8000/metrics | The demo app's metrics |
| http://localhost:8000/fail | Force a 500 |
| http://localhost:8000/slow | Force a slow response |
| http://localhost:5001 | Webhook sink (httpbin) — see the rendered notification payloads |
| http://localhost:9115 | blackbox_exporter UI (probe tester) |

Generate traffic (any of these):
```bash
# simple loop
while true; do curl -s -o /dev/null http://localhost:8000/orders; curl -s -o /dev/null http://localhost:8000/; sleep 0.2; done

# better: install hey or wrk
hey -z 5m -c 10 -q 5 http://localhost:8000/orders
```

Useful commands:
```bash
docker compose logs -f prometheus
docker compose logs -f alertmanager
docker compose restart alertmanager           # reload after editing alertmanager.yml
curl -XPOST localhost:9090/-/reload           # reload Prometheus after editing prometheus.yml
docker compose down                           # stop (keeps data)
docker compose down -v                        # stop and wipe all TSDB/Grafana data
```

**Validate before every change** (this habit is the point of the exercise):
```bash
promtool check config prometheus.yml
promtool check rules rules/*.yaml
amtool check-config alertmanager.yml
```

---

# Lab 1 — Bring it up, find the data (topic 02)

**Goal:** understand the scrape pipeline and where a sample can be dropped.

1. Open **Prometheus → Status → Targets**. Every target should be `UP`. Note the columns: `Endpoint`, `State`, `Labels`, `Last Scrape`, `Scrape Duration`, `Error`.
2. Query in the Prometheus expression browser:
   ```promql
   up
   count by (job) (up)
   rate(http_requests_total[5m])
   histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))
   topk(10, count by (__name__)({__name__=~".+"}))
   prometheus_tsdb_head_series
   ```
3. **Kill a target and watch the pipeline react:**
   ```bash
   docker compose stop node-exporter
   ```
   - Query `up{job="node"}` → `0` within one scrape interval.
   - Status → Targets → the node target turns red with a connection error.
   - Wait ~1 min: the `TargetDown` alert in Prometheus → Alerts goes `PENDING` → `FIRING`.
   - Start it back: `docker compose start node-exporter`, and watch the alert resolve.
4. **Prove the relabeling stage exists.** In `prometheus.yml`, uncomment the `relabel_configs` block on the `demo-app` job that keeps only `env="prod"`. Reload (`curl -XPOST localhost:9090/-/reload`). The target disappears — because `env` is `dev`. Add `env: prod` to the target's labels, reload, and it returns. This is how 90% of "missing target" incidents happen.
5. Run `promtool tsdb analyze` inside the container:
   ```bash
   docker compose exec prometheus promtool tsdb analyze /prometheus
   ```
   Read the "Top 10 series count by metric/label" sections. That output is your cardinality report.

**Done when:** you can explain, out loud, the seven steps a sample takes from service discovery to disk, and name the two stages where it can be dropped.

---

# Lab 2 — Instrumentation and PromQL (topics 03, 04)

**Goal:** read the app's metrics, write real queries, and fix a deliberately bad histogram.

1. `curl -s localhost:8000/metrics | head -60`. Identify: counters (`_total`), gauges, the histogram (`_bucket`/`_sum`/`_count`), the info metric (`demo_build_info`).
2. Generate 5 minutes of traffic with `hey`, then compute in Grafana Explore:
   ```promql
   sum(rate(http_requests_total{job="demo-app"}[$__rate_interval]))                       # QPS
   sum by (status) (rate(http_requests_total{job="demo-app"}[$__rate_interval]))           # by status
   sum by (path) (rate(http_requests_total{job="demo-app"}[$__rate_interval]))             # by path
   histogram_quantile(0.99, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))  # p99
   sum(rate(http_request_duration_seconds_sum[5m])) / sum(rate(http_request_duration_seconds_count[5m]))  # mean
   ```
3. **Find the histogram flaw.** Look at the `le` values in `/metrics` — they're the library defaults (`0.005 … 10`). Set `LATENCY_MS=1200` on `demo-app` in `docker-compose.yml`, restart, and hit `/slow`. Now compute p99: it will land on a coarse bucket boundary and be a poor estimate. **Fix it** in `app/app.py` by passing SLO-aligned buckets:
   ```python
   LATENCY = Histogram(..., buckets=(0.01, 0.05, 0.1, 0.2, 0.3, 0.4, 0.5, 1.0, 2.5, 5.0))
   ```
   Rebuild (`docker compose up -d --build demo-app`), regenerate load, and compare the p99 estimate before/after. **This is the single most instructive 5 minutes in the whole course.**
4. **Trigger the cardinality bomb on purpose.** In `app.py`, `RAW_PATH_ENABLED=1` switches the `path` label to the raw URL. Add `RAW_PATH_ENABLED: "1"` to the app's environment, then:
   ```bash
   for i in $(seq 1 500); do curl -s -o /dev/null "http://localhost:8000/orders/$RANDOM$i"; done
   ```
   Watch `prometheus_tsdb_head_series` climb, and `topk(5, count by (__name__)({__name__=~".+"}))` show `http_requests_total` exploding. Then turn it off and confirm that normalising `/orders/:id` keeps it flat.
5. Practise the trickier PromQL from topic 04: `< bool`, `and`/`unless`, `offset 1d`, `predict_linear`, `absent`, `changes`, `label_replace`.

**Done when:** you have measured the difference a histogram bucket change makes, and you have personally caused (and fixed) a cardinality explosion.

---

# Lab 3 — Alert rules, states and testing (topic 05)

**Goal:** watch the alert state machine, and prove your rules work before they page you.

1. Open **Prometheus → Alerts**. Find `HighErrorRatio`. Note its state and the `for:` remaining.
2. Make it fire:
   ```bash
   docker compose stop demo-app
   # edit docker-compose.yml: FAILURE_RATE: "0.35"
   docker compose up -d demo-app
   hey -z 10m -c 5 -q 5 http://localhost:8000/orders &
   ```
   Watch `INACTIVE → PENDING → FIRING` in the UI and correlate with the dashboard panel crossing the red threshold.
3. **Prove `for:` matters.** Change `for: 2m` to `for: 0m` in `rules/lab.yaml`, reload, and repeat. Notice how much noisier it is.
4. **Prove the traffic guard matters.** Stop the load generator but leave `FAILURE_RATE` high. The alert should *not* fire (error ratio is high but `job:http_requests:rate5m > 0.1` fails). Remove the guard and watch it fire on a trickle of traffic — which is exactly the 3 a.m. page you don't want.
5. **Prove `keep_firing_for:` matters.** Set `FAILURE_RATE` back to `0` and watch the alert resolve slowly (2 min) rather than instantly.
6. **Write a unit test.** Copy [`../13-Alert-Rules-Library/tests/example_test.yaml`](../13-Alert-Rules-Library/tests/example_test.yaml) to `tests/lab_test.yaml`, point `rule_files` at `../rules/lab.yaml`, and assert:
   - `HighErrorRatio` is **not** firing at `eval_time: 13m`,
   - **is** firing at `eval_time: 20m`,
   - with exactly the labels and annotations you expect.
   ```bash
   promtool test rules tests/lab_test.yaml
   ```
   Then break the rule (change the threshold to `0.9`) and confirm your test fails. **A test that cannot fail is not a test.**
7. Add a `runbook` and `dashboard` annotation with real localhost URLs, and check they appear in the Alertmanager UI when the alert fires.

**Done when:** you can state the exact conditions under which each of your lab alerts fires, and a CI-runnable test proves it.

---

# Lab 4 — Alertmanager: routing, grouping, inhibition, silences (topic 06)

**Goal:** control *who* is told, *how often*, and *how much noise* they see.

1. **Read the tree:**
   ```bash
   amtool config routes show --alertmanager.url=http://localhost:9093
   amtool config routes test --alertmanager.url=http://localhost:9093 \
     --verify.receivers=webhook-checkout-page severity="page" team="checkout" alertname="HighErrorRatio"
   ```
2. **See a notification rendered.** Point your browser (or curl) at the webhook sink while an alert fires:
   ```bash
   curl -s http://localhost:5001/anything/checkout-page | jq '.json'
   ```
   That's the exact payload Alertmanager sends. Inspect `commonLabels`, `commonAnnotations`, `groupLabels`, `alerts[].annotations`.
3. **Grouping.** Fire many alerts at once (stop `demo-app`, `node-exporter`, and make probes fail). In the Alertmanager UI, look at how many *groups* vs *alerts* exist. Then change `group_by` in `alertmanager.yml` from `['alertname','cluster','service']` to `['...']` (all labels → no grouping) and observe the notification count explode. Revert.
4. **Timing.** Set `group_wait: 5s`, `group_interval: 30s`, `repeat_interval: 2m` on the checkout route so the lab feels fast. Fire an alert and time-stamp each notification you receive. Then write down, in your journal, what each of the three parameters controlled.
5. **Inhibition.** Fire `DemoSLOFastBurn` *and* `HighErrorRatio` together (high `FAILURE_RATE` + sustained traffic does both). In the AM UI, `HighErrorRatio` should show as **inhibited** by the SLO alert. Now break the `equal: ['service']` clause to `equal: ['pod']` (a label the alert doesn't have), restart, and confirm inhibition stops working. **This is why inhibition rules silently fail.**
6. **Silences.**
   ```bash
   amtool silence add --alertmanager.url=http://localhost:9093 \
     --author="you@example.com" --comment="Lab 4 experiment" --duration=10m \
     alertname="HighErrorRatio"
   amtool silence query --alertmanager.url=http://localhost:9093
   amtool silence expire <id> --alertmanager.url=http://localhost:9093
   ```
   Confirm the alert still exists in Prometheus but produces no notification.
7. **Time intervals.** Find `business-hours-ist` in `alertmanager.yml`. Send a `severity: ticket` alert outside those hours (or temporarily flip the window) and confirm it's not delivered. Then **delete `location: 'Asia/Kolkata'`** from the interval and observe the window move by 5h30m — the classic UTC bug.
8. **Continue.** Add `continue: true` to the SRE route and confirm an alert now hits two receivers.
9. **Failure mode.** Point a receiver at `http://webhook-sink:80/does-not-exist-service` … actually point it at a dead host (`http://127.0.0.1:1/`) and watch:
   ```promql
   rate(alertmanager_notifications_failed_total[5m])
   ```
   Alertmanager retries with backoff; your `AlertmanagerNotificationsFailing` rule (from the library) is what tells you nobody is being paged.

**Done when:** you can explain, for a given alert, exactly which route matched, which group it joined, whether it was inhibited or silenced, and when the next notification will be sent.

---

# Lab 5 — Dashboards as code (topic 07)

**Goal:** build and version-control a dashboard you'd actually use in an incident.

1. Open Grafana → **Labs** folder → *Lab · Service (RED)*. Note the layout: symptoms on top, traffic breakdown, SLO burn rates, target health, probes.
2. Use the `$job` and `$path` variables. Change the rate window with `$interval`.
3. **Fix the `$__rate_interval` lesson.** Edit one panel, change `[$__rate_interval]` to `[15s]`, set the time range to 7 days, and watch the panel fill with gaps and Prometheus's query duration spike (`prometheus_engine_query_duration_seconds`). Revert.
4. **Add a panel yourself:** "Requests by HTTP method", stacked bars, `topk(6, ...)`, unit `reqps`, with a description saying what "bad" looks like. Save → confirm the JSON on disk updates within 30 s (or restart Grafana).
5. **Add a deploy annotation.** In Dashboard settings → Annotations, add a Prometheus annotation:
   ```promql
   changes(demo_build_info[5m]) > 0
   ```
6. **Data links.** On the p99 panel, add a data link to `http://localhost:9090/graph?g0.expr={{__field.labels.__name__}}` or to a Loki view — so a click takes you from symptom to evidence.
7. **Commit it.** `git add grafana/dashboards && git commit -m "add method breakdown panel"`. Then `docker compose down -v && docker compose up -d` and confirm the dashboard comes back **identically** — proof that provisioning works and nothing lives only in the database.
8. Import a real-world dashboard: **Dashboards → New → Import → `1860`** (Node Exporter Full). Trim it to 10 panels you'd actually read during an incident, save it into the provisioned folder, and delete the rest.

**Done when:** your dashboards survive a total volume wipe, and every panel has a title, a unit, thresholds and a description.

---

# Lab 6 — SLOs, burn rates and scale (topics 09, 11)

**Goal:** run an SLO end to end, then feel the limits of a single Prometheus.

1. **Define the SLO** for `demo-app`: 99.9% availability over the last 28 days (in the lab, use whatever window of data you have). The recording rules are already in `rules/lab.yaml`.
2. Compute the SLI and burn rate in Explore:
   ```promql
   sli:demo_app_availability:ratio_rate5m
   slo:demo_errors:ratio_rate1h / 0.001          # current burn rate
   ```
3. **Trigger a fast burn.** Set `FAILURE_RATE=0.05` (5% errors → burn rate ≈ 50×) with steady traffic. Watch:
   - `DemoSLOFastBurn` fires within ~4 minutes (1h window fills from data you already have + `for: 2m`),
   - the burn-rate panel go red,
   - `HighErrorRatio` also fires but gets **inhibited** by the SLO alert,
   - one notification arrives, not two.
4. **Trigger a slow burn.** Set `FAILURE_RATE=0.005` (0.5% → burn rate ≈ 5×). `DemoSLOFastBurn` must **not** fire (14.4× threshold not met); after ~15 min `DemoSLOSlowBurn` should. This is the behaviour that makes multi-window burn rates worth the complexity: one big incident pages immediately, a long slow degradation becomes a ticket.
5. **Prove the short window's purpose.** Cause a 60-second 50% error burst, then set `FAILURE_RATE=0` and wait. With only the 1h window the burn rate stays high for an hour and you'd be paged for a resolved incident. Confirm the 5m window drops quickly and the alert resolves.
6. **Write the error budget policy.** Create `SLO-POLICY.md` with the freeze/thaw table from topic 09 §5, filled in with your team's real thresholds.
7. **Feel the scale limit.** Enable `RAW_PATH_ENABLED=1` again and hammer unique paths:
   ```bash
   for i in $(seq 1 20000); do curl -s -o /dev/null "http://localhost:8000/orders/$i" & done; wait
   ```
   Watch `prometheus_tsdb_head_series` and container memory (`docker stats lab-prometheus`). Then fix it three ways and measure each:
   - a `metric_relabel_configs` `labeldrop` on `path`,
   - a `replace` normalising `/orders/\d+` → `/orders/:id`,
   - a `keep` dropping the metric entirely for that job.
8. **Bonus:** enable `--web.enable-otlp-receiver` and `--enable-feature=native-histograms` in `docker-compose.yml`, and see what changes in `/metrics` and in the TSDB stats.

**Done when:** you have seen a fast burn page, a slow burn ticket, a resolved burst *not* page, and you have personally reduced a series count by 10× with relabeling.

---

## Troubleshooting the lab

| Problem | Fix |
|---|---|
| `docker compose up` fails to build `demo-app` | No network for `pip install`? Run the app locally instead: `pip install -r app/requirements.txt && python app/app.py`, and change the Prometheus target to `host.docker.internal:8000`. |
| Grafana shows "No data" | Wait 60 s for the first scrapes; check the data source URL is `http://prometheus:9090` (container DNS, not `localhost`). |
| Alertmanager UI shows no alerts | Prometheus → Status → Runtime, confirm `alertmanagers` is discovered; check `prometheus_notifications_queue_length`. |
| Port already in use | Change the host port in `docker-compose.yml` (`"19090:9090"`). |
| `node_exporter` shows weird filesystems | Normal in Docker; the mount-point exclusion flag handles most of it. |
| No notifications in the webhook sink | The route may be muted (check `active_time_intervals` — the lab's `business-hours-ist` uses Asia/Kolkata), or inhibited, or `severity` doesn't match any route. Use `amtool config routes test`. |
| Prometheus OOMKilled during Lab 6 step 7 | That's the lesson. `docker compose up -d prometheus` to restart; the WAL replays. |

## Reset everything

```bash
docker compose down -v && docker compose up -d --build
git checkout -- .        # if you edited configs and want a clean slate
```

---

## Self-check (the real one)

Can you, from a cold start and without looking at these notes:

1. Stand up the stack and confirm every target is up?
2. Make a service return 500s and see a symptom alert page within 5 minutes?
3. Explain why only one notification arrived when three alerts fired?
4. Silence one alert for an hour with a comment, then expire it early?
5. Add a new panel, a new alert and a new unit test, validate all three, and commit them?
6. Reduce a 10× cardinality explosion back to baseline with relabeling?

If yes to all six, you are no longer reading about monitoring — you're doing it.

→ Next: [`14-Cheatsheets`](../14-Cheatsheets/README.md) for reference, [`15-Interview-Prep`](../15-Interview-Prep/README.md) for the job.
