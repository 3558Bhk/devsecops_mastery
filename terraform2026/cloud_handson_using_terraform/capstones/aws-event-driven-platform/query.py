# The QUERY function: API Gateway → DynamoDB (a GSI query)
import json    # serialize
import boto3   # the AWS SDK

ddb = boto3.client("dynamodb")   # the DynamoDB client


def handler(event, context):                      # the entry point
    status = event.get("queryStringParameters", {}).get("status", "new")   # the status to query

    # Query the GSI (StatusIndex) for all orders with this status
    resp = ddb.query(                             # the query
        TableName="orders",                       # the table
        IndexName="StatusIndex",                  # the GSI
        KeyConditionExpression="status = :s",     # the condition
        ExpressionAttributeValues={":s": {"S": status}},   # the value
    )

    # Convert the DynamoDB format to plain dicts for the response
    items = []                                    # the results
    for it in resp.get("Items", []):              # loop over the items
        items.append({                            # the plain dict
            "order_id":   it["order_id"]["S"],    # the partition key
            "created_at": it["created_at"]["S"],  # the sort key
            "status":     it["status"]["S"],      # the status
        })

    return {                                      # the HTTP response
        "statusCode": 200,                        # the status
        "headers": {"Content-Type": "application/json"},   # the header
        "body": json.dumps({"count": len(items), "orders": items}),   # the payload
    }
