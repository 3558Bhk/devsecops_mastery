# ======================================================================
#  outputs.tf
#  Output values — the "what got created" results Terraform prints after
#  `apply` (endpoints, ids, hostnames you copy-paste).
#  (the standard layout this folder follows: providers.tf | variables.tf |
#   main.tf | outputs.tf — one job per file)
# ======================================================================

output "volume_id" {                             # output: the source volume
  value       = aws_ebs_volume.data.id             # the id
  description = "aws ec2 describe-volumes --volume-ids <this>"   # how to look
}

output "snapshot_id" {                           # output: the snapshot
  value       = aws_ebs_snapshot.data.id           # the id
  description = "aws ec2 describe-snapshots --snapshot-ids <this>"   # how to look
}

output "restored_volume_id" {                    # output: the clone
  value       = aws_ebs_volume.restored.id         # the id
  description = "now in us-east-1b — cross-AZ restore done"        # the point of the exercise
}
