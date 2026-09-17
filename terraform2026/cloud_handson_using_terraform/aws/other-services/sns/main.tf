# ============================================================================
#  SNS — Terraform how-to
# ============================================================================

# --- THE RESOURCES (this file: everything Terraform creates / reads) -----------

resource "aws_sns_topic" "alerts" {              # the topic: the single publish point
  name      = "lab-alerts"                       # the topic's name
  tags      = { env = "lab" }                    # a label
}

resource "aws_sns_topic_subscription" "email" {  # deliver to an email (confirm the link once!)
  topic_arn = aws_sns_topic.alerts.arn           # which topic
  protocol  = "email"                            # the delivery protocol
  endpoint  = "you@example.com"                  # the address (CHANGE this)
}

resource "aws_sns_topic_subscription" "sqs" {    # deliver to a queue (the decoupling pattern)
  topic_arn = aws_sns_topic.alerts.arn           # which topic
  protocol  = "sqs"                              # deliver to SQS
  endpoint  = aws_sqs_queue.worker.arn           # to this queue
}

resource "aws_sqs_queue" "worker" {              # the queue that receives the fan-out
  name                      = "lab-worker-queue" # the queue's name
  message_retention_seconds = 86400              # keep messages 1 day
}

resource "aws_sqs_queue_policy" "allow_sns" {    # the queue must allow the TOPIC to publish to it
  queue_url = aws_sqs_queue.worker.url           # which queue

  policy = jsonencode({                          # the policy JSON
    Version = "2012-10-17"                        # the version
    Statement = [{                                 # one statement
      Effect    = "Allow"                          # allow
      Principal = { Service = "sns.amazonaws.com" }  # by the SNS service
      Action    = "sqs:SendMessage"                # sending messages
      Resource  = aws_sqs_queue.worker.arn         # to this queue
      Condition = {                                 # ...but only from our topic
        ArnEquals = { "aws:SourceArn" = aws_sns_topic.alerts.arn }   # the topic's ARN
      }
    }]
  })
}
