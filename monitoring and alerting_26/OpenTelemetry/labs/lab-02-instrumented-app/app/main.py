"""Lab 02 — demo FastAPI application.

Shows the four things a real service needs, and deliberately includes the
mistakes that make telemetry useless so you can see them in the UI:

  1. resource attributes that identify the service          (env vars, below)
  2. a MANUAL span for a business operation                 (checkout)
  3. log correlation — trace_id/span_id injected into logs  (logging setup)
  4. a HIGH-CARDINALITY MISTAKE and a PII LEAK, so the
     Collector's redaction and cardinality controls have
     something real to catch

Run locally without Docker:
    export OTEL_SERVICE_NAME=checkout-service
    export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
    opentelemetry-instrument uvicorn main:app --host 0.0.0.0 --port 8000

`opentelemetry-instrument` is the zero-code entry point installed by
opentelemetry-distro. It wires up the SDK, the OTLP exporter and the
auto-instrumentation for FastAPI/requests/logging without touching this file.
See ../../09-sdks-and-instrumentation.md
"""

import logging
import os
import random
import time

import requests
from fastapi import FastAPI, HTTPException

# ---------------------------------------------------------------------------
# The MANUAL part of instrumentation.
#
# Auto-instrumentation gives you the HTTP server span for free. What it cannot
# know is what your BUSINESS OPERATION is. So we import the API (not the SDK)
# and create a span by hand. Importing only `opentelemetry.trace` keeps this
# file working even when no SDK is configured — the API degrades to a no-op.
# ---------------------------------------------------------------------------
from opentelemetry import trace
from opentelemetry.trace import StatusCode

tracer = trace.get_tracer("checkout-service", "1.0.0")

# ★ Log correlation. The `opentelemetry-instrumentation-logging` package
#   injects otelTraceID / otelSpanID / otelServiceName into every LogRecord,
#   but ONLY if the format string references them. This is the piece people
#   forget: the SDK adds the fields, YOUR FORMATTER has to print them.
logging.basicConfig(
    level=logging.INFO,
    format=(
        "%(asctime)s %(levelname)s [%(otelServiceName)s]"
        "[trace_id=%(otelTraceID)s span_id=%(otelSpanID)s]"
        " %(name)s - %(message)s"
    ),
)
log = logging.getLogger("checkout")

app = FastAPI(title="Lab 02 demo service")

# A stand-in for a downstream dependency, so traces have more than one span.
PAYMENTS_URL = os.environ.get("PAYMENTS_URL", "http://localhost:8000/payments")

PRODUCTS = ["widget", "gadget", "doohickey", "thingamajig"]
REGIONS = ["us-east", "us-west", "eu-west", "ap-south"]


@app.get("/healthz")
def healthz():
    """★ Deliberately boring.

    This endpoint exists so you can see WHY you filter health checks out of
    telemetry. In a real cluster this is hit every few seconds per pod and can
    be 30-70% of all spans. Lab 03 and ../../14-scale-cost-and-cardinality.md
    drop it at the Collector; here we just generate it.
    """
    return {"status": "ok"}


@app.get("/products/{product_id}")
def get_product(product_id: str):
    """★ THE HIGH-CARDINALITY MISTAKE, ON PURPOSE.

    Two problems here, both extremely common in real code:

      1. The span name is built from a raw ID. Auto-instrumentation names the
         SERVER span after the route template (/products/{product_id}) which is
         bounded — but this manual span uses the literal ID, so every distinct
         product creates a new span NAME. Span name is a primary index in most
         trace backends: unbounded names = unbounded index = cost explosion.

      2. The metric below carries product_id AND region as attributes. That is
         the product of their cardinalities, per metric. See
         ../../14-scale-cost-and-cardinality.md for the arithmetic.

    Fix for (1): use the ROUTE TEMPLATE as the span name and put the ID in an
    attribute (attributes are cheap; names are indexed).
    Fix for (2): never put an unbounded identifier on a metric. Put it on the
    SPAN, where it costs bytes once instead of creating a permanent series.
    """
    with tracer.start_as_current_span("get-product") as span:
        # Correct: bounded span name, ID as an attribute.
        span.set_attribute("http.route", "/products/{product_id}")
        span.set_attribute("product.id", product_id)
        span.set_attribute("product.region", random.choice(REGIONS))

        if product_id not in PRODUCTS:
            # ★ Recording an exception AND setting ERROR status is what makes a
            #   trace findable by a status_code tail-sampling policy.
            span.set_status(StatusCode.ERROR, "unknown product")
            span.record_exception(HTTPException(status_code=404, detail="unknown product"))
            raise HTTPException(status_code=404, detail="unknown product")

        log.info("returning product %s", product_id)
        return {"id": product_id, "name": product_id.title(), "price_cents": 1999}


@app.post("/checkout")
def checkout():
    """★ THE MAIN EVENT — a manual span with a real child call.

    Demonstrates:
      - a business-level span name (checkout, not POST /checkout)
      - a nested child span for the downstream call
      - context propagation: `requests` is auto-instrumented, so the traceparent
        header is injected automatically. THIS is the thing that makes a
        distributed trace distributed. See ../../03-context-and-propagation.md
      - exception recording + ERROR status
      - a deliberate PII leak, so the Collector's redaction processor has
        something to catch
    """
    with tracer.start_as_current_span("checkout") as span:
        span.set_attribute("http.route", "/checkout")
        order_id = "ord-%d" % random.randint(100000, 999999)
        span.set_attribute("order.id", order_id)

        # ★ PII LEAK, DELIBERATE. Watch the Collector's `redaction` processor
        #   mask the email and the card number. Check
        #   `redaction.masked.count` on the span, and compare what arrives in
        #   Tempo against what was sent. See ../../15-security-and-governance.md
        span.set_attribute("customer.email", "someone@example.com")
        span.set_attribute("customer.card", "4111111111111111")
        span.set_attribute("customer.note", "contact billing@corp.internal for invoices")

        log.info("checkout started order=%s", order_id)

        # Child span around the downstream call.
        with tracer.start_as_current_span("reserve-inventory") as child:
            child.set_attribute("messaging.operation", "reserve")
            child.set_attribute("order.id", order_id)
            # Simulate latency so the histogram buckets in span_metrics are
            # actually populated across several buckets, not all in one.
            time.sleep(random.uniform(0.005, 0.120))

            # Every 5th checkout fails, so there is always an error to find
            # and so a status_code sampling policy has something to keep.
            if random.randint(1, 5) == 5:
                child.set_status(StatusCode.ERROR, "inventory unavailable")
                child.record_exception(RuntimeError("inventory unavailable"))
                log.error("checkout failed order=%s reason=inventory", order_id)
                raise HTTPException(status_code=503, detail="inventory unavailable")

        log.info("checkout succeeded order=%s", order_id)
        span.set_attribute("checkout.outcome", "success")
        return {"order_id": order_id, "status": "reserved"}


@app.get("/payments")
def payments():
    """Downstream endpoint, called by /checkout via PAYMENTS_URL in Docker.

    Auto-instrumented by FastAPIInstrumentor. Because `requests` propagates
    traceparent, this handler's span is a CHILD of reserve-inventory — that is
    what makes the trace span two services with zero manual wiring here.
    """
    time.sleep(random.uniform(0.002, 0.030))
    log.info("payment authorised")
    return {"authorised": True}


# ---------------------------------------------------------------------------
# NOTE ON SHUTDOWN — the most common SDK bug in production.
#
# With `opentelemetry-instrument` the launcher owns the TracerProvider and
# flushes it on exit, so this lab is safe. If you configure the SDK by hand in
# your own code you MUST call tracer_provider.shutdown() in a shutdown hook,
# otherwise every deploy silently drops the last batch of buffered telemetry —
# which looks like random data loss rather than a missing line of code.
# See ../../09-sdks-and-instrumentation.md and ../../16-troubleshooting.md
# ---------------------------------------------------------------------------
