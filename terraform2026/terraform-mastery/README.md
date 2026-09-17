# Terraform Mastery — AWS & Azure (Basic to Advanced)

Complete, self-contained study notes. Target versions (as of Sept 2026):
- **Terraform 1.16.x** (1.15.x still supported; 1.14 is EOL)
- **hashicorp/aws** provider v5.x
- **hashicorp/azurerm** provider v5.x (v4.x differences are noted where they matter)

## Folder Map (with time-to-complete per file)

```
terraform-mastery/
├── 00-terraform-core/            ← START HERE (cloud-agnostic)   [~5h 50m total]
│   ├── 01-introduction-installation-cli.md            (~45 min)
│   ├── 02-hcl-syntax-and-file-structure.md            (~40 min)
│   ├── 03-variables-outputs-locals-functions.md       (~45 min)
│   ├── 04-state-and-backends.md                       (~45 min)
│   ├── 05-providers.md                                (~35 min)
│   ├── 06-modules.md                                  (~45 min)
│   ├── 07-advanced-resource-configuration.md          (~60 min)
│   └── 08-best-practices-gotchas.md                   (~35 min)
├── 01-aws-provider/              ← DEEP DIVE: AWS         [~13h total incl. capstone]
│   ├── 01-provider-setup-and-authentication.md        (~45 min)
│   ├── 02-vpc-and-networking-fundamentals.md          (~75 min)
│   ├── 03-ec2-compute.md                              (~50 min)
│   ├── 04-storage-s3-ebs-efs.md                       (~50 min)
│   ├── 05-iam-identity-and-security.md                (~50 min)
│   ├── 06-databases-rds-dynamodb-aurora.md            (~75 min)
│   ├── 07-load-balancing-and-autoscaling.md           (~75 min)
│   ├── 08-serverless-lambda-and-messaging.md          (~75 min)
│   ├── 09-advanced-networking-dns-cdn-observability.md(~75 min)
│   ├── 10-multi-account-import-and-cost.md            (~50 min)
│   └── 11-capstone-3-tier-web-app.md                  (~2.5–3 hrs)
├── 02-azure-provider/            ← DEEP DIVE: Azure       [~12.5h total incl. capstone]
│   ├── 01-provider-setup-and-authentication.md        (~45 min)
│   ├── 02-azure-foundations-and-identity.md           (~50 min)
│   ├── 03-networking-vnets-nsgs.md                    (~75 min)
│   ├── 04-virtual-machines.md                         (~50 min)
│   ├── 05-storage-accounts.md                         (~35 min)
│   ├── 06-databases.md                                (~75 min)
│   ├── 07-load-balancer-and-app-gateway.md            (~75 min)
│   ├── 08-serverless-functions-and-app-service.md     (~50 min)
│   ├── 09-aks-kubernetes.md                           (~75 min)
│   ├── 10-advanced-state-diagnostics-interop.md       (~50 min)
│   └── 11-capstone-3-tier-web-app.md                  (~2.5–3 hrs)
└── 03-cross-cloud-and-interview/                       [~2h 50m total]
    ├── 01-aws-vs-azure-comparison.md                  (~35 min)
    ├── 02-cicd-terraform-cloud-workflows.md           (~75 min)
    └── 03-interview-questions-and-cheatsheet.md       (~60 min)
```

**Total course time: ~34 hours** (≈ 6 weeks at ~1 hr/day, or ~2 weeks at ~2.5 hrs/day).

## Suggested Learning Path (4–6 weeks)

| Phase | What | Files | Time |
|---|---|---|---|
| 1. Core | Install, syntax, CLI, variables/functions | 00-core/01–03 | ~2h 10m |
| 2. Core | State, backends, providers, modules | 00-core/04–06 | ~2h 05m |
| 3. Core | for_each, dynamic, lifecycle, import, checks | 00-core/07, 08 | ~1h 35m |
| 4. AWS | Setup/auth → networking → compute → storage | 01-aws/01–04 | ~3h 40m |
| 5. AWS | IAM, databases, ELB/ASG, serverless | 01-aws/05–08 | ~4h 35m |
| 6. AWS | DNS/CDN, multi-account, capstone | 01-aws/09–11 | ~4h 35m–5h 05m |
| 7. Azure | Setup/auth → foundations → networking → VMs | 02-azure/01–04 | ~3h 40m |
| 8. Azure | Storage, DBs, LB/AppGW, serverless, AKS | 02-azure/05–09 | ~5h 10m |
| 9. Azure | Diagnostics, interop, capstone | 02-azure/10–11 | ~3h 20m–3h 50m |
| 10. Synthesis | Cross-cloud comparison, CI/CD, interview drill | 03/01–03 | ~2h 50m |

## How to Actually Learn (not just read)

1. **Every code block must be executed.** Free tiers: AWS Free Tier (750h EC2, 20GB EBS, 5GB S3) and Azure free account ($200 credit + 12 months free services, 750h B1s VM, 12 months free Azure SQL/Storage basics).
2. **Destroy what you create** (`terraform destroy`) so you understand teardown order, and to save credits.
3. **Keep a `labs/` folder** next to each exercise — your muscle memory is built in that folder, not in these notes.
4. **Break things on purpose:** change one attribute at a time, run `plan`, and *predict* what will happen (update? in-place? replace?) before running `apply`.

## Golden Rules (memorize these now)

1. **Terraform is declarative** — you describe the *desired end state*, never the steps.
2. **State is sacred** — never commit it, never store it in plaintext, always use a remote backend with locking.
3. **Idempotency** — running `apply` twice in a row must produce zero changes (second plan is empty).
4. **`plan` before every `apply`**, always. A plan you didn't read is a change you didn't approve.
5. **Modules over copy-paste.** If the same block appears twice, it's a module.
6. **Secrets never live in state or config** — use data sources / secrets managers.
7. **Pin provider versions** (`~> 5.0`) so a new provider release can't silently change behavior.
8. **`destroy` order is the reverse of `create` order** — Terraform's dependency graph handles it.
