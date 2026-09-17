# The INGEST function: S3 → DynamoDB
import json    # parse the S3 event + serialize
import boto3   # the AWS SDK

ddb = boto3.client("dynamodb")   # the DynamoDB client (created once, per container)


def handler(event, context):                      # the entry point
    # The S3 event gives us the bucket + the object key
    for record in event.get("Records", []):       # loop over the records
        bucket = record["s3"]["bucket"]["name"]   # the bucket's name
        key    = record["s3"]["object"]["key"]    # the object's key

        # (In a real app: download the object, parse it, validate it.)
        # Here we just write a synthetic "order" so the pipeline is demonstrable.
        order = {                                 # the item to write
            "order_id":   {"S": key},             # the partition key (the key)
            "created_at": {"S": context.aws_request_id[:8]},   # the sort key
            "status":     {"S": "new"},           # the status (GSI key)
            "ttl":        {"N": "3600"},          # expires in 1 hour (TTL)
        }

        ddb.put_item(                             # write the item
            TableName="orders",                   # the table
            Item=order,                           # the item
        )

    # Publish an "order created" event to SNS (the fan-out)
    import boto3 as b3                            # (imported inline for clarity)
    sns = b3.client("sns")                        # the SNS client
    sns.publish(                                  # publish
        TopicArn="arn:aws:sns:us-east-1:000000000000:evt-events",   # the topic
        Message=json.dumps({"detail-type": "OrderCreated"}),        # the payload
    )

    return {"statusCode": 200}                    # success
