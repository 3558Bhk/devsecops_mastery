# The API's handler: echo the request path + method back
import json          # serialize the response


def handler(event, context):                       # the entry point
    return {                                       # AWS_PROXY: return a full HTTP response
        "statusCode": 200,                         # the status
        "headers": {"Content-Type": "application/json"},   # the headers
        "body": json.dumps({                        # the payload
            "path":   event.get("path"),            # the requested path
            "method": event.get("httpMethod"),      # the verb
        }),
    }
