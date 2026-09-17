# ============================================================================
#  EBS Volumes — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "aws_ebs_volume" "data" {               # the volume
  availability_zone = "us-east-1a"               # which AZ (EBS is single-AZ!)
  size              = 10                          # 10 GB
  type              = "gp3"                       # general purpose SSD (the default choice)
  tags              = { Name = "data-vol" }       # a label
}

resource "aws_ebs_snapshot" "data" {             # the snapshot
  volume_id = aws_ebs_volume.data.id             # which volume to snapshot
  tags      = { Name = "data-snap" }             # a label
  description = "lab snapshot"                    # a human note

  # snapshots are INCREMENTAL — a second snapshot of the same volume only stores deltas
}

resource "aws_ebs_volume" "restored" {           # the restored/clone volume
  availability_zone = "us-east-1b"               # a DIFFERENT AZ (this is how you move EBS cross-AZ)
  size              = 10                          # must be ≥ the snapshot's size
  type              = "gp3"                       # same type
  snapshot_id       = aws_ebs_snapshot.data.id   # clone FROM this snapshot
  tags              = { Name = "restored-vol" }   # a label
}
