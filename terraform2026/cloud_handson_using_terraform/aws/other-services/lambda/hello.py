# A minimal Lambda: echo the event back with a greeting
import json          # serialize the response


def handler(event, context):                       # the entry point (file.function = hello.handler)
    name = event.get("name", "world")              # read a field from the event (or default)
    return {                                       # the return value is the response
        "statusCode": 200,                         # the HTTP-ish status
        "body": json.dumps({"hello": name}),       # the payload
    }
