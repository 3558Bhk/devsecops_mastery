# Project 04 — Looping: for_each and count (AWS)

**Difficulty:** ⭐⭐ · **⏱️ ~45 min** · **Cost:** ~$0.02–0.04/hr (1–2 micro instances — destroy after!)

Two blocks of code, and Terraform creates one resource *per list item*. This is how you
stop copy-pasting.

## Concepts practiced
- `for_each` — one resource per *named* item (keyed, deletable independently) → `../terraform-mastery/00-terraform-core/07-advanced-resource-configuration.md`
- `count` — one resource per *number* (indexed)
- Splat expressions (`[*]`) — collecting outputs into a list
- `each.value` / `count.index`

## for_each vs count (memorize)

| | `for_each` | `count` |
|---|---|---|
| driven by | a **map/set** (names) | a **number** |
| identity | by **key** (`app-dev`) | by **index** (`[0]`, `[1]`) |
| removing an item | safe (only that one disappears) | dangerous (everything after shifts!) |
| use when | items have meaning ("dev", "prod") | items are identical ("2 replicas") |

## Files in this folder

| File | What it is |
|---|---|
| `variables.tf` | `environments` (list) + `instance_count` (number) |
| `main.tf` | buckets with `for_each`, instances with `count` |
| `outputs.tf` | collected lists of names and IPs |

## Run it

```bash
cd project-04-for-each-and-count
terraform init
terraform plan
terraform apply
```

## Verify it

```bash
terraform output bucket_names    # a map: dev/staging/prod → bucket name
terraform output worker_ips      # a list: the public IP(s)
aws s3 ls                        # three buckets appear
```

## Break it (this is the learning)

1. Remove `"prod"` from `environments` in the file → `plan` → **only the prod bucket** is
   destroyed, dev/staging untouched (that's the for_each win). Apply.
2. Set `instance_count = 2` → `plan` → one more instance added at index 1, index 0 untouched. Apply.
3. Set it back to 1 → `plan` → instance `[1]` destroyed. This is safe — but if you had
   resources *relying on* `[1]` it would break: that's why for_each is preferred for named items.

## Clean up

```bash
terraform destroy
```

## Common mistakes

| Mistake | Fix |
|---|---|
| `for_each` error: "must be a map or set" | wrap a list in `toset()`: `for_each = toset(var.environments)` |
| `Unsupported block type: for_each with count` | you can never use both on one resource — pick one |
| Changing from `count` to `for_each` destroys everything | expected — it changes resource identity; use `terraform state mv` to migrate |
