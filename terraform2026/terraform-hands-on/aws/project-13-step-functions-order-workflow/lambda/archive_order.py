# Final step: persist the (possibly annotated) order to S3
import os         # read the bucket name pushed in by terraform
import json       # serialize
import boto3      # AWS SDK

s3 = boto3.client("s3")                               # the S3 client


def handler(event, context):                         # called for every order that reached the end
    order_id = event.get("order_id", "unknown")      # the file is named after the order

    s3.put_object(
        Bucket = os.environ["ARCHIVE_BUCKET"],        # which bucket (env var from terraform)
        Key    = "orders/%s.json" % order_id,         # the object path
        Body   = json.dumps(event, indent=2),         # the whole (annotated) order as JSON
    )

    event["archived"] = True                          # annotate
    return event                                      # the run ends here
