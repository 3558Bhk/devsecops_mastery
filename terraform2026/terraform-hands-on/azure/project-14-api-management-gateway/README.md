# Project 14 — Expose Your API Behind API Management (Azure)

**Difficulty:** ⭐⭐⭐⭐ · **⏱️ ~60 min** · **Cost:** ~$1/mo (Developer_1 gateway) — destroy after

What every public API needs in front of it: **one URL** clients call, with **policies** that do the
boring dangerous stuff — rate limiting, key-based auth, logging — while the backend stays simple
and never sees a hostile client directly.

## The real-time flow

```
external client (curl with an API key)
   │  GET https://<apim>.azure-api.net/hello
   ▼
API Management gateway (Developer_1)
   │  policies run on EVERY request:
   │    1. base (auth via subscription key)
   │    2. rate-limit: 10 calls / second per client IP
   │    3. logging (every request → App Insights/portal)
   ▼
backend web app (F1, free) — serves /
```

## Concepts practiced
- API Management (gateway, products, subscriptions, policies-as-code) → `../terraform-mastery/02-azure-provider/08-api-management.md`
- Policies as XML in Terraform (change a limit = change code, reviewable, versioned)
- "One public door, many back rooms" architecture

## Files in this folder

| File | What it is |
|---|---|
| `variables.tf` | project, location, rate limit values |
| `main.tf` | backend web app + APIM service + API + policy + product |
| `outputs.tf` | gateway URL + the public API URL |
| `terraform.tfvars.example` | sample inputs |

## Run it

```bash
cd project-14-api-management-gateway
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

> The APIM gateway takes ~5–10 minutes to provision. Watch `az api-management show` until `state=Running`.

## Verify it

```bash
RG=$(terraform output -raw rg_name)
URL=$(terraform output -raw api_url)

# 1. call the API through the gateway (subscription_required=false, so no key needed in the lab)
curl -s -o /dev/null -w '%{http_code}\n' "$URL"        # expect 200 (the F1 app's default page)

# 2. feel the rate limit: 30 fast calls — the last few come back 429 (Too Many Requests)
for i in $(seq 1 30); do curl -s -o /dev/null -w '%{http_code} ' "$URL"; done; echo

# 3. the policy is code: terraform output shows the gateway URL; the XML lives in main.tf
```

## Break it (this is the learning)

1. **Tighten the limit**: set `rate_limit_calls = 3` in tfvars → `apply` → 10 fast calls →
   you see 3 `200`s then `429`s. (In production you'd throttle per subscription, not per IP.)
2. **Require a key**: set `subscription_required = true` on the API → `apply` → bare curl now gets
   `401`. Then in the portal: Products → Starter → `+ Add subscription` (pick "main" user) → copy
   the key → `curl -H 'Ocp-Apim-Subscription-Key: <key>'` → `200`. That's real API auth, end to end.
3. **Add a policy**: append `<set-header name="X-Processing-Time" exists-action="override"><value>tf</value></set-header>`
   inside `<inbound>` → `apply` → the response now carries your header. Policies deploy = `apply`.

## Clean up

```bash
terraform destroy
```

## Common mistakes

| Mistake | Fix |
|---|---|
| `404` on the API URL | the gateway is still provisioning (check `state`); the API's `path` must match your URL's last segment |
| All `429`s immediately | you're over the rate limit — wait for the renewal period, or raise `rate_limit_calls` |
| `401` when you didn't expect it | the API has `subscription_required = true` — send an `Ocp-Apim-Subscription-Key` header |
| APIM stuck provisioning | Developer_1 is cheap but not instant (5–10 min); check `az api-management show -g $RG -n <name> -o table` |
