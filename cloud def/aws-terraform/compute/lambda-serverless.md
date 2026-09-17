# Terraform Lambda & Serverless (AWS) — Interview Questions

> **Cloud:** AWS · **IaC Tool:** Terraform · **Levels:** Case A (Basic) · Case B (Advanced/Senior) · Case C (Scenario) · **Reading time:** ~5 min

---

## Case A — Basic

**A1. What resources define a Lambda function in Terraform?**
**Answer:** `aws_lambda_function` (code, handler, runtime, role) plus an `aws_iam_role` with an `aws_iam_role_policy_attachment` for `AWSLambdaBasicExecutionRole` (logs) and any resource permissions.

**A2. What is `filename` vs `s3_bucket`/`s3_key` for code?**
**Answer:** `filename` uploads a local zip; `s3_bucket`+`s3_key` point to a package in S3 (required for packages >50 MB or CI-built artifacts).

**A3. How do you create the deployment package with Terraform?**
**Answer:** Typically `data "archive_file" "zip" { ... }` zips your source directory, passed as `filename`, with `source_code_hash` to trigger updates on change.

**A4. What is the Lambda execution role?**
**Answer:** The IAM role the function assumes at runtime, granting it permissions (logs, DynamoDB, S3…). Set via `role = aws_iam_role.lambda.arn`.

**A5. What is `handler` and `runtime`?**
**Answer:** `handler` is the entrypoint (`index.handler`); `runtime` is the language runtime (e.g. `python3.12`, `nodejs20.x`).

**A6. How do you set environment variables and memory/timeout?**
**Answer:** `environment { variables = {...} }`, `memory_size`, and `timeout` arguments on `aws_lambda_function`.

**A7. What is a Lambda layer?**
**Answer:** `aws_lambda_layer_version` packages shared libraries/dependencies; functions reference layers with `layers = [aws_lambda_layer_version.x.arn]`.

**A8. How do you trigger a Lambda from API Gateway?**
**Answer:** `aws_api_gateway_rest_api` → `aws_api_gateway_resource` → `aws_api_gateway_method` → `aws_api_gateway_integration` (type `AWS_PROXY`), then `aws_lambda_permission` to let API Gateway invoke the function, and a deployment.

**A9. What is `aws_lambda_permission`?**
**Answer:** A resource policy statement allowing a principal (API Gateway, S3, SNS) to invoke the function.

**A10. How do you trigger a Lambda from S3 events?**
**Answer:** `aws_s3_bucket_notification` with `lambda_function { lambda_function_arn, events = ["s3:ObjectCreated:*"] }` plus `aws_lambda_permission` for S3.

**A11. What is `aws_cloudwatch_log_group` for Lambda?**
**Answer:** The log group where function logs go (`/aws/lambda/<name>`); defining it in Terraform lets you control retention.

**A12. What is a Lambda alias?**
**Answer:** `aws_lambda_alias` — a named pointer to a function version, enabling versioned deploys and weighted routing.

**A13. How do you publish versions?**
**Answer:** `publish = true` on `aws_lambda_function` or `aws_lambda_function_version`, so changes create a new immutable version.

**A14. What is `reserved_concurrent_executions`?**
**Answer:** A cap on concurrent executions for the function, protecting downstream resources from overload.

**A15. What is the `source_code_hash` argument?**
**Answer:** A hash that triggers redeployment when the code zip changes — otherwise Terraform may not detect code-only updates.

## Case B — Advanced / Senior

**B1. How do you do blue-green or canary deployments of a Lambda?**
**Answer:** Publish a new version, create/update an alias with `routing_config` weights (e.g. 90/10) to shift traffic, then promote. Terraform manages versions + alias routing explicitly.

**B2. How do you keep the Lambda zip reproducible in CI?**
**Answer:** Build the artifact in CI (deterministic zip), upload to S3, reference `s3_bucket`/`s3_key`/`s3_object_version`, and set `source_code_hash = filebase64sha256(zip)` so changes redeploy.

**B3. What is the difference between VPC-attached and non-VPC Lambdas?**
**Answer:** VPC-attached functions run in your subnets (with ENIs) to reach private resources like RDS; non-VPC functions run in AWS-managed networking. VPC attachment adds cold-start latency and needs NAT for internet.

**B4. How do you attach a Lambda to a VPC in Terraform?**
**Answer:** `vpc_config { subnet_ids = [...] ; security_group_ids = [...] }`. Ensure the SGs and route tables allow needed traffic (NAT for egress).

**B5. What is provisioned concurrency?**
**Answer:** `aws_lambda_provisioned_concurrency_config` keeps N instances warm to avoid cold starts, optionally per alias.

**B6. How do you manage environment-specific secrets in Lambda?**
**Answer:** Inject via environment variables referencing Secrets Manager/SSM (`data "aws_secretsmanager_secret_version"`), or use the Parameters and Secrets Lambda extension. Avoid hardcoding secrets in config/zip.

**B7. How does API Gateway HTTP API differ from REST API in Terraform?**
**Answer:** `aws_apigatewayv2_api` (HTTP API) is cheaper/faster for proxy-style Lambda/HTTP routes; `aws_api_gateway_rest_api` supports full REST features (request validation, usage plans, VPC links). Pick per requirements.

**B8. How do you wire SQS → Lambda with Terraform?**
**Answer:** `aws_lambda_event_source_mapping` connects the queue to the function (batch size, concurrency), plus the IAM policy to read SQS and the function's role to process messages.

**B9. What are Lambda destinations and dead-letter queues?**
**Answer:** `destination_on_success`/`destination_on_failure` on the function (or `dead_letter_config` legacy) send async results/errors to SQS/SNS/EventBridge for retry/observability.

**B10. How do you avoid a "function and IAM role create race" that fails on first apply?**
**Answer:** The role must exist before the function; Terraform orders this via the `role` reference. For edge cases (e.g. API Gateway needing the function), add `depends_on` explicitly.

**B11. What is the `aws_lambda_invocation` resource?**
**Answer:** It invokes a function during apply and stores the result — sometimes used for one-time setup tasks, but generally an anti-pattern for routine config (side effects outside the graph).

**B12. How do you manage many shared layers/versions across functions?**
**Answer:** Publish layers once (versioned), reference them in a module or via data sources, and centralize common IAM policies in reusable modules to avoid duplication.

## Case C — Scenario

**C1. A Lambda times out writing to RDS. What do you check in Terraform/config?**
**Answer:** Function `timeout` too low, VPC config missing (function can't reach the private RDS), SG rules not allowing function→RDS port, and subnets without a route to the DB. Fix config and re-apply.

**C2. You need a public HTTPS endpoint that calls your function.**
**Answer:** HTTP API (or REST API) + Lambda integration: define the API, route/method, `AWS_PROXY` integration, `aws_lambda_permission`, and a deployment. Attach a custom domain + ACM cert if needed.

**C3. Code deploys aren't updating the function even though the zip changed.**
**Answer:** `source_code_hash` isn't reflecting the new artifact. Point it at the actual zip hash (or use S3 object versioning) so Terraform detects the change and updates the function.

**C4. A busy function is throttling and returning 429s.**
**Answer:** Raise `reserved_concurrent_executions` (and account quota), add provisioned concurrency if latency-sensitive, tune batch size for stream/queue triggers, and scale downstream resources.

**C5. You must deploy the same function code to dev and prod with different config.**
**Answer:** One module with inputs (env vars, concurrency, memory), instantiated per environment with different tfvars/workspaces, sharing the same code artifact. Keep secrets per environment via SSM/Secrets Manager.

**C6. Cold starts hurt a latency-sensitive API. What do you change?**
**Answer:** Add provisioned concurrency for the alias, increase memory (more CPU), use a lighter runtime/package (smaller zip, fewer layers), and consider keeping the function warm or moving hot paths off Lambda.
