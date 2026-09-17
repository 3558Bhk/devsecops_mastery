# The single Lambda that backs both POST /orders and GET /orders
import json            # to parse/serialize JSON request + response bodies
import os              # to read environment variables set by Terraform
import boto3           # the AWS SDK (DynamoDB access)

TABLE = os.environ["ORDERS_TABLE"]                    # the table name (pushed in by terraform)
table = boto3.resource("dynamodb").Table(TABLE)       # a handle to the table (region comes from the AWS env)


def handler(event, context):                          # the entry point API Gateway calls
    method = event["httpMethod"]                      # the HTTP method the client used

    if method == "POST":                              # ── write path: create an order ──
        body = json.loads(event["body"])              # parse the request's JSON
        item = {
            "order_id": body["order_id"],             # partition key (required, else KeyError -> 500)
            "item":     body.get("item", "?"),        # what was ordered
            "status":   "new",                        # initial status (the GSI keys on this)
            "amount":   float(body.get("amount", 0)), # the price
        }
        table.put_item(Item=item)                     # write it to DynamoDB (real-time, ~ms)
        return {                                       # tell the client it was created
            "statusCode": 201,
            "body": json.dumps({"created": item["order_id"]}),
        }

    else:                                             # ── read path: list everything ──
        items = table.scan().get("Items", [])         # full scan (fine for a lab; use Query + GSI in prod)
        return {
            "statusCode": 200,
            "body": json.dumps({"orders": items}),
        }
