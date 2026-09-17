# The function: triggered by the topic's subscription, publishes the result to a queue
import json                          # parse / serialize the order
import azure.functions as func       # the functions SDK (bindings live here)

app = func.FunctionApp()             # the v2 programming model: one app object


@app.service_bus_trigger(            # BINDING 1 (input): run when a message lands...
    arg_name="msg",                  # ...name of the argument that carries the message
    connection="ServiceBusConnectionString",   # read the connection string from app settings
    topic_name="orders",             # ...on THIS topic
    subscription_name="processing",  # ...on THIS subscription (its own copy of every message)
)
@app.service_bus_output(             # BINDING 2 (output): the RETURN value is published...
    arg_name="result",               # ...to...
    connection="ServiceBusConnectionString",   # same connection string
    queue_name="processed",          # ...this queue
)
def process_order(msg: func.ServiceBusMessage, context: func.Context) -> str:
    # 1. read the raw message the order service published
    order = json.loads(msg.get_body())

    # 2. process it (a real system: validate, price, enrich, check stock)
    order["processed_by"] = "order-pipeline-function"
    order["status"] = "processed"

    # 3. log a line (visible in the function host's logs)
    context.log("processed order %s (amount=%s)" % (order.get("order_id"), order.get("amount")))

    # 4. the return value is picked up by the output binding -> the "processed" queue
    return json.dumps(order)
