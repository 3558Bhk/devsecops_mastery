# Step 2 (only on the "large order" branch): page a human via SNS
import os         # read the topic ARN pushed in by terraform
import boto3      # AWS SDK
import json       # serialize the message

sns = boto3.client("sns")                            # the SNS client


def handler(event, context):                         # called only when $.amount > threshold
    order_id = event.get("order_id", "?")            # what order
    amount   = event.get("amount", "?")              # how big

    message = json.dumps({                            # a structured alert (not just a string)
        "type":     "large_order",
        "order_id": order_id,
        "amount":   amount,
        "action":   "review before fulfilment",
    })
    sns.publish(                                      # publish to the topic
        TopicArn = os.environ["TOPIC_ARN"],           # which topic (env var from terraform)
        Subject  = "Large order needs review",        # the email subject
        Message  = message,                           # the JSON body
    )

    event["flagged_for_review"] = True                # annotate so the archive shows it happened
    return event                                      # continue to the archive step
