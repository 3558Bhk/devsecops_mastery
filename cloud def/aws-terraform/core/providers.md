# Terraform Providers (AWS) — Interview Questions

> **Cloud:** AWS · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~6 min

---

## Case A — Basic

**A1. What is the AWS provider in Terraform?**
**Answer:** It's the plugin that lets Terraform manage AWS resources (`aws_instance`, `aws_vpc`, etc.). It authenticates to AWS and translates HCL into AWS API calls.

**A2. How do you declare the AWS provider?**
**Answer:** With a `provider "aws" { ... }` block (or the newer `required_providers` block), setting `region` and credentials, e.g. `provider "aws" { region = "us-east-1" }`.

**A3. How does Terraform authenticate to AWS?**
**Answer:** Via the standard AWS credential chain: environment variables (`AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`), shared credentials file (`~/.aws/credentials`), instance role, or explicit `access_key`/`secret_key`/`token` arguments.

**A4. Why pin a provider version?**
**Answer:** To make builds reproducible and avoid surprises when provider behavior changes. Pin with a `required_providers` version constraint and commit `.terraform.lock.hcl`.

**A5. What does `terraform init -upgrade` do?**
**Answer:** It updates modules and providers to the newest versions allowed by your version constraints, refreshing the lock file.

**A6. How do you set the AWS region?**
**Answer:** Through the provider's `region` argument, or via the `AWS_REGION`/`AWS_DEFAULT_REGION` environment variables. Per-resource regions are not supported, so you use provider aliases.

**A7. What is a provider alias?**
**Answer:** A named, secondary configuration of the same provider, e.g. `provider "aws" { alias = "west" ; region = "us-west-2" }`. Resources select it with `provider = aws.west`.

**A8. What is a provider version constraint syntax like?**
**Answer:** e.g. `aws = { source = "hashicorp/aws", version = "~> 5.0" }`. `~> 5.0` allows 5.x but not 6.0.

**A9. Where are provider plugins stored after init?**
**Answer:** In the `.terraform/providers/` directory inside the working directory, downloaded from the Terraform Registry (or a private mirror).

**A10. What does the `source` attribute in `required_providers` mean?**
**Answer:** It identifies where the provider comes from, e.g. `hashicorp/aws` means the official registry namespace/name.

**A11. What happens if you run `terraform plan` before `terraform init`?**
**Answer:** It fails because providers aren't installed and the backend isn't configured. `init` must run first in any new or changed working directory.

**A12. What is the `assume_role` provider argument?**
**Answer:** It makes the provider assume an IAM role after initial authentication — commonly used to manage resources in another account or to adopt a least-privilege role from a CI user.

**A13. How do you reference the currently selected region in config?**
**Answer:** Via the data source `data "aws_region" "current" {}` and `data "aws_caller_identity" "current" {}` for the account ID.

**A14. Can you manage resources in multiple AWS accounts from one config?**
**Answer:** Yes — declare multiple `provider "aws"` blocks (one per account, using `assume_role`), give each an alias, and point resources at the right alias.

**A15. What are provider default tags?**
**Answer:** The `default_tags` provider argument adds a common tag set to every taggable resource the provider creates, keeping tagging consistent without repeating `tags` everywhere.

## Case B — Advanced / Senior

**B1. Explain the provider configuration hierarchy.**
**Answer:** Terraform merges: provider block arguments > environment variables > shared config files. Explicit arguments win. Credentials are resolved at plan/apply time; the chain differs slightly between credentials and region.

**B2. How do you manage the same provider at two versions in one project?**
**Answer:** You generally can't in one working directory — the lock file pins one version per provider source. If a module needs an older API, refactor to one version or split into separate state/root modules that run independently.

**B3. What is the `features` block in the Azure provider vs AWS?**
**Answer:** (Azure uses `features {}`; AWS has no equivalent.) In AWS the closest concepts are provider-level `default_tags` and `ignore_tags` for tag management, and `skip_*` options for metadata API calls.

**B4. Why might `terraform plan` be slow with the AWS provider?**
**Answer:** Large resource counts and per-resource API pagination (e.g. many IAM roles, thousands of S3 objects). Mitigate with narrower state, `parallelism` tuning, and avoiding data sources that scan (like `aws_iam_policy_document` is fine, but listing everything is not).

**B5. How does provider caching and the `.terraform.lock.hcl` checksum work?**
**Answer:** The lock file records the exact provider version plus hashes. `init` verifies downloads against these hashes, preventing tampering and ensuring every machine uses byte-identical plugins.

**B6. What is the risk of using `access_key`/`secret_key` directly in a provider block?**
**Answer:** Secrets end up in config and possibly state output. Prefer environment variables, shared credentials, IAM roles (EC2/CI OIDC), or a secrets manager injected at runtime.

**B7. How do you make the provider assume a role only for specific resources?**
**Answer:** Use a provider alias configured with `assume_role`, and set `provider = aws.alias_name` on just those resources. Resources without the attribute use the default provider.

**B8. What does `ignore_tags` do and when is it useful?**
**Answer:** It tells the provider to ignore specific tag keys when comparing state, so externally added tags (e.g. cost-center auto-tagging) don't cause perpetual diffs.

**B9. How do providers handle eventual consistency / API retries?**
**Answer:** The AWS provider implements retries with backoff for known eventually-consistent APIs (IAM, S3). If a race remains, use `depends_on` or a `time_sleep`/wait data source to sequence operations.

**B10. How would you route a subset of config to a different region without aliases?**
**Answer:** You can't cleanly — resources bind to their provider's region. The idiomatic approach is one provider per region using aliases, or per-environment roots each pinned to a region.

**B11. What is a provider's "terraform_version" requirement?**
**Answer:** Providers can declare a minimum Terraform core version. If your CLI is older, `init` fails — bump Terraform or pin an older provider that still supports your CLI.

**B12. How do you debug provider/API failures?**
**Answer:** Set `TF_LOG=DEBUG` (or `TF_LOG_PROVIDER=DEBUG`) to see raw API requests/responses, check `AWS_*` env vars and IAM permissions, and use `terraform apply -parallelism=1` to isolate the failing resource.

## Case C — Scenario

**C1. CI fails with "Error: Failed to query available provider packages" — how do you fix it?**
**Answer:** Check that the registry (or private mirror) is reachable from CI, that `required_providers` source/version is valid, and that the lock file isn't referencing hashes unavailable to the runner's platform. Re-run `terraform init -upgrade` and commit the updated lock file.

**C2. A dev reports plans differ between their laptop and CI. What do you check?**
**Answer:** Confirm everyone uses the same Terraform CLI and pinned provider version (lock file committed), same env vars/credentials, and the same backend/state. Differing provider versions is the usual culprit.

**C3. You must deploy identical infrastructure in `us-east-1` and `eu-west-1`. How do you structure it?**
**Answer:** Define a root module per region (or a single root with two aliased providers) so each region has its own state. Better: parameterize the region and run the same root twice with different backend/var files, keeping state per region for isolation.

**C4. An auditor flags long-lived access keys in your Terraform pipeline. What's the fix?**
**Answer:** Replace keys with OIDC federation (GitHub Actions → AWS IAM role with `assume_role`), short-lived credentials via Vault/STS, and remove keys from the environment entirely. Ensure the provider uses the role, not static secrets.

**C5. You need to manage resources in a second AWS account (logging account) from your main account's Terraform.**
**Answer:** Add a second `provider "aws"` block with `assume_role` targeting a role in the logging account, grant the main account's identity `sts:AssumeRole` via the role's trust policy, and use the alias for those resources.

**C6. A Terraform upgrade breaks your existing AWS config. How do you roll out the upgrade safely?**
**Answer:** Pin the current version, test the new provider version in a sandbox/plan-only branch, review the provider changelog for breaking changes (renamed resources, removed arguments), migrate with `state mv`/`moved` blocks if needed, then bump the constraint and roll out gradually per environment.
