# CloudFront — Terraform how-to

## 📁 File structure (the standard Terraform layout)

| File | What it does |
|---|---|
| `providers.tf` | the `terraform` block (required_providers) + provider config — "which cloud, which provider version, how to log in" |
| `variables.tf` | input variables — the knobs (e.g. `region`) you change without touching the resources |
| `main.tf` | the resources — the actual infrastructure Terraform creates (and any `data` lookups) |
| `outputs.tf` | output values — the endpoints/ids/URLs Terraform prints after `apply` |

> Why four files? Terraform reads **every** `.tf` file in the folder as one program. Splitting by
> concern is the industry convention: reviewers find the resources in `main.tf`, you change
> settings in `variables.tf`, and you read results in `outputs.tf` — instead of one 500-line file.

**What:** a CDN distribution in front of an S3 origin, with an **Origin Access Control** (private bucket, public edge).

**Interview angle (SDE3):**
- CloudFront = edge cache (100+ cities); OAC = "the edge may read this private bucket" (replaces the old OAI).
- Cache key = path + (optionally) query strings/headers — "why is my content stale?" is a cache-invalidation + cache-key question.
- CloudFront in front of an **ALB** (web app) vs S3 (static) are the two shapes you'll draw in an interview.

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: aws cloudfront list-distributions
# test:   curl -s https://$(aws cloudfront list-distributions --query 'DistributionList.Items[0].DomainName' --output text)
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| 403 from CloudFront to S3 | the OAC's `origin_access_control_origin_type` must be `s3` and the bucket policy must allow the OAC's `CallerReference` (this file wires both) |
| Content stale after S3 update | CloudFront caches — invalidate the path (`aws cloudfront create-invalidation`) or vary the object name |
| `AccessDenied` in the bucket logs | the bucket policy allows the OAC, not the public — check you're hitting it via the distribution, not S3 directly |
