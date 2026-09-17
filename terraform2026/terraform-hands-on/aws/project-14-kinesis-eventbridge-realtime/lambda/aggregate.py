# The stream consumer: turns a BATCH of click events into one per-minute stats file in S3
import json                                            # parse the Kinesis payload
import os                                              # read the bucket name
import boto3                                           # AWS SDK
from datetime import datetime, timezone                # UTC timestamps for the file name

s3 = boto3.client("s3")                                # the S3 client


def handler(event, context):                           # Kinesis calls this with a batch of records
    # Each record's payload is base64-encoded JSON in event["Records"][i]["kinesis"]["data"]
    import base64                                      # decode it
    clicks = []
    for record in event["Records"]:                    # walk the batch
        raw = base64.b64decode(record["kinesis"]["data"]).decode("utf-8")   # decode
        clicks.append(json.loads(raw))                 # parse the click event

    # One file per clock minute (many batches in the same minute -> same key -> last write wins)
    minute = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H-%M")   # e.g. 2026-09-17T10-42

    summary = {
        "minute": minute,                              # which minute this covers
        "count":  len(clicks),                         # how many clicks this batch had
        "clicks": clicks,                              # the raw events (a real system would pre-aggregate)
    }

    s3.put_object(                                     # persist the aggregate
        Bucket = os.environ["STATS_BUCKET"],           # which bucket (env var from terraform)
        Key    = "minute/%s.json" % minute,            # the object path
        Body   = json.dumps(summary, indent=2),        # the JSON file
    )

    return {"processed": len(clicks)}                  # reported in CloudWatch as the function result
