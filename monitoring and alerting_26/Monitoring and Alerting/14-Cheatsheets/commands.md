# Cheatsheet · Commands

## Validation — put these four in CI

```bash
promtool check config prometheus.yml          # also checks referenced rule files
promtool check rules rules/*.yaml
promtool test rules tests/*.yaml
amtool check-config alertmanager.yml
```
Also useful:
```bash
promtool check metrics metrics.txt            # lint an exposition-format file
promtool check web-config web.yml
promtool check sd-config prometheus.yml <job_name>
promtool check service-discovery prometheus.yml <job_name>
promtool tsdb create-blocks-from openmetrics in.txt out/
amtool check-config --alertmanager.url=http://localhost:9093 alertmanager.yml
```

## promtool — query & analyse

```bash
promtool query instant http://localhost:9090 'up'
promtool query instant --format=table http://localhost:9090 'sum by (job)(rate(http_requests_total[5m]))'
promtool query range --start=2026-09-14T00:00:00Z --end=2026-09-14T12:00:00Z --step=60s \
  http://localhost:9090 'rate(http_requests_total[5m])'
promtool query series --match='up' http://localhost:9090
promtool query labels http://localhost:9090

promtool tsdb analyze /prometheus                       # cardinality report ← run this monthly
promtool tsdb analyze --help
promtool tsdb list /prometheus
promtool tsdb out-of-order create-blocks /prometheus
promtool tsdb create-blocks-from openmetrics in.txt out/
promtool debug metrics http://localhost:9090
promtool debug all http://localhost:9090                # tarball of everything for a bug report
```

## amtool

```bash
export ALERTMANAGER_URL=http://localhost:9093

amtool config routes show
amtool config routes test --verify.receivers=checkout-page severity="page" team="checkout"
amtool config routes test --config.file=alertmanager.yml severity="ticket"

amtool alert query                                   # active alerts
amtool alert query severity="page" --expired
amtool alert query --output=extended

amtool silence add --author="me@x.com" --comment="upgrade" --duration=2h cluster="prod-2"
amtool silence add --expires=2026-09-15T02:00:00+05:30 --comment="maint" alertname="X"
amtool silence query
amtool silence query --expired --quiet
amtool silence expire <id>
amtool silence import --file=silences.json
amtool silence update --id=<id> --expires=+2h

amtool template render --template.glob='templates/*.tmpl' --template.text='{{ template "slack.text" . }}'
amtool template render --template.glob='templates/*.tmpl' --template.text='{{ template "email.html" . }}' --template.type=html
amtool template render --template.glob='templates/*.tmpl' --template.text='{{ template "slack.text" . }}' --template.data=/tmp/alert.json
amtool check-config alertmanager.yml
amtool cluster show
```

## kubectl

```bash
# resources
kubectl -n monitoring get prometheus,alertmanager,servicemonitor,podmonitor,probe,prometheusrule,alertmanagerconfig,scrapeconfig,thanosruler
kubectl -n monitoring describe prometheus <name>
kubectl -n monitoring get prometheusrule <name> -o yaml

# logs
kubectl -n monitoring logs prometheus-kps-0 -c prometheus --tail=200 -f
kubectl -n monitoring logs prometheus-kps-0 -c config-reloader --tail=100
kubectl -n monitoring logs alertmanager-kps-0 -c alertmanager --tail=200
kubectl -n monitoring logs -l app.kubernetes.io/name=kube-state-metrics --tail=100
kubectl -n monitoring logs daemonset/kps-prometheus-node-exporter --tail=50

# exec / inspect
kubectl -n monitoring exec -it prometheus-kps-0 -c prometheus -- sh
kubectl -n monitoring exec prometheus-kps-0 -c prometheus -- promtool tsdb analyze /prometheus
kubectl -n monitoring exec prometheus-kps-0 -c prometheus -- \
  wget -qO- localhost:9090/api/v1/targets?state=active | jq -r '.data.activeTargets[]|"\(.health)\t\(.labels.job)\t\(.lastError)"'
kubectl -n monitoring exec prometheus-kps-0 -c prometheus -- \
  wget -qO- localhost:9090/api/v1/rules | jq '.data.groups[].rules[]|select(.health!="ok")|{name,lastError}'

# generated config
kubectl -n monitoring get secret prometheus-kps-kube-prometheus-prometheus \
  -o jsonpath='{.data.prometheus\.yaml\.gz}' | base64 -d | gunzip | less
kubectl -n monitoring get secret alertmanager-kps-kube-prometheus-alertmanager \
  -o jsonpath='{.data.alertmanager\.yaml\.gz}' | base64 -d | gunzip | less

# port-forward
kubectl -n monitoring port-forward svc/kps-grafana 3000:80
kubectl -n monitoring port-forward svc/kps-kube-prometheus-prometheus 9090:9090
kubectl -n monitoring port-forward svc/kps-kube-prometheus-alertmanager 9093:9093

# reload
kubectl -n monitoring exec prometheus-kps-0 -c config-reloader -- wget -qO- --post-data='' localhost:9090/-/reload

# validate a PrometheusRule's spec offline
kubectl -n monitoring get prometheusrule <name> -o json | jq '.spec' > /tmp/rules.json
promtool check rules /tmp/rules.json

# diagnose app-side problems
kubectl -n <ns> top pods --sort-by=memory
kubectl -n <ns> get events --sort-by=.lastTimestamp | tail -30
kubectl -n <ns> describe pod <pod>
kubectl -n <ns> logs <pod> --previous
kubectl -n <ns> get pvc
kubectl get nodes -o wide
kubectl describe node <node> | sed -n '/Conditions/,/Events/p'
```

## curl / HTTP API

```bash
# Prometheus
curl -sG localhost:9090/api/v1/query --data-urlencode 'query=up' | jq '.data.result'
curl -sG localhost:9090/api/v1/query_range \
  --data-urlencode 'query=rate(http_requests_total[5m])' \
  --data-urlencode 'start=2026-09-14T00:00:00Z' \
  --data-urlencode 'end=2026-09-14T12:00:00Z' \
  --data-urlencode 'step=60s' | jq '.data.result|length'
curl -s 'localhost:9090/api/v1/label/__name__/values' | jq '.data|length'
curl -s 'localhost:9090/api/v1/series?match[]=up' | jq '.data|length'
curl -s  localhost:9090/api/v1/targets?state=active | jq '.data.activeTargets[].health'
curl -s  localhost:9090/api/v1/targets?state=dropped | jq '.data.droppedTargets|length'
curl -s  localhost:9090/api/v1/rules | jq '.data.groups[].rules[].name'
curl -s  localhost:9090/api/v1/alerts | jq '.data.alerts[]|{name:.labels.alertname,state}'
curl -s  localhost:9090/api/v1/status/tsdb | jq '.data.headStats'
curl -s  localhost:9090/api/v1/status/tsdb | jq '.data.seriesCountByMetricName'
curl -s  localhost:9090/api/v1/status/buildinfo
curl -s  localhost:9090/api/v1/status/config | jq -r '.data.yaml'
curl -s  localhost:9090/api/v1/status/runtimeinfo
curl -s  localhost:9090/api/v1/metadata | jq 'keys|length'
curl -XPOST localhost:9090/-/reload
curl -XPOST localhost:9090/api/v1/admin/tsdb/snapshot
curl -sG localhost:9090/api/v1/query --data-urlencode 'query=prometheus_tsdb_head_series'

# Alertmanager
curl -s localhost:9093/api/v2/status | jq '{cluster,versionInfo:.versionInfo.version,uptime}'
curl -s localhost:9093/api/v2/alerts | jq '.[]|{name:.labels.alertname,status}'
curl -s 'localhost:9093/api/v2/alerts?filter=severity%3D%22page%22&silenced=false&inhibited=false' | jq
curl -s localhost:9093/api/v2/alerts/groups | jq '.[].labels'
curl -s localhost:9093/api/v2/silences | jq '.[]|{id,status:.status.state,matchers,comment}'
curl -s localhost:9093/api/v2/receivers | jq
curl -XPOST localhost:9093/-/reload

# inject a test alert (the fastest way to test routing/templates)
curl -XPOST localhost:9093/api/v2/alerts -H 'Content-Type: application/json' -d '[{
  "labels":{"alertname":"TestAlert","severity":"page","team":"checkout","service":"checkout-api"},
  "annotations":{"summary":"Test","description":"Verifying routing and templates",
                 "runbook":"https://rb.example.com/x","dashboard":"https://g.example.com/d/x"},
  "startsAt":"2026-09-14T12:00:00+05:30"}]'

# scrape a target manually
curl -s localhost:8000/metrics | head -40
curl -s 'localhost:9115/probe?module=http_2xx&target=https://example.com' | grep probe_success

# webhook sink while testing notifications
nc -l 9999
curl -s http://localhost:5001/anything | jq
```

## docker / compose (labs)

```bash
docker compose up -d --build
docker compose ps
docker compose logs -f prometheus
docker compose logs --tail=100 alertmanager
docker compose restart alertmanager
docker compose stop node-exporter && docker compose start node-exporter
docker compose exec prometheus promtool tsdb analyze /prometheus
docker compose exec prometheus sh
docker compose config --quiet                # validate compose file
docker stats --no-stream lab-prometheus
docker compose down                          # keep volumes
docker compose down -v                       # wipe data
```

## Load generation (to make alerts fire)

```bash
# hey  (go install github.com/rakyll/hey@latest)
hey -z 5m -c 10 -q 5 http://localhost:8000/orders
hey -n 10000 -c 50 http://localhost:8000/fail

# wrk
wrk -t4 -c50 -d60s http://localhost:8000/orders

# vegeta
echo "GET http://localhost:8000/orders" | vegeta attack -rate=100 -duration=5m | vegeta report

# plain bash
while true; do curl -s -o /dev/null http://localhost:8000/orders; done
```

## Quick breakage recipes for labs

```bash
docker compose stop demo-app                        # up == 0, TargetDown
docker compose stop node-exporter                   # host metrics vanish
docker compose stop alertmanager                    # notifications queue up
# edit FAILURE_RATE: "0.35"  -> docker compose up -d demo-app   # HighErrorRatio + SLO burn
# edit LATENCY_MS: "1500"    -> docker compose up -d demo-app   # HighLatencyP99
docker compose exec prometheus sh -c 'echo "bad: yaml: [" > /etc/prometheus/prometheus.yml' \
  && curl -XPOST localhost:9090/-/reload            # ConfigReloadFailure
kubectl -n <ns> delete pod <pod>                    # restarts, CrashLoop if it fails again
kubectl -n <ns> scale deploy/<app> --replicas=0     # zero available replicas
dd if=/dev/zero of=/tmp/fill bs=1M count=5000       # disk pressure (careful!)
```

## Handy one-liners

```bash
# count active series by job
curl -sG localhost:9090/api/v1/query --data-urlencode 'query=count by (job)(up)' | jq -r '.data.result[]|"\(.metric.job)\t\(.value[1])"'

# every alert rule with its health and last error
curl -s localhost:9090/api/v1/rules | jq -r '.data.groups[].rules[]|select(.type=="alerting")|"\(.health)\t\(.name)\t\(.lastError // "")"'

# which alert rules have never fired? (needs a long Prometheus retention)
curl -sG localhost:9090/api/v1/query --data-urlencode 'query=count by (alertname)(ALERTS{alertstate="firing"})' | jq

# targets down right now
curl -s 'localhost:9090/api/v1/targets?state=active' | jq -r '.data.activeTargets[]|select(.health!="up")|"\(.labels.job) \(.scrapeUrl) \(.lastError)"'
```
