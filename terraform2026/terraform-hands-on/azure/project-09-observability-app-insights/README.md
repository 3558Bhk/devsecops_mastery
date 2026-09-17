# Project 09 — Observability: Log Analytics + App Insights + Alerts (Azure)

**Difficulty:** ⭐⭐⭐ · **⏱️ ~45 min** · **Cost:** ~$0 (F1 free web app + free Log Analytics/monitoring allowances)

You will wire the *three pillars* onto a web app: logs (Log Analytics), app telemetry
(Application Insights), and an alert that pages when CPU runs hot.

## Concepts practiced
- Log Analytics workspace + diagnostic settings → `../terraform-mastery/02-azure-provider/10-advanced-state-diagnostics-interop.md`
- Application Insights (app-level telemetry)
- Metric alerts (threshold + window + auto-mitigation)

## The flow

```
web app (F1)
   ├─ app telemetry ──► Application Insights  (requests, exceptions, dependencies)
   ├─ console logs  ──► Log Analytics workspace  (queryable with KQL)
   └─ CPU metric    ──► metric alert (CPU > 80% for 5 min → notify)
```

## Files in this folder

| File | What it is |
|---|---|
| `variables.tf` | project, location, alert email |
| `main.tf` | RG + LAW + App Insights + web app + diagnostic + metric alert |
| `outputs.tf` | app URL, instrumentation key, LAW name, alert name |
| `terraform.tfvars.example` | sample inputs |

## Run it

```bash
cd project-09-observability-app-insights
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

## Verify it

```bash
# 1. the app is up
sleep 60
curl -sI https://$(terraform output -raw app_url) | head -3        # expect 200

# 2. logs are flowing (give it ~5 min)
az monitor log-analytics workspace table-queries \
  --workspace $(terraform output -raw law_name) \
  --query "Heartbeat | take 3" --workspace $(terraform output -raw law_name) 2>/dev/null || \
  echo "→ Portal: Log Analytics workspace → Log Analytics queries → 'Heartbeat | take 3'"

# 3. the alert exists
az monitor metrics alert list -g $(terraform output -raw rg_name) -o table

# 4. (optional) heat the app and watch the alert fire:
#    Portal → Application Insights → fail a request a few times, or check CPU in Metrics
```

## Break it (this is the learning)

1. Add a second `enabled_log` category (`"AppEventLogs"`) to the diagnostic setting → `plan`
   → in-place update. Apply.
2. Change the alert threshold 80 → 50 → `plan` → in-place. It will fire more easily. Revert.
3. Add `enabled_metric { category = "Process" metric_name = "InstanceCpuPercent" ... }` to the
   diagnostic setting → `plan` → in-place.

## Clean up

```bash
terraform destroy
```

## Common mistakes

| Mistake | Fix |
|---|---|
| No rows in Log Analytics yet | it takes ~5–10 min for logs to appear; the workspace also gets a `Heartbeat` table automatically |
| Alert never fires | metric alerts need a full evaluation window (5 min here) + the metric to actually exceed it; check the metric in Portal → Metrics first |
| `app_url` 503 for a while | F1 free apps spin up on first hit — curl again in 30s |
