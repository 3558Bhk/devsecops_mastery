# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "policy_arn" {                             # output: the policy
  value       = aws_iam_policy.bucket_reader.arn   # the ARN
  description = "attach this ARN to other users/roles"             # it's reusable — that's "managed"
}

output "user_name" {                              # output: the user
  value       = aws_iam_user.lab.name               # the name
  description = "aws iam list-attached-user-policies --user-name <this>"   # verify the attach
}
