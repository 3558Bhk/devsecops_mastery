# The INVENTORY consumer. Runs once per message from the inventory queue.
# It has NO idea the billing consumer exists — that's the point of decoupling.


def handler(event, context):  # entry point: SQS calls this with the batch
    for record in event["Records"]:  # each message in the batch
        body = record["body"]  # the published JSON
        print(f"inventory: reserving stock for order {body}")  # to CloudWatch Logs
    return {"processed": len(event["Records"])}  # acknowledge the batch
