# AWS 5 — IAM, Identity & Security

> **⏱️ Time to complete: ~50 min** (read + create a role + instance profile)

## 5.1 IAM Mental Model

- **Principal** = who/what (user, role, group, federated identity).
- **Policy** = a JSON document of Allow/Deny statements (attached to a principal or a resource).
- **Role** = an identity an entity *assumes* (with a **trust policy** saying who may assume it).
- **Group** = a collection of users that share policies.
- **Instance profile** = how an EC2 instance gets a role.

Two policy types:
1. **Identity-based** (on user/role/group): "What can *this principal* do?"
2. **Resource-based** (on the resource): "Who can access *this resource*?" (e.g. S3 bucket policy, role trust policy).

## 5.2 Roles (the workhorse)

### The trust-policy data source (builds the JSON for you)

```hcl
data "aws_iam_policy_document" "ec2_assume" {   # build an IAM trust policy document
  statement {                                    # one statement
    effect  = "Allow"                            # allow
    actions = ["sts:AssumeRole"]                 # the assume-role action
    principals {                                 # who may assume
      type        = "Service"                    # an AWS service
      identifiers = ["ec2.amazonaws.com"]        # specifically EC2
    }
  }
}
```

### Create a role + policy + attach

```hcl
resource "aws_iam_role" "ec2" {              # create the role
  name               = "${local.name_prefix}-ec2"   # role name
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json   # the trust policy
  path               = "/"                  # the path (avoids the default "/" drift)
}

resource "aws_iam_role_policy_attachment" "ec2_s3" {   # attach a managed policy
  role       = aws_iam_role.ec2.name        # the role
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"   # AWS-managed S3 read-only
}

# Custom policy
resource "aws_iam_policy" "ec2_custom" {     # create a custom policy
  name        = "${local.name_prefix}-ec2-custom"   # policy name
  description = "Scoped S3 read for app bucket"     # description
  policy = jsonencode({                        # the policy document
    Version = "2012-10-17"                      # IAM policy version
    Statement = [{                              # one statement
      Effect   = "Allow"                        # allow
      Action   = ["s3:GetObject", "s3:ListBucket"]   # the actions
      Resource = [aws_s3_bucket.app.arn, "${aws_s3_bucket.app.arn}/*"]   # the bucket + objects
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_custom" {   # attach the custom policy
  role       = aws_iam_role.ec2.name        # the role
  policy_arn = aws_iam_policy.ec2_custom.arn   # the custom policy
}

# Expose to the instance
resource "aws_iam_instance_profile" "ec2" {  # an instance profile (wraps the role for EC2)
  name = "${local.name_prefix}-ec2-profile"  # profile name
  role = aws_iam_role.ec2.name               # the role it wraps
}
```

### Role variants by principal type

```hcl
# Human / cross-account AWS principal
data "aws_iam_policy_document" "cross_account" {   # a cross-account trust doc
  statement {                                    # one statement
    effect  = "Allow"                            # allow
    actions = ["sts:AssumeRole"]                 # assume-role
    principals {                                 # who
      type        = "AWS"                        # an AWS principal
      identifiers = ["arn:aws:iam::111111111111:root"]   # that account's root
    }
    condition {                                  # a condition
      test     = "StringEquals"                  # exact match
      variable = "sts:ExternalId"                # on the external id
      values   = [var.external_id]               # must equal this
    }
  }
}

# Lambda service role
data "aws_iam_policy_document" "lambda_assume" {  # a Lambda trust doc
  statement {
    effect = "Allow", actions = ["sts:AssumeRole"],
    principals { type = "Service", identifiers = ["lambda.amazonaws.com"] }  # trusted by Lambda
  }
}

# RDS, S3 replication, EKS, etc. — same pattern, different service principal
```

## 5.3 Users & Access Keys (avoid; know them)

```hcl
resource "aws_iam_user" "ci" {              # an IAM user
  name = "ci-bot"                           # the username
  force_destroy = (var.environment != "prod")   # dev-only (removes attached entities)
}

resource "aws_iam_user_policy_attachment" "ci" {   # attach a policy to the user
  user       = aws_iam_user.ci.name        # the user
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"   # read-only
}

# Access key (AVOID long-lived; prefer OIDC/roles)
resource "aws_iam_access_key" "ci" {        # an access key for the user
  user = aws_iam_user.ci.name               # the user
}
output "ci_key" {
  value = aws_iam_access_key.ci.sensitive_key   # the secret key
  sensitive = true                             # mask it in output
}
```

**Prefer:** OIDC (CI), instance profiles/IRSA (compute), roles (cross-account). Long-lived user keys = a rotating liability.

## 5.4 Cross-Account Access (the pattern)

1. Account A (data) creates a role with a trust policy for account B, **plus** `Condition sts:ExternalId`.
2. Account B assumes it with the matching `external_id`.
3. Account A's policies scope what the role can actually do.

This `external_id` guard prevents the **confused deputy** attack (someone in A forging a request that looks like B).

## 5.5 Useful IAM Data Sources & Policies

```hcl
data "aws_iam_policy" "admin" { arn = "arn:aws:iam::aws:policy/AdministratorAccess" }  # read the admin policy
data "aws_iam_policy_document" "deny" {   # a "force TLS" deny document
  statement {
    effect = "Deny"                        # deny
    actions = ["*"]                        # everything
    condition {                             # when the request is NOT over TLS
      test = "Bool"                         # boolean test
      variables = { "aws:SecureTransport" = "false" }
      values = ["false"]
    }
  }
}
```

**Permission boundaries** (cap a role's max permissions):
```hcl
resource "aws_iam_role" "capped" {        # a role with a boundary
  name = "capped-role"                     # the role name
  assume_role_policy = data.aws_iam_policy_document.x.json   # the trust policy
  permissions_boundary = "arn:aws:iam::111111111111:policy/boundary"   # the boundary policy
}
```

**SCP / Organizations** (account-level guardrails) are **not** managed by the aws provider's standard resources in most orgs — they're set at the **Organizations** level (`aws_organizations_*` resources exist but require org admin). Know they exist; don't try to SCP from a workload account.

## 5.6 Service-Principal Cheat Sheet

| Service | Principal |
|---|---|
| EC2 | `ec2.amazonaws.com` |
| Lambda | `lambda.amazonaws.com` |
| RDS | `rds.amazonaws.com` |
| S3 (replication) | `s3.amazonaws.com` |
| EKS | `eks.amazonaws.com` |
| ECS | `ecs-tasks.amazonaws.com` |
| CodeBuild | `codebuild.amazonaws.com` |
| CloudTrail → S3 | `cloudtrail.amazonaws.com` |
| SNS → Lambda | `sns.amazonaws.com` |

## 5.7 IAM Best Practices

- **Roles over users** for everything (services, cross-account, even humans via SSO).
- **Least privilege**: start broad to collect `AccessDenied`, then tighten to exact actions + resource ARNs.
- **`sts:ExternalId`** on cross-account roles.
- **No root** long-lived keys; use SSO.
- **Permission boundaries** to cap roles.
- **IAM Access Analyzer** to find unintended external access.
- **MFA** on human principals.
- **Rotate** keys/certs; prefer **temporary** (assumed) credentials.
- **Tag** IAM roles (`default_tags` works) for cost/ownership.

## 5.8 Getting It Right / Gotchas

- **`aws_iam_role` name is global** within the account — collisions across envs → prefix with env.
- **Policy JSON must be valid** — `jsonencode()` + `data.aws_iam_policy_document` keeps it clean and testable.
- **A role with no trust policy can't be assumed** — you always need the `assume_role_policy`.
- **Instance profile ≠ role**: the profile *wraps* the role for EC2.
- **Deny beats Allow** in IAM evaluation — use explicit `Deny` for guardrails (e.g. no plaintext).
- **`force_destroy`** on IAM user/role removes attached entities; dev-only.
- **`path = "/"`** to avoid the `/` vs `/\` default ambiguity (a classic drift source).

## 5.9 Interview Quick Facts

- Role = trust policy (who can assume) + permission policies (what it can do).
- **Identity-based vs resource-based** policies.
- **ExternalId** = confused-deputy defense.
- **Instance profile** = EC2's way of holding a role.
- **Deny > Allow**; **least privilege**; **roles over users**.
- SCP/permission boundaries = guardrails layered on top.
- Use `data.aws_iam_policy_document` to build trust/docs without hand-writing JSON.
