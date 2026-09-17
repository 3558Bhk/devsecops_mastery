# ============================================================================
#  SQS — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "aws_sqs_queue" "dlq" {                 # the DLQ
  name                      = "lab-work-dlq"     # the DLQ's name
  message_retention_seconds = 1209600            # keep failures 14 days (time to investigate)
}

resource "aws_sqs_queue" "work" {                # the main queue
  name                      = "lab-work"         # the queue's name
  visibility_timeout_seconds = 60                  # hide a message 60s while a consumer works on it
  message_retention_seconds  = 86400               # keep undelivered messages 1 day

  redrive_policy = jsonencode({                    # the redrive: "after N fails, send to the DLQ"
    deadLetterTargetArn = aws_sqs_queue.dlq.arn    # where poison messages go
    maxReceiveCount     = 3                        # 3 failed deliveries = poison
  })
}
