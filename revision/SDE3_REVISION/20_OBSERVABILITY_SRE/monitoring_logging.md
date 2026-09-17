# Observability - Monitoring, Logging, Tracing - SDE3

## Observability vs Monitoring

- **Monitoring**: Collecting and alerting on known metrics (CPU, error rate) - you know what to look for
- **Observability**: Ability to understand system state from external outputs, debug unknown unknowns - you can ask arbitrary questions
- 3 Pillars: Metrics, Logs, Traces (+ Profiles, Events)

## 1. Metrics

### What are Metrics?
- Numbers measured over time: CPU, memory, QPS, latency, error rate

### Types

- **Counter**: Only increases (requests total, errors total) - resets on restart
- **Gauge**: Can go up/down (CPU, memory, queue size, active connections)
- **Histogram**: Samples observations and counts in buckets (latency distribution) - e.g. http_request_duration_seconds_bucket
- **Summary**: Similar to histogram but calculates quantiles on client side (P50, P95, P99)

### RED Method (For services)
- **Rate**: Requests per second
- **Errors**: Error rate (5xx)
- **Duration**: Latency (P50, P95, P99)

### USE Method (For resources)
- **Utilization**: % time busy (CPU 80%)
- **Saturation**: Queue length, waiting (load average)
- **Errors**: Error count

### Golden Signals (Google SRE)
- Latency, Traffic, Errors, Saturation

### Tools
- **Prometheus**: Pull model, scrapes /metrics endpoint, PromQL query, TSDB, alerting via Alertmanager
- **Grafana**: Visualization, dashboards, data sources Prometheus, Loki, Elasticsearch
- **Datadog, New Relic, CloudWatch**: SaaS

### Prometheus Example

```java
// Spring Boot Micrometer + Prometheus
// Add dependency: micrometer-registry-prometheus
// Expose /actuator/prometheus

// Custom metric
@Component
class OrderMetrics {
  private final Counter ordersTotal;
  private final Timer orderProcessingTimer;
  OrderMetrics(MeterRegistry registry) {
    ordersTotal = Counter.builder("orders_total").tag("status","success").register(registry);
    orderProcessingTimer = Timer.builder("order_processing_seconds").register(registry);
  }
  void increment() { ordersTotal.increment(); }
  void record(Runnable r) { orderProcessingTimer.record(r); }
}
```

PromQL:
```
rate(http_requests_total[5m]) // QPS last 5 min
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) // P95 latency
up == 0 // down instances
```

### Grafana Dashboard Must Have
- Service: QPS, error rate (5xx %), latency P50/P95/P99, CPU, memory, JVM heap, GC, thread count, DB connections
- Infrastructure: Node CPU, memory, disk, network
- Business: Orders per min, revenue, active users

## 2. Logging

### Best Practices

- **Structured Logging**: JSON not plain text, easy to parse/search
```json
{"timestamp":"2026-09-13T10:00:00Z","level":"ERROR","service":"order-service","traceId":"abc123","userId":"123","message":"Payment failed","error":"Timeout","stack":"..."}
```
- **Levels**: TRACE (very detailed), DEBUG (dev), INFO (normal flow), WARN (potential issue), ERROR (failure), FATAL (system crash)
- **What to log**: Timestamp, level, service, traceId, requestId, userId, action, duration, error with stack, but NOT sensitive data (password, PII, card)
- **Correlation ID**: Pass X-Request-ID / X-Correlation-ID across services via headers, log it everywhere to trace request flow

### Log Levels in Prod
- INFO and above in prod, DEBUG in dev or temporary for troubleshooting (dynamic log level via /actuator/loggers)

### Centralized Logging

- **ELK Stack**: Elasticsearch (store/search), Logstash (collect/parse) or Fluentd/Fluent Bit (lighter), Kibana (visualize)
- **EFK**: Elasticsearch, Fluentd, Kibana - more common in K8s
- **PLG**: Promtail, Loki, Grafana - cheaper, Loki like Prometheus for logs, labels not full text index
- **Cloud**: CloudWatch Logs, Stackdriver, Azure Monitor

### K8s Logging Architecture
```
App -> stdout/stderr -> Container runtime -> Fluent Bit DaemonSet (collects from /var/log/containers) -> Loki/Elasticsearch -> Grafana/Kibana
```

### Log Sampling & Retention
- High volume logs costly, sample DEBUG, keep ERROR 100%, retention 7-30 days hot, then S3 Glacier

## 3. Tracing (Distributed Tracing)

### Why?
- Microservices: One request goes through 10 services, which one is slow? Where error?
- Trace shows timeline across services

### Concepts
- **Trace**: Whole request journey (traceId same across all services for one request)
- **Span**: One unit of work in one service (e.g. DB query, API call), has spanId, parentSpanId, duration, tags
- **TraceId + SpanId**: Propagated via headers (W3C Trace Context: traceparent)

### Tools
- **OpenTelemetry**: CNCF standard, collects traces/metrics/logs, vendor neutral, replaces OpenTracing + OpenCensus
- **Jaeger**: Open source tracing, UI to view traces
- **Zipkin**: Similar to Jaeger
- **AWS X-Ray, Datadog APM, New Relic**: SaaS

### How to Implement (Spring Boot)

```java
// Add OpenTelemetry starter
// implementation 'io.micrometer:micrometer-tracing-bridge-otel'
// implementation 'io.opentelemetry:opentelemetry-exporter-otlp'

@RestController
class OrderController {
  @GetMapping("/orders/{id}")
  public Order getOrder(@PathVariable Long id) {
    // Trace automatically created for HTTP request
    // Custom span
    Span span = tracer.nextSpan().name("fetch-from-db").start();
    try (Tracer.SpanInScope ws = tracer.withSpan(span)) {
      span.tag("db.query", "findById");
      return orderRepo.findById(id);
    } finally { span.end(); }
  }
}
```

### Trace Example
```
TraceId: abc123
[Frontend 50ms]
  -> [API Gateway 45ms]
    -> [Order Service 40ms]
      -> [DB query 15ms]
      -> [Payment Service 20ms] (parallel)
        -> [Payment Gateway 18ms]
```

### Sampling
- Don't trace 100% (costly), sample 1% or 10% or adaptive (sample all errors, sample 1% success)

## 4. Profiling (4th Pillar - Continuous Profiling)

- Shows where CPU/memory spent in code (flame graphs)
- Tools: Pyroscope, Parca, Java Flight Recorder (JFR), async-profiler
- Use: Find hot methods, memory leak

## Alerting

### Prometheus Alertmanager Rules

```yaml
groups:
- name: example
  rules:
  - alert: HighErrorRate
    expr: rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m]) > 0.05
    for: 5m
    labels: {severity: critical}
    annotations: {summary: "High error rate {{ $value }}", description: "Service {{ $labels.service }} error rate >5% for 5m"}

  - alert: HighLatency
    expr: histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m])) > 0.5
    for: 5m
    labels: {severity: warning}
```

### Alert Best Practices
- No alert fatigue: Only alert actionable, not informational (info goes to dashboard)
- Runbook: Each alert has runbook link how to debug
- Severity: Critical (page), Warning (slack), Info (dashboard)
- SLO based alerting: Burn rate alerting (error budget burning too fast)

## Dashboard Example

**Service Dashboard**:
- Row 1: QPS, Error Rate %, P95 Latency, CPU, Memory
- Row 2: JVM Heap, GC pause, Thread count, DB connections active/idle
- Row 3: Business metrics: Orders/min, Payment success rate
- Row 4: Logs panel filtered by error, Traces slow >500ms

## Interview Q

**Q: How to debug high latency?**
- Check metrics: Which endpoint? P95 vs P99? CPU or IO bound? Check traces to find slow span (DB? External API?), check logs for errors, check DB slow query log, check GC logs for long pauses, check thread dump for blocked threads, check downstream service latency

**Q: How to set up observability for microservices on K8s?**
- Metrics: Prometheus + Grafana + Micrometer in app exposing /actuator/prometheus, ServiceMonitor CRD
- Logs: Fluent Bit DaemonSet -> Loki -> Grafana
- Traces: OpenTelemetry sidecar or agent -> Jaeger -> Grafana Tempo
- All via Helm charts, dashboards as code
