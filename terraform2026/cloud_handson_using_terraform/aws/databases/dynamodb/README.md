# DynamoDB — Terraform how-to

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

**What:** a single-table-style order store with a GSI, TTL, PITR, and encryption.

**Interview angle (SDE3):**
- DynamoDB = key-value + query on the PK; **GSIs** = extra indexes with their own keys (you design for your access patterns first).
- `PAY_PER_REQUEST` vs provisioned RCUs/WCUs — and the "when would you switch?" trade-off.
- TTL = free auto-expiry; PITR = point-in-time restore; streams = the event source for Lambda.

## Run it
```bash
terraform init && terraform plan && terraform apply
# verify: aws dynamodb describe-table --table-name lab-orders
# put:    aws dynamodb put-item --table-name lab-orders \
#          --item '{"order_id":{"S":"o1"},"status":{"S":"new"},"expires_at":{"N":"1893456000"}}'
# query GSI: aws dynamodb query --table-name lab-orders --index-name StatusIndex \
#          --key-condition-expression "status = :s" --expression-attribute-values '{":s":{"S":"new"}}'
```

## Clean up
```bash
terraform destroy
```

## Common mistakes
| Mistake | Fix |
|---|---|
| Query on the GSI is slow/limited | GSI reads consume RCUs like the table; also a GSI is a **full copy** of the projected attributes — size accordingly |
| "I need a third index" | up to 20 GSIs per table; if you're past that, you're modeling wrong (rethink the access patterns) |
