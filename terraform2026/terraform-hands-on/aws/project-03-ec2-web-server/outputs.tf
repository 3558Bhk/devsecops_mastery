output "public_ip" {                             # output: the instance's public IP
  value       = aws_instance.web.public_ip       # this changes on stop/start (ephemeral IP)
  description = "Open http://this in your browser"   # what you'll use to test
}

output "instance_id" {                           # output: the instance's stable ID
  value       = aws_instance.web.id              # e.g. i-0abc123def456
  description = "Useful for aws console and CLI lookups"   # stays the same for the instance's life
}

output "ami_used" {                              # output: which image we actually booted
  value       = data.aws_ami.al2023.id           # from the data source
  description = "The AMI ID Terraform picked (the newest Amazon Linux 2023)"   # reproducible builds
}
