# Azure Track — 14 Hands-On Projects (Basic → Mastery)

Every project lives in its own folder with its own `.tf` files (each line commented).
The skills mirror the AWS track 1:1, so if you did AWS first, each project feels familiar.

## Prerequisites (once)

```bash
az login
az account set --subscription "<your-subscription-name>"
az account show -o table      # confirm the subscription
```

That's it — the `azurerm` provider picks up your Azure CLI login automatically
(`azure_auth` in the notes). Free account: $200 credit + 12 months of free
`Standard_B1s` VM hours and basic storage/SQL.

## The ladder

| Project | You will... | Skills | ⏱️ |
|---|---|---|---|
| `project-01-first-storage` | create your very first real resources | init / plan / apply / destroy, state file | ~30 min |
| `project-02-variables-outputs` | make storage configurable | `variable`, `output`, `tfvars`, `locals` | ~40 min |
| `project-03-first-vm-ssh` | launch a Linux VM and SSH into it | VNet/subnet/NSG/NIC, public IP, image reference | ~60 min |
| `project-04-for-each-and-count` | create N firewall rules and N VMs with 2 code blocks | `for_each`, `count`, splat expressions | ~45 min |
| `project-05-your-first-module` | build a reusable VNet module + a root that uses it | child modules, module inputs/outputs, `for_each` | ~60 min |
| `project-06-remote-backend-state` | move state to an Azure blob, state surgery, import | `azurerm` backend + SAS token, `state mv/show`, `import` | ~60 min |
| `project-07-key-vault-serverless` | a Key Vault secret + a web app | Key Vault, access policies, App Service | ~60 min |
| `project-08-capstone-3-tier-app` | VNet + App Gateway + VM + Azure SQL + Key Vault + monitoring | everything, combined | ~2.5 hrs |
| `project-09-observability-app-insights` | Log Analytics + App Insights + a CPU alert that pages you | diagnostic settings, App Insights, action groups, metric alerts | ~50 min |
| `project-10-service-bus-and-queues` | messaging: a topic + 2 subscriptions + a queue with a dead-letter path | Service Bus, auth rules, DLQ on expiry | ~60 min |
| `project-11-cosmos-key-vault-managed-identity` | Cosmos DB + a DB password in Key Vault read via a managed identity | Cosmos SQL API, Key Vault policies, system-assigned identity | ~60 min |
| `project-12-functions-service-bus-blob` | an order pipeline: Service Bus topic → Function → result queue (zip-deployed code) | Functions (consumption/Y1), bindings, topic/subscription fan-out, zip deploy | ~60 min |
| `project-13-event-hubs-stream-analytics` | IoT telemetry: Event Hubs → live SQL filter → hot readings in Blob | Event Hubs, Stream Analytics (inputs/outputs as resources) | ~60 min |
| `project-14-api-management-gateway` | a web app exposed behind API Management with a rate-limit policy + products | API Management, policies-as-XML, products & subscriptions | ~60 min |

**Total: ~7.25 hrs**

## Cost guardrails

- Smallest VM only: `Standard_B1s` (~$0.02/hr).
- The capstone (project 08) with App Gateway + SQL is roughly **$0.50–1.00/hr** while running. Test, then `terraform destroy`.
- Quick bill check: `az consumption usage list --start-date $(date -d "3 days ago" +%Y-%m-%d) -o table`

## Folder conventions (same in every project)

| File | Purpose |
|---|---|
| `main.tf` | resources (and `terraform`/`provider` blocks in simple projects) |
| `variables.tf` | inputs (`variable` blocks) |
| `outputs.tf` | values shown after `apply` |
| `terraform.tfvars.example` | sample input values — copy to `terraform.tfvars` |
| `README.md` | the plan: what, why, steps, verification, cleanup |
