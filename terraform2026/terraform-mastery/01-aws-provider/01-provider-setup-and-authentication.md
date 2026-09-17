# AWS 1 — Provider Setup & Authentication

> **⏱️ Time to complete: ~45 min** (read + verify auth with `data.aws_caller_identity`)

## 1.1 The Provider Block (minimal → complete)

```hcl
terraform {                          # the terraform config block
  required_providers {               # declare required providers
    aws = {                          # the AWS provider
      source  = "hashicorp/aws"      # registry address
      version = "~> 5.0"             # any 5.x, never 6.x
    }
  }
}

provider "aws" {                      # configure the AWS provider
  region  = var.region                # target region (or omit → AWS_REGION env var)
  profile = "admin"                   # use the "admin" profile from ~/.aws/credentials
}
```

Everything below is optional and environment-specific.

## 1.2 The AWS Credential Chain (what the provider tries, in order)

1. **Terraform provider args** (`access_key`, `secret_key`, `token`) — rarely; avoid hardcoding.
2. **Environment variables** — `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_REGION`.
3. **Shared credentials files** — `~/.aws/credentials` (+ `~/.aws/config` for profiles/SSO).
4. **SSO** (if `profile` points at an SSO config in `~/.aws/config`).
5. **Assume role** (provider `assume_role` block).
6. **ECS task role / EC2 instance metadata (IRSA/IMDS)** — when running on AWS itself.

For a developer laptop, you usually only need **one** of: a profile, env vars, or SSO. For CI/CD, you need **OIDC** or an assume-role.

## 1.3 `~/.aws/credentials` and `~/.aws/config`

```ini
# ~/.aws/credentials
[default]                            # the "default" profile
aws_access_key_id     = AKIAXXXXXXXXXXXXX   # access key id
aws_secret_access_key = XXXXXXXXXXXXXXXXXXXXXXX   # secret access key

[admin]                              # a named profile called "admin"
aws_access_key_id     = AKIA...   # its access key id
aws_secret_access_key = ...   # its secret access key
```

```ini
# ~/.aws/config
[profile admin]                      # a profile (region + other settings)
region = ap-south-1                  # default region for this profile

[profile sso-admin]                  # an SSO-based profile
sso_start_url        = https://myorg.awsapps.com/start   # the SSO portal URL
sso_account_id       = 111111111111  # the AWS account id
sso_role_name        = AdminRole     # the role to assume via SSO
region               = ap-south-1    # default region
```

```hcl
provider "aws" {                      # the provider block
  profile = "sso-admin"               # use the SSO profile (triggers `aws sso login` once)
}
```

> SSO is the modern default for AWS employees/enterprises: `aws sso login` → tokens cached in `~/.aws/sso/cache`.

## 1.4 `assume_role` in the Provider (cross-account / least privilege)

```hcl
provider "aws" {                      # the provider block
  region = var.region                 # target region

  assume_role {                       # assume a role (switch account/principal)
    role_arn       = var.terraform_role_arn   # arn:aws:iam::2222...:role/tf-prod
    session_name   = "terraform-${var.environment}"   # auditable session name
    external_id    = var.external_id          # anti-confused-deputy (cross-account)
    duration       = 3600                     # session lifetime (seconds)
    policy_arns    = [var.scoping_policy_arn] # runtime policy intersection (tighten further)
    source_identity = "terraform-pipeline"    # auditable in CloudTrail
  }
}
```

The target role's **trust policy** must allow your principal:

```hcl
resource "aws_iam_role" "terraform" {   # create the Terraform role
  name = "tf-${var.environment}"        # role name (per env)

  assume_role_policy = jsonencode({     # the trust policy (who may assume it)
    Version = "2012-10-17"              # IAM policy version
    Statement = [{                      # one statement
      Effect = "Allow"                  # allow
      Action = "sts:AssumeRole"         # the assume-role action
      Principal = { AWS = "arn:aws:iam::111111111111:role/ci-runner" }  # the CI runner role
      Condition = {                     # a condition (extra guard)
        StringEquals = { "sts:ExternalId" = var.external_id }   # must match this external id
      }
    }]
  })
}
```

## 1.5 CI/CD: GitHub Actions OIDC (the standard, no long-lived keys)

```yaml
- uses: aws-actions/configure-aws-credentials@v4   # the AWS OIDC action
  with:
    role-to-assume: arn:aws:iam::111111111111:role/github-tf   # the role to assume
    aws-region: ap-south-1   # the region
    audience: sts.amazonaws.com   # (default for GHA)
```

The role's trust policy:

```json
{
  "Effect": "Allow",                                  // allow
  "Action": "sts:AssumeRoleWithWebIdentity",          // web-identity (OIDC) assume
  "Principal": { "Federated": "arn:aws:iam::111111111111:oidc-provider/token.actions.githubusercontent.com" },  // the GHA OIDC provider
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",   // audience check
      "token.actions.githubusercontent.com:sub": "repo:myorg/infra:ref:refs/heads/main"   // only this repo+branch
    }
  }
}
```

After that step, the provider picks up the **default chain** (env vars set by the action) — no provider auth args needed. (Alternatively, set `web_identity_token_file` on the provider to point at the token file.)

## 1.6 Useful Provider Arguments

| Argument | Purpose |
|---|---|
| `region` | Target region |
| `profile` | Shared config profile |
| `shared_credentials_files` | Non-default credentials file paths |
| `assume_role { ... }` | Role to assume (above) |
| `assume_role_with_web_identity { role_arn, web_identity_token_file }` | OIDC directly |
| `max_retries` | Retries for 5xx/throttling (default 5) |
| `default_tags` | Auto-tag everything (see below) |
| `s3_use_path_style` | LocalStack/MinIO: `true` |
| `endpoints { s3 = "..." }` | Custom endpoints (LocalStack, sovereign clouds) |
| `sts_regional_endpoint` | `regional` vs `fips-regional` |
| `use_fips_endpoint` | FIPS environments |
| `forbidden_account_ids` | Guardrail: fail if these accounts appear in any arn |
| `allowed_account_ids` | Guardrail: only these accounts |
| `skip_credentials_validation`, `skip_metadata_api_check`, `skip_region_validation` | **Testing only** (LocalStack). Never in prod. |

### `default_tags` — your tag policy

```hcl
provider "aws" {                      # the provider block
  region = var.region                 # target region

  default_tags = {                    # tags auto-applied to every taggable resource
    Project     = var.project         #  project tag
    Environment = var.environment     #  environment tag
    ManagedBy   = "terraform"         #  managed-by tag
    CostCenter  = var.cost_center     #  cost-allocation tag
  }
}
```

Every taggable resource gets these **automatically**. Per-resource `tags` merge on top; `tags_all` is the merged result (use in outputs/alarms to avoid double-tag diffs).

## 1.7 Multi-Region / Multi-Account (aliases)

```hcl
provider "aws" {                      # an ALIASED provider
  alias  = "us_east"                  # alias name → referenced as aws.us_east
  region = "us-east-1"                # the us-east-1 region
}

resource "aws_acm_certificate" "wildcard" {   # an ACM certificate
  provider     = aws.us_east          # ACM for CloudFront MUST live in us-east-1
  domain_name  = "*.example.com"      # the wildcard domain
  validation_method = "DNS"           # validate via a DNS record
}
```

See Core 05 for the full alias mechanics.

## 1.8 LocalStack (test AWS without the cloud)

```hcl
terraform {                          # terraform block
  backend "local" {}                  # (or s3 with custom endpoints)
}

provider "aws" {                      # the provider pointed at LocalStack
  region                      = "us-east-1"   # any region works
  access_key                  = "test"        # dummy credentials
  secret_key                  = "test"        # dummy secret
  s3_use_path_style           = true          # path-style S3 URLs (LocalStack needs this)
  skip_credentials_validation = true          # don't validate creds (LocalStack)
  skip_metadata_api_check     = true          # don't check the IMDS endpoint
  skip_region_validation      = true          # don't validate the region

  endpoints {                         # point each service at the LocalStack port
    ec2      = "http://localhost:4566"   # EC2
    s3       = "http://localhost:4566"   # S3
    iam      = "http://localhost:4566"   # IAM
    lambda   = "http://localhost:4566"   # Lambda
    sqs      = "http://localhost:4566"   # SQS
    sns      = "http://localhost:4566"   # SNS
    dynamodb = "http://localhost:4566"   # DynamoDB
  }
}
```

Docker: `docker run -p 4566:4566 localstack/localstack`. Not everything is emulated (RDS is partial), but network/compute/storage/IAM/lambda work well for CI.

## 1.9 Verifying Your Setup

```hcl
data "aws_caller_identity" "me" {}          # who am I (account/arn/user)
data "aws_partition" "current" {}            # which partition
data "aws_region" "current" {}               # which region

output "whoami" {                            # expose it as an output
  value = {                                  # an object with all the facts
    account   = data.aws_caller_identity.me.account      # the account id
    arn       = data.aws_caller_identity.me.arn          # the caller ARN
    partition = data.aws_partition.current.partition     # aws/aws-cn/...
    region    = data.aws_region.current.name             # the region name
  }
}
```

`terraform plan` → outputs tell you **exactly which account/region you're about to modify**. Do this first in any new stack.

## 1.10 Common Auth Errors

| Error | Cause / Fix |
|---|---|
| `NoCredentialProviders: no valid providers in chain` | No creds anywhere: set env vars / profile / SSO login. |
| `Unable to validate AWS Credentials` | Bad/rotated keys; check `aws sts get-caller-identity`. |
| `AccessDenied` on a specific API | Role lacks that action (or scoped too tightly). |
| `Region not set or invalid` | Set `region` or `AWS_REGION`. |
| `ExpiredToken` | Long `assume_role` session expired mid-run; bump `duration` or re-auth. |
| SSO: `No cached SSO session` | Run `aws sso login --profile <p>` again. |

## 1.11 Interview Quick Facts

- AWS provider tries the **standard AWS credential chain** — same as the AWS SDK/CLI.
- **OIDC** (GHA → STS Web Identity) is the modern CI pattern: no static keys at all.
- `external_id` defends against the **confused deputy** problem in cross-account roles.
- `default_tags` = provider-level tag policy; `forbidden_account_ids`/`allowed_account_ids` = guardrails.
- LocalStack + `endpoints` + `s3_use_path_style` = local AWS for testing.
- Always `data.aws_caller_identity` in a new stack to **prove which account** you're talking to.
