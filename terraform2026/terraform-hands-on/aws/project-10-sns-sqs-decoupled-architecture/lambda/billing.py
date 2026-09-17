# The BILLING consumer. Runs once per message from the billing queue.


def handler(event, context):  # entry point: SQS calls this with the batch of messages
    for record in event["Records"]:  # a batch can hold several messages
        body = record["body"]  # the message body (the JSON string we published)
        print(f"billing: processing order {body}")  # print = CloudWatch Logs (where we see it)
    return {"processed": len(event["Records"])}  # acknowledge the batch (any return is fine)
