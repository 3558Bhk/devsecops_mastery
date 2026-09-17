output "data_bucket" {                            # output: the main bucket's name
  value       = aws_s3_bucket.data.id             # from the resource
  description = "The project's data bucket"       # what it is
}

output "legacy_bucket" {                          # output: the imported bucket's name
  value       = aws_s3_bucket.legacy.id           # after import, this now has a value
  description = "The bucket we adopted with terraform import"   # shows the import worked
}
