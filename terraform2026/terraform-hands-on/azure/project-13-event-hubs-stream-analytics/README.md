# Project 13 — IoT Telemetry, Filtered in Real Time (Azure)

**Difficulty:** ⭐⭐⭐⭐⭐ · **⏱️ ~60 min** · **Cost:** ~$0.10/mo at lab volume — destroy after

The canonical **real-time data pipeline**: devices stream temperature readings into Event Hubs,
**Stream Analytics runs a live SQL query** over the stream, and only the *hot* readings
(> 80°) are written to a Blob container — seconds after they happen, continuously, forever.

## The real-time flow

```
1000 sensors (az eventhubs event send)
   │  JSON: {"device_id":"s1","temperature":83.4}
   ▼
Event Hub  telemetry   (partitioned, ordered, 24h replay)
   │  the stream
   ▼
Stream Analytics job  (a LIVE SQL query: WHERE temperature > 80)
   │  only the hot rows
   ▼
Blob container  hot-readings/   (auto-partitioned by date/time pattern)
```

## Concepts practiced
- Event Hubs (the streaming ingest layer) → `../terraform-mastery/02-azure-provider/09-messaging.md`
- Stream Analytics (SQL over a stream; inputs/outputs as separate resources) → `../terraform-mastery/02-azure-provider/10-observability-and-streaming.md`
- The "ingest → filter → sink" shape you'll see in every IoT/log platform

## Files in this folder

| File | What it is |
|---|---|
| `variables.tf` | project, location, hot threshold |
| `main.tf` | storage + Event Hub + Stream Analytics job/input/output |
| `outputs.tf` | event hub endpoint, container, job name |
| `terraform.tfvars.example` | sample inputs |

## Run it

```bash
cd project-13-event-hubs-stream-analytics
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

> Give the Stream Analytics job ~2 minutes after apply — it has to start before it ingests.

## Verify it (send cold and hot readings)

```bash
RG=$(terraform output -raw rg_name)
NS=$(terraform output -raw namespace_name)

# 1. a COLD reading (should be filtered OUT)
az eventhubs event send -g $RG -n $NS --eventhub-name telemetry \
  --message-body '{"device_id":"s1","temperature":22.1}'

# 2. a HOT reading (should land in the blob)
az eventhubs event send -g $RG -n $NS --eventhub-name telemetry \
  --message-body '{"device_id":"s2","temperature":83.4}'
az eventhubs event send -g $RG -n $NS --eventhub-name telemetry \
  --message-body '{"device_id":"s3","temperature":91.0}'

# 3. wait ~1 min, then look in the blob container (path: hot-readings/hot/...)
az storage blob list -c hot-readings \
  --account-name $(terraform output -raw storage_name) -o table
# download one: az storage blob download -c hot-readings -n <the file> --account-name <...> -f hot.json
```

## Break it (this is the learning)

1. **Change the query live**: edit `transformation_query` in `main.tf` (e.g. threshold 50, or
   `SELECT device_id, AVG(temperature) AS avg FROM Telemetry GROUP BY TumblingWindow(hour, 1), device_id`
   — a real rolling average) → `apply` → the job updates → send readings → new output shape.
2. **Replay**: Event Hubs keeps 24h of data. Point the input at an older time? (Stream Analytics
   inputs can start from an offset — `az eventhubs position` shows where consumers are.)
3. **Add a second output**: copy the `azurerm_stream_analytics_output_blob` block → new output
   "ColdReadings" with `WHERE temperature <= 80` → two sinks from one stream.

## Clean up

```bash
terraform destroy
```

## Common mistakes

| Mistake | Fix |
|---|---|
| Nothing in the blob, no error | the job needs a minute to start; also check `az stream-analytics job show -g $RG -n <job>` → status Running; check the job's "Events lost" counter |
| `EventHub not found` in the job | the input's `servicebus_namespace`/`eventhub_name` must match exactly |
| Blob files appear but are empty | check the output's `time_format`/`date_format` (invalid patterns make the job drop rows — see the job's errors in the portal) |
| Job name errors | 3–50 chars, lowercase letters/digits/hyphens, must start with a letter |
