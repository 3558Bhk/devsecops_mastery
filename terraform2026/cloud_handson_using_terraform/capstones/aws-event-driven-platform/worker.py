# The WORKER function: SQS → (process)
import json    # serialize
import boto3   # the AWS SDK


def handler(event, context):                      # the entry point
    # The SQS event gives us the messages
    for record in event.get("Records", []):        # loop over the messages
        body = json.loads(record["body"])          # the payload
        message_id = record["messageId"]           # the message's id

        # (In a real app: call an external API, transform, enrich, etc.)
        # Here we just log — the point is the DECOUPLING, not the logic.
        print(f"processing {body} (message {message_id})")   # a log line

        # If this raised, SQS would retry (up to maxReceiveCount=3) → DLQ.

    # Returning normally = SQS deletes the messages (successful processing).
    return {"processed": len(event.get("Records", []))}   # the count
