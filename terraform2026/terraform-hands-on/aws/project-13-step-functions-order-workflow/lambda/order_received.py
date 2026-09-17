# Step 1 of the pipeline: validate the order before anything else happens
import json     # parse the order JSON


def handler(event, context):                         # called by Step Functions with the order
    # A real system would check stock, pricing, fraud signals, etc.
    # Here we enforce the one rule: every order needs an id.
    if "order_id" not in event:                      # missing id = invalid order
        raise ValueError("order_id is required")     # raise -> the state fails (visible in the workflow)

    event["received_at"] = "validated"               # annotate (shows up in the archived JSON)
    return event                                     # pass the order along to the Choice state
